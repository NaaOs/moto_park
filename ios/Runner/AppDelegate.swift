import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps SDK for iOS のAPIキー。
    // キーはソースに直書きせず Info.plist の "GMSApiKey" から読み込む。
    // Info.plist の値はビルド設定 $(GOOGLE_MAPS_API_KEY) を参照し、
    // 実際のキーは gitignore した ios/Flutter/Secrets.xcconfig もしくは
    // CI(Codemagic)の環境変数で注入する(リポジトリにキーを含めない)。
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty, key != "$(GOOGLE_MAPS_API_KEY)" {
      GMSServices.provideAPIKey(key)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
