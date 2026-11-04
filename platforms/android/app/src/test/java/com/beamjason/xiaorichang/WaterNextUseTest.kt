package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.core.WaterProfile
import com.beamjason.xiaorichang.net.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class WaterNextUseTest {
    private val profile=WaterProfile("fixture","fixture","student","school","11223344","fixture",1,1)
    private val idle=byteArrayOf(0x55,0x11,0x22,0x33,0x44)+ByteArray(15)
    private val ack=byteArrayOf(0xAA.toByte())+ByteArray(8)
    private class Store:WaterSessionPersistence {
        var current:ShowerSession?=null;val history=mutableListOf<ShowerSession>();var failArchive=false;var failSave=false
        override fun load()=current
        override fun save(session:ShowerSession){check(!failSave);current=session}
        override fun archive(session:ShowerSession){check(!failArchive);if(session !in history)history+=session}
        override fun loadArchive()=history.toList()
    }
    private inner class Radio:WaterTransport {
        var identity=idle;val writes=mutableListOf<ByteArray>();var disconnects=0;var replies=mutableListOf<ByteArray>()
        override suspend fun connect(deviceName:String,expectedAddress:String?)="radio"
        override suspend fun connectVerified(deviceName:String,machineId:String,preferredAddress:String?,onProbe:(String)->Unit)=VerifiedWaterTarget("radio",identity)
        override suspend fun scanCandidates(name:String)=emptyList<BleCandidate>()
        override suspend fun exchange(bytes:ByteArray):ByteArray{writes+=bytes;return if(replies.isEmpty())ack else replies.removeAt(0)}
        override fun disconnect(){disconnects++}
    }
    private class Service(val store:Store):WaterService {
        var calls=0;var settlements=0;var rejected=false
        override suspend fun authorize(profile:WaterProfile,frame:ByteArray):WaterAuthorization {
            calls++;assertFalse(store.history.isEmpty());assertEquals(ShowerStage.AUTHORIZATION_PENDING,store.current?.stage)
            check(!rejected){"学校仍有未完成热水订单"}
            return WaterAuthorization(profile.machineId,ByteArray(15),"00112233")
        }
        override suspend fun settle(profile:WaterProfile,frame:ByteArray):WaterReceipt{settlements++;return WaterReceipt(1)}
    }
    @Test fun nextUsePreservesAllPendingStagesAndSurvivesRestart()=runBlocking {
        for(stage in ShowerStage.entries.filter{it!=ShowerStage.SETTLED}) {
            val s=Store();val r=Radio();val p=Service(s)
            val old=ShowerSession(stage,profile.machineId,"radio",authorizationId="AABBCCDD",stateReviewRequired=true,startedAt=123)
            s.current=old;val c=WaterController(r,p,s);c.startNext(profile)
            assertEquals(listOf(old),s.history);assertEquals(ShowerStage.ACTIVE,s.current?.stage)
            assertEquals(1,p.calls);assertEquals(0,p.settlements);assertEquals(listOf(15),r.writes.map{it.size})
            val reopened=WaterController(r,p,s);assertEquals(listOf(old),reopened.archivedSessions)
        }
    }
    @Test fun occupiedOrWrongDeviceDoesNotArchiveAuthorizeOrClose()=runBlocking {
        for(frame in listOf(byteArrayOf(0xA5.toByte()),byteArrayOf(0x55)+ByteArray(19))) {
            val s=Store();val r=Radio();val p=Service(s);val old=ShowerSession(ShowerStage.CLOSE_WRITE_PENDING,profile.machineId,"radio")
            s.current=old;r.identity=frame;val c=WaterController(r,p,s)
            assertTrue(runCatching{c.startNext(profile)}.isFailure)
            assertEquals(if(frame.contentEquals(byteArrayOf(0xA5.toByte())))old.copy(waitingForRelease=true)else old,s.current);assertTrue(s.history.isEmpty());assertEquals(0,p.calls);assertEquals(0,p.settlements);assertTrue(r.writes.isEmpty())
        }
    }
    @Test fun storageFailureCannotLosePreviousRecordOrSendAuthorization()=runBlocking {
        for(archiveFailure in listOf(true,false)) {
            val s=Store();val r=Radio();val p=Service(s);val old=ShowerSession(ShowerStage.SETTLEMENT_PENDING,profile.machineId,"radio")
            s.current=old;s.failArchive=archiveFailure;s.failSave=!archiveFailure;val c=WaterController(r,p,s)
            assertTrue(runCatching{c.startNext(profile)}.isFailure);assertTrue(c.blocked);assertEquals(old,s.current);assertEquals(0,p.calls)
            if(!archiveFailure)assertEquals(listOf(old),s.history)
        }
    }
    @Test fun schoolRejectionKeepsHistoryWithoutWritingAuthorization()=runBlocking {
        val s=Store();val r=Radio();val p=Service(s);val old=ShowerSession(ShowerStage.ACTIVE,profile.machineId,"radio")
        s.current=old;p.rejected=true;val c=WaterController(r,p,s)
        assertTrue(runCatching{c.startNext(profile)}.isFailure)
        assertEquals(listOf(old),s.history);assertEquals(ShowerStage.AUTHORIZATION_PENDING,s.current?.stage)
        assertTrue(r.writes.isEmpty());assertEquals(1,p.calls);assertEquals(0,p.settlements)
    }
    @Test fun laterUsersActiveReplyCannotRestoreOldOwnership()=runBlocking {
        val s=Store();val r=Radio();val p=Service(s)
        s.current=ShowerSession(ShowerStage.ACTIVE,profile.machineId,"radio",authorizationId="00112233",stateReviewRequired=true)
        val c=WaterController(r,p,s);r.replies+=byteArrayOf(0xA5.toByte())
        assertTrue(c.review(profile));assertTrue(c.session!!.stateReviewRequired)
        assertTrue(runCatching{c.finish(profile)}.isFailure);assertEquals(0,p.settlements);assertEquals(1,r.writes.size)
    }
    @Test fun busyWaitPersistsAndReviewDisconnects()=runBlocking {
        val s=Store();val r=Radio();val p=Service(s)
        s.current=ShowerSession(ShowerStage.ACTIVE,profile.machineId,"radio",authorizationId="00112233")
        r.identity=byteArrayOf(0xA5.toByte());val c=WaterController(r,p,s)
        assertTrue(runCatching{c.startNext(profile)}.isFailure);assertTrue(s.current!!.waitingForRelease)
        val reopened=WaterController(r,p,s);r.replies+=byteArrayOf(0xA5.toByte())
        assertTrue(reopened.review(profile));assertTrue(r.disconnects>=2)
        assertTrue(runCatching{reopened.finish(profile)}.isFailure);assertEquals(0,p.settlements)
        assertTrue(ShowerSession.read(s.current!!.json()).waitingForRelease)
    }
    @Test fun officialUnfinishedOrderHasDistinctMessage() {
        val failure=runCatching{WaterProvider.decodeResponse("""{"code":4060,"data":{}}""".toByteArray())}.exceptionOrNull()
        assertTrue(failure?.message?.contains("学校仍有未完成热水订单")==true)
        assertTrue(runCatching{WaterProvider.decodeResponse("""{"code":true,"data":{}}""".toByteArray())}.isFailure)
    }
}
