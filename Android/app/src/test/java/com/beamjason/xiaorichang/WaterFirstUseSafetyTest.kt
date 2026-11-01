package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.core.WaterProfile
import com.beamjason.xiaorichang.net.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class WaterFirstUseSafetyTest {
    private val profile=WaterProfile("fixture-secret","fixture-provider","student","school","AABBCCDD","fixture-radio",1,1)
    private fun frame(id:String)=byteArrayOf(0x55)+id.chunked(2).map{it.toInt(16).toByte()}.toByteArray()+ByteArray(15)
    private class Store:WaterSessionPersistence {
        var value:ShowerSession?=null;val stages=mutableListOf<ShowerStage>()
        override fun load()=value
        override fun save(session:ShowerSession){value=session;stages+=session.stage}
    }
    private class Service:WaterService {
        var authorizations=0
        override suspend fun authorize(profile:WaterProfile,frame:ByteArray):WaterAuthorization {authorizations++;error("fixture network uncertain")}
        override suspend fun settle(profile:WaterProfile,frame:ByteArray):WaterReceipt {error("unexpected settlement")}
    }
    private class Transport(val identity:ByteArray?,val events:MutableList<String>):WaterTransport {
        override suspend fun connect(deviceName:String,expectedAddress:String?):String=error("unexpected direct connection")
        override suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?,onProbe:(String)->Unit):VerifiedWaterTarget {
            events+="verify"
            return VerifiedWaterTarget("fixture-address",identity ?: error("unreadable"))
        }
        override suspend fun scanCandidates(name:String):List<BleCandidate> = error("unexpected scan")
        override suspend fun exchange(bytes:ByteArray):ByteArray {events+="write";error("unexpected command")}
        override fun disconnect(){events+="disconnect"}
    }
    @Test fun unverifiedOrWrongControllerNeverCreatesSessionOrRequestsAuthorization()=runBlocking {
        for(identity in listOf(null,frame("01020304"))) {
            val store=Store();val service=Service();val events=mutableListOf<String>()
            val controller=WaterController(Transport(identity,events),service,store)
            assertTrue(runCatching{controller.start(profile)}.isFailure)
            assertEquals(0,service.authorizations);assertNull(store.value);assertEquals(listOf("verify","disconnect"),events)
        }
    }
    @Test fun uncertainAuthorizationIsPersistedAndCannotBeRepeated()=runBlocking {
        val store=Store();val service=Service();val events=mutableListOf<String>()
        val controller=WaterController(Transport(frame("AABBCCDD"),events),service,store)
        assertTrue(runCatching{controller.start(profile)}.isFailure)
        assertEquals(1,service.authorizations);assertEquals(ShowerStage.AUTHORIZATION_PENDING,store.value?.stage)
        assertTrue(runCatching{controller.start(profile)}.isFailure)
        assertEquals(1,service.authorizations);assertEquals(listOf("verify","disconnect"),events)
    }
}
