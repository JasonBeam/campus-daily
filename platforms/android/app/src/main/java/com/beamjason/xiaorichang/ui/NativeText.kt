package com.beamjason.xiaorichang.ui

import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/** Android's fallback CJK metrics can reserve more than the requested line
 * height. Keep the measured layout grid explicit while centering the original
 * text drawing within it. No bitmap text, fixed font-scale, or Apple font is used.
 * Multiline text retains all measured lines; larger amounts grow their own box. */
@Composable
fun NativeText(
    text:String,
    modifier:Modifier=Modifier,
    color:Color=Color.Unspecified,
    fontSize:TextUnit=TextUnit.Unspecified,
    fontWeight:FontWeight?=null,
    textAlign:TextAlign?=null,
    lineHeight:TextUnit=TextUnit.Unspecified,
    maxLines:Int=Int.MAX_VALUE,
    style:TextStyle=LocalTextStyle.current
) {
    val resolved=style.merge(TextStyle(color=color,fontSize=fontSize,fontWeight=fontWeight,textAlign=textAlign ?: TextAlign.Unspecified,lineHeight=lineHeight))
    var count by remember(text,resolved,maxLines){mutableIntStateOf(1)}
    val font=if(resolved.fontSize.isSpecified)resolved.fontSize.value else 16f
    val authored=if(resolved.lineHeight.isSpecified)resolved.lineHeight.value else font*1.25f
    val grid=maxOf(authored,font*1.16f).sp
    androidx.compose.material3.Text(text,modifier.layout {measurable,constraints ->
        val p=measurable.measure(constraints.copy(minHeight=0))
        val height=(grid.toPx()*count).roundToInt().coerceIn(constraints.minHeight,constraints.maxHeight)
        layout(p.width,height){p.placeRelative(0,(height-p.height)/2)}
    },maxLines=maxLines,style=resolved,onTextLayout={if(count!=it.lineCount)count=it.lineCount})
}
