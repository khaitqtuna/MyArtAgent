import Foundation
import MLX
import MLXLLM
import MLXLMCommon

struct PromptAgent {
    static let defaultModelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit"

    static func expandPrompt(
        userIdea: String,
        styleName: String,
        modelId: String,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let trimmedModel = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetModel = trimmedModel.isEmpty ? defaultModelId : trimmedModel

        let systemPrompt = """
        You are a precise translator and prompt formatter for Stable Diffusion image generation.
        Translate the user's idea into natural, vivid English image-generation phrases (maximum 48 words), tailored for the style "\(styleName)".
        STRICT RULES:
        1. Preserve ONLY the subjects, actions, objects, clothing, colors, mood, and setting explicitly mentioned or directly implied by the user.
        2. NEVER invent, add, or hallucinate extra characters, animals, objects, text, or lore that the user did not ask for.
        3. Describe concrete visual details (composition, lighting, atmosphere) concisely without filler prose.
        4. Output ONLY the final English prompt text, with no labels, explanations, markdown, or quotation marks.
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
                onStatus("LLM đang tải mô hình ngôn ngữ: \(percent)%...")
            }
        }

        onStatus("LLM đang dịch & chuẩn hóa prompt tiếng Anh...")

        let generateParameters = GenerateParameters(
            maxTokens: 110,
            temperature: 0.2,
            topP: 0.85,
            repetitionPenalty: 1.08
        )

        var session: ChatSession? = ChatSession(
            container!,
            instructions: systemPrompt,
            generateParameters: generateParameters
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
