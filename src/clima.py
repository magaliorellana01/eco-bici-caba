"""Descarga el clima histórico de Buenos Aires y lo guarda en data/external.

Uso (desde la raíz del proyecto):
    python -m src.clima 2024

Fuente: Open-Meteo Historical Weather API (https://open-meteo.com), datos del
reanálisis ERA5, licencia CC BY 4.0. Genera dos archivos:
    clima_diario_<año>.csv   temperatura máxima, mínima, media y lluvia del día
    clima_horario_<año>.csv  temperatura y lluvia de cada hora
"""

import csv
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
EXTERNAL = RAIZ / "data" / "external"
URL = "https://archive-api.open-meteo.com/v1/archive"

# Centro geográfico aproximado de la red de EcoBici (Almagro / Palermo).
LATITUD = -34.60
LONGITUD = -58.42

VARIABLES_DIARIAS = [
    "temperature_2m_max",
    "temperature_2m_min",
    "temperature_2m_mean",
    "precipitation_sum",
    "precipitation_hours",
]
VARIABLES_HORARIAS = ["temperature_2m", "precipitation"]


def pedir(anio: int) -> dict:
    parametros = {
        "latitude": LATITUD,
        "longitude": LONGITUD,
        "start_date": f"{anio}-01-01",
        "end_date": f"{anio}-12-31",
        "daily": ",".join(VARIABLES_DIARIAS),
        "hourly": ",".join(VARIABLES_HORARIAS),
        "timezone": "America/Argentina/Buenos_Aires",
    }
    url = f"{URL}?{urllib.parse.urlencode(parametros)}"
    with urllib.request.urlopen(url, timeout=60) as respuesta:
        return json.load(respuesta)


def guardar(bloque: dict, columna_tiempo: str, columnas: list[str], destino: Path) -> None:
    """Pasa el formato de la API (una lista por variable) a filas de CSV."""
    with destino.open("w", newline="", encoding="utf-8") as archivo:
        escritor = csv.writer(archivo)
        escritor.writerow([columna_tiempo, *columnas])
        escritor.writerows(zip(bloque["time"], *(bloque[c] for c in columnas)))
    print(f"{len(bloque['time'])} filas guardadas en {destino.relative_to(RAIZ)}")


def descargar_clima(anio: int) -> None:
    datos = pedir(anio)
    guardar(datos["daily"], "fecha", VARIABLES_DIARIAS, EXTERNAL / f"clima_diario_{anio}.csv")
    guardar(datos["hourly"], "momento", VARIABLES_HORARIAS, EXTERNAL / f"clima_horario_{anio}.csv")


if __name__ == "__main__":
    anios = [int(a) for a in sys.argv[1:]] or [2024]
    for anio in anios:
        descargar_clima(anio)
