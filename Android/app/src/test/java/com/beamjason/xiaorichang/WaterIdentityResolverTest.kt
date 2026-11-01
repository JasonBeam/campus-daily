package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.ble.resolveWaterIdentity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class WaterIdentityResolverTest {
    private fun frame(id:String)=byteArrayOf(0x55)+id.chunked(2).map{it.toInt(16).toByte()}.toByteArray()+ByteArray(15)
    @Test fun multipleSameNameDevicesAreMatchedByHardwareIdNotSignalOrder()=runTest {
        val calls=mutableListOf<String>();var disconnected=0
        val result=resolveWaterIdentity("AABBCCDD",null,{listOf("strong-other","own","weak-other")},
            {calls+=it;frame(if(it=="own")"AABBCCDD" else "01020304")},{disconnected++})
        assertEquals("own",result.address);assertEquals(listOf("strong-other","own"),calls)
        assertEquals(1,disconnected)
    }
    @Test fun staleSavedAddressFallsBackToFreshScanAndIsNotTriedTwice()=runTest {
        val calls=mutableListOf<String>();var scans=0;var disconnected=0
        val result=resolveWaterIdentity("AABBCCDD","old",{scans++;listOf("old","new")},
            {calls+=it;if(it=="old")error("offline");frame("AABBCCDD")},{disconnected++})
        assertEquals("new",result.address);assertEquals(listOf("old","new"),calls)
        assertEquals(1,scans);assertEquals(1,disconnected)
    }
    @Test fun confirmedSavedAddressSkipsScan()=runTest {
        val result=resolveWaterIdentity("aabbccdd","known",{fail("unexpected scan");emptyList()},
            {frame("AABBCCDD")},{fail("verified target must remain connected")})
        assertEquals("known",result.address)
    }
    @Test fun noMatchingIdentityNeverReturnsADevice()=runTest {
        var disconnected=0
        val result=runCatching {resolveWaterIdentity("AABBCCDD",null,{listOf("other","broken")},
            {if(it=="other")frame("01020304") else byteArrayOf(0x55)},{disconnected++})}
        assertTrue(result.isFailure);assertTrue(result.exceptionOrNull()?.message?.contains("不匹配")==true)
        assertEquals(2,disconnected)
    }
    @Test fun cancellationClosesProbeAndDoesNotScanFurther()=runTest {
        var disconnected=0;var count=0
        try {
            resolveWaterIdentity("AABBCCDD",null,{listOf("first","second")},
                {count++;throw CancellationException("cancelled")},{disconnected++})
            fail("must propagate cancellation")
        } catch(_:CancellationException) {}
        assertEquals(1,count);assertEquals(1,disconnected)
    }
    @Test fun unavailableDevicesAndEmptyScanGiveActionableErrors()=runTest {
        val none=runCatching {resolveWaterIdentity("AABBCCDD",null,{emptyList()},{error("no candidate")},{})}
        assertTrue(none.exceptionOrNull()?.message?.contains("未发现水控")==true)
        val unreadable=runCatching {resolveWaterIdentity("AABBCCDD",null,{listOf("busy")},{byteArrayOf(0xA5.toByte())},{})}
        assertTrue(unreadable.exceptionOrNull()?.message?.contains("无法读取")==true)
    }
    @Test fun timedOutCandidateIsDisconnectedBeforeTryingNext()=runTest {
        val calls=mutableListOf<String>();var disconnected=0
        val result=resolveWaterIdentity("AABBCCDD",null,{listOf("unresponsive","own")},
            {calls+=it;if(it=="unresponsive")delay(13_000);frame("AABBCCDD")},{disconnected++})
        assertEquals("own",result.address);assertEquals(listOf("unresponsive","own"),calls);assertEquals(1,disconnected)
    }
    @Test fun excessiveCandidatesDoNotTriggerUnboundedProbing()=runTest {
        var count=0
        val result=runCatching {resolveWaterIdentity("AABBCCDD",null,{(1..17).map(Int::toString)},
            {count++;frame("01020304")},{})}
        assertEquals(16,count);assertTrue(result.exceptionOrNull()?.message?.contains("较多")==true)
    }
}
