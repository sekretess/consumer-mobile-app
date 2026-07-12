package io.sekretess

import android.Manifest
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import com.google.android.gms.tasks.OnSuccessListener
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class MainActivity : FlutterActivity() {
    private val SIGNAL_PROTOCOL_CHANNEL = "io.sekretess/signal_protocol"
    private val API_BRIDGE_CHANNEL = "io.sekretess/api_bridge"
    private val VERSION_CHANNEL = "io.sekretess/version"
    private lateinit var signalProtocolHandler: SignalProtocolHandler
    private lateinit var apiBridgeChannel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    private fun checkForAppUpdate() {
        val appUpdateManager: AppUpdateManager = AppUpdateManagerFactory.create(this)

        val appUpdateInfoTask: com.google.android.gms.tasks.Task<AppUpdateInfo?> = appUpdateManager.appUpdateInfo

        appUpdateInfoTask.addOnSuccessListener { appUpdateInfo: AppUpdateInfo? ->
            if (appUpdateInfo?.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
                && (appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
                        || appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE))
            ) {
                appUpdateManager.startUpdateFlow(
                    appUpdateInfo, this,
                    AppUpdateOptions.defaultOptions(AppUpdateType.FLEXIBLE)
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        checkForAppUpdate()
        ActivityCompat.requestPermissions(
            this,
            arrayOf<String>(Manifest.permission.POST_NOTIFICATIONS),
            1
        )
        // Version Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VERSION_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAppVersion") {
                val versionName = BuildConfig.VERSION_NAME
                val versionCode = BuildConfig.VERSION_CODE
                val versionInfo = mapOf("versionName" to versionName, "versionCode" to versionCode)
                result.success(versionInfo)
            } else {
                result.notImplemented()
            }
        }

        // Initialize FlutterDependencyProvider first
        io.sekretess.bridge.FlutterDependencyProvider.initialize(applicationContext)

        signalProtocolHandler = SignalProtocolHandler(applicationContext)

        // Set up API bridge channel (for native -> Flutter calls)
        apiBridgeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, API_BRIDGE_CHANNEL)

        // Set up API callback bridge to handle API calls from native code
        val apiBridge = io.sekretess.bridge.FlutterDependencyProvider.getApiClientBridge()
        apiBridge.setApiCallback(object : io.sekretess.bridge.NativeApiClientBridge.ApiCallback {
            override fun onUpsertKeyStore(keyBundle: io.sekretess.dto.KeyBundle): Boolean {
                return try {
                    // Convert KeyBundle to Map
                    val keyBundleMap = io.sekretess.bridge.KeyBundleConverter.toMap(keyBundle)

                    // Use CompletableFuture for better synchronization
                    val completableFuture = CompletableFuture<Boolean>()

                    android.util.Log.i("MainActivity", "Calling upsertKeyStore via MethodChannel (thread: ${Thread.currentThread().name})")

                    // CRITICAL: Always post to main thread to ensure MethodChannel works correctly
                    // The callback will complete the CompletableFuture
                    mainHandler.post {
                        try {
                            android.util.Log.d("MainActivity", "Executing invokeMethod on main thread")
                            apiBridgeChannel.invokeMethod("upsertKeyStore", keyBundleMap, object : MethodChannel.Result {
                                override fun success(resultValue: Any?) {
                                    android.util.Log.i("MainActivity", "upsertKeyStore success callback: $resultValue (thread: ${Thread.currentThread().name})")
                                    val boolValue = resultValue as? Boolean ?: false
                                    android.util.Log.d("MainActivity", "Completing future with: $boolValue")
                                    completableFuture.complete(boolValue)
                                    android.util.Log.d("MainActivity", "Future completed")
                                }

                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                    android.util.Log.e("MainActivity", "Failed to upsert key store: $errorCode - $errorMessage")
                                    completableFuture.complete(false)
                                }

                                override fun notImplemented() {
                                    android.util.Log.w("MainActivity", "upsertKeyStore not implemented")
                                    completableFuture.complete(false)
                                }
                            })
                            android.util.Log.d("MainActivity", "invokeMethod call posted")
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Exception calling invokeMethod", e)
                            completableFuture.complete(false)
                        }
                    }

                    // Wait for the CompletableFuture to complete
                    android.util.Log.d("MainActivity", "Waiting for upsertKeyStore response...")
                    val startTime = System.currentTimeMillis()
                    try {
                        val resultValue = completableFuture.get(60, TimeUnit.SECONDS)
                        val elapsed = System.currentTimeMillis() - startTime
                        android.util.Log.i("MainActivity", "upsertKeyStore completed: $resultValue (elapsed: ${elapsed}ms)")
                        resultValue
                    } catch (e: java.util.concurrent.TimeoutException) {
                        val elapsed = System.currentTimeMillis() - startTime
                        android.util.Log.e("MainActivity", "Timeout waiting for upsertKeyStore response (elapsed: ${elapsed}ms)", e)
                        false
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "Error in onUpsertKeyStore", e)
                    false
                }
            }

            override fun onUpdateOneTimeKeys(
                preKeyRecords: Array<org.signal.libsignal.protocol.state.PreKeyRecord>,
                kyberPreKeyRecords: Array<org.signal.libsignal.protocol.state.KyberPreKeyRecord>
            ): Boolean {
                return try {
                    // Convert keys to Map
                    val keysMap = io.sekretess.bridge.KeyBundleConverter.oneTimeKeysToMap(
                        preKeyRecords,
                        kyberPreKeyRecords
                    )

                    // Call Flutter's ApiBridgeService via MethodChannel (blocking)
                    val latch = CountDownLatch(1)
                    val result = AtomicBoolean(false)
                    val errorRef = AtomicReference<String?>(null)

                    android.util.Log.i("MainActivity", "Calling updateOneTimeKeys via MethodChannel (thread: ${Thread.currentThread().name})")

                    // Check if we're on main thread
                    if (Looper.myLooper() == Looper.getMainLooper()) {
                        // Already on main thread - call directly
                        apiBridgeChannel.invokeMethod("updateOneTimeKeys", keysMap, object : MethodChannel.Result {
                            override fun success(resultValue: Any?) {
                                android.util.Log.i("MainActivity", "updateOneTimeKeys success: $resultValue")
                                result.set(resultValue as? Boolean ?: false)
                                latch.countDown()
                            }

                            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                android.util.Log.e("MainActivity", "Failed to update one-time keys: $errorCode - $errorMessage")
                                errorRef.set("$errorCode: $errorMessage")
                                result.set(false)
                                latch.countDown()
                            }

                            override fun notImplemented() {
                                android.util.Log.w("MainActivity", "updateOneTimeKeys not implemented in Flutter (handler not ready)")
                                errorRef.set("NOT_IMPLEMENTED")
                                result.set(false)
                                latch.countDown()
                            }
                        })
                    } else {
                        // Not on main thread - post to main thread
                        mainHandler.post {
                            apiBridgeChannel.invokeMethod("updateOneTimeKeys", keysMap, object : MethodChannel.Result {
                                override fun success(resultValue: Any?) {
                                    android.util.Log.i("MainActivity", "updateOneTimeKeys success: $resultValue")
                                    result.set(resultValue as? Boolean ?: false)
                                    latch.countDown()
                                }

                                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                    android.util.Log.e("MainActivity", "Failed to update one-time keys: $errorCode - $errorMessage")
                                    errorRef.set("$errorCode: $errorMessage")
                                    result.set(false)
                                    latch.countDown()
                                }

                                override fun notImplemented() {
                                    android.util.Log.w("MainActivity", "updateOneTimeKeys not implemented in Flutter (handler not ready)")
                                    errorRef.set("NOT_IMPLEMENTED")
                                    result.set(false)
                                    latch.countDown()
                                }
                            })
                        }
                    }
                    true
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "Error in onUpdateOneTimeKeys", e)
                    false
                }
            }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIGNAL_PROTOCOL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    try {
                        backgroundExecutor.submit {
                            try {
                                val success = signalProtocolHandler.init()
                                mainHandler.post {
                                    result.success(success)
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("INIT_ERROR", e.message, null)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                "decryptGroupChatMessage" -> {
                    try {
                        val sender = call.argument<String>("sender")
                        val base64Message = call.argument<String>("base64Message")
                        if (sender != null && base64Message != null) {
                            val decrypted = signalProtocolHandler.decryptGroupChatMessage(sender, base64Message)
                            result.success(decrypted)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Sender and base64Message are required", null)
                        }
                    } catch (e: Throwable) {
                        // libsignal wraps an unrecognised ciphertext version as an
                        // unchecked AssertionError (not Exception); catch Throwable so a
                        // single undecryptable message can never crash the app.
                        result.error("DECRYPT_ERROR", e.message, null)
                    }
                }
                "decryptPrivateMessage" -> {
                    try {
                        val sender = call.argument<String>("sender")
                        val base64Message = call.argument<String>("base64Message")
                        if (sender != null && base64Message != null) {
                            val decrypted = signalProtocolHandler.decryptPrivateMessage(sender, base64Message)
                            result.success(decrypted)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Sender and base64Message are required", null)
                        }
                    } catch (e: Throwable) {
                        // libsignal wraps an unrecognised ciphertext version as an
                        // unchecked AssertionError (not Exception); catch Throwable so a
                        // single undecryptable message can never crash the app.
                        result.error("DECRYPT_ERROR", e.message, null)
                    }
                }
                "processKeyDistributionMessage" -> {
                    try {
                        val name = call.argument<String>("name")
                        val base64Key = call.argument<String>("base64Key")
                        if (name != null && base64Key != null) {
                            signalProtocolHandler.processKeyDistributionMessage(name, base64Key)
                            result.success(null)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Name and base64Key are required", null)
                        }
                    } catch (e: Exception) {
                        result.error("PROCESS_KEY_ERROR", e.message, null)
                    }
                }
                "updateOneTimeKeys" -> {
                    try {
                        signalProtocolHandler.updateOneTimeKeys()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("UPDATE_KEYS_ERROR", e.message, null)
                    }
                }
                "clearSignalKeys" -> {
                    try {
                        signalProtocolHandler.clearSignalKeys()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CLEAR_KEYS_ERROR", e.message, null)
                    }
                }
                "initializeKeyBundle" -> {
                    try {
                        val keyBundle = signalProtocolHandler.initializeKeyBundle()
                        result.success(keyBundle)
                    } catch (e: Exception) {
                        result.error("INIT_KEY_BUNDLE_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
