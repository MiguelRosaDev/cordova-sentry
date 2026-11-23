import Foundation

#if canImport(Cordova)
import Cordova
#endif

#if canImport(Sentry)
import Sentry
#elseif canImport(SentrySwift)
import SentrySwift
#endif

/**
 * SentryCordova: Native iOS implementation in Swift for OutSystems 11 (MABS 12 & MABS 13).
 *
 * Wraps the official Sentry Cocoa SDK (`Sentry` 9.19.1+ via CocoaPods on MABS 12 and SPM on MABS 13).
 *
 * Rules for OutSystems MABS (cordova-ios 7 & 8):
 * 1. Guard `import Cordova` with `#if canImport(Cordova)` for MABS 12 + MABS 13 SPM compatibility.
 * 2. Type `let pluginResult: CDVPluginResult = ...` explicitly and never use optional chaining on it.
 * 3. Always log with `NSLog("%@", "\(tag) ...")` and never log DSNs, PII, or raw payloads.
 */
@objc(SentryCordova)
public class SentryCordova: CDVPlugin {

    private let tag = "[SentryCordova]"
    private let notInitializedError =
        "Sentry SDK is not initialized. Configure SENTRY_DSN (or SENTRY_IOS_DSN) " +
            "in Extensibility Configurations, or call initialize() at runtime."

    private struct InitOptions {
        let dsn: String
        let environment: String
        let releaseName: String?
        let dist: String?
        let sampleRate: Double
        let tracesSampleRate: Double
        let sendDefaultPii: Bool
        let enableAutoSessionTracking: Bool
        let anrEnabled: Bool
        let attachScreenshot: Bool
        let attachViewHierarchy: Bool
        let maxBreadcrumbs: UInt
        let debug: Bool
    }

    private let transactionsLock = NSLock()
    private var activeTransactions: [String: Span] = [:]

    public override func pluginInitialize() {
        super.pluginInitialize()
        NSLog("%@", "\(tag) Plugin loaded")

        let autoInitialize = boolSetting("sentryautoinitialize", defaultValue: true)
        if !autoInitialize {
            NSLog("%@", "\(tag) Auto-initialize disabled; waiting for JS initialize() call")
            return
        }

        let iosDsn = cleanSetting("sentryiosdsn")
        let dsn = iosDsn.isEmpty ? cleanSetting("sentrydsn") : iosDsn
        if dsn.isEmpty {
            NSLog(
                "%@",
                "\(tag) Auto-initialize skipped: missing DSN (set SENTRY_DSN or SENTRY_IOS_DSN in Extensibility Configurations)"
            )
            return
        }

        let envSetting = cleanSetting("sentryenvironment")
        let releaseSetting = cleanSetting("sentryrelease")
        let distSetting = cleanSetting("sentrydist")

        let options = InitOptions(
            dsn: dsn,
            environment: envSetting.isEmpty ? "production" : envSetting,
            releaseName: releaseSetting.isEmpty ? nil : releaseSetting,
            dist: distSetting.isEmpty ? nil : distSetting,
            sampleRate: clampUnit(doubleSetting("sentrysamplerate", defaultValue: 1.0)),
            tracesSampleRate: clampUnit(doubleSetting("sentrytracessamplerate", defaultValue: 0.0)),
            sendDefaultPii: boolSetting("sentrysenddefaultpii", defaultValue: false),
            enableAutoSessionTracking: boolSetting("sentryenableautosessiontracking", defaultValue: true),
            anrEnabled: boolSetting("sentryanrenabled", defaultValue: true),
            attachScreenshot: boolSetting("sentryattachscreenshot", defaultValue: false),
            attachViewHierarchy: boolSetting("sentryattachviewhierarchy", defaultValue: false),
            maxBreadcrumbs: uintSetting("sentrymaxbreadcrumbs", defaultValue: 100),
            debug: boolSetting("sentrydebug", defaultValue: false)
        )

        let result = performInitialize(options: options)
        let initialized = (result["initialized"] as? Bool) ?? false
        NSLog("%@", "\(tag) Auto-initialization finished: initialized=\(initialized)")
    }

    // ==================== LIFECYCLE ====================

    @objc(initialize:)
    public func initialize(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=initialize")

        guard let config = command.arguments.first as? [String: Any] else {
            sendError("initialize requires a configuration object.", callbackId: command.callbackId)
            return
        }

        let dsn = trimmedString(config["dsn"])
        guard !dsn.isEmpty else {
            sendError("Configuration 'dsn' is required.", callbackId: command.callbackId)
            return
        }

        let envVal = trimmedString(config["environment"])
        let releaseVal = trimmedString(config["release"])
        let distVal = trimmedString(config["dist"])

        let options = InitOptions(
            dsn: dsn,
            environment: envVal.isEmpty ? "production" : envVal,
            releaseName: releaseVal.isEmpty ? nil : releaseVal,
            dist: distVal.isEmpty ? nil : distVal,
            sampleRate: clampUnit(doubleValue(config["sampleRate"], defaultValue: 1.0)),
            tracesSampleRate: clampUnit(doubleValue(config["tracesSampleRate"], defaultValue: 0.0)),
            sendDefaultPii: boolValue(config["sendDefaultPii"], defaultValue: false),
            enableAutoSessionTracking: boolValue(config["enableAutoSessionTracking"], defaultValue: true),
            anrEnabled: boolValue(config["anrEnabled"], defaultValue: true),
            attachScreenshot: boolValue(config["attachScreenshot"], defaultValue: false),
            attachViewHierarchy: boolValue(config["attachViewHierarchy"], defaultValue: false),
            maxBreadcrumbs: uintValue(config["maxBreadcrumbs"], defaultValue: 100),
            debug: boolValue(config["debug"], defaultValue: false)
        )

        DispatchQueue.main.async {
            let result = self.performInitialize(options: options)
            let pluginResult: CDVPluginResult = CDVPluginResult(
                status: .ok,
                messageAs: result
            )
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
    }

    private func performInitialize(options: InitOptions) -> [AnyHashable: Any] {
        if SentrySDK.isEnabled {
            NSLog("%@", "\(tag) SDK already initialized; skipping re-initialization")
            return [
                "initialized": true,
                "alreadyInitialized": true
            ]
        }

        SentrySDK.start { sentryOptions in
            sentryOptions.dsn = options.dsn
            sentryOptions.environment = options.environment
            if let releaseName = options.releaseName {
                sentryOptions.releaseName = releaseName
            }
            if let dist = options.dist {
                sentryOptions.dist = dist
            }
            sentryOptions.sampleRate = NSNumber(value: options.sampleRate)
            if options.tracesSampleRate > 0.0 {
                sentryOptions.tracesSampleRate = NSNumber(value: options.tracesSampleRate)
            }
            sentryOptions.sendDefaultPii = options.sendDefaultPii
            sentryOptions.enableAutoSessionTracking = options.enableAutoSessionTracking
            sentryOptions.enableAppHangTracking = options.anrEnabled
            sentryOptions.attachScreenshot = options.attachScreenshot
            sentryOptions.attachViewHierarchy = options.attachViewHierarchy
            sentryOptions.maxBreadcrumbs = options.maxBreadcrumbs
            sentryOptions.debug = options.debug
        }

        NSLog(
            "%@",
            "\(tag) Initialized Sentry SDK (env=\(options.environment), tracing=\(options.tracesSampleRate > 0.0), appHang=\(options.anrEnabled))"
        )

        return [
            "initialized": true,
            "alreadyInitialized": false
        ]
    }

    @objc(isInitialized:)
    public func isInitialized(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=isInitialized")
        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .ok,
            messageAs: SentrySDK.isEnabled
        )
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(close:)
    public func close(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=close")
        transactionsLock.lock()
        activeTransactions.removeAll()
        transactionsLock.unlock()

        SentrySDK.close()
        NSLog("%@", "\(tag) close: Sentry SDK closed")
        sendOk(callbackId: command.callbackId)
    }

    @objc(flush:)
    public func flush(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=flush")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let timeoutMs = max(0.0, doubleValue(argument(at: 0, in: command), defaultValue: 2000.0))
        let timeoutSec: TimeInterval = timeoutMs / 1000.0

        commandDelegate.run(inBackground: {
            SentrySDK.flush(timeout: timeoutSec)
            self.sendOk(callbackId: command.callbackId)
        })
    }

    @objc(crashedLastRun:)
    public func crashedLastRun(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=crashedLastRun")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .ok,
            messageAs: SentrySDK.crashedLastRun
        )
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    // ==================== CAPTURE MESSAGE & EXCEPTION ====================

    @objc(captureMessage:)
    public func captureMessage(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=captureMessage")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        guard let payload = command.arguments.first as? [String: Any] else {
            sendError("captureMessage requires a payload object.", callbackId: command.callbackId)
            return
        }

        let text = trimmedString(payload["message"])
        guard !text.isEmpty else {
            sendError("captureMessage requires a non-empty 'message'.", callbackId: command.callbackId)
            return
        }

        let level = parseLevel(trimmedString(payload["level"]))
        let event = Event(level: level)
        event.message = SentryMessage(formatted: text)

        if let tags = convertStringDictionary(payload["tags"] as? [String: Any]), !tags.isEmpty {
            event.tags = tags
        }
        if let extras = cleanDictionary(payload["extras"] as? [String: Any]), !extras.isEmpty {
            event.extra = extras
        }
        if let fingerprint = extractStringArray(payload["fingerprint"]), !fingerprint.isEmpty {
            event.fingerprint = fingerprint
        }

        let eventId = SentrySDK.capture(event: event)
        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .ok,
            messageAs: eventId.sentryIdString
        )
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(captureException:)
    public func captureException(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=captureException")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        guard let payload = command.arguments.first as? [String: Any] else {
            sendError("captureException requires a payload object.", callbackId: command.callbackId)
            return
        }

        let message = trimmedString(payload["message"])
        guard !message.isEmpty else {
            sendError("captureException requires a non-empty 'message'.", callbackId: command.callbackId)
            return
        }

        let rawType = trimmedString(payload["type"])
        let exceptionType = rawType.isEmpty ? "Error" : rawType
        let handled = boolValue(payload["handled"], defaultValue: true)
        let levelStr = trimmedString(payload["level"])
        let level = parseLevel(levelStr.isEmpty ? "error" : levelStr)
        let frames = parseFrames(payload["frames"] as? [Any])

        let mechanism = Mechanism(type: handled ? "generic" : "onerror")
        mechanism.handled = NSNumber(value: handled)

        let exception = Exception(value: message, type: exceptionType)
        exception.mechanism = mechanism
        if !frames.isEmpty {
            exception.stacktrace = SentryStacktrace(frames: frames, registers: [:])
        }

        let event = Event(level: level)
        if !frames.isEmpty {
            event.platform = "javascript"
        }
        event.exceptions = [exception]

        if let tags = convertStringDictionary(payload["tags"] as? [String: Any]), !tags.isEmpty {
            event.tags = tags
        }

        var extras = cleanDictionary(payload["extras"] as? [String: Any]) ?? [:]
        let rawStack = trimmedString(payload["stacktrace"])
        if frames.isEmpty && !rawStack.isEmpty {
            extras["js_stacktrace"] = rawStack
        }
        if !extras.isEmpty {
            event.extra = extras
        }

        if let fingerprint = extractStringArray(payload["fingerprint"]), !fingerprint.isEmpty {
            event.fingerprint = fingerprint
        }

        let eventId = SentrySDK.capture(event: event)
        NSLog("%@", "\(tag) captureException: type=\(exceptionType), handled=\(handled), frames=\(frames.count)")
        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .ok,
            messageAs: eventId.sentryIdString
        )
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    // ==================== BREADCRUMBS ====================

    @objc(addBreadcrumb:)
    public func addBreadcrumb(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=addBreadcrumb")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        guard let obj = command.arguments.first as? [String: Any] else {
            sendError("addBreadcrumb requires a breadcrumb object.", callbackId: command.callbackId)
            return
        }

        let level = parseLevel(trimmedString(obj["level"]))
        let rawCategory = trimmedString(obj["category"])
        let category = rawCategory.isEmpty ? "custom" : rawCategory
        let crumb = Breadcrumb(level: level, category: category)

        let message = trimmedString(obj["message"])
        if !message.isEmpty {
            crumb.message = message
        }
        let crumbType = trimmedString(obj["type"])
        if !crumbType.isEmpty {
            crumb.type = crumbType
        }
        crumb.origin = "cordova"

        if let data = cleanDictionary(obj["data"] as? [String: Any]), !data.isEmpty {
            crumb.data = data
        }

        SentrySDK.addBreadcrumb(crumb)
        sendOk(callbackId: command.callbackId)
    }

    @objc(clearBreadcrumbs:)
    public func clearBreadcrumbs(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=clearBreadcrumbs")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        SentrySDK.configureScope { scope in
            scope.clearBreadcrumbs()
        }
        NSLog("%@", "\(tag) clearBreadcrumbs: cleared")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== USER CONTEXT ====================

    @objc(setUser:)
    public func setUser(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=setUser")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        guard let obj = command.arguments.first as? [String: Any] else {
            sendError("setUser requires a user object.", callbackId: command.callbackId)
            return
        }

        let user = User()
        let userId = trimmedString(obj["id"])
        if !userId.isEmpty { user.userId = userId }
        let username = trimmedString(obj["username"])
        if !username.isEmpty { user.username = username }
        let email = trimmedString(obj["email"])
        if !email.isEmpty { user.email = email }
        let name = trimmedString(obj["name"])
        if !name.isEmpty { user.name = name }
        let ipAddress = trimmedString(obj["ipAddress"])
        if !ipAddress.isEmpty { user.ipAddress = ipAddress }

        if let data = cleanDictionary(obj["data"] as? [String: Any]), !data.isEmpty {
            user.data = data
        }

        SentrySDK.setUser(user)
        NSLog("%@", "\(tag) setUser: updated")
        sendOk(callbackId: command.callbackId)
    }

    @objc(clearUser:)
    public func clearUser(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=clearUser")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        SentrySDK.setUser(nil)
        NSLog("%@", "\(tag) clearUser: cleared")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== SCOPE (TAGS, EXTRAS, CONTEXTS) ====================

    @objc(setTag:)
    public func setTag(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=setTag")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("setTag requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }
        let value = trimmedString(argument(at: 1, in: command))

        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
        NSLog("%@", "\(tag) setTag: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(removeTag:)
    public func removeTag(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=removeTag")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("removeTag requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }

        SentrySDK.configureScope { scope in
            scope.removeTag(key: key)
        }
        NSLog("%@", "\(tag) removeTag: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(setExtra:)
    public func setExtra(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=setExtra")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("setExtra requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }
        let rawValue = argument(at: 1, in: command)

        SentrySDK.configureScope { scope in
            if let value = rawValue, !(value is NSNull) {
                scope.setExtra(value: value, key: key)
            } else {
                scope.removeExtra(key: key)
            }
        }
        NSLog("%@", "\(tag) setExtra: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(removeExtra:)
    public func removeExtra(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=removeExtra")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("removeExtra requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }

        SentrySDK.configureScope { scope in
            scope.removeExtra(key: key)
        }
        NSLog("%@", "\(tag) removeExtra: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(setContext:)
    public func setContext(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=setContext")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("setContext requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }
        let dict = cleanDictionary(argument(at: 1, in: command) as? [String: Any]) ?? [:]

        SentrySDK.configureScope { scope in
            scope.setContext(value: dict, key: key)
        }
        NSLog("%@", "\(tag) setContext: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(removeContext:)
    public func removeContext(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=removeContext")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("removeContext requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }

        SentrySDK.configureScope { scope in
            scope.removeContext(key: key)
        }
        NSLog("%@", "\(tag) removeContext: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(clearScope:)
    public func clearScope(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=clearScope")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        SentrySDK.configureScope { scope in
            scope.clear()
        }
        NSLog("%@", "\(tag) clearScope: cleared")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== PERFORMANCE TRANSACTIONS ====================

    @objc(startTransaction:)
    public func startTransaction(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=startTransaction")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        guard let payload = command.arguments.first as? [String: Any] else {
            sendError("startTransaction requires a payload object.", callbackId: command.callbackId)
            return
        }

        let name = trimmedString(payload["name"])
        guard !name.isEmpty else {
            sendError("startTransaction requires a non-empty 'name'.", callbackId: command.callbackId)
            return
        }

        let rawOp = trimmedString(payload["operation"])
        let operation = rawOp.isEmpty ? "custom" : rawOp
        let description = trimmedString(payload["description"])
        let data = cleanDictionary(payload["data"] as? [String: Any]) ?? [:]

        let transaction = SentrySDK.startTransaction(name: name, operation: operation)
        if !description.isEmpty {
            transaction.spanDescription = description
        }
        for (k, v) in data {
            transaction.setData(value: v, key: k)
        }

        let txId = UUID().uuidString
        transactionsLock.lock()
        activeTransactions[txId] = transaction
        transactionsLock.unlock()

        NSLog("%@", "\(tag) startTransaction: operation=\(operation)")
        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .ok,
            messageAs: txId
        )
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(finishTransaction:)
    public func finishTransaction(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=finishTransaction")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let txId = trimmedString(argument(at: 0, in: command))
        guard !txId.isEmpty else {
            sendError("finishTransaction requires a non-empty 'transactionId'.", callbackId: command.callbackId)
            return
        }

        transactionsLock.lock()
        let transaction = activeTransactions.removeValue(forKey: txId)
        transactionsLock.unlock()

        guard let span = transaction else {
            sendError("No active transaction found for id '\(txId)'.", callbackId: command.callbackId)
            return
        }

        let status = parseSpanStatus(trimmedString(argument(at: 1, in: command)))
        let data = cleanDictionary(argument(at: 2, in: command) as? [String: Any]) ?? [:]
        for (k, v) in data {
            span.setData(value: v, key: k)
        }
        span.finish(status: status)

        NSLog("%@", "\(tag) finishTransaction: completed")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== SESSIONS & CRASH TEST ====================

    @objc(startSession:)
    public func startSession(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=startSession")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        SentrySDK.startSession()
        NSLog("%@", "\(tag) startSession: started")
        sendOk(callbackId: command.callbackId)
    }

    @objc(endSession:)
    public func endSession(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=endSession")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        SentrySDK.endSession()
        NSLog("%@", "\(tag) endSession: ended")
        sendOk(callbackId: command.callbackId)
    }

    @objc(nativeCrash:)
    public func nativeCrash(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=nativeCrash")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        NSLog("%@", "\(tag) nativeCrash: triggering deliberate test crash")
        DispatchQueue.main.async {
            SentrySDK.crash()
        }
    }

    // ==================== HELPERS ====================

    private func requireInitialized(callbackId: String) -> Bool {
        if !SentrySDK.isEnabled {
            NSLog("%@", "\(tag) \(notInitializedError)")
            sendError(notInitializedError, callbackId: callbackId)
            return false
        }
        return true
    }

    private func sendOk(callbackId: String) {
        let pluginResult: CDVPluginResult = CDVPluginResult(status: .ok)
        commandDelegate.send(pluginResult, callbackId: callbackId)
    }

    private func sendError(_ message: String, callbackId: String) {
        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .error,
            messageAs: message
        )
        commandDelegate.send(pluginResult, callbackId: callbackId)
    }

    private func argument(at index: Int, in command: CDVInvokedUrlCommand) -> Any? {
        guard index >= 0 && index < command.arguments.count else { return nil }
        return command.arguments[index]
    }

    private func cleanSetting(_ lowercaseKey: String) -> String {
        guard let raw = commandDelegate.settings[lowercaseKey] as? String else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("$") ? "" : trimmed
    }

    private func boolSetting(_ lowercaseKey: String, defaultValue: Bool) -> Bool {
        let raw = cleanSetting(lowercaseKey).lowercased()
        if raw.isEmpty { return defaultValue }
        return raw == "true" || raw == "1" || raw == "yes"
    }

    private func doubleSetting(_ lowercaseKey: String, defaultValue: Double) -> Double {
        let raw = cleanSetting(lowercaseKey)
        return Double(raw) ?? defaultValue
    }

    private func uintSetting(_ lowercaseKey: String, defaultValue: UInt) -> UInt {
        let raw = cleanSetting(lowercaseKey)
        return UInt(raw) ?? defaultValue
    }

    private func trimmedString(_ value: Any?) -> String {
        guard let str = value as? String else { return "" }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boolValue(_ value: Any?, defaultValue: Bool) -> Bool {
        if let boolVal = value as? Bool { return boolVal }
        if let numVal = value as? NSNumber { return numVal.boolValue }
        if let strVal = value as? String {
            let lowered = strVal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowered == "true" || lowered == "1" { return true }
            if lowered == "false" || lowered == "0" { return false }
        }
        return defaultValue
    }

    private func doubleValue(_ value: Any?, defaultValue: Double) -> Double {
        if let numVal = value as? NSNumber { return numVal.doubleValue }
        if let strVal = value as? String, let parsed = Double(strVal) { return parsed }
        return defaultValue
    }

    private func uintValue(_ value: Any?, defaultValue: UInt) -> UInt {
        if let numVal = value as? NSNumber {
            let intVal = numVal.intValue
            return intVal >= 0 ? UInt(intVal) : defaultValue
        }
        if let strVal = value as? String, let parsed = UInt(strVal) { return parsed }
        return defaultValue
    }

    private func clampUnit(_ value: Double) -> Double {
        return min(max(value, 0.0), 1.0)
    }

    private func parseLevel(_ raw: String) -> SentryLevel {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug":
            return .debug
        case "warning", "warn":
            return .warning
        case "error":
            return .error
        case "fatal":
            return .fatal
        default:
            return .info
        }
    }

    private func parseSpanStatus(_ raw: String) -> SentrySpanStatus {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cancelled":
            return .cancelled
        case "internal_error":
            return .internalError
        case "unknown", "unknown_error":
            return .unknownError
        case "invalid_argument":
            return .invalidArgument
        case "deadline_exceeded":
            return .deadlineExceeded
        case "not_found":
            return .notFound
        case "already_exists":
            return .alreadyExists
        case "permission_denied":
            return .permissionDenied
        case "resource_exhausted":
            return .resourceExhausted
        case "failed_precondition":
            return .failedPrecondition
        case "aborted":
            return .aborted
        case "out_of_range":
            return .outOfRange
        case "unimplemented":
            return .unimplemented
        case "unavailable":
            return .unavailable
        case "data_loss":
            return .dataLoss
        case "unauthenticated":
            return .unauthenticated
        default:
            return .ok
        }
    }

    private func parseFrames(_ rawFrames: [Any]?) -> [Frame] {
        guard let rawFrames = rawFrames, !rawFrames.isEmpty else { return [] }
        var frames: [Frame] = []
        for item in rawFrames {
            guard let dict = item as? [String: Any] else { continue }
            let frame = Frame()
            let fn = trimmedString(dict["function"])
            if !fn.isEmpty { frame.function = fn }
            let file = trimmedString(dict["filename"])
            if !file.isEmpty { frame.fileName = file }
            if let line = dict["lineno"] as? NSNumber { frame.lineNumber = line }
            if let col = dict["colno"] as? NSNumber { frame.columnNumber = col }
            frame.inApp = NSNumber(value: boolValue(dict["inApp"], defaultValue: true))
            frame.platform = "javascript"
            frames.append(frame)
        }
        return frames
    }

    private func convertStringDictionary(_ raw: [String: Any]?) -> [String: String]? {
        guard let raw = raw else { return nil }
        var result: [String: String] = [:]
        for (key, value) in raw {
            if !(value is NSNull) {
                result[key] = String(describing: value)
            }
        }
        return result
    }

    private func cleanDictionary(_ raw: [String: Any]?) -> [String: Any]? {
        guard let raw = raw else { return nil }
        var result: [String: Any] = [:]
        for (key, value) in raw {
            if !(value is NSNull) {
                result[key] = value
            }
        }
        return result
    }

    private func extractStringArray(_ raw: Any?) -> [String]? {
        guard let arr = raw as? [Any] else { return nil }
        let strings = arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return strings.isEmpty ? nil : strings
    }
}
