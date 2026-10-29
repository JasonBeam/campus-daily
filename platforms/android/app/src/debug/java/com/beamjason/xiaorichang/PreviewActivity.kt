package com.beamjason.xiaorichang

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.ui.*

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.graphics.Color
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop

/** Debug-only fixture renderer. No repository, credentials or network client. */
class PreviewActivity:ComponentActivity() {
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState);enableEdgeToEdge()
        if(android.os.Build.VERSION.SDK_INT>=29)window.isNavigationBarContrastEnforced=false
        val dark=intent.getStringExtra("mode")=="dark"
        androidx.core.view.WindowInsetsControllerCompat(window,window.decorView).apply {
            isAppearanceLightStatusBars=!dark;isAppearanceLightNavigationBars=!dark
        }
        val initial=intent.getStringExtra("page") ?: "home"
        val effect=when(intent.getStringExtra("glass")){"solid"->GlassMode.SOLID;"frosted"->GlassMode.FROSTED;else->glassMode(this,true)}
        val refined=intent.getBooleanExtra("refined",true)
        setContent {NativeTheme(dark){PreviewLayout(initial,effect,refined)}}
    }
}

@Composable
fun PreviewLayout(initial:String,mode:GlassMode=GlassMode.LIQUID,refined:Boolean=true) {
    var page by rememberSaveable(initial) {mutableStateOf(initial)}
    val s=remember(page){previewFixture(page=="laundry-running")}
    val backdrop=rememberLayerBackdrop()
    val tab=when(page){"orders"->1;"devices","setup","setup-complete","washerSetup","dorm-matched"->2;else->0}
    val root=page in setOf("home","orders","devices")
    val title=when(page){"dorm-matched"->"校园登录与宿舍";"water"->"热水洗澡";"laundry","laundry-running"->"洗衣机";"setup","setup-complete"->"首次配置";"orders"->"最近订单";"devices"->"设备与设置";else->"校园生活"}
    Scaffold(containerColor=MaterialTheme.colorScheme.background,contentWindowInsets=WindowInsets.safeDrawing,
        topBar={CampusHeader(title,large=root && page!="devices",back=if(!root)({page="home"})else null,settings=if(page=="home")({page="devices"})else null,refresh=if(page in setOf("laundry","laundry-running"))({})else null)},
        bottomBar={if(refined)RefinedTabBar(tab,{page=listOf("home","orders","devices")[it]},backdrop,mode) else CampusTabBar(tab,{page=listOf("home","orders","devices")[it]},backdrop,mode)}) {padding->
        Box(Modifier.fillMaxSize().layerBackdrop(backdrop).background(MaterialTheme.colorScheme.background)) {
                when(page){
                    "dorm-matched"->DormSetupContent(matchedDormFixture(),padding,DormActions())
                    "water"->WaterScreen(s,padding,{page=it},operate={})
                    "laundry","laundry-running"->LaundryScreen(s,padding,LaundryActions(),{page=it},{})
                    "setup"->SetupScreen(CampusUiState(),padding,{page=it})
                    "setup-complete"->SetupScreen(s,padding,{page=it})
                    "orders"->OrdersScreen(s,padding,{page=it},{},{},{})
                    "devices"->DevicesScreen(s,padding,{page=it})
                    else->HomeScreen(s,padding,{page=it},{})
                }
        }
    }
}
fun previewFixture(running:Boolean=false):CampusUiState {
    val now=System.currentTimeMillis()
    val c=CampusConfig("demo","demo-placeholder","demo","demo-card",dorm="1栋301",buildingId="demo",meterId="demo")
    val program=WasherProgram(1,"普通洗",35,190)
    val washer=WasherSnapshot("demo-washer","01","6.5kg波轮机","宿舍洗衣区",0,true,listOf(program,WasherProgram(2,"小件洗",25,170),WasherProgram(3,"单脱水",10,100),WasherProgram(4,"大件洗",61,220)),"demo-store",1)
    val order=LaundryOrder("demo-order","demo-washer",if(running)"40" else "50","1",1,"1.90",if(running)1380 else null,null,"")
    return CampusUiState(campus=c,water=WaterSettings("demo","demo","demo","demo","00112233","DEMO",1,room="1栋301"),account=UjingAccount("demo","demo","demo-placeholder","demo","demo"),
        washers=listOf(SavedWasher("demo-washer","","洗衣机 01","01")),selectedWasher="demo-washer",washer=if(running)washer.copy(state=1)else washer,
        cache=BalanceCache(c.owner,"36.80",now,PowerMeter("demo","1栋301","42.6","23.43","3.2",""),now),
        waterSession=ShowerSession(ShowerStage.SETTLED,"demo","demo",payFen=128,endedAt=now),
        checkout=CheckoutRecord("demo","demo-washer",1,"普通洗",190,stage=if(running)CheckoutStage.CREATED else CheckoutStage.COMPLETED,orderId="demo-order",order=order,updatedAt=now),storageIssue=false)
}

fun matchedDormFixture():CampusUiState {
    val original=previewFixture();val c=original.campus.copy(portalDormAddress="示例校区1栋2号3层301房")
    val machine=DormWater("AABBCCDD","1-301","BT19-S")
    return original.copy(campus=c,dormSetup=DormSetup(identity=DormIdentity("demo","demo"),
        levels=listOf(listOf(Option("c","示例校区")),listOf(Option("b","1栋")),listOf(Option("f","三楼")),listOf(Option("r","301"))),
        path=listOf(Option("c","示例校区"),Option("b","1栋"),Option("f","三楼"),Option("r","301")),
        machines=listOf(machine),selected=machine,suggestedPower=CampusPowerSuggestion("demo-building",original.cache.power!!),autoMatched=true))
}
