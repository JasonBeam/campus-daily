package com.beamjason.xiaorichang

import android.graphics.Bitmap
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.beamjason.xiaorichang.ui.NativeTheme
import com.beamjason.xiaorichang.ui.OfficialBrowser
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
@androidx.test.filters.SdkSuppress(minSdkVersion=26)
class PortalViewportRegressionTest {
    @get:Rule val compose=createComposeRule()
    private fun find(v:View):WebView? {
        if(v is WebView)return v
        if(v is ViewGroup)for(i in 0 until v.childCount)find(v.getChildAt(i))?.let{return it}
        return null
    }
    @Test fun collapsedPortalRootIsRepairedAndPainted() {
        compose.setContent {NativeTheme {OfficialBrowser(onError={})}}
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        var web:WebView?=null
        compose.waitUntil(10_000){instrumentation.runOnMainSync{web=ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).firstNotNullOfOrNull{find(it.window.decorView)}};web!=null}
        instrumentation.runOnMainSync {
            val w=web!!;w.stopLoading();val production=w.webViewClient
            w.webViewClient=object:WebViewClient() {
                override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest)=production.shouldOverrideUrlLoading(view,request)
                override fun onPageStarted(view:WebView,url:String,icon:Bitmap?)=production.onPageStarted(view,url,icon)
                override fun onPageFinished(view:WebView,url:String)=production.onPageFinished(view,url)
                override fun shouldInterceptRequest(view:WebView,request:WebResourceRequest)=WebResourceResponse("text/html","UTF-8",ByteArrayInputStream("""
                    <!doctype html><html><head><style>
                    html,body{margin:0}body>div{position:relative}
                    section{position:absolute;top:0;left:0;width:100%;height:100%;overflow:hidden;background:#00d084}
                    </style></head><body><div><section><h1>校园门户测试</h1><p>一卡通入口</p></section></div></body></html>
                """.trimIndent().toByteArray()))
            }
            w.loadUrl("https://portal.gdbtu.edu.cn/main.html")
        }
        val expanded=AtomicBoolean(false)
        compose.waitUntil(12_000) {
            instrumentation.runOnMainSync {
                web!!.evaluateJavascript("location.hostname==='portal.gdbtu.edu.cn'&&document.documentElement.getBoundingClientRect().height>100&&document.body.getBoundingClientRect().height>100&&document.body.querySelector(':scope>div')?.getBoundingClientRect().height>100") {expanded.set(it=="true")}
            }
            expanded.get()
        }
        val painted=CountDownLatch(1)
        instrumentation.runOnMainSync {web!!.postVisualStateCallback(1,object:WebView.VisualStateCallback(){override fun onComplete(id:Long){web!!.postOnAnimation{web!!.postOnAnimation{painted.countDown()}}}})}
        assertTrue(painted.await(10,TimeUnit.SECONDS))
        compose.waitUntil(5_000) {
            val bitmap=instrumentation.uiAutomation.takeScreenshot();var green=0
            for(y in 0 until bitmap.height step 8)for(x in 0 until bitmap.width step 8) {
                val c=bitmap.getPixel(x,y);if(android.graphics.Color.green(c)>150&&android.graphics.Color.red(c)<60&&android.graphics.Color.blue(c) in 80..180)green++
            }
            if(green>1000) {
                val dir=java.io.File(instrumentation.targetContext.getExternalFilesDir(null),"login-smoke").apply{mkdirs()}
                java.io.File(dir,"restored-portal-fixture.png").outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
            }
            bitmap.recycle();green>1000
        }
    }
}
