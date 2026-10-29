package com.beamjason.xiaorichang.net

import com.beamjason.xiaorichang.core.WaterProfile
import com.beamjason.xiaorichang.core.WaterProtocol
import org.json.JSONObject
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class WaterAuthorization(val machineId:String,val payload:ByteArray,val authorizationId:String)
data class WaterReceipt(val payFen:Long?) {
    val yuan:String? get() = payFen?.let { "%.2f".format(java.util.Locale.ROOT,it / 100.0) }
    companion object {
        fun parse(body:JSONObject):WaterReceipt {
            val raw=body.opt("pay")
            val text=when(raw) { is Number -> raw.toString(); is String -> raw; else -> null }
            val value=text?.takeIf { it.matches(Regex("[0-9]+")) }?.toLongOrNull()
            return WaterReceipt(value?.takeIf { it in 0..100_000_000_000 })
        }
    }
}

interface WaterService {
    suspend fun authorize(profile:WaterProfile,frame:ByteArray):WaterAuthorization
    suspend fun settle(profile:WaterProfile,frame:ByteArray):WaterReceipt
}
class WaterProvider:WaterService {
    override suspend fun authorize(profile:WaterProfile,frame:ByteArray):WaterAuthorization = withContext(Dispatchers.IO) {
        profile.access?.let{a->
            profile.validate();require(WaterProtocol.identity(frame)==profile.machineId.uppercase())
            val r=WaterAccessClient.call("authorize",a,JSONObject().put("frame",frame.joinToString(""){"%02X".format(it.toInt() and 255)}).put("operationID",java.util.UUID.randomUUID().toString()))
            val payload=WaterProtocol.decodeHex(r.getString("payload")) ?: error("水控授权数据格式异常")
            require(payload.size==15)
            return@withContext WaterAuthorization(r.getString("machineID"),payload,r.getString("studentID"))
        }
        val data=request(profile,"/ZK_BSRS/GDBusinessSchool/bathingConsumptionAuthorization",frame)
        val machine=data.optString("machineid"); val id=data.optString("studentId")
        val payload=WaterProtocol.decodeHex(data.optString("systemData")) ?: error("水控授权数据格式异常")
        require(payload.size==15 && id.isNotBlank())
        WaterAuthorization(machine,payload,id)
    }
    override suspend fun settle(profile:WaterProfile,frame:ByteArray):WaterReceipt = withContext(Dispatchers.IO) {
        profile.access?.let{a->
            profile.validate();require(WaterProtocol.identity(frame)==profile.machineId.uppercase())
            val r=WaterAccessClient.call("settle",a,JSONObject().put("frame",frame.joinToString(""){"%02X".format(it.toInt() and 255)}))
            require(r.optBoolean("settled"));return@withContext WaterReceipt.parse(JSONObject().put("pay",r.opt("payFen")))
        }
        val data=request(profile,"/ZK_BSRS/GDBusinessSchool/analysisOfBathingConsumptionData",frame)
        WaterReceipt.parse(data)
    }
    private fun request(profile:WaterProfile,path:String,frame:ByteArray):JSONObject {
        require(path=="/ZK_BSRS/GDBusinessSchool/bathingConsumptionAuthorization" || path=="/ZK_BSRS/GDBusinessSchool/analysisOfBathingConsumptionData")
        val wxcode=WaterProtocol.wxcode(profile,frame,com.beamjason.xiaorichang.core.secureRandomWaterSuffix())
        val form="wxcode=${WaterProtocol.encodeForm(wxcode)}&sign=${WaterProtocol.signature(profile.secret,wxcode)}&sid=${WaterProtocol.encodeForm(profile.sid)}"
        val conn=(URL("https://isv.lxt6.cn$path").openConnection() as HttpsURLConnection).apply {
            instanceFollowRedirects=false; requestMethod="POST"; connectTimeout=15000; readTimeout=20000
            setRequestProperty("Content-Type","application/x-www-form-urlencoded"); doOutput=true
        }
        return try {
            conn.outputStream.use { it.write(form.toByteArray(Charsets.UTF_8)) }
            require(conn.responseCode==200) { "热水服务暂时无法连接" }
            val bytes=conn.inputStream.use { it.readBytesBounded(65536) }
            val root=JSONObject(bytes.toString(Charsets.UTF_8))
            require(root.optInt("code",-1)==0) { "热水服务未确认成功，请核对校园记录" }
            root.optJSONObject("data") ?: error("热水服务器返回无效")
        } finally { conn.disconnect() }
    }
}

private fun java.io.InputStream.readBytesBounded(limit:Int):ByteArray {
    val out=java.io.ByteArrayOutputStream(); val buf=ByteArray(4096)
    while(true) { val n=read(buf); if(n<0) break; require(out.size()+n<=limit); out.write(buf,0,n) }
    return out.toByteArray()
}
