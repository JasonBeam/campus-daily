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
import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.security.SecureStore
import com.beamjason.xiaorichang.ui.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Production screen and encrypted model, fixture Bluetooth only. */
@RunWith(AndroidJUnit4::class)
class WaterInspectionPersistenceTest {
    @get:Rule val compose=createComposeRule()
    private class IsolatedApplication(private val base:Context):Application() {
        private val prefix="water-inspection-${System.nanoTime()}"
        init {attachBaseContext(base)}
        override fun getSharedPreferences(name:String,mode:Int)=base.getSharedPreferences("$prefix-$name",mode)
        override fun getNoBackupFilesDir()=File(base.cacheDir,prefix).apply{mkdirs()}
    }
    private class FixtureTransport:WaterTransport {
        var verified=0;var disconnected=0;var dangerous=0
        override suspend fun connect(deviceName:String,expectedAddress:String?):String {dangerous++;error("unexpected transaction")}
        override suspend fun scanCandidates(name:String):List<BleCandidate> = error("unexpected direct scan")
        override suspend fun exchange(bytes:ByteArray):ByteArray {dangerous++;error("unexpected direct exchange")}
        override suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?,onProbe:(String)->Unit):VerifiedWaterTarget {
            verified++;assertEquals("AABBCCDD",machineId)
            return VerifiedWaterTarget("AA:BB:CC:DD:EE:FF",byteArrayOf(0x55,0xAA.toByte(),0xBB.toByte(),0xCC.toByte(),0xDD.toByte())+ByteArray(15))
        }
        override fun disconnect(){disconnected++}
    }
    @Test fun userCanInspectInPlaceAndReopenWithVerifiedDeviceSaved() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        val c=CampusConfig(syscustid="fixture-owner",token="fixture-session",areaCode="fixture-campus",custid="fixture-card",dorm="2栋504")
        val water=WaterSettings("fixture-secret","fixture-sid","fixture-student","fixture-school","AABBCCDD","fixture-radio",1,room="2栋504")
        SecureStore(app).put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",water.json()).toString().toByteArray())
        val transport=FixtureTransport();lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {model=CampusViewModel(app,null,suppliedWaterTransport=transport)}
        var starts=0;var navigations=0
        compose.setContent {val state by model.state.collectAsState();NativeTheme {WaterScreen(state,PaddingValues(),{navigations++},inspect=model::inspectConfiguredWater,operate={starts++})}}
        compose.onNodeWithText("连接检查与设备信息").performScrollTo().performClick()
        compose.onNodeWithText("扫描并核对本宿舍水控").performScrollTo().performClick()
        compose.waitUntil(5000){model.state.value.water.address=="AA:BB:CC:DD:EE:FF"}
        compose.onNodeWithText("已找到本宿舍水控，编号已核对。").assertExists()
        assertEquals(1,transport.verified);assertEquals(1,transport.disconnected);assertEquals(0,transport.dangerous)
        assertEquals(0,starts);assertEquals(0,navigations);assertNull(model.state.value.waterSession)
        lateinit var restored:CampusViewModel
        instrumentation.runOnMainSync {restored=CampusViewModel(app,null,suppliedWaterTransport=FixtureTransport())}
        assertEquals("AA:BB:CC:DD:EE:FF",restored.state.value.water.address)
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
    }
}
