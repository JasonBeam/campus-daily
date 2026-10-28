package com.beamjason.xiaorichang.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.Backdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens

/** Compact phone proportions, a single physical-pixel rim and one shared
 * selection surface. No app-wide density override or fixed font scale. */
@Composable
fun RefinedTabBar(selected:Int,onSelect:(Int)->Unit,backdrop:Backdrop,mode:GlassMode) {
    val dark=MaterialTheme.colorScheme.background==Color.Black
    val surface=MaterialTheme.colorScheme.surface
    val shape=RoundedCornerShape(50)
    val rim=remember(dark){Brush.verticalGradient(if(dark)listOf(Color.White.copy(alpha=.24f),Color.White.copy(alpha=.07f)) else listOf(Color.White.copy(alpha=.98f),Color(0xFFB8C0CC).copy(alpha=.48f)))}
    val gleam=remember(dark){Brush.verticalGradient(listOf(Color.White.copy(alpha=if(dark).07f else .18f),Color.Transparent))}
    val background=if(mode==GlassMode.SOLID)Modifier.background(surface.copy(alpha=.97f),shape)
        else Modifier.drawBackdrop(backdrop,shape={shape},effects={blur(10.dp.toPx());if(mode==GlassMode.LIQUID)lens(14.dp.toPx(),6.dp.toPx())},shadow=null,
            onDrawSurface={drawRect(surface.copy(alpha=if(dark).64f else .70f));drawRect(gleam)})
    val bottom=LocalPreviewSafeBottom.current
    val safe=if(bottom!=null)Modifier.padding(bottom=bottom)else Modifier.windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom+WindowInsetsSides.Horizontal))
    BoxWithConstraints(Modifier.fillMaxWidth().testTag("campus-tab-bar").then(safe).padding(horizontal=20.dp),contentAlignment=Alignment.Center) {
        val scale=(((maxWidth+40.dp).value-360f)/80f).coerceIn(0f,1f)
        val width=(240f+40f*scale).dp
        val minimumHeight=(54f+6f*scale).dp
        val iconSize=(24f+3f*scale).dp
        val labelSize=(11f+scale).sp
        val itemWidth=(width-6.dp)/3
        val offset by animateDpAsState(itemWidth*selected,tween(150,easing=CubicBezierEasing(.23f,1f,.32f,1f)),label="selected tab")
        Box(Modifier.width(width).shadow(2.dp,shape,clip=false,ambientColor=Color.Black.copy(alpha=.06f),spotColor=Color.Black.copy(alpha=.08f))
            .then(background).border(Dp.Hairline,rim,shape).padding(3.dp)) {
            Box(Modifier.matchParentSize()) {
                Box(Modifier.offset(x=offset).width(itemWidth).fillMaxHeight().background(MaterialTheme.colorScheme.onSurface.copy(alpha=if(dark).085f else .055f),shape))
            }
            Row(Modifier.fillMaxWidth().heightIn(min=minimumHeight-6.dp).selectableGroup(),verticalAlignment=Alignment.CenterVertically) {
                listOf("日常","订单","设备").forEachIndexed {index,title->
                    val active=selected==index
                    val interaction=remember{MutableInteractionSource()}
                    val pressed by interaction.collectIsPressedAsState()
                    val pressScale by animateFloatAsState(if(pressed).97f else 1f,tween(100),label="tab press")
                    val icon=when(index){0->if(active)CampusSymbols.Grid else CampusSymbols.GridOutline;1->CampusSymbols.History;else->CampusSymbols.Tune}
                    val tint=if(active)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                    Column(Modifier.weight(1f).heightIn(min=48.dp)
                        .selectable(selected=active,interactionSource=interaction,indication=null,role=Role.Tab,onClick={onSelect(index)})
                        .graphicsLayer{scaleX=pressScale;scaleY=pressScale}
                        .padding(vertical=4.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(2.dp,Alignment.CenterVertically)) {
                        Icon(icon,null,Modifier.size(iconSize),tint=tint)
                        NativeText(title,fontSize=labelSize,lineHeight=14.sp,fontWeight=if(active)FontWeight.SemiBold else FontWeight.Medium,color=tint)
                    }
                }
            }
        }
    }
}
