package com.beamjason.xiaorichang

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.beamjason.xiaorichang.data.CampusUiState
import com.beamjason.xiaorichang.ui.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import org.json.JSONObject
import org.json.JSONArray

@RunWith(AndroidJUnit4::class)
class NativeLayoutTest {
    @get:Rule val compose=createComposeRule()
    private data class Case(val page:String,val width:Int,val dark:Boolean=false,val scale:Float=1f,val glass:GlassMode=GlassMode.LIQUID) {
        val filename get()="$page-${width}dp-${if(dark)"dark" else "light"}-${scale}x-${glass.name.lowercase()}.png"
    }
    @Test fun nativeScreensAcrossPhoneWidthsThemesAndLargeText() {
        var current by mutableStateOf(Case("home",360))
        compose.setContent {
            val density=LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density,current.scale), LocalPreviewSafeTop provides 62.dp, LocalPreviewSafeBottom provides 21.dp) {
                NativeTheme(current.dark) {
                    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),contentAlignment=Alignment.TopCenter) {
                        key(current) {Box(Modifier.width(current.width.dp).fillMaxHeight()){PreviewLayout(current.page,current.glass)}}
                    }
                }
            }
        }
        val cases=buildList {
            for(page in listOf("home","water","laundry","devices","setup-complete","orders"))add(Case(page,440))
            for(width in listOf(360,393,412))for(dark in listOf(false,true))add(Case("home",width,dark))
            add(Case("home",360,false,1.6f));add(Case("water",360));add(Case("water",360,true,1.6f))
            add(Case("laundry",393));add(Case("laundry",360,true,1.3f));add(Case("laundry-running",393,true));add(Case("home",360,glass=GlassMode.SOLID));add(Case("home",360,glass=GlassMode.FROSTED));add(Case("setup",360));add(Case("devices",393,true));add(Case("orders",393))
        }
        val dir=File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null),"ui-previews").apply{mkdirs()}
        for(c in cases) {
            compose.runOnIdle {current=c};compose.waitForIdle()
            val expected=when(c.page){"home"->"校园卡";"water"->"本次费用";"laundry"->"选择程序";"laundry-running"->"当前洗衣订单";"setup"->"完成首次设置";"devices"->"账号与设备设置";"setup-complete"->"都准备好了";else->"最近洗衣订单"}
            compose.onNodeWithText(expected).assertExists()
            File(dir,c.filename).outputStream().use {compose.onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG,100,it)}
            if(c.width==440) {
                val labels=listOf("校园生活","双余额","宿舍电量","校园卡","热水洗澡","本次费用","最近一次用水","连接检查与设备信息","再次开始洗澡","选择程序","普通洗","设备与设置","账号与设备设置","我的信息","都准备好了","已完成 3 / 3","最近洗衣订单","最近热水结算")
                val points=JSONObject();val px=InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density
                for(label in labels){val nodes=compose.onAllNodesWithText(label,useUnmergedTree=true).fetchSemanticsNodes();if(nodes.isNotEmpty()){val b=nodes.first().boundsInRoot;points.put(label,JSONArray(listOf(b.left/px,b.top/px,b.width/px,b.height/px)))}}
                File(dir,c.filename.removeSuffix(".png")+".json").writeText(points.toString(2))
            }
            if(c.page=="home") {
                compose.onNodeWithText("宿舍电量").performScrollTo().assertIsDisplayed()
                compose.onNodeWithText("洗衣机").performScrollTo().assertIsDisplayed()
            }
        }
        compose.runOnIdle {current=Case("home",393)};compose.waitForIdle()
        compose.onNodeWithText("订单",useUnmergedTree=true).performClick()
        compose.onNodeWithText("最近订单").assertIsDisplayed()
        compose.onNodeWithText("设备",useUnmergedTree=true).performClick()
        compose.onNodeWithText("高级设置与故障排查").performScrollTo().performClick()
        compose.onNodeWithText("液态玻璃").performScrollTo().assertIsDisplayed()
    }
}
