package com.beamjason.xiaorichang

import android.graphics.Bitmap
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import androidx.compose.runtime.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Explicit network smoke check, for an emulator with no personal school session.
 * Detects form presence only: never reads, fills or submits any field values. */
@RunWith(AndroidJUnit4::class)
@androidx.test.filters.SdkSuppress(minSdkVersion=26)
class PublicCampusLoginSmokeTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    private fun find(view:View):WebView? {
        if(view is WebView)return view
        if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let{return it}
        return null
    }
    @Test fun officialFormLoadsAndUnauthenticatedPortalReturnsToLogin() {
        compose.onNodeWithText("登录并连接校园卡").performClick()
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        var web:WebView?=null
        compose.waitUntil(15_000) {
            instrumentation.runOnMainSync {web=ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(Stage.RESUMED).firstNotNullOfOrNull{find(it.window.decorView)}}
            web!=null
        }
        fun awaitOfficialForm() {
            val visible=AtomicBoolean(false)
            compose.waitUntil(40_000) {
                instrumentation.runOnMainSync {
                    if(android.net.Uri.parse(web!!.url ?: "").host=="cas.gdbtu.edu.cn")
                        web!!.evaluateJavascript("location.hostname==='cas.gdbtu.edu.cn'&&document.querySelectorAll('input[type=password]').length>0") {visible.set(it=="true")}
                }
                visible.get()
            }
        }
        awaitOfficialForm()
        val sawPortalMain=AtomicBoolean(false)
        val returnedCasFinished=CountDownLatch(1)
        instrumentation.runOnMainSync {assertTrue(web!!.width>0 && web!!.height>0)
            val original=web!!.webViewClient
            web!!.webViewClient=object:WebViewClient() {
                override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest)=original.shouldOverrideUrlLoading(view,request)
                override fun onPageStarted(view:WebView,url:String,icon:Bitmap?) {
                    if(android.net.Uri.parse(url).let{it.host=="portal.gdbtu.edu.cn"&&it.path=="/main.html"})sawPortalMain.set(true)
                    original.onPageStarted(view,url,icon)
                }
                override fun onPageFinished(view:WebView,url:String) {
                    original.onPageFinished(view,url)
                    if(sawPortalMain.get() && view.url==url && android.net.Uri.parse(url).host=="cas.gdbtu.edu.cn")returnedCasFinished.countDown()
                }
            }
            web!!.loadUrl("https://portal.gdbtu.edu.cn/?path=https%3A%2F%2Fportal.gdbtu.edu.cn%2Fmain.html%23%2FStudent")}
        compose.waitUntil(30_000) {sawPortalMain.get()}
        assertTrue("The return navigation must finish, not retain the preceding login DOM",returnedCasFinished.await(40,TimeUnit.SECONDS))
        awaitOfficialForm()
        val compact=AtomicBoolean(false)
        compose.waitUntil(10_000) {
            instrumentation.runOnMainSync {web!!.evaluateJavascript("document.getElementById('campus-compact-login')!==null"){compact.set(it=="true")}}
            compact.get()
        }
        val styledButton=AtomicBoolean(false)
        compose.waitUntil(10_000) {
            instrumentation.runOnMainSync {web!!.evaluateJavascript("Array.from(document.querySelectorAll('#vue_main .card:not(.mfa-m) .el-button--primary')).some(x=>x.getBoundingClientRect().width>0&&getComputedStyle(x).backgroundColor==='rgb(33, 105, 216)')"){styledButton.set(it=="true")}}
            styledButton.get()
        }
        val painted=CountDownLatch(1)
        instrumentation.runOnMainSync {
            web!!.postVisualStateCallback(1,object:WebView.VisualStateCallback() {
                override fun onComplete(requestId:Long) {
                    web!!.postOnAnimation {web!!.postOnAnimation {painted.countDown()}}
                }
            })
        }
        assertTrue("School page reaches a rendered frame",painted.await(15,TimeUnit.SECONDS))
        val screenshot=instrumentation.uiAutomation.takeScreenshot()
        val dir=File(instrumentation.targetContext.getExternalFilesDir(null),"login-smoke").apply{mkdirs()}
        File(dir,"official-login-empty.png").outputStream().use{screenshot.compress(Bitmap.CompressFormat.PNG,100,it)}
        var loginPixels=0
        val location=IntArray(2);var width=0;var height=0
        instrumentation.runOnMainSync {web!!.getLocationOnScreen(location);width=web!!.width;height=web!!.height}
        for(y in location[1].coerceAtLeast(0) until (location[1]+height).coerceAtMost(screenshot.height) step 8)for(x in location[0].coerceAtLeast(0) until (location[0]+width).coerceAtMost(screenshot.width) step 8) {
            val color=screenshot.getPixel(x,y)
            if(android.graphics.Color.blue(color)>150 && android.graphics.Color.red(color)<100 && android.graphics.Color.green(color) in 50..160)loginPixels++
        }
        screenshot.recycle()
        assertTrue("Compact official login controls must be visible in the WebView, not only in the DOM ($loginPixels)",loginPixels>100)
    }
}
