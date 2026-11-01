package com.beamjason.xiaorichang.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** Original geometric outlines. No Apple font or SF Symbols asset is bundled. */
object CampusSymbols {
    private fun outline(name:String,draw:PathBuilder.()->Unit)=ImageVector.Builder(name,24.dp,24.dp,24f,24f).apply {
        path(fill=null,stroke=SolidColor(Color.Black),strokeLineWidth=1.65f,strokeLineCap=StrokeCap.Round,strokeLineJoin=StrokeJoin.Round,pathBuilder=draw)
    }.build()
    val Drop=outline("Water drop") {
        moveTo(12f,2f);curveTo(10f,5.4f,5.4f,11.7f,5.4f,15.5f)
        curveTo(5.4f,19.3f,8f,22f,12f,22f);curveTo(16f,22f,18.6f,19.3f,18.6f,15.5f)
        curveTo(18.6f,11.7f,14f,5.4f,12f,2f);close()
    }
    val Washer=outline("Washer") {
        moveTo(11f,21f);lineTo(3.5f,21f);quadTo(2f,21f,2f,19.5f);lineTo(2f,3.5f);quadTo(2f,2f,3.5f,2f)
        lineTo(18.5f,2f);quadTo(20f,2f,20f,3.5f);lineTo(20f,13f)
        moveTo(2f,7f);lineTo(20f,7f);moveTo(5f,4.5f);lineTo(6f,4.5f);moveTo(9f,4.5f);lineTo(10f,4.5f)
        moveTo(16.5f,14f);curveTo(16f,11f,14f,9f,11f,9f);curveTo(7.5f,9f,5f,11.5f,5f,15f);curveTo(5f,18.5f,7.5f,21f,11f,21f)
        moveTo(11.5f,17f);lineTo(14f,23f);lineTo(20.5f,23f);lineTo(23f,17f)
        curveTo(21.5f,17f,21f,16f,19.5f,16f);curveTo(18f,16f,17.8f,18f,16.5f,18f);curveTo(15f,18f,14f,16.5f,11.5f,17f);close()
    }
    val Tune=outline("Adjustments") {
        moveTo(2f,5f);lineTo(13f,5f);moveTo(18f,5f);lineTo(22f,5f)
        moveTo(2f,12f);lineTo(6f,12f);moveTo(11f,12f);lineTo(22f,12f)
        moveTo(2f,19f);lineTo(13f,19f);moveTo(18f,19f);lineTo(22f,19f)
        moveTo(13f,5f);curveTo(13f,1.7f,18f,1.7f,18f,5f);curveTo(18f,8.3f,13f,8.3f,13f,5f)
        moveTo(6f,12f);curveTo(6f,8.7f,11f,8.7f,11f,12f);curveTo(11f,15.3f,6f,15.3f,6f,12f)
        moveTo(13f,19f);curveTo(13f,15.7f,18f,15.7f,18f,19f);curveTo(18f,22.3f,13f,22.3f,13f,19f)
    }
    val History=outline("Recent orders") {
        moveTo(3f,10f);curveTo(4f,4f,10f,1f,15f,3f);curveTo(21f,5f,24f,11f,21f,17f)
        curveTo(18f,23f,9f,24f,5f,19f);moveTo(1f,8f);lineTo(3f,11f);lineTo(6f,8f)
        moveTo(12f,6f);lineTo(12f,12f);lineTo(16f,15f)
    }
    val Grid=ImageVector.Builder("Daily",24.dp,24.dp,24f,24f).apply {
        path(fill=SolidColor(Color.Black)) {
            for(x in listOf(2f,13f))for(y in listOf(2f,13f)){
                moveTo(x+2f,y);lineTo(x+7f,y);quadTo(x+9f,y,x+9f,y+2f);lineTo(x+9f,y+7f)
                quadTo(x+9f,y+9f,x+7f,y+9f);lineTo(x+2f,y+9f);quadTo(x,y+9f,x,y+7f);lineTo(x,y+2f);quadTo(x,y,x+2f,y);close()
            }
        }
    }.build()
    val GridOutline=outline("Daily outline") {
        for(x in listOf(2.5f,13.5f))for(y in listOf(2.5f,13.5f)) {
            moveTo(x+1.6f,y);lineTo(x+6.4f,y);quadTo(x+8f,y,x+8f,y+1.6f)
            lineTo(x+8f,y+6.4f);quadTo(x+8f,y+8f,x+6.4f,y+8f)
            lineTo(x+1.6f,y+8f);quadTo(x,y+8f,x,y+6.4f);lineTo(x,y+1.6f);quadTo(x,y,x+1.6f,y);close()
        }
    }
    val ChevronForward=outline("Forward"){moveTo(8f,4f);lineTo(16f,12f);lineTo(8f,20f)}
    val ChevronBack=outline("Back"){moveTo(15f,4f);lineTo(7f,12f);lineTo(15f,20f)}
    val ArrowUpRight=outline("Open"){moveTo(5f,19f);lineTo(19f,5f);moveTo(6f,5f);lineTo(19f,5f);lineTo(19f,18f)}
}
