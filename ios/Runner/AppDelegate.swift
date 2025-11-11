import Flutter
import UIKit
import Sentry
import MLKitVision
import MLKitFaceDetection

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let CHANNEL_NAME = "embarqueellus/native_face_detection"

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

      print("✅ [iOS Native] Sentry inicializado nativamente no AppDelegate")
      print("✅ [iOS Native] DSN configurado: \(options.dsn ?? "N/A")")
      print("✅ [iOS Native] Debug mode: \(options.debug)")
    }

    // ✅ Enviar evento de teste nativo para confirmar funcionamento
    SentrySDK.capture(message: "🍎 iOS AppDelegate: Sentry NATIVO inicializado com sucesso!")

    GeneratedPluginRegistrant.register(with: self)

    // Configurar Platform Channel para detecção facial nativa
    setupFaceDetectionChannel()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ Capturar erros não tratados nativamente
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    SentrySDK.capture(message: "🍎 iOS App ficou ativa - Sentry monitorando")
  }

  /// Configura o Platform Channel para detecção facial nativa
  private func setupFaceDetectionChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("❌ [iOS Native] Não foi possível obter FlutterViewController")
      return
    }

    let channel = FlutterMethodChannel(
      name: CHANNEL_NAME,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }

      if call.method == "detectAndCropFace" {
        self.handleFaceDetection(call: call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    print("✅ [iOS Native] Platform Channel configurado: \(CHANNEL_NAME)")
  }

  /// Processa a detecção e recorte facial nativamente
  private func handleFaceDetection(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let imagePath = args["path"] as? String else {
      SentrySDK.capture(message: "❌ [iOS Native] Argumentos inválidos no Platform Channel") { scope in
        scope.setLevel(.error)
        scope.setTag(value: "invalid_args", key: "error_type")
      }
      result(FlutterError(
        code: "INVALID_ARGS",
        message: "Argumentos inválidos. Esperado: {'path': String}",
        details: nil
      ))
      return
    }

    print("📸 [iOS Native] Iniciando detecção facial: \(imagePath)")
    SentrySDK.capture(message: "📸 [iOS Native] Iniciando detecção facial nativa") { scope in
      scope.setLevel(.info)
      scope.setContext(value: ["image_path": imagePath], key: "face_detection_start")
    }

    // PASSO 1: Carregar imagem (UIImage corrige EXIF automaticamente)
    guard let image = UIImage(contentsOfFile: imagePath) else {
      SentrySDK.capture(message: "❌ [iOS Native] Erro ao carregar imagem") { scope in
        scope.setLevel(.error)
        scope.setTag(value: "image_load_error", key: "error_type")
        scope.setContext(value: ["image_path": imagePath], key: "error_context")
      }
      result(FlutterError(
        code: "IMAGE_LOAD_ERROR",
        message: "Não foi possível carregar a imagem: \(imagePath)",
        details: nil
      ))
      return
    }

    print("✅ [iOS Native] Imagem carregada: \(image.size.width)x\(image.size.height)")
    print("🔍 [iOS Native] DEBUG - Orientation: \(image.imageOrientation.rawValue)")
    print("🔍 [iOS Native] DEBUG - Scale: \(image.scale)")

    SentrySDK.capture(message: "✅ [iOS Native] Imagem carregada (EXIF corrigido automaticamente)") { scope in
      scope.setLevel(.info)
      scope.setContext(value: [
        "width": image.size.width,
        "height": image.size.height,
        "orientation": image.imageOrientation.rawValue,
        "scale": image.scale
      ], key: "image_loaded")
    }

    // PASSO 2: Configurar detector do ML Kit
    let options = FaceDetectorOptions()
    options.performanceMode = .accurate
    options.landmarkMode = .all
    options.classificationMode = .none
    options.contourMode = .none
    options.minFaceSize = 0.01  // Mais sensível: 1% da imagem (era 5%)

    let faceDetector = FaceDetector.faceDetector(options: options)

    print("🔍 [iOS Native] DEBUG - Detector configurado: minFaceSize=0.01, mode=accurate")

    // PASSO 3: Criar VisionImage
    let visionImage = VisionImage(image: image)
    visionImage.orientation = image.imageOrientation

    print("🔍 [iOS Native] DEBUG - VisionImage criado com orientation: \(image.imageOrientation.rawValue)")

    // PASSO 4: Detectar faces
    faceDetector.process(visionImage) { [weak self] faces, error in
      guard let self = self else { return }

      print("🔍 [iOS Native] DEBUG - Callback do detector executado")

      if let error = error {
        print("❌ [iOS Native] DEBUG - Erro no ML Kit: \(error.localizedDescription)")
        SentrySDK.capture(error: error) { scope in
          scope.setLevel(.error)
          scope.setTag(value: "ml_kit_detection_error", key: "error_type")
          scope.setContext(value: [
            "error_message": error.localizedDescription,
            "image_path": imagePath
          ], key: "detection_error")
        }
        result(FlutterError(
          code: "DETECTION_ERROR",
          message: "Erro ao detectar faces: \(error.localizedDescription)",
          details: nil
        ))
        return
      }

      print("🔍 [iOS Native] DEBUG - Faces retornadas: \(faces?.count ?? 0)")

      guard let faces = faces, !faces.isEmpty else {
        print("⚠️ [iOS Native] DEBUG - Nenhuma face detectada (faces array vazio ou nil)")
        SentrySDK.capture(message: "⚠️ [iOS Native] Nenhuma face detectada") { scope in
          scope.setLevel(.warning)
          scope.setTag(value: "no_face", key: "detection_result")
          scope.setContext(value: [
            "image_path": imagePath,
            "image_width": image.size.width,
            "image_height": image.size.height,
            "min_face_size": 0.01
          ], key: "detection_context")
        }
        result(FlutterError(
          code: "NO_FACE_DETECTED",
          message: "Nenhum rosto detectado. Verifique: iluminação, ângulo da câmera e distância.",
          details: nil
        ))
        return
      }

      print("✅ [iOS Native] Detectadas \(faces.count) face(s)")
      SentrySDK.capture(message: "✅ [iOS Native] Detecção facial bem-sucedida") { scope in
        scope.setLevel(.info)
        scope.setContext(value: [
          "faces_count": faces.count,
          "image_path": imagePath
        ], key: "detection_success")
      }

      // PASSO 5: Selecionar face principal (maior área)
      let primaryFace = faces.max { face1, face2 in
        let area1 = face1.frame.width * face1.frame.height
        let area2 = face2.frame.width * face2.frame.height
        return area1 < area2
      }!

      print("📐 [iOS Native] Face principal: \(primaryFace.frame)")

      // PASSO 6: Recortar face
      guard let cgImage = image.cgImage,
            let croppedCGImage = cgImage.cropping(to: primaryFace.frame) else {
        SentrySDK.capture(message: "❌ [iOS Native] Erro ao recortar face") { scope in
          scope.setLevel(.error)
          scope.setTag(value: "crop_error", key: "error_type")
          scope.setContext(value: [
            "face_frame": "\(primaryFace.frame)",
            "image_path": imagePath
          ], key: "crop_error")
        }
        result(FlutterError(
          code: "CROP_ERROR",
          message: "Erro ao recortar face",
          details: nil
        ))
        return
      }

      let croppedImage = UIImage(cgImage: croppedCGImage)

      // PASSO 7: Redimensionar para 112x112
      let finalImage = self.resizeImage(image: croppedImage, targetSize: CGSize(width: 112, height: 112))

      // PASSO 8: Converter para JPEG
      guard let jpegData = finalImage.jpegData(compressionQuality: 0.95) else {
        SentrySDK.capture(message: "❌ [iOS Native] Erro ao converter para JPEG") { scope in
          scope.setLevel(.error)
          scope.setTag(value: "jpeg_conversion_error", key: "error_type")
        }
        result(FlutterError(
          code: "JPEG_ERROR",
          message: "Erro ao converter imagem para JPEG",
          details: nil
        ))
        return
      }

      print("✅ [iOS Native] Face processada: \(jpegData.count) bytes")
      SentrySDK.capture(message: "✅ [iOS Native] Processamento completo") { scope in
        scope.setLevel(.info)
        scope.setContext(value: [
          "jpeg_bytes": jpegData.count,
          "bbox_width": Int(primaryFace.frame.width),
          "bbox_height": Int(primaryFace.frame.height),
          "final_size": "112x112"
        ], key: "processing_complete")
      }

      // PASSO 9: Retornar resultado
      let responseMap: [String: Any] = [
        "croppedFaceBytes": FlutterStandardTypedData(bytes: jpegData),
        "boundingBox": [
          "left": primaryFace.frame.origin.x,
          "top": primaryFace.frame.origin.y,
          "width": primaryFace.frame.width,
          "height": primaryFace.frame.height
        ]
      ]

      result(responseMap)
    }
  }

  /// Redimensiona imagem para tamanho específico
  private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
    let size = image.size

    let widthRatio  = targetSize.width  / size.width
    let heightRatio = targetSize.height / size.height

    let newSize: CGSize
    if widthRatio > heightRatio {
      newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
    } else {
      newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
    }

    let rect = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)

    UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
    image.draw(in: rect)
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return newImage ?? image
  }
}
