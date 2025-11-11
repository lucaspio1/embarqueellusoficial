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
    print("🔍 [iOS Native] DEBUG - Orientation ANTES de bake: \(image.imageOrientation.rawValue)")
    print("🔍 [iOS Native] DEBUG - Scale: \(image.scale)")

    SentrySDK.capture(message: "✅ [iOS Native] Imagem carregada (lazy, ainda não aplicada)") { scope in
      scope.setLevel(.info)
      scope.setContext(value: [
        "width_lazy": image.size.width,
        "height_lazy": image.size.height,
        "orientation_lazy": image.imageOrientation.rawValue,
        "scale": image.scale
      ], key: "image_loaded_lazy")
    }

    // PASSO 2: "ASSAR" (BAKE) A ORIENTAÇÃO NOS PIXELS
    // Crucial: UIImage é "preguiçoso" - a rotação EXIF não é aplicada fisicamente nos pixels
    // Precisamos forçar a aplicação desenhando em um novo contexto gráfico
    print("🔥 [iOS Native] DEBUG - Assando orientação nos pixels...")

    guard let bakedImage = bakeOrientation(image: image) else {
      SentrySDK.capture(message: "❌ [iOS Native] Erro ao assar orientação") { scope in
        scope.setLevel(.error)
        scope.setTag(value: "bake_orientation_error", key: "error_type")
      }
      result(FlutterError(
        code: "BAKE_ERROR",
        message: "Erro ao processar orientação da imagem",
        details: nil
      ))
      return
    }

    print("✅ [iOS Native] Orientação assada: \(bakedImage.size.width)x\(bakedImage.size.height)")
    print("🔍 [iOS Native] DEBUG - Orientation DEPOIS de bake: \(bakedImage.imageOrientation.rawValue) (deve ser 0=Up)")

    SentrySDK.capture(message: "✅ [iOS Native] Orientação assada nos pixels") { scope in
      scope.setLevel(.info)
      scope.setContext(value: [
        "width_baked": bakedImage.size.width,
        "height_baked": bakedImage.size.height,
        "orientation_baked": bakedImage.imageOrientation.rawValue,
        "orientation_fixed": bakedImage.imageOrientation == .up
      ], key: "image_baked")
    }

    // PASSO 3: Criar VisionImage com imagem ASSADA
    let visionImage = VisionImage(image: bakedImage)
    visionImage.orientation = bakedImage.imageOrientation  // Deve ser .up (0)

    print("🔍 [iOS Native] DEBUG - VisionImage criado com imagem assada (orientation: \(bakedImage.imageOrientation.rawValue))")

    // PASSO 4: Detectar faces (com múltiplas tentativas)
    print("🔍 [iOS Native] DEBUG - Iniciando detecção (Tentativa 1/3)")

    detectFacesWithRetry(
      image: bakedImage,  // ✅ USANDO IMAGEM ASSADA
      visionImage: visionImage,
      imagePath: imagePath,
      result: result
    )
  }

  /// "Assa" (bake) a orientação EXIF nos pixels da imagem
  /// Resolve o bug do UIImage "preguiçoso" que não aplica a rotação fisicamente
  private func bakeOrientation(image: UIImage) -> UIImage? {
    // Se já está orientada corretamente, retornar como está
    if image.imageOrientation == .up {
      return image
    }

    // Criar um contexto gráfico com o tamanho correto
    // Importante: usar o tamanho da imagem (que já considera a orientação)
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)

    // Desenhar a imagem no contexto
    // Isso força o iOS a aplicar fisicamente a transformação de rotação
    image.draw(in: CGRect(origin: .zero, size: image.size))

    // Obter a nova imagem com pixels "assados"
    let bakedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    // A nova imagem terá orientation = .up porque os pixels já estão corretos
    return bakedImage
  }

  /// Detecta faces com múltiplas tentativas e configurações diferentes
  private func detectFacesWithRetry(
    image: UIImage,
    visionImage: VisionImage,
    imagePath: String,
    result: @escaping FlutterResult,
    attempt: Int = 1
  ) {
    // Configurar detector baseado na tentativa
    let options = FaceDetectorOptions()
    options.performanceMode = .accurate
    options.landmarkMode = .all
    options.classificationMode = .none
    options.contourMode = .none

    // Ajustar minFaceSize por tentativa
    switch attempt {
    case 1:
      options.minFaceSize = 0.01  // Muito sensível
    case 2:
      options.minFaceSize = 0.05  // Padrão
    case 3:
      options.minFaceSize = 0.1   // Menos sensível mas mais robusto
    default:
      options.minFaceSize = 0.01
    }

    let faceDetector = FaceDetector.faceDetector(options: options)

    print("🔍 [iOS Native] DEBUG - Tentativa \(attempt): minFaceSize=\(options.minFaceSize)")

    faceDetector.process(visionImage) { [weak self] faces, error in
      guard let self = self else { return }

      print("🔍 [iOS Native] DEBUG - Callback tentativa \(attempt) executado")

      if let error = error {
        print("❌ [iOS Native] DEBUG - Erro no ML Kit (tentativa \(attempt)): \(error.localizedDescription)")

        // Se erro na tentativa 1 ou 2, tentar novamente
        if attempt < 3 {
          print("🔄 [iOS Native] DEBUG - Tentando novamente...")
          self.detectFacesWithRetry(
            image: image,
            visionImage: visionImage,
            imagePath: imagePath,
            result: result,
            attempt: attempt + 1
          )
          return
        }

        // Erro na última tentativa
        SentrySDK.capture(error: error) { scope in
          scope.setLevel(.error)
          scope.setTag(value: "ml_kit_detection_error", key: "error_type")
          scope.setContext(value: [
            "error_message": error.localizedDescription,
            "image_path": imagePath,
            "attempts": attempt
          ], key: "detection_error")
        }
        result(FlutterError(
          code: "DETECTION_ERROR",
          message: "Erro ao detectar faces após \(attempt) tentativas: \(error.localizedDescription)",
          details: nil
        ))
        return
      }

      print("🔍 [iOS Native] DEBUG - Faces retornadas (tentativa \(attempt)): \(faces?.count ?? 0)")

      // Se não encontrou faces, tentar novamente
      if faces?.isEmpty ?? true {
        if attempt < 3 {
          print("⚠️ [iOS Native] DEBUG - Nenhuma face na tentativa \(attempt), tentando novamente...")
          self.detectFacesWithRetry(
            image: image,
            visionImage: visionImage,
            imagePath: imagePath,
            result: result,
            attempt: attempt + 1
          )
          return
        }

        // Nenhuma face encontrada após todas as tentativas
        print("⚠️ [iOS Native] DEBUG - Nenhuma face detectada após \(attempt) tentativas")
        SentrySDK.capture(message: "⚠️ [iOS Native] Nenhuma face detectada após múltiplas tentativas") { scope in
          scope.setLevel(.warning)
          scope.setTag(value: "no_face", key: "detection_result")
          scope.setContext(value: [
            "image_path": imagePath,
            "image_width": image.size.width,
            "image_height": image.size.height,
            "attempts": attempt,
            "min_face_sizes_tried": "0.01, 0.05, 0.1"
          ], key: "detection_context")
        }
        result(FlutterError(
          code: "NO_FACE_DETECTED",
          message: "Nenhum rosto detectado após \(attempt) tentativas. Verifique: iluminação, ângulo da câmera e distância.",
          details: nil
        ))
        return
      }

      guard let faces = faces else { return }

      print("✅ [iOS Native] Detectadas \(faces.count) face(s) na tentativa \(attempt)")
      SentrySDK.capture(message: "✅ [iOS Native] Detecção facial bem-sucedida") { scope in
        scope.setLevel(.info)
        scope.setContext(value: [
          "faces_count": faces.count,
          "image_path": imagePath,
          "attempt": attempt,
          "min_face_size_used": options.minFaceSize
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
