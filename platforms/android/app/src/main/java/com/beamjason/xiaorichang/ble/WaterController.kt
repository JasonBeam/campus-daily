package com.beamjason.xiaorichang.ble

import android.content.Context
import com.beamjason.xiaorichang.core.WaterProfile
import com.beamjason.xiaorichang.core.WaterProtocol
import com.beamjason.xiaorichang.net.WaterProvider
import com.beamjason.xiaorichang.net.WaterService
import com.beamjason.xiaorichang.net.WaterReceipt
import com.beamjason.xiaorichang.security.SecureStore
import org.json.JSONObject
import android.util.Base64
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class ShowerStage { AUTHORIZATION_PENDING, AUTHORIZATION_ISSUED, AUTHORIZATION_WRITE_PENDING, ACTIVE,
    CLOSE_WRITE_PENDING, SETTLEMENT_PENDING, SETTLED }
data class ShowerSession(val stage:ShowerStage,val machineId:String,val peripheralAddress:String,
                         val authorizationId:String?=null,val consumption:String?=null,val payFen:Long?=null,val endedAt:Long?=null)

internal interface WaterSessionPersistence {
    fun load():ShowerSession?
    fun save(session:ShowerSession)
}
private class ShowerSessionStore(context:Context):WaterSessionPersistence {
    private val storage=SecureStore(context)
    override fun load():ShowerSession? {
        val bytes=storage.get("water.session") ?: return null
        val j=JSONObject(bytes.toString(Charsets.UTF_8))
        return ShowerSession(ShowerStage.valueOf(j.getString("stage")),j.getString("machineId"),j.getString("peripheralAddress"),
            j.optString("authorizationId").takeUnless{it.isBlank() || it=="null"},j.optString("consumption").takeUnless{it.isBlank() || it=="null"},j.opt("payFen").let{(it as? Number)?.toLong()},(j.opt("endedAt") as? Number)?.toLong())
    }
    override fun save(session:ShowerSession) {
        val s=session
        storage.put("water.session",JSONObject().put("stage",s.stage.name).put("machineId",s.machineId)
            .put("peripheralAddress",s.peripheralAddress).put("authorizationId",s.authorizationId)
            .put("consumption",s.consumption).put("payFen",s.payFen).put("endedAt",s.endedAt).toString().toByteArray())
    }
}

/** No retry paths: uncertain remote or BLE results remain persisted and block a second start. */
class WaterController internal constructor(private val transport:WaterTransport,private val provider:WaterService,private val store:WaterSessionPersistence) {
    constructor(context:Context,transport:WaterTransport,provider:WaterProvider=WaterProvider()):this(transport,provider,ShowerSessionStore(context.applicationContext))
    private val mutex=Mutex()
    @Volatile var session:ShowerSession?=runCatching{store.load()}.getOrNull(); private set
    @Volatile var blocked:Boolean=runCatching{store.load()}.isFailure; private set

    private fun persist(s:ShowerSession) { session=s; try { store.save(s) } catch(t:Throwable) { blocked=true; throw IllegalStateException("操作记录无法安全保存，已阻止后续操作",t) } }

    suspend fun start(profile:WaterProfile,verifiedAddress:String?=null) = mutex.withLock {
        check(!blocked) { "操作记录不可读取，请勿重复开水" }
        check(session==null || session?.stage==ShowerStage.SETTLED) { "已有未确认会话，请先核对水控和校园记录" }
        profile.validate()
        try {
            val remembered=verifiedAddress ?: session?.takeIf { it.stage==ShowerStage.SETTLED && it.machineId.equals(profile.machineId,true) }?.peripheralAddress
            val target=transport.connectVerified(profile.bleName,profile.machineId,remembered)
            val machine=WaterProtocol.identity(target.identityFrame)
            check(machine==profile.machineId.uppercase()) { "水控编号不匹配，已停止" }
            currentCoroutineContext().ensureActive()
            var current=ShowerSession(ShowerStage.AUTHORIZATION_PENDING,machine,target.address); persist(current)
            val auth=provider.authorize(profile,target.identityFrame)
            check(auth.machineId.equals(machine,true)) { "服务器授权的设备编号不匹配" }
            check(auth.payload.size==15); WaterProtocol.closeCommand(auth.authorizationId)
            current=current.copy(stage=ShowerStage.AUTHORIZATION_ISSUED,authorizationId=auth.authorizationId); persist(current)
            current=current.copy(stage=ShowerStage.AUTHORIZATION_WRITE_PENDING); persist(current)
            val ack=transport.exchange(auth.payload)
            check(ack.size==9 && ack[0]==0xAA.toByte()) { "水控未确认授权写入" }
            persist(current.copy(stage=ShowerStage.ACTIVE))
        } finally { transport.disconnect() }
    }

    suspend fun finish(profile:WaterProfile):WaterReceipt = mutex.withLock {
        check(!blocked) { "操作记录不可读取，请勿重复结算" }
        val old=session ?: error("没有本 App 的待结算记录")
        check(old.stage==ShowerStage.ACTIVE || old.stage==ShowerStage.AUTHORIZATION_WRITE_PENDING) { "当前会话状态不允许结束，请先核对校园记录" }
        profile.validate(); check(old.machineId==profile.machineId.uppercase()) { "水控配置与本次会话不匹配" }
        val id=old.authorizationId ?: error("没有本次授权标识")
        val command=WaterProtocol.closeCommand(id)
        try {
            transport.connect(profile.bleName,old.peripheralAddress)
            val state=transport.exchange(byteArrayOf(0xAA.toByte()))
            check(state.contentEquals(byteArrayOf(0xA5.toByte()))) { "水控未返回使用中状态，未发送结束指令" }
            var current=old.copy(stage=ShowerStage.CLOSE_WRITE_PENDING); persist(current)
            val consumed=transport.exchange(command)
            check(WaterProtocol.identity(consumed)==old.machineId) { "结束数据中的水控编号不匹配" }
            current=current.copy(stage=ShowerStage.SETTLEMENT_PENDING,consumption=Base64.encodeToString(consumed,Base64.NO_WRAP)); persist(current)
            val receipt=provider.settle(profile,consumed)
            current=current.copy(stage=ShowerStage.SETTLED,payFen=receipt.payFen,endedAt=System.currentTimeMillis()); persist(current)
            return@withLock receipt
        } finally { transport.disconnect() }
    }
}
