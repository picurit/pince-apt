#!/bin/sh
# Valida el repositorio apt SIN tocar el sistema y sin necesitar root.
#
#   validation/validate.sh            valida ./repo servido por HTTP local
#                                     (mismo transporte que usa un cliente real)
#   validation/validate.sh --remote   valida el repo publicado en GitHub
#                                     (raw.githubusercontent.com), como lo
#                                     veria cualquier otro dispositivo
#
# Ejercita las operaciones de apt: update, policy, show, install (y version
# especifica), download, list --upgradable, upgrade, hold/unhold, purge y
# autoremove --purge (las que mutan el sistema, en modo --simulate contra un
# estado dpkg de prueba). Requiere haber corrido tools/update-repo.sh antes
# en modo local.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d /tmp/pince-apt-validate.XXXXXX)"
SRV_PID=""
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null || true; }
trap cleanup EXIT
echo "Sandbox: $SB"

fail() { echo "FALLO: $*" >&2; exit 1; }

# ---------------------------------------------------------------- origen apt
if [ "${1:-}" = "--remote" ]; then
    BASE_URI="https://raw.githubusercontent.com/picurit/pince-apt/main/repo"
    echo "Modo remoto: $BASE_URI"
else
    [ -f "$here/repo/Packages" ] || fail "no existe repo/Packages; corre tools/update-repo.sh"
    PORT=8931
    ( cd "$here/repo" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 ) >/dev/null 2>&1 &
    SRV_PID=$!
    sleep 1
    kill -0 "$SRV_PID" 2>/dev/null || fail "no se pudo servir repo/ en el puerto $PORT"
    BASE_URI="http://127.0.0.1:$PORT"
    echo "Modo local: sirviendo ./repo en $BASE_URI (transporte HTTP real)"
fi

# ------------------------------------------------- apt aislado via APT_CONFIG
R="$SB/aptroot"
mkdir -p "$R/etc/apt/sources.list.d" "$R/etc/apt/apt.conf.d" "$R/etc/apt/preferences.d" \
         "$R/var/lib/apt/lists/partial" "$R/var/cache/apt/archives/partial" \
         "$R/var/lib/dpkg" "$R/var/log/apt"
: > "$R/etc/apt/sources.list"
cp /var/lib/dpkg/status "$R/var/lib/dpkg/status"   # curl/ca-certificates resuelven
cat > "$R/etc/apt/sources.list.d/pince.sources" <<EOF
Types: deb
URIs: $BASE_URI
Suites: ./
Trusted: yes
EOF
cat > "$R/apt.conf" <<EOF
Dir "$R";
Dir::State::status "$R/var/lib/dpkg/status";
EOF
export APT_CONFIG="$R/apt.conf"
# apt-mark hold delega en 'dpkg --set-selections', que no lee APT_CONFIG:
# se le redirige su base de datos al sandbox via variable de entorno
export DPKG_ADMINDIR="$R/var/lib/dpkg"

echo
echo "== apt update =="
apt-get update

echo
echo "== apt policy pince (listado de versiones) =="
apt-cache policy pince | tee "$SB/policy.txt"
grep -q 'Candidate: [0-9]' "$SB/policy.txt" || fail "sin candidato para pince"
newest="$(sed -n 's/^  Candidate: //p' "$SB/policy.txt")"
older="$(grep -oE '^     [0-9][^ ]*' "$SB/policy.txt" | tr -d ' ' | sort -V | head -1)"
echo "(mas reciente: $newest; mas antigua publicada: $older)"

echo
echo "== apt show pince =="
apt-cache show pince | head -12

echo
echo "== simulacion: apt install pince =="
apt-get install --simulate pince | grep -E '^(Inst|Conf)' | tee "$SB/inst.txt"
grep -q "^Inst pince-apt " "$SB/inst.txt" || fail "no resuelve la dependencia pince-apt"
grep -q "^Inst pince ($newest" "$SB/inst.txt" || fail "no instala la version candidata"

echo
echo "== simulacion: apt install pince=$older (version especifica) =="
apt-get install --simulate "pince=$older" | grep -E "^Inst pince \($older" \
    || fail "no instala la version especifica"

echo
echo "== apt download pince (descarga real del .deb) =="
( cd "$SB" && apt-get download pince >/dev/null 2>&1 || apt-get -o Debug::NoLocking=1 download pince )
deb="$(ls "$SB"/pince_*.deb | head -1)"
dpkg-deb --info "$deb" | grep -E '^ (Package|Version):'

# ------------------- estado simulado: pince (version antigua) ya instalado --
fake_status() { # $1: incluir pince (yes/no)
    cp /var/lib/dpkg/status "$R/var/lib/dpkg/status"
    if [ "$1" = yes ]; then
        cat >> "$R/var/lib/dpkg/status" <<EOF

Package: pince
Status: install ok installed
Priority: optional
Section: devel
Maintainer: validacion
Architecture: amd64
Version: $older
Depends: pince-apt, curl, ca-certificates
Description: instalado simulado para validacion
EOF
    fi
    cat >> "$R/var/lib/dpkg/status" <<EOF

Package: pince-apt
Status: install ok installed
Priority: optional
Section: admin
Maintainer: validacion
Architecture: all
Version: 2.0.0
Depends: ca-certificates
Description: instalado simulado para validacion
EOF
}

echo
echo "== con pince $older 'instalado': apt list --upgradable =="
fake_status yes
apt list --upgradable 2>/dev/null | tee "$SB/upg.txt"
grep -q "^pince/" "$SB/upg.txt" || fail "pince no aparece como actualizable"

echo
echo "== simulacion: apt upgrade =="
apt-get upgrade --simulate | grep -E "^Inst pince \[$older\] \($newest" \
    || fail "upgrade no propone $older -> $newest"
echo "upgrade propone pince $older -> $newest: OK"

echo
echo "== apt-mark hold pince (pin) y upgrade retenido =="
apt-mark hold pince
apt-get upgrade --simulate | tee "$SB/hold.txt" | grep -E '(retenidos|kept back)' || true
if grep -qE "^Inst pince " "$SB/hold.txt"; then fail "hold no retuvo pince"; fi
echo "con hold, upgrade NO toca pince: OK"
apt-mark unhold pince
apt-get upgrade --simulate | grep -qE "^Inst pince " || fail "unhold no libero pince"
echo "con unhold, upgrade vuelve a proponerlo: OK"

echo
echo "== simulacion: apt purge pince =="
apt-get purge --simulate pince | grep -E '^Purg pince' || fail "purge no propone Purg"

echo
echo "== simulacion: apt autoremove --purge (cascada sobre pince-apt) =="
fake_status no                      # pince ya no esta; pince-apt quedo huerfano
apt-mark auto pince-apt >/dev/null
apt-get autoremove --purge --simulate | grep -E '^Purg pince-apt' \
    || fail "autoremove no purga pince-apt huerfano"
echo "autoremove --purge elimina pince-apt: OK"

echo
echo "VALIDACION COMPLETA OK ($BASE_URI)"
echo "Sandbox conservado en: $SB (limpiar con rm -rf)"
