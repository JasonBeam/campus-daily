package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.campusPortalDocument
import org.junit.Assert.*
import org.junit.Test

class CampusPortalNavigationTest {
    @Test fun preservesCasQueryExactlyWithoutDoubleEncodingOrReordering() {
        val query="path=https%3A%2F%2Fportal.gdbtu.edu.cn%2Fmain.html%23%2FStudent&ticket=ST-test%2Bcase%252F&redirect=true"
        assertEquals("https://portal.gdbtu.edu.cn/main.html?$query",
            campusPortalDocument("https://portal.gdbtu.edu.cn/?$query"))
    }
    @Test fun handlesEmptyRootAndPreservesFragmentAndHttpsPort() {
        assertEquals("https://portal.gdbtu.edu.cn/main.html",campusPortalDocument("https://portal.gdbtu.edu.cn"))
        assertEquals("https://portal.gdbtu.edu.cn:443/main.html#/Student",campusPortalDocument("https://portal.gdbtu.edu.cn:443/#/Student"))
    }
    @Test fun leavesRealDocumentsAndUnrelatedOriginsUnchanged() {
        for(url in listOf("https://portal.gdbtu.edu.cn/main.html?ticket=ST-test","https://portal.gdbtu.edu.cn/api/",
            "https://cas.gdbtu.edu.cn/","https://ecykt.gdbtu.edu.cn/","http://portal.gdbtu.edu.cn/",
            "https://portal.gdbtu.edu.cn.evil.test/","https://user@portal.gdbtu.edu.cn/","https://portal.gdbtu.edu.cn:8443/"))
            assertNull(url,campusPortalDocument(url))
    }
}
