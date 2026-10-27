package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.WaterReceipt
import com.beamjason.xiaorichang.core.WaterProtocol
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WaterReceiptTest {
    @Test fun integerFenMatchesIosReceipt() {
        assertEquals("1.23",WaterReceipt.parse(JSONObject().put("pay",123)).yuan)
        assertEquals(123L,WaterReceipt.parse(JSONObject().put("pay","123")).payFen)
        assertEquals(0L,WaterReceipt.parse(JSONObject().put("pay",0)).payFen)
        assertEquals(100_000_000_000L,WaterReceipt.parse(JSONObject().put("pay","100000000000")).payFen)
    }
    @Test fun invalidFeeIsNeverTruncatedOrGuessed() {
        for(value in listOf(1.9,"1.9",true,-1,"+1"," 1","1e2","100000000001","999999999999999999999999")) {
            assertNull(value.toString(),WaterReceipt.parse(JSONObject().put("pay",value)).payFen)
        }
        assertNull(WaterReceipt.parse(JSONObject()).payFen)
    }
    @Test fun busyControllerCannotBeUsedAsIdentity() {
        val result=runCatching {WaterProtocol.identity(byteArrayOf(0xA5.toByte()))}
        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()?.message?.contains("正在使用")==true)
    }
}
