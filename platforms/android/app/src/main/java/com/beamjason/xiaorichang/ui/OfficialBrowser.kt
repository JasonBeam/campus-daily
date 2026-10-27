package com.beamjason.xiaorichang.ui

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.data.message
import com.alipay.sdk.app.PayTask
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener

private val campusHosts=setOf("portal.gdbtu.edu.cn","cas.gdbtu.edu.cn","ecykt.gdbtu.edu.cn")
private fun official(url:Uri) = url.scheme=="https" && url.host in campusHosts && url.userInfo==null && url.port in listOf(-1,443)

/** No JavascriptInterface, file access or credentials in URLs. Reads only the
 * authenticated school origin after the user presses “读取登录”. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun OfficialBrowser(session:CampusWebSession?=null,power:Boolean=false,onLogin:((CampusConfig)->Unit)?=null,onError:(String)->Unit) {
    val context=LocalContext.current
    val loginCallback by rememberUpdatedState(onLogin)
    val errorCallback by rememberUpdatedState(onError)
    var loading by remember { mutableStateOf(true) }
    var currentUrl by remember { mutableStateOf("") }
    var ready by remember { mutableStateOf(false) }
    var bootstrapping by remember { mutableStateOf(false) }
    var bootstrapFailed by remember { mutableStateOf(false) }
    val web=remember(context,session,power) {
        WebView(context).apply {
            settings.javaScriptEnabled=true; settings.domStorageEnabled=true
            settings.allowFileAccess=false; settings.allowContentAccess=false
            settings.mixedContentMode=WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.setSupportMultipleWindows(false)
            if(!session?.userAgent.isNullOrBlank()) settings.userAgentString=session!!.userAgent
            CookieManager.getInstance().setAcceptThirdPartyCookies(this,false)
            webViewClient=object:WebViewClient() {
                override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest):Boolean {
                    if(!request.isForMainFrame) return false
                    val target=request.url
                    if(official(target)) return false
                    if(session!=null && view.url?.let { Uri.parse(it).host }=="ecykt.gdbtu.edu.cn" && request.hasGesture() && target.scheme in setOf("alipays","alipay","weixin")) {
                        try { context.startActivity(Intent(Intent.ACTION_VIEW,target)) } catch(_:Exception) { errorCallback("没有找到相应付款应用，请先安装后重试") }
                    }
                    return true
                }
                override fun onPageStarted(view:WebView,url:String,icon:android.graphics.Bitmap?) { loading=true; currentUrl=url }
                override fun onReceivedError(view:WebView,request:WebResourceRequest,error:WebResourceError) {
                    if(request.isForMainFrame) { loading=false; errorCallback("学校网页暂时无法打开，请检查网络后重试") }
                }
                override fun onPageFinished(view:WebView,url:String) {
                    loading=false; currentUrl=url
                    if(session!=null && !ready && !bootstrapping && !bootstrapFailed && Uri.parse(url).host=="ecykt.gdbtu.edu.cn") {
                        bootstrapping=true
                        val payload=JSONObject.quote(session.state.toString())
                        view.evaluateJavascript("""(()=>{if(location.origin!=='https://ecykt.gdbtu.edu.cn')return false;localStorage.setItem('elecampus_state',$payload);localStorage.removeItem('elecampus_state_authquery');localStorage.removeItem('elecampus_state_backurl');return true})()""") { result ->
                            if(result=="true") { ready=true; view.loadUrl(session.url(power)) }
                            else { bootstrapFailed=true; errorCallback("登录信息未能交接，请重新登录学校账号") }
                        }
                    }
                    if(session!=null && ready) view.evaluateJavascript("""(()=>location.hostname==='ecykt.gdbtu.edu.cn'&&document.body&&/登录状态过期|登录已过期|登录失效/.test(document.body.innerText))()""") { if(it=="true") errorCallback("学校登录已过期，请返回设备页重新登录") }
                }
            }
            loadUrl(if(session==null) "https://portal.gdbtu.edu.cn/main.html#/Student" else "https://ecykt.gdbtu.edu.cn/ykt-view/")
        }
    }
    DisposableEffect(web) { onDispose { web.stopLoading(); web.webViewClient=WebViewClient(); web.destroy() } }
    Column(Modifier.fillMaxSize()) {
        Hint(if(session==null) "在学校官方网页登录，进入一卡通后点“读取登录”。账号密码由学校页面处理。" else "学校官方充值页面，请核对账号、宿舍和金额后付款。")
        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top=8.dp))
        AndroidView(factory={web},modifier=Modifier.weight(1f).fillMaxWidth())
        if(onLogin!=null) ActionButton("读取登录",enabled=!loading && Uri.parse(currentUrl).host=="ecykt.gdbtu.edu.cn") {
            web.evaluateJavascript("""(()=>{if(location.origin!=='https://ecykt.gdbtu.edu.cn')return null;const s=JSON.parse(localStorage.getItem('elecampus_state')||'{}');return JSON.stringify({logintoken:s.logintoken,loginInfo:s.loginInfo,schoolid:s.schoolid,custInfo:s.custInfo,custid:s.custid,userAgent:navigator.userAgent})})()""") { result ->
                try {
                    require(result.length<=131072); val raw=JSONTokener(result).nextValue() as? String ?: error("请先打开学校一卡通页面")
                    loginCallback?.invoke(parseOfficialSession(JSONObject(raw)))
                } catch(e:Exception) { errorCallback(message(e)) }
            }
        }
    }
}

suspend fun launchPayment(activity:Activity,destination:PaymentDestination):String = when(destination) {
    PaymentDestination.Query -> "请刷新订单，以服务器状态为准"
    is PaymentDestination.Checkout -> {
        require(PaymentPolicy.allowedCheckout(destination.url))
        try { activity.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(destination.url))); "已打开付款页面，返回后核对订单状态" }
        catch(_:android.content.ActivityNotFoundException) { "未找到支付宝，请先安装并在 U净核对订单" }
    }
    is PaymentDestination.Signed -> {
        // Use the official SDK on its required worker thread. Its callback is a hint,
        // never proof of payment: the order is always queried again on return.
        val result=withContext(Dispatchers.IO) { PayTask(activity).payV2(destination.value,true) }
        when(result["resultStatus"]) { "9000" -> "支付宝已返回，请刷新确认订单"; "6001" -> "已退出付款，请核对订单"; else -> "付款结果待核对，请查看支付宝和订单状态" }
    }
}
