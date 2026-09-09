#!/bin/sh
# Construye repo/pince-apt_<ver>_all.deb (el paquete bootstrap que da de alta
# el repositorio remoto en apt) si esa version aun no esta empaquetada, y
# poda versiones antiguas del bootstrap.
set -eu
cd "$(dirname "$0")"

ver="$(sed -n 's/^Version: //p' src/DEBIAN/control)"
out="repo/pince-apt_${ver}_all.deb"
mkdir -p repo

for old in repo/pince-apt_*_all.deb; do
    [ -e "$old" ] || continue
    [ "$old" = "$out" ] || { rm -f "$old"; echo "build.sh: podado $old"; }
done
if [ -e "$out" ]; then
    echo "build.sh: $out ya existe."
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -a src/. "$work/"
chmod 644 "$work/DEBIAN/control" "$work/DEBIAN/conffiles" \
          "$work/etc/apt/sources.list.d/pince.sources"

dpkg-deb --root-owner-group -b "$work" "$out" >/dev/null
echo "build.sh: construido $out"
