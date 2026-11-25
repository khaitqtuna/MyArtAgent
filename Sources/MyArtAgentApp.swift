import SwiftUI

@main
struct MyArtAgentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var userIdea: String = ""
    @State private var statusText: String = "Sẵn sàng nhận ý tưởng vẽ tranh!"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Nhập ý tưởng tranh (VD: Mèo phi hành gia...)", text: $userIdea)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button("Tạo tranh thử") {
                    if userIdea.isEmpty {
                        statusText = "Bạn hãy nhập ý tưởng trước nhé."
                    } else {
                        statusText = "Đã nhận ý tưởng: \(userIdea)\n(Bước sau sẽ gắn AI vào đây!)"
                    }
                }
                .buttonStyle(.borderedProminent)

                Text(statusText)
                    .multilineTextAlignment(.center)
                    .padding()
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, 30)
            .navigationTitle("My Art Agent")
        }
    }
}
