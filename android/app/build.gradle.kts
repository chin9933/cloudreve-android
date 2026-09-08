import java.util.Properties
import java.util.Base64
import java.net.URI

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter and Android consume exactly the same compile-time metadata.
val appMetadata = providers.gradleProperty("dart-defines").orNull
    ?.split(",")?.filter { it.isNotEmpty() }?.associate { encoded ->
        val item = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        val separator = item.indexOf('=')
        require(separator > 0) { "Invalid Dart define" }
        item.substring(0, separator) to item.substring(separator + 1)
    } ?: emptyMap()
val appDisplayName = appMetadata["APP_NAME"] ?: "Cloudreve"
val appId = appMetadata["APP_APPLICATION_ID"] ?: "com.example.cloudreve"
require(appDisplayName.isNotBlank() && appDisplayName.length <= 64 &&
    appDisplayName.none { it.code < 32 || it.code == 127 }) { "Invalid APP_NAME" }
require(appId.matches(Regex("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+"))) { "Invalid APP_APPLICATION_ID" }
appMetadata["APP_DESCRIPTION"]?.let { value ->
    require(value.isNotBlank() && value.length <= 240 && value.none { it.code < 32 || it.code == 127 }) { "Invalid APP_DESCRIPTION" }
}
appMetadata["CLOUDREVE_SITE_URL"]?.takeIf { it.isNotEmpty() }?.let { value ->
    val site = URI(value)
    require(site.scheme == "https" && !site.host.isNullOrEmpty() && site.userInfo == null &&
        site.query == null && site.fragment == null) { "CLOUDREVE_SITE_URL must be HTTPS without credentials/query/fragment" }
}
val configuredVersionName = appMetadata["APP_VERSION_NAME"]
require(configuredVersionName == null || configuredVersionName.matches(Regex("\\d+\\.\\d+\\.\\d+([-+][0-9A-Za-z.-]+)?"))) { "Invalid APP_VERSION_NAME" }
val configuredVersionCode = appMetadata["APP_VERSION_CODE"]?.let { value ->
    value.toIntOrNull()?.takeIf { it in 1..2100000000 } ?: error("Invalid APP_VERSION_CODE")
}
fun androidString(value: String) = "\"" + value.replace("\\", "\\\\")
    .replace("\"", "\\\"").replace("'", "\\'") + "\""

val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.isFile) {
    releasePropertiesFile.inputStream().use(releaseProperties::load)
}
fun releaseSetting(environment: String, property: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: releaseProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStoreFile = releaseSetting("CLOUDREVE_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = releaseSetting("CLOUDREVE_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = releaseSetting("CLOUDREVE_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = releaseSetting("CLOUDREVE_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
).all { it != null }
val allowDebugReleaseSigning =
    providers.gradleProperty("allowDebugReleaseSigning").orNull == "true"

// Fail before packaging, rather than silently calling a debug-signed APK a release.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        it.project == project && it.name in setOf(
            "assembleRelease", "bundleRelease", "packageRelease", "packageReleaseBundle",
        )
    }
    if (buildsRelease && !hasReleaseSigning && !allowDebugReleaseSigning) {
        throw GradleException(
            "Release signing is missing. Configure android/key.properties or " +
                "CLOUDREVE_KEYSTORE_* variables. For local testing only, explicitly " +
                "pass -PallowDebugReleaseSigning=true.",
        )
    }
}

android {
    namespace = "com.example.cloudreve"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = appId
        resValue("string", "app_name", androidString(appDisplayName))
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = configuredVersionCode ?: flutter.versionCode
        versionName = configuredVersionName ?: flutter.versionName
    }

    val hostDebugKeystore = System.getenv("CLOUDREVE_DEBUG_KEYSTORE")
    if (!hostDebugKeystore.isNullOrBlank()) {
        signingConfigs.create("hostDebug") {
            storeFile = file(hostDebugKeystore)
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    if (hasReleaseSigning) {
        signingConfigs.create("release") {
            storeFile = rootProject.file(releaseStoreFile!!)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        debug {
            if (!hostDebugKeystore.isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("hostDebug")
            }
        }
        release {
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                allowDebugReleaseSigning -> signingConfigs.getByName(
                    if (hostDebugKeystore.isNullOrBlank()) "debug" else "hostDebug",
                )
                else -> null
            }
            proguardFiles("proguard-rules.pro")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
