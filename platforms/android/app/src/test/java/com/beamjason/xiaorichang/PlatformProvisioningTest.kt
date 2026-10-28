package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.data.parseDevelopmentPlatform
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PlatformProvisioningTest {
    private fun seed()=JSONObject().put("secret","fixture-secret").put("sid","fixture-provider").put("bleName","fixture-ble").put("typeID",1).put("version",1)
    @Test fun platformSeedDoesNotBindAnyPersonOrDevice() {
        val parsed=parseDevelopmentPlatform(seed().toString())
        assertTrue(parsed.hasPlatform);assertFalse(parsed.configured)
        assertEquals("",parsed.studentId);assertEquals("",parsed.schoolId);assertEquals("",parsed.machineId);assertNull(parsed.address)
    }
    @Test fun refusesPersonalAndDeviceFieldsInsteadOfSilentlyImportingThem() {
        for(field in listOf("studentId","schoolId","machineId","room","acc_token","address")) {
            assertTrue(field,runCatching{parseDevelopmentPlatform(seed().put(field,"private-placeholder").toString())}.isFailure)
        }
    }
    @Test fun rejectsMissingOutOfRangeAndConflictingProtocolFields() {
        for(value in listOf(seed().put("secret",""),seed().put("typeID",-1),seed().put("version",0),seed().put("typeId",2),seed().put("bleName","bad\nname")))
            assertTrue(runCatching{parseDevelopmentPlatform(value.toString())}.isFailure)
    }
}
