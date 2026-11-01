package com.beamjason.xiaorichang.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import java.security.MessageDigest

fun CampusConfig.waterAccessOwner()=MessageDigest.getInstance("SHA-256").digest((areaCode+"\u0000"+syscustid).toByteArray()).joinToString(""){"%02x".format(it.toInt() and 255)}
data class WaterAccessSession(val token:String,val campusOwner:String,val expiresAt:Long,val studentId:String,val schoolId:String,val bleName:String,val typeId:Int,val version:Int) {
    fun validate() {
        require(token.matches(Regex("[A-Za-z0-9_-]{43}")) && campusOwner.matches(Regex("[0-9a-f]{64}")) && expiresAt>0)
        require(listOf(studentId,schoolId).all{it.matches(Regex("[A-Za-z0-9.-]{1,64}"))} && bleName.isNotBlank() && bleName.length<=64 && typeId>=0 && version>0)
    }
    val current get()=expiresAt>System.currentTimeMillis()+60_000
    fun json()=JSONObject().put("token",token).put("campusOwner",campusOwner).put("expiresAt",expiresAt).put("studentID",studentId).put("schoolID",schoolId).put("bleName",bleName).put("typeID",typeId).put("version",version)
    companion object {fun read(j:JSONObject)=WaterAccessSession(j.getString("token"),j.getString("campusOwner"),j.getLong("expiresAt"),j.getString("studentID"),j.getString("schoolID"),j.getString("bleName"),j.getInt("typeID"),j.getInt("version")).also{it.validate()}}
}
class WaterAccessException(val status:Int,val code:String):Exception(when(code) {
    "school_login_required","school_login_expired","access_expired","login_required" -> "学校登录需更新，请重新登录学校账号"
    "transactions_not_enabled" -> "热水接入正在验收，暂未开放开始用水"
    "water_unresolved" -> "仍有未确认的热水记录，请先核对记录"
    "wrong_device","bind_required","invalid_location" -> "宿舍或水控需要重新核对，请返回宿舍设置"
    "rate_limited" -> "查询较频繁，请稍后重试"
    "access_network_unavailable" -> "无法连接热水接入服务，请检查网络后重试"
    else -> "热水在线接入暂时不可用，请稍后重新读取宿舍"
})
object WaterAccessClient {
    const val BASE="https://campus-api.070688.xyz"
    const val BACKUP="https://campus-daily-access.jasonbeam-campus.workers.dev"
    @Volatile private var healthy:Pair<String,Long>?=null
    private fun origin():String {
        healthy?.takeIf{it.second>System.currentTimeMillis()}?.let{return it.first}
        // Probe known hosts without credentials before a POST. Never replay
        // authorization or settlement after a timeout or unknown result.
        for(candidate in listOf(BASE,BACKUP)) {
            val c=(URL("$candidate/health").openConnection() as HttpsURLConnection).apply {
                instanceFollowRedirects=false;connectTimeout=3000;readTimeout=4000
            }
            try {
                if(c.responseCode!=200)continue
                val bytes=c.inputStream.use{input->val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(1024);while(out.size()<4097){val n=input.read(buffer,0,minOf(buffer.size,4097-out.size()));if(n<0)break;out.write(buffer,0,n)};out.toByteArray()}
                if(bytes.size>4096)continue
                val value=JSONObject(bytes.toString(Charsets.UTF_8))
                if(value.optString("service")=="campus-daily-access" && value.optInt("protocol")==1 && value.optBoolean("configured")) {
                    healthy=candidate to (System.currentTimeMillis()+if(candidate==BASE)300000 else 15000);return candidate
                }
            }catch(_:Exception){}finally{c.disconnect()}
        }
        throw WaterAccessException(0,"access_network_unavailable")
    }
    suspend fun connect(c:CampusConfig):WaterAccessSession = withContext(Dispatchers.IO) {
        val body=JSONObject().put("syscustid",c.syscustid).put("acc_token",c.token).put("areacode",c.areaCode).put("custid",c.custid)
        if(c.timestamp.isNotBlank())body.put("timestamp",c.timestamp)
        WaterAccessSession.read(call("connect",null,body)).also{require(it.campusOwner==c.waterAccessOwner())}
    }
    fun call(route:String,access:WaterAccessSession?,body:JSONObject):JSONObject {
        require(route in setOf("connect","bootstrap","options","machines","bind","authorize","settle","status"))
        access?.validate()
        val origin=origin()
        val conn=(URL("$origin/v1/$route").openConnection() as HttpsURLConnection).apply {
            instanceFollowRedirects=false;requestMethod="POST";connectTimeout=20000;readTimeout=25000;doOutput=true
            setRequestProperty("Content-Type","application/json")
            if(access!=null)setRequestProperty("Authorization","Bearer ${access.token}")
        }
        return try {
            conn.outputStream.use{it.write(body.toString().toByteArray())}
            val status=conn.responseCode
            val stream=if(status==200)conn.inputStream else conn.errorStream
            val bytes=stream?.use{input->val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(4096);while(true){val n=input.read(buffer);if(n<0)break;require(out.size()+n<=1048576);out.write(buffer,0,n)};out.toByteArray()} ?: byteArrayOf()
            val result=runCatching{JSONObject(bytes.toString(Charsets.UTF_8))}.getOrElse{throw WaterAccessException(status,"invalid_response")}
            if(status!=200)throw WaterAccessException(status,result.optString("error").takeIf{it.matches(Regex("[a-z][a-z0-9_]{0,63}"))} ?: "invalid_response")
            result
        }catch(e:java.io.IOException){healthy=null;throw e}finally{conn.disconnect()}
    }
    suspend fun bind(access:WaterAccessSession,room:String,machine:String)=withContext(Dispatchers.IO){
        val result=call("bind",access,JSONObject().put("room",room).put("machineID",machine))
        require(result.optBoolean("bound") && result.optString("machineID")==machine){"水控编号不匹配，尚未保存"}
    }
    suspend fun bootstrap(access:WaterAccessSession,residence:String):WaterAccessBootstrap=withContext(Dispatchers.IO){
        WaterAccessBootstrap.read(call("bootstrap",access,JSONObject().put("residence",residence)),residence)
    }
}

data class WaterAccessBootstrap(val levels:List<List<Option>>,val path:List<Option>,val machines:List<DormWater>,val matched:Boolean,val transactionsEnabled:Boolean) {
    companion object {
        fun read(root:JSONObject,residence:String):WaterAccessBootstrap {
            fun options(rows:org.json.JSONArray):List<Option> {
                require(rows.length()<=1000)
                return (0 until rows.length()).map{rows.getJSONObject(it).let{row->Option(row.getString("id"),row.getString("name"))}}
                    .also{require(it.all{o->o.id.isNotBlank()&&o.id.length<=1024&&o.name.isNotBlank()&&o.name.length<=128} && it.map{o->o.id}.distinct().size==it.size)}
            }
            val rawLevels=root.getJSONArray("levels");require(rawLevels.length() in 1..4)
            val levels=(0 until rawLevels.length()).map{options(rawLevels.getJSONArray(it))}
            val path=options(root.getJSONArray("path"));require(path.size<=levels.size && path.withIndex().all{(i,o)->o in levels[i]})
            require(root.get("matched") is Boolean && root.get("transactionsEnabled") is Boolean)
            val matched=root.getBoolean("matched");require(matched==(path.size==4))
            val address=PortalDormAddress.parse(residence)
            if(matched)require(address!=null && path.withIndex().all{(i,o)->address.matches(o.name,i)})
            val rows=root.getJSONArray("machines");require(rows.length()<=100 && (matched || rows.length()==0))
            val machines=(0 until rows.length()).map{rows.getJSONObject(it).let{r->DormWater(r.getString("id").uppercase(),r.getString("name"),r.getString("mac"))}}
            require(machines.all{it.machineId.matches(Regex("[0-9A-F]{8}"))} && machines.map{it.machineId}.distinct().size==machines.size)
            return WaterAccessBootstrap(levels,path,machines,matched,root.getBoolean("transactionsEnabled"))
        }
    }
}
