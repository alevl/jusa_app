import UIKit
import Flutter
import GoogleMaps // 1. Importante: Importar la librería de Google

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 2. REEMPLAZA "TU_API_KEY_AQUI" con tu llave real entre las comillas
    GMSServices.provideAPIKey("AIzaSyC-aarw02OP9iW4pwHoOlbZ2njidcJY82I")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}