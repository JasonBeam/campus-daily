package com.beamjason.xiaorichang

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
import kotlinx.coroutines.*

class MainActivity:ComponentActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if(Build.VERSION.SDK_INT>=29) window.isNavigationBarContrastEnforced=false
        setContent { NativeTheme { CampusApp(this) } }
    }
}

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
    fun payOrder() {vm.payOrder {destination->scope.launch {try {vm.notice(launchPayment(activity,destination));vm.refreshOrder()}catch(e:Exception){vm.notice(message(e))}}}}
    fun import() {platformOnlyImport=false;importer.launch(arrayOf("application/json","application/octet-stream","*/*"))}
    fun importPlatform() {platformOnlyImport=true;importer.launch(arrayOf("application/json","application/octet-stream","*/*"))}
    LaunchedEffect(Unit) {vm.resume()}
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {vm.resume();mode=glassMode(activity,glassEnabled)}
    LaunchedEffect(page,tab,state.campus.owner,state.water.hasPlatform) {
        if(page=="powerSetup" && state.campus.configured)vm.loadPower()
        if(page=="dorm" && state.campus.configured && state.water.hasPlatform && state.dormSetup.levels.isEmpty())vm.loadDorm()
        if(page=="laundry")vm.refreshWasher()
        if(page in setOf("rechargeCard","rechargePower"))vm.prepareRecharge()
        while(isActive) {delay(30_000);if(page=="laundry")vm.refreshWasher(force=false);if(tab==1 || page=="laundry")vm.refreshOrder(false)}
    }
    LaunchedEffect(state.message) {state.message?.let {snackbar.showSnackbar(it);vm.notice(null)}}
    BackHandler(page.isNotBlank()) {page=if(page=="scanner")"laundry" else ""}
    if(page=="scanner") {BarcodeCamera(onFound={page="laundry";vm.scanWasher(it)},onClose={page="laundry"},onError=vm::notice);return}
    val titles=mapOf("water" to "热水洗澡","laundry" to "洗衣机","setup" to "首次配置","dorm" to "宿舍与水控","powerSetup" to "绑定宿舍电表","login" to "连接校园卡","laundryLogin" to "U净登录","rechargeCard" to "校园卡充值","rechargePower" to "宿舍电费充值","import" to "导入热水配置","washerSetup" to "常用洗衣机")
    // WebView draws through Android's native view hierarchy. Do not record its
    // content into the Compose glass backdrop; vendor GPU paths can retain a
    // blank frame while the DOM continues loading normally.
    val nativeBrowserPage=page in setOf("login","rechargeCard","rechargePower")
    Scaffold(containerColor=MaterialTheme.colorScheme.background,contentWindowInsets=WindowInsets.safeDrawing,
        topBar={CampusHeader(titles[page] ?: listOf("校园生活","最近订单","设备与设置")[tab],large=page.isBlank() && tab!=2,back=if(page.isNotBlank())({page=""})else null,settings=if(page.isEmpty() && tab==0)({tab=2})else null,refresh=if(page=="laundry")({vm.refreshWasher()})else null)},
        bottomBar={RefinedTabBar(tab,{tab=it;page=""},backdrop,if(nativeBrowserPage)GlassMode.SOLID else mode)},
        snackbarHost={SnackbarHost(snackbar)}) {padding ->
        val contentModifier=Modifier.fillMaxSize().then(if(nativeBrowserPage)Modifier else Modifier.layerBackdrop(backdrop))
        Box(contentModifier.background(MaterialTheme.colorScheme.background)) {
        when(page) {
            "water"->WaterScreen(state,padding,::navigate,inspect={withBle("inspect")},review={withBle("review")}){finish->withBle(if(finish)"finish" else "start")}
            "setup"->SetupScreen(state,padding,::navigate)
            "dorm"->DormScreen(state,padding,vm,{withBle("scan")},::importPlatform,::navigate,onSaved={if(page=="dorm"){tab=0;page=""}})
            "powerSetup"->PowerSetupScreen(state,padding,vm,::navigate)
            "washerSetup"->WasherSetupScreen(state,padding,LaundryActions(vm::selectWasher,vm::scanWasher,{vm.refreshWasher()},vm::createOrder),::navigate,::scan)
            "laundryLogin"->LaundryLoginScreen(state,padding,vm)
            "laundry"->LaundryScreen(state,padding,LaundryActions(vm::selectWasher,vm::scanWasher,{vm.refreshWasher()},vm::createOrder,{vm.refreshOrder()},vm::cancelOrder,::payOrder),::navigate,::scan)
            "login"->Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).padding(horizontal=12.dp)) {OfficialBrowser(onLogin={value->vm.acceptLogin(value){page=if(value.portalDormAddress.isNotBlank())"dorm" else "setup"}},onError=vm::notice)}
            "rechargeCard","rechargePower"->Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).padding(horizontal=12.dp)) {
                if("recharge" in state.busy) {LinearProgressIndicator(Modifier.fillMaxWidth());Hint("正在确认学校登录…")}
                val session=state.webSession
                if(session!=null)key(session,page){OfficialBrowser(session,power=page=="rechargePower",onError=vm::notice)}
                else if("recharge" !in state.busy)Group {Text("暂时无法打开充值");Hint("请重试；如果登录已过期，先重新登录学校账号。");ActionButton("重试",onClick=vm::prepareRecharge);TextButton({page="login"}){Text("重新登录学校账号")}}
            }
            "import"->Page(padding){Group {Text("导入一次热水配置",style=MaterialTheme.typography.titleLarge);Hint("选择开发者提供的平台配置，或你本人的 waterconfig 文件。之后通过学校账号选择自己的宿舍。");ActionButton("选择配置文件",onClick=::import)}}
            else->when(tab) {
                0->HomeScreen(state,padding,::navigate){vm.refresh(true)}
                1->OrdersScreen(state,padding,::navigate,{vm.refreshOrder()},vm::cancelOrder,::payOrder)
                else->DevicesScreen(state,padding,::navigate,glassEnabled,onGlassChange={enabled ->
                    glassEnabled=enabled;appearance.edit().putBoolean("glass",enabled).apply();mode=glassMode(activity,enabled)
                },refresh={vm.refresh(true)},exportDiagnostics=::exportDiagnostics,review={navigate("water");withBle("review")})
            }
        }
        }
    }
}
