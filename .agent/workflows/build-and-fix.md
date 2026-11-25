---
description: Đẩy code lên GitHub, chờ Xcode biên dịch, tự đọc lỗi và sửa cho đến khi tải xong file .ipa
---

1. Kiểm tra lại toàn bộ các file vừa sửa trong `Sources/` và `project.yml` xem có lỗi cú pháp hoặc lệch chữ ký hàm giữa các file không.
2. Chạy lệnh PowerShell sau để commit, push và theo dõi GitHub Actions:
   `powershell -ExecutionPolicy Bypass -File .\scripts\ci_build.ps1 "<tóm tắt ngắn gọn thay đổi bằng tiếng Anh>"`
   Lưu ý: Quá trình biên dịch Xcode trên macOS mất khoảng 4–12 phút; hãy kiên nhẫn chờ lệnh hoàn tất thay vì hủy sớm.
3. Nếu lệnh trả về mã lỗi khác 0:
   - Đọc kỹ phần `TOM TAT LOI BIEN DICH` trong output Terminal. Nếu chưa đủ ngữ cảnh, mở file `last_build_error.log` và tìm các dòng chứa `error:`.
   - Sửa trực tiếp lỗi trong mã nguồn và lặp lại bước 2.
   - Thực hiện tối đa **4 vòng sửa tự động**. Nếu sau 4 vòng vẫn thất bại, dừng lại và giải thích chi tiết lỗi cho người dùng.
4. Nếu lệnh trả về mã 0: thông báo cho người dùng biết file `dist\MyArtAgent.ipa` đã tải sẵn để cài vào iPad qua Sideloadly.