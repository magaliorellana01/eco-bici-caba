"""Carga los archivos de data/raw en una base DuckDB y ejecuta las consultas de sql/.

Uso (desde la raíz del proyecto):
    python -m src.cargar

Genera data/processed/ecobici.duckdb. Se puede correr las veces que haga falta:
cada corrida reemplaza las tablas.
"""

import sys
import time
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parent.parent
RAW = RAIZ / "data" / "raw"
BASE = RAIZ / "data" / "processed" / "ecobici.duckdb"
CARPETA_SQL = RAIZ / "sql"

ARCHIVO_VIAJES = RAW / "badata_ecobici_recorridos_realizados_2024.csv"
ARCHIVO_ESTACIONES_SHP = RAW / "nuevas-estaciones-ecobici.shp"
ARCHIVO_ESTACIONES_GEOJSON = RAW / "estaciones.geojson"


def verificar_archivos() -> None:
    faltantes = [
        p.name
        for p in (ARCHIVO_VIAJES, ARCHIVO_ESTACIONES_SHP, ARCHIVO_ESTACIONES_GEOJSON)
        if not p.exists()
    ]
    if faltantes:
        sys.exit(f"Faltan archivos en data/raw: {', '.join(faltantes)}. Ver README.")


def cargar_crudos(con: duckdb.DuckDBPyConnection) -> None:
    """Copia los archivos originales a tablas raw_*, sin transformar nada."""
    con.execute(f"""
        create or replace table raw_viajes as
        select * from read_csv('{ARCHIVO_VIAJES.as_posix()}', sample_size = -1)
    """)
    # El shapefile (sept-2024) trae barrio, comuna y emplazamiento.
    con.execute(f"""
        create or replace table raw_estaciones_shp as
        select * exclude (geom) from ST_Read('{ARCHIVO_ESTACIONES_SHP.as_posix()}')
    """)
    # El GeoJSON es el único archivo que trae la capacidad (ANCLAJES).
    con.execute(f"""
        create or replace table raw_estaciones_geojson as
        select * exclude (geom) from ST_Read('{ARCHIVO_ESTACIONES_GEOJSON.as_posix()}')
    """)


def ejecutar_sql(con: duckdb.DuckDBPyConnection) -> None:
    """Ejecuta los archivos de sql/ que empiezan con número, en orden."""
    for archivo in sorted(CARPETA_SQL.glob("[0-9][0-9]_*.sql")):
        inicio = time.perf_counter()
        con.execute(archivo.read_text(encoding="utf-8"))
        print(f"  {archivo.name} ({time.perf_counter() - inicio:.1f} s)")


def main() -> None:
    verificar_archivos()
    BASE.parent.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(BASE) as con:
        con.execute("install spatial; load spatial;")
        print("Cargando archivos originales...")
        cargar_crudos(con)
        print("Ejecutando consultas:")
        ejecutar_sql(con)
        print("\nEmbudo de limpieza:")
        print(con.sql("from embudo_limpieza order by paso"))
    print(f"Base generada en {BASE.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
