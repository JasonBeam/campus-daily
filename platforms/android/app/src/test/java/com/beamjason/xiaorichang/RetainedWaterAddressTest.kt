package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.data.WaterSettings
import com.beamjason.xiaorichang.data.previouslyVerifiedAddress
import org.junit.Assert.*
import org.junit.Test

class RetainedWaterAddressTest {
    @Test fun retainsOnlyForSameOwnerSchoolMachineAndRoom() {
        val saved=WaterSettings(studentId="student",schoolId="school",machineId="AABBCCDD",address="fixture-address",room="2栋504")
        fun lookup(student:String="student",school:String="school",machine:String="aabbccdd",room:String="2栋504") =
            previouslyVerifiedAddress(saved,student,school,machine,room)
        assertEquals("fixture-address",lookup())
        assertNull(lookup(student="other"));assertNull(lookup(school="other"))
        assertNull(lookup(machine="11223344"));assertNull(lookup(room="2栋505"))
        assertNull(lookup(student=""));assertNull(lookup(machine=""))
        assertNull(previouslyVerifiedAddress(saved.copy(address=null),"student","school","AABBCCDD","2栋504"))
    }
}
