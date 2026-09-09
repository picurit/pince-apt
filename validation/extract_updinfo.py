#!/usr/bin/env python3
"""Valida que el AppImage publicado de PINCE tenga informacion de
actualizacion embebida (.upd_info) sin descargar el archivo completo.
Usa peticiones HTTP Range contra el asset del release."""
import struct
import subprocess
import sys

URL = "https://github.com/korcankaraokcu/PINCE/releases/download/v0.10.1/PINCE-x86_64.AppImage"


def fetch(start, length):
    end = start + length - 1
    out = subprocess.run(
        ["curl", "-sfL", "-r", f"{start}-{end}", URL],
        capture_output=True, check=True,
    )
    data = out.stdout
    assert len(data) == length, f"esperados {length} bytes, recibidos {len(data)}"
    return data


# 1. Cabecera ELF64
ehdr = fetch(0, 64)
assert ehdr[:4] == b"\x7fELF", "no es un ELF"
e_shoff = struct.unpack_from("<Q", ehdr, 0x28)[0]
e_shentsize = struct.unpack_from("<H", ehdr, 0x3A)[0]
e_shnum = struct.unpack_from("<H", ehdr, 0x3C)[0]
e_shstrndx = struct.unpack_from("<H", ehdr, 0x3E)[0]
print(f"ELF ok. Secciones: {e_shnum} (entsize {e_shentsize}) shoff={e_shoff:#x}")

# 2. Tabla de cabeceras de seccion
shtab = fetch(e_shoff, e_shnum * e_shentsize)
sections = []
for i in range(e_shnum):
    off = i * e_shentsize
    sh_name = struct.unpack_from("<I", shtab, off)[0]
    sh_offset = struct.unpack_from("<Q", shtab, off + 0x18)[0]
    sh_size = struct.unpack_from("<Q", shtab, off + 0x20)[0]
    sections.append((sh_name, sh_offset, sh_size))

# 3. Tabla de nombres de seccion
strtab_off, strtab_size = sections[e_shstrndx][1], sections[e_shstrndx][2]
strtab = fetch(strtab_off, strtab_size)


def name_at(idx):
    end = strtab.index(b"\x00", idx)
    return strtab[idx:end].decode()


# 4. Localizar .upd_info y extraerla
for sh_name, sh_offset, sh_size in sections:
    if name_at(sh_name) == ".upd_info":
        data = fetch(sh_offset, sh_size).rstrip(b"\x00")
        print(f".upd_info encontrada en offset {sh_offset:#x}, {sh_size} bytes")
        print(f"UPDATE INFO: {data.decode()}")
        sys.exit(0)

print("ERROR: seccion .upd_info NO encontrada — el AppImage no soporta AppImageUpdate")
sys.exit(1)
