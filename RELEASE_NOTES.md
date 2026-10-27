# Tmux Style v1.0.0

- Năm giao diện tmux: Aurora, Midnight / Cyan, Ember, Paper / Ink và Neon / Circuit.
- Bộ cài Windows dạng EXE, chọn màu/thư mục, tạo shortcut workspace ba pane, sao lưu và khôi phục cấu hình.
- Bộ remap theo original tmux configuration: Ctrl-a rồi c, |, -, r/R, z, x/X, mũi tên, Ctrl-mũi tên và F12 pass-through. Không ghi nội dung gõ; chỉ xử lý khi Windows Terminal ở phía trước.
- Giữ các profile/tùy chọn/phím không xung đột. Có bảng các thao tác tmux chưa có tương đương native.
- EXE được biên dịch từ source và chạy self-test từ chính gói trên Windows PowerShell 5.1; CI build/test độc lập.

## Tải và dùng

Windows: tải `TmuxStyle-Setup-1.0.0.exe`, chọn theme và bấm **Install workspace**. Cần Windows 10/11 với .NET Framework 4.8; nếu thiếu Windows Terminal, bộ cài có thể lấy gói chính thức bằng winget khi bạn bật tùy chọn và có internet.

tmux: tải `tmux-theme-collection-1.0.0.zip`, giải nén trên máy đã cài samoshkin/tmux-config và tmux >= 3.2; chạy `bash install.sh aurora` rồi `tmux source-file ~/.tmux.conf`.

EXE chưa ký số. `SHA256SUMS.txt` chứa checksum của các file phát hành. Windows Terminal vẫn kết thúc các phiên PowerShell khi đóng cửa sổ; bản native không cung cấp tmux detach/attach. GUI capture tại môi trường build bị timeout, nên phần kiểm chứng UI không được mô tả là đã bấm thử mọi phím.
