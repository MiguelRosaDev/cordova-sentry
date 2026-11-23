package com.outsystems.plugins.sentry

import android.util.Log
import io.sentry.Breadcrumb
import io.sentry.ITransaction
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.SpanStatus
import io.sentry.android.core.SentryAndroid
import io.sentry.protocol.Mechanism
import io.sentry.protocol.Message
import io.sentry.protocol.SentryException
import io.sentry.protocol.SentryStackFrame
import io.sentry.protocol.SentryStackTrace
import io.sentry.protocol.User
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * SentryCordova: Native Android implementation in Kotlin for OutSystems 11 (MABS 12 & MABS 13).
 *
 * Wraps the official Sentry Android SDK (`io.sentry:sentry-android:8.65.1`).
 * Security note: Never log DSNs, PII, or raw user/extra payloads to Logcat.
 */
class SentryCordova : CordovaPlugin() {

    companion object {
        private const val TAG = "[SentryCordova]"
        private const val DEFAULT_ENVIRONMENT = "production"
        private const val DEFAULT_SAMPLE_RATE = 1.0
        private const val DEFAULT_TRACES_SAMPLE_RATE = 0.0
        private const val DEFAULT_MAX_BREADCRUMBS = 100
        private const val NOT_INITIALIZED_ERROR =
            "Sentry SDK is not initialized. Configure SENTRY_DSN (or SENTRY_ANDROID_DSN) " +
                "in Extensibility Configurations, or call initialize() at runtime."
    }

    private data class InitOptions(
        val dsn: String,
        val environment: String,
        val release: String?,
        val dist: String?,
        val sampleRate: Double,
        val tracesSampleRate: Double,
        val sendDefaultPii: Boolean,
        val enableAutoSessionTracking: Boolean,
        val anrEnabled: Boolean,
        val attachScreenshot: Boolean,
        val attachViewHierarchy: Boolean,
        val maxBreadcrumbs: Int,
        val debug: Boolean
    )

    private val activeTransactions = ConcurrentHashMap<String, ITransaction>()

    override fun pluginInitialize() {
        super.pluginInitialize()
        Log.d(TAG, "Plugin loaded")

        val autoInitialize = preferences.getBoolean("SentryAutoInitialize", true)
        if (!autoInitialize) {
            Log.d(TAG, "Auto-initialize disabled; waiting for JS initialize() call")
            return
        }

        val dsn = cleanPreference("SentryAndroidDsn")
            .ifEmpty { cleanPreference("SentryDsn") }
        if (dsn.isEmpty()) {
            Log.w(
                TAG,
                "Auto-initialize skipped: missing DSN (set SENTRY_DSN or SENTRY_ANDROID_DSN in Extensibility Configurations)"
            )
            return
        }

        val options = InitOptions(
            dsn = dsn,
            environment = cleanPreference("SentryEnvironment").ifEmpty { DEFAULT_ENVIRONMENT },
            release = cleanPreference("SentryRelease").ifEmpty { null },
            dist = cleanPreference("SentryDist").ifEmpty { null },
            sampleRate = parseDoublePreference("SentrySampleRate", DEFAULT_SAMPLE_RATE).coerceIn(0.0, 1.0),
            tracesSampleRate = parseDoublePreference("SentryTracesSampleRate", DEFAULT_TRACES_SAMPLE_RATE)
                .coerceIn(0.0, 1.0),
            sendDefaultPii = preferences.getBoolean("SentrySendDefaultPii", false),
            enableAutoSessionTracking = preferences.getBoolean("SentryEnableAutoSessionTracking", true),
            anrEnabled = preferences.getBoolean("SentryAnrEnabled", true),
            attachScreenshot = preferences.getBoolean("SentryAttachScreenshot", false),
            attachViewHierarchy = preferences.getBoolean("SentryAttachViewHierarchy", false),
            maxBreadcrumbs = parseIntPreference("SentryMaxBreadcrumbs", DEFAULT_MAX_BREADCRUMBS)
                .coerceAtLeast(0),
            debug = preferences.getBoolean("SentryDebug", false)
        )

        try {
            val result = performInitialize(options)
            Log.d(TAG, "Auto-initialization finished: initialized=${result.optBoolean("initialized")}")
        } catch (e: Exception) {
            Log.e(TAG, "Auto-initialization failed: ${e.message}", e)
        }
    }

    override fun execute(
        action: String,
        args: JSONArray,
        callbackContext: CallbackContext
    ): Boolean {
        Log.d(TAG, "execute: action=$action")

        return try {
            when (action) {
                "initialize" -> {
                    handleInitialize(args, callbackContext)
                    true
                }
                "isInitialized" -> {
                    handleIsInitialized(callbackContext)
                    true
                }
                "close" -> {
                    handleClose(callbackContext)
                    true
                }
                "flush" -> {
                    handleFlush(args, callbackContext)
                    true
                }
                "crashedLastRun" -> {
                    handleCrashedLastRun(callbackContext)
                    true
                }
                "captureMessage" -> {
                    handleCaptureMessage(args, callbackContext)
                    true
                }
                "captureException" -> {
                    handleCaptureException(args, callbackContext)
                    true
                }
                "addBreadcrumb" -> {
                    handleAddBreadcrumb(args, callbackContext)
                    true
                }
                "clearBreadcrumbs" -> {
                    handleClearBreadcrumbs(callbackContext)
                    true
                }
                "setUser" -> {
                    handleSetUser(args, callbackContext)
                    true
                }
                "clearUser" -> {
                    handleClearUser(callbackContext)
                    true
                }
                "setTag" -> {
                    handleSetTag(args, callbackContext)
                    true
                }
                "removeTag" -> {
                    handleRemoveTag(args, callbackContext)
                    true
                }
                "setExtra" -> {
                    handleSetExtra(args, callbackContext)
                    true
                }
                "removeExtra" -> {
                    handleRemoveExtra(args, callbackContext)
                    true
                }
                "setContext" -> {
                    handleSetContext(args, callbackContext)
                    true
                }
                "removeContext" -> {
                    handleRemoveContext(args, callbackContext)
                    true
                }
                "clearScope" -> {
                    handleClearScope(callbackContext)
                    true
                }
                "startTransaction" -> {
                    handleStartTransaction(args, callbackContext)
                    true
                }
                "finishTransaction" -> {
                    handleFinishTransaction(args, callbackContext)
                    true
                }
                "startSession" -> {
                    handleStartSession(callbackContext)
                    true
                }
                "endSession" -> {
                    handleEndSession(callbackContext)
                    true
                }
                "nativeCrash" -> {
                    handleNativeCrash(callbackContext)
                    true
                }
                else -> {
                    Log.w(TAG, "Unknown action: $action")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception during execute($action): ${e.message}", e)
            callbackContext.error("SentryCordova error: ${e.message}")
            true
        }
    }

    // ==================== LIFECYCLE ====================

    private fun handleInitialize(args: JSONArray, callbackContext: CallbackContext) {
        val configObj = args.optJSONObject(0)
        if (configObj == null) {
            callbackContext.error("initialize requires a configuration object.")
            return
        }

        val dsn = optTrimmedString(configObj, "dsn")
        if (dsn.isEmpty()) {
            callbackContext.error("Configuration 'dsn' is required.")
            return
        }

        val options = InitOptions(
            dsn = dsn,
            environment = optTrimmedString(configObj, "environment").ifEmpty { DEFAULT_ENVIRONMENT },
            release = optTrimmedString(configObj, "release").ifEmpty { null },
            dist = optTrimmedString(configObj, "dist").ifEmpty { null },
            sampleRate = optDouble(configObj, "sampleRate", DEFAULT_SAMPLE_RATE).coerceIn(0.0, 1.0),
            tracesSampleRate = optDouble(configObj, "tracesSampleRate", DEFAULT_TRACES_SAMPLE_RATE)
                .coerceIn(0.0, 1.0),
            sendDefaultPii = configObj.optBoolean("sendDefaultPii", false),
            enableAutoSessionTracking = configObj.optBoolean("enableAutoSessionTracking", true),
            anrEnabled = configObj.optBoolean("anrEnabled", true),
            attachScreenshot = configObj.optBoolean("attachScreenshot", false),
            attachViewHierarchy = configObj.optBoolean("attachViewHierarchy", false),
            maxBreadcrumbs = configObj.optInt("maxBreadcrumbs", DEFAULT_MAX_BREADCRUMBS)
                .coerceAtLeast(0),
            debug = configObj.optBoolean("debug", false)
        )

        cordova.threadPool.execute {
            try {
                val result = performInitialize(options)
                callbackContext.success(result)
            } catch (e: Exception) {
                Log.e(TAG, "initialize failed: ${e.message}", e)
                callbackContext.error("SentryCordova initialize failed: ${e.message}")
            }
        }
    }

    private fun performInitialize(options: InitOptions): JSONObject {
        if (Sentry.isEnabled()) {
            Log.d(TAG, "SDK already initialized; skipping re-initialization")
            return JSONObject().apply {
                put("initialized", true)
                put("alreadyInitialized", true)
            }
        }

        val appContext = cordova.activity?.applicationContext
            ?: throw IllegalStateException("Android applicationContext is unavailable.")

        SentryAndroid.init(appContext) { sentryOptions ->
            sentryOptions.setDsn(options.dsn)
            sentryOptions.setEnvironment(options.environment)
            options.release?.let { sentryOptions.setRelease(it) }
            options.dist?.let { sentryOptions.setDist(it) }
            sentryOptions.setSampleRate(options.sampleRate)
            if (options.tracesSampleRate > 0.0) {
                sentryOptions.setTracesSampleRate(options.tracesSampleRate)
            }
            sentryOptions.setSendDefaultPii(options.sendDefaultPii)
            sentryOptions.setEnableAutoSessionTracking(options.enableAutoSessionTracking)
            sentryOptions.setAnrEnabled(options.anrEnabled)
            sentryOptions.setAttachScreenshot(options.attachScreenshot)
            sentryOptions.setAttachViewHierarchy(options.attachViewHierarchy)
            sentryOptions.setMaxBreadcrumbs(options.maxBreadcrumbs)
            sentryOptions.setDebug(options.debug)
        }

        Log.d(
            TAG,
            "Initialized Sentry SDK (env=${options.environment}, tracing=${options.tracesSampleRate > 0.0}, " +
                "anr=${options.anrEnabled})"
        )

        return JSONObject().apply {
            put("initialized", true)
            put("alreadyInitialized", false)
        }
    }

    private fun handleIsInitialized(callbackContext: CallbackContext) {
        callbackContext.sendPluginResult(PluginResult(PluginResult.Status.OK, Sentry.isEnabled()))
    }

    private fun handleClose(callbackContext: CallbackContext) {
        activeTransactions.clear()
        Sentry.close()
        Log.d(TAG, "close: Sentry SDK closed")
        callbackContext.success()
    }

    private fun handleFlush(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val timeoutMs = args.optLong(0, 2000L).coerceAtLeast(0L)
        cordova.threadPool.execute {
            try {
                Sentry.flush(timeoutMs)
                callbackContext.success()
            } catch (e: Exception) {
                Log.e(TAG, "flush failed: ${e.message}", e)
                callbackContext.error("SentryCordova flush failed: ${e.message}")
            }
        }
    }

    private fun handleCrashedLastRun(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val crashed = Sentry.isCrashedLastRun() == true
        callbackContext.sendPluginResult(PluginResult(PluginResult.Status.OK, crashed))
    }

    // ==================== CAPTURE MESSAGE & EXCEPTION ====================

    private fun handleCaptureMessage(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val payload = args.optJSONObject(0)
        if (payload == null) {
            callbackContext.error("captureMessage requires a payload object.")
            return
        }
        val text = optTrimmedString(payload, "message")
        if (text.isEmpty()) {
            callbackContext.error("captureMessage requires a non-empty 'message'.")
            return
        }

        val event = SentryEvent()
        val msg = Message()
        msg.setFormatted(text)
        event.setMessage(msg)
        event.setLevel(parseLevel(optTrimmedString(payload, "level").ifEmpty { "info" }))

        applyTags(payload.optJSONObject("tags"), event)
        applyExtras(payload.optJSONObject("extras"), event)
        val fingerprint = extractStringList(payload.optJSONArray("fingerprint"))
        if (fingerprint.isNotEmpty()) {
            event.setFingerprints(fingerprint)
        }

        val eventId = Sentry.captureEvent(event)
        Log.d(TAG, "captureMessage: level=${event.level?.name}")
        callbackContext.success(eventId.toString())
    }

    private fun handleCaptureException(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val payload = args.optJSONObject(0)
        if (payload == null) {
            callbackContext.error("captureException requires a payload object.")
            return
        }

        val message = optTrimmedString(payload, "message")
        val type = optTrimmedString(payload, "type").ifEmpty { "Error" }
        if (message.isEmpty()) {
            callbackContext.error("captureException requires a non-empty 'message'.")
            return
        }

        val handled = payload.optBoolean("handled", true)
        val level = parseLevel(optTrimmedString(payload, "level").ifEmpty { "error" })
        val framesArray = payload.optJSONArray("frames")
        val frames = parseFrames(framesArray)

        val mechanism = Mechanism()
        mechanism.setType(if (handled) "generic" else "onerror")
        mechanism.setHandled(handled)

        val sentryException = SentryException()
        sentryException.setType(type)
        sentryException.setValue(message)
        sentryException.setMechanism(mechanism)
        if (frames.isNotEmpty()) {
            sentryException.setStacktrace(SentryStackTrace(frames))
        }

        val event = SentryEvent()
        event.setLevel(level)
        event.setExceptions(listOf(sentryException))
        applyTags(payload.optJSONObject("tags"), event)
        applyExtras(payload.optJSONObject("extras"), event)

        val rawStack = optTrimmedString(payload, "stacktrace")
        if (frames.isEmpty() && rawStack.isNotEmpty()) {
            event.setExtra("js_stacktrace", rawStack)
        }

        val fingerprint = extractStringList(payload.optJSONArray("fingerprint"))
        if (fingerprint.isNotEmpty()) {
            event.setFingerprints(fingerprint)
        }

        val eventId = Sentry.captureEvent(event)
        Log.d(TAG, "captureException: type=$type, handled=$handled, frames=${frames.size}")
        callbackContext.success(eventId.toString())
    }

    // ==================== BREADCRUMBS ====================

    private fun handleAddBreadcrumb(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val obj = args.optJSONObject(0)
        if (obj == null) {
            callbackContext.error("addBreadcrumb requires a breadcrumb object.")
            return
        }

        val crumb = Breadcrumb()
        optTrimmedString(obj, "message").takeIf { it.isNotEmpty() }?.let { crumb.setMessage(it) }
        optTrimmedString(obj, "category").takeIf { it.isNotEmpty() }?.let { crumb.setCategory(it) }
        optTrimmedString(obj, "type").takeIf { it.isNotEmpty() }?.let { crumb.setType(it) }
        crumb.setLevel(parseLevel(optTrimmedString(obj, "level").ifEmpty { "info" }))
        crumb.setOrigin("cordova")

        val dataMap = jsonObjectToMap(obj.optJSONObject("data"))
        for ((k, v) in dataMap) {
            if (v != null) {
                crumb.setData(k, v)
            }
        }

        Sentry.addBreadcrumb(crumb)
        Log.d(TAG, "addBreadcrumb: added")
        callbackContext.success()
    }

    private fun handleClearBreadcrumbs(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        Sentry.clearBreadcrumbs()
        Log.d(TAG, "clearBreadcrumbs: cleared")
        callbackContext.success()
    }

    // ==================== USER CONTEXT ====================

    private fun handleSetUser(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val obj = args.optJSONObject(0)
        if (obj == null) {
            callbackContext.error("setUser requires a user object.")
            return
        }

        val user = User()
        optTrimmedString(obj, "id").takeIf { it.isNotEmpty() }?.let { user.setId(it) }
        optTrimmedString(obj, "username").takeIf { it.isNotEmpty() }?.let { user.setUsername(it) }
        optTrimmedString(obj, "email").takeIf { it.isNotEmpty() }?.let { user.setEmail(it) }
        optTrimmedString(obj, "name").takeIf { it.isNotEmpty() }?.let { user.setName(it) }
        optTrimmedString(obj, "ipAddress").takeIf { it.isNotEmpty() }?.let { user.setIpAddress(it) }

        val dataObj = obj.optJSONObject("data")
        if (dataObj != null) {
            val stringData = mutableMapOf<String, String>()
            val keys = dataObj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (!dataObj.isNull(key)) {
                    stringData[key] = dataObj.opt(key)?.toString().orEmpty()
                }
            }
            if (stringData.isNotEmpty()) {
                user.setData(stringData)
            }
        }

        Sentry.setUser(user)
        Log.d(TAG, "setUser: updated")
        callbackContext.success()
    }

    private fun handleClearUser(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        Sentry.setUser(null)
        Log.d(TAG, "clearUser: cleared")
        callbackContext.success()
    }

    // ==================== SCOPE (TAGS, EXTRAS, CONTEXTS) ====================

    private fun handleSetTag(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("setTag requires a non-empty 'key'.")
            return
        }
        val value = optStringArg(args, 1)
        Sentry.setTag(key, value)
        Log.d(TAG, "setTag: key=$key")
        callbackContext.success()
    }

    private fun handleRemoveTag(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("removeTag requires a non-empty 'key'.")
            return
        }
        Sentry.removeTag(key)
        Log.d(TAG, "removeTag: key=$key")
        callbackContext.success()
    }

    private fun handleSetExtra(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("setExtra requires a non-empty 'key'.")
            return
        }
        val rawValue = if (args.isNull(1)) null else args.opt(1)
        if (rawValue == null) {
            Sentry.removeExtra(key)
        } else {
            Sentry.setExtra(key, rawValue.toString())
        }
        Log.d(TAG, "setExtra: key=$key")
        callbackContext.success()
    }

    private fun handleRemoveExtra(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("removeExtra requires a non-empty 'key'.")
            return
        }
        Sentry.removeExtra(key)
        Log.d(TAG, "removeExtra: key=$key")
        callbackContext.success()
    }

    private fun handleSetContext(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("setContext requires a non-empty 'key'.")
            return
        }
        val valueMap = jsonObjectToMap(args.optJSONObject(1))
        Sentry.configureScope { scope ->
            scope.setContexts(key, valueMap)
        }
        Log.d(TAG, "setContext: key=$key")
        callbackContext.success()
    }

    private fun handleRemoveContext(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("removeContext requires a non-empty 'key'.")
            return
        }
        Sentry.configureScope { scope ->
            scope.removeContexts(key)
        }
        Log.d(TAG, "removeContext: key=$key")
        callbackContext.success()
    }

    private fun handleClearScope(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        Sentry.configureScope { scope ->
            scope.clear()
        }
        Log.d(TAG, "clearScope: cleared")
        callbackContext.success()
    }

    // ==================== PERFORMANCE TRANSACTIONS ====================

    private fun handleStartTransaction(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val payload = args.optJSONObject(0)
        if (payload == null) {
            callbackContext.error("startTransaction requires a payload object.")
            return
        }
        val name = optTrimmedString(payload, "name")
        if (name.isEmpty()) {
            callbackContext.error("startTransaction requires a non-empty 'name'.")
            return
        }
        val operation = optTrimmedString(payload, "operation").ifEmpty { "custom" }
        val description = optTrimmedString(payload, "description").ifEmpty { null }
        val dataMap = jsonObjectToMap(payload.optJSONObject("data"))

        val transaction = Sentry.startTransaction(name, operation)
        if (description != null) {
            transaction.setDescription(description)
        }
        for ((k, v) in dataMap) {
            if (v != null) {
                transaction.setData(k, v)
            }
        }

        val txId = UUID.randomUUID().toString()
        activeTransactions[txId] = transaction
        Log.d(TAG, "startTransaction: operation=$operation")
        callbackContext.success(txId)
    }

    private fun handleFinishTransaction(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val txId = optStringArg(args, 0)
        if (txId.isEmpty()) {
            callbackContext.error("finishTransaction requires a non-empty 'transactionId'.")
            return
        }

        val transaction = activeTransactions.remove(txId)
        if (transaction == null) {
            callbackContext.error("No active transaction found for id '$txId'.")
            return
        }

        val status = parseSpanStatus(optStringArg(args, 1).ifEmpty { "ok" })
        val dataMap = jsonObjectToMap(args.optJSONObject(2))
        for ((k, v) in dataMap) {
            if (v != null) {
                transaction.setData(k, v)
            }
        }
        transaction.finish(status)
        Log.d(TAG, "finishTransaction: status=${status.name}")
        callbackContext.success()
    }

    // ==================== SESSIONS & CRASH TEST ====================

    private fun handleStartSession(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        Sentry.startSession()
        Log.d(TAG, "startSession: started")
        callbackContext.success()
    }

    private fun handleEndSession(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        Sentry.endSession()
        Log.d(TAG, "endSession: ended")
        callbackContext.success()
    }

    private fun handleNativeCrash(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val activity = cordova.activity
        if (activity == null) {
            callbackContext.error("Android Activity is unavailable.")
            return
        }
        Log.w(TAG, "nativeCrash: triggering deliberate test crash")
        activity.runOnUiThread {
            throw RuntimeException("SentryCordova deliberate native test crash")
        }
    }

    // ==================== HELPERS ====================

    private fun requireInitialized(callbackContext: CallbackContext): Boolean {
        if (!Sentry.isEnabled()) {
            Log.w(TAG, NOT_INITIALIZED_ERROR)
            callbackContext.error(NOT_INITIALIZED_ERROR)
            return false
        }
        return true
    }

    private fun cleanPreference(key: String): String {
        val value = preferences.getString(key, "")?.trim().orEmpty()
        return if (value.startsWith("$")) "" else value
    }

    private fun parseDoublePreference(key: String, defaultValue: Double): Double {
        return cleanPreference(key).toDoubleOrNull() ?: defaultValue
    }

    private fun parseIntPreference(key: String, defaultValue: Int): Int {
        return cleanPreference(key).toIntOrNull() ?: defaultValue
    }

    private fun optStringArg(args: JSONArray, index: Int): String {
        if (index >= args.length() || args.isNull(index)) return ""
        return args.optString(index, "").trim()
    }

    private fun optTrimmedString(obj: JSONObject, key: String): String {
        if (!obj.has(key) || obj.isNull(key)) return ""
        return obj.optString(key, "").trim()
    }

    private fun optDouble(obj: JSONObject, key: String, defaultValue: Double): Double {
        if (!obj.has(key) || obj.isNull(key)) return defaultValue
        val value = obj.optDouble(key, defaultValue)
        return if (value.isNaN()) defaultValue else value
    }

    private fun parseLevel(raw: String): SentryLevel {
        return when (raw.trim().lowercase(Locale.US)) {
            "debug" -> SentryLevel.DEBUG
            "warning", "warn" -> SentryLevel.WARNING
            "error" -> SentryLevel.ERROR
            "fatal" -> SentryLevel.FATAL
            else -> SentryLevel.INFO
        }
    }

    private fun parseSpanStatus(raw: String): SpanStatus {
        return when (raw.trim().lowercase(Locale.US)) {
            "cancelled" -> SpanStatus.CANCELLED
            "internal_error" -> SpanStatus.INTERNAL_ERROR
            "unknown", "unknown_error" -> SpanStatus.UNKNOWN_ERROR
            "invalid_argument" -> SpanStatus.INVALID_ARGUMENT
            "deadline_exceeded" -> SpanStatus.DEADLINE_EXCEEDED
            "not_found" -> SpanStatus.NOT_FOUND
            "already_exists" -> SpanStatus.ALREADY_EXISTS
            "permission_denied" -> SpanStatus.PERMISSION_DENIED
            "resource_exhausted" -> SpanStatus.RESOURCE_EXHAUSTED
            "failed_precondition" -> SpanStatus.FAILED_PRECONDITION
            "aborted" -> SpanStatus.ABORTED
            "out_of_range" -> SpanStatus.OUT_OF_RANGE
            "unimplemented" -> SpanStatus.UNIMPLEMENTED
            "unavailable" -> SpanStatus.UNAVAILABLE
            "data_loss" -> SpanStatus.DATA_LOSS
            "unauthenticated" -> SpanStatus.UNAUTHENTICATED
            else -> SpanStatus.OK
        }
    }

    private fun parseFrames(framesArray: JSONArray?): List<SentryStackFrame> {
        if (framesArray == null || framesArray.length() == 0) return emptyList()
        val frames = mutableListOf<SentryStackFrame>()
        for (i in 0 until framesArray.length()) {
            val item = framesArray.optJSONObject(i) ?: continue
            val frame = SentryStackFrame()
            optTrimmedString(item, "function").takeIf { it.isNotEmpty() }?.let { frame.setFunction(it) }
            optTrimmedString(item, "filename").takeIf { it.isNotEmpty() }?.let {
                frame.setFilename(it)
                frame.setAbsPath(it)
            }
            if (item.has("lineno") && !item.isNull("lineno")) {
                frame.setLineno(item.optInt("lineno"))
            }
            if (item.has("colno") && !item.isNull("colno")) {
                frame.setColno(item.optInt("colno"))
            }
            frame.setInApp(item.optBoolean("inApp", true))
            frame.setPlatform("javascript")
            frames.add(frame)
        }
        return frames
    }

    private fun applyTags(tagsObj: JSONObject?, event: SentryEvent) {
        if (tagsObj == null) return
        val keys = tagsObj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            if (!tagsObj.isNull(key)) {
                event.setTag(key, tagsObj.opt(key)?.toString().orEmpty())
            }
        }
    }

    private fun applyExtras(extrasObj: JSONObject?, event: SentryEvent) {
        val map = jsonObjectToMap(extrasObj)
        for ((k, v) in map) {
            if (v != null) {
                event.setExtra(k, v)
            }
        }
    }

    private fun extractStringList(arr: JSONArray?): List<String> {
        if (arr == null || arr.length() == 0) return emptyList()
        val list = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            val item = arr.optString(i, "").trim()
            if (item.isNotEmpty()) list.add(item)
        }
        return list
    }

    private fun jsonObjectToMap(jsonObject: JSONObject?): Map<String, Any?> {
        if (jsonObject == null) return emptyMap()
        val map = mutableMapOf<String, Any?>()
        val keys = jsonObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = jsonValueToKotlin(jsonObject.opt(key))
        }
        return map
    }

    private fun jsonArrayToList(jsonArray: JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until jsonArray.length()) {
            list.add(jsonValueToKotlin(jsonArray.opt(i)))
        }
        return list
    }

    private fun jsonValueToKotlin(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(value)
            is JSONArray -> jsonArrayToList(value)
            else -> value
        }
    }
}
