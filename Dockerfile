FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    NOVNC_PORT=6080 \
    ANDROID_ISO="/data/android.iso" \
    ANDROID_DISK="/data/android-disk.qcow2" \
    ANDROID_ISO_URL="https://sourceforge.net/projects/android-x86/files/Release%209.0/android-x86_64-9.0-r2.iso/download" \
    DISK_SIZE="8G" \
    RAM="2048" \
    CPUS="2"

# ── Install semua package ────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-kvm \
    qemu-utils \
    libsdl2-2.0-0 \
    libsdl2-image-2.0-0 \
    wget \
    curl \
    xvfb \
    x11vnc \
    git \
    python3 \
    python3-pip \
    python3-numpy \
    openbox \
    net-tools \
    procps \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── Install noVNC dari git (versi terbaru, path pasti) ──────────
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /opt/websockify \
    && pip3 install --break-system-packages /opt/websockify \
    && ln -sf /opt/novnc/vnc.html /opt/novnc/index.html

# ── Buat direktori data persistent ──────────────────────────────
RUN mkdir -p /data

# ── Tulis entrypoint ─────────────────────────────────────────────
RUN cat > /start.sh << 'SCRIPT'
#!/bin/bash

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }

log "=== Android x86 VM ==="

mkdir -p /data

# 1. Download ISO
if [ ! -f "$ANDROID_ISO" ]; then
    log "Download Android x86 ISO (~900MB)..."
    wget -q --show-progress -O "$ANDROID_ISO" "$ANDROID_ISO_URL" \
        || die "Gagal download ISO. Mount manual: -v /path/to/android.iso:/data/android.iso"
    log "ISO selesai diunduh."
else
    log "ISO sudah ada: $ANDROID_ISO"
fi

# 2. Buat disk
if [ ! -f "$ANDROID_DISK" ]; then
    log "Membuat virtual disk ${DISK_SIZE}..."
    qemu-img create -f qcow2 "$ANDROID_DISK" "$DISK_SIZE"
    log "Disk dibuat: $ANDROID_DISK"
else
    log "Disk sudah ada: $ANDROID_DISK"
fi

# 3. Xvfb
log "Start Xvfb..."
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb :99 -screen 0 1280x768x24 -ac -noreset &
XVFB_PID=$!
sleep 3
kill -0 $XVFB_PID 2>/dev/null || die "Xvfb gagal start"
log "Xvfb OK (PID $XVFB_PID)"

# 4. Openbox
DISPLAY=:99 openbox --sm-disable &
sleep 1

# 5. KVM check
KVM_ARGS="-cpu qemu64"
[ -e /dev/kvm ] && KVM_ARGS="-enable-kvm -cpu host" && log "KVM aktif" || log "KVM tidak ada, pakai emulasi"

# 6. QEMU — render ke Xvfb via SDL
log "Start QEMU Android..."
DISPLAY=:99 qemu-system-x86_64 \
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
    -device usb-ehci \
    -device usb-tablet \
    -audiodev none,id=snd \
    -machine type=pc \
    2>/tmp/qemu.log &
QEMU_PID=$!
sleep 5
kill -0 $QEMU_PID 2>/dev/null || { log "QEMU gagal! Log:"; cat /tmp/qemu.log; exit 1; }
log "QEMU OK (PID $QEMU_PID)"

# 7. x11vnc — capture Xvfb ke VNC port 5900
log "Start x11vnc..."
x11vnc \
    -display :99 \
    -rfbport 5900 \
    -nopw \
    -forever \
    -shared \
    -noxdamage \
    -nodpms \
    -wait 20 \
    -defer 5 \
    -bg \
    -o /tmp/x11vnc.log
sleep 2
# Verifikasi port 5900 listening
if ! ss -tlnp 2>/dev/null | grep -q ':5900' && ! netstat -tlnp 2>/dev/null | grep -q ':5900'; then
    log "x11vnc log:"; cat /tmp/x11vnc.log
    die "x11vnc tidak listening di port 5900"
fi
log "x11vnc OK (port 5900)"

# 8. websockify — bridge port 6080 → 5900
log "Start websockify (noVNC) port $NOVNC_PORT..."
python3 -m websockify \
    --web=/opt/novnc \
    --heartbeat=15 \
    0.0.0.0:$NOVNC_PORT \
    127.0.0.1:5900 \
    > /tmp/websockify.log 2>&1 &
WS_PID=$!
sleep 3
kill -0 $WS_PID 2>/dev/null || { log "websockify log:"; cat /tmp/websockify.log; die "websockify gagal"; }
log "websockify OK (PID $WS_PID)"

log ""
log "============================================"
log "  ✅  SIAP! Buka di browser:"
log "  🌐  http://<HOST_IP>:$NOVNC_PORT/vnc.html"
log "  📱  ADB: adb connect <HOST_IP>:5555"
log "============================================"

# Jaga container tetap hidup
wait $QEMU_PID
SCRIPT

RUN chmod +x /start.sh

EXPOSE 6080 5555

CMD ["/start.sh"]
