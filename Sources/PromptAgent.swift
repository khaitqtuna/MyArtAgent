import Foundation
import MLX
import MLXLLM
import MLXLMCommon

struct PromptAgent {
    static let defaultModelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"

    static func expandPrompt(
        userIdea: String,
        styleName: String,
        modelId: String,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let trimmedModel = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetModel = trimmedModel.isEmpty ? defaultModelId : trimmedModel

        let systemPrompt = """
        You are an expert AI art prompt engineer.
        Convert the user's idea (which may be in Vietnamese or English) into a single, vivid, concise English image-generation prompt (maximum 55 words).
        Include subject, composition, lighting, color palette, and atmosphere matching the requested style: \(styleName).
        Output ONLY the final English prompt text. Do not include explanations, labels, or quotation marks.
        """

        // Ép giới hạn cache GPU xuống 20 MB và dọn sạch trước khi nạp LLM
        Memory.cacheLimit = 20 * 1024 * 1024
        Memory.clearCache()
        defer { Memory.clearCache() }

        let config = ModelConfiguration(id: targetModel)
        var container: ModelContainer? = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            if percent < 100 {
                onStatus("Não AI đang tải model ngôn ngữ: \(percent)%...")
            }
        }

        onStatus("Não AI đang phân tích ý tưởng & viết prompt tiếng Anh...")

        var session: ChatSession? = ChatSession(
            container!,
            instructions: systemPrompt
        )

        let rawOutput = try await session!.respond(to: userIdea)

        // Giải phóng hoàn toàn LLM và cache GPU trước khi nhường RAM cho model vẽ
        session = nil
        container = nil
        Memory.clearCache()

        let cleaned = rawOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        return cleaned.isEmpty ? userIdea : cleaned
    }
}
