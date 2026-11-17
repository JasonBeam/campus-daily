package com.beamjason.xiaorichang.net

sealed interface LaundryReminderAction {
    data object Ignore:LaundryReminderAction
    data object Clear:LaundryReminderAction
    data object Completed:LaundryReminderAction
    data class Estimate(val deadline:Long):LaundryReminderAction
}
fun laundryReminderAction(status:String,remaining:Int?,observed:Long,now:Long,tracked:Boolean,reminded:Boolean,recentOrder:Boolean=false):LaundryReminderAction {
    if(observed>now+5000 || now-observed>=60_000)return LaundryReminderAction.Ignore
    if(status=="50")return if(recentOrder && !reminded)LaundryReminderAction.Completed else LaundryReminderAction.Ignore
    if(status in setOf("51","52","53"))return if(tracked)LaundryReminderAction.Clear else LaundryReminderAction.Ignore
    if(status !in setOf("21","22","24","29","30","35","40") || remaining==null || remaining !in 0..86400 || reminded)return LaundryReminderAction.Ignore
    if(remaining==0 && !tracked)return LaundryReminderAction.Ignore
    return LaundryReminderAction.Estimate(observed+remaining*1000L)
}
