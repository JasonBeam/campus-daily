package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.data.CampusRefreshSchedule
import com.beamjason.xiaorichang.net.CampusClient
import com.beamjason.xiaorichang.net.CampusConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CampusRefreshParityTest {
    private val config=CampusConfig("fixture-user","fixture-token","fixture-school","fixture-card",buildingId="fixture-building")
    @Test fun failuresAndCancellationDoNotConsumeTheRefreshInterval() {
        var time=10L;val schedule=CampusRefreshSchedule{time}
        assertTrue(schedule.due("card"));assertTrue(schedule.due("card"))
        schedule.succeeded("card");assertFalse(schedule.due("card"));assertTrue(schedule.due("card",true))
        assertTrue(schedule.due("power"));assertTrue(schedule.due("other-card"))
        time+=300_000;assertTrue(schedule.due("card"))
        schedule.succeeded("card");time=0;assertTrue(schedule.due("card"))
        schedule.clear();assertTrue(schedule.due("card"))
    }
    @Test fun cancelledSchoolLoginDoesNotFallBackToAnotherRequest()=runBlocking {
        val paths=mutableListOf<String>()
        val api=CampusClient{path,_->paths+=path;throw CancellationException("fixture cancellation")}
        try{api.balance(config);fail("must propagate cancellation")}catch(_:CancellationException){}
        assertEquals(listOf("/ykt-mini/api/customer/loginBySysId"),paths)
    }
    @Test fun normalBalanceReadStillUsesSavedAccount()=runBlocking {
        val paths=mutableListOf<String>()
        val api=CampusClient{path,body->
            paths+=path;assertEquals(config.token,body.getString("acc_token"))
            if(path.endsWith("loginBySysId"))JSONObject().put("syscustid",config.syscustid) else "12.34"
        }
        assertEquals("12.34",api.balance(config))
        assertEquals(2,paths.size)
    }
}
