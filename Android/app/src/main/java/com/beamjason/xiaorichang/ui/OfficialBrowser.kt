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
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.alpha
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
private const val campusPrimerURL="https://ecykt.gdbtu.edu.cn/__campus_native_login__"
private fun official(url:Uri) = url.scheme=="https" && url.host in campusHosts && url.userInfo==null && url.port in listOf(-1,443)
// Enter CAS explicitly: the portal SPA may render its student dashboard before
// an unauthenticated embedded browser has established a school session.
private val campusLoginUrl=Uri.Builder().scheme("https").authority("cas.gdbtu.edu.cn")
    .path("/cas/login").appendQueryParameter("service",
        "https://portal.gdbtu.edu.cn/?path="+Uri.encode("https://portal.gdbtu.edu.cn/main.html#/Student"))
    .build().toString()

/** No JavascriptInterface, file access or credentials in URLs. Reads only the
 * authenticated school origin during the user-started login flow. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun OfficialBrowser(session:CampusWebSession?=null,power:Boolean=false,onLogin:((CampusConfig)->Unit)?=null,onError:(String)->Unit) {
    val context=LocalContext.current
    val diagnostics=remember(context){CampusWebDiagnostics(context)}
    val loginCallback by rememberUpdatedState(onLogin)
    val errorCallback by rememberUpdatedState(onError)
    var loading by remember { mutableStateOf(true) }
    var currentUrl by remember { mutableStateOf("") }
    var ready by remember { mutableStateOf(false) }
    var bootstrapping by remember { mutableStateOf(false) }
    var bootstrapFailed by remember { mutableStateOf(false) }
    var pageError by remember { mutableStateOf<String?>(null) }
    var loadSequence by remember { mutableIntStateOf(0) }
    var web by remember { mutableStateOf<WebView?>(null) }
    var loginPrimed by remember { mutableStateOf(false) }
    var primerInFlight by remember { mutableStateOf(false) }
    var readingLogin by remember { mutableStateOf(false) }
    var loginCaptured by remember { mutableStateOf(false) }
    var automationStalled by remember { mutableStateOf(false) }
    var automationRevision by remember { mutableIntStateOf(0) }
    var manualLogin by remember { mutableStateOf(false) }
    var portalDormAddress by remember {mutableStateOf("")}
    var loginStatus by remember { mutableStateOf("填写学校学工号和密码，登录后自动同步校园卡。") }
    val automationScript=remember(context){runCatching{context.assets.open("CampusLoginAutomation.js").bufferedReader().use{it.readText()}}.getOrNull()}
    fun readAuthenticatedLogin(automatic:Boolean) {
        val active=web ?: return
        if(readingLogin || loginCaptured || loginCallback==null)return
        readingLogin=true
        active.evaluateJavascript("""(()=>{if(location.origin!=='https://ecykt.gdbtu.edu.cn')return null;const s=JSON.parse(localStorage.getItem('elecampus_state')||'{}');return JSON.stringify({logintoken:s.logintoken,loginInfo:s.loginInfo,schoolid:s.schoolid,custInfo:s.custInfo,custid:s.custid,userAgent:navigator.userAgent})})()""") {result->
            try {
                if(active!==web)return@evaluateJavascript
                require(result.length<=131072)
                val raw=JSONTokener(result).nextValue() as? String ?: error("请先完成学校一卡通登录")
                val config=parseOfficialSession(JSONObject(raw)).copy(portalDormAddress=portalDormAddress)
                loginCaptured=true;loginStatus="正在同步校园卡…";loginCallback?.invoke(config)
            } catch(e:Exception) {if(!automatic)errorCallback(message(e))}
            finally {readingLogin=false}
        }
    }
    fun createWebView(viewContext:android.content.Context):WebView {
        return WebView(viewContext).apply {
            // A browser must be measured against its allocated viewport, not
            // WRAP_CONTENT: percentage/viewport-sized portal shells otherwise
            // have no intrinsic content height to measure.
            layoutParams=android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT)
            settings.javaScriptEnabled=true; settings.domStorageEnabled=true
            settings.useWideViewPort=true; settings.loadWithOverviewMode=true
            settings.allowFileAccess=false; settings.allowContentAccess=false
            settings.mixedContentMode=WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.setSupportMultipleWindows(false)
            if(!session?.userAgent.isNullOrBlank()) settings.userAgentString=session!!.userAgent
            CookieManager.getInstance().setAcceptThirdPartyCookies(this,false)
            webChromeClient=object:WebChromeClient() {
                override fun onConsoleMessage(message:ConsoleMessage):Boolean {diagnostics.console(message);return true}
            }
            webViewClient=object:WebViewClient() {
                override fun shouldOverrideUrlLoading(view:WebView,request:WebResourceRequest):Boolean {
                    if(!request.isForMainFrame) return false
                    val target=request.url
                    if(official(target)) {
                        campusPortalDocument(target.toString())?.let { document ->
                            view.loadUrl(document)
                            return true
                        }
                        return false
                    }
                    if(session!=null && view.url?.let { Uri.parse(it).host }=="ecykt.gdbtu.edu.cn" && request.hasGesture() && target.scheme in setOf("alipays","alipay","weixin")) {
                        try { context.startActivity(Intent(Intent.ACTION_VIEW,target)) } catch(_:Exception) { errorCallback("没有找到相应付款应用，请先安装后重试") }
                    }
                    if(target.scheme=="https") {
                        pageError="学校页面跳转到了暂未支持的站点，请反馈此提示"
                        if(com.beamjason.xiaorichang.BuildConfig.DEBUG) android.util.Log.w("CampusWeb","Blocked navigation host=${target.host}")
                    }
                    return true
                }
                override fun onPageStarted(view:WebView,url:String,icon:android.graphics.Bitmap?) {
                    diagnostics.event("started",url)
                    loading=true; currentUrl=url; pageError=null; loadSequence++
                    if(Uri.parse(url).host=="cas.gdbtu.edu.cn")portalDormAddress=""
                    if(com.beamjason.xiaorichang.BuildConfig.DEBUG) android.util.Log.d("CampusWeb","Started host=${Uri.parse(url).host}")
                }
                override fun onReceivedError(view:WebView,request:WebResourceRequest,error:WebResourceError) {
                    diagnostics.event(if(request.isForMainFrame)"document-error" else "resource-error",request.url.toString(),error.errorCode)
                    if(request.isForMainFrame) {
                        loading=false
                        pageError=when(error.errorCode) {
                            ERROR_HOST_LOOKUP -> "学校网址解析失败，请检查手机网络后重试"
                            ERROR_TIMEOUT -> "学校网页连接超时，请稍后重试"
                            ERROR_FAILED_SSL_HANDSHAKE -> "学校网页的安全连接失败，请检查手机日期与网络"
                            else -> "学校网页加载失败（${error.errorCode}），请重试"
                        }
                        if(com.beamjason.xiaorichang.BuildConfig.DEBUG) android.util.Log.w("CampusWeb","Main-frame error=${error.errorCode} host=${request.url.host}")
                    }
                }
                override fun onReceivedHttpError(view:WebView,request:WebResourceRequest,response:WebResourceResponse) {
                    diagnostics.event(if(request.isForMainFrame)"document-http" else "resource-http",request.url.toString(),response.statusCode)
                    if(request.isForMainFrame) {
                        loading=false; pageError="学校网页暂时不可用（HTTP ${response.statusCode}）"
                        if(com.beamjason.xiaorichang.BuildConfig.DEBUG) android.util.Log.w("CampusWeb","HTTP error=${response.statusCode} host=${request.url.host}")
                    }
                }
                override fun onReceivedSslError(view:WebView,handler:SslErrorHandler,error:android.net.http.SslError) {
                    handler.cancel(); loading=false; pageError="学校网页证书验证失败，请检查手机日期与网络后重试"
                }
                override fun onPageFinished(view:WebView,url:String) {
                    diagnostics.event("finished",url)
                    if(session==null && onLogin!=null && !loginPrimed && !primerInFlight && view.url==url && Uri.parse(url).path=="/__campus_native_login__") {
                        primerInFlight=true
                        val sequence=loadSequence
                        view.evaluateJavascript("""(()=>{if(!document.getElementById('campus-native-login-reset')||new URL(document.baseURI).origin!=='https://ecykt.gdbtu.edu.cn')return false;try{localStorage.removeItem('elecampus_state');localStorage.removeItem('elecampus_state_new_power');return true}catch{return false}})()""") {
                            if(view!==web || view.url!=campusPrimerURL || loadSequence!=sequence)return@evaluateJavascript
                            primerInFlight=false
                            if(it=="true"){loginPrimed=true;view.loadUrl(campusLoginUrl)}
                            else {loading=false;pageError="未能准备学校登录，请重试连接"}
                        }
                        return
                    }
                    // Redirected or cancelled pages may finish after the next
                    // navigation has started. Never reload their stale ticket.
                    val activeUrl=view.url ?: url
                    if(activeUrl==url)campusPortalDocument(url)?.let { document -> view.loadUrl(document); return }
                    loading=view.progress<100; currentUrl=activeUrl
                    if(loading)return
                    restorePortalViewport(view){diagnostics.event("viewport-restored",view.url)}
                    if(com.beamjason.xiaorichang.BuildConfig.DEBUG) android.util.Log.d("CampusWeb","Finished host=${Uri.parse(url).host}")
                    if(session!=null && !ready && !bootstrapping && !bootstrapFailed && Uri.parse(activeUrl).host=="ecykt.gdbtu.edu.cn") {
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
            if(session==null && onLogin!=null)loadDataWithBaseURL(campusPrimerURL,"<!doctype html><html><body><div id='campus-native-login-reset'>正在连接学校…</div></body></html>","text/html","UTF-8",campusPrimerURL)
            else loadUrl(if(session==null) campusLoginUrl else "https://ecykt.gdbtu.edu.cn/ykt-view/")
        }
    }
    LaunchedEffect(web,loadSequence) {
        val active=web ?: return@LaunchedEffect
        repeat(8){delay(500);restorePortalViewport(active){diagnostics.event("viewport-restored",active.url)}}
        delay(21_000)
        if(loading && pageError==null) pageError="学校网页加载时间较长，可以重试；若持续白屏，请反馈当前页面"
    }
    LaunchedEffect(web) {
        val active=web ?: return@LaunchedEffect
        if(com.beamjason.xiaorichang.BuildConfig.DEBUG)repeat(8){delay(2_000);diagnostics.sample(active)}
    }
    LaunchedEffect(web,loadSequence,automationRevision) {
        val active=web ?: return@LaunchedEffect
        if(session!=null || onLogin==null)return@LaunchedEffect
        automationStalled=false
        val sequence=loadSequence
        val script=automationScript ?: run{loginStatus="自动连接暂不可用，请使用备用方式";return@LaunchedEffect}
        repeat(60) {
            delay(750)
            if(loginCaptured)return@LaunchedEffect
            active.evaluateJavascript(script) {encoded->
                if(active!==web || loginCaptured || loadSequence!=sequence)return@evaluateJavascript
                runCatching {
                    val raw=JSONTokener(encoded).nextValue() as? String ?: return@runCatching
                    val result=JSONObject(raw)
                    when(result.optString("stage")) {
                        "portal-profile"->{
                            val address=result.optString("dormAddress")
                            if(Uri.parse(active.url).host=="portal.gdbtu.edu.cn" && address.isNotBlank() && address.length<=128 && address.none(Char::isISOControl)){
                                portalDormAddress=address
                                active.evaluateJavascript("window.__campusDormAcknowledged="+JSONObject.quote(address),null)
                            }
                        }
                        "login"->loginStatus="填写学校学工号和密码，登录后自动同步校园卡。"
                        "waiting-profile"->loginStatus="正在读取学校登记宿舍…"
                        "opening-wallet","waiting-portal"->loginStatus="正在进入一卡通…"
                        "waiting-wallet"->loginStatus="正在连接校园卡…"
                        "wallet-ready"->{loginStatus="正在同步校园卡…";readAuthenticatedLogin(true)}
                        "unsupported-entry","unsupported-origin"->{automationStalled=true;loginStatus="自动连接尚未完成，可重试或使用备用方式"}
                    }
                }
            }
        }
        if(!loginCaptured)automationStalled=true
    }
    Column(Modifier.fillMaxSize()) {
        Hint(if(session==null) loginStatus else "学校官方充值页面，请核对账号、宿舍和金额后付款。")
        if(loading) LinearProgressIndicator(Modifier.fillMaxWidth().padding(top=8.dp))
        pageError?.let { error ->
            Hint(error)
            TextButton(onClick={ pageError=null; loading=true; loadSequence++; web?.reload() }) { Text("重新加载") }
        }
        key(session,power) {
            val connecting=onLogin!=null && Uri.parse(currentUrl).host in setOf("portal.gdbtu.edu.cn","ecykt.gdbtu.edu.cn") && !automationStalled && pageError==null
            Box(Modifier.weight(1f).fillMaxWidth(),contentAlignment=Alignment.Center) {
            AndroidView(
                factory={viewContext -> createWebView(viewContext).also {web=it}},
                modifier=Modifier.fillMaxSize().alpha(if(connecting)0f else 1f),
                update={it.isEnabled=!connecting;it.importantForAccessibility=if(connecting)android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS else android.view.View.IMPORTANT_FOR_ACCESSIBILITY_AUTO},
                onRelease={released ->
                    released.stopLoading(); released.webViewClient=WebViewClient(); released.destroy()
                    if(web===released)web=null
                }
            )
                if(connecting)Column(horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(16.dp)) {
                    CircularProgressIndicator();Text("正在连接校园卡…")
                }
            }
        }
        if(onLogin!=null) {
            if(automationStalled)ActionButton(if(readingLogin)"正在同步…" else "重试自动连接",enabled=!readingLogin) {loginCaptured=false;automationRevision++}
            if(automationStalled || manualLogin)TextButton({manualLogin=!manualLogin}){Text("备用方式")}
            if(manualLogin) {
                Hint("若自动连接未完成，可手动进入学校一卡通，再读取当前页面。")
                TextButton({readAuthenticatedLogin(false)},enabled=!loading && !readingLogin && Uri.parse(currentUrl).host=="ecykt.gdbtu.edu.cn"){Text("从当前一卡通页面读取")}
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
