FROM codercom/code-server:latest
USER root

# ══════════════════════════════════════════════════════════════════════════════
# 1. INSTALL ALAT PROTEKSI
#    - e2fsprogs : untuk perintah chattr (immutable flag)
#    - inotify-tools : opsional, pantau perubahan file sistem secara realtime
# ══════════════════════════════════════════════════════════════════════════════
RUN apt-get update && apt-get install -y --no-install-recommends \
        e2fsprogs \
        inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# ══════════════════════════════════════════════════════════════════════════════
# 2. SIAPKAN WORKSPACE ROOT YANG AMAN
#    Hanya /root/project yang boleh ditulis & dihapus.
# ══════════════════════════════════════════════════════════════════════════════
RUN mkdir -p /root/project
WORKDIR /root/project

# ══════════════════════════════════════════════════════════════════════════════
# 3. PROTEKSI DIREKTORI SISTEM DENGAN chattr +i (IMMUTABLE)
#    Bahkan root tidak bisa menghapus / memindahkan file di dalam direktori
#    yang sudah diberi flag immutable.
#
#    Catatan: chattr +i PADA DIREKTORI itu sendiri mencegah:
#      - penghapusan isi direktori  (unlink)
#      - rename/move file di dalamnya
#      - pembuatan file baru di dalamnya
#    tapi TIDAK mencegah baca / eksekusi file yang sudah ada (normal).
#
#    chattr +i tidak bisa dijalankan saat build (butuh kernel nyata),
#    jadi kita pakai entrypoint inline untuk menerapkannya saat container
#    pertama kali start.
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# 4. TULIS ENTRYPOINT INLINE — TIDAK ADA FILE EKSTERNAL
#    Script ini:
#      a) Pasang chattr +i pada direktori sistem kritis
#      b) Verifikasi binary utama masih utuh (SHA256)
#      c) Jalankan code-server
# ══════════════════════════════════════════════════════════════════════════════
RUN cat > /usr/local/sbin/docker-entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
set -euo pipefail

# ── Warna untuk log ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[GUARD]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN] ${NC} $*"; }
die()  { echo -e "${RED}[FATAL]${NC} $*"; exit 1; }

log "════════════════════════════════════════"
log "  Code-Server Security Guard v2.0"
log "════════════════════════════════════════"

# ══════════════════════════════════════════════════════════════════════════════
# A. APT HOLD — Cegah penghapusan paket kritis via apt/dpkg
#    apt-mark hold memblokir: apt remove, apt purge, apt autoremove
#    terhadap paket yang di-hold. Ini berlapis dengan chattr di bawah.
# ══════════════════════════════════════════════════════════════════════════════
log "Mengunci paket APT kritis dengan apt-mark hold..."

APT_CRITICAL_PACKAGES=(
    # ── Manajer paket itu sendiri ──────────────────────────────────────────
    apt
    apt-utils
    dpkg
    # ── Library inti apt ──────────────────────────────────────────────────
    libapt-pkg6.0
    # ── Pondasi sistem ────────────────────────────────────────────────────
    base-files
    base-passwd
    bash
    coreutils
    util-linux
    login
    passwd
    # ── Manajemen file & proses ───────────────────────────────────────────
    findutils
    grep
    sed
    gawk
    procps
    # ── Jaringan & keamanan ───────────────────────────────────────────────
    libssl3
    ca-certificates
    openssl
    # ── Alat proteksi yang sudah kita install ─────────────────────────────
    e2fsprogs
    inotify-tools
)

HELD=0; FAILED=0
for pkg in "${APT_CRITICAL_PACKAGES[@]}"; do
    # Hanya hold jika paket memang terpasang
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        if apt-mark hold "$pkg" > /dev/null 2>&1; then
            ((HELD++))
        else
            warn "  Gagal hold: $pkg"
            ((FAILED++))
        fi
    fi
done
log "  ✅ $HELD paket dikunci (hold), $FAILED gagal"

# ══════════════════════════════════════════════════════════════════════════════
# B. PROTEKSI FILE APT DENGAN chattr +i
#    Lindungi binary apt, database dpkg, dan konfigurasi apt secara langsung.
#    Ini adalah lapisan kedua — bahkan jika seseorang mencoba bypass apt-mark,
#    file fisiknya tidak bisa dihapus.
# ══════════════════════════════════════════════════════════════════════════════
log "Memasang chattr +i pada binary & database APT..."

# Binary apt & dpkg (file spesifik, bukan seluruh direktori dulu)
APT_BINARIES=(
    /usr/bin/apt
    /usr/bin/apt-get
    /usr/bin/apt-cache
    /usr/bin/apt-mark
    /usr/bin/apt-key
    /usr/bin/apt-config
    /usr/bin/dpkg
    /usr/bin/dpkg-query
    /usr/bin/dpkg-divert
)
for bin in "${APT_BINARIES[@]}"; do
    if [[ -f "$bin" ]]; then
        chattr +i "$bin" 2>/dev/null \
            && log "  ✅ Immutable: $bin" \
            || warn "  ⚠️  Lewati: $bin"
    fi
done

# Database dpkg (list paket yang terpasang) — immutable seluruh dir
log "Memasang chattr +i pada database dpkg..."
chattr -R +i /var/lib/dpkg/info   2>/dev/null && log "  ✅ Immutable: /var/lib/dpkg/info"   || warn "  ⚠️  /var/lib/dpkg/info"
chattr    +i /var/lib/dpkg/status 2>/dev/null && log "  ✅ Immutable: /var/lib/dpkg/status" || warn "  ⚠️  /var/lib/dpkg/status"
chattr    +i /var/lib/dpkg/lock   2>/dev/null || true  # lock file, boleh lewati
chattr -R +i /var/lib/apt         2>/dev/null && log "  ✅ Immutable: /var/lib/apt"         || warn "  ⚠️  /var/lib/apt"

# Konfigurasi apt (/etc/apt sudah dicakup di bawah oleh proteksi /etc)
chattr -R +i /etc/apt 2>/dev/null && log "  ✅ Immutable: /etc/apt" || warn "  ⚠️  /etc/apt"

# ══════════════════════════════════════════════════════════════════════════════
# C. PASANG IMMUTABLE FLAG PADA DIREKTORI SISTEM KRITIS
# ══════════════════════════════════════════════════════════════════════════════
PROTECTED_DIRS=(
    /bin /sbin
    /usr/bin /usr/sbin /usr/lib /usr/share
    /lib /lib64
    /etc
    /boot
)

log "Memasang proteksi immutable pada direktori sistem..."
for dir in "${PROTECTED_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        chattr -R +i "$dir" 2>/dev/null \
            && log "  ✅ Protected: $dir" \
            || warn "  ⚠️  Lewati: $dir"
    fi
done

# ══════════════════════════════════════════════════════════════════════════════
# D. PASTIKAN /root/project TETAP WRITABLE
# ══════════════════════════════════════════════════════════════════════════════
log "Memastikan workspace /root/project tetap writable..."
chattr -R -i /root/project 2>/dev/null || true
# Juga pastikan /tmp bisa ditulis (dibutuhkan banyak program)
chattr -R -i /tmp 2>/dev/null || true
log "  ✅ Workspace bebas ditulis: /root/project"

# ══════════════════════════════════════════════════════════════════════════════
# E. VERIFIKASI BINARY KRITIS MASIH ADA
# ══════════════════════════════════════════════════════════════════════════════
log "Memeriksa integritas binary sistem..."
CRITICAL_BINS=(
    "/bin/bash"
    "/usr/bin/env"
    "/usr/bin/apt"
    "/usr/bin/apt-get"
    "/usr/bin/dpkg"
    "/usr/local/bin/code-server"
)
for bin in "${CRITICAL_BINS[@]}"; do
    [[ -f "$bin" ]] || die "Binary hilang: $bin — sistem mungkin rusak!"
done
log "  ✅ Semua binary kritis terverifikasi"

# ══════════════════════════════════════════════════════════════════════════════
# F. CHECKSUM SHA256 — deteksi modifikasi binary saat runtime
# ══════════════════════════════════════════════════════════════════════════════
CHECKSUM_FILE="/tmp/.guard_checksums"
if [[ ! -f "$CHECKSUM_FILE" ]]; then
    log "Membuat baseline checksum sistem..."
    sha256sum "${CRITICAL_BINS[@]}" > "$CHECKSUM_FILE" 2>/dev/null || true
    chmod 400 "$CHECKSUM_FILE"
    log "  ✅ Baseline checksum tersimpan"
else
    log "Memverifikasi checksum sistem..."
    if sha256sum -c "$CHECKSUM_FILE" --quiet 2>/dev/null; then
        log "  ✅ Checksum valid — tidak ada binary yang dimodifikasi"
    else
        die "Checksum TIDAK COCOK! Binary sistem telah diubah. Hentikan."
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# G. JALANKAN CODE-SERVER
# ══════════════════════════════════════════════════════════════════════════════
log "════════════════════════════════════════"
log "  Menjalankan code-server di port 6080"
log "  Workspace: /root/project"
log "════════════════════════════════════════"
exec code-server \
    --bind-addr 0.0.0.0:6080 \
    --auth none \
    --disable-telemetry \
    --disable-update-check \
    /root/project
ENTRYPOINT

# Pastikan entrypoint bisa dieksekusi
RUN chmod 700 /usr/local/sbin/docker-entrypoint.sh

# ══════════════════════════════════════════════════════════════════════════════
# 5. KONFIGURASI TAMBAHAN: batasi shell history agar tidak menyimpan perintah
#    yang berpotensi berbahaya ke disk di luar workspace
# ══════════════════════════════════════════════════════════════════════════════
RUN echo 'export HISTFILE=/root/project/.bash_history' >> /root/.bashrc \
    && echo 'export HISTSIZE=1000'                     >> /root/.bashrc \
    && echo 'export HISTCONTROL=ignoredups:erasedups'  >> /root/.bashrc

# ══════════════════════════════════════════════════════════════════════════════
# 6. EXPOSE & CMD
# ══════════════════════════════════════════════════════════════════════════════
EXPOSE 6080

# Tetap root, tapi dijaga oleh entrypoint
USER root

CMD ["/usr/local/sbin/docker-entrypoint.sh"]
