# pince-apt — capa de compatibilidad apt para PINCE

Permite instalar, actualizar, versionar y **purgar** [PINCE](https://github.com/korcankaraokcu/PINCE)
(AppImage) usando exclusivamente las operaciones estándar de `apt`, sin emulación:
PINCE se convierte en un paquete deb real (`pince`) servido desde un repositorio
apt local que se sincroniza automáticamente con los releases de GitHub.

Validado el 2026-09-08 sobre KDE neon 24.04 (base Ubuntu noble).

## Arquitectura

Dos paquetes:

```
pince-apt (all, este repo lo construye)          pince (amd64, generado automáticamente)
├── /etc/apt/sources.list.d/pince.sources        ├── /usr/bin/pince (lanzador)
│     repo local file:///var/lib/pince-apt/repo  ├── /usr/share/applications/pince.desktop
├── /etc/apt/apt.conf.d/60pince-apt              ├── /usr/share/pince/release-tag
│     hook APT::Update::Pre-Invoke               ├── /opt/pince/ (dir propiedad del paquete)
└── /usr/lib/pince-apt/                          └── postinst: descarga el AppImage oficial
    ├── refresh-repo    (sincroniza con GitHub)        del tag, verifica su SHA-1 contra el
    ├── build-pince-deb (empaqueta un tag)             .zsync del release y lo deja en
    └── gen-packages    (metadatos del repo)           /opt/pince/PINCE-x86_64.AppImage
```

Flujo en cada `apt update`: el hook **Pre-Invoke** consulta el último release de
GitHub (una llamada a la API, con timeout y `|| true` para no romper apt nunca);
si hay tag nuevo, empaqueta un `pince_<ver>_amd64.deb` minúsculo (~2 KB) en
`/var/lib/pince-apt/repo` y regenera `Packages`/`Release`. Como corre *antes* de
que apt lea las listas, la nueva versión aparece como actualizable en ese mismo
`apt update`, y `apt upgrade` la instala como cualquier paquete (el postinst
descarga el AppImage nuevo, 200–400 MB, verificado por SHA-1).

## Instalación

```sh
./build.sh                                     # genera dist/pince-apt_1.0.0_all.deb
sudo apt install ./dist/pince-apt_1.0.0_all.deb
sudo apt update
sudo apt install pince
sudo apt-mark auto pince-apt                   # ver "Limpieza total" abajo
```

`pince` queda en el menú de aplicaciones y como comando `pince`.
El AppImage requiere una base ≥ Ubuntu 22.04 (requisito del upstream).

## Operaciones de apt mapeadas

| Operación | Efecto sobre PINCE |
|---|---|
| `apt update` | Sincroniza el repo local con los releases de GitHub |
| `apt list --upgradable` / `apt upgrade` | Muestra/instala la nueva versión de PINCE |
| `apt policy pince` / `apt list -a pince` | **Lista las versiones disponibles** (se conservan las 3 más recientes) |
| `apt install pince=0.10` | **Instala una versión específica** |
| `apt-mark hold pince` / `unhold` | **Fija/libera la versión** (pin nativo de apt) |
| `apt show pince` | Metadatos, homepage, descripción |
| `apt reinstall pince` | Reinstala; si el AppImage está intacto (SHA-1 ok) no re-descarga |
| `apt download pince` | Descarga el .deb del repo local |
| `apt purge / remove / autoremove / clean` | Limpieza (ver siguiente sección) |
| unattended-upgrades (opcional) | El repo publica `Origin: pince-apt`; basta permitir ese origen en `Unattended-Upgrade::Allowed-Origins` para actualizaciones desatendidas |

## Limpieza total: liberar apt de todo rastro

Pasos estándar, en orden:

```sh
sudo apt purge pince            # 1. la app: lanzador, .desktop, y su postrm borra
                                #    el AppImage/icono descargados y /opt/pince
sudo apt autoremove --purge     # 2. pince-apt cayó a "automático" (apt-mark auto de
                                #    la instalación) y ya nada depende de él: se purga
                                #    → hook, .sources y /var/lib/pince-apt desaparecen
sudo apt clean                  # 3. vacía la caché de .deb de apt (/var/cache/apt/archives)
```

Si no se hizo el `apt-mark auto`, el paso 2 es explícito: `sudo apt purge pince-apt`.

Verificación de que no queda rastro:

```sh
apt policy pince                              # "Unable to locate package"
ls /etc/apt/apt.conf.d/60pince-apt \
   /etc/apt/sources.list.d/pince.sources \
   /var/lib/pince-apt /opt/pince 2>&1         # todos: No such file or directory
```

Único resto (intencional, apt nunca toca `$HOME`): la configuración de usuario
de la app en `~/.config/PINCE` — borrar a mano si se desea.

Notas de semántica estándar respetada:
- `apt remove pince` (sin purge) borra la app y el AppImage pero conserva la
  infraestructura (`pince-apt`) por si se reinstala.
- `apt remove pince-apt` conserva conffiles y `/var/lib/pince-apt` (datos solo
  se borran en purge, como cualquier paquete Debian).

## Validación sin tocar el sistema

```sh
sh validation/validate.sh
```

Construye ambos paquetes, genera el repo local en un sandbox de `/tmp` con
releases reales de GitHub y hace que un apt totalmente aislado (`APT_CONFIG`
redirigido) lo consuma: `apt update`, `apt policy pince` (lista de versiones),
`apt install --simulate pince` y `pince=<versión-antigua>`. No requiere root.

`validation/extract_updinfo.py` es la evidencia de la sesión de análisis: extrae
por HTTP-Range la sección ELF `.upd_info` del AppImage publicado y demuestra que
embebe `gh-releases-zsync|korcankaraokcu|PINCE|latest|PINCE-x86_64.AppImage.zsync`.

Más contexto de diseño y hallazgos: [docs/DESIGN.md](docs/DESIGN.md).
