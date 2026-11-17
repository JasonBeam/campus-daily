package com.beamjason.xiaorichang.net

import org.json.JSONObject
import com.beamjason.xiaorichang.data.text

data class LaundryStartDetails(val order:LaundryOrder,val moduleType:Int,val online:Boolean?,val requiresPreparation:Boolean) {
    companion object {
        fun read(j:JSONObject):LaundryStartDetails {
            val online=if(!j.has("online") || j.isNull("online"))null else j.opt("online").toString() in setOf("1","true")
            val hasDispenser=j.has("wp_order") && !j.isNull("wp_order")
            val cleanFinished=j.text("cleanSelfEndTime").isNotBlank()
            val cleanEnabled=j.opt("selfCleanEnable").toString() in setOf("1","true")
            return LaundryStartDetails(LaundryOrder.read(j),j.optInt("moduleType",-1),online,
                hasDispenser || !cleanFinished && cleanEnabled && j.optDouble("selfCleanPrice",0.0)>0)
        }
    }
}
object ImmediatePolling {
    fun needed(r:CheckoutRecord?,now:Long=System.currentTimeMillis()):Boolean = r!=null && r.immediateStart && r.stage!=CheckoutStage.COMPLETED && r.startAttempt!="blocked" && r.order?.running!=true && now-r.createdAt in 0..600_000
    fun interval(r:CheckoutRecord?,activeSince:Long,now:Long=System.currentTimeMillis()):Long = if(!needed(r,now))30_000 else if(now-activeSince in 0..19_999)1000 else 3000
}
fun immediateOrderPath(id:String,control:Boolean):String {
    require(validOrderId(id))
    return "/api/v1/app/orders/$id/"+if(control)"control/start" else "detail?additional=price"
}
