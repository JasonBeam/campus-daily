package com.beamjason.xiaorichang

import android.app.Application
import android.content.Context
import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.core.WaterProfile
import com.beamjason.xiaorichang.data.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.security.SecureStore
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.IOException

@RunWith(AndroidJUnit4::class)
class RefreshAndWaterParityTest {
    private class IsolatedApplication(private val base:Context):Application() {
        private val prefix="refresh-parity-${System.nanoTime()}"
        init{attachBaseContext(base)}
        override fun getApplicationContext():Context=this
        override fun getSharedPreferences(name:String,mode:Int)=base.getSharedPreferences("$prefix-$name",mode)
        override fun getNoBackupFilesDir()=File(base.cacheDir,prefix).apply{mkdirs()}
    }
    private suspend fun awaitIdle(model:CampusViewModel) {
        withTimeout(5000){while(model.state.value.busy.any{it in setOf("card","power")})delay(10)}
    }
    @Test fun failedOrCancelledBalanceReadsKeepCacheAndAllowImmediateRetry()=runBlocking {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        for(cancel in listOf(false,true)) {
            val app=IsolatedApplication(instrumentation.targetContext)
            val c=CampusConfig("fixture-owner","fixture-token","fixture-school","fixture-card",buildingId="building",meterId="meter")
            val cache=BalanceCache(c.owner,"8.88",100,PowerMeter("meter","测试宿舍","10","5",null,""),200,c.cardOwner)
            val storage=SecureStore(app)
            storage.put("app.settings.v2",JSONObject().put("campus",c.json()).put("water",WaterSettings().json()).toString().toByteArray())
            storage.put("campus.balance-cache",cache.json().toString().toByteArray())
            val failRead=java.util.concurrent.atomic.AtomicBoolean(true)
            val api=CampusClient{path,_->
                if(failRead.get()){if(cancel)throw CancellationException("fixture cancellation") else throw IOException("fixture network failure")}
                when {
                    path.endsWith("loginBySysId")->JSONObject().put("syscustid",c.syscustid)
                    path.endsWith("getUserBalance")->"12.34"
                    else->JSONArray().put(JSONObject().put("comAddress","meter").put("piplineName","测试宿舍").put("remaining","15").put("leftMoney","9"))
                }
            }
            lateinit var model:CampusViewModel
            instrumentation.runOnMainSync{model=CampusViewModel(app,null,campusApi=api);model.refresh(true)}
            awaitIdle(model)
            assertEquals("8.88",model.state.value.cache.card);assertEquals(100L,model.state.value.cache.cardAt)
            assertEquals(200L,model.state.value.cache.powerAt)
            if(cancel){assertNull(model.state.value.cardError);assertNull(model.state.value.powerError)}
            else {assertNotNull(model.state.value.cardError);assertNotNull(model.state.value.powerError)}
            failRead.set(false)
            instrumentation.runOnMainSync{model.refresh(true)}
            awaitIdle(model)
            assertEquals("12.34",model.state.value.cache.card);assertEquals("15",model.state.value.cache.power?.remaining)
            assertNull(model.state.value.cardError);assertNull(model.state.value.powerError)
            assertEquals(c,model.state.value.campus)
        }
    }
    @Test fun retainedAuthorizationCanFinishOnceAndDisconnectAfterSettlement()=runBlocking {
        val identity=byteArrayOf(0x55,0xAA.toByte(),0xBB.toByte(),0xCC.toByte(),0xDD.toByte())+ByteArray(15)
        val profile=WaterProfile("fixture-secret","fixture-provider","fixture-student","fixture-school","AABBCCDD","fixture-radio",1,1)
        var saved:ShowerSession?=null;var disconnects=0;var settlements=0
        val replies=ArrayDeque(listOf(byteArrayOf(0xAA.toByte())+ByteArray(8),byteArrayOf(0xA5.toByte()),identity))
        val writes=mutableListOf<ByteArray>()
        val radio=object:WaterTransport {
            override suspend fun connect(deviceName:String,expectedAddress:String?):String {assertEquals("fixture-address",expectedAddress);return "fixture-address"}
            override suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?,onProbe:(String)->Unit)=VerifiedWaterTarget("fixture-address",identity)
            override suspend fun scanCandidates(name:String)=emptyList<BleCandidate>()
            override suspend fun exchange(bytes:ByteArray):ByteArray {writes+=bytes;return replies.removeFirst()}
            override fun disconnect(){disconnects++}
        }
        val service=object:WaterService {
            override suspend fun authorize(profile:WaterProfile,frame:ByteArray)=WaterAuthorization(profile.machineId,ByteArray(15),"00112233")
            override suspend fun settle(profile:WaterProfile,frame:ByteArray):WaterReceipt {settlements++;return WaterReceipt(5)}
        }
        val store=object:WaterSessionPersistence {
            override fun load()=saved
            override fun save(session:ShowerSession){saved=ShowerSession.read(session.json())}
        }
        val controller=WaterController(radio,service,store)
        controller.start(profile);assertEquals(0,disconnects)
        assertEquals(5L,controller.finish(profile).payFen)
        assertEquals(ShowerStage.SETTLED,saved!!.stage);assertFalse(saved!!.stateReviewRequired)
        assertEquals(1,disconnects);assertEquals(1,settlements);assertEquals(listOf(15,1,5),writes.map{it.size})
        assertTrue(runCatching{controller.finish(profile)}.isFailure);assertEquals(1,settlements)
    }
    @Test fun diagnosticSharingCannotExposeOtherPrivateFiles() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val authority="${BuildConfig.APPLICATION_ID}.fileprovider"
        val provider=context.packageManager.resolveContentProvider(authority,0)!!
        assertFalse(provider.exported);assertTrue(provider.grantUriPermissions)
        val file=File(context.cacheDir,"water-diagnostics/report.json")
        assertEquals(authority,FileProvider.getUriForFile(context,authority,file).authority)
        assertTrue(runCatching{FileProvider.getUriForFile(context,authority,File(context.filesDir,"private-state.json"))}.isFailure)
    }
}
