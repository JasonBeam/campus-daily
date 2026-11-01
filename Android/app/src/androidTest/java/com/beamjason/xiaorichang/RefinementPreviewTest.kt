package com.beamjason.xiaorichang

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Same real Android window/safe areas as the vivo-sized emulator; fixture data only. */
@RunWith(AndroidJUnit4::class)
class RefinementPreviewTest {
    @get:Rule val compose=createEmptyComposeRule()
    @Test fun previewActualPhoneSize() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val dir=File(instrumentation.targetContext.getExternalFilesDir(null),"refinement-preview").apply{mkdirs()}
        for(refined in listOf(false,true))for(dark in listOf(false,true))for(page in listOf("home","water","laundry","devices","setup")) {
            val intent=Intent(instrumentation.targetContext,PreviewActivity::class.java).putExtra("page",page).putExtra("mode",if(dark)"dark" else "light").putExtra("refined",refined)
            ActivityScenario.launch<PreviewActivity>(intent).use {
                compose.onNodeWithText(when(page){"water"->"热水洗澡";"laundry"->"洗衣机";"devices"->"设备与设置";"setup"->"首次配置";else->"校园生活"}).assertExists()
                compose.waitForIdle()
                instrumentation.uiAutomation.waitForIdle(200,2_000)
                val bitmap=instrumentation.uiAutomation.takeScreenshot()
                File(dir,"${if(refined)"refined" else "before"}-$page-${if(dark)"dark" else "light"}-vivo.png").outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
                bitmap.recycle()
            }
        }
    }
}
