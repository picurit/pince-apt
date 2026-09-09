#!/bin/sh
# Reconstruye repo/ de forma idempotente: solo empaqueta lo que falta y solo
# regenera metadatos si el conjunto de .deb cambio. Asi los bytes de los .deb
# existentes nunca cambian entre ejecuciones (dpkg-deb no es reproducible) y
# el cron de GitHub Actions no produce commits vacios.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

mkdir -p "$root/repo"
before="$(ls -1 "$root/repo" 2>/dev/null | sort)"

"$here/refresh-repo"      # paquetes pince de los ultimos releases
sh "$root/build.sh"       # paquete bootstrap pince-apt

after="$(ls -1 "$root/repo" | sort)"
if [ "$before" != "$after" ] || [ ! -f "$root/repo/Packages" ]; then
    "$here/gen-packages"
else
    echo "update-repo: sin cambios."
fi
