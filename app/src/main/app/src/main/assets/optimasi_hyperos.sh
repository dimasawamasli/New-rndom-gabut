#!/system/bin/sh
# ==============================================================
#  TECHMODWARE OPTIMIZER v2
#  Dijalankan lewat Shizuku (hak akses shell/ADB), contoh:
#    sh -c "<isi file ini>" techmodware selfpkg=PAKET FITUR [ARGUMEN]
#
#  Fitur:
#    info      info perangkat
#    all       hz + perf + ppa + batt + net + gm + otg
#    max       INJECT: all + animasi mati + render lebih rendah + clean + optimasi ART
#    hz        kunci refresh rate ke maksimum
#    perf      mode performa, notifikasi pop-up off, animasi cepat
#    ppa       matikan Phantom Process Killer + app freezer
#    batt      bebaskan batasan baterai app game & tools
#    net       Wi-Fi mode latensi rendah
#    gm        Game Mode Free Fire (performance + turunkan render)
#    otg       pengaturan OTG + keyboard/mouse fisik
#    clean     hentikan app latar & kosongkan RAM
#    debloat   nonaktifkan bloatware Xiaomi (bisa dikembalikan)
#    launch P  buka aplikasi dengan nama paket P
#    revert    kembalikan SEMUA ke nilai asli
#
#  Semua pesan memakai ASCII murni supaya aman di semua ROM.
# ==============================================================

exec 2>&1
exec </dev/null

STATE="${TMW_STATE:-/data/local/tmp/techmodware.state}"
DEBLOAT_STATE="${STATE}.debloat"

# ---- Pengaturan (boleh diubah) --------------------------------
GAME_PKGS="com.dts.freefireth com.dts.freefiremax"
KEYWORDS="ggmouse redcorner gamespace ggspace sensix nebula mobilador"
SHIZUKU_PKG="moe.shizuku.privileged.api"
GM_DOWNSCALE="0.8"
DEBLOAT_LIST="com.miui.analytics com.miui.msa.global com.miui.systemAdSolution com.xiaomi.mipicks com.miui.hybrid com.miui.bugreport com.miui.miservice com.facebook.appmanager com.facebook.services com.facebook.system com.netflix.partner.activation com.miui.videoplayer com.miui.player"
# ---------------------------------------------------------------

hdr()  { echo "== $1 =="; }
ok()   { echo "[OK] $1"; }
warn() { echo "[!] $1"; }
err()  { echo "[X] $1"; }
note() { echo "    $1"; }
quiet() { "$@" >/dev/null 2>&1; }
step() {
  desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else warn "$desc (tidak didukung ROM ini)"; fi
}

SDK=$(getprop ro.build.version.sdk 2>/dev/null)
[ -n "$SDK" ] || SDK=0
SELF=""
ALLPKGS=""

need_pkgs() {
  [ -n "$ALLPKGS" ] || ALLPKGS=$(pm list packages 2>/dev/null | sed 's/^package://')
}

has_pkg() {
  need_pkgs
  echo "$ALLPKGS" | grep -qx "$1"
}

# ---- Simpan nilai asli supaya revert 100% akurat ---------------
remember() {
  grep -q "^$1|$2|" "$STATE" 2>/dev/null && return 0
  cur=$(settings get "$1" "$2" 2>/dev/null)
  [ -n "$cur" ] || cur=null
  echo "$1|$2|$cur" >> "$STATE" 2>/dev/null
  return 0
}

sput() {
  remember "$1" "$2"
  settings put "$1" "$2" "$3" >/dev/null 2>&1
}

restore_settings() {
  if [ ! -f "$STATE" ]; then
    note "Belum ada catatan nilai asli (tidak ada yang perlu dikembalikan)"
    return 0
  fi
  n=0
  while IFS='|' read -r ns key val; do
    [ -n "$ns" ] || continue
    if [ "$val" = "null" ]; then
      settings delete "$ns" "$key" >/dev/null 2>&1 </dev/null
    else
      settings put "$ns" "$key" "$val" >/dev/null 2>&1 </dev/null
    fi
    n=$((n + 1))
  done < "$STATE"
  rm -f "$STATE"
  ok "$n pengaturan dikembalikan ke nilai asli"
}

# ---- Utilitas --------------------------------------------------
max_hz() {
  best=0
  for v in $(dumpsys display 2>/dev/null | grep -o 'fps=[0-9.]*' | cut -d= -f2); do
    i=${v%%.*}
    case "$i" in ''|*[!0-9]*) continue ;; esac
    f=${v#*.}
    [ "$f" = "$v" ] && f=0
    d=${f%"${f#?}"}
    case "$d" in ''|*[!0-9]*) d=0 ;; esac
    [ "$d" -ge 5 ] && i=$((i + 1))
    if [ "$i" -gt "$best" ] && [ "$i" -le 240 ]; then best=$i; fi
  done
  echo "$best"
}

mem_avail() {
  v=$(grep MemAvailable /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
  echo $(( ${v:-0} / 1024 ))
}

mem_total() {
  v=$(grep MemTotal /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
  echo $(( ${v:-0} / 1024 ))
}

batt_targets() {
  need_pkgs
  OUT=""
  for p in $GAME_PKGS $SHIZUKU_PKG $SELF; do
    [ -n "$p" ] || continue
    echo "$ALLPKGS" | grep -qx "$p" && OUT="$OUT $p"
  done
  for kw in $KEYWORDS; do
    for p in $(echo "$ALLPKGS" | grep -i "$kw"); do OUT="$OUT $p"; done
  done
  echo "$OUT" | tr ' ' '\n' | grep -v '^$' | sort -u
}

# ---- Fitur -----------------------------------------------------
do_info() {
  hdr "Info Perangkat"
  echo "Perangkat : $(getprop ro.product.brand) $(getprop ro.product.model)"
  OSV=$(getprop ro.mi.os.version.name)
  [ -n "$OSV" ] || OSV=$(getprop ro.miui.ui.version.name)
  echo "Android   : $(getprop ro.build.version.release) (SDK $SDK) ${OSV}"
  echo "Chipset   : $(getprop ro.board.platform) / $(getprop ro.product.cpu.abi)"
  echo "RAM       : $(mem_avail) MB bebas dari $(mem_total) MB"
  PHYS=$(wm size 2>/dev/null | grep -i physical | grep -o '[0-9]*x[0-9]*' | head -n 1)
  echo "Layar     : ${PHYS:-?} / maks $(max_hz) Hz"
  B=$(dumpsys battery 2>/dev/null)
  LV=$(echo "$B" | grep -m1 'level:' | tr -dc '0-9')
  TP=$(echo "$B" | grep -m1 'temperature:' | tr -dc '0-9')
  TP=${TP:-0}
  echo "Baterai   : ${LV:-?}% / $((TP / 10)).$((TP % 10)) C"
  echo "Shizuku   : uid $(id -u 2>/dev/null)"
}

do_hz() {
  hdr "Kunci Refresh Rate"
  HZ=$(max_hz)
  if [ "$HZ" -lt 30 ]; then
    warn "Refresh rate maksimum tidak terdeteksi - dilewati (supaya Hz tidak malah turun)"
    return
  fi
  note "Maksimum terdeteksi: ${HZ} Hz"
  sput system min_refresh_rate "${HZ}.0"
  sput system peak_refresh_rate "${HZ}.0"
  sput system user_refresh_rate "$HZ"
  sput system miui_refresh_rate "$HZ"
  sput secure miui_refresh_rate "$HZ"
  ok "Refresh rate dikunci di ${HZ} Hz"
}

do_perf() {
  hdr "Mode Performa"
  step "Fixed performance mode" cmd power set-fixed-performance-mode-enabled true
  sput global low_power 0
  sput global low_power_sticky 0
  sput global adaptive_battery_management_enabled 0
  sput global dynamic_power_savings_enabled 0
  ok "Hemat daya dimatikan"
  sput global heads_up_notifications_enabled 0
  ok "Notifikasi pop-up dimatikan (anti ganggu saat main)"
  AN=0.5
  [ "$1" = max ] && AN=0
  sput global window_animation_scale "$AN"
  sput global transition_animation_scale "$AN"
  sput global animator_duration_scale "$AN"
  if [ "$AN" = 0 ]; then ok "Animasi sistem dimatikan total"; else ok "Animasi sistem dipercepat 2x"; fi
}

do_ppa() {
  hdr "Anti-Kill (Phantom Process Killer)"
  if [ "$SDK" -ge 31 ]; then
    step "Sinkronisasi device_config dibekukan" device_config set_sync_disabled_for_tests persistent
    step "Batas phantom process dibuka" device_config put activity_manager max_phantom_processes 2147483647
    step "Monitor phantom process dimatikan" device_config put activity_manager settings_enable_monitor_phantom_procs false
    sput global settings_enable_monitor_phantom_procs false
    step "App freezer dimatikan" device_config put activity_manager_native_boot use_freezer false
    sput global cached_apps_freezer disabled
    ok "Proses latar (game, tools) tidak mudah dibunuh sistem"
  else
    warn "PPK hanya ada di Android 12+ (SDK 31), dilewati"
  fi
}

do_batt() {
  hdr "Bebas Batasan Baterai"
  T=$(batt_targets)
  if [ -z "$T" ]; then
    warn "Tidak ada app game/tools yang cocok ditemukan"
    return
  fi
  for p in $T; do
    quiet dumpsys deviceidle whitelist +"$p"
    quiet cmd appops set "$p" RUN_IN_BACKGROUND allow
    quiet cmd appops set "$p" RUN_ANY_IN_BACKGROUND allow
    quiet cmd appops set "$p" WAKE_LOCK allow
    quiet cmd appops set "$p" START_FOREGROUND allow
    quiet am set-standby-bucket "$p" active
    ok "Bebas batasan: $p"
  done
}

do_net() {
  hdr "Jaringan Latensi Rendah"
  step "Wi-Fi low-latency mode" cmd wifi force-low-latency-mode enabled
  step "Wi-Fi high-performance mode" cmd wifi force-hi-perf-mode enabled
}

do_gm() {
  hdr "Game Mode Free Fire"
  DS="${1:-$GM_DOWNSCALE}"
  FOUND=0
  for p in $GAME_PKGS; do
    has_pkg "$p" || continue
    FOUND=1
    if quiet cmd game set --mode performance --downscale "$DS" "$p"; then
      ok "$p: performance + render ${DS}x"
    elif quiet cmd game mode performance "$p"; then
      ok "$p: mode performance (turun render tidak didukung)"
    else
      warn "$p: Game Mode tidak didukung ROM ini"
    fi
  done
  [ "$FOUND" = 1 ] || warn "Free Fire belum terpasang"
}

do_otg() {
  hdr "OTG, Keyboard & Mouse"
  sput global otg_enable 1
  sput global otg_auto_disable 0
  sput secure otg_enabled 1
  sput global usb_otg_enable 1
  sput secure show_ime_with_hard_keyboard 0
  ok "Pengaturan OTG dikirim (hasil tergantung ROM)"
  ok "Keyboard layar tidak muncul saat keyboard fisik terpasang"
}

do_clean() {
  hdr "Bersihkan RAM"
  BEFORE=$(mem_avail)
  IME=$(settings get secure default_input_method 2>/dev/null)
  IME=${IME%%/*}
  HOMEP=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
  HOMEP=${HOMEP%%/*}
  IMES=$(ime list -s 2>/dev/null | sed 's#/.*##')
  PROTECT="$SELF $SHIZUKU_PKG $GAME_PKGS $IME $IMES $HOMEP $(batt_targets)"
  N=0
  for p in $(pm list packages -3 2>/dev/null | sed 's/^package://'); do
    SKIP=0
    for q in $PROTECT; do
      if [ "$q" = "$p" ]; then SKIP=1; break; fi
    done
    [ "$SKIP" = 1 ] && continue
    if am force-stop "$p" >/dev/null 2>&1; then N=$((N + 1)); fi
  done
  quiet am kill-all
  AFTER=$(mem_avail)
  ok "$N aplikasi dihentikan"
  note "RAM bebas: ${BEFORE} MB -> ${AFTER} MB"
}

do_debloat() {
  hdr "Debloat Xiaomi"
  N=0
  for p in $DEBLOAT_LIST; do
    has_pkg "$p" || continue
    if pm disable-user --user 0 "$p" >/dev/null 2>&1; then
      ok "Dinonaktifkan: $p"
      echo "$p" >> "$DEBLOAT_STATE" 2>/dev/null
      N=$((N + 1))
    else
      warn "Ditolak sistem: $p"
    fi
  done
  if [ "$N" = 0 ]; then
    note "Tidak ada bloatware dari daftar yang bisa dinonaktifkan"
  else
    note "Bisa dikembalikan lewat tombol Kembalikan Semua"
  fi
}

do_dexopt() {
  hdr "Optimasi ART Game"
  FOUND=0
  for p in $GAME_PKGS; do
    has_pkg "$p" || continue
    FOUND=1
    note "Mengompilasi $p (bisa 10-40 detik)..."
    if command -v timeout >/dev/null 2>&1; then
      timeout 45 cmd package compile -m speed -f "$p" >/dev/null 2>&1
    else
      cmd package compile -m speed -f "$p" >/dev/null 2>&1
    fi
    case "$?" in
      0)   ok "$p: kode game dikompilasi penuh (loading lebih ringan)" ;;
      124) warn "$p: terlalu lama, dilewati (aman, coba lagi nanti)" ;;
      *)   warn "$p: optimasi ART tidak didukung ROM ini" ;;
    esac
  done
  [ "$FOUND" = 1 ] || warn "Free Fire belum terpasang"
}

do_max() {
  hdr "INJECT"
  note "Semua optimasi performa dijalankan sekaligus"
  do_hz
  do_perf max
  do_ppa
  do_batt
  do_net
  do_gm 0.7
  do_otg
  do_clean
  do_dexopt
  hdr "Inject selesai"
  ok "HP siap tempur. Ingat: lebih panas dan lebih boros baterai."
  note "Selesai main? Tekan Kembalikan Semua."
}

do_launch() {
  hdr "Buka Aplikasi"
  P="$1"
  if [ -z "$P" ]; then err "Nama paket kosong"; return; fi
  if has_pkg "$P"; then
    if quiet monkey -p "$P" -c android.intent.category.LAUNCHER 1; then ok "Membuka $P"; else err "Gagal membuka $P"; fi
  else
    warn "Aplikasi $P belum terpasang"
  fi
}

do_revert() {
  hdr "Kembalikan Semua"
  restore_settings
  if [ "$SDK" -ge 31 ]; then
    quiet device_config delete activity_manager max_phantom_processes
    quiet device_config delete activity_manager settings_enable_monitor_phantom_procs
    quiet device_config delete activity_manager_native_boot use_freezer
    quiet device_config set_sync_disabled_for_tests none
    ok "PPK dan app freezer kembali ke bawaan sistem"
  fi
  quiet cmd power set-fixed-performance-mode-enabled false
  quiet cmd wifi force-low-latency-mode disabled
  quiet cmd wifi force-hi-perf-mode disabled
  for p in $GAME_PKGS; do
    quiet cmd game reset "$p"
    quiet cmd game mode standard "$p"
  done
  ok "Mode performa, Wi-Fi, dan Game Mode dikembalikan"
  if [ -f "$DEBLOAT_STATE" ]; then
    for p in $(sort -u "$DEBLOAT_STATE"); do
      if pm enable --user 0 "$p" >/dev/null 2>&1; then ok "Diaktifkan lagi: $p"; else warn "Gagal mengaktifkan: $p"; fi
    done
    rm -f "$DEBLOAT_STATE"
  fi
}

# ---- Pengurai perintah ------------------------------------------
for a in "$@"; do
  case "$a" in selfpkg=*) SELF=${a#selfpkg=} ;; esac
done

[ $# -eq 0 ] && set -- info

while [ $# -gt 0 ]; do
  case "$1" in
    selfpkg=*) ;;
    info)     do_info ;;
    all)      do_hz; do_perf; do_ppa; do_batt; do_net; do_gm; do_otg ;;
    max)      do_max ;;
    dexopt)   do_dexopt ;;
    hz)       do_hz ;;
    perf)     do_perf ;;
    ppa)      do_ppa ;;
    batt)     do_batt ;;
    net)      do_net ;;
    gm)       do_gm ;;
    otg)      do_otg ;;
    clean)    do_clean ;;
    debloat)  do_debloat ;;
    launch)   shift; do_launch "$1" ;;
    revert)   do_revert ;;
    *)        warn "Fitur tidak dikenal: $1" ;;
  esac
  shift
done
echo "Selesai."
