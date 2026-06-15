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

# Install semua dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    openbox \
    obconf \
    x11-xserver-utils \
    x11-utils \
    xterm \
    desmume \
    fonts-liberation \
    dbus-x11 \
    procps \
    feh \
    && rm -rf /var/lib/apt/lists/*

# Buat folder ROM, config openbox, dan startup script dalam satu RUN
RUN mkdir -p /roms /root/.config/openbox && \
    \
    # Openbox autostart: set background abu-abu + langsung launch desmume
    printf '# Set background warna abu-abu (bukan hitam)\nxsetroot -solid "#2d2d2d"\n\n# Jalankan desmume saat openbox start\nROM=$(find /roms -maxdepth 1 \\( -name "*.nds" -o -name "*.NDS" \\) 2>/dev/null | head -n 1)\nif [ -n "$ROM" ]; then\n    desmume "$ROM" &\nelse\n    desmume &\nfi\n' > /root/.config/openbox/autostart && \
    \
    # Openbox menu klik kanan
    printf '<openbox_menu xmlns="http://openbox.org/3.4/menu">\n  <menu id="root-menu" label="Menu">\n    <item label="desmume"><action name="Execute"><command>desmume</command></action></item>\n    <item label="Terminal"><action name="Execute"><command>xterm</command></action></item>\n    <separator/>\n    <item label="Exit"><action name="Exit"/></item>\n  </menu>\n</openbox_menu>\n' > /root/.config/openbox/menu.xml && \
    \
    # Startup script utama
    printf '#!/bin/bash\nset -e\n\necho "=== Nintendo DS Emulator via noVNC ==="\necho "=== Buka: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1 ==="\n\n# 1. Jalankan Xvfb dan tunggu sampai benar-benar siap\nXvfb ${DISPLAY} -screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH} -ac +extension GLX +render -noreset &\nXVFB_PID=$!\n\n# Poll sampai Xvfb siap (max 10 detik)\nfor i in $(seq 1 20); do\n    if xdpyinfo -display ${DISPLAY} >/dev/null 2>&1; then\n        echo "[OK] Xvfb siap"\n        break\n    fi\n    sleep 0.5\ndone\n\n# 2. Set background warna (bukan hitam polos)\nxsetroot -display ${DISPLAY} -solid "#2d2d2d"\n\n# 3. Window manager openbox\nDISPLAY=${DISPLAY} openbox-session &\nsleep 2\n\n# 4. x11vnc — tunggu display, retry jika gagal\nfor i in 1 2 3; do\n    x11vnc -display ${DISPLAY} -nopw -listen 0.0.0.0 \\\n        -rfbport ${VNC_PORT} -forever -shared \\\n        -noxdamage -noxfixes -repeat -bg -o /tmp/x11vnc.log \\\n        && break || sleep 1\ndone\necho "[OK] x11vnc started"\n\n# 5. noVNC web proxy\nwebsockify --web /usr/share/novnc --wrap-mode=ignore \\\n    0.0.0.0:${NOVNC_PORT} localhost:${VNC_PORT} &\necho "[OK] noVNC started di port ${NOVNC_PORT}"\n\n# 6. Tunggu openbox + desmume fully loaded\nsleep 3\n\necho "=== Siap! Buka browser: http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=1 ==="\n\nwait\n' > /start.sh && \
    chmod +x /start.sh

EXPOSE 6080 5900

CMD ["/start.sh"]
