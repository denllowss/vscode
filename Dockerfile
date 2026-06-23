FROM ubuntu:22.04

# ─── Environment ──────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:0 \
    NOVNC_PORT=6080 \
    ANDROID_ISO="/android.iso" \
    ANDROID_DISK="/android-disk.qcow2" \
    ANDROID_ISO_URL="https://sourceforge.net/projects/android-x86/files/Release%209.0/android-x86_64-9.0-r2.iso/download" \
    DISK_SIZE="8G" \
    RAM="2048" \
    CPUS="2"

# ─── Install semua dependency ──────────────────────────────────
RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-kvm \
    qemu-utils \
    wget \
    curl \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    net-tools \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ─── Symlink noVNC index ───────────────────────────────────────
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html || true

# ─── Tulis entrypoint langsung ke dalam image ─────────────────
RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    '' \
    'echo "========================================"' \
    'echo "  Android x86 VM  |  Web: port $NOVNC_PORT"' \
    'echo "========================================"' \
    '' \
    '# 1. Download ISO jika belum ada' \
    'if [ ! -f "$ANDROID_ISO" ]; then' \
    '    echo "[*] Mengunduh Android x86 ISO (~900 MB)..."' \
    '    wget --progress=bar:force -O "$ANDROID_ISO" "$ANDROID_ISO_URL" || {' \
    '        echo "[!] Gagal download. Mount manual: -v /path/to/android.iso:/android.iso"' \
    '        exit 1' \
    '    }' \
    '    echo "[✓] ISO berhasil diunduh."' \
    'else' \
    '    echo "[✓] ISO ditemukan: $ANDROID_ISO"' \
    'fi' \
    '' \
    '# 2. Buat virtual disk jika belum ada' \
    'if [ ! -f "$ANDROID_DISK" ]; then' \
    '    echo "[*] Membuat virtual disk ${DISK_SIZE}..."' \
    '    qemu-img create -f qcow2 "$ANDROID_DISK" "$DISK_SIZE"' \
    '    echo "[✓] Virtual disk dibuat."' \
    'else' \
    '    echo "[✓] Virtual disk sudah ada."' \
    'fi' \
    '' \
    '# 3. Cek KVM' \
    'if [ -e /dev/kvm ]; then' \
    '    echo "[✓] KVM tersedia – akselerasi hardware aktif."' \
    '    KVM_ARGS="-enable-kvm -cpu host"' \
    'else' \
    '    echo "[!] KVM tidak tersedia – emulasi software (lebih lambat)."' \
    '    KVM_ARGS="-cpu qemu64"' \
    'fi' \
    '' \
    '# 4. Jalankan Android di QEMU dengan output VNC di display :10 (port 5910)' \
    'echo "[*] Menjalankan Android x86 di QEMU..."' \
    'qemu-system-x86_64 \' \
    '    $KVM_ARGS \' \
    '    -m "$RAM" \' \
    '    -smp "$CPUS" \' \
    '    -hda "$ANDROID_DISK" \' \
    '    -cdrom "$ANDROID_ISO" \' \
    '    -boot order=dc \' \
    '    -vga std \' \
    '    -display none \' \
    '    -vnc :10 \' \
    '    -net nic \' \
    '    -net user,hostfwd=tcp::5555-:5555 \' \
    '    -usb \' \
    '    -device usb-tablet \' \
    '    -no-reboot &' \
    '' \
    'QEMU_PID=$!' \
    'echo "[✓] QEMU berjalan (PID: $QEMU_PID)"' \
    'sleep 3' \
    '' \
    '# 5. noVNC: bridge WebSocket (6080) → QEMU VNC (localhost:5910)' \
    'echo "[*] Menjalankan noVNC pada port $NOVNC_PORT..."' \
    'websockify \' \
    '    --web=/usr/share/novnc/ \' \
    '    --heartbeat=30 \' \
    '    "$NOVNC_PORT" \' \
    '    "localhost:5910" &' \
    '' \
    'echo ""' \
    'echo "========================================"' \
    'echo "  ✅  Android VM SIAP!"' \
    'echo "  🌐  Buka: http://<HOST_IP>:$NOVNC_PORT"' \
    'echo "  📱  ADB : adb connect <HOST_IP>:5555"' \
    'echo "========================================"' \
    '' \
    'wait $QEMU_PID' \
    > /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 6080 5555

CMD ["/entrypoint.sh"]
