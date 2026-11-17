package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.*
import org.junit.Assert.assertEquals
import org.junit.Test

class LaundryReminderTest {
    private fun decide(status:String,seconds:Int?=300,observed:Long=1_000_000,tracked:Boolean=true,reminded:Boolean=false,recent:Boolean=true)=
        laundryReminderAction(status,seconds,observed,1_010_000,tracked,reminded,recent)
    @Test fun onlyActualCompletionMayAnnounceSuccess() {
        for(status in listOf("51","52","53"))assertEquals(LaundryReminderAction.Clear,decide(status))
        assertEquals(LaundryReminderAction.Completed,decide("50"))
    }
    @Test fun historicalOrPreviouslyNotifiedOrdersStayQuiet() {
        assertEquals(LaundryReminderAction.Ignore,decide("50",tracked=false,recent=false))
        assertEquals(LaundryReminderAction.Ignore,decide("50",reminded=true))
        assertEquals(LaundryReminderAction.Ignore,decide("40",reminded=true))
    }
    @Test fun recentCompletionWithoutForecastStillAlertsOnce() {
        assertEquals(LaundryReminderAction.Completed,decide("50",tracked=false))
        assertEquals(LaundryReminderAction.Ignore,decide("50",tracked=false,reminded=true))
        assertEquals(LaundryReminderAction.Ignore,decide("50",tracked=false,observed=900_000))
    }
    @Test fun zeroCountdownOnlyRemindsTrackedRunningOrder() {
        assertEquals(LaundryReminderAction.Estimate(1_000_000),decide("40",0))
        assertEquals(LaundryReminderAction.Ignore,decide("40",0,tracked=false))
    }
    @Test fun forecastNeedsFreshRunningOrderAndValidRemainingTime() {
        assertEquals(LaundryReminderAction.Estimate(1_300_000),decide("40"))
        for(status in listOf("20","unknown"))assertEquals(LaundryReminderAction.Ignore,decide(status))
        for(seconds in listOf(null,-1,86401))assertEquals(LaundryReminderAction.Ignore,decide("40",seconds))
        assertEquals(LaundryReminderAction.Ignore,decide("40",observed=900_000))
        assertEquals(LaundryReminderAction.Ignore,decide("40",observed=1_200_000))
    }
}
