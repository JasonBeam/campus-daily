package com.beamjason.xiaorichang.ui

import android.content.Context
import android.net.Uri
import android.webkit.ConsoleMessage
import android.webkit.WebView
import com.beamjason.xiaorichang.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File

/** Private debug-only allowlisted metadata. Never stores query/fragment values,
 * page text, form values, cookies, headers, account state or storage contents. */
internal class CampusWebDiagnostics(context:Context) {
    private val file=File(context.noBackupFilesDir,"campus-web-support.json")
    private val state=JSONObject().put("version",BuildConfig.VERSION_NAME)
    private fun save() {if(BuildConfig.DEBUG)runCatching{file.writeText(state.toString())}}
    fun event(name:String,url:String?=null,code:Int?=null) {
        if(!BuildConfig.DEBUG)return
        val uri=url?.let{runCatching{Uri.parse(it)}.getOrNull()}
        val entry=JSONObject().put("event",name)
        if(uri?.scheme in setOf("http","https"))entry.put("host",uri?.host).put("path",uri?.path)
        if(code!=null)entry.put("code",code)
        val old=state.optJSONArray("events") ?: JSONArray()
        val next=JSONArray();for(i in maxOf(0,old.length()-11) until old.length())next.put(old.get(i))
        state.put("events",next.put(entry));save()
    }
    fun console(message:ConsoleMessage) {
        if(!BuildConfig.DEBUG || message.messageLevel()!=ConsoleMessage.MessageLevel.ERROR)return
        val kind=listOf("TypeError","ReferenceError","SyntaxError","SecurityError","Mixed Content","Content Security Policy")
            .firstOrNull{message.message().contains(it)} ?: "script-error"
        event(kind,message.sourceId(),message.lineNumber())
    }
    fun sample(web:WebView) {
        if(!BuildConfig.DEBUG)return
        val uri=web.url?.let{Uri.parse(it)}
        state.put("native",JSONObject().put("host",uri?.host).put("path",uri?.path)
            .put("progress",web.progress).put("width",web.width).put("height",web.height)
            .put("javascript",web.settings.javaScriptEnabled).put("layerType",web.layerType).put("contentHeight",web.contentHeight).put("scrollX",web.scrollX).put("scrollY",web.scrollY)
            .put("chromeMajor",Regex("Chrome/([0-9]+)").find(web.settings.userAgentString)?.groupValues?.get(1)))
        save()
        web.evaluateJavascript("""JSON.stringify((()=>{
          const locationInfo=v=>{try{const u=new URL(v,location.href);return ['https:','http:'].includes(u.protocol)?{host:u.hostname,path:u.pathname}:null}catch{return null}};
          const marker=id=>{const e=document.getElementById(id);if(!e)return null;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return {height:r.height,width:r.width,display:s.display,visibility:s.visibility,opacity:s.opacity}};
          const box=e=>{if(!e)return null;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return {tag:e.tagName,x:r.x,y:r.y,width:r.width,height:r.height,display:s.display,visibility:s.visibility,opacity:s.opacity,color:s.color,background:s.backgroundColor,position:s.position,z:s.zIndex,transform:s.transform}};
          return {host:location.hostname,path:location.pathname,ready:document.readyState,
            inputCount:document.querySelectorAll('input').length,textLength:document.body?.innerText?.trim().length,
            bodyTags:Array.from(document.body?.children||[]).map(e=>e.tagName),
            app:marker('app'),root:marker('root'),browserNotice:marker('noSupportText'),
            viewport:{width:innerWidth,height:innerHeight,scale:visualViewport?.scale},body:box(document.body),
            containers:Array.from(document.body?.children||[]).filter(e=>e.tagName==='DIV').slice(0,4).map(box),
            center:document.elementsFromPoint(innerWidth/2,innerHeight/2).slice(0,6).map(box),
            scripts:Array.from(document.scripts).map(e=>locationInfo(e.src)).filter(Boolean).slice(0,16),
            frames:Array.from(document.querySelectorAll('iframe')).map(e=>locationInfo(e.src)).filter(Boolean).slice(0,8)};
        })())""") { encoded ->
            runCatching {
                val raw=JSONTokener(encoded).nextValue() as? String ?: return@runCatching
                state.put("document",JSONObject(raw));save()
            }
        }
    }
}
