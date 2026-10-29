package com.beamjason.xiaorichang.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.Dp
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.ble.ShowerStage
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun Page(padding:PaddingValues=PaddingValues(),modifier:Modifier=Modifier,spacing:Dp=18.dp,top:Dp=20.dp,content:@Composable ColumnScope.()->Unit) {
    // Keep the scroll viewport above the interactive tab bar: a child can be
    // geometrically visible while its button is still covered by floating tabs.
    LazyColumn(modifier.fillMaxSize().padding(bottom=padding.calculateBottomPadding()),contentPadding=PaddingValues(start=20.dp,end=20.dp,
        top=padding.calculateTopPadding()+top,bottom=24.dp),horizontalAlignment=Alignment.CenterHorizontally) {
        item { Column(Modifier.widthIn(max=560.dp).fillMaxWidth(),verticalArrangement=Arrangement.spacedBy(spacing),content=content) }
    }
}

@Composable
fun NavRow(title:String,detail:String,icon:ImageVector=Icons.Default.Settings,done:Boolean=false,onClick:()->Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick=onClick).padding(vertical=10.dp).heightIn(min=56.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
        Icon(if(done) Icons.Default.CheckCircle else icon,null,tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(24.dp))
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(5.dp)) { NativeText(title,fontWeight=FontWeight.Medium); Hint(detail) }
        Icon(Icons.Default.ChevronRight,null,tint=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.size(14.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(s:CampusUiState,padding:PaddingValues,navigate:(String)->Unit,refresh:()->Unit) {
    PullToRefreshBox(isRefreshing=s.busy.any {it in setOf("card","power")},onRefresh=refresh) {
        Page(padding) {
            NativeText(s.campus.dorm.ifBlank { "尚未选择宿舍" },style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Group(padding=PaddingValues(start=16.dp,end=16.dp,top=6.dp,bottom=16.dp),spacing=16.dp) {
                Row(verticalAlignment=Alignment.CenterVertically) {
                    NativeText("双余额",style=MaterialTheme.typography.titleMedium,modifier=Modifier.weight(1f))
                    PlainAction(if(s.campus.buildingId.isBlank())"绑定电表" else "电表设置"){navigate("powerSetup")}
                }
                BoxWithConstraints {
                    val power:@Composable (Modifier)->Unit={ m -> Column(m,verticalArrangement=Arrangement.spacedBy(10.dp)) {
                        NativeText("宿舍电量",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        MetricValue(s.cache.power?.remaining?.let(::money) ?: "—","度")
                        Column(verticalArrangement=Arrangement.spacedBy(5.dp)) {
                            Hint("电费 "+(s.cache.power?.balance?.let {"¥${money(it)}"} ?: "未获取"))
                            Hint("昨日 "+(s.cache.power?.yesterday?.let {"${money(it)} 度"} ?: "未返回"))
                        }
                        Hint(if("power" in s.busy)"正在更新…" else if(s.cache.powerAt>0)"${if(s.powerError!=null)"上次" else "查询"} ${clock(s.cache.powerAt)}" else "尚未查询")
                        PlainAction("充电费 ↗"){navigate(if(!s.campus.configured)"login" else if(s.campus.buildingId.isBlank())"powerSetup" else "rechargePower")}
                        s.powerError?.let {Hint(it,true)}
                    } }
                    val card:@Composable (Modifier)->Unit={m -> Column(m,verticalArrangement=Arrangement.spacedBy(10.dp)) {
                        NativeText("校园卡",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        MetricValue(s.cache.card?.let(::money) ?: "—","元")
                        Column(verticalArrangement=Arrangement.spacedBy(5.dp)) {Hint("校园消费余额");Hint(if(s.cardError!=null)"上次数据" else if("card" in s.busy)"正在更新…" else if(s.cache.cardAt>0)"已更新" else "等待查询")}
                        Hint(if(s.cache.cardAt>0)"查询 ${clock(s.cache.cardAt)}" else "尚未查询")
                        PlainAction("充校园卡 ↗"){navigate(if(s.campus.configured)"rechargeCard" else "login")}
                        s.cardError?.let {Hint(it,true)}
                    } }
                    if(maxWidth<286.dp || LocalDensity.current.fontScale>1.3f)Column(verticalArrangement=Arrangement.spacedBy(18.dp)){power(Modifier.fillMaxWidth());HorizontalDivider();card(Modifier.fillMaxWidth())}
                    else Row(horizontalArrangement=Arrangement.spacedBy(16.dp)){power(Modifier.weight(1f));card(Modifier.weight(1f))}
                }
            }
            if(s.setupCount<3) Group {NavRow("继续完成设置","账号、宿舍和常用洗衣机",Icons.Outlined.Tune){navigate("setup")}}
            BoxWithConstraints {
                val water:@Composable (Modifier)->Unit={m->ServiceFeature(m,"热水洗澡",s.water.room.ifBlank {s.campus.dorm},if(!s.water.configured)"待配置" else if(s.unresolvedWater)waterLabel(s) else "可连接",CampusSymbols.Drop){navigate("water")}}
                val laundry:@Composable (Modifier)->Unit={m->ServiceFeature(m,"洗衣机",s.washer?.let {"常用 · ${it.number}号"} ?: "登录与扫码绑定",s.washer?.label ?: "待配置",CampusSymbols.Washer){navigate("laundry")}}
                if(maxWidth<302.dp || LocalDensity.current.fontScale>1.3f)Column(verticalArrangement=Arrangement.spacedBy(12.dp)){water(Modifier.fillMaxWidth());laundry(Modifier.fillMaxWidth())}
                else Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){water(Modifier.weight(1f));laundry(Modifier.weight(1f))}
            }
            if(s.unresolvedLaundry)Group {NavRow("洗衣订单",s.checkout?.order?.label ?: "订单结果待核对",Icons.Default.History){navigate("orders")}}
            s.waterSession?.takeIf {it.stage==ShowerStage.SETTLED}?.let {last->Group(padding=PaddingValues(16.dp)) {
                Row(verticalAlignment=Alignment.CenterVertically) {
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(5.dp)) {NativeText("上次热水 · 已结算",style=MaterialTheme.typography.bodyMedium);last.endedAt?.let {Hint(time(it))}}
                    last.payFen?.let {NativeText("¥${moneyFen(it)}",style=MaterialTheme.typography.bodyMedium,fontWeight=FontWeight.Medium)}
                }
            }}
            Hint("下拉刷新余额")
        }
    }
}

@Composable
private fun MetricValue(value:String,unit:String) {
    Row(verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(4.dp)) {
        BasicText(value,Modifier.weight(1f,fill=false),style=TextStyle(color=MaterialTheme.colorScheme.onSurface,fontSize=34.sp,lineHeight=40.sp,fontWeight=FontWeight.SemiBold,platformStyle=PlatformTextStyle(includeFontPadding=false),lineHeightStyle=LineHeightStyle(LineHeightStyle.Alignment.Center,LineHeightStyle.Trim.None)),maxLines=1,autoSize=TextAutoSize.StepBased(minFontSize=23.sp,maxFontSize=34.sp))
        NativeText(unit,Modifier.padding(bottom=5.dp),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ServiceFeature(modifier:Modifier,title:String,detail:String,status:String,icon:ImageVector,onClick:()->Unit) {
    Surface(modifier.clickable(onClick=onClick),shape=RoundedCornerShape(16.dp),color=MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            Icon(icon,null,tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(24.dp))
            Column(verticalArrangement=Arrangement.spacedBy(6.dp)){NativeText(title,style=MaterialTheme.typography.titleMedium);Hint(detail)}
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {NativeText(status,Modifier.weight(1f),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant);Icon(CampusSymbols.ArrowUpRight,null,Modifier.size(12.dp),tint=MaterialTheme.colorScheme.primary)}
        }
    }
}

fun waterLabel(s:CampusUiState):String = when(s.waterSession?.stage) {
    null -> if(s.water.configured) "已就绪" else "先选择宿舍与水控"
    ShowerStage.ACTIVE -> "已授权 · 可用水"
    ShowerStage.SETTLED -> "结算完成"
    ShowerStage.SETTLEMENT_PENDING -> "结算待核对"
    else -> "操作结果待核对"
}

@Composable
fun WaterScreen(s:CampusUiState,padding:PaddingValues,navigate:(String)->Unit,inspect:()->Unit={},operate:(Boolean)->Unit) {
    val stage=s.waterSession?.stage
    val finish=stage in setOf(ShowerStage.ACTIVE,ShowerStage.AUTHORIZATION_WRITE_PENDING)
    val start=stage==null || stage==ShowerStage.SETTLED
    var expanded by rememberSaveable {mutableStateOf(false)}
    Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
        Page(modifier=Modifier.weight(1f),spacing=24.dp) {
            Row {NativeText("宿舍热水",Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant);NativeText(s.water.room.ifBlank {s.campus.dorm},style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            Column(verticalArrangement=Arrangement.spacedBy(13.dp)) {
                Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(9.dp)) {
                    if("water" in s.busy)CircularProgressIndicator(Modifier.size(17.dp),strokeWidth=2.dp)
                    else Box(Modifier.size(7.dp).background(MaterialTheme.colorScheme.primary,RoundedCornerShape(50)))
                    NativeText(if("water" in s.busy)"正在连接水控…" else waterLabel(s),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)
                }
                NativeText(when{finish->"水控已确认授权。结束后请确认现场停水。";stage==ShowerStage.SETTLED->"服务器已确认结算";start->"靠近水控并打开蓝牙，即可开始本次用水。";else->"操作结果待核对，请查看现场和学校记录，暂不可再次开始。"},style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Group {Row(verticalAlignment=Alignment.CenterVertically) {
                NativeText("本次费用",Modifier.weight(1f),color=MaterialTheme.colorScheme.onSurfaceVariant)
                NativeText(if(stage==ShowerStage.SETTLED)s.waterSession.payFen?.let {"¥${moneyFen(it)}"} ?: "金额未返回" else "结算后显示",style=if(stage==ShowerStage.SETTLED)MaterialTheme.typography.titleLarge else MaterialTheme.typography.bodyMedium)
            }}
            s.waterSession?.takeIf {it.endedAt!=null}?.let {last->Group {
                NativeText("最近一次用水",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
                Row(verticalAlignment=Alignment.CenterVertically) {
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){NativeText("已结算",style=MaterialTheme.typography.bodyMedium);Hint(time(last.endedAt!!))}
                    last.payFen?.let {NativeText("¥${moneyFen(it)}",style=MaterialTheme.typography.bodyMedium)}
                }
            }}
            if(!s.water.configured)TextButton({navigate("dorm")}) {NativeText("设置校园账号与宿舍")}
            else Group {
                Row(Modifier.fillMaxWidth().heightIn(min=26.dp).clickable {expanded=!expanded},verticalAlignment=Alignment.CenterVertically) {NativeText("连接检查与设备信息",Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.primary);Icon(if(expanded)Icons.Default.ExpandMore else CampusSymbols.ChevronForward,null,Modifier.size(16.dp),tint=MaterialTheme.colorScheme.onSurface)}
                if(expanded) {
                    val canInspect=!s.storageIssue && !s.transactionBusy && !s.unresolvedWater
                    OutlinedButton(inspect,enabled=canInspect,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {
                        NativeText(if("verify" in s.busy)"正在核对…" else "扫描并核对本宿舍水控",
                            color=if(canInspect)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    s.waterInspection?.let{Hint(it)}
                    Hint("只读取设备编号，不会出水。")
                    Hint("水控编号 ${s.water.machineId}")
                    Hint(if(s.water.address!=null)"已保存核对结果；开始洗澡时会再次连接。" else "已保存宿舍配置，连接时仍需核对设备编号。")
                }
            }
        }
        Column(Modifier.widthIn(max=560.dp).fillMaxWidth().align(Alignment.CenterHorizontally).padding(horizontal=20.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(10.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            ActionButton(if(!s.water.configured)"配置宿舍与水控" else if(finish)"结束并结算" else if(start)"开始洗澡" else "等待核对",enabled=!s.storageIssue && !s.transactionBusy && (start || finish),busy="water" in s.busy,aligned=true) {if(!s.water.configured)navigate("dorm") else operate(finish)}
            Hint(if(finish)"结算完成前，请留在水控附近。" else "授权后，按水控上的出水键。")
        }
    }
}

@Composable
private fun FormLabel(text:String) {Box(Modifier.fillMaxWidth().height(40.dp).padding(horizontal=20.dp),contentAlignment=Alignment.CenterStart){NativeText(text,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}}

@Composable
private fun FormRow(title:String,value:String?=null,action:(()->Unit)?=null,blue:Boolean=false) {
    Row(Modifier.fillMaxWidth().heightIn(min=52.dp).then(if(action!=null)Modifier.clickable(onClick=action)else Modifier).padding(horizontal=20.dp,vertical=14.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
        NativeText(title,Modifier.weight(1f),style=MaterialTheme.typography.bodyLarge,color=if(blue)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
        if(value!=null)NativeText(value,style=MaterialTheme.typography.bodyLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
        if(action!=null && !blue)Icon(CampusSymbols.ChevronForward,null,Modifier.size(12.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun DevicesScreen(s:CampusUiState,padding:PaddingValues,navigate:(String)->Unit,glassEnabled:Boolean=true,onGlassChange:(Boolean)->Unit={},refresh:()->Unit={}) = Page(padding,spacing=0.dp,top=35.dp) {
    var advanced by rememberSaveable {mutableStateOf(false)}
    Surface(onClick={navigate("setup")},shape=RoundedCornerShape(26.dp),color=MaterialTheme.colorScheme.surface){
        Row(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=24.dp),verticalAlignment=Alignment.CenterVertically) {
            Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(8.dp)){Hint("首次配置");NativeText("账号与设备设置",style=MaterialTheme.typography.titleMedium);NativeText("跟着步骤登录、选宿舍、扫机器",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            Icon(CampusSymbols.ChevronForward,null,Modifier.size(12.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    Spacer(Modifier.height(17.dp));FormLabel("我的信息")
    Surface(shape=RoundedCornerShape(26.dp),color=MaterialTheme.colorScheme.surface){Column {
        FormRow("校园账号与宿舍",s.campus.dorm.ifBlank {"去登录"},{navigate(if(s.campus.configured)"dorm" else "login")})
        HorizontalDivider(Modifier.padding(horizontal=20.dp));FormRow("常用洗衣机",if(s.account!=null)"已登录 · ${s.washers.size} 台" else "去设置",{navigate(if(s.account==null)"laundryLogin" else "washerSetup")})
        HorizontalDivider(Modifier.padding(horizontal=20.dp));FormRow("更新校园卡余额",action=refresh,blue=true)
    }}
    Spacer(Modifier.height(17.dp));FormLabel("快捷使用")
    Surface(shape=RoundedCornerShape(26.dp),color=MaterialTheme.colorScheme.surface){NativeText("在「日常」页打开热水或洗衣机，使用已保存的配置。\n更换宿舍、重新登录或添加机器，可进入账号与设备设置。",Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=16.dp),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
    Spacer(Modifier.height(34.dp))
    Surface(shape=RoundedCornerShape(26.dp),color=MaterialTheme.colorScheme.surface){Column {
        FormRow("高级设置与故障排查",action={advanced=!advanced})
        if(advanced){
            Hint("通常优先使用上方账号与设备设置。")
            FormRow("重新登录学校账号",action={navigate("login")},blue=true)
            FormRow("导入内测热水配置",action={navigate("import")},blue=true)
            FormRow("宿舍电表",action={navigate("powerSetup")},blue=true)
            Row(Modifier.padding(horizontal=20.dp),verticalAlignment=Alignment.CenterVertically){NativeText("液态玻璃",Modifier.weight(1f));Switch(glassEnabled,onGlassChange)}
            NativeText("省电模式或低内存设备自动简化效果。个人配置通过 Android Keystore 加密保存在本机。",Modifier.padding(20.dp),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        HorizontalDivider(Modifier.padding(horizontal=20.dp));Row(Modifier.fillMaxWidth().heightIn(min=52.dp).padding(horizontal=20.dp),verticalAlignment=Alignment.CenterVertically){Hint("版本");Spacer(Modifier.weight(1f));Hint(com.beamjason.xiaorichang.BuildConfig.VERSION_NAME)}
    }}
}

@Composable
fun SetupScreen(s:CampusUiState,padding:PaddingValues,navigate:(String)->Unit) = Page(padding,spacing=24.dp) {
    Column(verticalArrangement=Arrangement.spacedBy(11.dp)) {
        NativeText("已完成 ${s.setupCount} / 3",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        NativeText(if(s.setupCount==3)"都准备好了" else "完成首次设置",fontSize=26.sp,lineHeight=34.sp,fontWeight=FontWeight.Bold)
        NativeText(if(!s.campus.configured)"先登录学校账号，再选择宿舍和常用洗衣机。" else if(!s.water.configured)"学校账号已登录，接着选择你的宿舍。" else "宿舍已保存，接着绑定常用洗衣机。",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        LinearProgressIndicator(progress={s.setupCount/3f},modifier=Modifier.fillMaxWidth(),trackColor=MaterialTheme.colorScheme.primary.copy(alpha=.12f))
    }
    Group(padding=PaddingValues(horizontal=16.dp),spacing=0.dp) {
        NavRow("学校账号",if(s.campus.configured)"已登录，可查询校园卡余额" else "登录后自动同步校园卡余额",Icons.Outlined.AccountCircle,s.campus.configured){navigate("login")}
        HorizontalDivider(Modifier.padding(start=40.dp))
        NavRow("选择宿舍与水控",s.water.room.ifBlank {"选择楼栋房间，确认自己的设备"},Icons.Outlined.Apartment,s.water.configured){navigate("dorm")}
        HorizontalDivider(Modifier.padding(start=40.dp))
        NavRow("绑定洗衣机",if(s.washers.isEmpty())"登录 U净，扫码保存常用机器" else "已保存 ${s.washers.size} 台机器",CampusSymbols.Washer,s.account!=null && s.washers.isNotEmpty()){navigate(if(s.account==null)"laundryLogin" else "washerSetup")}
    }
    ActionButton(if(s.setupCount==3)"完成设置" else if(!s.campus.configured)"登录并连接校园卡" else if(!s.water.configured)"继续选择宿舍" else if(s.account==null)"登录 U净" else "扫描洗衣机二维码") {
        navigate(if(s.setupCount==3)"" else if(!s.campus.configured)"login" else if(!s.water.configured)"dorm" else if(s.account==null)"laundryLogin" else "washerSetup")
    }
    Surface(onClick={navigate("powerSetup")},shape=RoundedCornerShape(16.dp),color=MaterialTheme.colorScheme.surface){
        Row(Modifier.fillMaxWidth().padding(16.dp),verticalAlignment=Alignment.CenterVertically){
            Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){NativeText("宿舍电费",style=MaterialTheme.typography.bodyMedium,fontWeight=FontWeight.Medium);Hint(if(s.campus.buildingId.isNotBlank())"电表已绑定，可更换" else "可选，完成后也能设置")}
            Icon(CampusSymbols.ChevronForward,null,Modifier.size(12.dp),tint=MaterialTheme.colorScheme.onSurface)
        }
    }
    Hint("这里只读取和保存配置，不会出水、下单或付款。")
}

data class DormActions(val reload:()->Unit={},val choose:(Option,Int)->Unit={_,_->},val select:(DormWater)->Unit={},val verify:(com.beamjason.xiaorichang.ble.BleCandidate)->Unit={},val save:()->Unit={},val provision:()->Unit={})

@Composable
fun DormScreen(s:CampusUiState,padding:PaddingValues,vm:CampusViewModel,requestScan:()->Unit,import:()->Unit,navigate:(String)->Unit,onSaved:()->Unit={}) {
    DormSetupContent(s,padding,DormActions(vm::loadDorm,vm::chooseDorm,vm::selectMachine,vm::verifyWater,{vm.saveDorm(onSaved)},vm::resume),requestScan,import,navigate,powerChoice=vm::choosePowerApartment,powerRetry={vm.matchPowerAutomatically(true)})
}

@Composable
fun DormSetupContent(s:CampusUiState,padding:PaddingValues,actions:DormActions,requestScan:()->Unit={},import:()->Unit={},navigate:(String)->Unit={},powerChoice:(CampusPowerCandidate)->Unit={},powerRetry:()->Unit={}) = Page(padding) {
    var expandedLevel by rememberSaveable { mutableIntStateOf(-1) }
    var showManualDorm by rememberSaveable {mutableStateOf(false)}
    var showOtherRadios by rememberSaveable { mutableStateOf(false) }
    if(s.campus.portalDormAddress.isNotBlank()) Group {
        NativeText("学校登记宿舍",style=MaterialTheme.typography.titleMedium)
        Hint(s.campus.portalDormAddress)
        if(s.dormSetup.autoMatched)Hint("已匹配热水宿舍，请核对后保存。")
    }
    AutomaticPowerContent(s,powerChoice,powerRetry)
    var search by rememberSaveable { mutableStateOf("") }
    var backupAccess by rememberSaveable {mutableStateOf(false)}
    val d=s.dormSetup; val busy="dorm" in s.busy || "verify" in s.busy || "saveDorm" in s.busy
    if(!d.autoMatched)Hint("登录学校账号后匹配本人宿舍；信息缺失时可手动选择。")
    if(d.serviceEnabled==false)Hint("在线身份和宿舍可配置；开始用水仍在验收，暂未开放。",true)
    if(!s.water.hasPlatform) Group {
        NativeText("自动连接热水",style=MaterialTheme.typography.titleMedium)
        Hint("完成学校登录后直接读取本人宿舍与水控，无需导入配置文件。")
        if(s.campus.configured)ActionButton("重试自动连接",enabled=!busy && !s.unresolvedWater,onClick=actions.reload)
        TextButton({backupAccess=!backupAccess}){NativeText("备用接入方式")}
        if(backupAccess){Hint("仅用于旧版迁移和开发排查，正常使用无需导入文件。");OutlinedButton(import){NativeText("导入热水接入文件")}}
    }
    if(!s.campus.configured) ActionButton("先登录学校账号") { navigate("login") }
    else if(s.water.hasPlatform) {
        OutlinedButton(actions.reload,enabled=!busy && !s.unresolvedWater,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) { NativeText(if(d.levels.isEmpty()) "读取我的宿舍信息" else "重新选择宿舍") }
        if(s.unresolvedWater) Hint("请先结束或核对当前热水会话，再更换水控。",true)
        if(d.autoMatched)Group(padding=PaddingValues(horizontal=16.dp),spacing=0.dp) {
            Row(Modifier.fillMaxWidth().heightIn(min=52.dp),verticalAlignment=Alignment.CenterVertically){NativeText("已匹配宿舍",Modifier.weight(1f));NativeText(PortalDormAddress.parse(s.campus.portalDormAddress)?.shortRoom ?: s.campus.dorm,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            HorizontalDivider()
            TextButton({showManualDorm=!showManualDorm},modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)){NativeText(if(showManualDorm)"收起宿舍选择" else "更换宿舍")}
        }
        if(!d.autoMatched || showManualDorm)d.levels.forEachIndexed { level,options ->
            Group {
                val selected=d.path.getOrNull(level)
                Row(verticalAlignment=Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {Hint(listOf("校区","楼栋","楼层","房间")[level]);if(selected!=null)NativeText(selected.name,fontWeight=FontWeight.Medium)}
                    if(selected!=null)TextButton({expandedLevel=if(expandedLevel==level)-1 else level;search=""},enabled=!busy){NativeText("更改")}
                }
                if(selected==null || expandedLevel==level) {
                    if(options.size>8)OutlinedTextField(search,{search=it},label={NativeText("搜索")},singleLine=true,modifier=Modifier.fillMaxWidth())
                    options.filter {search.isBlank() || it.name.contains(search,true)}.forEach {o->
                        ChoiceRow(o.name,selected==o,enabled=!busy){expandedLevel=-1;search="";actions.choose(o,level)}
                    }
                }
            }
        }
        if(d.path.size==4) Group {
            NativeText("选择自己的水控",style=MaterialTheme.typography.titleMedium)
            if(d.machines.isEmpty()) Hint("未返回设备，请核对宿舍后重新读取。")
            if(d.autoMatched && d.machines.size==1) {
                NativeText(d.machines.single().name,style=MaterialTheme.typography.bodyLarge)
                Hint("水控编号 ${d.machines.single().machineId}")
            } else d.machines.forEach { m -> ChoiceRow("${m.name} · ${m.machineId}",d.selected==m,enabled=!busy) { actions.select(m) } }
        }
        if(d.selected!=null) Group {
            NativeText("蓝牙核对",style=MaterialTheme.typography.titleMedium)
            Hint("靠近水控后自动读取编号，匹配本宿舍设备。")
            ActionButton(if(d.verifiedAddress!=null)"重新查找水控" else "查找本宿舍水控",
                enabled=!busy && !s.unresolvedWater,busy="verify" in s.busy,onClick=requestScan)
            if(d.checkingAddress!=null)Hint("正在核对附近设备 ${d.checkingIndex}/${d.candidates.size.coerceAtMost(16)}，请保持靠近水控…")
            val own=d.candidates.firstOrNull{it.address==d.verifiedAddress}
            if(own!=null) {
                NavRow("本宿舍水控","${d.selected.name} · 编号已核对",Icons.Default.Bluetooth,true){}
                val others=d.candidates.filter{it.address!=d.verifiedAddress}
                if(others.isNotEmpty())TextButton({showOtherRadios=!showOtherRadios}){NativeText(if(showOtherRadios)"收起其他附近设备" else "其他附近设备（${others.size}）")}
                if(showOtherRadios)others.forEach{c->Hint(if(d.readIdentities.containsKey(c.address))"其他水控 · 与本宿舍编号不匹配" else "其他附近设备 · 无需选择")}
            } else if(!busy)d.candidates.forEach { c ->
                if(d.readIdentities[c.address]?.equals(d.selected.machineId,true)==false)Hint("其他宿舍水控 · 编号不匹配")
                else NavRow("待确认的水控","信号 ${c.rssi} dBm · 点按重新核对",Icons.Default.Bluetooth){if(!busy)actions.verify(c)}
            }
            val previous = if(d.path.size==4 && d.identity!=null) previouslyVerifiedAddress(s.water,d.identity.studentId,d.identity.schoolId,d.selected.machineId,d.path[1].name+d.path[3].name) else null
            if(d.verifiedAddress==null && !busy) Hint(if(previous!=null) "已保留上次核对记录；连接时会再次核对编号。" else "尚未找到本宿舍水控。也可以先保存宿舍，稍后靠近设备再核对。")
            ActionButton(if(d.verifiedAddress!=null) "保存宿舍与已核对水控" else if(previous!=null) "保存并保留上次核对" else "保存宿舍，稍后核对",enabled=!busy && !s.unresolvedWater, onClick=actions.save)
        }
    }
    if(busy) LinearProgressIndicator(Modifier.fillMaxWidth())
}

@Composable
private fun AutomaticPowerContent(s:CampusUiState,choose:(CampusPowerCandidate)->Unit,retry:()->Unit) {
    if(s.matchingPower || s.powerChoices.isNotEmpty() || s.powerMatchIssue!=null || s.campus.buildingId.isNotBlank())Group {
        NativeText("宿舍电表",style=MaterialTheme.typography.titleMedium)
        when {
            s.matchingPower-> {LinearProgressIndicator(Modifier.fillMaxWidth());Hint("正在匹配电表，可以先保存热水宿舍。")}
            s.powerChoices.isNotEmpty()-> {
                Hint("学校目录里有同名楼栋，只需确认一次公寓。")
                s.powerChoices.forEach{candidate->OutlinedButton({choose(candidate)},modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)){NativeText(candidate.label)}}
            }
            s.campus.buildingId.isNotBlank()->Hint("电表已保存")
        }
        s.powerMatchIssue?.let{Hint(it);TextButton(retry){NativeText("重试匹配电表")}}
    }
}

@Composable
fun PowerSetupScreen(s:CampusUiState,padding:PaddingValues,vm:CampusViewModel,navigate:(String)->Unit) = Page(padding) {
    var search by rememberSaveable { mutableStateOf("") }
    val p=s.powerSetup; val busy="powerSetup" in s.busy || "saveMeter" in s.busy
    AutomaticPowerContent(s,vm::choosePowerApartment){vm.matchPowerAutomatically(true)}
    Hint("电表与热水水控分别绑定，请核对房间后保存。")
    if(!s.campus.configured) ActionButton("先登录学校账号") { navigate("login") }
    else {
        OutlinedButton({ search=""; vm.loadPower() },enabled=!busy,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) { NativeText("重新读取位置列表") }
        if(p.path.isNotEmpty()) NativeText(p.path.joinToString(" · "){it.name},style=MaterialTheme.typography.titleSmall)
        OutlinedTextField(search,{search=it},label={NativeText("搜索楼栋或房间")},modifier=Modifier.fillMaxWidth(),singleLine=true)
        if(busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if(p.options.isNotEmpty()) Group { p.options.filter { it.name.contains(search,true) }.forEach { o ->
            NavRow(o.name,"继续选择",Icons.Outlined.Apartment) { if(!busy) { search=""; vm.choosePower(o) } }
        } }
        if(p.meters.isNotEmpty()) Group { p.meters.filter { it.room.contains(search,true) }.forEach { m ->
            NavRow(m.room,"剩余 ${m.remaining} 度 · ¥${money(m.balance)} · 点击保存",Icons.Outlined.Bolt,s.campus.meterId==m.id) { if(!busy) vm.saveMeter(m) }
        } }
    }
}

@Composable
fun LaundryLoginScreen(s:CampusUiState,padding:PaddingValues,vm:CampusViewModel) = Page(padding) {
    // Do not put phone numbers or one-time codes in savedInstanceState.
    var phone by remember { mutableStateOf("") }; var code by remember { mutableStateOf("") }
    var cooldown by rememberSaveable { mutableLongStateOf(0L) }; var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(cooldown) { while(System.currentTimeMillis()<cooldown) { delay(1000); now=System.currentTimeMillis() } }
    Group {
        NativeText(if(s.account!=null) "U净已登录" else "登录 U净",style=MaterialTheme.typography.titleLarge)
        Hint("使用你本人的手机号和短信验证码，登录后即可保存多台常用洗衣机。")
        OutlinedTextField(phone,{phone=it.filter(Char::isDigit).take(11)},label={NativeText("手机号")},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Phone),singleLine=true,modifier=Modifier.fillMaxWidth())
        OutlinedTextField(code,{code=it.filter(Char::isDigit).take(8)},label={NativeText("短信验证码")},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.NumberPassword),singleLine=true,modifier=Modifier.fillMaxWidth())
        OutlinedButton({vm.sendCode(phone);cooldown=System.currentTimeMillis()+60_000;now=System.currentTimeMillis()},enabled=phone.length==11 && now>=cooldown && "sms" !in s.busy && !s.unresolvedLaundry,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) { NativeText(if(now<cooldown) "${((cooldown-now)/1000).coerceAtLeast(1)} 秒后重试" else "获取验证码") }
        ActionButton("登录并保存",enabled=phone.length==11 && code.length in 4..8 && !s.unresolvedLaundry,busy="laundryLogin" in s.busy) { vm.loginLaundry(phone,code); code="" }
    }
    if(s.unresolvedLaundry) Hint("当前有待处理洗衣订单，请完成或核对后再重新登录。",true)
    Hint("若官方要求额外验证，请先在 U净完成本人认证。")
}

@Composable
fun LaundryScreen(s:CampusUiState,padding:PaddingValues,actions:LaundryActions,navigate:(String)->Unit,scan:()->Unit) {
    var qr by remember {mutableStateOf("")}
    var selectedProgram by rememberSaveable(s.washer?.id) {mutableIntStateOf(-1)}
    var confirm by remember {mutableStateOf<WasherProgram?>(null)}
    var manage by rememberSaveable {mutableStateOf(false)}
    val w=s.washer;val busy=s.transactionBusy || "washer" in s.busy
    val program=w?.programs?.firstOrNull {it.id==selectedProgram} ?: w?.programs?.firstOrNull()
    Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
        Page(modifier=Modifier.weight(1f),spacing=20.dp) {
            if(s.account==null) Group {
                NativeText("尚未配置洗衣机",style=MaterialTheme.typography.titleLarge)
                Hint("先登录 U净，再扫码添加常用机器")
                ActionButton("登录 U净"){navigate("laundryLogin")}
            } else {
                if(w!=null) Group {
                    Row(horizontalArrangement=Arrangement.spacedBy(14.dp),verticalAlignment=Alignment.CenterVertically) {
                        Box(Modifier.size(52.dp).background(MaterialTheme.colorScheme.primary.copy(alpha=.08f),RoundedCornerShape(16.dp)),contentAlignment=Alignment.Center){Icon(CampusSymbols.Washer,null,Modifier.size(29.dp),tint=MaterialTheme.colorScheme.primary)}
                        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){NativeText("${w.number}号 · ${w.title}",style=MaterialTheme.typography.titleMedium);NativeText(w.store,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                    }
                    Row(verticalAlignment=Alignment.CenterVertically) {
                        NativeText("●  ${w.label}",Modifier.weight(1f),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.primary)
                        Hint(if("washer" in s.busy)"正在更新…" else if(s.washerError!=null)"上次状态" else "已更新")
                    }
                    Hint("查询于 ${clockSeconds(w.fetchedAt)}")
                    s.washerError?.let {Hint(it,true)}
                    if(w.state==1 && s.checkout?.deviceId!=w.id)Hint("这台机器正在使用，暂未取得剩余时间。")
                } else Group {
                    NativeText("等待设备信息",style=MaterialTheme.typography.titleLarge)
                    Hint("扫码保存常用机器，以后直接打开。")
                    ActionButton("添加洗衣机",onClick=scan)
                }
                if(s.checkout!=null && !s.unresolvedLaundry)Group(padding=PaddingValues(16.dp)){Row {NativeText(s.checkout.order?.label ?: "上次订单已结束",Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium);Hint(if(s.checkout.order?.unpaid==true)"未支付" else "已付款")}}
                if(s.checkout!=null && s.unresolvedLaundry)LaundryOrderCard(s,actions.refreshOrder,actions.cancel,actions.pay)
                if(w!=null && !s.unresolvedLaundry) {
                    Row(verticalAlignment=Alignment.CenterVertically) {NativeText("选择程序",Modifier.weight(1f),style=MaterialTheme.typography.titleLarge);Hint("按当前价格")}
                    Column(verticalArrangement=Arrangement.spacedBy(10.dp)) {
                        w.programs.forEach {p ->
                            val active=program?.id==p.id
                            Surface(onClick={selectedProgram=p.id},enabled=!busy && w.available,shape=RoundedCornerShape(16.dp),color=if(active)MaterialTheme.colorScheme.primary.copy(alpha=.08f)else MaterialTheme.colorScheme.surface,border=if(active)BorderStroke(1.dp,MaterialTheme.colorScheme.primary.copy(alpha=.5f))else null) {
                                Row(Modifier.fillMaxWidth().heightIn(min=82.dp).padding(18.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                                    Icon(if(active)Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,null,Modifier.size(22.dp),tint=if(active)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){NativeText(p.name,style=MaterialTheme.typography.titleMedium);NativeText("${p.minutes}分钟",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                                    NativeText("¥${moneyFen(p.priceFen.toLong())}",style=MaterialTheme.typography.titleLarge)
                                }
                            }
                        }
                    }
                    Hint("先放好衣物。确认机器与程序后再下单，付款可能使设备开始运行。")
                }
                if(w==null)Group {
                    NavRow("常用洗衣机","扫描或粘贴机身二维码",Icons.Default.QrCodeScanner,onClick=scan)
                    var manual by rememberSaveable {mutableStateOf(false)}
                    TextButton({manual=!manual}){NativeText("粘贴二维码链接")}
                    if(manual){OutlinedTextField(qr,{qr=it},label={NativeText("U净机身二维码链接")},modifier=Modifier.fillMaxWidth());OutlinedButton({actions.read(qr)},enabled=!busy && qr.isNotBlank()){NativeText("读取并保存")}}
                }
            }
        }
        if(w!=null && !s.unresolvedLaundry)Column(Modifier.widthIn(max=560.dp).fillMaxWidth().align(Alignment.CenterHorizontally).padding(horizontal=20.dp,vertical=12.dp)) {
            ActionButton(if(program!=null)"确认程序" else "选择洗衣程序",aligned=true,trailing=program?.let {"¥${moneyFen(it.priceFen.toLong())}"},enabled=!s.storageIssue && !busy && w.available && program!=null && s.washerError==null,busy="order" in s.busy){confirm=program}
        }
    }
    confirm?.let {p->AlertDialog(onDismissRequest={confirm=null},title={NativeText("确认预约这台洗衣机？")},text={NativeText("${w?.store} · ${w?.number}号\n${p.name} · ¥${moneyFen(p.priceFen.toLong())}\n预约后另行确认付款。")},confirmButton={TextButton({confirm=null;actions.create(p);navigate("laundry")}){NativeText("确认预约")}},dismissButton={TextButton({confirm=null}){NativeText("再看看")}})}
}

data class LaundryActions(val select:(SavedWasher)->Unit={},val read:(String)->Unit={},val refresh:()->Unit={},val create:(WasherProgram)->Unit={},val refreshOrder:()->Unit={},val cancel:()->Unit={},val pay:()->Unit={})

@Composable
fun OrdersScreen(s:CampusUiState,padding:PaddingValues,navigate:(String)->Unit,refresh:()->Unit,cancel:()->Unit,pay:()->Unit) = Page(padding,spacing=0.dp,top=0.dp) {
    val r=s.checkout
    if(r==null && s.waterSession==null)Group {Icon(Icons.Default.History,null,tint=MaterialTheme.colorScheme.onSurfaceVariant);NativeText("还没有使用记录",style=MaterialTheme.typography.titleLarge);Hint("在本 App 使用热水或洗衣后，最近记录会显示在这里。")}
    if(r!=null){
        FormLabel("最近洗衣订单")
        Surface(onClick={navigate("laundry")},shape=RoundedCornerShape(26.dp),color=MaterialTheme.colorScheme.surface){
            Row(Modifier.fillMaxWidth().padding(20.dp),verticalAlignment=Alignment.CenterVertically){
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(8.dp)){NativeText(r.order?.label ?: "订单待核对",style=MaterialTheme.typography.titleMedium);NativeText(r.programName,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant);NativeText("¥${r.order?.priceYuan?.let(::money) ?: moneyFen(r.priceFen.toLong())}")}
                Icon(Icons.Default.ChevronRight,null,tint=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    s.waterSession?.let {water->
        if(r!=null)Spacer(Modifier.height(17.dp))
        FormLabel(if(water.stage==ShowerStage.SETTLED)"最近热水结算" else "当前热水记录")
        Surface(onClick={navigate("water")},shape=RoundedCornerShape(26.dp),color=MaterialTheme.colorScheme.surface){
            Row(Modifier.fillMaxWidth().padding(20.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)){
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){NativeText(if(water.stage==ShowerStage.SETTLED)"热水已结算" else "热水洗澡");Hint(water.endedAt?.let(::time) ?: waterLabel(s))}
                if(water.stage==ShowerStage.SETTLED)NativeText(water.payFen?.let {"¥${moneyFen(it)}"} ?: "金额未返回",style=MaterialTheme.typography.bodyMedium)
                Icon(Icons.Default.ChevronRight,null,tint=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun ChoiceRow(text:String,selected:Boolean,enabled:Boolean=true,onClick:()->Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min=52.dp).clickable(enabled=enabled,onClick=onClick),verticalAlignment=Alignment.CenterVertically) {
        RadioButton(selected,onClick=null,enabled=enabled)
        NativeText(text,Modifier.padding(start=10.dp).weight(1f),color=if(enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable
private fun Countdown(seconds:Int,at:Long,running:Boolean) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(seconds,at) { while(true) { delay(1000); now=System.currentTimeMillis() } }
    val remaining=(seconds-((now-at)/1000).coerceAtLeast(0)).coerceAtLeast(0)
    Hint(if(remaining==0L) "等待服务器确认状态" else if(running) "剩余约 ${(remaining+59)/60} 分钟" else "%02d:%02d 后预约超时".format(Locale.ROOT,remaining/60,remaining%60))
}
fun time(at:Long):String = SimpleDateFormat("yyyy年M月d日 HH:mm",Locale.CHINA).format(Date(at))
fun money(raw:String):String = runCatching { java.math.BigDecimal(raw).setScale(2,java.math.RoundingMode.HALF_UP).toPlainString() }.getOrDefault(raw)
fun moneyFen(fen:Long):String = java.math.BigDecimal(fen).movePointLeft(2).setScale(2).toPlainString()

fun clock(at:Long):String = SimpleDateFormat("HH:mm",Locale.CHINA).format(Date(at))

@Composable
private fun LaundryOrderCard(s:CampusUiState,refresh:()->Unit,cancel:()->Unit,pay:()->Unit) {
    val r=s.checkout ?: return
    var confirm by rememberSaveable {mutableStateOf("")}
    Group {
        Hint("当前洗衣订单")
        NativeText(r.order?.label ?: "预约结果待核对",style=MaterialTheme.typography.titleLarge)
        NativeText("¥${r.order?.priceYuan?.let(::money) ?: moneyFen(r.priceFen.toLong())}",fontSize=36.sp,fontWeight=FontWeight.SemiBold)
        NativeText(r.programName); Hint("${time(r.createdAt)} · ${r.deviceId.takeLast(8)}")
        r.order?.let { order ->
            val seconds=if(order.running) order.remainSeconds else if(order.unpaid) order.countDown else null
            if(seconds!=null) Countdown(seconds,r.updatedAt,order.running)
        }
        if(r.stage==CheckoutStage.CREATING) Hint("预约结果未确认，已保留本机记录。请刷新或到官方 U净核对，勿重复下单。",true)
        if(r.stage==CheckoutStage.PAYMENT_REQUESTED) Hint("已经请求付款，请刷新核对服务器状态；退出支付宝不会自动取消预约。")
        if(r.stage==CheckoutStage.CANCELLATION_REQUESTED) Hint("取消结果尚未确认，请刷新订单。",true)
        if(r.stage==CheckoutStage.CREATED && r.order?.unpaid==true) {
            Hint("付款可能启动洗衣机，请先放好衣物并核对金额。")
            ActionButton("前往支付宝",enabled=!s.transactionBusy && !s.storageIssue) { confirm="pay" }
        }
        OutlinedButton(refresh,enabled=!s.transactionBusy && r.orderId!=null,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) { NativeText(if("orderRefresh" in s.busy) "正在核对…" else "刷新订单状态") }
        if(r.order?.unpaid==true && r.stage in setOf(CheckoutStage.CREATED,CheckoutStage.PAYMENT_REQUESTED)) TextButton({confirm="cancel"},enabled=!s.transactionBusy && !s.storageIssue) { NativeText("取消未支付订单",color=MaterialTheme.colorScheme.error) }
    }
    if(confirm.isNotEmpty()) AlertDialog(onDismissRequest={confirm=""},title={NativeText(if(confirm=="pay") "前往支付宝付款？" else "取消这笔未支付订单？")},
        text={NativeText(if(confirm=="pay") "${r?.programName} · ¥${r?.priceFen?.toLong()?.let(::moneyFen)}\n付款可能启动洗衣机，请确认衣物已放好。" else "将先核对订单仍未付款，再申请取消。")},
        confirmButton={TextButton({val action=confirm;confirm="";if(action=="pay") pay() else cancel()}) { NativeText("确认") }},dismissButton={TextButton({confirm=""}){NativeText("返回")}})
}

fun clockSeconds(at:Long):String=SimpleDateFormat("HH:mm:ss",Locale.CHINA).format(Date(at))


@Composable
fun WasherSetupScreen(s:CampusUiState,padding:PaddingValues,actions:LaundryActions,navigate:(String)->Unit,scan:()->Unit)=Page(padding) {
    var qr by remember {mutableStateOf("")}
    val busy=s.transactionBusy || "washer" in s.busy
    Group {
        NavRow("U净账号",if(s.account!=null)"已登录" else "使用本人手机号登录",Icons.Default.AccountCircle,done=s.account!=null){navigate("laundryLogin")}
    }
    Group {
        NativeText("常用洗衣机",style=MaterialTheme.typography.titleMedium)
        if(s.washers.isEmpty())Hint("扫描机身二维码，保存后即可直接使用。")
        s.washers.forEach {item->ChoiceRow("${item.name} · ${item.number}",s.selectedWasher==item.id,!busy){actions.select(item)}}
        ActionButton("扫描洗衣机二维码",enabled=s.account!=null && !busy,onClick=scan)
    }
    if(s.account!=null)Group {
        NativeText("也可以粘贴二维码链接",style=MaterialTheme.typography.bodyMedium)
        OutlinedTextField(qr,{qr=it},label={NativeText("U净机身二维码链接")},modifier=Modifier.fillMaxWidth(),minLines=2)
        ActionButton("读取并保存",enabled=!busy && qr.isNotBlank()){actions.read(qr)}
    }
}
