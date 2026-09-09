# Diseño y hallazgos

Registro consolidado de la sesión de análisis/validación (2026-09-08, KDE neon
24.04 / Ubuntu noble) que llevó a esta capa de compatibilidad.

## Hallazgos sobre PINCE

- **Método de instalación recomendado por upstream: el AppImage oficial.**
  El `install.sh` del repo es solo para desarrollo. Release validado: v0.10.1
  (2026-08-08), `PINCE-x86_64.AppImage` de 210 MB. Requiere base ≥ Ubuntu 22.04.
- **El AppImage embebe información de actualización, no la herramienta.**
  Verificado a tres niveles: (1) `ci/package.sh` del upstream usa linuxdeploy con
  `LDAI_UPDATE_INFORMATION="gh-releases-zsync|korcankaraokcu|PINCE|latest|PINCE-x86_64.AppImage.zsync"`;
  (2) extracción por HTTP-Range de la sección ELF `.upd_info` del binario
  publicado (`validation/extract_updinfo.py`) — contiene exactamente esa cadena;
  (3) prueba de extremo a extremo con `appimageupdatetool` real: `-d` resuelve
  la URL del zsync y `-j` devuelve 0 (al día) / 1 (hay update).
- **Cada release publica su propio AppImage y `.zsync` desde v0.6** (verificado
  contra la API de releases y con HEAD a tags concretos), lo que habilita tanto
  la instalación de versiones específicas como la verificación por SHA-1 (el
  campo `SHA-1:` del `.zsync` del tag).

## Evolución del diseño

**v1 (descartada): hooks directos + appimageupdatetool.** Scripts en
`/opt/pince` con `APT::Update::Post-Invoke-Success` (chequeo con
`appimageupdatetool -j`) y `DPkg::Post-Invoke` (aplicación con `-O -r`).
Funcionaba (validado en sandbox), pero la transparencia era superficial: PINCE
no existía para dpkg — sin `apt purge`, sin `apt policy`, sin `apt-mark hold`,
y el manejo de versiones exigía tooling propio (`pince-version`).

**v2 (actual): PINCE como paquete deb desde un repo apt local.** El patrón es el
de `google-chrome-stable` (deb que instala en `/opt/<vendor>`) combinado con el
de los paquetes "installer" de Debian tipo `ttf-mscorefonts-installer` (postinst
descarga el blob externo y lo verifica). Con esto, cada operación de apt es
nativa, no mapeada:

- purge/remove/autoremove/clean → gestionadas por dpkg/apt con la semántica normal.
- listado de versiones → `apt policy` (el repo conserva los N=3 tags recientes).
- versión específica → `apt install pince=<ver>`.
- pin → `apt-mark hold` (desapareció el flag `pinned` casero de la v1).
- notificación de updates → `apt list --upgradable`, motd de update-notifier, etc.,
  gratis, porque el repo local es un origen apt más.

**v3 (actual): el repositorio apt vive en GitHub y lo mantiene Actions.**
Al publicarse el repo como `picurit/pince-apt`, el repositorio apt local de la
v2 se volvió innecesario: `repo/` se versiona en git y se sirve por
`raw.githubusercontent.com` (HTTPS, CDN con caché ~5 min), con lo que cualquier
dispositivo lo consume como un origen apt normal. Consecuencias:

- El hook cliente `APT::Update::Pre-Invoke` y los scripts instalados en
  `/usr/lib/pince-apt` desaparecen: la sincronización con los releases de
  PINCE ocurre una sola vez, en GitHub Actions (cron cada 6 h + push +
  manual), no en cada máquina. Los scripts pasaron a `tools/` como
  herramientas de CI/desarrollo.
- El paquete `pince-apt` (v2.0.0) queda reducido a un conffile: el `.sources`
  deb822 que da de alta el origen remoto. Sin postinst, sin estado en
  `/var/lib`. También puede prescindirse de él creando el `.sources` a mano.
- **Idempotencia del CI**: dpkg-deb no es reproducible byte a byte, así que
  `update-repo.sh` solo empaqueta versiones que faltan y solo regenera
  metadatos si el conjunto de .deb cambió. Los bytes publicados nunca se
  reescriben (los hashes que apt ya conoce siguen siendo válidos) y el cron
  no genera commits vacíos.
- El workflow valida el repo con `validation/validate.sh` (apt aislado,
  transporte HTTP real) antes de publicar cambios.

## Decisiones técnicas

- **El .deb de `pince` no embebe el AppImage** (~2 KB vs 210–390 MB): el
  postinst lo descarga del tag exacto y verifica el SHA-1 publicado en el
  `.zsync` de ese release. Idempotente: si el AppImage local ya coincide con el
  SHA-1, no re-descarga (hace `apt reinstall` barato). Consecuencia declarada en
  la descripción del paquete: `Installed-Size` no refleja el AppImage.
- **Repo plano con metadatos generados a mano** (`gen-packages`): solo dpkg-deb
  y coreutils, sin depender de `dpkg-dev`/`apt-utils`. Genera `Packages`,
  `Packages.gz` y un `Release` con SHA256; el origen se declara
  `Trusted: yes` en un `.sources` deb822 sobre HTTPS. apt sigue verificando
  los hashes SHA256 de las listas y de cada .deb; lo que falta es la firma
  GPG del `Release` (mejora descrita abajo).
- **`/opt/pince` propiedad del paquete, binarios en `/usr/bin`**: al ser ya un
  paquete de verdad, el lanzador va en `/usr/bin` (en la v1 iba en
  `/usr/local/bin`, correcto solo para instalaciones no empaquetadas). El
  AppImage y el icono no son ficheros propiedad de dpkg (los crea el postinst),
  por eso el postrm los borra explícitamente en remove y purge.
- **appimageupdatetool ya no es necesaria**: las actualizaciones fluyen por apt.
  Se pierde la actualización delta de zsync (cada upgrade descarga el AppImage
  completo), a cambio de transparencia total. El AppImage sigue embebiendo su
  update info por si alguien quiere usar la herramienta de forma independiente.
- **`--appimage-extract` / `APPIMAGE_EXTRACT_AND_RUN=1`** para operar sin FUSE
  cuando se corre como root (extracción del icono en postinst).

- **Revisiones de plantilla (`+pa<N>`)**: los .deb publicados son inmutables
  (idempotencia del CI), así que un arreglo en la plantilla del paquete
  (`package-template/`) no puede reescribirlos. En su lugar se incrementa
  `package-template/REVISION` y todos los tags se re-empaquetan como
  `<version>+pa<N>` — para dpkg `0.10.1+pa2 > 0.10.1`, con lo que el arreglo
  llega a los clientes como un upgrade normal de apt. La poda del repo elimina
  las revisiones superadas comparando por versión extraída, no por nombre de
  archivo (`_amd64` vs `+pa` invierte el orden en `sort -V`). Origen del
  esquema: la instalación real detectó que el icono raíz del AppImage es un
  symlink y el postinst extraía el enlace roto (corregido en pa2 extrayendo
  `usr/share/icons/hicolor/512x512/apps/PINCE.png`).

## Mejora futura: firma GPG

1. Generar una clave dedicada y guardar la privada como secret de Actions
   (`APT_SIGNING_KEY`).
2. En el workflow, tras `gen-packages`: `gpg --clearsign -o InRelease Release`
   y `gpg -abs -o Release.gpg Release`.
3. Publicar la clave pública como `repo/pince-apt-keyring.gpg`, instalarla
   desde el bootstrap en `/usr/share/keyrings/`, y sustituir `Trusted: yes`
   por `Signed-By: /usr/share/keyrings/pince-apt-keyring.gpg` en el `.sources`.

## Límites conocidos

- La API de GitHub sin autenticar limita a 60 peticiones/hora por IP; el hook
  hace 1 por `apt update` (más 1 por tag nuevo a empaquetar). De sobra.
- Un `apt update` sin red simplemente no refresca el repo local (el hook sale
  en silencio); apt sigue funcionando con las listas existentes.
- Tags muy antiguos pueden no publicar AppImage; solo se empaquetan los N
  recientes (todos con asset verificado desde v0.6).
- `apt changelog pince` no está implementado (requeriría servir los release
  notes de GitHub con formato changelog Debian; posible mejora futura).
- La instalación descarga 200–400 MB dentro del postinst: es el patrón
  "installer" estándar, pero un fallo de red a mitad deja el paquete en estado
  de error dpkg (se resuelve con `apt install -f` cuando vuelva la red;
  la descarga es atómica vía `.part` + `mv`).
