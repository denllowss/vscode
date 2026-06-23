FROM ubuntu:22.04

# ─── Environment ──────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
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
    openbox \
    net-tools \
    ca-certificates \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ─── Symlink noVNC index ───────────────────────────────────────
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html 2>/dev/null || \
    ln -sf /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html 2>/dev/null || true

# ─── Buat entrypoint all-in-one ───────────────────────────────
RUN cat > /entrypoint.sh << 'SCRIPT'
#!/bin/bash
set -e

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "========================================"
log "  Android x86 VM  |  port $NOVNC_PORT  "
log "========================================"

# ── 1. Download ISO jika belum ada ──────────────────────────
if [ ! -f "$ANDROID_ISO" ]; then
    log "Mengunduh Android x86 ISO (~900 MB)..."
    wget -q --show-progress -O "$ANDROID_ISO" "$ANDROID_ISO_URL" || {
        log "GAGAL download ISO."
        log "Mount manual: -v /path/to/android.iso:/android.iso"
        exit 1
    }
    log "ISO berhasil diunduh."
else
    log "ISO ditemukan: $ANDROID_ISO"
fi

# ── 2. Buat virtual disk jika belum ada ─────────────────────
if [ ! -f "$ANDROID_DISK" ]; then
    log "Membuat virtual disk ${DISK_SIZE}..."
    qemu-img create -f qcow2 "$ANDROID_DISK" "$DISK_SIZE"
    log "Virtual disk dibuat."
else
    log "Virtual disk sudah ada."
fi

# ── 3. Start Xvfb (virtual framebuffer) ─────────────────────
log "Menjalankan Xvfb pada DISPLAY=$DISPLAY ..."
Xvfb "$DISPLAY" -screen 0 1280x768x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 2
# Verifikasi Xvfb running
if ! kill -0 $XVFB_PID 2>/dev/null; then
    log "ERROR: Xvfb gagal start!"
    exit 1
fi
log "Xvfb aktif (PID: $XVFB_PID)"

# ── 4. Start openbox window manager ─────────────────────────
DISPLAY="$DISPLAY" openbox &
sleep 1

# ── 5. Cek KVM ──────────────────────────────────────────────
if [ -e /dev/kvm ]; then
    log "KVM tersedia – akselerasi hardware aktif."
    KVM_ARGS="-enable-kvm -cpu host"
else
    log "KVM tidak tersedia – emulasi software (lebih lambat)."
    KVM_ARGS="-cpu qemu64"
fi

# ── 6. Jalankan Android di QEMU ─────────────────────────────
# Gunakan display sdl → render ke Xvfb, bukan VNC headless
log "Menjalankan Android x86 di QEMU..."
DISPLAY="$DISPLAY" qemu-system-x86_64 \
    $KVM_ARGS \
    -m "$RAM" \
    -smp "$CPUS" \
    -hda "$ANDROID_DISK" \
    -cdrom "$ANDROID_ISO" \
    -boot order=dc \
    -vga std \
    -display sdl,gl=off \
    -net nic,model=virtio \
    -net user,hostfwd=tcp::5555-:5555 \
    -usb \
    -device usb-tablet \
    -audiodev none,id=audio0 \
    -no-reboot &

QEMU_PID=$!
log "QEMU berjalan (PID: $QEMU_PID)"
sleep 5

# Verifikasi QEMU masih running
if ! kill -0 $QEMU_PID 2>/dev/null; then
    log "ERROR: QEMU gagal start! Cek apakah --privileged aktif."
    exit 1
fi

# ── 7. Start x11vnc (capture Xvfb → VNC) ───────────────────
log "Menjalankan x11vnc..."
x11vnc \
    -display "$DISPLAY" \
    -forever \
    -nopw \
    -shared \
    -noxdamage \
    -rfbport 5900 \
    -bg \
    -o /var/log/x11vnc.log \
    -loop500 \
    -wait 50 \
    -defer 10
sleep 2
log "x11vnc aktif pada port 5900"

# ── 8. Start noVNC (WebSocket → VNC) ────────────────────────
log "Menjalankan noVNC pada port $NOVNC_PORT..."

# Cari path noVNC yang valid
NOVNC_PATH=""
for p in /usr/share/novnc /usr/share/novnc/utils /opt/novnc; do
    [ -d "$p" ] && NOVNC_PATH="$p" && break
done

if [ -z "$NOVNC_PATH" ]; then
    log "ERROR: noVNC tidak ditemukan!"
    exit 1
fi

websockify \
    --web="$NOVNC_PATH" \
    --heartbeat=30 \
    "$NOVNC_PORT" \
    "127.0.0.1:5900" &

NOVNC_PID=$!
sleep 2

if ! kill -0 $NOVNC_PID 2>/dev/null; then
    log "ERROR: websockify/noVNC gagal start!"
    exit 1
fi

log ""
log "========================================"
log "  ✅  Android VM SIAP!"
log "  🌐  Buka: http://<HOST_IP>:$NOVNC_PORT"
log "  📱  ADB : adb connect <HOST_IP>:5555"
log "========================================"

# Tunggu QEMU sampai selesai
wait $QEMU_PID
SCRIPT

RUN chmod +x /entrypoint.sh

EXPOSE 6080 5555

CMD ["/entrypoint.sh"]
