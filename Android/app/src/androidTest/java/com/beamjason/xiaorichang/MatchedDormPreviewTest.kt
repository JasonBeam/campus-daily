package com.beamjason.xiaorichang

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Production onboarding content with inert callbacks and fixture identity only. */
@RunWith(AndroidJUnit4::class)
class MatchedDormPreviewTest {
    @get:Rule val compose=createEmptyComposeRule()
    @Test fun ownResidenceIsDefaultAndManualPickersAreSecondary() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val dir=File(instrumentation.targetContext.getExternalFilesDir(null),"matched-dorm-preview").apply{mkdirs()}
        for(dark in listOf(false,true)) {
            val intent=Intent(instrumentation.targetContext,PreviewActivity::class.java).putExtra("page","dorm-matched").putExtra("mode",if(dark)"dark" else "light")
            ActivityScenario.launch<PreviewActivity>(intent).use {
                compose.onNodeWithText("已匹配宿舍").assertExists()
                compose.onNodeWithText("1栋301").assertExists()
                compose.onNodeWithText("校区",substring=false).assertDoesNotExist()
                compose.onNodeWithText("保存宿舍，稍后核对").performScrollTo().assertIsDisplayed()
                val save=compose.onNodeWithText("保存宿舍，稍后核对").fetchSemanticsNode().boundsInRoot
                val tabs=compose.onNodeWithTag("campus-tab-bar",useUnmergedTree=true).fetchSemanticsNode().boundsInRoot
                org.junit.Assert.assertTrue("The entire save button must stay above the floating tab bar",save.bottom<=tabs.top)
                compose.waitForIdle();instrumentation.uiAutomation.waitForIdle(200,2000)
                val bitmap=instrumentation.uiAutomation.takeScreenshot()
                File(dir,"matched-${if(dark)"dark" else "light"}.png").outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
                compose.onNodeWithText("更换宿舍").performScrollTo().performClick()
                compose.onNodeWithText("校区",substring=false).assertExists()
            }
        }
    }
}
