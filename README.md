# pince-apt — repositorio apt de PINCE servido desde GitHub

Convierte [PINCE](https://github.com/korcankaraokcu/PINCE) (AppImage) en un
paquete deb real servido desde un **repositorio apt alojado en este mismo repo
de GitHub** (`repo/`, vía `raw.githubusercontent.com`) y sincronizado
automáticamente con los releases oficiales por GitHub Actions. Instalar,
actualizar, listar versiones, fijar y purgar PINCE son operaciones nativas de
apt en cualquier dispositivo Debian/Ubuntu (base ≥ 22.04, requisito del
AppImage upstream).

## Uso desde cualquier dispositivo

```sh
curl -fsSLo /tmp/pince-apt.deb \
  https://raw.githubusercontent.com/picurit/pince-apt/main/repo/pince-apt_2.0.0_all.deb
sudo apt install /tmp/pince-apt.deb     # da de alta el repositorio en apt
sudo apt update
sudo apt install pince
sudo apt-mark auto pince-apt            # habilita la cascada de autoremove (ver Limpieza)
```

Equivalente manual, sin el bootstrap (los archivos de este repo bastan):

```sh
sudo tee /etc/apt/sources.list.d/pince.sources >/dev/null <<'EOF'
Types: deb
URIs: https://raw.githubusercontent.com/picurit/pince-apt/main/repo
Suites: ./
Trusted: yes
EOF
sudo apt update && sudo apt install pince
```

## Cómo funciona

```
GitHub Actions (cron 6h / push / manual)          Cliente (cualquier dispositivo)
┌──────────────────────────────────────┐          ┌────────────────────────────────┐
│ tools/update-repo.sh                 │          │ apt update                     │
│  ├ refresh-repo: empaqueta los tags  │  push    │  └ lee repo/ por HTTPS         │
│  │  nuevos de PINCE (deb ~2 KB)      │ ───────► │ apt install/upgrade pince      │
│  ├ build.sh: bootstrap pince-apt     │  repo/   │  └ postinst descarga el        │
│  └ gen-packages: Packages + Release  │          │    AppImage oficial del tag y  │
│ validation/validate.sh (pre-publish) │          │    verifica su SHA-1 (.zsync)  │
└──────────────────────────────────────┘          └────────────────────────────────┘
```

- `repo/` es un repositorio apt plano versionado en git: los `.deb` de `pince`
  (~2 KB cada uno, los 3 releases más recientes), el bootstrap `pince-apt`, y
  los metadatos `Packages`/`Packages.gz`/`Release`.
- El `.deb` de `pince` no contiene el AppImage: su postinst lo descarga del
  release oficial de GitHub del tag exacto y lo verifica contra el `SHA-1:` del
  `.zsync` publicado en ese release, dejándolo en `/opt/pince/`. Idempotente:
  si el AppImage local ya coincide, no re-descarga.
- El workflow [.github/workflows/apt-repo.yml](.github/workflows/apt-repo.yml)
  corre cada 6 horas (y en cada push relevante): solo empaqueta lo que falta
  (los bytes de los .deb existentes nunca cambian), valida el repo con un apt
  aislado y commitea `repo/` únicamente si hubo cambios.

## Operaciones de apt (todas validadas)

| Operación | Efecto |
|---|---|
| `apt update` | Refresca el índice del repo remoto |
| `apt policy pince` / `apt list -a pince` | **Lista las versiones disponibles** |
| `apt install pince` | Instala la última (resuelve `pince-apt` como dependencia) |
| `apt install pince=0.9.3` | **Instala una versión específica** |
| `apt list --upgradable` / `apt upgrade` | Muestra/aplica la actualización |
| `apt-mark hold pince` / `unhold` | **Fija/libera la versión** (pin nativo) |
| `apt show pince` | Metadatos y descripción |
| `apt download pince` | Descarga el .deb |
| `apt reinstall pince` | Reinstala (sin re-descargar el AppImage si está íntegro) |
| `apt purge / autoremove / clean` | Limpieza total (siguiente sección) |
| unattended-upgrades (opcional) | Permitir `Origin: pince-apt` en `Allowed-Origins` |

`validation/validate.sh` ejercita todas ellas contra un apt totalmente aislado
(`APT_CONFIG` + `DPKG_ADMINDIR` redirigidos, sin root): en local sirviendo
`./repo` por HTTP real, y con `--remote` contra la URL pública de GitHub — la
prueba de "cualquier otro dispositivo". Las operaciones que mutan el sistema se
validan con `--simulate` sobre un estado dpkg de prueba.

## Limpieza total: liberar apt de todo rastro

```sh
sudo apt purge pince            # 1. app: lanzador, .desktop; su postrm borra el
                                #    AppImage/icono descargados y /opt/pince
sudo apt autoremove --purge     # 2. purga pince-apt huérfano (tras el apt-mark
                                #    auto de la instalación) → borra el .sources
sudo apt clean                  # 3. vacía la caché de .deb de apt
```

Sin el `apt-mark auto`, el paso 2 es explícito: `sudo apt purge pince-apt`.
Verificación: `apt policy pince` → "Unable to locate";
`ls /etc/apt/sources.list.d/pince.sources /opt/pince` → "No such file".
Único resto intencional: `~/.config/PINCE` (apt nunca toca `$HOME`).

## Desarrollo

```sh
tools/update-repo.sh          # sincroniza ./repo con los releases (idempotente)
validation/validate.sh        # valida ./repo por HTTP local
validation/validate.sh --remote   # valida el repo ya publicado en GitHub
```

`validation/extract_updinfo.py` documenta el análisis original del AppImage
(sección ELF `.upd_info` extraída por HTTP-Range). Diseño, decisiones y
límites: [docs/DESIGN.md](docs/DESIGN.md).

## Nota de seguridad

El origen se declara `Trusted: yes` sobre HTTPS: apt verifica los hashes SHA256
de `Packages` y de cada `.deb`, y el postinst verifica el AppImage con el SHA-1
del release oficial, pero el repositorio no está firmado con GPG. Para
endurecerlo: generar una clave, firmar `Release` (`gpg --clearsign` →
`InRelease`) en el workflow con la clave privada en un secret de Actions, servir
la pública en el repo y cambiar `Trusted: yes` por `Signed-By:` en el
`.sources`. Está descrito como mejora en docs/DESIGN.md.
