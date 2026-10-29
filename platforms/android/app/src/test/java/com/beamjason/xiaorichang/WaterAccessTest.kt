package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.data.WaterSettings
import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import org.json.JSONArray

class WaterAccessTest {
    @Test fun remoteSessionPersistsWithoutAnyPlatformSigningKey() {
        val campus=CampusConfig("owner","token","450010","card")
        val access=WaterAccessSession("A".repeat(43),campus.waterAccessOwner(),System.currentTimeMillis()+3600000,"own-user","own-school","fixture-ble",1,1)
        val settings=WaterSettings(studentId=access.studentId,schoolId=access.schoolId,machineId="11223344",bleName=access.bleName,typeId=1,version=1,access=access)
        val restored=WaterSettings.read(settings.json())
        assertTrue(restored.hasPlatform);assertTrue(restored.configured);assertEquals("",restored.secret);assertEquals("",restored.sid)
        assertEquals(access,restored.access);assertTrue(access.current)
        assertTrue(runCatching{restored.copy(studentId="another-user").profile().validate()}.isFailure)
        assertNotEquals(campus.waterAccessOwner(),campus.copy(syscustid="another-owner").waterAccessOwner())
    }
    @Test fun bootstrapRequiresExactResidenceAndKeepsReadinessSeparate() {
        val names=listOf("示例校区","2栋","五楼","504")
        val path=JSONArray();val levels=JSONArray()
        names.forEachIndexed{i,name->val row=JSONObject().put("id","fixture-$i").put("name",name);path.put(row);levels.put(JSONArray().put(row))}
        val root=JSONObject().put("levels",levels).put("path",path).put("matched",true).put("transactionsEnabled",false)
            .put("machines",JSONArray().put(JSONObject().put("id","11223344").put("name","fixture").put("mac","11:22:33:44:55:66")))
        val result=WaterAccessBootstrap.read(root,"示例校区2栋3号5层504房")
        assertTrue(result.matched);assertEquals(4,result.path.size);assertFalse(result.transactionsEnabled)
        assertTrue(runCatching{WaterAccessBootstrap.read(root,"其他校区2栋5层504房")}.isFailure)
        root.put("matched",false);assertTrue(runCatching{WaterAccessBootstrap.read(root,"示例校区2栋5层504房")}.isFailure)
    }
}
