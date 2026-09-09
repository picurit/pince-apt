#!/bin/sh
# Construye dist/pince-apt_<ver>_all.deb a partir de src/
set -eu
cd "$(dirname "$0")"

ver="$(sed -n 's/^Version: //p' src/DEBIAN/control)"
mkdir -p dist

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -a src/. "$work/"

chmod 755 "$work/DEBIAN/postinst" "$work/DEBIAN/postrm" \
          "$work/usr/lib/pince-apt/refresh-repo" \
          "$work/usr/lib/pince-apt/build-pince-deb" \
          "$work/usr/lib/pince-apt/gen-packages" \
          "$work/usr/share/pince-apt/template/DEBIAN/postinst" \
          "$work/usr/share/pince-apt/template/DEBIAN/postrm" \
          "$work/usr/share/pince-apt/template/usr/bin/pince"
chmod 644 "$work/DEBIAN/control" "$work/DEBIAN/conffiles" \
          "$work/etc/apt/apt.conf.d/60pince-apt" \
          "$work/etc/apt/sources.list.d/pince.sources"

dpkg-deb --root-owner-group -b "$work" "dist/pince-apt_${ver}_all.deb"
echo "Construido: dist/pince-apt_${ver}_all.deb"
