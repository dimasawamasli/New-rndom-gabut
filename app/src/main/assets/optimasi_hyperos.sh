#!/system/bin/sh
# Optimasi HyperOS

echo "== 1. Matikan Phantom Process Killer =="
device_config set_sync_disabled_for_tests persistent
device_config put activity_manager max_phantom_processes 2147483647
settings put global settings_enable_monitor_phantom_procs false

echo "== 2. Kunci refresh rate ke maksimum =="
MAX=$(dumpsys display | grep -oE 'fps=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | sort -n | tail -1)
MAX=${MAX%%.*}
if [ -n "$MAX" ]; then
  echo "Refresh rate maksimum terdeteksi: ${MAX}Hz"
  settings put system min_refresh_rate "$MAX"
  settings put system peak_refresh_rate "$MAX"
  settings put system user_refresh_rate "$MAX"
else
  echo "Gagal mendeteksi refresh rate, dilewati."
fi

echo "== 3. Whitelist baterai =="
KEYWORDS="freefiremax ggmouse gamespace redcorner sensix nebula"
MANUAL=""

for kw in $KEYWORDS; do
  for pkg in $(pm list packages | grep -i "$kw" | cut -d: -f2); do
    MANUAL="$MANUAL $pkg"
  done
done

for pkg in $MANUAL; do
  echo "Whitelist: $pkg"
  dumpsys deviceidle whitelist +"$pkg" >/dev/null 2>&1
  cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow
  cmd appops set "$pkg" RUN_IN_BACKGROUND allow
done

echo "Selesai."
