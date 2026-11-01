package com.beamjason.xiaorichang.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.location.LocationManager
import android.content.Context
import android.os.Build
import com.beamjason.xiaorichang.core.FrameDecoder
import com.beamjason.xiaorichang.core.WaterProtocol
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** One foreground BLE session. The caller must request SCAN and CONNECT permissions first. */
data class BleCandidate(val address:String,val name:String,val rssi:Int)
interface WaterTransport {
    suspend fun connect(deviceName:String,expectedAddress:String?):String
    suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?=null,onProbe:(String)->Unit = {}):VerifiedWaterTarget
    suspend fun scanCandidates(name:String):List<BleCandidate>
    suspend fun exchange(bytes:ByteArray):ByteArray
    fun disconnect()
}
class BleWaterTransport(private val context:Context):WaterTransport {
    private val support=BleSupport(context)
    private val adapter get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager)?.adapter ?: error("此设备不支持蓝牙")
    @Volatile private var generation=0L
    @Volatile private var gatt:BluetoothGatt?=null
    @Volatile private var writeCharacteristic:BluetoothGattCharacteristic?=null
    @Volatile private var readyAddress:String?=null
    @Volatile private var linkLost=false
    private var decoder=FrameDecoder()
    private var exchange:Exchange?=null
    private val serviceUuid=UUID.fromString("0000FFE0-0000-1000-8000-00805F9B34FB")
    private val notifyUuid=UUID.fromString("0000FFE1-0000-1000-8000-00805F9B34FB")
    private val writeUuid=UUID.fromString("0000FFE2-0000-1000-8000-00805F9B34FB")
    private val cccdUuid=UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")

    private data class Exchange(val ack:CompletableDeferred<Unit> = CompletableDeferred(),val frame:CompletableDeferred<ByteArray> = CompletableDeferred())

    // Lint cannot follow our SDK-dependent permission helper across GATT callbacks.
    // Entry and callbacks check permissions; synchronous revocations propagate or
    // complete the pending request exceptionally instead of escaping a callback.
    @SuppressLint("MissingPermission")
    override suspend fun connect(deviceName:String,expectedAddress:String?):String {
        support.event("connect-start")
        permissions(scan=expectedAddress==null)
        check(adapter.isEnabled) { "请先打开蓝牙" }
        synchronized(this) {
            if(expectedAddress!=null && readyAddress==expectedAddress && gatt!=null && !linkLost) {
                support.event("reuse-connection")
                return expectedAddress
            }
            if(gatt!=null && linkLost)disconnect()
            check(gatt==null) { "GATT already open" }
        }
        // A saved address is used only after physical identity verification. Every start
        // still reads and compares the 4-byte machine ID before requesting authorization.
        val chosen=if(expectedAddress!=null) {
            require(BluetoothAdapter.checkBluetoothAddress(expectedAddress)); adapter.getRemoteDevice(expectedAddress)
        } else {
            val candidates=scanCandidates(deviceName)
            when(candidates.size) {
                0 -> error("未发现目标水控，请靠近设备")
                1 -> adapter.getRemoteDevice(candidates.single().address)
                else -> error("发现多个同名水控，请在设备页选择并核对")
            }
        }
        val token=synchronized(this) { check(gatt==null) { "GATT already open" }; ++generation }
        val ready=CompletableDeferred<Unit>()
        val callback=object:BluetoothGattCallback() {
            override fun onConnectionStateChange(g:BluetoothGatt,status:Int,newState:Int) = synchronized(this@BleWaterTransport) {
                if(token!=generation) return@synchronized
                support.event("connection-state",mapOf("status" to status,"state" to newState))
                if(status!=BluetoothGatt.GATT_SUCCESS || newState==BluetoothProfile.STATE_DISCONNECTED) {
                    linkLost=true;readyAddress=null
                    ready.completeExceptionally(IllegalStateException("BLE 连接中断")); exchange?.let { e -> e.ack.completeExceptionally(IllegalStateException("BLE 连接中断")); e.frame.completeExceptionally(IllegalStateException("BLE 连接中断")) }
                    return@synchronized
                }
                if(newState==BluetoothProfile.STATE_CONNECTED) try { permissions();check(g.discoverServices()) { "无法读取水控服务" } }
                    catch(e:Exception) {ready.completeExceptionally(e)}
            }
            override fun onServicesDiscovered(g:BluetoothGatt,status:Int) = synchronized(this@BleWaterTransport) {
                if(token!=generation) return@synchronized
                support.event("services",mapOf("status" to status))
                try {
                permissions()
                if(status!=BluetoothGatt.GATT_SUCCESS) { ready.completeExceptionally(IllegalStateException("水控服务发现失败")); return@synchronized }
                val svc=g.getService(serviceUuid); val notify=svc?.getCharacteristic(notifyUuid); val write=svc?.getCharacteristic(writeUuid)
                if(notify==null || write==null || notify.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY==0 || write.properties and BluetoothGattCharacteristic.PROPERTY_WRITE==0) {
                    ready.completeExceptionally(IllegalStateException("水控 BLE 服务不匹配")); return
                }
                writeCharacteristic=write
                if(!g.setCharacteristicNotification(notify,true)) { ready.completeExceptionally(IllegalStateException("开启水控通知失败")); return@synchronized }
                val descriptor=notify.getDescriptor(cccdUuid)
                if(descriptor==null) { ready.completeExceptionally(IllegalStateException("水控通知描述符缺失")); return@synchronized }
                val value=BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                val initiated=if(Build.VERSION.SDK_INT>=33) g.writeDescriptor(descriptor,value)==BluetoothStatusCodes.SUCCESS else {
                    @Suppress("DEPRECATION")
                    descriptor.value=value
                    @Suppress("DEPRECATION")
                    g.writeDescriptor(descriptor)
                }
                if(!initiated) ready.completeExceptionally(IllegalStateException("开启水控通知失败"))
                } catch(e:Exception) {ready.completeExceptionally(e)}
            }
            override fun onDescriptorWrite(g:BluetoothGatt,d:BluetoothGattDescriptor,status:Int) = synchronized(this@BleWaterTransport) {
                if(token!=generation) return@synchronized
                support.event("notifications",mapOf("status" to status))
                if(d.uuid==cccdUuid) if(status==BluetoothGatt.GATT_SUCCESS) ready.complete(Unit) else ready.completeExceptionally(IllegalStateException("订阅水控通知失败"))
            }
            override fun onCharacteristicWrite(g:BluetoothGatt,c:BluetoothGattCharacteristic,status:Int) = synchronized(this@BleWaterTransport) {
                if(token!=generation) return@synchronized
                if(c.uuid==writeUuid) exchange?.let { if(status==BluetoothGatt.GATT_SUCCESS) it.ack.complete(Unit) else it.ack.completeExceptionally(IllegalStateException("水控写入未确认")) }
            }
            override fun onCharacteristicChanged(g:BluetoothGatt,c:BluetoothGattCharacteristic) = synchronized(this@BleWaterTransport) {
                if(token!=generation) return@synchronized
                @Suppress("DEPRECATION")
                if(c.uuid==notifyUuid) onNotification(c.value ?: return@synchronized)
            }
            override fun onCharacteristicChanged(g:BluetoothGatt,c:BluetoothGattCharacteristic,value:ByteArray) = synchronized(this@BleWaterTransport) {
                if(token!=generation) return@synchronized
                if(c.uuid==notifyUuid) onNotification(value)
            }
        }
        synchronized(this) {
            check(token==generation) { "BLE 连接已取消" }
            gatt=chosen.connectGatt(context,false,callback,BluetoothDevice.TRANSPORT_LE)
        }
        return try {
            withTimeout(20_000) { ready.await() }
            synchronized(this){check(token==generation && !linkLost){"BLE 连接中断"};readyAddress=chosen.address}
            support.event("gatt-ready");chosen.address
        } catch(t:Throwable) { support.event("connect-failed");disconnect();throw t }
    }

    /** Returns with the verified GATT connection open. Sends only the 0xAA identity query. */
    override suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?,onProbe:(String)->Unit):VerifiedWaterTarget =
        resolveWaterIdentity(machineId,preferredAddress,
            scan={scanCandidates(deviceName).map{it.address}},
            probe={address->connect(deviceName,address);exchange(byteArrayOf(0xAA.toByte()))},
            disconnect=::disconnect,onProbe=onProbe)

    @SuppressLint("MissingPermission")
    override suspend fun exchange(bytes:ByteArray):ByteArray {
        permissions()
        val current=Exchange()
        val (g,c)=synchronized(this) {
            val g=gatt ?: error("BLE 未连接"); val c=writeCharacteristic ?: error("水控写特征值缺失")
            check(exchange==null && !decoder.hasPartialFrame) { "上一次 BLE 帧尚未结束" }
            exchange=current
            Pair(g,c)
        }
        try {
            val initiated=if(Build.VERSION.SDK_INT>=33) g.writeCharacteristic(c,bytes,BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)==BluetoothStatusCodes.SUCCESS else {
                @Suppress("DEPRECATION")
                c.writeType=BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                @Suppress("DEPRECATION")
                c.value=bytes
                @Suppress("DEPRECATION") g.writeCharacteristic(c)
            }
            check(initiated) { "水控写入未开始" }
            val command=when {bytes.contentEquals(byteArrayOf(0xAA.toByte()))->1;bytes.size==15->2;bytes.size==5 && bytes[0]==0xAC.toByte()->3;else->0}
            support.event("write",mapOf("command" to command))
            val pair=withTimeout(10_000) { current.ack.await(); current.frame.await() }
            return pair
        } finally { synchronized(this) { if(exchange===current) exchange=null } }
    }

    private fun onNotification(bytes:ByteArray) {
        try {
            val frames=decoder.append(bytes)
            require(frames.size<=1) { "收到多帧水控通知" }
            frames.forEach{support.event("reply",mapOf("bytes" to it.size,"frameKind" to WaterDiagnostics.frameKind(it)))}
            if(frames.isNotEmpty()) exchange?.frame?.complete(frames.first())
        } catch(t:Throwable) { exchange?.frame?.completeExceptionally(t) }
    }

    @SuppressLint("MissingPermission")
    override suspend fun scanCandidates(name:String):List<BleCandidate> = withContext(Dispatchers.Main) {
        permissions(scan=true)
        check(adapter.isEnabled) { "请先打开蓝牙" }
        if(Build.VERSION.SDK_INT<31) {
            val lm=context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            check(lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) { "此系统扫描蓝牙需要开启手机定位服务" }
        }
        val scanner=adapter.bluetoothLeScanner ?: error("BLE 扫描器不可用")
        val found=ConcurrentHashMap<String,BleCandidate>()
        var received=0
        val done=CompletableDeferred<Unit>()
        val cb=object:ScanCallback() {
            private fun collect(result:ScanResult) {
                received++
                val cached=runCatching { result.device.name }.getOrNull()
                if(matchesWaterAdvertisement(name,cached,result.scanRecord?.deviceName))
                    found[result.device.address]=BleCandidate(result.device.address,name,result.rssi)
            }
            override fun onScanResult(type:Int,result:ScanResult)=collect(result)
            override fun onBatchScanResults(results:MutableList<ScanResult>)=results.forEach(::collect)
            override fun onScanFailed(errorCode:Int) {support.event("scan-error",mapOf("code" to errorCode));done.completeExceptionally(IllegalStateException("BLE 扫描失败 ($errorCode)"))}
        }
        support.event("scan-start")
        scanner.startScan(null,ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),cb)
        try {withTimeoutOrNull(6_000){done.await()};found.values.sortedByDescending{it.rssi}}
        finally {runCatching{scanner.stopScan(cb)};support.event("scan-end",mapOf("packets" to received,"matches" to found.size))}
    }

    @Synchronized override fun disconnect() {
        support.event("disconnect")
        generation++
        val g=gatt; gatt=null; writeCharacteristic=null;readyAddress=null;linkLost=false
        exchange?.let { val error=IllegalStateException("BLE disconnected"); it.ack.completeExceptionally(error); it.frame.completeExceptionally(error) }
        exchange=null
        try {g?.disconnect()} catch(_:SecurityException) { /* Revoked while connected. */ }
        try {g?.close()} catch(_:SecurityException) { /* Native client is released where permitted. */ }
        decoder=FrameDecoder()
    }
    private fun permissions(scan:Boolean=false) {
        val needed=if(Build.VERSION.SDK_INT>=31) listOfNotNull(Manifest.permission.BLUETOOTH_CONNECT,if(scan) Manifest.permission.BLUETOOTH_SCAN else null)
            else if(scan) listOf(Manifest.permission.ACCESS_FINE_LOCATION) else emptyList()
        check(needed.all {ContextCompat.checkSelfPermission(context,it)==PackageManager.PERMISSION_GRANTED}) {
            if(Build.VERSION.SDK_INT>=31) "蓝牙权限已关闭，请重新允许附近设备权限" else "此安卓版本需要定位权限来查找蓝牙水控"
        }
    }
}
