package com.beamjason.xiaorichang.data

import android.content.Context
import com.beamjason.xiaorichang.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONObject
import java.net.URI
import java.net.URL
import javax.net.ssl.HttpsURLConnection

data class UpdateState(val enabled:Boolean=true,val checking:Boolean=false,val message:String="仅检查 GitHub 正式版，不会自动安装。",val url:String?=null,val prompt:Boolean=false)
data class AndroidRelease(val tag:String,val url:String,val code:Int)
fun readAndroidRelease(root:JSONObject):AndroidRelease {
    require(!root.optBoolean("draft") && !root.optBoolean("prerelease"))
    val tag=root.getString("tag_name");require(tag.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+")))
    val url=root.getString("html_url");val u=URI(url)
    require(u.scheme=="https" && u.host=="github.com" && u.userInfo==null && u.port==-1 && u.query==null && u.fragment==null && u.path=="/JasonBeam/campus-daily/releases/tag/$tag")
    val assets=root.getJSONArray("assets");val pattern=Regex("CampusDaily-.+-code([0-9]+)-(debug|release)\\.apk")
    val code=(0 until assets.length()).mapNotNull { pattern.matchEntire(assets.getJSONObject(it).optString("name"))?.groupValues?.get(1)?.toIntOrNull() }.maxOrNull() ?: 0
    return AndroidRelease(tag,url,code)
}
class AppUpdates(context:Context) {
    private val prefs=context.getSharedPreferences("app.updates",Context.MODE_PRIVATE)
    private val mutable=MutableStateFlow(UpdateState(enabled=prefs.getBoolean("enabled",true)))
    val state=mutable.asStateFlow()
    private var lastAttempt=0L
    fun setEnabled(value:Boolean){prefs.edit().putBoolean("enabled",value).apply();mutable.update{it.copy(enabled=value,prompt=false)}}
    fun dismiss(){mutable.update{it.copy(prompt=false)}}
    suspend fun check(manual:Boolean=false) {
        val now=System.currentTimeMillis()
        if(mutable.value.checking || !manual && (!mutable.value.enabled || now-lastAttempt<21_600_000))return
        lastAttempt=now;mutable.update{it.copy(checking=true)}
        try {
            val release=withContext(Dispatchers.IO) {
                val c=URL("https://api.github.com/repos/JasonBeam/campus-daily/releases/latest").openConnection() as HttpsURLConnection
                c.instanceFollowRedirects=false;c.connectTimeout=15_000;c.readTimeout=15_000
                c.setRequestProperty("Accept","application/vnd.github+json");c.setRequestProperty("User-Agent","CampusDaily")
                try {kotlin.check(c.responseCode==200);val bytes=c.inputStream.use{it.readBytesLimited()};readAndroidRelease(JSONObject(bytes.toString(Charsets.UTF_8)))}finally{c.disconnect()}
            }
            val newer=release.code>BuildConfig.VERSION_CODE;val identity="${release.tag}:${release.code}"
            val prompt=newer && !manual && prefs.getString("prompt",null)!=identity
            if(prompt)prefs.edit().putString("prompt",identity).apply()
            mutable.update{it.copy(checking=false,url=if(newer)release.url else null,prompt=prompt,message=if(newer)"发现 ${release.tag}，可查看更新说明与安装包。" else "当前已是最新正式版或更新的测试版本。")}
        } catch(_:Exception){mutable.update{it.copy(checking=false,message="暂时无法检查更新，请稍后重试。")}}
    }
    private fun java.io.InputStream.readBytesLimited():ByteArray {
        val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192)
        while(true){val n=read(buffer);if(n<0)break;kotlin.check(out.size()+n<=524288);out.write(buffer,0,n)}
        return out.toByteArray()
    }
}
