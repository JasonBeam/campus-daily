package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.ble.matchesWaterAdvertisement
import org.junit.Assert.*
import org.junit.Test

class WaterAdvertisementTest {
    @Test fun currentAdvertisingNameSurvivesStaleAndroidCache() {
        assertTrue(matchesWaterAdvertisement("BT19-S","old-controller-name","BT19-S"))
        assertTrue(matchesWaterAdvertisement("BT19-S","","BT19-S"))
    }
    @Test fun cachedNameStillWorksWhenLocalNameIsNotAdvertised() {
        assertTrue(matchesWaterAdvertisement("BT19-S","BT19-S",null))
        assertTrue(matchesWaterAdvertisement("BT19-S",null,"BT19-S"))
    }
    @Test fun unrelatedNearbyRadiosAreNotSelected() {
        assertFalse(matchesWaterAdvertisement("BT19-S","BT19-S-other",null))
        assertFalse(matchesWaterAdvertisement("BT19-S",null,null))
        assertFalse(matchesWaterAdvertisement("",null,""))
    }
}
