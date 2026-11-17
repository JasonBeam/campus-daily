package com.beamjason.xiaorichang

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.beamjason.xiaorichang.net.PaymentDestination
import com.beamjason.xiaorichang.ui.launchPayment
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.net.URLEncoder
import java.net.URLDecoder

@RunWith(AndroidJUnit4::class)
class PaymentHandoffTest {
    private class RecordingActivity:Activity() {
        val launches=mutableListOf<Intent>()
        var unavailable=false
        override fun startActivity(intent:Intent) {
            if(unavailable)throw ActivityNotFoundException()
            launches+=intent
        }
    }
    private fun enc(s:String)=URLEncoder.encode(s,"UTF-8")
    private fun destination():PaymentDestination.Checkout {
        val target="https://wx.zhinengxiyifang.cn/static/commonWasher/index.html"
        val auth="https://openauth.alipay.com/oauth2/publicAppAuthorize.htm?redirect_uri=${enc(target)}"
        return PaymentDestination.Checkout("alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url=${enc(auth)}")
    }
    @Test fun selectedRouteCarriesTheSameValidatedDestination()=runBlocking(Dispatchers.Main) {
        val activity=RecordingActivity();val dest=destination()
        assertFalse(launchPayment(activity,dest).noHandler)
        assertEquals(dest.url,activity.launches.single().data.toString())
        assertFalse(launchPayment(activity,dest,browser=true).noHandler)
        val fallback=activity.launches.last().data!!
        assertEquals("https",fallback.scheme);assertEquals("ds.alipay.com",fallback.host)
        assertEquals(dest.url,URLDecoder.decode(fallback.encodedQuery!!.removePrefix("scheme="),"UTF-8"))
        assertEquals(Intent.ACTION_VIEW,activity.launches.last().action)
    }
    @Test fun unavailableHandlerDoesNotTryAnotherRouteAutomatically()=runBlocking(Dispatchers.Main) {
        val activity=RecordingActivity().apply{unavailable=true}
        assertTrue(launchPayment(activity,destination()).noHandler)
        assertTrue(activity.launches.isEmpty())
    }
}
