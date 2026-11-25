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
    @State private var selectedStyle: ArtStyle = .anime
    @State private var steps: Int = 4
    @State private var useAgent: Bool = true
    @State private var llmModelId: String = PromptAgent.defaultModelId
    @State private var savedNotice: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(useAgent
                             ? "Nhập ý tưởng tranh (tiếng Việt hay tiếng Anh đều được):"
                             : "Nhập thẳng Prompt tiếng Anh (Direct Mode):")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(
                            useAgent
                                ? "VD: Một quán mì nhỏ ấm cúng giữa đêm mưa ở Tokyo"
                                : "VD: A cozy ramen shop at night in the rain, warm glow",
                            text: $ideaText,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Bật Não AI Agent (tự dịch & viết prompt)", isOn: $useAgent)

                    if useAgent {
                        DisclosureGroup("Tùy chỉnh model Não AI (Hugging Face)") {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Hugging Face MLX Model ID", text: $llmModelId)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)

                                Text("Mặc định dùng Qwen2.5-3B (4-bit, ~1.8 GB). Có thể đổi sang bất kỳ model MLX 4-bit nào khác trên Hugging Face.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                        .font(.subheadline)
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

                    Stepper("Số bước vẽ (Steps): \(steps)", value: $steps, in: 2...8)

                    Button {
                        savedNotice = ""
                        engine.generateImage(
                            idea: ideaText,
                            style: selectedStyle,
                            steps: steps,
                            useAgent: useAgent,
                            llmModelId: llmModelId
                        )
                    } label: {
                        Text(engine.isGenerating ? "Đang xử lý..." : "Tạo tranh bằng AI Agent")
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
                            Text("Prompt tiếng Anh do Agent viết:")
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
