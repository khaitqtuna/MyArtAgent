import Foundation
import CoreGraphics
import UIKit
import MLX
import StableDiffusion

enum ImageModel: String, CaseIterable, Identifiable {
    case meinaMix = "digiplay/MeinaMix_v11"
    case dreamShaper = "Lykon/dreamshaper-8"
    case majicMix = "digiplay/majicMIX_realistic_v7"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meinaMix:
            return "MeinaMix v11 (Pixiv / Anime)"
        case .dreamShaper:
            return "DreamShaper 8 (DeviantArt / Minh họa)"
        case .majicMix:
            return "majicMIX v7 (Ảnh tả thực)"
        }
    }

    var configuration: StableDiffusionConfiguration {
        StableDiffusionConfiguration.sd15FP16(id: rawValue, cfgWeight: 7.5, steps: 20)
    }

    var defaultNegativePrompt: String {
        switch self {
        case .meinaMix:
            return "lowres, bad anatomy, bad hands, extra fingers, missing fingers, deformed, blurry, jpeg artifacts, worst quality, low quality, signature, watermark, text"
        case .dreamShaper:
            return "lowres, bad anatomy, bad hands, extra fingers, deformed, blurry, ugly, jpeg artifacts, worst quality, low quality, signature, watermark, text"
        case .majicMix:
            return "lowres, bad anatomy, bad hands, extra fingers, deformed, plastic skin, cgi, 3d render, blurry, worst quality, low quality, watermark, text"
        }
    }
}

enum ArtStyle: String, CaseIterable, Identifiable {
    case anime = "Anime / Minh họa 2D (Pixiv)"
    case digitalArt = "Digital Art / Fantasy (DeviantArt)"
    case oilPainting = "Sơn dầu cổ điển"
    case watercolor = "Màu nước"
    case inkWash = "Tranh thủy mặc"
    case realistic = "Ảnh tả thực"
    case raw = "Tự do (Không áp style)"

    var id: String { rawValue }

    var promptSuffix: String {
        switch self {
        case .anime:
            return ", masterpiece, best quality, highly detailed anime illustration, vibrant lighting, crisp lineart, pixiv style"
        case .digitalArt:
            return ", masterpiece, best quality, highly detailed digital painting, concept art, dramatic lighting, deviantart style"
        case .oilPainting:
            return ", masterpiece, classic oil painting on canvas, rich brushstrokes, dramatic lighting, fine art"
        case .watercolor:
            return ", masterpiece, delicate watercolor painting, soft pigment washes, textured cold press paper"
        case .inkWash:
            return ", masterpiece, traditional east asian sumi-e ink wash painting, expressive brush strokes, rice paper"
        case .realistic:
            return ", photorealistic, raw photo, natural lighting, sharp focus, 8k uhd, highly detailed"
        case .raw:
            return ""
        }
    }
}

@MainActor
final class ArtEngine: ObservableObject {
    @Published var statusMessage: String = "Sẵn sàng nhận ý tưởng vẽ tranh."
    @Published var expandedPrompt: String = ""
    @Published var downloadProgress: Double = 0
    @Published var isGenerating: Bool = false
    @Published var generatedImage: UIImage?

    func generateImage(
        idea: String,
        imageModel: ImageModel,
        style: ArtStyle,
        steps: Int,
        useLLM: Bool,
        llmModelId: String
    ) {
        let trimmed = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        isGenerating = true
        downloadProgress = 0
        expandedPrompt = ""
        UIApplication.shared.isIdleTimerDisabled = true
        statusMessage = useLLM
            ? "Đang khởi động mô hình LLM..."
            : "Đang kiểm tra model vẽ tranh..."

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let basePrompt: String
                if useLLM {
                    basePrompt = try await PromptAgent.expandPrompt(
                        userIdea: trimmed,
                        styleName: style.rawValue,
                        modelId: llmModelId
                    ) { status in
                        Task { @MainActor [weak self] in
                            self?.statusMessage = status
                        }
                    }

                    await MainActor.run {
                        self.expandedPrompt = basePrompt
                        self.downloadProgress = 0
                        self.statusMessage = "Đã tạo xong prompt! Đang chuyển sang GPU vẽ tranh..."
                    }
                } else {
                    basePrompt = trimmed
                }

                let fullPrompt = basePrompt + style.promptSuffix
                let cgImage = try await self.runPipeline(
                    fullPrompt: fullPrompt,
                    imageModel: imageModel,
                    steps: steps
                )
                let uiImage = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.generatedImage = uiImage
                    self.statusMessage = "Đã vẽ xong!"
                    self.isGenerating = false
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.statusMessage = "Lỗi: \(message)"
                    self.isGenerating = false
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
        }
    }

    private nonisolated func runPipeline(
        fullPrompt: String,
        imageModel: ImageModel,
        steps: Int
    ) async throws -> CGImage {
        // Ép giới hạn cache GPU xuống 20 MB để tránh bị iPadOS Jetsam kill app
        Memory.cacheLimit = 20 * 1024 * 1024
        Memory.clearCache()
        defer { Memory.clearCache() }

        let config = imageModel.configuration
        let loadConfig = LoadConfiguration(float16: true, quantize: true)

        try await config.download { progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor [weak self] in
                self?.downloadProgress = fraction
                let percent = Int(fraction * 100)
                if percent < 100 {
                    self?.statusMessage = "Đang tải model vẽ về iPad: \(percent)%"
                }
            }
        }

        await MainActor.run {
            self.statusMessage = "Đang nạp model ở chế độ tiết kiệm RAM..."
        }

        var params = config.defaultParameters()
        params.prompt = fullPrompt
        params.negativePrompt = imageModel.defaultNegativePrompt
        params.steps = steps
        params.seed = UInt64.random(in: 0 ..< UInt64.max)

        var generator = try config.textToImageGenerator(configuration: loadConfig)
        guard generator != nil else {
            throw NSError(
                domain: "ArtEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Không thể nạp model vẽ vào bộ nhớ."]
            )
        }

        // Không gọi ensureLoaded() để tránh nạp cùng lúc toàn bộ mạng nơ-ron vào RAM
        await MainActor.run {
            self.statusMessage = "Đang vẽ bước 1/\(steps)..."
        }

        var latents = Optional(generator!.generateLatents(parameters: params))
        var current = latents?.next() ?? nil
        if let first = current {
            eval(first)
            Memory.clearCache()
        }
        var currentStep = 1

        while let next = (latents?.next() ?? nil) {
            eval(next)
            Memory.clearCache()
            current = next
            currentStep += 1
            let stepCopy = currentStep
            Task { @MainActor [weak self] in
                self?.statusMessage = "Đang vẽ bước \(stepCopy)/\(steps)..."
            }
        }

        let decoder = generator!.detachedDecoder()
        // Giải phóng hoàn toàn UNet và TextEncoder trước khi giải mã ảnh
        latents = nil
        generator = nil
        Memory.clearCache()

        guard let finalXt = current else {
            throw NSError(
                domain: "ArtEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Không tạo được dữ liệu ảnh đầu ra."]
            )
        }

        await MainActor.run {
            self.statusMessage = "Đang hoàn thiện chi tiết ảnh..."
        }

        let decoded = decoder(finalXt)
        eval(decoded)
        let cgImage = try makeCGImage(from: decoded)
        Memory.clearCache()
        return cgImage
    }

    private nonisolated func makeCGImage(from array: MLXArray) throws -> CGImage {
        let imageArray = array.ndim == 4 ? array[0] : array
        guard imageArray.ndim == 3 else {
            throw NSError(
                domain: "ArtEngine",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Định dạng dữ liệu ảnh không hợp lệ: \(imageArray.shape)"]
            )
        }

        let height = imageArray.shape[0]
        let width = imageArray.shape[1]
        let channels = imageArray.shape[2]

        let floats = imageArray.asType(.float32).asArray(Float.self)
        let maxValue = floats.lazy.filter(\.isFinite).max() ?? 1.0
        let scale: Float = maxValue <= 1.5 ? 255.0 : 1.0

        func toByte(_ value: Float) -> UInt8 {
            guard value.isFinite else { return 0 }
            return UInt8(min(max(value * scale, 0), 255))
        }

        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0 ..< (width * height) {
            let src = i * channels
            let dst = i * 4
            if channels >= 3 {
                rgba[dst] = toByte(floats[src])
                rgba[dst + 1] = toByte(floats[src + 1])
                rgba[dst + 2] = toByte(floats[src + 2])
            } else {
                let gray = toByte(floats[src])
                rgba[dst] = gray
                rgba[dst + 1] = gray
                rgba[dst + 2] = gray
            }
        }

        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else {
            throw NSError(
                domain: "ArtEngine",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Không thể dựng ảnh CGImage từ dữ liệu AI."]
            )
        }

        return cgImage
    }
}
