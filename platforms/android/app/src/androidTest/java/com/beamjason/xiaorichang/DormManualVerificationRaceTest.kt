package com.beamjason.xiaorichang

import android.app.Application
import android.content.Context
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.security.SecureStore
import kotlinx.coroutines.CompletableDeferred
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DormManualVerificationRaceTest {
    @get:Rule val compose=createComposeRule()
    private class IsolatedApplication(private val base:Context):Application() {
        private val prefix="dorm-manual-${System.nanoTime()}"
        init {attachBaseContext(base)}
        override fun getSharedPreferences(name:String,mode:Int)=base.getSharedPreferences("$prefix-$name",mode)
        override fun getNoBackupFilesDir()=File(base.cacheDir,prefix).apply{mkdirs()}
    }
    @Test fun delayedManualReadCannotVerifyAChangedSelection() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        val c=CampusConfig(syscustid="fixture-owner",token="fixture-session",areaCode="fixture-area",custid="fixture-card",portalDormAddress="示例校区2栋3号5层504房")
        val water=WaterSettings(secret="fixture-secret",sid="fixture-sid",bleName="fixture-radio",typeId=1)
        SecureStore(app).put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",water.json()).toString().toByteArray())
        val one=DormWater("AABBCCDD","设备一","fixture-radio"); val two=DormWater("11223344","设备二","fixture-radio")
        val api=object:CampusClient() {
            override suspend fun readDormIdentity(c:CampusConfig,profile:HotWaterProfile)=DormIdentity("fixture-student","fixture-school")
            override suspend fun dormOptions(parent:String,rooms:Boolean,profile:HotWaterProfile):List<Option> = when(parent) {
                "fixture-school"->listOf(Option("campus","示例校区"));"campus"->listOf(Option("building","2栋"))
                "building"->listOf(Option("floor","5楼"));"floor"->listOf(Option("room","504"));else->emptyList()
            }
            override suspend fun waterMachines(room:String,school:String,profile:HotWaterProfile)=listOf(one,two)
        }
        val gate=CompletableDeferred<Unit>();val entered=CompletableDeferred<Unit>()
        val candidate=BleCandidate("AA:BB:CC:DD:EE:FF","fixture-radio",-40)
        val transport=object:WaterTransport {
            var connections=0;var disconnects=0
            override suspend fun scanCandidates(name:String)=listOf(candidate)
            override suspend fun connect(deviceName:String,expectedAddress:String?):String {
                connections++; if(connections==1)error("fixture unavailable during initial scan")
                entered.complete(Unit);gate.await();return candidate.address
            }
            override suspend fun exchange(bytes:ByteArray):ByteArray {
                assertArrayEquals(byteArrayOf(0xAA.toByte()),bytes)
                return byteArrayOf(0x55,0xAA.toByte(),0xBB.toByte(),0xCC.toByte(),0xDD.toByte())+ByteArray(15)
            }
            override suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?,onProbe:(String)->Unit):VerifiedWaterTarget = error("unexpected transaction")
            override fun disconnect(){disconnects++}
        }
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {model=CampusViewModel(app,null,suppliedWaterTransport=transport,campusApi=api);model.loadDorm()}
        compose.waitUntil(5000){model.state.value.dormSetup.machines.size==2}
        instrumentation.runOnMainSync {model.selectMachine(one);model.scanWater()}
        compose.waitUntil(5000){"verify" !in model.state.value.busy && model.state.value.dormSetup.candidates.isNotEmpty()}
        instrumentation.runOnMainSync {model.verifyWater(candidate)}
        compose.waitUntil(5000){entered.isCompleted}
        instrumentation.runOnMainSync {model.selectMachine(two)}
        gate.complete(Unit)
        compose.waitUntil(5000){"verify" !in model.state.value.busy}
        assertEquals(two,model.state.value.dormSetup.selected)
        assertNull(model.state.value.dormSetup.verifiedAddress)
        assertTrue(model.state.value.message.orEmpty().contains("变化"))
        assertEquals(2,transport.disconnects)
        assertNull(model.state.value.waterSession)
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
    }
}
