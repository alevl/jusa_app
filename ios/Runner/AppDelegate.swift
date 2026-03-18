import UIKit
import Flutter
import GoogleMaps // 1. Importamos la librería de mapas

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 2. Proporcionamos la API Key de Google Cloud Console
    GMSServices.provideAPIKey("TU_CLAVE_AQUI")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}