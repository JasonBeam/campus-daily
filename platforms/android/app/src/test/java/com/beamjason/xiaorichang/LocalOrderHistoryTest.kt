package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.data.LocalOrderRecord
import com.beamjason.xiaorichang.ble.ShowerSession
import com.beamjason.xiaorichang.ble.ShowerStage
import com.beamjason.xiaorichang.net.*
import org.junit.Test
import org.junit.Assert.*

class LocalOrderHistoryTest {
    private val now=1800000000000L
    private fun row(id:String,owner:String="a",offset:Long=0)=LocalOrderRecord(id,owner,"water","热水",now+offset,"待核对",null,"未确认扣费")
    @Test fun filtersWeekBoundaryOtherAccountsAndFuture() {
        val rows=listOf(row("now"),row("boundary",offset=-7L*86400000),row("old",offset=-7L*86400000-1),row("future",offset=1),row("other",owner="b"))
        assertEquals(listOf("now","boundary"),LocalOrderRecord.recent(rows,mapOf("water" to "a"),now).map{it.id})
        assertTrue(LocalOrderRecord.recent(rows,emptyMap(),now).isEmpty())
    }
    @Test fun replacesDuplicateSnapshotAndRoundTrips() {
        val old=row("same");val updated=old.copy(status="已结算",amount="1.23")
        assertEquals(listOf(updated),LocalOrderRecord.recent(listOf(old,LocalOrderRecord.read(updated.json())),mapOf("water" to "a"),now))
    }
    @Test fun pendingWaterNeverClaimsDebitAndLegacyKeepsUnknownOwner() {
        val old=ShowerSession(ShowerStage.SETTLEMENT_PENDING,"00112233","radio",payFen=123)
        assertNull(LocalOrderRecord.water(old))
        val attributed=old.copy(historyOwner="a")
        assertNull(LocalOrderRecord.water(attributed)?.amount)
        val done=LocalOrderRecord.water(attributed.copy(stage=ShowerStage.SETTLED))!!
        assertEquals("1.23",done.amount)
        assertEquals(done.id,LocalOrderRecord.water(attributed)?.id)
        assertEquals(done,LocalOrderRecord.read(done.json()))
        assertNull(ShowerSession.read(old.json()).historyOwner)
    }
    @Test fun quotedLaundryPriceIsNotAChargeAndReceiptDoesNotDuplicate() {
        val pending=CheckoutRecord("account","machine",1,"普通洗",999,createdAt=now)
        assertNull(LocalOrderRecord.laundry(pending).amount)
        val order=LaundryOrder("order123","machine","50","1",1,"1.90",null,null,"")
        val paid=LocalOrderRecord.laundry(pending.copy(orderId=order.id,order=order))
        assertEquals("1.90",paid.amount)
        assertEquals(LocalOrderRecord.laundry(pending).id,paid.id)
        assertNotEquals(LocalOrderRecord.laundry(pending.copy(accountId="other")).id,paid.id)
    }
}
