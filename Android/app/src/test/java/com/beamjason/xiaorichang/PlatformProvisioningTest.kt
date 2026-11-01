package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.data.parseDevelopmentPlatform
import com.beamjason.xiaorichang.data.parseWaterPlatformImport
import com.beamjason.xiaorichang.data.migrateWaterToDirect
import com.beamjason.xiaorichang.net.DormIdentity
import com.beamjason.xiaorichang.net.WaterAccessSession
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
    @Test fun publicImportNeedsNoPreviousUserAndSurvivesSerialization() {
        val first=parseWaterPlatformImport(seed().toString())
        val restored=com.beamjason.xiaorichang.data.WaterSettings.read(first.json())
        assertTrue(restored.hasPlatform);assertFalse(restored.configured)
        assertEquals("",restored.studentId);assertEquals("",restored.machineId);assertEquals("",restored.room)
    }
    @Test fun publicImportRejectsFullOtherUserConfigAndNonIntegerProtocolFields() {
        for(field in listOf("student_id","studentId","machineId","schoolId","room","acc_token","address"))
            assertTrue(runCatching{parseWaterPlatformImport(seed().put(field,"private-placeholder").toString())}.isFailure)
        for(value in listOf(seed().put("version","1"),seed().put("typeID",1.5),seed().put("typeID",2147483648L),seed().put("secret","bad\nsecret")))
            assertTrue(runCatching{parseWaterPlatformImport(value.toString())}.isFailure)
    }
    @Test fun settledExpiredRemoteProfileMigratesOnlyForSameOwnerAndKeepsController() {
        val platform=parseWaterPlatformImport(seed().toString())
        val owner="a".repeat(64)
        val access=WaterAccessSession("A".repeat(43),owner,1,"own-user","own-school","fixture-ble",1,1)
        val previous=platform.copy(secret="",sid="",studentId="own-user",schoolId="own-school",machineId="11223344",address="fixture-radio",room="2栋504",access=access)
        val who=DormIdentity("own-user","own-school")
        val next=migrateWaterToDirect(previous,platform,who,owner,false)
        assertNull(next.access);assertEquals(previous.machineId,next.machineId);assertEquals(previous.address,next.address);assertEquals(previous.room,next.room)
        assertTrue(next.configured)
        assertTrue(runCatching{migrateWaterToDirect(previous,platform,who,owner,true)}.isFailure)
        assertTrue(runCatching{migrateWaterToDirect(previous,platform,who,"b".repeat(64),false)}.isFailure)
        assertTrue(runCatching{migrateWaterToDirect(previous,platform,DormIdentity("other-user","own-school"),owner,false)}.isFailure)
    }
}
