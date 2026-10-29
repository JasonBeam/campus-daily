package com.beamjason.xiaorichang

import android.app.Application
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.security.SecureStore
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class CampusCardCacheMigrationTest {
    private class IsolatedApplication(private val base:Context):Application() {
        private val prefix="card-cache-${System.nanoTime()}"
        init {attachBaseContext(base)}
        override fun getSharedPreferences(name:String,mode:Int)=base.getSharedPreferences("$prefix-$name",mode)
        override fun getNoBackupFilesDir()=File(base.cacheDir,prefix).apply{mkdirs()}
    }
    @Test fun changedCardOrLegacyCacheCannotShowAnotherCardsBalanceButKeepsMeter() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        for(legacy in listOf(false,true)) {
            val app=IsolatedApplication(instrumentation.targetContext);val store=SecureStore(app)
            val old=CampusConfig(syscustid="fixture-owner",token="fixture-token",areaCode="fixture-campus",custid="old-card")
            val current=old.copy(custid="new-card",buildingId="fixture-room",meterId="fixture-meter")
            val power=PowerMeter("fixture-meter","2栋504","10","5",null,"")
            store.put("app.settings.v2",JSONObject().put("campus",current.json()).put("water",WaterSettings().json()).toString().toByteArray())
            store.put("campus.balance-cache",BalanceCache(old.owner,"88.88",100,power,200,if(legacy)"" else old.cardOwner).json().toString().toByteArray())
            lateinit var model:CampusViewModel
            instrumentation.runOnMainSync {model=CampusViewModel(app,null)}
            assertNull(model.state.value.cache.card);assertEquals(0L,model.state.value.cache.cardAt)
            assertEquals("fixture-meter",model.state.value.cache.power?.id)
            assertEquals(current.cardOwner,model.state.value.cache.cardOwner)
            app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
        }
    }
    @Test fun missingNewBindingDoesNotReloadPreviousDormsCachedPower() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val app=IsolatedApplication(instrumentation.targetContext);val store=SecureStore(app)
        val c=CampusConfig(syscustid="fixture-owner",token="fixture-token",areaCode="fixture-campus",custid="fixture-card")
        val power=PowerMeter("old-meter","2栋504","10","5",null,"")
        store.put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",WaterSettings().json()).toString().toByteArray())
        store.put("campus.balance-cache",BalanceCache(c.owner,"36.80",100,power,200,c.cardOwner).json().toString().toByteArray())
        lateinit var model:CampusViewModel
        instrumentation.runOnMainSync {model=CampusViewModel(app,null)}
        assertNull(model.state.value.cache.power);assertEquals(0L,model.state.value.cache.powerAt)
        assertEquals("36.80",model.state.value.cache.card)
        app.getSharedPreferences("private_state_v1",Context.MODE_PRIVATE).edit().clear().commit()
    }
}
