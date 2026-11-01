package com.beamjason.xiaorichang

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.beamjason.xiaorichang.data.CampusViewModel
import com.beamjason.xiaorichang.ui.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Empty isolated storage, the production public import path, and encrypted
 * persistence. No USB seed, school account, network call or physical operation. */
@RunWith(AndroidJUnit4::class)
class PublicPlatformImportTest {
    @get:Rule val compose=createComposeRule()
    private class EmptyApplication(private val base:Context):Application() {
        private val prefix="platform-first-install-${System.nanoTime()}"
        init {attachBaseContext(base)}
        override fun getSharedPreferences(name:String,mode:Int)=base.getSharedPreferences("$prefix-$name",mode)
        override fun getNoBackupFilesDir()=File(base.cacheDir,prefix).apply{mkdirs()}
    }
    @Test fun publicEntryImportsOnlyPlatformAndPersistsWithoutPreProvisioning() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val app=EmptyApplication(instrumentation.targetContext)
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {model=CampusViewModel(app,null)}
        assertFalse(model.state.value.water.hasPlatform)
        assertFalse(model.state.value.campus.configured)
        val fixture="""{"secret":"fixture-secret","sid":"fixture-provider","bleName":"fixture-ble","typeID":1,"version":1}"""
        compose.setContent {
            val state by model.state.collectAsState()
            NativeTheme {DormSetupContent(state,PaddingValues(),DormActions(),import={model.importConfig(fixture,true)})}
        }
        compose.onNodeWithText("导入热水接入文件").assertDoesNotExist()
        compose.onNodeWithText("自动连接热水").assertExists()
        compose.onNodeWithText("备用接入方式").performScrollTo().performClick()
        compose.onNodeWithText("导入热水接入文件").performScrollTo().assertIsDisplayed().performClick()
        compose.waitUntil(5000){model.state.value.water.hasPlatform}
        compose.onNodeWithText("导入热水接入文件").assertDoesNotExist()
        compose.onNodeWithText("先登录学校账号").assertExists()
        // Recreating the model reads encrypted state; no student's account,
        // residence or previously verified BLE address was imported.
        lateinit var restored:CampusViewModel
        instrumentation.runOnMainSync {restored=CampusViewModel(app,null)}
        assertTrue(restored.state.value.water.hasPlatform)
        assertFalse(restored.state.value.water.configured)
        assertFalse(restored.state.value.campus.configured)
        assertEquals("",restored.state.value.water.studentId)
        assertEquals("",restored.state.value.water.machineId)
        assertEquals("",restored.state.value.water.room)
        assertNull(restored.state.value.water.address)
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
        app.noBackupFilesDir.deleteRecursively()
    }
    @Test fun freshInstallAutomaticallyPreparesBundledPlatformWithoutAnAccountOrImport() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val app=EmptyApplication(instrumentation.targetContext)
        lateinit var model:CampusViewModel
        // Exercise the actual installed bundle, not a USB seed or test-only configuration.
        instrumentation.runOnMainSync {model=CampusViewModel(app)}
        assertTrue(model.state.value.water.hasPlatform)
        assertFalse(model.state.value.water.configured)
        assertFalse(model.state.value.campus.configured)
        assertNull(model.state.value.water.access)
        assertEquals("",model.state.value.water.studentId)
        assertEquals("",model.state.value.water.machineId)
        lateinit var restored:CampusViewModel
        instrumentation.runOnMainSync {restored=CampusViewModel(app,null)}
        assertTrue(restored.state.value.water.hasPlatform)
        assertFalse(restored.state.value.campus.configured)
        assertNull(restored.state.value.water.access)
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
        app.noBackupFilesDir.deleteRecursively()
    }
}
