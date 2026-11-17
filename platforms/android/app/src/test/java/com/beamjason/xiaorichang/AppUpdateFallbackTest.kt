package com.beamjason.xiaorichang
import com.beamjason.xiaorichang.data.loadAndroidUpdate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
class AppUpdateFallbackTest {
    private val body="""{"tag_name":"v0.9.0","html_url":"https://github.com/JasonBeam/campus-daily/releases/tag/v0.9.0","assets":[{"name":"CampusDaily-0.3.0-alpha25-code27-debug.apk"}]}""".toByteArray()
    @Test fun rateLimitFallsBackWithoutAccountToken()=runTest {
        val sources=mutableListOf<String>()
        val value=loadAndroidUpdate { sources+=it;if(sources.size==1)error("HTTP 403");body }
        assertEquals(27,value.code);assertEquals(2,sources.size);assertEquals("https://jasonbeam.github.io/campus-daily/updates.json",sources.last())
    }
    @Test fun malformedPrimaryCannotHideFallback()=runTest {
        var calls=0;val value=loadAndroidUpdate {calls++;if(calls==1)"{}".toByteArray() else body}
        assertEquals(27,value.code);assertEquals(2,calls)
    }
    @Test fun cancelledCheckDoesNotTryAnotherSource()=runTest {
        var calls=0
        try {loadAndroidUpdate{calls++;throw CancellationException()};fail("must cancel")}catch(_:CancellationException){}
        assertEquals(1,calls)
    }
    @Test fun offlineCheckCannotClaimToBeCurrent()=runTest {
        var calls=0;assertTrue(runCatching{loadAndroidUpdate{calls++;error("offline")}}.isFailure);assertEquals(2,calls)
    }
}
