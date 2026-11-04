package com.beamjason.xiaorichang

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File
import androidx.activity.ComponentActivity
import androidx.activity.compose.*
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.ble.mayResumeBleAction
import com.beamjason.xiaorichang.ui.*
import com.beamjason.xiaorichang.net.PaymentDestination
import com.beamjason.xiaorichang.net.ImmediatePolling
import com.beamjason.xiaorichang.net.mayOpenPendingPayment
import kotlinx.coroutines.*

class MainActivity:ComponentActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if(Build.VERSION.SDK_INT>=29) window.isNavigationBarContrastEnforced=false
        setContent { NativeTheme { CampusApp(this) } }
    }
}
private data class PendingPayment(val destination:PaymentDestination.Checkout,val accountId:String,val orderId:String)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CampusApp(activity:ComponentActivity,vm:CampusViewModel=viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val backdrop=rememberLayerBackdrop()
    val appearance=remember {activity.getSharedPreferences("appearance",android.content.Context.MODE_PRIVATE)}
    var glassEnabled by remember {mutableStateOf(appearance.getBoolean("glass",true))}
    var mode by remember {mutableStateOf(glassMode(activity,glassEnabled))}
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var page by rememberSaveable { mutableStateOf(if(state.setupCount==0) "setup" else "") }
    val scope=rememberCoroutineScope();val snackbar=remember { SnackbarHostState() }
    val laundryReminders=remember {LaundryReminders(activity)}
    var remindersEnabled by remember {mutableStateOf(laundryReminders.enabled)}
    val notificationPermission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        laundryReminders.setEnabled(granted);remindersEnabled=granted
        if(granted)vm.refreshOrder() else vm.notice("通知未获允许，请在系统设置中允许校日常发送通知")
    }
    fun setLaundryReminders(value:Boolean) {
        if(value && Build.VERSION.SDK_INT>=33 && ContextCompat.checkSelfPermission(activity,Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        else {
            val allowed=!value || androidx.core.app.NotificationManagerCompat.from(activity).areNotificationsEnabled()
            laundryReminders.setEnabled(value && allowed);remindersEnabled=value && allowed
            if(!allowed)vm.notice("系统通知已关闭，请在设置中允许校日常发送通知")
            else if(value)vm.refreshOrder()
        }
    }
    fun navigate(target:String) { if(target=="orders") {tab=1;page=""} else page=target }
    val permissions=remember { if(Build.VERSION.SDK_INT>=31) arrayOf(Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION) }
    // A recreated Activity must not replay a previously requested transaction.
    var pendingBle by remember { mutableStateOf("") }
    val bleLauncher=rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val allowed=permissions.all { p -> ContextCompat.checkSelfPermission(activity,p)==PackageManager.PERMISSION_GRANTED }
        val operation=pendingBle;pendingBle=""
        if(allowed && mayResumeBleAction(operation,page)) when(operation) {"scan"->vm.scanWater();"inspect"->vm.inspectConfiguredWater();"review"->vm.reviewWater();"start"->vm.operateWater(false);"finish"->vm.operateWater(true)}
        else if(allowed) vm.notice("权限已更新，请回到原页面重新操作")
        else vm.notice(if(Build.VERSION.SDK_INT>=31) "需要附近设备权限才能连接热水水控，可在系统设置中允许" else "此安卓版本需要定位权限来查找蓝牙水控，可在系统设置中允许")
    }
    fun withBle(action:String) {
        if(permissions.any { ContextCompat.checkSelfPermission(activity,it)!=PackageManager.PERMISSION_GRANTED }) { pendingBle=action;bleLauncher.launch(permissions) }
        else when(action) {"scan"->vm.scanWater();"inspect"->vm.inspectConfiguredWater();"review"->vm.reviewWater();"start"->vm.operateWater(false);"finish"->vm.operateWater(true)}
    }
    fun exportDiagnostics() {scope.launch {
        try {
            val report=vm.waterDiagnosticReport()
            val uri=withContext(Dispatchers.IO) {
                val directory=File(activity.cacheDir,"water-diagnostics").apply{mkdirs()}
                val file=File(directory,"CampusDaily-water-diagnostics.json").apply{writeText(report)}
                FileProvider.getUriForFile(activity,"${BuildConfig.APPLICATION_ID}.fileprovider",file)
            }
            val send=Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM,uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(Intent.createChooser(send,"分享热水诊断"))
        } catch(_:Exception){vm.notice("诊断文件暂时无法分享，请稍后重试")}
    }}
    fun exportPassive() {scope.launch {
        try {
            val uri=withContext(Dispatchers.IO) {
                val report=com.beamjason.xiaorichang.ble.WaterPassiveCapture.report(activity)
                val directory=File(activity.cacheDir,"water-diagnostics").apply{mkdirs()}
                val file=File(directory,"CampusDaily-water-passive-private.json").apply{writeText(report)}
                FileProvider.getUriForFile(activity,"${BuildConfig.APPLICATION_ID}.fileprovider",file)
            }
            val send=Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM,uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(Intent.createChooser(send,"导出机身关水原始记录"))
        } catch(_:Exception){vm.notice("原始记录暂未生成，请完成现场操作后再导出")}
    }}
    val cameraLauncher=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { if(it)page="scanner" else vm.notice("需要相机权限才能扫描机身二维码，也可以粘贴二维码链接") }
    fun scan() {
        if(state.account==null) {page="laundryLogin";return}
        if(ContextCompat.checkSelfPermission(activity,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)page="scanner" else cameraLauncher.launch(Manifest.permission.CAMERA)
    }
    var platformOnlyImport by rememberSaveable {mutableStateOf(false)}
    val importer=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if(uri!=null)scope.launch {
            try {
                val text=withContext(Dispatchers.IO) { activity.contentResolver.openInputStream(uri)?.use { input ->
                    val out=java.io.ByteArrayOutputStream();val buf=ByteArray(4096)
                    while(true) {val n=input.read(buf);if(n<0)break;require(out.size()+n<=65536){"配置文件超过大小限制"};out.write(buf,0,n)}
                    out.toString("UTF-8") } ?: error("无法读取所选文件") }
                vm.importConfig(text,platformOnlyImport)
            } catch(e:Exception) {vm.notice(message(e))}
        }
    }
    // Payment URLs are held only in this Activity's memory and are never restored
    // across recreation. A user explicitly selects one handoff for the same order.
    var pendingPayment by remember { mutableStateOf<PendingPayment?>(null) }
    var handoffError by remember { mutableStateOf(false) }
    fun handoff(destination:PaymentDestination,browser:Boolean=false,offer:PendingPayment?=null) {scope.launch {
        try {
            if(offer!=null) {
                val current=vm.state.value
                if(!mayOpenPendingPayment(current.checkout,current.account,offer.accountId,offer.orderId)) {
                    vm.notice("订单状态已变化，请刷新核对后再付款");return@launch
                }
            }
            val result=launchPayment(activity,destination,browser)
            if(result.noHandler && offer!=null && !browser) {
                handoffError=true;pendingPayment=offer
            } else vm.notice(result.message)
            vm.refreshOrder()
        } catch(e:Exception){vm.notice(message(e))}
    }}
    fun payOrder() {vm.payOrder {destination->
        if(destination is PaymentDestination.Checkout){
            val record=vm.state.value.checkout
            val id=record?.orderId
            if(record==null || id==null)vm.notice("订单状态已变化，请刷新核对后再付款")
            else {handoffError=false;pendingPayment=PendingPayment(destination,record.accountId,id)}
        }
        else handoff(destination)
    }}
    fun import() {platformOnlyImport=false;importer.launch(arrayOf("application/json","application/octet-stream","*/*"))}
    fun importPlatform() {platformOnlyImport=true;importer.launch(arrayOf("application/json","application/octet-stream","*/*"))}
    pendingPayment?.let { offer ->
        AlertDialog(onDismissRequest={pendingPayment=null},title={Text("选择付款打开方式")},
            text={Text(if(handoffError) "系统没有打开支付宝。可尝试浏览器中转；卓易通能否唤起鸿蒙支付宝需视设备而定。" else "可直接打开支付宝。鸿蒙卓易通用户也可尝试浏览器中转。付款后请返回核对订单。")},
            confirmButton={TextButton(onClick={pendingPayment=null;handoff(offer.destination,offer=offer)}){Text("打开支付宝")}},
            dismissButton={Row {
                TextButton(onClick={pendingPayment=null;handoff(offer.destination,true,offer)}){Text("浏览器中转")}
                TextButton(onClick={pendingPayment=null}){Text("关闭")}
            }})
    }
    val updates=remember{AppUpdates(activity.applicationContext)}
    val updateState by updates.state.collectAsStateWithLifecycle()
    fun openUpdate(){updateState.url?.let{activity.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(it)))}}
    if(updateState.prompt)AlertDialog(onDismissRequest=updates::dismiss,title={Text("发现新版本")},text={Text(updateState.message)},confirmButton={TextButton({updates.dismiss();openUpdate()}){Text("查看更新")}},dismissButton={TextButton(updates::dismiss){Text("稍后再说")}})
    val immediateKey=state.checkout?.let{if(ImmediatePolling.needed(it))"${it.orderId}:${it.startAttempt}" else "regular"} ?: "regular"
    LaunchedEffect(immediateKey) {
        var activeSince=System.currentTimeMillis();var wasActive=false
        while(isActive && ImmediatePolling.needed(vm.state.value.checkout)) {
            val active=activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            if(active){if(!wasActive)activeSince=System.currentTimeMillis();vm.refreshOrder(false)}
            wasActive=active;delay(ImmediatePolling.interval(vm.state.value.checkout,activeSince))
        }
    }
    LaunchedEffect(Unit) {vm.resume()}
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {scope.launch{updates.check()};vm.resume();laundryReminders.restore();mode=glassMode(activity,glassEnabled)}
    LaunchedEffect(page,tab,state.campus.owner,state.water.hasPlatform) {
        if(page=="powerSetup" && state.campus.configured)vm.loadPower()
        if(page=="dorm" && state.campus.configured && state.water.hasPlatform && state.dormSetup.levels.isEmpty())vm.loadDorm()
        if(page=="laundry")vm.refreshWasher()
        while(isActive) {
            delay(30_000)
            if(!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED))continue
            if(page=="laundry")vm.refreshWasher(force=false)
            if(tab==1 || page=="laundry" || laundryReminders.enabled)vm.refreshOrder(false)
        }
    }
    LaunchedEffect(state.message) {state.message?.let {snackbar.showSnackbar(it);vm.notice(null)}}
    BackHandler(page.isNotBlank()) {page=if(page=="scanner")"laundry" else if(page in setOf("rechargeCard","rechargePower"))"recharge" else ""}
    if(page=="scanner") {BarcodeCamera(onFound={page="laundry";vm.scanWasher(it)},onClose={page="laundry"},onError=vm::notice);return}
    val titles=mapOf("water" to "热水洗澡","laundry" to "洗衣机","setup" to "首次配置","dorm" to "宿舍与水控","powerSetup" to "绑定宿舍电表","login" to "连接校园卡","laundryLogin" to "U净登录","recharge" to "校园充值","rechargeCard" to "校园卡充值","rechargePower" to "宿舍电费充值","import" to "导入热水配置","washerSetup" to "常用洗衣机","reminders" to "洗衣提醒","updates" to "版本与更新","advanced" to "故障排查","usage" to "快捷使用")
    // WebView draws through Android's native view hierarchy. Do not record its
    // content into the Compose glass backdrop; vendor GPU paths can retain a
    // blank frame while the DOM continues loading normally.
    val nativeBrowserPage=page in setOf("login","rechargeCard","rechargePower")
    Scaffold(containerColor=MaterialTheme.colorScheme.background,contentWindowInsets=WindowInsets.safeDrawing,
        topBar={CampusHeader(titles[page] ?: listOf("校园生活","最近订单","设备与设置")[tab],large=page.isBlank() && tab!=2,back=if(page.isNotBlank())({page=if(page in setOf("rechargeCard","rechargePower"))"recharge" else ""})else null,settings=if(page.isEmpty() && tab==0)({tab=2})else null,refresh=if(page=="laundry")({vm.refreshWasher()})else null)},
        bottomBar={RefinedTabBar(tab,{tab=it;page=""},backdrop,if(nativeBrowserPage)GlassMode.SOLID else mode)},
        snackbarHost={SnackbarHost(snackbar)}) {padding ->
        val contentModifier=Modifier.fillMaxSize().then(if(nativeBrowserPage)Modifier else Modifier.layerBackdrop(backdrop))
        Box(contentModifier.background(MaterialTheme.colorScheme.background)) {
        when(page) {
            "reminders"->ReminderSettingsScreen(padding,remindersEnabled,::setLaundryReminders){runCatching{laundryReminders.test()}.onSuccess{vm.notice("已安排10秒测试提醒，请切到后台查看")}.onFailure{vm.notice(message(it))}}
            "updates"->UpdateSettingsScreen(padding,updateState,{updates.setEnabled(it)},{scope.launch{updates.check(true)}},::openUpdate,{activity.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://jasonbeam.github.io/campus-daily/")))})
            "advanced"->AdvancedSettingsScreen(state,padding,::navigate,glassEnabled,{enabled->glassEnabled=enabled;appearance.edit().putBoolean("glass",enabled).apply();mode=glassMode(activity,enabled)},::exportDiagnostics,{navigate("water");withBle("review")},::exportPassive)
            "usage"->Page(padding){Group{NativeText("在日常页打开热水或洗衣机，使用已保存的配置。");Hint("更换宿舍、重新登录或添加机器，可进入账号与设备设置。")}}
            "recharge"->RechargeMenuScreen(padding){browser->
                val target=if(browser)"https://wxmpurl.cn/I0xUgrvZt1g" else "weixin://dl/business/?t=I0xUgrvZt1g"
                try { activity.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(target))) }
                catch(_:android.content.ActivityNotFoundException){vm.notice("未能打开微信，请确认已安装微信，或使用官方中转页。")}
                catch(_:SecurityException){vm.notice("系统阻止打开入口，请在微信搜索学校官方服务。")}
            }
            "water"->WaterScreen(state,padding,::navigate,inspect={withBle("inspect")},review={withBle("review")}){finish->withBle(if(finish)"finish" else "start")}
            "setup"->SetupScreen(state,padding,::navigate)
            "dorm"->DormScreen(state,padding,vm,{withBle("scan")},::importPlatform,::navigate,onSaved={if(page=="dorm"){tab=0;page=""}})
            "powerSetup"->PowerSetupScreen(state,padding,vm,::navigate)
            "washerSetup"->WasherSetupScreen(state,padding,LaundryActions(vm::selectWasher,vm::scanWasher,{vm.refreshWasher()},vm::createOrder),::navigate,::scan)
            "laundryLogin"->LaundryLoginScreen(state,padding,vm)
            "laundry"->LaundryScreen(state,padding,LaundryActions(vm::selectWasher,vm::scanWasher,{vm.refreshWasher()},vm::createOrder,{vm.refreshOrder()},vm::cancelOrder,::payOrder,vm::createImmediateOrder),::navigate,::scan)
            "login"->Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).padding(horizontal=12.dp)) {OfficialBrowser(onLogin={value->vm.acceptLogin(value){page=if(value.portalDormAddress.isNotBlank())"dorm" else "setup"}},onError=vm::notice)}
            "import"->Page(padding){Group {Text("导入一次热水配置",style=MaterialTheme.typography.titleLarge);Hint("选择开发者提供的平台配置，或你本人的 waterconfig 文件。之后通过学校账号选择自己的宿舍。");ActionButton("选择配置文件",onClick=::import)}}
            else->when(tab) {
                0->HomeScreen(state,padding,::navigate){vm.refresh(true)}
                1->OrdersScreen(state,padding,::navigate,{vm.refreshOrder()},vm::cancelOrder,::payOrder)
                else->DevicesScreen(state,padding,::navigate,remindersEnabled,updateState.url!=null)
            }
        }
        }
    }
}
