import Flutter
import UIKit
import Sentry

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ✅ CRÍTICO: Inicializar Sentry NATIVAMENTE no iOS ANTES de tudo
    SentrySDK.start { options in
      options.dsn = "https://16c773f79c6fc2a3a4951733ce3570ed@o4504103203045376.ingest.us.sentry.io/4510326779740160"
      options.debug = true  // ✅ FORÇAR debug para diagnóstico
      options.tracesSampleRate = 1.0
      options.environment = "production"

      // ✅ Capturar TODOS os crashes nativos do iOS
      options.enableCaptureFailedRequests = true
      options.enableAutoSessionTracking = true
      options.sessionTrackingIntervalMillis = 30000

      print("✅ [iOS Native] Sentry inicializado nativamente no AppDelegate")
      print("✅ [iOS Native] DSN configurado: \(options.dsn ?? "N/A")")
      print("✅ [iOS Native] Debug mode: \(options.debug)")
    }

    // ✅ Enviar evento de teste nativo para confirmar funcionamento
    SentrySDK.capture(message: "🍎 iOS AppDelegate: Sentry NATIVO inicializado com sucesso!")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ Capturar erros não tratados nativamente
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    SentrySDK.capture(message: "🍎 iOS App ficou ativa - Sentry monitorando")
  }
}
