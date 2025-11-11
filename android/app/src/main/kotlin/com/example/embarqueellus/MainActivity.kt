package com.example.embarqueellus

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL_NAME = "embarqueellus/native_face_detection"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectAndCropFace" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            handleFaceDetection(path, result)
                        } else {
                            result.error(
                                "INVALID_ARGS",
                                "Argumentos inválidos. Esperado: {'path': String}",
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        println("✅ [Android Native] Platform Channel configurado: $CHANNEL_NAME")
    }

    /// Processa a detecção e recorte facial nativamente
    private fun handleFaceDetection(path: String, result: MethodChannel.Result) {
        try {
            println("📸 [Android Native] Iniciando detecção facial: $path")

            val file = File(path)
            if (!file.exists()) {
                result.error(
                    "FILE_NOT_FOUND",
                    "Arquivo não encontrado: $path",
                    null
                )
                return
            }

            // PASSO 1: Carregar bitmap
            val bitmap = BitmapFactory.decodeFile(file.absolutePath)
            if (bitmap == null) {
                result.error(
                    "IMAGE_LOAD_ERROR",
                    "Não foi possível carregar a imagem: $path",
                    null
                )
                return
            }

            println("✅ [Android Native] Imagem carregada: ${bitmap.width}x${bitmap.height}")

            // PASSO 2: Corrigir rotação EXIF (CRÍTICO para Android)
            val rotatedBitmap = rotateBitmapIfRequired(bitmap, file)
            println("✅ [Android Native] Rotação EXIF aplicada: ${rotatedBitmap.width}x${rotatedBitmap.height}")

            // PASSO 3: Criar InputImage do ML Kit
            val image = InputImage.fromBitmap(rotatedBitmap, 0)

            // PASSO 4: Configurar detector do ML Kit
            val options = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .setContourMode(FaceDetectorOptions.CONTOUR_MODE_NONE)
                .setMinFaceSize(0.05f)
                .build()

            val detector = FaceDetection.getClient(options)

            // PASSO 5: Detectar faces
            detector.process(image)
                .addOnSuccessListener { faces ->
                    if (faces.isEmpty()) {
                        result.error(
                            "NO_FACE_DETECTED",
                            "Nenhum rosto detectado. Verifique: iluminação, ângulo da câmera e distância.",
                            null
                        )
                        return@addOnSuccessListener
                    }

                    println("✅ [Android Native] Detectadas ${faces.size} face(s)")

                    // PASSO 6: Selecionar face principal (maior área)
                    val primaryFace = faces.maxByOrNull { face ->
                        face.boundingBox.width() * face.boundingBox.height()
                    }!!

                    println("📐 [Android Native] Face principal: ${primaryFace.boundingBox}")

                    // PASSO 7: Recortar face (com bounds seguros)
                    val bbox = primaryFace.boundingBox
                    val left = bbox.left.coerceAtLeast(0)
                    val top = bbox.top.coerceAtLeast(0)
                    val width = bbox.width().coerceAtMost(rotatedBitmap.width - left)
                    val height = bbox.height().coerceAtMost(rotatedBitmap.height - top)

                    val croppedBitmap = Bitmap.createBitmap(
                        rotatedBitmap,
                        left,
                        top,
                        width,
                        height
                    )

                    // PASSO 8: Redimensionar para 112x112
                    val finalBitmap = Bitmap.createScaledBitmap(
                        croppedBitmap,
                        112,
                        112,
                        true
                    )

                    // PASSO 9: Converter para JPEG
                    val stream = ByteArrayOutputStream()
                    finalBitmap.compress(Bitmap.CompressFormat.JPEG, 95, stream)
                    val jpegBytes = stream.toByteArray()

                    println("✅ [Android Native] Face processada: ${jpegBytes.size} bytes")

                    // PASSO 10: Retornar resultado
                    val responseMap = hashMapOf<String, Any>(
                        "croppedFaceBytes" to jpegBytes,
                        "boundingBox" to hashMapOf(
                            "left" to bbox.left.toDouble(),
                            "top" to bbox.top.toDouble(),
                            "width" to bbox.width().toDouble(),
                            "height" to bbox.height().toDouble()
                        )
                    )

                    result.success(responseMap)

                    // Liberar recursos
                    bitmap.recycle()
                    rotatedBitmap.recycle()
                    croppedBitmap.recycle()
                    finalBitmap.recycle()
                }
                .addOnFailureListener { e ->
                    result.error(
                        "DETECTION_ERROR",
                        "Erro ao detectar faces: ${e.message}",
                        null
                    )
                }
        } catch (e: Exception) {
            result.error(
                "UNEXPECTED_ERROR",
                "Erro inesperado: ${e.message}",
                null
            )
        }
    }

    /// Corrige rotação do bitmap baseado nos metadados EXIF
    private fun rotateBitmapIfRequired(bitmap: Bitmap, file: File): Bitmap {
        try {
            val exif = ExifInterface(file.absolutePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )

            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                else -> return bitmap // Sem rotação necessária
            }

            return Bitmap.createBitmap(
                bitmap,
                0,
                0,
                bitmap.width,
                bitmap.height,
                matrix,
                true
            )
        } catch (e: Exception) {
            println("⚠️ [Android Native] Erro ao ler EXIF: ${e.message}")
            return bitmap
        }
    }
}
