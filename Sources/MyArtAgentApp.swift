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
    @State private var promptText: String = ""
    @State private var selectedStyle: ArtStyle = .anime
    @State private var steps: Int = 4
    @State private var savedNotice: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mô tả tranh (nên nhập tiếng Anh ở bước này):")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(
                            "VD: A cat astronaut floating in nebula, glowing stars",
                            text: $promptText,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
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
                            prompt: promptText,
                            style: selectedStyle,
                            steps: steps
                        )
                    } label: {
                        Text(engine.isGenerating ? "Đang xử lý..." : "Tạo tranh bằng AI")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isGenerating || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
