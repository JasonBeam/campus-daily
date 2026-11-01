package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.*
import org.junit.Assert.*
import org.junit.Test

class CampusPowerMatchScopeTest {
    private val original=CampusConfig(syscustid="demo-owner",custid="demo-card",token="demo-session",areaCode="demo-system",
        portalDormAddress="示例校区2栋3号5层504房",dorm="示例校区 · 2栋 · 五楼 · 504")
    @Test fun sameResidenceSaveSurvivesPendingLookup() {
        assertTrue(CampusPowerMatchScope(original).accepts(original.copy(dorm="2栋504")))
    }
    @Test fun changedAccountSessionResidenceOrManualMeterRejectsOldResult() {
        val scope=CampusPowerMatchScope(original)
        listOf(original.copy(syscustid="other"),original.copy(custid="other"),original.copy(token="new-session"),original.copy(areaCode="other"),
            original.copy(portalDormAddress="其他校区2栋3号5层504房"),original.copy(dorm="12栋504"),original.copy(buildingId="manual-building"),original.copy(meterId="manual-meter"))
            .forEach{assertFalse(scope.accepts(it))}
    }
}
