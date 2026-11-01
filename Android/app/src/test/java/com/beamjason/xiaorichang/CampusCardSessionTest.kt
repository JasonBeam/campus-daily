package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.CampusConfig
import org.junit.Assert.*
import org.junit.Test

class CampusCardSessionTest {
    private val original=CampusConfig(syscustid="owner",areaCode="campus",custid="card-a",token="session-a")
    @Test fun meterOrDormChangesDoNotInvalidateAnInFlightCardRead() {
        assertTrue(original.sameCardSession(original.copy(buildingId="other-meter",dorm="other-room")))
    }
    @Test fun differentCardOrLoginCannotReuseAnOldCardResponseOrCacheOwner() {
        val card=original.copy(custid="card-b")
        assertFalse(original.sameCardSession(card));assertNotEquals(original.cardOwner,card.cardOwner)
        assertFalse(original.sameCardSession(original.copy(token="new-session")))
        assertFalse(original.sameCardSession(original.copy(syscustid="other-owner")))
        assertFalse(original.sameCardSession(original.copy(areaCode="other-campus")))
    }
    @Test fun dormLookupSurvivesMeterUpdatesButRejectsAccountAndRoomChanges() {
        val c=original.copy(portalDormAddress="示例校区2栋3号5层504房",dorm="2栋504")
        assertTrue(c.sameDormSession(c.copy(buildingId="new-building",meterId="new-meter")))
        assertFalse(c.sameDormSession(c.copy(token="new-session")))
        assertFalse(c.sameDormSession(c.copy(custid="other-card")))
        assertFalse(c.sameDormSession(c.copy(dorm="2栋505")))
        assertFalse(c.sameDormSession(c.copy(portalDormAddress="示例校区2栋3号5层505房")))
    }
}
