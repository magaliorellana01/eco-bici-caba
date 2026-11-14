"""Descarga los feriados nacionales de Argentina y los guarda en data/external.

Uso (desde la raíz del proyecto):
    python -m src.feriados 2024

Fuente: ArgentinaDatos (https://argentinadatos.com), que publica los feriados
nacionales oficiales, incluidos los puentes turísticos.
"""

import csv
import json
import sys
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
EXTERNAL = RAIZ / "data" / "external"
URL = "https://api.argentinadatos.com/v1/feriados/{anio}"


def descargar_feriados(anio: int) -> Path:
    # La API rechaza (403) el User-Agent por defecto de Python.
    pedido = urllib.request.Request(
        URL.format(anio=anio), headers={"User-Agent": "eco-bici-caba/1.0"}
    )
    with urllib.request.urlopen(pedido, timeout=30) as respuesta:
        feriados = json.load(respuesta)

    destino = EXTERNAL / f"feriados_{anio}.csv"
    with destino.open("w", newline="", encoding="utf-8") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=["fecha", "tipo", "nombre"])
        escritor.writeheader()
        escritor.writerows(feriados)
    print(f"{len(feriados)} feriados guardados en {destino.relative_to(RAIZ)}")
    return destino


if __name__ == "__main__":
    anios = [int(a) for a in sys.argv[1:]] or [2024]
    for anio in anios:
        descargar_feriados(anio)
