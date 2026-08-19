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
    //
    // FlutterPluginRegistry itself has no `.messenger` — that lives on
    // FlutterPluginRegistrar, obtained via registrar(forPlugin:). "Receipt
    // Channel" here is just a unique key to claim a registrar slot, the
    // same way any real Flutter plugin bootstraps its own method channel.
    // registrar(forPlugin:) returns an Optional, so it has to be unwrapped
    // before .messenger is reachable on it.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReceiptChannel") else {
      return
    }
    let receiptChannel = FlutterMethodChannel(
        name: "com.geraldmiller.safeprepalcohol/receipt",
        binaryMessenger: registrar.messenger
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
