package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.ble.mayResumeBleAction
import org.junit.Assert.*
import org.junit.Test

class BlePermissionActionTest {
    @Test fun transactionAndInspectionResumeOnlyOnTheWaterPage() {
        for(action in listOf("start","finish","inspect","review")) {
            assertTrue(mayResumeBleAction(action,"water"))
            for(page in listOf("dorm","setup","","login"))assertFalse(mayResumeBleAction(action,page))
        }
    }
    @Test fun dormScanCannotRunOnAnotherPageOrAfterProcessRecreation() {
        assertTrue(mayResumeBleAction("scan","dorm"))
        assertFalse(mayResumeBleAction("scan","water"))
        assertFalse(mayResumeBleAction("","water"))
        assertFalse(mayResumeBleAction("unknown","dorm"))
    }
}
