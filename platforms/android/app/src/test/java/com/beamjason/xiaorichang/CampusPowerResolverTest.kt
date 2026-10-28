package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class CampusPowerResolverTest {
    private val address=PortalDormAddress.parse("示例校区2栋3号5层504房")!!
    private fun meter(id:String)=PowerMeter(id,"2栋504","10","5",null,"")
    @Test fun fullHierarchyOnlyReadsOwnRoomAndUsesIndependentServerIds()=runBlocking {
        val tree=mapOf("root" to listOf(Option("campus","示例校区"),Option("other-campus","别的校区")),
            "campus" to listOf(Option("group","半山公寓")),"group" to listOf(Option("building","2栋"),Option("wrong-building","3栋")),
            "building" to listOf(Option("floor","5楼"),Option("wrong-floor","6楼")),
            "floor" to (501..519).map{Option("room-$it","$it")},"room-504" to emptyList())
        val calls=mutableListOf<String>();val meterCalls=mutableListOf<String>()
        val result=resolveCampusPower(address,{parent->val key=parent ?: "root";calls+=key;tree[key] ?: emptyList()},{parent->meterCalls+=parent;listOf(meter("server-meter"))})
        assertEquals("room-504",result?.building);assertEquals("server-meter",result?.meter?.id)
        assertEquals(listOf("room-504"),meterCalls);assertFalse(calls.contains("wrong-building"));assertFalse(calls.contains("other-campus"))
    }
    @Test fun duplicateRoomsAcrossResidenceGroupsNeedManualConfirmation()=runBlocking {
        val result=resolveCampusPower(address,{parent->when(parent){null->listOf(Option("campus","示例校区"));"campus"->listOf(Option("a","公寓甲"),Option("b","公寓乙"));else->emptyList()}},{parent->listOf(meter(parent))})
        assertNull(result)
    }
    @Test fun incompleteDepthLimitedSearchDoesNotPickAResult()=runBlocking {
        val result=resolveCampusPower(address,{parent->if(parent==null)listOf(Option("campus","示例校区"))else listOf(Option("$parent/next","分组"))},{fail("Not a leaf");emptyList()})
        assertNull(result)
    }
}
