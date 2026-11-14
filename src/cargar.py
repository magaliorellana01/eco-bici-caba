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
EXTERNAL = RAIZ / "data" / "external"
BASE = RAIZ / "data" / "processed" / "ecobici.duckdb"
CARPETA_SQL = RAIZ / "sql"

ARCHIVO_VIAJES = RAW / "badata_ecobici_recorridos_realizados_2024.csv"
ARCHIVO_ESTACIONES_SHP = RAW / "nuevas-estaciones-ecobici.shp"
ARCHIVO_ESTACIONES_GEOJSON = RAW / "estaciones.geojson"
ARCHIVO_FERIADOS = EXTERNAL / "feriados_2024.csv"
ARCHIVO_CLIMA_DIARIO = EXTERNAL / "clima_diario_2024.csv"
ARCHIVO_CLIMA_HORARIO = EXTERNAL / "clima_horario_2024.csv"


def verificar_archivos() -> None:
    faltantes = [
        p.name
        for p in (
            ARCHIVO_VIAJES,
            ARCHIVO_ESTACIONES_SHP,
            ARCHIVO_ESTACIONES_GEOJSON,
            ARCHIVO_FERIADOS,
            ARCHIVO_CLIMA_DIARIO,
            ARCHIVO_CLIMA_HORARIO,
        )
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
    # Feriados nacionales (se descargan con: python -m src.feriados 2024).
    con.execute(f"""
        create or replace table raw_feriados as
        select * from read_csv('{ARCHIVO_FERIADOS.as_posix()}')
    """)
    # Viajes de años anteriores (trips_2019.csv a trips_2023.csv). Tienen otro
    # formato: todo se lee como texto y se convierte en sql/50_evolucion.sql.
    # Es una vista: no se copian a la base, solo se leen para agregarlos.
    archivos_historicos = sorted(RAW.glob("trips_*.csv"))
    if archivos_historicos:
        lista = ", ".join(f"'{p.as_posix()}'" for p in archivos_historicos)
        con.execute(f"""
            create or replace view raw_viajes_historicos as
            select * from read_csv([{lista}], all_varchar = true, union_by_name = true)
        """)
        print(f"  Años anteriores: {', '.join(p.stem for p in archivos_historicos)}")
    else:
        # Sin años anteriores, la evolución queda solo con 2024.
        columnas = [
            "Id_recorrido", "duracion_recorrido", "fecha_origen_recorrido",
            "id_estacion_origen", "nombre_estacion_origen", "id_estacion_destino",
            "nombre_estacion_destino", "id_usuario",
        ]
        con.execute(
            "create or replace view raw_viajes_historicos as select "
            + ", ".join(f"null::varchar as {c}" for c in columnas)
            + " where false"
        )
        print("  Años anteriores: no hay archivos trips_*.csv (se analiza solo 2024)")
    # Clima de Open-Meteo (se descarga con: python -m src.clima 2024).
    con.execute(f"""
        create or replace table raw_clima_diario as
        select * from read_csv('{ARCHIVO_CLIMA_DIARIO.as_posix()}')
    """)
    con.execute(f"""
        create or replace table raw_clima_horario as
        select * from read_csv('{ARCHIVO_CLIMA_HORARIO.as_posix()}')
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
