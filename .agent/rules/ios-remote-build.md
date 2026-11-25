---
trigger: always_on
---

# Luật phát triển & biên dịch từ xa cho dự án MyArtAgent (iPadOS trên Windows)

- Dự án này là ứng dụng Swift/SwiftUI chạy local trên iPad Pro M5, viết trên Windows và biên dịch từ xa bằng GitHub Actions (macOS + XcodeGen + xcodebuild).
- Trước khi chỉnh sửa bất kỳ file nào, luôn đọc toàn bộ các file liên quan trong `Sources/` và `project.yml` để đảm bảo đồng bộ tên hàm, kiểu dữ liệu và dependency.
- Hoàn tất sửa toàn bộ các file cần thiết rồi mới chạy build một lần (không commit/push lẻ từng file).
- Ràng buộc phần cứng bắt buộc: App cài bằng Apple ID miễn phí qua Sideloadly nên bị giới hạn trần RAM iPadOS (~4–5 GB). Luôn giữ `MLX.Memory.cacheLimit` thấp (20 MB), không nạp song song LLM và Diffusion model, và luôn gọi `MLX.Memory.clearCache()` sau khi giải phóng từng model.
- Không bao giờ commit thư mục `dist/` hoặc file `last_build_error.log`.