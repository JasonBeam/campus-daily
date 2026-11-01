package com.beamjason.xiaorichang

import android.graphics.Bitmap
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.*
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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Offline regression of the real navigation client, never a school account. */
@RunWith(AndroidJUnit4::class)
@androidx.test.filters.SdkSuppress(minSdkVersion=26)
class CampusPortalWebViewRegressionTest {
    @get:Rule val compose=createComposeRule()
    private fun find(view:View):WebView? {
        if(view is WebView)return view
        if(view is ViewGroup)for(i in 0 until view.childCount)find(view.getChildAt(i))?.let{return it}
        return null
    }
    private fun currentWeb():WebView? = ActivityLifecycleMonitorRegistry.getInstance()
        .getActivitiesInStage(Stage.RESUMED).firstNotNullOfOrNull{find(it.window.decorView)}

    @Test fun blankPortalLandingReachesMainWithIntactTicketAndSurvivesRecomposition() {
        var revision by mutableIntStateOf(0)
        compose.setContent {NativeTheme {Column {Text("$revision");OfficialBrowser(onLogin={if(revision<0)error("unused")},onError={})}}}
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        var web:WebView?=null
        compose.waitUntil(10_000) {instrumentation.runOnMainSync {web=currentWeb()};web!=null}
        // Let the isolated wallet reset finish before replacing navigation with
        // offline fixtures. Cancelling loadDataWithBaseURL mid-commit can cancel
        // the next load even after stopLoading(), independently of our client.
        compose.waitUntil(15_000) {
            var primed=false
            instrumentation.runOnMainSync { primed=android.net.Uri.parse(web?.url.orEmpty()).host=="cas.gdbtu.edu.cn" }
            primed
        }
        val query="path=https%3A%2F%2Fportal.gdbtu.edu.cn%2Fmain.html%23%2FStudent&ticket=ST-fixture%2Bcase%252F"
        val mainFinished=CountDownLatch(1)
        val mainRequests=java.util.concurrent.atomic.AtomicInteger(0)
        instrumentation.runOnMainSync {
            val w=web!!;w.stopLoading()
            val production=w.webViewClient
            w.webViewClient=object:WebViewClient() {
                override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest)=production.shouldOverrideUrlLoading(view,request)
                override fun onPageStarted(view:WebView,url:String,icon:Bitmap?)=production.onPageStarted(view,url,icon)
                override fun onPageFinished(view:WebView,url:String) {
                    production.onPageFinished(view,url)
                    if(android.net.Uri.parse(url).path=="/main.html")mainFinished.countDown()
                }
                override fun shouldInterceptRequest(view:WebView,request:WebResourceRequest):WebResourceResponse {
                    if(request.url.path=="/main.html")mainRequests.incrementAndGet()
                    val html=if(request.url.path=="/main.html")"<html><body><form id='school-fixture'><input type='password'></form></body></html>"
                        else "<html><body><div></div><div></div><div></div><div></div></body></html>"
                    return WebResourceResponse("text/html","UTF-8",ByteArrayInputStream(html.toByteArray()))
                }
            }
            w.loadUrl("https://portal.gdbtu.edu.cn/?$query")
        }
        assertTrue("Blank root must reach the official main document",mainFinished.await(20,TimeUnit.SECONDS))
        val visible=CountDownLatch(1)
        instrumentation.runOnMainSync {
            assertEquals("https://portal.gdbtu.edu.cn/main.html?$query",web!!.url)
            web!!.evaluateJavascript("document.getElementById('school-fixture')!==null") {if(it=="true")visible.countDown()}
        }
        assertTrue("Destination form is rendered",visible.await(10,TimeUnit.SECONDS))
        val staleCallbackChecked=CountDownLatch(1)
        instrumentation.runOnMainSync {
            web!!.webViewClient.onPageFinished(web!!,"https://portal.gdbtu.edu.cn/?$query")
            web!!.postVisualStateCallback(2,object:WebView.VisualStateCallback(){override fun onComplete(id:Long){web!!.postOnAnimation {staleCallbackChecked.countDown()}}})
        }
        assertTrue(staleCallbackChecked.await(10,TimeUnit.SECONDS))
        assertEquals("A stale callback must not replay a consumed ticket",1,mainRequests.get())
        compose.runOnIdle {revision++};compose.waitForIdle()
        instrumentation.runOnMainSync {assertSame("Parent updates must retain the active WebView",web,currentWeb());assertEquals("https://portal.gdbtu.edu.cn/main.html?$query",web!!.url)}
    }
}
