import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val sharedAutomationRoot=providers.gradleProperty("campusSharedAssetsDir")
    .orElse(rootProject.file("../../Shared").absolutePath)
val syncCampusAutomation=tasks.register<Copy>("syncCampusAutomation") {
    from(sharedAutomationRoot){include("CampusLoginAutomation.js")}
    into(layout.buildDirectory.dir("generated/campusAutomationAssets"))
}
val waterProfilePath=providers.gradleProperty("campusWaterProfile")
    .orElse(providers.environmentVariable("CAMPUS_WATER_PROFILE_PATH"))
val waterAssets=layout.buildDirectory.dir("generated/waterPlatformAssets")
val stageWaterPlatform=tasks.register<Exec>("stageWaterPlatform") {
    inputs.file(waterProfilePath)
    inputs.file(sharedAutomationRoot.map{File(it).parentFile.resolve("tools/stage_platform_profile.py")})
    outputs.file(waterAssets.map{it.file("CampusWaterPlatform.json")})
    doFirst {
        require(waterProfilePath.isPresent){"Set campusWaterProfile to your local platform-only JSON file"}
        commandLine("python3",File(sharedAutomationRoot.get()).parentFile.resolve("tools/stage_platform_profile.py").absolutePath,
            "--profile",waterProfilePath.get(),"--output",waterAssets.get().file("CampusWaterPlatform.json").asFile.absolutePath)
    }
}

android {
    namespace = "com.beamjason.xiaorichang"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.beamjason.xiaorichang"
        // CameraX, bundled ML Kit barcode scanning, BLE and Android Keystore
        // support API 23+, so Android 6.0 is the broadest supported baseline.
        minSdk = 23
        targetSdk = 35
        versionCode = 24
        versionName = "0.2.0-alpha22"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true; buildConfig = true }
    sourceSets["main"].assets.srcDir(syncCampusAutomation.map{it.destinationDir})
    sourceSets["main"].assets.srcDir(waterAssets)
    buildTypes {
        debug { applicationIdSuffix = ".debug"; versionNameSuffix = "-debug" }
        release { isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
tasks.named("preBuild").configure {dependsOn(syncCampusAutomation,stageWaterPlatform)}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.11.00"))
    implementation("androidx.activity:activity-compose:1.12.0")
    implementation("androidx.compose.ui:ui")
    // Pinned to the stable Compose 1.9 / API 36 toolchain. Apache-2.0.
    implementation("io.github.kyant0:backdrop:1.0.0")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("com.alipay.sdk:alipaysdk-android:15.8.42@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // The bundled ML Kit model works without Google Play Services (important on Huawei).
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("androidx.camera:camera-camera2:1.5.1")
    implementation("androidx.camera:camera-lifecycle:1.5.1")
    implementation("androidx.camera:camera-view:1.5.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.11.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
