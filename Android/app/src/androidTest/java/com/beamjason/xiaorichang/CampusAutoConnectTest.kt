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
import com.beamjason.xiaorichang.net.CampusConfig
import com.beamjason.xiaorichang.ui.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Offline end-to-end onboarding with fixture school data, no account or fees. */
@RunWith(AndroidJUnit4::class)
@androidx.test.filters.SdkSuppress(minSdkVersion=26)
class CampusAutoConnectTest {
    @get:Rule val compose=createComposeRule()
    private fun find(v:View):WebView? {
        if(v is WebView)return v
        if(v is ViewGroup)for(i in 0 until v.childCount)find(v.getChildAt(i))?.let{return it}
        return null
    }
    @Test fun schoolCardEntryAndWalletReadNeedNoAdditionalTap() {
        val captured=AtomicReference<CampusConfig>();val complete=CountDownLatch(1)
        compose.setContent {NativeTheme {OfficialBrowser(onLogin={captured.set(it);complete.countDown()},onError={})}}
        val instrumentation=InstrumentationRegistry.getInstrumentation();var web:WebView?=null
        compose.waitUntil(10_000){instrumentation.runOnMainSync {web=ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).firstNotNullOfOrNull{find(it.window.decorView)}};web!=null}
        // Let the isolated wallet reset finish before replacing navigation with
        // offline fixtures. Cancelling loadDataWithBaseURL mid-commit can cancel
        // the next load even after stopLoading(), independently of our client.
        compose.waitUntil(15_000) {
            var primed=false
            instrumentation.runOnMainSync { primed=android.net.Uri.parse(web?.url.orEmpty()).host=="cas.gdbtu.edu.cn" }
            primed
        }
        instrumentation.runOnMainSync {
            val w=web!!;w.stopLoading();val actual=w.webViewClient
            w.webViewClient=object:WebViewClient() {
                override fun shouldOverrideUrlLoading(v:WebView,r:WebResourceRequest)=actual.shouldOverrideUrlLoading(v,r)
                override fun onPageStarted(v:WebView,url:String,icon:Bitmap?)=actual.onPageStarted(v,url,icon)
                override fun onPageFinished(v:WebView,url:String)=actual.onPageFinished(v,url)
                override fun shouldInterceptRequest(v:WebView,r:WebResourceRequest):WebResourceResponse {
                    val html=if(r.url.host=="ecykt.gdbtu.edu.cn")"""
                        <html><body><h1>校园钱包测试</h1><script>
                        localStorage.setItem('elecampus_state',JSON.stringify({logintoken:'fixture-token',schoolid:'fixture-school',loginInfo:{syscustid:'fixture-owner',custid:'fixture-card'},custInfo:{custid:'fixture-card'}}));
                        </script></body></html>
                    """ else """
                        <html><body><div class='studentContainer-left-top-info'><span>学号：fixture-account</span><span>宿舍地址：示例校区2栋3号5层504房</span></div><div id='card-fixture'>
                        <a href='https://invalid.test/admin'>校园卡系统</a>
                        <div class='studentContainer-right-top-title'><span>一卡通信息</span><span class='more'>更多 &gt;</span></div>
                        </div><script>document.getElementById('card-fixture').__vue__={cardInfo:{pcUrl:'https://ecykt.gdbtu.edu.cn/ykt-view/wallet/transaction'}};</script></body></html>
                    """
                    return WebResourceResponse("text/html","UTF-8",ByteArrayInputStream(html.trimIndent().toByteArray()))
                }
            }
            w.loadUrl("https://portal.gdbtu.edu.cn/main.html")
        }
        compose.waitUntil(25_000) { complete.count==0L }
        assertNotNull("Login must automatically enter the correct wallet and capture its valid session",captured.get())
        assertEquals("示例校区2栋3号5层504房",captured.get().portalDormAddress);assertEquals("fixture-owner",captured.get().syscustid);assertEquals("fixture-card",captured.get().custid)
        instrumentation.runOnMainSync {assertEquals("ecykt.gdbtu.edu.cn",android.net.Uri.parse(web!!.url).host)}
    }
}
