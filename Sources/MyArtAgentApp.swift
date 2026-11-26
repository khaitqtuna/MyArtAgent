import SwiftUI
import UIKit

@main
struct MyArtAgentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var engine = ArtEngine()
    @State private var ideaText: String = ""
    @State private var selectedPreset: DiffusionModelPreset = .meinaMixSD15
    @State private var customRepoId: String = ""
    @State private var selectedAspectRatio: AspectRatio = .square
    @State private var selectedStyle: ArtStyle = .anime
    @State private var steps: Int = DiffusionModelPreset.meinaMixSD15.recommendedSteps
    @State private var imageCount: Int = 1
    @State private var generationMode: GenerationMode = .sequenceGrowth
    @State private var lockSequenceSeed: Bool = true
    @State private var negativePrompt: String = DiffusionModelPreset.meinaMixSD15.defaultNegativePrompt
    @State private var useLLM: Bool = true
    @State private var primaryLLM: LLMModelPreset = PromptAgent.defaultPrimaryModel
    @State private var refinerLLM: LLMModelPreset = PromptAgent.defaultRefinerModel
    @State private var llmPipelineMode: LLMPipelineMode = .single
    @State private var savedNotice: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(useLLM
                             ? "Nhập ý tưởng tranh hoặc kịch bản chuỗi (tiếng Việt/Anh):"
                             : "Nhập thẳng Prompt tiếng Anh (mỗi dòng 1 giai đoạn nếu tạo chuỗi):")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(
                            useLLM
                                ? "VD: Quá trình một hạt mầm mọc thành cây cổ thụ phát sáng dưới ánh trăng"
                                : "VD: 1girl holding a paper lantern in a rainy Tokyo street at night",
                            text: $ideaText,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Bật LLM tối ưu prompt (dịch & tạo chuỗi)", isOn: $useLLM)

                    if useLLM {
                        DisclosureGroup("Tùy chỉnh mô hình LLM (Danh sách chọn sẵn)") {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Chế độ phối hợp") {
                                    Picker("Chế độ phối hợp", selection: $llmPipelineMode) {
                                        ForEach(LLMPipelineMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                LabeledContent(llmPipelineMode == .dualEnsemble ? "LLM 1 (Dịch & Lập ý)" : "Mô hình LLM") {
                                    Picker("LLM chính", selection: $primaryLLM) {
                                        ForEach(LLMModelPreset.allCases) { model in
                                            Text(model.displayName).tag(model)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                if llmPipelineMode == .dualEnsemble {
                                    LabeledContent("LLM 2 (Kiểm lỗi)") {
                                        Picker("LLM tinh chỉnh", selection: $refinerLLM) {
                                            ForEach(LLMModelPreset.allCases) { model in
                                                Text(model.displayName).tag(model)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }

                                Text("Các LLM chạy tuần tự từng mô hình rồi giải phóng RAM hoàn toàn trước khi vẽ để tránh vượt trần RAM iPadOS.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                    }

                    HStack {
                        Text("Model vẽ:")
                        Spacer()
                        Picker("Model vẽ", selection: $selectedPreset) {
                            ForEach(DiffusionModelPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .onChange(of: selectedPreset) { _, newPreset in
                        steps = newPreset.recommendedSteps
                        negativePrompt = newPreset.defaultNegativePrompt
                    }

                    if selectedPreset == .custom {
                        TextField("Nhập Hugging Face Repo ID (VD: user/my-sdxl-lora)", text: $customRepoId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }

                    HStack {
                        Text("Tỷ lệ khung hình:")
                        Spacer()
                        Picker("Tỷ lệ khung hình", selection: $selectedAspectRatio) {
                            ForEach(AspectRatio.allCases) { ratio in
                                Text(ratio.rawValue).tag(ratio)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("Phong cách:")
                        Spacer()
                        Picker("Phong cách", selection: $selectedStyle) {
                            ForEach(ArtStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Stepper("Số bước vẽ (Steps): \(steps)", value: $steps, in: 2...40, step: 1)

                    Stepper("Số lượng ảnh tạo ra: \(imageCount)", value: $imageCount, in: 1...8, step: 1)

                    if imageCount > 1 {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Chế độ nhiều ảnh:")
                                Spacer()
                                Picker("Chế độ nhiều ảnh", selection: $generationMode) {
                                    ForEach(GenerationMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            if generationMode == .sequenceGrowth {
                                Toggle("Giữ Seed nhất quán giữa các khung hình", isOn: $lockSequenceSeed)
                                    .font(.subheadline)
                            }
                        }
                    }

                    DisclosureGroup("Negative Prompt (Chống lỗi nét / mờ)") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Nhập những thứ muốn loại trừ...", text: $negativePrompt, axis: .vertical)
                                .lineLimit(2...5)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)

                            if selectedPreset == .sdxlTurbo {
                                Text("SDXL Turbo dùng CFG = 0.0 nên không áp dụng Negative Prompt.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.subheadline)

                    Button {
                        savedNotice = ""
                        engine.generateImages(
                            idea: ideaText,
                            preset: selectedPreset,
                            customRepoId: customRepoId,
                            aspectRatio: selectedAspectRatio,
                            style: selectedStyle,
                            steps: steps,
                            imageCount: imageCount,
                            generationMode: generationMode,
                            lockSequenceSeed: lockSequenceSeed,
                            negativePrompt: negativePrompt,
                            useLLM: useLLM,
                            primaryLLM: primaryLLM,
                            refinerLLM: refinerLLM,
                            llmPipelineMode: llmPipelineMode
                        )
                    } label: {
                        Text(engine.isGenerating ? "Đang xử lý..." : (imageCount > 1 ? "Tạo chuỗi \(imageCount) ảnh AI" : "Tạo tranh AI"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        engine.isGenerating
                        || ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (selectedPreset == .custom && customRepoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )

                    if engine.isGenerating {
                        if engine.downloadProgress > 0 && engine.downloadProgress < 1 {
                            ProgressView(value: engine.downloadProgress)
                        } else {
                            ProgressView()
                        }
                    }

                    Text(engine.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if !engine.expandedPrompt.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(imageCount > 1 ? "Kịch bản chuỗi prompt:" : "Prompt tiếng Anh do LLM tạo:")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(.secondary)
                            Text(engine.expandedPrompt)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !engine.generatedItems.isEmpty {
                        VStack(spacing: 14) {
                            ForEach(engine.generatedItems) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    if engine.generatedItems.count > 1 {
                                        Text("Khung hình \(item.index)/\(engine.generatedItems.count)")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(.secondary)
                                    }

                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .shadow(radius: 4)

                                    if engine.generatedItems.count > 1 {
                                        Text(item.prompt)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                            }

                            Button(engine.generatedItems.count > 1 ? "Lưu tất cả \(engine.generatedItems.count) ảnh vào Thư viện" : "Lưu vào Thư viện Ảnh") {
                                for item in engine.generatedItems {
                                    UIImageWriteToSavedPhotosAlbum(item.image, nil, nil, nil)
                                }
                                savedNotice = engine.generatedItems.count > 1
                                    ? "Đã lưu \(engine.generatedItems.count) ảnh vào Thư viện Ảnh của iPad!"
                                    : "Đã lưu vào Thư viện Ảnh của iPad!"
                            }
                            .buttonStyle(.bordered)

                            if !savedNotice.isEmpty {
                                Text(savedNotice)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 700)
            }
            .navigationTitle("My Art Agent")
        }
    }
}
