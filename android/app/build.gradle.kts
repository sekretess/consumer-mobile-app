plugins {
    id("com.android.application")
    id("kotlin-android")
    id("kotlin-kapt")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "io.sekretess"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.sekretess"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 30
        targetSdk = 35
        versionCode = 51
        versionName = "Marakuya"
    }



    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")

            buildConfigField(
                "String",
                "AUTH_API_URL",
                "\"https://auth.test.sekretess.io/realms/consumer/.well-known/openid-configuration\""
            )
            buildConfigField(
                "String",
                "CONSUMER_API_URL",
                "\"https://consumer.test.sekretess.io/api/v1/consumers\""
            )
            buildConfigField(
                "String",
                "BUSINESS_API_URL",
                "\"https://business.test.sekretess.net/api/v1/businesses\""
            )

            buildConfigField(
                "String",
                "WEB_SOCKET_URL",
                "\"wss://consumer.test.sekretess.io/api/v1/consumers/ws\""
            )
        }
    }
    buildFeatures{
        buildConfig = true
        viewBinding = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring (required for libsignal-android)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.google.android.play:app-update:2.1.0")
    // Signal Protocol dependencies
    // client (Java API) and android (native .so) must be the SAME version.
    implementation("org.signal:libsignal-client:0.86.5")
    runtimeOnly("org.signal:libsignal-android:0.86.5")
    
    // Room database for Signal Protocol storage
    implementation("androidx.room:room-runtime:2.6.1")
    kapt("androidx.room:room-compiler:2.6.1")
    
    // SQLite
    implementation("androidx.sqlite:sqlite:2.6.2")
    
    // Jackson for JSON serialization
    implementation("com.fasterxml.jackson.core:jackson-databind:2.20.1")
    implementation("com.fasterxml.jackson.core:jackson-core:2.20.1")
    implementation("com.fasterxml.jackson.core:jackson-annotations:2.20")
}
