import Foundation
import CoreGraphics
import UIKit
import StableDiffusion

enum ArtStyle: String, CaseIterable, Identifiable {
    case anime = "Anime / Minh họa 2D"
    case oilPainting = "Sơn dầu cổ điển"
    case watercolor = "Màu nước"
    case inkWash = "Tranh thủy mặc"
    case realistic = "Ảnh tả thực"
    case raw = "Tự do (Không áp style)"

    var id: String { rawValue }

    var promptSuffix: String {
        switch self {
        case .anime:
            return ", anime illustration, vibrant colors, clean detailed lineart, studio art"
        case .oilPainting:
            return ", classic oil painting on canvas, rich brushstrokes, dramatic lighting, fine art"
        case .watercolor:
            return ", delicate watercolor painting, soft pigment washes, textured cold press paper"
        case .inkWash:
            return ", traditional east asian sumi-e ink wash painting, expressive brush strokes, rice paper"
        case .realistic:
            return ", photorealistic photography, natural lighting, sharp focus, highly detailed"
        case .raw:
            return ""
        }
    }
}

@MainActor
final class ArtEngine: ObservableObject {
    @Published var statusMessage: String = "Sẵn sàng nhận mô tả tranh."
    @Published var downloadProgress: Double = 0
    @Published var isGenerating: Bool = false
    @Published var generatedImage: UIImage?

    func generateImage(prompt: String, style: ArtStyle, steps: Int) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        isGenerating = true
        downloadProgress = 0
        statusMessage = "Đang kiểm tra / tải model AI (lần đầu cần Wi-Fi)..."

        let fullPrompt = trimmed + style.promptSuffix

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let cgImage = try await self.runPipeline(fullPrompt: fullPrompt, steps: steps)
                let uiImage = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.generatedImage = uiImage
                    self.statusMessage = "Đã vẽ xong!"
                    self.isGenerating = false
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.statusMessage = "Lỗi: \(message)"
                    self.isGenerating = false
                }
            }
        }
    }

    private nonisolated func runPipeline(fullPrompt: String, steps: Int) async throws -> CGImage {
        let config = StableDiffusionConfiguration.presetSDXLTurbo
        let loadConfig = LoadConfiguration(float16: true, quantize: true)

        try await config.download { progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                self.downloadProgress = fraction
                let percent = Int(fraction * 100)
                if percent < 100 {
                    self.statusMessage = "Đang tải model về iPad: \(percent)%"
                }
            }
        }

        await MainActor.run {
            self.statusMessage = "Đang khởi động GPU M5 và vẽ tranh..."
        }

        var params = config.defaultParameters()
        params.prompt = fullPrompt
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

        generator!.ensureLoaded()
        var latents = Optional(generator!.generateLatents(parameters: params))
        var current = latents?.next() ?? nil
        var currentStep = 1

        while let next = (latents?.next() ?? nil) {
            current = next
            currentStep += 1
            let stepCopy = currentStep
            Task { @MainActor in
                self.statusMessage = "Đang vẽ bước \(stepCopy)/\(steps)..."
            }
        }

        let decoder = generator!.detachedDecoder()
        // Giải phóng UNet và TextEncoder khỏi RAM trước khi giải mã ảnh
        latents = nil
        generator = nil

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
        return StableDiffusion.Image(decoded).asCGImage()
    }
}
