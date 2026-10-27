package com.beamjason.xiaorichang.ui

import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@Composable
fun BarcodeCamera(onFound:(String)->Unit,onClose:()->Unit,onError:(String)->Unit) {
    val context=LocalContext.current;val owner=LocalLifecycleOwner.current
    val preview=remember(context){PreviewView(context)}
    val found by rememberUpdatedState(onFound);val error by rememberUpdatedState(onError)
    DisposableEffect(preview,owner) {
        val executor=Executors.newSingleThreadExecutor();val active=AtomicBoolean(true);val delivered=AtomicBoolean(false)
        val scanner=BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build())
        val future=ProcessCameraProvider.getInstance(context);var bound:ProcessCameraProvider?=null
        val cameraPreview=Preview.Builder().build().also {it.setSurfaceProvider(preview.surfaceProvider)}
        val analysis=ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
        future.addListener({if(active.get())try {
            val provider=future.get();bound=provider
            analysis.setAnalyzer(executor){proxy->analyze(proxy,active,delivered,{qr->ContextCompat.getMainExecutor(context).execute {if(active.get())found(qr)}},scanner)}
            provider.bindToLifecycle(owner,CameraSelector.DEFAULT_BACK_CAMERA,cameraPreview,analysis)
        }catch(_:Exception){error("无法打开相机，可以返回粘贴二维码链接")}},ContextCompat.getMainExecutor(context))
        onDispose {active.set(false);analysis.clearAnalyzer();bound?.unbind(cameraPreview,analysis);scanner.close();executor.shutdown()}
    }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(factory={preview},modifier=Modifier.fillMaxSize())
        Surface(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(16.dp),color=Color.Black.copy(alpha=.65f),contentColor=Color.White,shape=MaterialTheme.shapes.medium) {
            Row(Modifier.padding(12.dp),verticalAlignment=Alignment.CenterVertically){Text("对准 U净机身二维码",Modifier.weight(1f));TextButton(onClose){Text("返回",color=Color.White)}}
        }
    }
}
@androidx.annotation.OptIn(ExperimentalGetImage::class)
private fun analyze(proxy:ImageProxy,active:AtomicBoolean,delivered:AtomicBoolean,found:(String)->Unit,scanner:com.google.mlkit.vision.barcode.BarcodeScanner) {
    val image=proxy.image
    if(!active.get() || delivered.get() || image==null){proxy.close();return}
    scanner.process(InputImage.fromMediaImage(image,proxy.imageInfo.rotationDegrees)).addOnSuccessListener {rows->
        rows.firstOrNull{!it.rawValue.isNullOrBlank()}?.rawValue?.let{if(active.get() && delivered.compareAndSet(false,true))found(it)}
    }.addOnCompleteListener{proxy.close()}
}
