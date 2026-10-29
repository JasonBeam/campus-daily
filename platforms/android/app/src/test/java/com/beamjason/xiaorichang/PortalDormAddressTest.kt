package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.PortalDormAddress
import org.junit.Assert.*
import org.junit.Test

class PortalDormAddressTest {
    @Test fun explicitPortalAddressUsesBuildingNotUnitOrFloorAsRoom() {
        val d=PortalDormAddress.parse("示例校区2栋3号5层504房")!!
        assertEquals("2栋504",d.shortRoom);assertTrue(d.matches("示例校区",0));assertTrue(d.matches("2栋",1));assertTrue(d.matches("五楼",2));assertTrue(d.matches("504",3))
        assertFalse(d.matches("3栋",1));assertFalse(d.matches("教师2栋",1));assertFalse(d.matches("其他校区",0))
    }
    @Test fun incompleteOrAmbiguousRoomNumbersAreNotGuessed() {
        for(value in listOf("2504","2栋504","暂无宿舍","示例校区2栋3号5层"))assertNull(PortalDormAddress.parse(value))
    }
    @Test fun powerRoomRequiresExactRoomIdentity() {
        val d=PortalDormAddress.parse("示例校区2栋5楼504室")!!
        assertTrue(d.matchesMeterRoom("2栋 · 504"));assertFalse(d.matchesMeterRoom("12栋504"));assertFalse(d.matchesMeterRoom("2栋5040"))
    }
    @Test fun sameResidenceFormattingRetainsMeterWhileOtherCampusDoesNot() {
        val d=PortalDormAddress.parse("示例校区2栋3号5层504房")!!
        val own=listOf("示例校区","2栋","五楼","504")
        assertTrue(d.keepsPowerBinding(own,"示例校区 · 2栋 · 五楼 · 504",null))
        assertTrue(d.keepsPowerBinding(own,"2栋504",null))
        assertTrue(d.keepsPowerBinding(own,"旧版标签","2栋 · 504"))
        assertFalse(d.keepsPowerBinding(listOf("其他校区","2栋","五楼","504"),"2栋504","2栋504"))
        assertFalse(d.keepsPowerBinding(own,"12栋504","2栋5040"))
        assertFalse(d.keepsPowerBinding(emptyList(),"2栋504","2栋504"))
    }
    @Test fun movedRequiresTwoCompleteAndDifferentResidences() {
        val original="示例校区2栋3号5层504房"
        assertFalse(PortalDormAddress.hasMoved(original,"示例校区 2栋3号5层504房"))
        assertTrue(PortalDormAddress.hasMoved(original,"示例校区2栋3号5层505房"))
        assertTrue(PortalDormAddress.hasMoved(original,"其他校区2栋3号5层504房"))
        assertFalse(PortalDormAddress.hasMoved("",original))
        assertFalse(PortalDormAddress.hasMoved(original,"暂无宿舍"))
    }
}
