package com.beamjason.xiaorichang.net

import com.beamjason.xiaorichang.core.WaterProtocol
import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

data class CampusConfig(val syscustid:String = "", val token:String = "", val areaCode:String = "", val custid:String = "",
                        val timestamp:String = "", val userAgent:String = "", val dorm:String = "",
                        val buildingId:String = "", val meterId:String = "", val campusVersion:String = "v1.1.55",val portalDormAddress:String="") {
    val configured get() = listOf(syscustid,token,areaCode).all { it.isNotBlank() }
    val owner get() = java.security.MessageDigest.getInstance("SHA-256").digest("$syscustid|$areaCode".toByteArray()).joinToString("") { "%02x".format(it) }
    val cardOwner get() = java.security.MessageDigest.getInstance("SHA-256").digest("$syscustid|$areaCode|$custid".toByteArray()).joinToString("") { "%02x".format(it) }
    fun sameCardSession(other:CampusConfig) = syscustid==other.syscustid && areaCode==other.areaCode && custid==other.custid && token==other.token
    // A meter selection is independent from the in-flight hot-water setup.
    fun sameDormSession(other:CampusConfig) = sameCardSession(other) && timestamp==other.timestamp && userAgent==other.userAgent &&
        campusVersion==other.campusVersion && portalDormAddress==other.portalDormAddress && dorm==other.dorm
}
data class Option(val id:String,val name:String)
data class DormWater(val machineId:String,val name:String,val bleName:String)
data class HotWaterProfile(val secret:String,val sid:String,val bleName:String,val typeId:Int,val version:Int,val access:WaterAccessSession?=null)
data class DormIdentity(val studentId:String,val schoolId:String)
data class PowerMeter(val id:String,val room:String,val remaining:String,val balance:String,val yesterday:String?,val meterAt:String) {
    fun json() = JSONObject().put("id",id).put("room",room).put("remaining",remaining).put("balance",balance).put("yesterday",yesterday).put("meterAt",meterAt)
    companion object {
        fun read(j:JSONObject) = PowerMeter(j.getString("id"),j.getString("room"),j.getString("remaining"),j.getString("balance"),
            j.optString("yesterday").takeUnless { it.isNullOrBlank() || it=="null" },j.optString("meterAt"))
    }
}
data class CampusWebSession(val state:JSONObject,val cardId:String,val ownerId:String,val userAgent:String) {
    fun url(power:Boolean) = if(power) "https://ecykt.gdbtu.edu.cn/ykt-mini/api/electricnew/getPowerUrl?custid=${WaterProtocol.encodeForm(cardId)}&syscustid=${WaterProtocol.encodeForm(ownerId)}"
        else "https://ecykt.gdbtu.edu.cn/ykt-view/recharge?isbind=1"
}

open class CampusClient(private val schoolReader:(suspend (String,JSONObject)->Any)?=null) {
    suspend fun webSession(c:CampusConfig):CampusWebSession = withContext(Dispatchers.IO) {
        val login=call("/ykt-mini/api/customer/loginBySysId",c,JSONObject().put("areacode",c.areaCode)
            .put("version",c.campusVersion).put("appid","wx7077a0b57d156efe").put("redirect","/recharge?isbind=1")) as? JSONObject ?: error("学校身份格式异常")
        require(login.optString("isbind")=="1" && login.optString("syscustid").isNotBlank()) { "请先在学校官方页面绑定校园卡" }
        val cards=call("/ykt-mini/api/customer/getSysBindCustInfo",c,JSONObject().put("areacode",c.areaCode)
            .put("version",c.campusVersion).put("appid","wx7077a0b57d156efe")) as? JSONArray ?: error("校园卡列表格式异常")
        val list=(0 until cards.length()).map { cards.getJSONObject(it) }
        val card=list.singleOrNull { it.optString("custid")==c.custid } ?: list.singleOrNull() ?: error("请在学校页面确认要使用的校园卡")
        val owner=login.getString("syscustid"); val id=card.optString("custid")
        require(id.isNotBlank() && (!card.has("syscustid") || card.optString("syscustid")==owner)) { "校园卡账号不匹配，请重新登录" }
        if(!login.has("timestamp") && c.timestamp.isNotBlank()) login.put("timestamp",c.timestamp)
        CampusWebSession(JSONObject().put("logintoken",c.token).put("loginInfo",login).put("schoolid",c.areaCode).put("custInfo",card).put("custid",id),id,owner,c.userAgent)
    }

    suspend fun powerBuildings(c:CampusConfig,parent:String?=null):List<Option> = withContext(Dispatchers.IO) {
        val payload=JSONObject().put("server","/api/getBuildingInfo").put("areacode",c.areaCode)
        if(parent!=null) payload.put("buildingID",parent)
        val rows=call("/ykt-mini/api/electricnew/service",c,payload,true) as? JSONArray ?: error("电表位置列表格式异常")
        require(rows.length()<=10000)
        (0 until rows.length()).map { rows.getJSONObject(it).let { row -> Option(row.getString("buildingID"),row.getString("buildingName")) } }
            .also { list -> require(list.all { it.id.isNotBlank() && it.name.isNotBlank() } && list.map { it.id }.distinct().size==list.size) }
    }
    suspend fun powerMeters(c:CampusConfig,building:String):List<PowerMeter> = withContext(Dispatchers.IO) {
        require(building.isNotBlank())
        val rows=call("/ykt-mini/api/electricnew/service",c,JSONObject().put("server","/api/getMeterStatus").put("areacode",c.areaCode).put("buildingID",building),true) as? JSONArray ?: error("电表列表格式异常")
        require(rows.length()<=100)
        (0 until rows.length()).map { rows.getJSONObject(it).let { row -> PowerMeter(row.getString("comAddress"),row.getString("piplineName"),
            amount(row.opt("remaining")),amount(row.opt("leftMoney")),runCatching { amount(row.opt("preUseDay")) }.getOrNull(),row.optString("updateDateTime").take(80)) } }
            .also { list -> require(list.map { it.id }.distinct().size==list.size) }
    }
    suspend fun electricity(c:CampusConfig):PowerMeter {
        val list=powerMeters(c,c.buildingId)
        return if(c.meterId.isNotBlank()) list.singleOrNull { it.id==c.meterId } ?: error("绑定电表已变化，请重新选择")
        else list.singleOrNull() ?: error("请先选择自己的宿舍电表")
    }
    suspend fun balance(c: CampusConfig): String = withContext(Dispatchers.IO) {
        validate(c)
        var balanceId = c.syscustid
        val login=try { call("/ykt-mini/api/customer/loginBySysId", c, JSONObject()
            .put("areacode", c.areaCode).put("version", c.campusVersion)
            .put("appid", "wx7077a0b57d156efe").put("redirect", "/recharge?isbind=1")) as? JSONObject
        } catch(e:CancellationException){throw e}catch(_:Exception){null}
        currentCoroutineContext().ensureActive()
        login?.optString("syscustid")?.takeIf {it.isNotBlank()}?.let {balanceId=it}
        var cardId = c.custid
        if (cardId.isBlank()) {
            val cards = call("/ykt-mini/api/customer/getSysBindCustInfo", c,
                JSONObject().put("areacode", c.areaCode).put("version", c.campusVersion).put("appid", "wx7077a0b57d156efe")) as? JSONArray
                ?: error("校园卡列表格式异常")
            require(cards.length() == 1) { "绑定校园卡不唯一，请先在学校官方页面核对" }
            cardId = cards.getJSONObject(0).optString("custid")
        }
        val data = call("/ykt-mini/scanpay/getUserBalance", c,
            JSONObject().put("syscustid",balanceId).put("custid",cardId))
        val amount = if (data is JSONObject) data.opt("balance") else data
        val text = when(amount) { is Number -> amount.toString(); is String -> amount.trim(); else -> error("校园卡余额格式异常") }
        require(text.matches(Regex("[+-]?[0-9]+(\\.[0-9]+)?")))
        text
    }

    open suspend fun readDormIdentity(c: CampusConfig, profile: HotWaterProfile): DormIdentity = withContext(Dispatchers.IO) {
        profile.access?.let{it.validate();require(it.campusOwner==c.waterAccessOwner());return@withContext DormIdentity(it.studentId,it.schoolId)}
        validate(c); validate(profile)
        val body = JSONObject().put("syscustid",c.syscustid).put("custid",c.custid)
            .put("acc_token",c.token).put("timestamp",c.timestamp)
        val app = call("/ykt-mini/api/customer/getSignData",c,body) as? JSONObject ?: error("学校身份交接格式异常")
        val own = app.opt("appdata").let { if (it is String) JSONObject(it) else it as? JSONObject }
            ?: error("学校身份数据为空")
        val fields = linkedMapOf("schoolid" to "20021")
        listOf("vsuppid","appid","userId","deptId","username","phone").forEach { k ->
            val value=own.optString(k); require(value.isNotBlank() && value.length <= 2048); fields[k]=value
        }
        fields["random"] = (1..6).map { "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".random() }.joinToString("")
        val data = signed("/AECC/GDBusinessSchool/getUserMsg",fields,profile,requestType=true).optJSONObject("Data")
            ?: error("热水平台未返回本人信息")
        val student=data.optString("studentid"); val school=data.opt("schoolid")?.toString().orEmpty()
        require(student.isNotBlank() && school.isNotBlank()); DormIdentity(student,school)
    }

    open suspend fun dormOptions(parent:String, rooms:Boolean, profile:HotWaterProfile):List<Option> = withContext(Dispatchers.IO) {
        profile.access?.let{a->
            val rows=WaterAccessClient.call("options",a,JSONObject().put("parent",parent)).getJSONArray("options");require(rows.length()<=1000)
            return@withContext (0 until rows.length()).map{val r=rows.getJSONObject(it);Option(r.getString("id"),r.getString("name")).also{o->require(o.id.length<=1024 && o.name.length<=128)}}
        }
        validate(profile)
        val path=if(rooms) "/zk_areainfo_api/areaInfo/getAreaForRoomApplests" else "/zk_areainfo_api/areaInfo/getAreaInfoForApplests"
        val list=signed(path,linkedMapOf("id" to parent),profile).optJSONArray("data") ?: error("宿舍列表为空")
        require(list.length() <= 1000)
        val out=(0 until list.length()).map { i ->
            val row=list.getJSONObject(i); Option(row.opt("id")?.toString().orEmpty(),row.optString("name")).also {
                require(it.id.isNotBlank() && it.name.isNotBlank() && it.name.length <= 128)
            }
        }
        require(out.map{it.id}.toSet().size==out.size); out
    }

    open suspend fun waterMachines(room:String,school:String,profile:HotWaterProfile):List<DormWater> = withContext(Dispatchers.IO) {
        profile.access?.let{a->
            require(a.schoolId==school)
            val rows=WaterAccessClient.call("machines",a,JSONObject().put("room",room)).getJSONArray("machines");require(rows.length()<=100)
            return@withContext (0 until rows.length()).map{val r=rows.getJSONObject(it);val id=r.getString("id");require(WaterProtocol.decodeHex(id)?.size==4);DormWater(id,r.getString("name"),r.getString("mac"))}
        }
        val data=signed("/ZK_BSRS/bathe/getMachineMacAddress",linkedMapOf("typeId" to profile.typeId.toString(),"schoolId" to school,"roomId" to room),profile)
            .optJSONObject("data")?.optJSONArray("objList") ?: error("寝室水控列表为空")
        require(data.length() <= 100)
        (0 until data.length()).map { i ->
            val row=data.getJSONObject(i); val id=row.optString("machineId"); val name=row.optString("machineName"); val ble=row.optString("Mac")
            require(WaterProtocol.decodeHex(id)?.size == 4 && name.isNotBlank() && ble.isNotBlank())
            DormWater(id.uppercase(),name,ble)
        }
    }

    private suspend fun call(path:String,c:CampusConfig,payload:JSONObject,power:Boolean=false):Any {
        currentCoroutineContext().ensureActive()
        validate(c)
        val allowed=setOf("/ykt-mini/api/customer/getSignData","/ykt-mini/api/customer/loginBySysId",
            "/ykt-mini/api/customer/getSysBindCustInfo","/ykt-mini/scanpay/getUserBalance","/ykt-mini/api/electricnew/service")
        require(path in allowed)
        if(!payload.has("syscustid")) payload.put("syscustid",c.syscustid)
        payload.put("acc_token",c.token)
        if(c.timestamp.isNotBlank()) payload.put("timestamp",c.timestamp)
        schoolReader?.let {reader->
            val value=reader(path,payload)
            currentCoroutineContext().ensureActive()
            return value
        }
        val conn=(URL("https://ecykt.gdbtu.edu.cn$path").openConnection() as HttpsURLConnection).apply {
            instanceFollowRedirects=false; requestMethod="POST"; connectTimeout=12000; readTimeout=18000
            setRequestProperty("Content-Type","application/json"); setRequestProperty("Accept","application/json")
            setRequestProperty("Origin","https://ecykt.gdbtu.edu.cn"); setRequestProperty("acc_token",c.token)
            setRequestProperty("User-Agent",c.userAgent.ifBlank{"Mozilla/5.0"})
            setRequestProperty("Referer",if(power) "https://ecykt.gdbtu.edu.cn/ykt-view/powernew?interfaceName=powernew_${WaterProtocol.encodeForm(c.areaCode)}&isbind=1" else "https://ecykt.gdbtu.edu.cn/ykt-view/recharge?isbind=1"); doOutput=true
        }
        return try {
            conn.outputStream.use { it.write(payload.toString().toByteArray()) }
            require(conn.responseCode==200) { if(conn.responseCode in listOf(401,403)) "校园登录已失效，请重新登录" else "校园服务暂时无法连接" }
            val body=conn.inputStream.use { it.readLimited(1_048_576) }
            currentCoroutineContext().ensureActive()
            parseCampusEnvelope(JSONObject(body.toString(Charsets.UTF_8)))
        } catch(e:Exception){currentCoroutineContext().ensureActive();throw e}
          finally { conn.disconnect() }
    }

    private fun signed(path:String,fields:Map<String,String>,p:HotWaterProfile,requestType:Boolean=false):JSONObject {
        val allowed=setOf("/AECC/GDBusinessSchool/getUserMsg","/zk_areainfo_api/areaInfo/getAreaInfoForApplests",
            "/zk_areainfo_api/areaInfo/getAreaForRoomApplests","/ZK_BSRS/bathe/getMachineMacAddress")
        require(path in allowed)
        val wxcode=fields.entries.joinToString("*_") { "${it.key}=${it.value}" }
        val q=linkedMapOf("wxcode" to wxcode,"sign" to WaterProtocol.signature(p.secret,wxcode),"sid" to p.sid)
        if(requestType) q["requestType"]="1"
        val encoded=q.entries.joinToString("&"){ "${WaterProtocol.encodeForm(it.key)}=${WaterProtocol.encodeForm(it.value)}" }
        val conn=(URL("https://isv.lxt6.cn$path?$encoded").openConnection() as HttpsURLConnection).apply {
            instanceFollowRedirects=false; connectTimeout=20000; readTimeout=25000
        }
        return try {
            require(conn.responseCode==200) { "热水服务暂时无法连接" }
            val raw=org.json.JSONTokener(conn.inputStream.use{it.readLimited(1_048_576)}.toString(Charsets.UTF_8)).nextValue()
            val root=if(raw is String) JSONObject(raw) else raw as? JSONObject ?: error("热水平台响应格式异常")
            require(root.optInt("code",root.optInt("Code",-1))==0) { "热水服务未确认身份" }
            root
        } finally { conn.disconnect() }
    }

    private fun parseCampusEnvelope(root:JSONObject):Any {
        require(root.optInt("code",-1)==0) { "校园登录已失效，请重新登录" }
        val value=root.opt("data")?.takeUnless { it==JSONObject.NULL } ?: error("校园服务未返回数据")
        return if(value is String && value.trim().startsWith("{")) JSONObject(value) else if(value is String && value.trim().startsWith("[")) JSONArray(value) else value
    }
    private fun validate(c:CampusConfig) { require(c.configured && listOf(c.syscustid,c.token,c.areaCode,c.userAgent).all { it.length<=8192 && it.none { ch -> ch.isISOControl() } }) { "请先登录学校账号" } }
    private fun validate(p:HotWaterProfile) { require(p.secret.isNotBlank() && p.sid.isNotBlank() && p.bleName.isNotBlank() && p.typeId>=0 && p.version>0) }
}

fun amount(raw:Any?):String {
    require(raw is String || raw is Number) { "金额格式异常" }
    val value=raw.toString().trim(); require(value.matches(Regex("[+-]?[0-9]{1,12}(\\.[0-9]{1,6})?"))) { "金额格式异常" }
    return value
}

fun parseOfficialSession(j:JSONObject):CampusConfig {
    val login=j.optJSONObject("loginInfo") ?: error("尚未连接校园卡，请完成学校官方登录后等待自动同步")
    val card=j.optJSONObject("custInfo")
    fun text(o:JSONObject?,key:String)=o?.opt(key)?.takeIf {it is String || it is Number}?.toString().orEmpty()
    val c=CampusConfig(text(login,"syscustid"),text(j,"logintoken"),text(j,"schoolid").ifBlank {text(login,"areacode")},
        text(card,"custid").ifBlank {text(login,"custid").ifBlank {text(j,"custid")}},text(login,"timestamp"),text(j,"userAgent"))
    require(c.configured && c.custid.isNotBlank() && listOf(c.syscustid,c.token,c.areaCode,c.custid,c.userAgent).all { it.length<=8192 && it.none(Char::isISOControl) }) { "校园卡信息尚未就绪，请等待自动同步或重试连接" }
    return c
}

private fun java.io.InputStream.readLimited(limit:Int):ByteArray {
    val out=java.io.ByteArrayOutputStream(); val buf=ByteArray(8192)
    while(true) { val n=read(buf); if(n<0) break; require(out.size()+n<=limit) { "response too large" }; out.write(buf,0,n) }
    return out.toByteArray()
}
