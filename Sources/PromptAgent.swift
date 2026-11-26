import Foundation
import MLX
import MLXLLM
import MLXLMCommon

enum LLMModelPreset: String, CaseIterable, Identifiable {
    case qwen35_4B = "mlx-community/Qwen3.5-4B-MLX-4bit"
    case qwen3_4B = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    case phi4Mini = "mlx-community/Phi-4-mini-instruct-4bit"
    case gemma3_4B = "mlx-community/gemma-3-4b-it-4bit"
    case llama32_3B = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    case gemma2_2B = "mlx-community/gemma-2-2b-it-4bit"
    case qwen25_7B = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen35_4B:
            return "Qwen 3.5 4B (~2.8 GB • Thông minh nhất)"
        case .qwen3_4B:
            return "Qwen 3 4B Instruct (~2.1 GB • Dịch Việt/Anh chuẩn)"
        case .phi4Mini:
            return "Phi-4 Mini (~2.0 GB • Kiểm lỗi chặt, ít bịa)"
        case .gemma3_4B:
            return "Gemma 3 4B IT (~3.2 GB • Mượt & giàu chi tiết)"
        case .llama32_3B:
            return "Llama 3.2 3B (~1.7 GB • Nhẹ & nhanh)"
        case .gemma2_2B:
            return "Gemma 2 2B (~1.4 GB • Siêu nhẹ RAM)"
        case .qwen25_7B:
            return "Qwen 2.5 7B (~4.0 GB • Cần iPad RAM cao)"
        }
    }
}

enum LLMPipelineMode: String, CaseIterable, Identifiable {
    case dualEnsemble = "Kết hợp 2 LLM (Dịch & Lập ý → Kiểm lỗi & Tinh chỉnh)"
    case single = "1 LLM đơn (Nhanh)"

    var id: String { rawValue }
}

struct PromptAgent {
    static let defaultPrimaryModel: LLMModelPreset = .qwen35_4B
    static let defaultRefinerModel: LLMModelPreset = .phi4Mini

    static func generatePrompts(
        userIdea: String,
        styleName: String,
        styleSuffix: String,
        qualityTags: String,
        tagsAtStart: Bool,
        tagFormatted: Bool,
        count: Int,
        sequenceGrowth: Bool,
        primaryModel: LLMModelPreset,
        refinerModel: LLMModelPreset,
        pipelineMode: LLMPipelineMode,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> [String] {
        let clampedCount = max(1, count)
        let isSequence = clampedCount > 1 && sequenceGrowth
        let formatRule = tagFormatted
            ? "Use concise comma-separated Danbooru/booru keyword tags (e.g., 1girl, silver hair, dynamic pose, dramatic lighting) rather than long prose."
            : "Use concise, vivid English visual phrases (subject, pose, composition, lighting, colors, atmosphere)."

        let stage1SystemPrompt: String
        if isSequence {
            stage1SystemPrompt = """
            You are a precise Stable Diffusion sequence planner and translator.
            Convert the user's idea into EXACTLY \(clampedCount) progressive English prompts showing a clear, smooth step-by-step sequence/growth from Stage 1 (beginning) to Stage \(clampedCount) (final culmination), matching style "\(styleName)".
            STRICT RULES:
            1. Preserve ONLY the subjects, setting, and evolution requested or directly implied by the user. NEVER hallucinate unrelated characters or objects.
            2. Keep the same main subject, camera framing, and visual identity across all \(clampedCount) stages, changing only what progressively grows or transforms at each stage.
            3. \(formatRule) Keep each prompt under 42 words.
            4. Output EXACTLY \(clampedCount) lines formatted strictly as:
            1: <prompt for stage 1>
            2: <prompt for stage 2>
            ...
            \(clampedCount): <prompt for stage \(clampedCount)>
            Do NOT include any intro, outro, markdown, or quotation marks.
            """
        } else {
            stage1SystemPrompt = """
            You are a precise translator and prompt formatter for Stable Diffusion image generation.
            Translate the user's idea into English for the style "\(styleName)" (maximum 45 words).
            STRICT RULES:
            1. Preserve ONLY the subjects, actions, objects, clothing, colors, mood, and setting explicitly mentioned or directly implied by the user.
            2. NEVER invent, add, or hallucinate extra characters, animals, objects, text, or lore that the user did not ask for.
            3. \(formatRule)
            4. Output ONLY the final English prompt text, with no labels, explanations, markdown, or quotation marks.
            """
        }

        let stage1MaxTokens = isSequence ? min(clampedCount * 75, 550) : 110
        let draftRaw = try await runSingleLLM(
            modelId: primaryModel.rawValue,
            roleLabel: pipelineMode == .dualEnsemble ? "LLM 1 (\(primaryModel.shortLabel))" : "LLM",
            systemPrompt: stage1SystemPrompt,
            userPrompt: userIdea,
            maxTokens: stage1MaxTokens,
            temperature: 0.2,
            actionMessage: isSequence
                ? "LLM 1 đang dịch & lập kịch bản chuỗi \(clampedCount) ảnh..."
                : "LLM đang dịch & chuẩn hóa prompt tiếng Anh...",
            onStatus: onStatus
        )

        let finalRaw: String
        if pipelineMode == .dualEnsemble {
            let stage2SystemPrompt: String
            let stage2UserPrompt: String

            if isSequence {
                let draftLines = parseSequenceLines(draftRaw, expectedCount: clampedCount, fallbackIdea: userIdea)
                let numberedDraft = draftLines.enumerated()
                    .map { "\($0.offset + 1): \($0.element)" }
                    .joined(separator: "\n")

                stage2SystemPrompt = """
                You are a strict Stable Diffusion sequence auditor and refiner.
                Compare the Draft \(clampedCount)-stage sequence against the Original User Request for style "\(styleName)".
                STRICT RULES:
                1. Remove ANY hallucinated character, object, or detail not requested or directly implied by the Original User Request.
                2. Restore any important subject, quantity, color, action, or progression detail from the Original User Request that was missed.
                3. Ensure smooth, logical growth/progression from Stage 1 to Stage \(clampedCount) with consistent subject identity and camera framing.
                4. \(formatRule) Keep each stage under 42 words.
                5. Output EXACTLY \(clampedCount) numbered lines (1: ... to \(clampedCount): ...), with no intro, outro, markdown, or quotes.
                """
                stage2UserPrompt = """
                Original User Request:
                \(userIdea)

                Draft Sequence:
                \(numberedDraft)
                """
            } else {
                let cleanedDraft = cleanPromptLine(draftRaw)
                stage2SystemPrompt = """
                You are a strict prompt fidelity auditor and refiner for Stable Diffusion.
                Compare the Draft Prompt against the Original User Request for style "\(styleName)".
                STRICT RULES:
                1. Remove ANY hallucinated subject, object, action, or detail not requested or directly implied by the Original User Request.
                2. Restore any key subject, quantity, color, mood, or setting from the Original User Request that was missed or mistranslated.
                3. \(formatRule) Keep under 45 words.
                4. Output ONLY the final corrected English prompt text, with no labels, explanations, markdown, or quotation marks.
                """
                stage2UserPrompt = """
                Original User Request:
                \(userIdea)

                Draft Prompt:
                \(cleanedDraft.isEmpty ? userIdea : cleanedDraft)
                """
            }

            finalRaw = try await runSingleLLM(
                modelId: refinerModel.rawValue,
                roleLabel: "LLM 2 (\(refinerModel.shortLabel))",
                systemPrompt: stage2SystemPrompt,
                userPrompt: stage2UserPrompt,
                maxTokens: stage1MaxTokens,
                temperature: 0.15,
                actionMessage: isSequence
                    ? "LLM 2 đang đối chiếu & tinh chỉnh chuỗi \(clampedCount) prompt..."
                    : "LLM 2 đang kiểm lỗi bịa & tinh chỉnh sát nghĩa...",
                onStatus: onStatus
            )
        } else {
            finalRaw = draftRaw
        }

        if isSequence {
            let parsed = parseSequenceLines(finalRaw, expectedCount: clampedCount, fallbackIdea: userIdea)
            return parsed.map {
                applyQualityAndStyle(
                    corePrompt: $0,
                    qualityTags: qualityTags,
                    tagsAtStart: tagsAtStart,
                    styleSuffix: styleSuffix
                )
            }
        } else {
            let cleaned = cleanPromptLine(finalRaw)
            let core = cleaned.isEmpty ? userIdea : cleaned
            let final = applyQualityAndStyle(
                corePrompt: core,
                qualityTags: qualityTags,
                tagsAtStart: tagsAtStart,
                styleSuffix: styleSuffix
            )
            return Array(repeating: final, count: clampedCount)
        }
    }

    private static func runSingleLLM(
        modelId: String,
        roleLabel: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Float,
        actionMessage: String,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        // Ép giới hạn cache GPU xuống 20 MB và giải phóng hoàn toàn trước khi nạp từng LLM
        Memory.cacheLimit = 20 * 1024 * 1024
        Memory.clearCache()
        defer { Memory.clearCache() }

        let config = ModelConfiguration(id: modelId)
        var container: ModelContainer? = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            if percent < 100 {
                onStatus("\(roleLabel) đang tải: \(percent)%...")
            }
        }

        onStatus(actionMessage)

        let generateParameters = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: 0.85,
            repetitionPenalty: 1.08
        )

        var session: ChatSession? = ChatSession(
            container!,
            instructions: systemPrompt,
            generateParameters: generateParameters,
            additionalContext: ["enable_thinking": false]
        )

        let rawOutput = try await session!.respond(to: userPrompt)

        // Giải phóng hoàn toàn LLM hiện tại và cache GPU trước khi nạp LLM kế tiếp hoặc model vẽ
        session = nil
        container = nil
        Memory.clearCache()

        return stripThinkingTags(rawOutput)
    }

    static func buildDirectPrompts(
        userIdea: String,
        styleSuffix: String,
        qualityTags: String,
        tagsAtStart: Bool,
        count: Int,
        sequenceGrowth: Bool
    ) -> [String] {
        let clampedCount = max(1, count)
        if clampedCount > 1 && sequenceGrowth {
            let lines = userIdea
                .components(separatedBy: .newlines)
                .map { cleanPromptLine($0) }
                .filter { !$0.isEmpty }

            if lines.count >= clampedCount {
                return Array(lines.prefix(clampedCount)).map {
                    applyQualityAndStyle(
                        corePrompt: $0,
                        qualityTags: qualityTags,
                        tagsAtStart: tagsAtStart,
                        styleSuffix: styleSuffix
                    )
                }
            }

            return (1...clampedCount).map { stage in
                let progressRatio = Float(stage - 1) / Float(max(clampedCount - 1, 1))
                let stageCue: String
                switch progressRatio {
                case ..<0.2:
                    stageCue = "stage 1 of \(clampedCount), initial early beginning phase"
                case ..<0.55:
                    stageCue = "stage \(stage) of \(clampedCount), gradual middle growth progression"
                case ..<0.85:
                    stageCue = "stage \(stage) of \(clampedCount), advanced transformation phase"
                default:
                    stageCue = "stage \(stage) of \(clampedCount), final peak fully developed climax"
                }
                return applyQualityAndStyle(
                    corePrompt: "\(userIdea), \(stageCue)",
                    qualityTags: qualityTags,
                    tagsAtStart: tagsAtStart,
                    styleSuffix: styleSuffix
                )
            }
        }

        let single = applyQualityAndStyle(
            corePrompt: userIdea,
            qualityTags: qualityTags,
            tagsAtStart: tagsAtStart,
            styleSuffix: styleSuffix
        )
        return Array(repeating: single, count: clampedCount)
    }

    static func applyQualityAndStyle(
        corePrompt: String,
        qualityTags: String,
        tagsAtStart: Bool,
        styleSuffix: String
    ) -> String {
        var result = corePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTags = qualityTags.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTags.isEmpty {
            let lowerResult = result.lowercased()
            let firstTag = trimmedTags.split(separator: ",").first.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            } ?? ""
            if firstTag.isEmpty || !lowerResult.contains(firstTag) {
                result = tagsAtStart
                    ? "\(trimmedTags), \(result)"
                    : "\(result), \(trimmedTags)"
            }
        }

        if !styleSuffix.isEmpty {
            result += styleSuffix
        }
        return result
    }

    private static func stripThinkingTags(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"<think>[\s\S]*?</think>"#, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        if let openRange = result.range(of: "<think>", options: .caseInsensitive) {
            result = String(result[..<openRange.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanPromptLine(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"^(?:stage\s*)?\d+\s*[:.)\-]\s*"#, options: [.caseInsensitive]) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        return s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func parseSequenceLines(_ rawOutput: String, expectedCount: Int, fallbackIdea: String) -> [String] {
        let lines = rawOutput
            .components(separatedBy: .newlines)
            .map { cleanPromptLine($0) }
            .filter { !$0.isEmpty }

        if lines.count >= expectedCount {
            return Array(lines.prefix(expectedCount))
        }
        if lines.isEmpty {
            return (1...expectedCount).map { "\(fallbackIdea), stage \($0) of \(expectedCount)" }
        }
        var padded = lines
        while padded.count < expectedCount {
            let nextIndex = padded.count + 1
            padded.append("\(lines.last ?? fallbackIdea), stage \(nextIndex) of \(expectedCount)")
        }
        return padded
    }
}

private extension LLMModelPreset {
    var shortLabel: String {
        switch self {
        case .qwen35_4B: return "Qwen3.5-4B"
        case .qwen3_4B: return "Qwen3-4B"
        case .phi4Mini: return "Phi-4-Mini"
        case .gemma3_4B: return "Gemma3-4B"
        case .llama32_3B: return "Llama3.2-3B"
        case .gemma2_2B: return "Gemma2-2B"
        case .qwen25_7B: return "Qwen2.5-7B"
        }
    }
}
