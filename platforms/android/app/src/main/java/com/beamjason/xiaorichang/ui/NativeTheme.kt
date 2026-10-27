package com.beamjason.xiaorichang.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material3.Icon
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.sp

@Composable
fun NativeTheme(dark:Boolean=isSystemInDarkTheme(),content:@Composable ()->Unit) {
    val colors=if(dark) darkColorScheme(primary=Color(0xFF8BBAFF),onPrimary=Color(0xFF062550),background=Color(0xFF000000),
        surface=Color(0xFF1C1C1E),onSurface=Color(0xFFF2F2F7),onSurfaceVariant=Color(0xFFAEAEB2),surfaceVariant=Color(0xFF292D36),outlineVariant=Color(0xFF363A45))
    else lightColorScheme(primary=Color(0xFF185ECC),onPrimary=Color.White,background=Color(0xFFF2F2F7),surface=Color.White,
        onSurface=Color(0xFF1C1C1E),onSurfaceVariant=Color(0xFF8A8A8E),surfaceVariant=Color(0xFFE8EBF2),outlineVariant=Color(0xFFE1E4EB))
    val type=Typography(
            bodyLarge=Typography().bodyLarge.copy(fontSize=16.sp,lineHeight=20.sp),
            bodyMedium=Typography().bodyMedium.copy(fontSize=14.sp,lineHeight=18.sp),
            bodySmall=Typography().bodySmall.copy(fontSize=11.sp,lineHeight=14.sp),
            titleSmall=Typography().titleSmall.copy(fontSize=16.sp,lineHeight=20.sp,fontWeight=FontWeight.SemiBold),
            titleMedium=Typography().titleMedium.copy(fontSize=16.sp,lineHeight=20.sp,fontWeight=FontWeight.SemiBold),
            titleLarge=Typography().titleLarge.copy(fontWeight=FontWeight.SemiBold,fontSize=20.sp,lineHeight=26.sp),
            headlineLarge=Typography().headlineLarge.copy(fontSize=32.sp,lineHeight=41.sp,fontWeight=FontWeight.Bold))
    val exact=Typography(
        displayLarge=type.displayLarge.precise(),
        displayMedium=type.displayMedium.precise(),
        displaySmall=type.displaySmall.precise(),
        headlineLarge=type.headlineLarge.precise(),
        headlineMedium=type.headlineMedium.precise(),
        headlineSmall=type.headlineSmall.precise(),
        titleLarge=type.titleLarge.precise(),
        titleMedium=type.titleMedium.precise(),
        titleSmall=type.titleSmall.precise(),
        bodyLarge=type.bodyLarge.precise(),
        bodyMedium=type.bodyMedium.precise(),
        bodySmall=type.bodySmall.precise(),
        labelLarge=type.labelLarge.precise(),
        labelMedium=type.labelMedium.precise(),
        labelSmall=type.labelSmall.precise()
    )
    MaterialTheme(colorScheme=colors,shapes=Shapes(medium=RoundedCornerShape(16.dp),large=RoundedCornerShape(16.dp)),typography=exact,content=content)
}

@Composable
fun Group(modifier:Modifier=Modifier,padding:PaddingValues=PaddingValues(18.dp),spacing:Dp=12.dp,content:@Composable ColumnScope.()->Unit) {
    Surface(modifier.fillMaxWidth(),shape=RoundedCornerShape(16.dp),color=MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(padding),verticalArrangement=Arrangement.spacedBy(spacing),content=content)
    }
}
@Composable
fun Hint(text:String,error:Boolean=false) {
    NativeText(text,style=MaterialTheme.typography.bodySmall,color=if(error) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
}
@Composable
fun ActionButton(text:String,enabled:Boolean=true,busy:Boolean=false,aligned:Boolean=false,trailing:String?=null,onClick:()->Unit) {
    Button(onClick,Modifier.fillMaxWidth().heightIn(min=52.dp),enabled=enabled && !busy,shape=RoundedCornerShape(12.dp),contentPadding=PaddingValues(horizontal=18.dp,vertical=12.dp),colors=ButtonDefaults.buttonColors(containerColor=Color(0xFF175ECA),contentColor=Color.White)) {
        if(busy) {CircularProgressIndicator(Modifier.size(18.dp),strokeWidth=2.dp,color=Color.White);Spacer(Modifier.width(10.dp))}
        NativeText(text,style=MaterialTheme.typography.titleSmall)
        if(aligned){Spacer(Modifier.weight(1f));if(trailing!=null){NativeText(trailing,style=MaterialTheme.typography.titleSmall);Spacer(Modifier.width(10.dp))};Icon(CampusSymbols.ArrowUpRight,null,Modifier.size(18.dp))}
    }
}

@Composable
fun PlainAction(text:String,onClick:()->Unit) {
    Box(Modifier.heightIn(min=44.dp).clickable(onClick=onClick),contentAlignment=Alignment.CenterStart){NativeText(text,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.primary)}
}

private fun TextStyle.precise()=copy(platformStyle=PlatformTextStyle(includeFontPadding=false),lineHeightStyle=LineHeightStyle(LineHeightStyle.Alignment.Center,LineHeightStyle.Trim.None))
