package com.beamjason.xiaorichang.ble

import com.beamjason.xiaorichang.core.WaterProtocol
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeoutOrNull

/** Read the hardware identity before any authorization. A remembered address is
 * only a hint, and a failed or mismatched one is followed by a fresh scan. */
data class VerifiedWaterTarget(val address:String,val identityFrame:ByteArray)

internal suspend fun resolveWaterIdentity(
    machineId:String,
    preferredAddress:String?,
    scan:suspend ()->List<String>,
    probe:suspend (String)->ByteArray,
    disconnect:()->Unit,
    onProbe:(String)->Unit = {}
):VerifiedWaterTarget {
    val tried=mutableSetOf<String>()
    var wrongIdentity=false
    suspend fun attempt(address:String):VerifiedWaterTarget? {
        if(!tried.add(address))return null
        currentCoroutineContext().ensureActive()
        onProbe(address)
        var keepConnected=false
        try {
            val frame=withTimeoutOrNull(12_000){probe(address)} ?: return null
            val actual=WaterProtocol.identity(frame)
            if(!actual.equals(machineId,true)) {wrongIdentity=true;return null}
            currentCoroutineContext().ensureActive()
            keepConnected=true
            return VerifiedWaterTarget(address,frame)
        } catch(e:CancellationException) {throw e}
          catch(_:Exception) {return null}
        finally {if(!keepConnected)disconnect()}
    }
    preferredAddress?.takeIf{it.isNotBlank()}?.let{attempt(it)?.let{return it}}
    val candidates=scan().distinct()
    if(candidates.isEmpty())error("未发现水控，请靠近设备并确认蓝牙已开启")
    for(address in candidates.take(16))attempt(address)?.let{return it}
    currentCoroutineContext().ensureActive()
    if(candidates.size>16)error("附近同名设备较多，请更靠近自己的水控后重试")
    if(wrongIdentity)error("附近水控与宿舍编号不匹配，请核对宿舍并靠近设备")
    error("暂时无法读取水控编号，请靠近设备后重试")
}
