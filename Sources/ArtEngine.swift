import Foundation
import CoreGraphics
import UIKit
import MLX
import StableDiffusion

enum DiffusionModelPreset: String, CaseIterable, Identifiable {
    case meinaMixSD15 = "digiplay/MeinaMix_v11"
    case dreamShaperSD15 = "Lykon/dreamshaper-8"
    case majicMixSD15 = "digiplay/majicMIX_realistic_v7"
    case dreamShaperXLTurbo = "Lykon/dreamshaper-xl-v2-turbo"
    case sdxlTurbo = "stabilityai/sdxl-turbo"
    case illustriousXL = "OnomaAIResearch/Illustrious-xl-early-release-v0"
    case ponyV6XL = "misri/ponyDiffusionV6XL"
    case animagineXL = "cagliostrolab/animagine-xl-3.1"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meinaMixSD15:
            return "MeinaMix v11 (Pixiv / Anime • Nhẹ RAM nhất)"
        case .dreamShaperSD15:
            return "DreamShaper 8 (DeviantArt / Fantasy • Nhẹ RAM)"
        case .majicMixSD15:
            return "majicMIX v7 (Ảnh tả thực • Nhẹ RAM)"
        case .dreamShaperXLTurbo:
            return "DreamShaper XL Turbo (SDXL 6 steps)"
        case .sdxlTurbo:
            return "SDXL Turbo (SDXL nhanh 4 steps)"
        case .illustriousXL:
            return "Illustrious-XL (SDXL Pixiv / Tensor.Art)"
        case .ponyV6XL:
            return "Pony Diffusion V6 XL (SDXL Anime / Concept)"
        case .animagineXL:
            return "Animagine XL 3.1 (SDXL Pixiv / Anime)"
        case .custom:
            return "Tùy chỉnh (Custom Hugging Face ID)"
        }
    }

    var isSDXL: Bool {
        switch self {
        case .meinaMixSD15, .dreamShaperSD15, .majicMixSD15:
            return false
        default:
            return true
        }
    }

    var recommendedSteps: Int {
        switch self {
        case .sdxlTurbo: return 4
        case .dreamShaperXLTurbo: return 6
        case .meinaMixSD15, .dreamShaperSD15, .majicMixSD15, .animagineXL, .illustriousXL, .custom: return 20
        case .ponyV6XL: return 22
        }
    }

    var cfgWeight: Float {
        switch self {
        case .sdxlTurbo: return 0.0
        case .dreamShaperXLTurbo: return 2.0
        case .animagineXL, .illustriousXL, .custom: return 6.0
        case .ponyV6XL: return 6.5
        case .meinaMixSD15, .dreamShaperSD15, .majicMixSD15: return 7.5
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
        case .dreamShaperXLTurbo, .meinaMixSD15, .dreamShaperSD15, .majicMixSD15, .custom:
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
        case .majicMixSD15:
            return "lowres, bad anatomy, bad hands, extra fingers, deformed, plastic skin, cgi, 3d render, blurry, worst quality, low quality, watermark, text"
        case .dreamShaperXLTurbo, .meinaMixSD15, .dreamShaperSD15, .custom:
            return "lowres, bad anatomy, bad hands, extra fingers, missing fingers, deformed, worst quality, low quality, jpeg artifacts, blurry, signature, watermark, text"
        }
    }
}

enum AspectRatio: String, CaseIterable, Identifiable {
    case square = "Vuông (1:1 • 768px SDXL / 512px SD1.5)"
    case portrait = "Dọc chân dung (2:3 • 640×896 / 512×768)"
    case landscape = "Ngang phong cảnh (3:2 • 896×640 / 768×512)"

    var id: String { rawValue }

    func latentSize(isSDXL: Bool) -> [Int] {
        if !isSDXL {
            switch self {
            case .square: return [64, 64]       // 512x512
            case .portrait: return [96, 64]     // 512x768
            case .landscape: return [64, 96]    // 768x512
            }
        }
        switch self {
        case .square: return [96, 96]           // 768x768
        case .portrait: return [112, 80]        // 640x896
        case .landscape: return [80, 112]       // 896x640
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
                        self.statusMessage = "Đã chuẩn bị xong prompt! Đang dọn RAM trước khi vẽ..."
                    }
                    // Nhường 1 nhịp ngắn để ARC/Metal thu hồi bộ nhớ của LLM trước khi nạp Diffusion
                    try? await Task.sleep(for: .milliseconds(300))
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
    ) async throws -> (config: StableDiffusionConfiguration, isSDXL: Bool, cfgWeight: Float) {
        switch preset {
        case .sdxlTurbo, .dreamShaperXLTurbo, .ponyV6XL:
            return (StableDiffusionConfiguration.sdxl(
                id: preset.rawValue,
                useFP16Suffix: true,
                cfgWeight: preset.cfgWeight,
                steps: steps
            ), true, preset.cfgWeight)
        case .animagineXL, .illustriousXL:
            return (StableDiffusionConfiguration.sdxl(
                id: preset.rawValue,
                useFP16Suffix: false,
                cfgWeight: preset.cfgWeight,
                steps: steps
            ), true, preset.cfgWeight)
        case .meinaMixSD15, .dreamShaperSD15, .majicMixSD15:
            return (StableDiffusionConfiguration.sd15FP16(
                id: preset.rawValue,
                useFP16Suffix: true,
                cfgWeight: preset.cfgWeight,
                steps: steps
            ), false, preset.cfgWeight)
        case .custom:
            let metadata = await inspectCustomRepo(repoId: customRepoId)
            if metadata.isSDXL {
                return (StableDiffusionConfiguration.sdxl(
                    id: customRepoId,
                    useFP16Suffix: metadata.useFP16Suffix,
                    cfgWeight: preset.cfgWeight,
                    steps: steps
                ), true, preset.cfgWeight)
            } else {
                return (StableDiffusionConfiguration.sd15FP16(
                    id: customRepoId,
                    useFP16Suffix: metadata.useFP16Suffix,
                    cfgWeight: 7.5,
                    steps: steps
                ), false, 7.5)
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
        // Luôn ép giới hạn cache GPU xuống 20 MB và giới hạn tổng bộ nhớ ~3.2 GB để bảo vệ RAM iPadOS
        Memory.cacheLimit = 20 * 1024 * 1024
        Memory.memoryLimit = 3_200 * 1024 * 1024
        Memory.clearCache()
        defer { Memory.clearCache() }

        let resolved = try await resolveConfiguration(
            preset: preset,
            customRepoId: customRepoId,
            steps: steps
        )
        let config = resolved.config

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

        let baseSeed = UInt64.random(in: 0 ..< UInt64.max)
        let cleanedNegative = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = prompts.enumerated().map { idx, promptText in
            SequencePromptItem(
                prompt: promptText,
                negativePrompt: cleanedNegative,
                seed: lockSequenceSeed ? baseSeed : (baseSeed &+ UInt64(idx))
            )
        }

        let targetLatentSize = aspectRatio.latentSize(isSDXL: resolved.isSDXL)
        let unetBits = resolved.isSDXL ? 4 : 8

        try config.runLowMemorySequence(
            items: items,
            isSDXL: resolved.isSDXL,
            steps: steps,
            cfgWeight: resolved.cfgWeight,
            latentSize: targetLatentSize,
            unetBits: unetBits,
            onProgress: { status in
                Task { @MainActor [weak self] in
                    self?.statusMessage = status
                }
            },
            onDecodedRGBA: { index, rgbaData, width, height in
                let cgImage = try ArtEngine.makeCGImage(fromRGBA: rgbaData, width: width, height: height)
                let uiImage = UIImage(cgImage: cgImage)
                let promptText = items[index].prompt
                let seedValue = items[index].seed
                Task { @MainActor [weak self] in
                    let artItem = GeneratedArtItem(
                        index: index + 1,
                        image: uiImage,
                        prompt: promptText,
                        seed: seedValue
                    )
                    self?.generatedItems.append(artItem)
                    self?.generatedImage = uiImage
                }
            }
        )
    }

    private nonisolated static func makeCGImage(fromRGBA data: Data, width: Int, height: Int) throws -> CGImage {
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
