"""Exporta las tablas de análisis de DuckDB a Parquet para usarlas en Power BI.

Uso (desde la raíz del proyecto, después de python -m src.cargar):
    python -m src.exportar_powerbi

Genera un archivo .parquet por tabla en data/processed/powerbi/. Power BI no
lee DuckDB directo, pero sí Parquet (Obtener datos > Parquet), que además
conserva los tipos de cada columna (fechas, enteros, decimales).

Se exportan tablas chicas y ya agregadas, una por visual, en lugar de los
3 millones de viajes: el dashboard queda liviano y rápido.
"""

from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parent.parent
BASE = RAIZ / "data" / "processed" / "ecobici.duckdb"
DESTINO = RAIZ / "data" / "processed" / "powerbi"

# nombre del archivo -> consulta. Agrupadas por página del dashboard.
TABLAS = {
    # Página 1: Uso
    "uso_por_hora": "from uso_por_hora",
    # dia_orden: sin esto, Power BI ordena los días alfabéticamente.
    "uso_por_dia_semana": """
        select
            *,
            list_position(
                ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo', 'Feriado'],
                dia
            ) as dia_orden
        from uso_por_dia_semana
    """,
    "perfil_uso": "from perfil_uso where franja is not null",
    # Página 2: Rebalanceo. Las dos tablas se relacionan por id_estacion:
    # al elegir una estación en el mapa, se ve su curva del día.
    "estaciones_rebalanceo": """
        select r.*, e.comuna, e.emplazamiento
        from rebalanceo as r
        join estaciones as e using (id_estacion)
    """,
    "flujo_horario": "from flujo_horario",
    # Página 3: Recorridos y clima
    "top_recorridos": "from top_recorridos",
    "dias_clima": "from dias_clima",
    "efecto_lluvia": "from efecto_lluvia",
    "efecto_lluvia_horaria": "from efecto_lluvia_horaria",
    # rango: etiqueta para el eje ("20 a 25 °C"); se ordena por temp_max_desde.
    "efecto_temperatura": """
        select
            *,
            temp_max_desde || ' a ' || temp_max_hasta || ' °C' as rango
        from efecto_temperatura
    """,
    # Página 4: Evolución
    "evolucion_mensual": "from evolucion_mensual",
    "evolucion_anual": "from evolucion_anual",
}


def sin_hugeint(con: duckdb.DuckDBPyConnection, consulta: str) -> str:
    """Convierte las columnas HUGEINT (resultado de sum()) a BIGINT.

    Parquet no tiene un entero de 128 bits y DuckDB lo guardaría como
    decimal, que Power BI muestra con coma decimal en vez de como entero.
    """
    columnas = con.sql(f"describe ({consulta})").fetchall()
    partes = [
        f'"{nombre}"::bigint as "{nombre}"' if tipo == "HUGEINT" else f'"{nombre}"'
        for nombre, tipo, *_ in columnas
    ]
    return f"select {', '.join(partes)} from ({consulta})"


def main() -> None:
    if not BASE.exists():
        raise SystemExit("No existe la base. Primero corré: python -m src.cargar")
    DESTINO.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(BASE, read_only=True) as con:
        for nombre, consulta in TABLAS.items():
            archivo = DESTINO / f"{nombre}.parquet"
            con.execute(f"copy ({sin_hugeint(con, consulta)}) to '{archivo.as_posix()}' (format parquet)")
            filas = con.sql(f"select count(*) from '{archivo.as_posix()}'").fetchall()[0][0]
            print(f"  {archivo.name:<30} {filas:>7,} filas")
    print(f"Archivos en {DESTINO.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
