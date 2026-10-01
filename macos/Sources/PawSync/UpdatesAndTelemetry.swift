import AppKit
#if canImport(Sparkle)
import Sparkle
#endif
#if canImport(Sentry)
import Sentry
#endif

@MainActor final class UpdateService {
    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    #endif
    init() {
        #if canImport(Sparkle)
        if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           URL(string: feed)?.scheme == "https", Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            controller?.updater.automaticallyDownloadsUpdates = false
            controller?.updater.updateCheckInterval = 86400
        }
        #endif
    }
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        #if canImport(Sparkle)
        if let controller { controller.checkForUpdates(nil); return }
        #endif
        let alert = NSAlert(); alert.messageText = "Updates aren’t configured yet"
        alert.informativeText = "This development build has no signed release feed. Release builds use Sparkle’s confirmation flow."
        alert.runModal()
    }
}

@MainActor enum Diagnostics {
    static func configure(enabled: Bool, configuration: AppConfiguration) {
        #if canImport(Sentry)
        SentrySDK.close()
        guard enabled, !configuration.sentryDSN.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = configuration.sentryDSN
            options.environment = configuration.environment
            options.sendDefaultPii = false
            options.enableAutoSessionTracking = false
            options.enableAutoPerformanceTracing = false
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableFileIOTracing = false
            options.enableAppHangTracking = false
            options.enableSwizzling = false
            options.maxBreadcrumbs = 0
            options.tracesSampleRate = 0
            options.beforeSend = { event in event.user = nil; event.breadcrumbs = nil; return event }
        }
        #endif
    }
}
