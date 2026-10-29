package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.core.WaterProfile
import com.beamjason.xiaorichang.net.*
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WaterParityTest {
    private val profile=WaterProfile("fixture-secret","fixture-provider","fixture-student","fixture-school","AABBCCDD","fixture-radio",1,1)
    private val identity=byteArrayOf(0x55,0xAA.toByte(),0xBB.toByte(),0xCC.toByte(),0xDD.toByte())+ByteArray(15)
    private class Store:WaterSessionPersistence {
        var value:ShowerSession?=null
        override fun load()=value
        override fun save(session:ShowerSession){value=ShowerSession.read(session.json())}
    }
    private inner class Transport:WaterTransport {
        var replies=mutableListOf<ByteArray>();val writes=mutableListOf<ByteArray>();var disconnected=0;var expected:String?=null
        override suspend fun connect(deviceName:String,expectedAddress:String?):String {expected=expectedAddress;return "fixture-address"}
        override suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?,onProbe:(String)->Unit)=VerifiedWaterTarget("fixture-address",identity)
        override suspend fun scanCandidates(name:String)=emptyList<BleCandidate>()
        override suspend fun exchange(bytes:ByteArray):ByteArray {writes+=bytes;return replies.removeAt(0)}
        override fun disconnect(){disconnected++}
    }
    private class Service:WaterService {
        var authorizations=0;var settlements=0
        override suspend fun authorize(profile:WaterProfile,frame:ByteArray):WaterAuthorization {
            authorizations++;return WaterAuthorization(profile.machineId,ByteArray(15),"00112233")
        }
        override suspend fun settle(profile:WaterProfile,frame:ByteArray):WaterReceipt {settlements++;return WaterReceipt(5)}
    }
    @Test fun authorizationRetainsLinkAndInactiveFinishRemainsUnderReviewAfterRestart()=runBlocking {
        val store=Store();val radio=Transport();val service=Service();val log=WaterDiagnostics()
        val controller=WaterController(radio,service,store,log)
        radio.replies+=byteArrayOf(0xAA.toByte())+ByteArray(8)
        controller.start(profile)
        assertEquals(0,radio.disconnected);assertEquals(ShowerStage.ACTIVE,store.value?.stage)
        radio.replies+=identity
        assertTrue(runCatching{controller.finish(profile)}.isFailure)
        val restarted=WaterController(radio,service,store)
        assertTrue(restarted.session!!.stateReviewRequired)
        assertEquals(1,service.authorizations);assertEquals(0,service.settlements)
        assertEquals(listOf(15,1),radio.writes.map{it.size})
        assertTrue(log.snapshot().toString().contains("FINISH_BLOCKED"))
        assertFalse(log.snapshot().toString().contains("\"CLOSE\""))
    }
    @Test fun readOnlyInspectionUsesOriginalDeviceAndKeepsAnActiveLink()=runBlocking {
        val store=Store().apply{value=ShowerSession(ShowerStage.ACTIVE,profile.machineId,"fixture-address",stateReviewRequired=true)}
        val radio=Transport();val service=Service();val controller=WaterController(radio,service,store)
        radio.replies+=byteArrayOf(0xA5.toByte())
        assertTrue(controller.review(profile));assertFalse(store.value!!.stateReviewRequired)
        assertEquals(0,radio.disconnected);assertEquals("fixture-address",radio.expected)
        radio.replies+=identity
        assertFalse(controller.review(profile));assertTrue(store.value!!.stateReviewRequired)
        assertEquals(1,radio.disconnected);assertEquals(0,service.authorizations);assertEquals(0,service.settlements)
        assertTrue(radio.writes.all{it.contentEquals(byteArrayOf(0xAA.toByte()))})
    }
    @Test fun malformedAuthorizationReleasesConnectionAndBlocksAnotherStart()=runBlocking {
        val radio=Transport();val store=Store();val service=Service();val controller=WaterController(radio,service,store)
        radio.replies+=byteArrayOf(0)
        assertTrue(runCatching{controller.start(profile)}.isFailure)
        assertEquals(1,radio.disconnected);assertEquals(ShowerStage.AUTHORIZATION_WRITE_PENDING,store.value?.stage)
        assertTrue(runCatching{controller.start(profile)}.isFailure);assertEquals(1,service.authorizations)
    }
    @Test fun legacySessionsAndDiagnosticsExcludePrivateData() {
        val old=JSONObject().put("stage","ACTIVE").put("machineId",profile.machineId).put("peripheralAddress","private-address")
        assertFalse(ShowerSession.read(old).stateReviewRequired)
        var saved="";val log=WaterDiagnostics(save={saved=it})
        repeat(210){log.record(WaterDiagnostics.Event.STATE_REPLY,ShowerStage.ACTIVE,identity)}
        assertEquals(200,log.snapshot().length())
        val restored=WaterDiagnostics(history=saved).snapshot().toString()
        for(secret in listOf(profile.secret,profile.studentId,profile.machineId,"private-address","authorizationId","acc_token"))assertFalse(restored.contains(secret))
        assertEquals(200,WaterDiagnostics(history=saved).snapshot().length())
    }
}
