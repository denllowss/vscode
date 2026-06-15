# ============================================================
# Nintendo DS Emulator (desmume) via noVNC — Satu File
# Akses: http://localhost:6080/vnc.html?autoconnect=1
# ============================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    SCREEN_WIDTH=1280 \
    SCREEN_HEIGHT=800 \
    SCREEN_DEPTH=24 \
    VNC_PORT=5900 \
    NOVNC_PORT=6080

# Install semua dependencies sekaligus
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    openbox \
    x11-xserver-utils \
    desmume \
    fonts-liberation \
    dbus-x11 \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Buat folder ROM & tulis startup script dalam satu RUN
RUN mkdir -p /roms && \
    printf '#!/bin/bash\n\
set -e\n\
echo "=== Nintendo DS Emulator via noVNC ==="\n\
echo "=== Buka: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1 ==="\n\
Xvfb ${DISPLAY} -screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH} &\n\
sleep 1\n\
DISPLAY=${DISPLAY} openbox-session &\n\
sleep 1\n\
x11vnc -display ${DISPLAY} -nopw -listen 0.0.0.0 -rfbport ${VNC_PORT} -forever -shared -noxdamage -quiet &\n\
sleep 1\n\
websockify --web /usr/share/novnc --wrap-mode=ignore 0.0.0.0:${NOVNC_PORT} localhost:${VNC_PORT} &\n\
sleep 1\n\
ROM=$(find /roms -maxdepth 1 \\( -name "*.nds" -o -name "*.NDS" \\) 2>/dev/null | head -n 1)\n\
if [ -n "$ROM" ]; then\n\
    echo "=== Memuat ROM: $ROM ==="\n\
    DISPLAY=${DISPLAY} desmume "$ROM" &\n\
else\n\
    echo "=== Tidak ada ROM di /roms, buka desmume kosong ==="\n\
    DISPLAY=${DISPLAY} desmume &\n\
fi\n\
wait\n' > /start.sh && \
    chmod +x /start.sh

EXPOSE 6080 5900

CMD ["/start.sh"]
