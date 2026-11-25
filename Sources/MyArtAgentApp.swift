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
    @State private var selectedImageModel: ImageModel = .meinaMix
    @State private var selectedStyle: ArtStyle = .anime
    @State private var steps: Int = 20
    @State private var useLLM: Bool = true
    @State private var llmModelId: String = PromptAgent.defaultModelId
    @State private var savedNotice: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(useLLM
                             ? "Nhập ý tưởng tranh (tiếng Việt hay tiếng Anh đều được):"
                             : "Nhập thẳng Prompt tiếng Anh (Direct Mode):")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(
                            useLLM
                                ? "VD: Một cô gái cầm đèn lồng giữa phố đêm mưa ở Tokyo"
                                : "VD: 1girl holding a paper lantern in a rainy Tokyo street at night",
                            text: $ideaText,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Bật LLM tối ưu prompt (dịch & viết chi tiết)", isOn: $useLLM)

                    if useLLM {
                        DisclosureGroup("Tùy chỉnh mô hình LLM (Hugging Face)") {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Hugging Face MLX Model ID", text: $llmModelId)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)

                                Text("Mặc định dùng Qwen3-4B-Instruct-2507 (4-bit, ~2.1 GB) dịch sát ý, ít bịa thêm chi tiết. Có thể đổi sang model MLX 4-bit khác.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                        .font(.subheadline)
                    }

                    HStack {
                        Text("Mô hình vẽ:")
                        Spacer()
                        Picker("Mô hình vẽ", selection: $selectedImageModel) {
                            ForEach(ImageModel.allCases) { model in
                                Text(model.displayName).tag(model)
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

                    Stepper("Số bước vẽ (Steps): \(steps)", value: $steps, in: 10...35, step: 2)

                    Button {
                        savedNotice = ""
                        engine.generateImage(
                            idea: ideaText,
                            imageModel: selectedImageModel,
                            style: selectedStyle,
                            steps: steps,
                            useLLM: useLLM,
                            llmModelId: llmModelId
                        )
                    } label: {
                        Text(engine.isGenerating ? "Đang xử lý..." : "Tạo tranh AI")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isGenerating || ideaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
                            Text("Prompt tiếng Anh do LLM tạo:")
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

                    if let image = engine.generatedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(radius: 4)

                        Button("Lưu vào Thư viện Ảnh") {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            savedNotice = "Đã lưu vào Thư viện Ảnh của iPad!"
                        }
                        .buttonStyle(.bordered)

                        if !savedNotice.isEmpty {
                            Text(savedNotice)
                                .font(.footnote)
                                .foregroundStyle(.green)
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
