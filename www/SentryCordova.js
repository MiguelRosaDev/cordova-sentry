var exec = require('cordova/exec');

// Must match the <feature> name in plugin.xml and the native class registered
// for Android (Kotlin) and iOS (Swift).
var PLUGIN_NAME = 'SentryCordova';

var globalErrorHandler = null;
var globalRejectionHandler = null;

function isFunction(value) {
    return typeof value === 'function';
}

/**
 * Parses a JavaScript stack trace string (V8/Chrome on Android WebView or
 * JavaScriptCore/Safari on iOS WKWebView) into Sentry stack frames ordered
 * oldest-to-newest (Sentry convention).
 *
 * @param {string} stack
 * @returns {Array<Object>}
 */
function parseJsStacktrace(stack) {
    if (typeof stack !== 'string' || !stack.trim()) {
        return [];
    }

    var lines = stack.split(/\r?\n/);
    var frames = [];

    // V8/Chrome: "    at funcName (https://host/file.js:10:20)" or "    at https://host/file.js:10:20"
    var chromeWithFn = /^\s*at\s+(.+?)\s+\((.+?):(\d+):(\d+)\)\s*$/;
    var chromeNoFn = /^\s*at\s+(.+?):(\d+):(\d+)\s*$/;
    // Safari/WebKit (iOS WKWebView): "funcName@https://host/file.js:10:20" or "@https://host/file.js:10:20"
    var safariRe = /^\s*([^@]*)@(.+?):(\d+):(\d+)\s*$/;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var match = chromeWithFn.exec(line);
        if (match) {
            frames.push({
                function: match[1] || '<anonymous>',
                filename: match[2],
                lineno: parseInt(match[3], 10),
                colno: parseInt(match[4], 10),
                inApp: true
            });
            continue;
        }

        match = chromeNoFn.exec(line);
        if (match) {
            frames.push({
                function: '<anonymous>',
                filename: match[1],
                lineno: parseInt(match[2], 10),
                colno: parseInt(match[3], 10),
                inApp: true
            });
            continue;
        }

        match = safariRe.exec(line);
        if (match) {
            frames.push({
                function: match[1] || '<anonymous>',
                filename: match[2],
                lineno: parseInt(match[3], 10),
                colno: parseInt(match[4], 10),
                inApp: true
            });
        }
    }

    // Sentry expects frames ordered from oldest (caller) to newest (throwing frame)
    return frames.reverse();
}

var SentryCordova = {
    /**
     * Initializes the native Sentry SDK at runtime.
     * Note: When SENTRY_AUTO_INITIALIZE="true" (default), Sentry is already initialized
     * natively during pluginInitialize(). Calling initialize() again is idempotent.
     *
     * @param {Object}   config
     * @param {string}   config.dsn                          Sentry project DSN (required).
     * @param {string}   [config.environment="production"]   Environment name.
     * @param {string}   [config.release]                    Optional release identifier.
     * @param {string}   [config.dist]                       Optional distribution identifier.
     * @param {number}   [config.sampleRate=1.0]             Error event sample rate (0.0 to 1.0).
     * @param {number}   [config.tracesSampleRate=0.0]       Performance tracing sample rate (0.0 to 1.0).
     * @param {boolean}  [config.sendDefaultPii=false]       Include default PII (keep false for GDPR).
     * @param {boolean}  [config.enableAutoSessionTracking=true] Track release health sessions.
     * @param {boolean}  [config.anrEnabled=true]            Enable Android ANR / iOS App Hang detection.
     * @param {boolean}  [config.attachScreenshot=false]     Attach screenshots to errors.
     * @param {boolean}  [config.attachViewHierarchy=false]  Attach native view hierarchy to errors.
     * @param {number}   [config.maxBreadcrumbs=100]         Max breadcrumbs retained in scope.
     * @param {boolean}  [config.debug=false]                Enable Sentry internal debug logs.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    initialize: function (config, onSuccess, onError) {
        var payload = config && typeof config === 'object' ? Object.assign({}, config) : {};
        exec(onSuccess, onError, PLUGIN_NAME, 'initialize', [payload]);
    },

    /**
     * Checks whether the native Sentry SDK is currently enabled/initialized.
     *
     * @param {Function} onSuccess Receives boolean (`true` or `false`).
     * @param {Function} [onError]
     */
    isInitialized: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'isInitialized', []);
    },

    /**
     * Closes the native Sentry SDK and stops event transmission.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    close: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'close', []);
    },

    /**
     * Waits up to `timeoutMs` milliseconds for queued Sentry events to flush.
     *
     * @param {number|Function} [timeoutMs=2000] Timeout in milliseconds.
     * @param {Function}        [onSuccess]
     * @param {Function}        [onError]
     */
    flush: function (timeoutMs, onSuccess, onError) {
        var timeout = timeoutMs;
        var success = onSuccess;
        var error = onError;

        if (isFunction(timeoutMs)) {
            success = timeoutMs;
            error = onSuccess;
            timeout = 2000;
        }
        if (typeof timeout !== 'number' || isNaN(timeout) || timeout < 0) {
            timeout = 2000;
        }

        exec(success, error, PLUGIN_NAME, 'flush', [timeout]);
    },

    /**
     * Checks whether the previous app session ended in a native crash.
     *
     * @param {Function} onSuccess Receives boolean (`true` or `false`).
     * @param {Function} [onError]
     */
    crashedLastRun: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'crashedLastRun', []);
    },

    /**
     * Captures a message event and sends it to Sentry.
     * Supports either an options object `{ message, level, tags, extras, fingerprint }`
     * or positional arguments `(message, level, tags, extras, onSuccess, onError)`.
     *
     * @param {string|Object} messageOrOptions
     * @param {string|Function} [level="info"]  "debug" | "info" | "warning" | "error" | "fatal".
     * @param {Object|Function} [tags]
     * @param {Object|Function} [extras]
     * @param {Function}        [onSuccess]     Receives Sentry eventId string.
     * @param {Function}        [onError]
     */
    captureMessage: function (messageOrOptions, level, tags, extras, onSuccess, onError) {
        var payload = {
            message: '',
            level: 'info',
            tags: {},
            extras: {},
            fingerprint: []
        };
        var success = onSuccess;
        var error = onError;

        if (messageOrOptions && typeof messageOrOptions === 'object') {
            payload.message = messageOrOptions.message || '';
            payload.level = messageOrOptions.level || 'info';
            payload.tags = messageOrOptions.tags && typeof messageOrOptions.tags === 'object'
                ? messageOrOptions.tags : {};
            payload.extras = messageOrOptions.extras && typeof messageOrOptions.extras === 'object'
                ? messageOrOptions.extras : {};
            payload.fingerprint = Array.isArray(messageOrOptions.fingerprint)
                ? messageOrOptions.fingerprint : [];
            success = level;
            error = tags;
        } else {
            payload.message = messageOrOptions || '';
            if (isFunction(level)) {
                success = level;
                error = tags;
            } else {
                payload.level = level || 'info';
                if (isFunction(tags)) {
                    success = tags;
                    error = extras;
                } else {
                    payload.tags = tags && typeof tags === 'object' ? tags : {};
                    if (isFunction(extras)) {
                        success = extras;
                        error = onSuccess;
                    } else {
                        payload.extras = extras && typeof extras === 'object' ? extras : {};
                    }
                }
            }
        }

        exec(success, error, PLUGIN_NAME, 'captureMessage', [payload]);
    },

    /**
     * Captures an exception (JS Error, string, or structured options object) and sends it
     * to the native Sentry SDK with parsed stack frames.
     *
     * @param {Error|string|Object} errorOrOptions
     *   When object: `{ message, type, stacktrace, frames, level, handled, tags, extras, fingerprint }`.
     * @param {Function} [onSuccess] Receives Sentry eventId string.
     * @param {Function} [onError]
     */
    captureException: function (errorOrOptions, onSuccess, onError) {
        var payload = {
            message: '',
            type: 'Error',
            stacktrace: '',
            frames: [],
            level: 'error',
            handled: true,
            tags: {},
            extras: {},
            fingerprint: []
        };

        if (errorOrOptions instanceof Error) {
            payload.type = errorOrOptions.name || 'Error';
            payload.message = errorOrOptions.message || String(errorOrOptions);
            payload.stacktrace = errorOrOptions.stack || '';
            payload.frames = parseJsStacktrace(payload.stacktrace);
        } else if (errorOrOptions && typeof errorOrOptions === 'object') {
            payload.type = errorOrOptions.type || errorOrOptions.name || 'Error';
            payload.message = errorOrOptions.message || '';
            payload.stacktrace = errorOrOptions.stacktrace || errorOrOptions.stack || '';
            payload.frames = Array.isArray(errorOrOptions.frames)
                ? errorOrOptions.frames
                : parseJsStacktrace(payload.stacktrace);
            payload.level = errorOrOptions.level || 'error';
            payload.handled = errorOrOptions.handled !== undefined ? !!errorOrOptions.handled : true;
            payload.tags = errorOrOptions.tags && typeof errorOrOptions.tags === 'object'
                ? errorOrOptions.tags : {};
            payload.extras = errorOrOptions.extras && typeof errorOrOptions.extras === 'object'
                ? errorOrOptions.extras : {};
            payload.fingerprint = Array.isArray(errorOrOptions.fingerprint)
                ? errorOrOptions.fingerprint : [];
        } else if (typeof errorOrOptions === 'string') {
            payload.message = errorOrOptions;
        }

        exec(onSuccess, onError, PLUGIN_NAME, 'captureException', [payload]);
    },

    /**
     * Records a breadcrumb that will be attached to subsequent Sentry events.
     *
     * @param {string|Object} breadcrumbOrMessage
     *   When object: `{ message, category, type, level, data }`.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    addBreadcrumb: function (breadcrumbOrMessage, onSuccess, onError) {
        var payload;
        if (typeof breadcrumbOrMessage === 'string') {
            payload = { message: breadcrumbOrMessage, category: 'custom', level: 'info' };
        } else if (breadcrumbOrMessage && typeof breadcrumbOrMessage === 'object') {
            payload = Object.assign({}, breadcrumbOrMessage);
        } else {
            payload = {};
        }

        exec(onSuccess, onError, PLUGIN_NAME, 'addBreadcrumb', [payload]);
    },

    /**
     * Clears all breadcrumbs from the current Sentry scope.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    clearBreadcrumbs: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'clearBreadcrumbs', []);
    },

    /**
     * Sets user context attached to subsequent Sentry events.
     * GDPR note: Prefer internal surrogate IDs (e.g. UserId / CustomerId) over raw PII.
     *
     * @param {Object}   user
     * @param {string}   [user.id]
     * @param {string}   [user.username]
     * @param {string}   [user.email]
     * @param {string}   [user.name]
     * @param {string}   [user.ipAddress]
     * @param {Object}   [user.data]
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    setUser: function (user, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'setUser', [
            user && typeof user === 'object' ? user : {}
        ]);
    },

    /**
     * Clears the user context (call on user logout).
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    clearUser: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'clearUser', []);
    },

    /**
     * Sets a global tag (indexed/searchable in Sentry) on the current scope.
     *
     * @param {string}   key
     * @param {string}   value
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    setTag: function (key, value, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'setTag', [key, value !== undefined && value !== null ? String(value) : '']);
    },

    /**
     * Removes a tag from the current scope.
     *
     * @param {string}   key
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    removeTag: function (key, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'removeTag', [key]);
    },

    /**
     * Sets an extra key/value pair on the current scope.
     *
     * @param {string}   key
     * @param {*}        value
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    setExtra: function (key, value, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'setExtra', [key, value]);
    },

    /**
     * Removes an extra entry from the current scope.
     *
     * @param {string}   key
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    removeExtra: function (key, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'removeExtra', [key]);
    },

    /**
     * Sets a structured context object on the current scope (e.g. "order", { orderId: "123" }).
     *
     * @param {string}   key
     * @param {Object}   value
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    setContext: function (key, value, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'setContext', [
            key,
            value && typeof value === 'object' ? value : {}
        ]);
    },

    /**
     * Removes a structured context from the current scope.
     *
     * @param {string}   key
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    removeContext: function (key, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'removeContext', [key]);
    },

    /**
     * Clears all tags, extras, contexts, breadcrumbs, and user info from the current scope.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    clearScope: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'clearScope', []);
    },

    /**
     * Starts a Sentry performance transaction (requires `tracesSampleRate > 0`).
     * Supports either an options object `{ name, operation, description, data }`
     * or positional arguments `(name, operation, description, data, onSuccess, onError)`.
     *
     * @param {string|Object} nameOrOptions
     * @param {string|Function} [operation="custom"]
     * @param {string|Function} [description]
     * @param {Object|Function} [data]
     * @param {Function}        [onSuccess] Receives transactionId string.
     * @param {Function}        [onError]
     */
    startTransaction: function (nameOrOptions, operation, description, data, onSuccess, onError) {
        var payload = {
            name: '',
            operation: 'custom',
            description: null,
            data: {}
        };
        var success = onSuccess;
        var error = onError;

        if (nameOrOptions && typeof nameOrOptions === 'object') {
            payload.name = nameOrOptions.name || '';
            payload.operation = nameOrOptions.operation || 'custom';
            payload.description = nameOrOptions.description || null;
            payload.data = nameOrOptions.data && typeof nameOrOptions.data === 'object'
                ? nameOrOptions.data : {};
            success = operation;
            error = description;
        } else {
            payload.name = nameOrOptions || '';
            if (isFunction(operation)) {
                success = operation;
                error = description;
            } else {
                payload.operation = operation || 'custom';
                if (isFunction(description)) {
                    success = description;
                    error = data;
                } else {
                    payload.description = description || null;
                    if (isFunction(data)) {
                        success = data;
                        error = onSuccess;
                    } else {
                        payload.data = data && typeof data === 'object' ? data : {};
                    }
                }
            }
        }

        exec(success, error, PLUGIN_NAME, 'startTransaction', [payload]);
    },

    /**
     * Finishes a previously started performance transaction.
     *
     * @param {string}          transactionId ID returned by `startTransaction`.
     * @param {string|Function} [status="ok"] Span status: "ok", "cancelled", "internal_error", "invalid_argument", "deadline_exceeded", "not_found", "permission_denied", "unauthenticated", "unavailable", etc.
     * @param {Object|Function} [data]        Optional final data attributes.
     * @param {Function}        [onSuccess]
     * @param {Function}        [onError]
     */
    finishTransaction: function (transactionId, status, data, onSuccess, onError) {
        var txStatus = 'ok';
        var txData = {};
        var success = onSuccess;
        var error = onError;

        if (isFunction(status)) {
            success = status;
            error = data;
        } else {
            txStatus = status || 'ok';
            if (isFunction(data)) {
                success = data;
                error = onSuccess;
            } else {
                txData = data && typeof data === 'object' ? data : {};
            }
        }

        exec(success, error, PLUGIN_NAME, 'finishTransaction', [transactionId, txStatus, txData]);
    },

    /**
     * Manually starts a new Release Health session.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    startSession: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'startSession', []);
    },

    /**
     * Manually ends the current Release Health session.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    endSession: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'endSession', []);
    },

    /**
     * Triggers an intentional native crash to verify Sentry crash reporting in DEV/QA.
     * Never call this in production flows.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    nativeCrash: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'nativeCrash', []);
    },

    /**
     * Attaches global WebView `error` and `unhandledrejection` listeners so unhandled
     * OutSystems / JavaScript exceptions are forwarded automatically to native Sentry.
     */
    installGlobalErrorHandlers: function () {
        if (typeof window === 'undefined' || globalErrorHandler) {
            return;
        }

        globalErrorHandler = function (event) {
            var err = event && event.error;
            if (err instanceof Error) {
                SentryCordova.captureException({
                    type: err.name || 'Error',
                    message: err.message || (event && event.message) || 'Unhandled JavaScript error',
                    stacktrace: err.stack || '',
                    handled: false,
                    tags: { origin: 'webview.onerror' }
                });
            } else {
                SentryCordova.captureException({
                    type: 'Error',
                    message: (event && event.message) || 'Unhandled JavaScript error',
                    frames: event && event.filename ? [{
                        function: '<global>',
                        filename: event.filename,
                        lineno: event.lineno || 0,
                        colno: event.colno || 0,
                        inApp: true
                    }] : [],
                    handled: false,
                    tags: { origin: 'webview.onerror' }
                });
            }
        };

        globalRejectionHandler = function (event) {
            var reason = event && event.reason;
            if (reason instanceof Error) {
                SentryCordova.captureException({
                    type: reason.name || 'UnhandledRejection',
                    message: reason.message || 'Unhandled Promise rejection',
                    stacktrace: reason.stack || '',
                    handled: false,
                    tags: { origin: 'webview.unhandledrejection' }
                });
            } else {
                SentryCordova.captureException({
                    type: 'UnhandledRejection',
                    message: reason !== undefined ? String(reason) : 'Unhandled Promise rejection',
                    handled: false,
                    tags: { origin: 'webview.unhandledrejection' }
                });
            }
        };

        window.addEventListener('error', globalErrorHandler);
        window.addEventListener('unhandledrejection', globalRejectionHandler);
    },

    /**
     * Removes global WebView error listeners installed by `installGlobalErrorHandlers()`.
     */
    uninstallGlobalErrorHandlers: function () {
        if (typeof window === 'undefined') {
            return;
        }
        if (globalErrorHandler) {
            window.removeEventListener('error', globalErrorHandler);
            globalErrorHandler = null;
        }
        if (globalRejectionHandler) {
            window.removeEventListener('unhandledrejection', globalRejectionHandler);
            globalRejectionHandler = null;
        }
    }
};

module.exports = SentryCordova;
