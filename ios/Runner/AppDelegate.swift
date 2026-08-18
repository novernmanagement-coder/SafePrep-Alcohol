import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // ── Sandbox / TestFlight receipt check ──────────────────────
    // Mirrors SafePrep Manager's AppDelegate: lets Dart (iap_service.dart's
    // _isSandboxEnvironment()) ask whether this install is running a
    // TestFlight/sandbox build, by checking whether the on-device App
    // Store receipt file is named "sandboxReceipt" instead of the
    // production receipt name. Used to keep test purchases out of real
    // Mixpanel conversion data.
    let receiptChannel = FlutterMethodChannel(
        name: "com.geraldmiller.safeprepalcohol/receipt",
        binaryMessenger: engineBridge.pluginRegistry.messenger()
    )
    receiptChannel.setMethodCallHandler { (call, result) in
        if call.method == "isSandboxReceipt" {
            let receiptURL = Bundle.main.appStoreReceiptURL
            let isSandbox = receiptURL?.lastPathComponent == "sandboxReceipt"
            result(isSandbox)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    // ── END ─────────────────────────────────────────────────────
  }
}
