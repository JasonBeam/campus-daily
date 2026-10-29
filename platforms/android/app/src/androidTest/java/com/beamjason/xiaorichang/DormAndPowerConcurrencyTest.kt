package com.beamjason.xiaorichang

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
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

/** Fixture-only overlap of the production power and dorm setup jobs. */
@RunWith(AndroidJUnit4::class)
class DormAndPowerConcurrencyTest {
    @get:Rule val compose=createComposeRule()
    private class IsolatedApplication(private val base:Context):Application() {
        private val prefix="dorm-power-${System.nanoTime()}"
        var failBalanceCacheWrite=false
        init {attachBaseContext(base)}
        override fun getSharedPreferences(name:String,mode:Int):SharedPreferences {
            val original=base.getSharedPreferences("$prefix-$name",mode)
            return object:SharedPreferences by original {
                override fun edit():SharedPreferences.Editor {
                    val editor=original.edit()
                    return object:SharedPreferences.Editor by editor {
                        var cacheWrite=false
                        override fun putString(key:String?,value:String?):SharedPreferences.Editor {
                            if(key=="campus.balance-cache")cacheWrite=true
                            editor.putString(key,value);return this
                        }
                        override fun commit():Boolean = if(cacheWrite && failBalanceCacheWrite)false else editor.commit()
                    }
                }
            }
        }
        override fun getNoBackupFilesDir()=File(base.cacheDir,prefix).apply{mkdirs()}
    }
    @Test fun independentPowerMatchDoesNotAbortOrOverwriteDormSetup() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        val c=CampusConfig(syscustid="fixture-owner",token="fixture-session",areaCode="fixture-area",custid="fixture-card",dorm="2栋504",portalDormAddress="示例校区2栋3号5层504房")
        val water=WaterSettings(secret="fixture-secret",sid="fixture-sid",bleName="fixture-radio",typeId=1)
        SecureStore(app).put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",water.json()).toString().toByteArray())
        val identityStarted=CompletableDeferred<Unit>();val identityGate=CompletableDeferred<Unit>();val powerGate=CompletableDeferred<Unit>()
        val api=object:CampusClient() {
            override suspend fun readDormIdentity(c:CampusConfig,profile:HotWaterProfile):DormIdentity {identityStarted.complete(Unit);identityGate.await();return DormIdentity("fixture-student","fixture-school")}
            override suspend fun dormOptions(parent:String,rooms:Boolean,profile:HotWaterProfile):List<Option> = when(parent) {
                "fixture-school"->listOf(Option("campus","示例校区"));"campus"->listOf(Option("building","2栋"))
                "building"->listOf(Option("floor","5楼"));"floor"->listOf(Option("room","504"));else->emptyList()
            }
            override suspend fun waterMachines(room:String,school:String,profile:HotWaterProfile)=listOf(DormWater("AABBCCDD","504水控","fixture-radio"))
        }
        val meter=PowerMeter("fixture-meter","2栋504","10","5",null,"")
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {
            model=CampusViewModel(app,null,powerDirectory={_,_->powerGate.await();CampusPowerResolution(suggestion=CampusPowerSuggestion("power-room",meter))},campusApi=api)
            model.matchPowerAutomatically(true);model.loadDorm()
        }
        compose.waitUntil(5000){identityStarted.isCompleted && model.state.value.matchingPower}
        powerGate.complete(Unit)
        compose.waitUntil(5000){model.state.value.campus.meterId=="fixture-meter"}
        identityGate.complete(Unit)
        compose.waitUntil(5000){model.state.value.dormSetup.autoMatched}
        assertEquals("AABBCCDD",model.state.value.dormSetup.selected?.machineId)
        assertEquals("fixture-meter",model.state.value.campus.meterId)
        assertFalse(model.state.value.water.configured)
        assertNull(model.state.value.waterSession)
        var saved=false
        instrumentation.runOnMainSync {model.saveDorm {saved=true}}
        compose.waitUntil(5000){saved}
        assertTrue(model.state.value.water.configured)
        assertEquals("fixture-meter",model.state.value.campus.meterId)
        assertNull(model.state.value.waterSession)
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
    }
    @Test fun cacheWriteFailureCannotPartiallySaveDormSettings() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        val c=CampusConfig(syscustid="fixture-owner",token="fixture-session",areaCode="fixture-area",custid="fixture-card",portalDormAddress="示例校区2栋3号5层504房")
        val water=WaterSettings(secret="fixture-secret",sid="fixture-sid",bleName="fixture-radio",typeId=1)
        val store=SecureStore(app)
        store.put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",water.json()).toString().toByteArray())
        val api=object:CampusClient() {
            override suspend fun readDormIdentity(c:CampusConfig,profile:HotWaterProfile)=DormIdentity("fixture-student","fixture-school")
            override suspend fun dormOptions(parent:String,rooms:Boolean,profile:HotWaterProfile):List<Option> = when(parent) {
                "fixture-school"->listOf(Option("campus","示例校区"));"campus"->listOf(Option("building","2栋"))
                "building"->listOf(Option("floor","5楼"));"floor"->listOf(Option("room","504"));else->emptyList()
            }
            override suspend fun waterMachines(room:String,school:String,profile:HotWaterProfile)=listOf(DormWater("AABBCCDD","504水控","fixture-radio"))
        }
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {model=CampusViewModel(app,null,campusApi=api);model.loadDorm()}
        compose.waitUntil(5000){model.state.value.dormSetup.autoMatched}
        app.failBalanceCacheWrite=true
        var saved=false
        instrumentation.runOnMainSync {model.saveDorm {saved=true}}
        compose.waitUntil(5000){"saveDorm" !in model.state.value.busy}
        assertFalse(saved);assertFalse(model.state.value.water.configured)
        val persisted=JSONObject(store.get("app.settings.v2")!!.toString(Charsets.UTF_8))
        assertEquals("",persisted.getJSONObject("water").optString("machineId"))
        assertEquals("",persisted.getJSONObject("campus").optString("dorm"))
    }
    @Test fun savingSameDormWithoutRescanRetainsOnlyPreviouslyVerifiedAddress() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        val c=CampusConfig(syscustid="fixture-owner",token="fixture-session",areaCode="fixture-area",custid="fixture-card",dorm="2栋504",portalDormAddress="示例校区2栋3号5层504房")
        val water=WaterSettings(secret="fixture-secret",sid="fixture-sid",studentId="fixture-student",schoolId="fixture-school",machineId="AABBCCDD",bleName="fixture-radio",typeId=1,address="AA:BB:CC:DD:EE:FF",room="2栋504")
        SecureStore(app).put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",water.json()).toString().toByteArray())
        val api=object:CampusClient() {
            override suspend fun readDormIdentity(c:CampusConfig,profile:HotWaterProfile)=DormIdentity("fixture-student","fixture-school")
            override suspend fun dormOptions(parent:String,rooms:Boolean,profile:HotWaterProfile):List<Option> = when(parent) {
                "fixture-school"->listOf(Option("campus","示例校区"));"campus"->listOf(Option("building","2栋"))
                "building"->listOf(Option("floor","5楼"));"floor"->listOf(Option("room","504"));else->emptyList()
            }
            override suspend fun waterMachines(room:String,school:String,profile:HotWaterProfile)=listOf(DormWater("AABBCCDD","504水控","fixture-radio"))
        }
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {model=CampusViewModel(app,null,campusApi=api);model.loadDorm()}
        compose.waitUntil(5000){model.state.value.dormSetup.autoMatched}
        assertNull(model.state.value.dormSetup.verifiedAddress)
        var saved=false
        instrumentation.runOnMainSync {model.saveDorm{saved=true}}
        compose.waitUntil(5000){saved}
        lateinit var restored:CampusViewModel
        instrumentation.runOnMainSync {restored=CampusViewModel(app,null,campusApi=api)}
        assertEquals("AA:BB:CC:DD:EE:FF",restored.state.value.water.address)
        assertNull(restored.state.value.waterSession)
    }
}
