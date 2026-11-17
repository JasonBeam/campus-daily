package com.beamjason.xiaorichang.data

import android.content.Context
import com.beamjason.xiaorichang.BuildConfig
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONObject
import java.net.URI
import java.net.URL
import javax.net.ssl.HttpsURLConnection

data class UpdateState(val enabled:Boolean=true,val checking:Boolean=false,val message:String="仅检查 GitHub 正式版，不会自动安装。",val url:String?=null,val prompt:Boolean=false,val failed:Boolean=false)
data class AndroidRelease(val tag:String,val url:String,val code:Int,val json:String)
fun readAndroidRelease(root:JSONObject):AndroidRelease {
    require(!root.optBoolean("draft") && !root.optBoolean("prerelease"))
    val tag=root.getString("tag_name");require(tag.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+")))
    val url=root.getString("html_url");val u=URI(url)
    require(u.scheme=="https" && u.host=="github.com" && u.userInfo==null && u.port==-1 && u.query==null && u.fragment==null && u.path=="/JasonBeam/campus-daily/releases/tag/$tag")
    val assets=root.getJSONArray("assets");val pattern=Regex("CampusDaily-.+-code([0-9]+)-(debug|release)\\.apk")
    val code=(0 until assets.length()).mapNotNull { pattern.matchEntire(assets.getJSONObject(it).optString("name"))?.groupValues?.get(1)?.toIntOrNull() }.maxOrNull() ?: 0
    require(code>0)
    return AndroidRelease(tag,url,code,root.toString())
}
suspend fun loadAndroidUpdate(fetch:suspend (String)->ByteArray):AndroidRelease {
    val sources=listOf("https://api.github.com/repos/JasonBeam/campus-daily/releases/latest","https://jasonbeam.github.io/campus-daily/updates.json")
    var failure:Exception=IllegalStateException("更新服务不可用")
    for(source in sources) {
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        try {
            val bytes=fetch(source);require(bytes.size<=524288)
            return readAndroidRelease(JSONObject(bytes.toString(Charsets.UTF_8)))
        } catch(e:kotlinx.coroutines.CancellationException){throw e}
          catch(e:Exception){failure=e}
    }
    throw failure
}
class AppUpdates(context:Context) {
    private val prefs=context.getSharedPreferences("app.updates",Context.MODE_PRIVATE)
    private val mutable=MutableStateFlow(UpdateState(enabled=prefs.getBoolean("enabled",true)))
    val state=mutable.asStateFlow()
    private var lastSuccess=0L
    private var lastFailure=0L
    init {
        val cached=runCatching{readAndroidRelease(JSONObject(prefs.getString("cached",null) ?: error("no cache")))}.getOrNull()
        if(cached!=null)mutable.update{it.copy(url=if(cached.code>BuildConfig.VERSION_CODE)cached.url else null,message="上次更新信息已保留，联网检查后确认最新版本。")}
    }
    fun setEnabled(value:Boolean){prefs.edit().putBoolean("enabled",value).apply();mutable.update{it.copy(enabled=value,prompt=false)}}
    fun dismiss(){mutable.update{it.copy(prompt=false)}}
    suspend fun check(manual:Boolean=false) {
        val now=System.currentTimeMillis()
        if(mutable.value.checking || !manual && (!mutable.value.enabled || now-lastSuccess<21_600_000 || now-lastFailure<60_000))return
        mutable.update{it.copy(checking=true,failed=false)}
        try {
            val release=withContext(Dispatchers.IO) {
                loadAndroidUpdate { source ->
                val c=URL(source).openConnection() as HttpsURLConnection
                c.instanceFollowRedirects=false;c.connectTimeout=5_000;c.readTimeout=5_000
                c.setRequestProperty("Accept","application/vnd.github+json");c.setRequestProperty("User-Agent","CampusDaily")
                try {kotlin.check(c.responseCode==200);c.inputStream.use{it.readBytesLimited()}}finally{c.disconnect()}
                }
            }
            lastSuccess=now;lastFailure=0
            prefs.edit().putString("cached",release.json).putLong("checkedAt",now).apply()
            val newer=release.code>BuildConfig.VERSION_CODE;val identity="${release.tag}:${release.code}"
            val prompt=newer && !manual && prefs.getString("prompt",null)!=identity
            if(prompt)prefs.edit().putString("prompt",identity).apply()
            mutable.update{it.copy(checking=false,url=if(newer)release.url else null,prompt=prompt,message=if(newer)"发现 ${release.tag}，可查看更新说明与安装包。" else "当前已是最新正式版或更新的测试版本。")}
        } catch(e:kotlinx.coroutines.CancellationException){mutable.update{it.copy(checking=false)};throw e}
          catch(_:Exception){
            lastFailure=now
            val checked=prefs.getLong("checkedAt",0)
            val detail=if(checked>0)"；已保留上次（${java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT,java.text.DateFormat.SHORT).format(java.util.Date(checked))}）的结果" else ""
            mutable.update{it.copy(checking=false,failed=true,message="暂时连不上更新服务$detail，可直接打开下载页查看版本。")}
        }
    }
    private fun java.io.InputStream.readBytesLimited():ByteArray {
        val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192)
        while(true){val n=read(buffer);if(n<0)break;kotlin.check(out.size()+n<=524288);out.write(buffer,0,n)}
        return out.toByteArray()
    }
}
