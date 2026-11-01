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

    private fun duplicateTree():MutableMap<String,List<Option>> {
        val tree=mutableMapOf("root" to listOf(Option("campus","示例校区")),"campus" to listOf(Option("a","半山公寓"),Option("b","兰香公寓")))
        for(group in listOf("a","b")) {
            tree[group]=listOf(Option("$group-building","2栋"));tree["$group-building"]=listOf(Option("$group-floor","5楼"))
            tree["$group-floor"]=listOf(Option("$group-room","504"));tree["$group-room"]=emptyList()
        }
        return tree
    }
    @Test fun duplicateCompletePathsAskApartmentBeforeAnyMeterRead()=runBlocking {
        val tree=duplicateTree()
        val result=discoverCampusPower(address,{tree[it ?: "root"] ?: emptyList()},{fail("No balances before apartment choice");emptyList()})
        assertNull(result.suggestion)
        assertEquals(listOf("半山公寓 · 2栋 · 5楼 · 504","兰香公寓 · 2栋 · 5楼 · 504"),result.choices.map{it.label})
        val calls=mutableListOf<String>()
        val selected=selectCampusPower(result.choices.first(),address){calls+=it;listOf(PowerMeter("own","504","10","5",null,""))}
        assertEquals(listOf("a-room"),calls);assertEquals("own",selected?.meter?.id)
    }
    @Test fun floorDisambiguatesSameBuildingNumbers()=runBlocking {
        val tree=duplicateTree();tree["b-building"]=listOf(Option("other-floor","4楼"))
        val result=discoverCampusPower(address,{tree[it ?: "root"] ?: emptyList()},{assertEquals("a-room",it);listOf(meter("own"))})
        assertEquals("own",result.suggestion?.meter?.id);assertTrue(result.choices.isEmpty())
    }
    @Test fun cyclesDiscardPartialResults()=runBlocking {
        val tree=duplicateTree();tree["b-room"]=listOf(Option("b","返回上层"))
        val result=discoverCampusPower(address,{tree[it ?: "root"] ?: emptyList()},{fail("No partial search balance");emptyList()})
        assertNull(result.suggestion);assertTrue(result.choices.isEmpty())
    }
    @Test fun bareRoomNeedsCompletePathAndMultipleMetersNeedConfirmation()=runBlocking {
        val tree=duplicateTree();tree["campus"]=listOf(Option("a","公寓甲"));tree["a-floor"]=emptyList()
        val bare=PowerMeter("own","504","10","5",null,"")
        val unknown=discoverCampusPower(address,{tree[it ?: "root"] ?: emptyList()},{listOf(bare)})
        assertNull(unknown.suggestion)
        tree["a-floor"]=listOf(Option("a-room","504"))
        val multiple=discoverCampusPower(address,{tree[it ?: "root"] ?: emptyList()},{listOf(bare,meter("second"))})
        assertNull(multiple.suggestion)
    }
    @Test fun failedDirectoryCannotProduceFalseUniqueMatch()=runBlocking {
        val tree=duplicateTree()
        try {
            discoverCampusPower(address,{if(it=="b")throw IllegalStateException("offline");tree[it ?: "root"] ?: emptyList()},{fail("No partial search balance");emptyList()})
            fail("Must report failure")
        } catch(e:IllegalStateException){assertEquals("offline",e.message)}
    }
}
