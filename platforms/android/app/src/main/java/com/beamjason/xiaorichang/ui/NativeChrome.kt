package com.beamjason.xiaorichang.ui

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.Dp
import androidx.compose.foundation.clickable
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens

/** Only fixture rendering overrides the safe area; production uses real system bars. */
val LocalPreviewSafeTop=compositionLocalOf<Dp?> {null}
val LocalPreviewSafeBottom=compositionLocalOf<Dp?> {null}

enum class GlassMode { LIQUID, FROSTED, SOLID }

fun glassMode(context:Context,enabled:Boolean):GlassMode {
    val lowRam=(context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice
    val powerSave=(context.getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode
    return resolveGlassMode(Build.VERSION.SDK_INT,enabled,lowRam,powerSave)
}

internal fun resolveGlassMode(sdk:Int,enabled:Boolean,lowRam:Boolean,powerSave:Boolean):GlassMode = when {
    !enabled || lowRam || powerSave -> GlassMode.SOLID
    sdk>=33 -> GlassMode.LIQUID
    sdk>=31 -> GlassMode.FROSTED
    else -> GlassMode.SOLID
}

@Composable
fun CampusHeader(title:String,large:Boolean=false,back:(()->Unit)?=null,settings:(()->Unit)?=null,refresh:(()->Unit)?=null) {
    val top=LocalPreviewSafeTop.current
    val safe=if(top!=null)Modifier.padding(top=top)else Modifier.windowInsetsPadding(WindowInsets.statusBars.only(WindowInsetsSides.Top+WindowInsetsSides.Horizontal))
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.background).then(safe)) {
        Box(Modifier.fillMaxWidth().height(54.dp)) {
            if(back!=null)ChromeButton(back,Modifier.padding(start=20.dp),false){Icon(CampusSymbols.ChevronBack,"返回",tint=MaterialTheme.colorScheme.onSurface,modifier=Modifier.size(27.dp))}
            if(!large)Box(Modifier.fillMaxWidth().height(44.dp),contentAlignment=Alignment.Center){NativeText(title,fontSize=17.sp,lineHeight=22.sp,fontWeight=FontWeight.SemiBold)}
            val action=refresh ?: settings
            if(action!=null)ChromeButton(action,Modifier.align(Alignment.TopEnd).padding(end=20.dp),true){
                Icon(if(refresh!=null)Icons.Default.Refresh else CampusSymbols.Tune,if(refresh!=null)"刷新洗衣机" else "设备与设置",tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(25.dp))
            }
        }
        if(large)Box(Modifier.fillMaxWidth().heightIn(min=52.dp).padding(start=20.dp,end=20.dp,top=4.dp,bottom=7.dp)){NativeText(title,style=MaterialTheme.typography.headlineLarge)}
    }
}

@Composable
private fun ChromeButton(action:()->Unit,modifier:Modifier,wide:Boolean,content:@Composable ()->Unit) {
    val dark=MaterialTheme.colorScheme.background==Color.Black
    Box(modifier.width(if(wide)56.dp else 44.dp).height(44.dp)
        .background(MaterialTheme.colorScheme.surface.copy(alpha=.35f),RoundedCornerShape(50))
        .border(.5.dp,if(dark)Color.White.copy(alpha=.18f)else Color(0xFFD2D2D7),RoundedCornerShape(50))
        .clickable(onClick=action),contentAlignment=Alignment.Center){content()}
}

/** A single small backdrop layer, not a full-screen blur. The foreground text is
 * never recorded into the glass layer. Unsupported/low-power devices keep the
 * same navigation geometry and tap targets without running effects. */
@Composable
fun CampusTabBar(selected:Int,onSelect:(Int)->Unit,backdrop:Backdrop,mode:GlassMode) {
    val surface=MaterialTheme.colorScheme.surface
    val shape=RoundedCornerShape(50)
    val dark=MaterialTheme.colorScheme.background==Color.Black
    val glass=if(mode==GlassMode.SOLID) Modifier.background(surface.copy(alpha=.97f),shape)
        else Modifier.drawBackdrop(backdrop,shape={shape},effects={
            blur(10.dp.toPx())
            if(mode==GlassMode.LIQUID) lens(16.dp.toPx(),8.dp.toPx())
        },shadow=null,onDrawSurface={drawRect(surface.copy(alpha=if(dark).72f else .78f))})
    val bottom=LocalPreviewSafeBottom.current
    val safe=if(bottom!=null)Modifier.padding(bottom=bottom)else Modifier.windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom+WindowInsetsSides.Horizontal))
    Box(Modifier.fillMaxWidth().then(safe).padding(horizontal=20.dp),contentAlignment=Alignment.Center) {
        Row(Modifier.widthIn(max=280.dp).fillMaxWidth().then(glass)
            .border(.5.dp,if(dark)Color.White.copy(alpha=.18f)else Color.White.copy(alpha=.9f),shape)
            .padding(4.dp).selectableGroup(),verticalAlignment=Alignment.CenterVertically) {
            listOf("日常" to CampusSymbols.Grid,"订单" to CampusSymbols.History,"设备" to CampusSymbols.Tune).forEachIndexed { index,item ->
                val active=selected==index
                val color=if(active)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                Column(Modifier.weight(1f).background(if(active)MaterialTheme.colorScheme.onSurface.copy(alpha=.075f)else Color.Transparent,shape)
                    .selectable(active,onClick={onSelect(index)},role=Role.Tab)
                    .padding(vertical=4.5.dp,horizontal=4.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(3.dp)) {
                    Icon(item.second,null,Modifier.size(28.dp),tint=color)
                    NativeText(item.first,fontSize=12.sp,lineHeight=14.sp,fontWeight=if(active)FontWeight.SemiBold else FontWeight.Medium,color=color)
                }
            }
        }
    }
}
