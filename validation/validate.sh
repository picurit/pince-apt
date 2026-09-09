#!/bin/sh
# Validacion completa de la capa de compatibilidad SIN tocar el sistema:
# construye los paquetes, genera el repo local en un sandbox de /tmp y hace
# que un apt totalmente aislado (Dir= redirigido) lo consuma y simule
# instalaciones. No requiere root y no deja rastro fuera del sandbox.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d /tmp/pince-apt-validate.XXXXXX)"
echo "Sandbox: $SB"

echo
echo "== 0. sintaxis de todos los scripts sh =="
for f in "$here/build.sh" \
         "$here/src/DEBIAN/postinst" "$here/src/DEBIAN/postrm" \
         "$here"/src/usr/lib/pince-apt/* \
         "$here/src/usr/share/pince-apt/template/DEBIAN/postinst" \
         "$here/src/usr/share/pince-apt/template/DEBIAN/postrm" \
         "$here/src/usr/share/pince-apt/template/usr/bin/pince"; do
    sh -n "$f"
done
echo "OK"

echo
echo "== 1. build del paquete pince-apt =="
sh "$here/build.sh"
deb="$(ls "$here"/dist/pince-apt_*_all.deb | sort -V | tail -1)"
dpkg-deb --info "$deb"
dpkg-deb --contents "$deb" | awk '{print $1, $NF}'

echo
echo "== 2. repo local en sandbox con releases reales de GitHub =="
export PINCE_APT_STATE="$SB/state"
export PINCE_APT_LIB="$here/src/usr/lib/pince-apt"
export PINCE_APT_TEMPLATE="$here/src/usr/share/pince-apt/template"
export PINCE_APT_KEEP="${PINCE_APT_KEEP:-2}"
mkdir -p "$PINCE_APT_STATE/repo"
sh "$PINCE_APT_LIB/refresh-repo" --bootstrap
cp "$deb" "$PINCE_APT_STATE/repo/"   # para que la dependencia pince-apt resuelva
sh "$PINCE_APT_LIB/gen-packages"
ls -la "$PINCE_APT_STATE/repo/"
echo "--- Release ---"
cat "$PINCE_APT_STATE/repo/Release"

echo
echo "== 3. un apt aislado consume el repo =="
R="$SB/aptroot"
mkdir -p "$R/etc/apt/sources.list.d" "$R/etc/apt/apt.conf.d" "$R/etc/apt/preferences.d" \
         "$R/var/lib/apt/lists/partial" "$R/var/cache/apt/archives/partial" "$R/var/lib/dpkg" \
         "$R/var/log/apt"
: > "$R/etc/apt/sources.list"
# estado dpkg real (solo lectura) para que curl/ca-certificates resuelvan
cp /var/lib/dpkg/status "$R/var/lib/dpkg/status"
cat > "$R/etc/apt/sources.list.d/pince.sources" <<EOF
Types: deb
URIs: file://$PINCE_APT_STATE/repo
Suites: ./
Trusted: yes
EOF
# APT_CONFIG aisla por completo: apt no lee /etc/apt del sistema (ni sus hooks)
cat > "$R/apt.conf" <<EOF
Dir "$R";
Dir::State::status "$R/var/lib/dpkg/status";
EOF
export APT_CONFIG="$R/apt.conf"

apt-get update
echo "--- apt policy pince (listado de versiones disponibles) ---"
apt-cache policy pince
echo "--- simulacion: apt install pince ---"
apt-get install --simulate pince
older="$(grep -B0 '^Package: pince$' -A2 "$PINCE_APT_STATE/repo/Packages" \
         | sed -n 's/^Version: //p' | sort -V | head -1)"
echo "--- simulacion: apt install pince=$older (version especifica) ---"
apt-get install --simulate "pince=$older"
unset APT_CONFIG

echo
echo "VALIDACION COMPLETA OK. Sandbox conservado para inspeccion en: $SB"
echo "Limpiar con: rm -rf $SB"
