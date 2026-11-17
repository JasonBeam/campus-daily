package com.beamjason.xiaorichang.data

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.beamjason.xiaorichang.MainActivity
import com.beamjason.xiaorichang.net.CheckoutRecord
import com.beamjason.xiaorichang.net.LaundryReminderAction
import com.beamjason.xiaorichang.net.laundryReminderAction
import java.security.MessageDigest

/** Local estimates only in the background. No network or device control from a receiver. */
class LaundryReminders(private val context:Context) {
    private val prefs=context.getSharedPreferences("laundry.reminders",Context.MODE_PRIVATE)
    val enabled get()=prefs.getBoolean("enabled",false)
    private val alarms=context.getSystemService(AlarmManager::class.java)
    private fun pending()=PendingIntent.getBroadcast(context,0,Intent(context,LaundryReminderReceiver::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun setEnabled(value:Boolean) {
        prefs.edit().putBoolean("enabled",value).commit()
        if(!value) clear()
    }
    private fun clear() {
        alarms.cancel(pending()); NotificationManagerCompat.from(context).cancel(504)
        prefs.edit().remove("order").remove("due").remove("delivered").commit()
    }
    fun update(record:CheckoutRecord) {
        val order=record.order ?: return
        if(!enabled || record.orderId!=order.id || record.deviceId!=order.deviceId ||
            kotlin.math.abs(System.currentTimeMillis()-record.updatedAt)>60_000) return
        val key=MessageDigest.getInstance("SHA-256").digest("${record.accountId}:${order.id}".toByteArray()).joinToString(""){"%02x".format(it)}
        val tracked=prefs.getString("order",null)
        if(tracked!=null && tracked!=key)clear()
        val action=laundryReminderAction(order.status,order.remainSeconds,record.updatedAt,System.currentTimeMillis(),
            tracked==key,prefs.getString("completed",null)==key || tracked==key && prefs.getBoolean("delivered",false),
            System.currentTimeMillis()-record.createdAt in -5000..86_400_000)
        when(action) {
            LaundryReminderAction.Ignore -> return
            LaundryReminderAction.Clear -> {clear();return}
            LaundryReminderAction.Completed -> {
                if(notifyUser(true)) {
                    alarms.cancel(pending())
                    prefs.edit().remove("order").remove("due").remove("delivered").putString("completed",key).commit()
                }
                return
            }
            is LaundryReminderAction.Estimate -> Unit
        }
        val due=(action as LaundryReminderAction.Estimate).deadline
        if(tracked==key && (prefs.getBoolean("delivered",false) || kotlin.math.abs(prefs.getLong("due",0)-due)<60_000))return
        prefs.edit().putString("order",key).putLong("due",due).putBoolean("delivered",false).commit()
        schedule(due)
    }
    fun test() {
        check(enabled){"请先开启洗衣提醒"}
        val intent=PendingIntent.getBroadcast(context,1,Intent(context,LaundryReminderReceiver::class.java).setAction("campus.laundry.TEST"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,System.currentTimeMillis()+10_000,intent)
    }
    fun deliverTest(){notifyUser(false,true)}
    private fun schedule(due:Long) {
        // Inexact alarm: no exact-alarm privilege, and no promise of second-level delivery.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,maxOf(System.currentTimeMillis()+1000,due),pending())
    }
    fun restore() {
        if(enabled && !prefs.getBoolean("delivered",false) && prefs.contains("order"))schedule(prefs.getLong("due",0))
    }
    fun deliverEstimate() {
        if(!enabled || !prefs.contains("order") || prefs.getBoolean("delivered",false))return
        if(prefs.getLong("due",0)>System.currentTimeMillis()+1000) {restore();return}
        if(notifyUser(false))prefs.edit().putBoolean("delivered",true).commit()
    }
    private fun notifyUser(complete:Boolean,test:Boolean=false):Boolean {
        if(Build.VERSION.SDK_INT>=33 && ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return false
        val manager=NotificationManagerCompat.from(context)
        if(!manager.areNotificationsEnabled())return false
        if(Build.VERSION.SDK_INT>=26)context.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("laundry","洗衣结束提醒",NotificationManager.IMPORTANCE_DEFAULT))
        val open=PendingIntent.getActivity(context,0,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification=NotificationCompat.Builder(context,"laundry").setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(if(test)"校日常测试提醒" else if(complete)"洗衣完成" else "预计洗衣结束")
            .setContentText(if(test)"洗衣提醒可以正常显示。" else if(complete)"订单已确认完成，请及时取衣。" else "按上次剩余时间估算，请打开校日常核对订单后取衣。")
            .setContentIntent(open).setAutoCancel(true).build()
        try { manager.notify(if(test)505 else 504,notification) } catch(_:SecurityException){return false}
        return true
    }
}

class LaundryReminderReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        val reminders=LaundryReminders(context)
        if(intent.action==Intent.ACTION_BOOT_COMPLETED)reminders.restore() else if(intent.action=="campus.laundry.TEST")reminders.deliverTest() else reminders.deliverEstimate()
    }
}
