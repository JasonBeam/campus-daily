package com.beamjason.xiaorichang

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.security.SecureStore
import com.beamjason.xiaorichang.ui.*
import kotlinx.coroutines.CompletableDeferred
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Production model, UI and encrypted persistence, with read-only fixture APIs.
 * No real school credentials, Bluetooth, water operations or payments. */
@RunWith(AndroidJUnit4::class)
class PowerAutoMatchPersistenceTest {
    @get:Rule val compose=createComposeRule()
    private class IsolatedApplication(private val base:Context):Application() {
        private val prefix="power-auto-${System.nanoTime()}"
        var failCacheWrite=false
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
                        override fun commit():Boolean = if(cacheWrite && failCacheWrite)false else editor.commit()
                    }
                }
            }
        }
        override fun getNoBackupFilesDir()=File(base.cacheDir,prefix).apply{mkdirs()}
    }
    private fun seed(app:Application):CampusConfig {
        val c=CampusConfig(syscustid="fixture-owner",token="fixture-session",areaCode="fixture-system",custid="fixture-card",dorm="2栋504",portalDormAddress="示例校区2栋3号5层504房")
        val secure=SecureStore(app)
        secure.put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",WaterSettings().json()).toString().toByteArray())
        secure.put("campus.balance-cache",BalanceCache(c.owner,"36.80",12345,cardOwner=c.cardOwner).json().toString().toByteArray())
        return c
    }
    private val meter=PowerMeter("fixture-meter","2栋504","42.6","23.43",null,"")
    @Test fun cacheWriteFailureDoesNotPersistAnInvisibleMeterBinding() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        seed(app);app.failCacheWrite=true
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {
            model=CampusViewModel(app,null,{_,_->CampusPowerResolution(suggestion=CampusPowerSuggestion("fixture-room",meter))})
            model.matchPowerAutomatically(true)
        }
        compose.waitUntil(5000){model.state.value.powerMatchIssue!=null}
        assertEquals("",model.state.value.campus.meterId)
        val stored=JSONObject(SecureStore(app).get("app.settings.v2")!!.toString(Charsets.UTF_8))
        assertEquals("",stored.getJSONObject("campus").optString("meterID"))
        assertEquals("36.80",model.state.value.cache.card)
    }
    @Test fun delayedAutomaticResultSavesMeterAndPreservesCardAcrossModelRecreation() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        seed(app);val gate=CompletableDeferred<Unit>();lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {
            model=CampusViewModel(app,null,{_,_->gate.await();CampusPowerResolution(suggestion=CampusPowerSuggestion("fixture-room",meter))},{_,_->error("No second meter request")})
            model.matchPowerAutomatically(true)
        }
        compose.waitUntil(5000){model.state.value.matchingPower}
        assertEquals("",model.state.value.campus.buildingId)
        gate.complete(Unit)
        compose.waitUntil(5000){model.state.value.campus.meterId==meter.id}
        assertEquals("36.80",model.state.value.cache.card)
        assertEquals(12345L,model.state.value.cache.cardAt)
        lateinit var restored:CampusViewModel
        instrumentation.runOnMainSync {restored=CampusViewModel(app,null)}
        assertEquals("fixture-room",restored.state.value.campus.buildingId)
        assertEquals("fixture-meter",restored.state.value.cache.power?.id)
        assertEquals("36.80",restored.state.value.cache.card)
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
    }
    @Test fun duplicateApartmentChoiceIsVisibleAndOnlyChosenMeterIsReadAndSaved() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext)
        seed(app);val calls=mutableListOf<String>()
        val paths=listOf("a" to "半山公寓","b" to "兰香公寓").map{(id,name)->CampusPowerCandidate(listOf(Option("campus","示例校区"),Option(id,name),Option("$id-building","2栋"),Option("$id-floor","5楼"),Option("$id-room","504")))}
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {
            model=CampusViewModel(app,null,{_,_->CampusPowerResolution(choices=paths)},{_,room->calls+=room;if(calls.size==1)error("fixture-network-unavailable");listOf(meter)})
            model.matchPowerAutomatically(true)
        }
        compose.setContent {val state by model.state.collectAsState();NativeTheme {DormSetupContent(state,PaddingValues(),DormActions(),powerChoice=model::choosePowerApartment,powerRetry={model.matchPowerAutomatically(true)})}}
        compose.waitUntil(5000){model.state.value.powerChoices.size==2}
        assertTrue(calls.isEmpty());assertEquals("",model.state.value.campus.meterId)
        compose.onNodeWithText("学校目录里有同名楼栋，只需确认一次公寓。").assertExists()
        compose.onNodeWithText(paths.first().label).performScrollTo().assertIsDisplayed()
        val bitmap=instrumentation.uiAutomation.takeScreenshot()
        val file=File(instrumentation.targetContext.getExternalFilesDir(null),"power-apartment-choice.png")
        file.outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
        compose.onNodeWithText(paths.first().label).performClick()
        compose.waitUntil(5000){model.state.value.powerMatchIssue!=null}
        assertEquals("",model.state.value.campus.meterId)
        compose.onNodeWithText("重试匹配电表").performScrollTo().performClick()
        compose.waitUntil(5000){model.state.value.powerChoices.size==2 && model.state.value.powerMatchIssue==null}
        compose.onNodeWithText(paths.first().label).performScrollTo().performClick()
        compose.waitUntil(5000){model.state.value.campus.meterId==meter.id}
        assertEquals(listOf("a-room","a-room"),calls)
        assertEquals("36.80",model.state.value.cache.card)
        compose.onNodeWithText("电表已保存").assertExists()
        assertTrue(model.state.value.powerChoices.isEmpty())
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
    }
}
