# EcoBici CABA

Análisis de los viajes del sistema de bicicletas públicas de la Ciudad de Buenos Aires con **SQL (DuckDB)** y **Power BI**: cuándo y para qué se usa, qué recorridos son los más frecuentes y, sobre todo, **qué estaciones se vacían o se llenan y qué hacer al respecto** (el problema de rebalanceo).

> Proyecto en curso.

## Preguntas

1. **¿Cuándo se usa?** Horas y días pico. ¿Se usa más para ir a trabajar o para pasear?
2. **¿Qué estaciones se vacían o se llenan?** Flujo neto de bicis por estación y franja horaria, en relación con su capacidad. Recomendación de rebalanceo: qué estaciones, en qué horario y cuántas bicis mover.
3. **¿Cuáles son los recorridos más frecuentes?**
4. **¿Cómo influye el clima?** Lluvia y temperatura contra la cantidad de viajes.
5. **¿Cómo evolucionó el uso entre años?**

## Resultados

### 1. ¿Cuándo se usa? ¿Para ir a trabajar o para pasear?

**EcoBici es principalmente un medio de transporte, no de paseo.** El 85% de los viajes se hace en días hábiles: un día hábil promedio tiene unos 10.900 viajes, contra unos 4.000 en un sábado, un domingo o un feriado.

| | Días hábiles | Fines de semana y feriados |
|---|---:|---:|
| Viajes de una ruta habitual del usuario | **46%** | 18% |
| Viajes circulares (vuelven a la misma estación) | 6% | **13%** |
| Duración mediana | 15 min | **25 min** |
| Viajes de más de 30 minutos | 14% | **41%** |

- **Los días hábiles tienen dos picos:** a las 8 h (560 viajes por hora) y a las 17 h (1.045 viajes por hora). Los fines de semana no hay pico a la mañana: el uso crece de a poco y se mantiene alto de 14 a 19 h.
- **El pico de la tarde casi duplica al de la mañana.** La franja de 16 a 20 h concentra el 34% de los viajes de un día hábil, y la de 7 a 10 h, el 13%. Pero a la mañana el uso es más "de trabajo": el 67% de esos viajes son de una ruta habitual, contra el 42% a la tarde. A la tarde se mezcla la vuelta a casa con trámites y salidas.

Consultas: [`sql/10_uso_temporal.sql`](sql/10_uso_temporal.sql).

## Datos

- **Viajes:** [Bicicletas públicas](https://data.buenosaires.gob.ar/dataset/bicicletas-publicas), portal de datos abiertos del GCBA. Un archivo por año (2010 a 2026) con estación de origen y destino, fecha y hora de salida y llegada.
- **Estaciones:** [Estaciones de bicicletas públicas](https://data.buenosaires.gob.ar/dataset/estaciones-bicicletas-publicas), con coordenadas y capacidad.
- **Usuarios:** edad, género y fecha de alta, en el mismo dataset de los viajes.
- **Clima:** a definir (datos históricos diarios u horarios de Buenos Aires).
- **Feriados:** feriados nacionales de [ArgentinaDatos](https://argentinadatos.com) (`python -m src.feriados 2024`).

## Metodología

- **Día hábil vs no hábil:** los feriados cuentan como no hábiles, igual que los fines de semana. Un feriado que cae un miércoles se comporta como un domingo (unos 4.500 viajes contra 11.000).
- **Promedios por día calendario:** los viajes promedio por hora se dividen por la cantidad de días de cada tipo, no por los días con viajes.
- **Señales de viaje "de trabajo":**
  - *Ruta habitual:* el usuario hace ese mismo recorrido, en cualquier sentido, en 5 días distintos o más del año.
  - *Ida y vuelta:* el usuario va de A a B y su siguiente viaje del día es de B a A. Es una señal más estricta, porque no detecta a quien va en bici y vuelve en otro medio. En días hábiles llega al 15% de los viajes.

## Estructura del proyecto

```
├── data/
│   ├── raw/          # archivos originales del portal (no incluidos en el repo)
│   ├── processed/    # base DuckDB (se genera con src/)
│   └── external/     # clima
├── sql/              # consultas de limpieza, modelo y análisis, numeradas en orden
├── src/              # scripts de Python para descargar y cargar los datos
├── dashboard/        # archivo de Power BI
└── reports/figures/  # capturas para el README
```

## Cómo reproducirlo

Requiere Python 3.12 o superior.

```bash
git clone https://github.com/magaliorellana01/eco-bici-caba.git
cd eco-bici-caba
python -m venv .venv
.venv\Scripts\activate          # Windows  (Linux/Mac: source .venv/bin/activate)
pip install -r requirements.txt
```

1. Descargar estos archivos del portal y guardarlos en `data/raw/`:
   - [Recorridos realizados 2024](https://data.buenosaires.gob.ar/dataset/bicicletas-publicas): descomprimir el ZIP (`badata_ecobici_recorridos_realizados_2024.csv`).
   - [Estaciones (SHP) (nuevo sistema)](https://data.buenosaires.gob.ar/dataset/estaciones-bicicletas-publicas): descomprimir el ZIP (`nuevas-estaciones-ecobici.shp` y sus archivos asociados).
   - [Estaciones (GEOJSON) (nuevo sistema)](https://data.buenosaires.gob.ar/dataset/estaciones-bicicletas-publicas/resource/e62fb076-dc64-4c42-b8ea-a8dd47395062): guardar como `estaciones.geojson`. Si el navegador lo abre como texto, usar Ctrl + S.
2. Generar la base: `python -m src.cargar` (tarda menos de un minuto y crea `data/processed/ecobici.duckdb`).

## Tecnologías

SQL · DuckDB · Python · Power BI
