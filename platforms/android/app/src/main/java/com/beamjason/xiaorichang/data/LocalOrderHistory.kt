package com.beamjason.xiaorichang.data

import android.content.Context
import com.beamjason.xiaorichang.ble.ShowerSession
import com.beamjason.xiaorichang.ble.ShowerStage
import com.beamjason.xiaorichang.net.CheckoutRecord
import com.beamjason.xiaorichang.security.SecureStore
import org.json.JSONObject
import org.json.JSONArray
import java.security.MessageDigest
import java.math.BigDecimal

data class LocalOrderRecord(val id:String,val owner:String,val kind:String,val title:String,val startedAt:Long,
    val status:String,val amount:String?,val amountLabel:String) {
    fun json()=JSONObject().put("id",id).put("owner",owner).put("kind",kind).put("title",title).put("startedAt",startedAt)
        .put("status",status).put("amount",amount).put("amountLabel",amountLabel)
    companion object {
        fun digest(text:String)=MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString(""){"%02x".format(it)}
        fun waterOwner(school:String,student:String)=digest(school+"\u0000"+student)
        fun water(s:ShowerSession):LocalOrderRecord? {
            val owner=s.historyOwner?.takeIf{it.isNotBlank()} ?: return null
            val settled=s.stage==ShowerStage.SETTLED
            return LocalOrderRecord(digest("water|$owner|${s.machineId}|${s.startedAt}"),owner,"water","热水洗澡",s.startedAt,
                if(settled)"服务器已确认结算" else "热水记录待核对",
                if(settled)s.payFen?.let{BigDecimal(it).movePointLeft(2).toPlainString()}else null,
                if(settled)"结算金额" else "尚未确认扣费")
        }
        fun laundry(r:CheckoutRecord)=LocalOrderRecord(digest("laundry|${r.accountId}|${r.deviceId}|${r.createdAt}"),r.accountId,"laundry",
            "洗衣 · ${r.programName}",r.createdAt,r.order?.label ?: "下单结果待核对",r.order?.priceYuan,
            if(r.order?.payFlag=="1")"服务器订单金额（退款请到U净核对）" else "订单金额（未确认付款）")
        fun read(j:JSONObject)=LocalOrderRecord(j.getString("id"),j.getString("owner"),j.getString("kind"),j.getString("title"),
            j.getLong("startedAt"),j.getString("status"),j.text("amount").takeIf{it.isNotBlank()},j.getString("amountLabel"))
        fun recent(records:List<LocalOrderRecord>,owners:Map<String,String>,now:Long=System.currentTimeMillis()):List<LocalOrderRecord> =
            records.filter{owners[it.kind]==it.owner && it.startedAt in (now-7L*86400000)..now}
                .associateBy{it.id}.values.sortedWith(compareByDescending<LocalOrderRecord>{it.startedAt}.thenBy{it.id})
    }
}

/** Encrypted summaries, separate from transaction state; history failures never issue controls. */
class LocalOrderHistoryStore(context:Context) {
    private val store=SecureStore(context.applicationContext)
    private val indexKey="local.orders.index.v1"
    fun record(record:LocalOrderRecord?,onlyIfMissing:Boolean=false) {
        if(record==null)return
        try {
            val key="local.orders."+record.id
            if(onlyIfMissing && store.get(key)!=null)return
            val bytes=record.json().toString().toByteArray()
            if(store.get(key)?.contentEquals(bytes)==true)return
            store.put(key,bytes)
            val index=store.get(indexKey)?.let{JSONArray(it.toString(Charsets.UTF_8))} ?: JSONArray()
            if((0 until index.length()).none{index.getString(it)==key}) {index.put(key);store.put(indexKey,index.toString().toByteArray())}
        } catch(_:Exception){issue="部分本机历史记录未能保存，请保留当前订单并稍后重试。"}
    }
    fun load(owners:Map<String,String>):List<LocalOrderRecord> {
        val index=store.get(indexKey)?.let{JSONArray(it.toString(Charsets.UTF_8))} ?: return emptyList()
        val records=mutableListOf<LocalOrderRecord>()
        for(i in 0 until index.length()) {
            try {
                val key=index.getString(i);require(key.matches(Regex("local\\.orders\\.[0-9a-f]{64}")))
                val bytes=store.get(key) ?: error("记录缺失")
                records.add(LocalOrderRecord.read(JSONObject(bytes.toString(Charsets.UTF_8))))
            } catch(_:Exception){issue="部分本机历史记录无法读取，列表可能不完整。"}
        }
        return LocalOrderRecord.recent(records,owners)
    }
    companion object { var issue:String?=null }
}
