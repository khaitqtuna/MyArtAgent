import Foundation
import CoreGraphics
import UIKit
import MLX
import StableDiffusion

enum DiffusionModelPreset: String, CaseIterable, Identifiable {
    case illustriousXL = "OnomaAIResearch/Illustrious-xl-early-release-v0"
    case ponyV6XL = "misri/ponyDiffusionV6XL"
    case animagineXL = "cagliostrolab/animagine-xl-3.1"
    case dreamShaperXLTurbo = "Lykon/dreamshaper-xl-v2-turbo"
    case sdxlTurbo = "stabilityai/sdxl-turbo"
    case meinaMixSD15 = "digiplay/MeinaMix_v11"
    case dreamShaperSD15 = "Lykon/dreamshaper-8"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .illustriousXL:
            return "Illustrious-XL (Chuẩn Pixiv / Tensor.Art)"
        case .ponyV6XL:
            return "Pony Diffusion V6 XL (Anime / Concept)"
        case .animagineXL:
            return "Animagine XL 3.1 (Pixiv / Anime)"
        case .dreamShaperXLTurbo:
            return "DreamShaper XL Turbo (Digital Art, 6 steps)"
        case .sdxlTurbo:
            return "SDXL Turbo (Nhanh, 4 steps)"
        case .meinaMixSD15:
            return "MeinaMix v11 (SD 1.5 nhẹ RAM)"
        case .dreamShaperSD15:
            return "DreamShaper 8 (SD 1.5 nhẹ RAM)"
        case .custom:
            return "Tùy chỉnh (Custom Hugging Face ID)"
        }
    }

    var isSDXL: Bool {
        switch self {
        case .meinaMixSD15, .dreamShaperSD15:
            return false
        default:
            return true
        }
    }

    var recommendedSteps: Int {
        switch self {
        case .sdxlTurbo: return 4
        case .dreamShaperXLTurbo: return 6
        case .animagineXL, .illustriousXL, .meinaMixSD15, .dreamShaperSD15, .custom: return 20
        case .ponyV6XL: return 22
        }
    }

    var cfgWeight: Float {
        switch self {
        case .sdxlTurbo: return 0.0
        case .dreamShaperXLTurbo: return 2.0
        case .animagineXL, .illustriousXL, .custom: return 6.0
        case .ponyV6XL: return 6.5
        case .meinaMixSD15, .dreamShaperSD15: return 7.5
        }
    }

    var smartQualityTags: String {
        switch self {
        case .ponyV6XL:
            return "score_9, score_8_up, score_7_up, score_6_up, source_anime"
        case .illustriousXL:
            return "masterpiece, best quality, newest, absurdres"
        case .animagineXL:
            return "masterpiece, best quality, very aesthetic, absurdres"
        case .dreamShaperXLTurbo, .meinaMixSD15, .dreamShaperSD15, .custom:
            return "masterpiece, best quality, highly detailed"
        case .sdxlTurbo:
            return ""
        }
    }

    var qualityTagsAtStart: Bool {
        switch self {
        case .ponyV6XL, .illustriousXL:
            return true
        default:
            return false
        }
    }

    var prefersTagFormat: Bool {
        switch self {
        case .ponyV6XL, .illustriousXL, .animagineXL, .meinaMixSD15:
            return true
        default:
            return false
        }
    }

    var defaultNegativePrompt: String {
        switch self {
        case .sdxlTurbo:
            return ""
        case .ponyV6XL:
            return "score_6, score_5, score_4, lowres, bad anatomy, bad hands, missing fingers, extra fingers, deformed, worst quality, low quality, blurry, watermark, signature, text"
        case .animagineXL, .illustriousXL:
            return "nsfw, lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry"
        case .dreamShaperXLTurbo, .meinaMixSD15, .dreamShaperSD15, .custom:
            return "lowres, bad anatomy, bad hands, extra fingers, missing fingers, deformed, worst quality, low quality, jpeg artifacts, blurry, signature, watermark, text"
        }
    }
}

enum AspectRatio: String, CaseIterable, Identifiable {
    case square = "Vuông (1024×1024)"
    case portrait = "Dọc chân dung (832×1216)"
    case landscape = "Ngang phong cảnh (1216×832)"

    var id: String { rawValue }

    func latentSize(isSDXL: Bool) -> [Int] {
        switch self {
        case .square:
            return isSDXL ? [128, 128] : [64, 64]
        case .portrait:
            return isSDXL ? [152, 104] : [96, 64]
        case .landscape:
            return isSDXL ? [104, 152] : [64, 96]
        }
    }
}

enum GenerationMode: String, CaseIterable, Identifiable {
    case sequenceGrowth = "Chuỗi tiến triển (Sequence Growth)"
    case variations = "Biến thể cùng prompt"

    var id: String { rawValue }
}

struct GeneratedArtItem: Identifiable {
    let id = UUID()
    let index: Int
    let image: UIImage
    let prompt: String
    let seed: UInt64
}

@MainActor
final class ArtEngine: ObservableObject {
    @Published var statusMessage: String = "Sẵn sàng nhận ý tưởng vẽ tranh."
    @Published var expandedPrompt: String = ""
    @Published var downloadProgress: Double = 0
    @Published var isGenerating: Bool = false
    @Published var generatedImage: UIImage?
    @Published var generatedItems: [GeneratedArtItem] = []

    func generateImages(
        idea: String,
        preset: DiffusionModelPreset,
        customRepoId: String,
        aspectRatio: AspectRatio,
        style: ArtStyle,
        steps: Int,
        imageCount: Int,
        generationMode: GenerationMode,
        lockSequenceSeed: Bool,
        negativePrompt: String,
        useLLM: Bool,
        primaryLLM: LLMModelPreset,
        refinerLLM: LLMModelPreset,
        llmPipelineMode: LLMPipelineMode
    ) {
        let trimmed = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        let targetCount = min(max(1, imageCount), 8)
        let customId = customRepoId.trimmingCharacters(in: .whitespacesAndNewlines)
        if preset == .custom && customId.isEmpty {
            statusMessage = "Lỗi: Vui lòng nhập Custom Hugging Face Repo ID."
            return
        }

        isGenerating = true
        downloadProgress = 0
        expandedPrompt = ""
        generatedItems = []
        generatedImage = nil
        UIApplication.shared.isIdleTimerDisabled = true
        statusMessage = useLLM
            ? "Đang khởi động mô hình LLM..."
            : "Đang kiểm tra model vẽ tranh..."

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let isSequence = targetCount > 1 && generationMode == .sequenceGrowth
                let resolvedPrompts: [String]

                if useLLM {
                    resolvedPrompts = try await PromptAgent.generatePrompts(
                        userIdea: trimmed,
                        styleName: style.rawValue,
                        styleSuffix: style.promptSuffix,
                        qualityTags: preset.smartQualityTags,
                        tagsAtStart: preset.qualityTagsAtStart,
                        tagFormatted: preset.prefersTagFormat,
                        count: targetCount,
                        sequenceGrowth: isSequence,
                        primaryModel: primaryLLM,
                        refinerModel: refinerLLM,
                        pipelineMode: llmPipelineMode
                    ) { status in
                        Task { @MainActor [weak self] in
                            self?.statusMessage = status
                        }
                    }

                    let previewText: String
                    if resolvedPrompts.count > 1 && isSequence {
                        previewText = resolvedPrompts.enumerated()
                            .map { "[\($0.offset + 1)/\(resolvedPrompts.count)] \($0.element)" }
                            .joined(separator: "\n\n")
                    } else {
                        previewText = resolvedPrompts.first ?? ""
                    }

                    await MainActor.run {
                        self.expandedPrompt = previewText
                        self.downloadProgress = 0
                        self.statusMessage = "Đã chuẩn bị xong prompt! Đang chuyển sang GPU vẽ tranh..."
                    }
                } else {
                    resolvedPrompts = PromptAgent.buildDirectPrompts(
                        userIdea: trimmed,
                        styleSuffix: style.promptSuffix,
                        qualityTags: preset.smartQualityTags,
                        tagsAtStart: preset.qualityTagsAtStart,
                        count: targetCount,
                        sequenceGrowth: isSequence
                    )
                    if isSequence {
                        let previewText = resolvedPrompts.enumerated()
                            .map { "[\($0.offset + 1)/\(resolvedPrompts.count)] \($0.element)" }
                            .joined(separator: "\n\n")
                        await MainActor.run {
                            self.expandedPrompt = previewText
                        }
                    }
                }

                try await self.runPipeline(
                    prompts: resolvedPrompts,
                    preset: preset,
                    customRepoId: customId,
                    aspectRatio: aspectRatio,
                    steps: steps,
                    negativePrompt: negativePrompt,
                    lockSequenceSeed: isSequence && lockSequenceSeed
                )

                await MainActor.run {
                    self.statusMessage = targetCount > 1
                        ? "Đã vẽ xong chuỗi \(targetCount) ảnh!"
                        : "Đã vẽ xong!"
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

    private nonisolated func resolveConfiguration(
        preset: DiffusionModelPreset,
        customRepoId: String,
        steps: Int
    ) async throws -> (config: StableDiffusionConfiguration, isSDXL: Bool) {
        switch preset {
        case .sdxlTurbo:
            return (StableDiffusionConfiguration.sdxl(
                id: preset.rawValue,
                useFP16Suffix: true,
                cfgWeight: preset.cfgWeight,
                steps: steps
            ), true)
        case .dreamShaperXLTurbo, .ponyV6XL:
            return (StableDiffusionConfiguration.sdxl(
                id: preset.rawValue,
                useFP16Suffix: true,
                cfgWeight: preset.cfgWeight,
                steps: steps
            ), true)
        case .animagineXL, .illustriousXL:
            return (StableDiffusionConfiguration.sdxl(
                id: preset.rawValue,
                useFP16Suffix: false,
                cfgWeight: preset.cfgWeight,
                steps: steps
            ), true)
        case .meinaMixSD15, .dreamShaperSD15:
            return (StableDiffusionConfiguration.sd15FP16(
                id: preset.rawValue,
                cfgWeight: preset.cfgWeight,
                steps: steps
            ), false)
        case .custom:
            let metadata = await inspectCustomRepo(repoId: customRepoId)
            if metadata.isSDXL {
                return (StableDiffusionConfiguration.sdxl(
                    id: customRepoId,
                    useFP16Suffix: metadata.useFP16Suffix,
                    cfgWeight: preset.cfgWeight,
                    steps: steps
                ), true)
            } else {
                return (StableDiffusionConfiguration.sd15FP16(
                    id: customRepoId,
                    useFP16Suffix: metadata.useFP16Suffix,
                    cfgWeight: 7.5,
                    steps: steps
                ), false)
            }
        }
    }

    private nonisolated func inspectCustomRepo(repoId: String) async -> (isSDXL: Bool, useFP16Suffix: Bool) {
        guard let encoded = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/api/models/\(encoded)") else {
            return (true, false)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let siblings = json["siblings"] as? [[String: Any]] {
                let filenames = Set(siblings.compactMap { $0["rfilename"] as? String })
                let isSDXL = filenames.contains("text_encoder_2/config.json")
                let hasFP16 = filenames.contains("unet/diffusion_pytorch_model.fp16.safetensors")
                return (isSDXL, hasFP16)
            }
        } catch {
            // Fallback an toàn về SDXL chuẩn (.safetensors) nếu không tra cứu được API
        }
        return (true, false)
    }

    private nonisolated func runPipeline(
        prompts: [String],
        preset: DiffusionModelPreset,
        customRepoId: String,
        aspectRatio: AspectRatio,
        steps: Int,
        negativePrompt: String,
        lockSequenceSeed: Bool
    ) async throws {
        // Ép giới hạn cache GPU xuống 20 MB để tránh bị iPadOS Jetsam kill app
        Memory.cacheLimit = 20 * 1024 * 1024
        Memory.clearCache()
        defer { Memory.clearCache() }

        let resolved = try await resolveConfiguration(
            preset: preset,
            customRepoId: customRepoId,
            steps: steps
        )
        let config = resolved.config
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

        var generator = try config.textToImageGenerator(configuration: loadConfig)
        guard generator != nil else {
            throw NSError(
                domain: "ArtEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Không thể nạp model vẽ vào bộ nhớ."]
            )
        }

        // Không gọi ensureLoaded() để tránh nạp cùng lúc toàn bộ mạng nơ-ron vào RAM
        let baseSeed = UInt64.random(in: 0 ..< UInt64.max)
        let totalImages = prompts.count
        var pendingLatents: [(index: Int, prompt: String, seed: UInt64, latent: MLXArray)] = []
        let targetLatentSize = aspectRatio.latentSize(isSDXL: resolved.isSDXL)

        for (idx, promptText) in prompts.enumerated() {
            let imageIndex = idx + 1
            let frameSeed = lockSequenceSeed ? baseSeed : (baseSeed &+ UInt64(idx))

            var params = config.defaultParameters()
            params.prompt = promptText
            params.negativePrompt = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            params.steps = steps
            params.latentSize = targetLatentSize
            params.seed = frameSeed

            await MainActor.run {
                self.statusMessage = totalImages > 1
                    ? "Ảnh \(imageIndex)/\(totalImages) — bước 1/\(steps)..."
                    : "Đang vẽ bước 1/\(steps)..."
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
                    self?.statusMessage = totalImages > 1
                        ? "Ảnh \(imageIndex)/\(totalImages) — bước \(stepCopy)/\(steps)..."
                        : "Đang vẽ bước \(stepCopy)/\(steps)..."
                }
            }

            latents = nil
            Memory.clearCache()

            guard let finalXt = current else {
                throw NSError(
                    domain: "ArtEngine",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Không tạo được dữ liệu ảnh đầu ra ở ảnh \(imageIndex)."]
                )
            }
            pendingLatents.append((index: imageIndex, prompt: promptText, seed: frameSeed, latent: finalXt))
        }

        let decoder = generator!.detachedDecoder()
        // Giải phóng hoàn toàn UNet và TextEncoder trước khi giải mã ảnh để tối ưu RAM
        generator = nil
        Memory.clearCache()

        for entry in pendingLatents {
            await MainActor.run {
                self.statusMessage = totalImages > 1
                    ? "Đang giải mã chi tiết ảnh \(entry.index)/\(totalImages)..."
                    : "Đang hoàn thiện chi tiết ảnh..."
            }

            let decoded = decoder(entry.latent)
            eval(decoded)
            let cgImage = try makeCGImage(from: decoded)
            Memory.clearCache()

            let uiImage = UIImage(cgImage: cgImage)
            let item = GeneratedArtItem(
                index: entry.index,
                image: uiImage,
                prompt: entry.prompt,
                seed: entry.seed
            )
            await MainActor.run {
                self.generatedItems.append(item)
                self.generatedImage = uiImage
            }
        }
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
            return ", anime illustration, vibrant colors, clean lineart, pixiv style"
        case .digitalArt:
            return ", digital painting, concept art, dramatic lighting, deviantart style"
        case .oilPainting:
            return ", classic oil painting on canvas, rich brushstrokes, dramatic lighting, fine art"
        case .watercolor:
            return ", delicate watercolor painting, soft pigment washes, textured cold press paper"
        case .inkWash:
            return ", traditional east asian sumi-e ink wash painting, expressive brush strokes, rice paper"
        case .realistic:
            return ", photorealistic, raw photo, natural lighting, sharp focus, 8k uhd"
        case .raw:
            return ""
        }
    }
}
