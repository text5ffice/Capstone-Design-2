plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.safety_monitor_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 1. 핵심: 자바 8 데슈가링 활성화 (알림 패키지 필수 설정)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8.toString()
    }

    defaultConfig {
        applicationId = "com.example.safety_monitor_app"
        // 2. 중요: 알림 패키지 요구사항에 맞춰 minSdk를 최소 21 이상으로 권장 (보통 flutter.minSdkVersion이 처리함)
        minSdk = flutter.minSdkVersion 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // 3. 멀티덱스 활성화
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 4. 핵심: 데슈가링 라이브러리 추가
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
