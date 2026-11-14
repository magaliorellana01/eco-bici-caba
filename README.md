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

### 2. ¿Qué estaciones se vacían o se llenan? ¿Qué hacer?

**El desbalance se da dentro del día, no de un día para otro.** A la mañana, la gente llega en tren a Constitución y a Retiro, toma una bici y la deja en las zonas de oficinas. A la tarde hace el viaje inverso.

- **Constitución pierde en promedio 40 bicis entre las 5 y las 13 h**, el 83% de sus 48 anclajes, y las recupera entre las 14 y las 19 h.
- **Las oficinas del centro se llenan:** Madero Office gana 18 bicis hasta las 11 h, Juana Manso 16 y Macacha Güemes 12.

Para cada estación se buscó **con cuántas bicis conviene arrancar el día** para no quedarse vacía ni llena, y **cuántas hay que mover en un día malo** (percentil 90).

| Prioridad | Estaciones | % de los movimientos | Criterio |
|---|---:|---:|---|
| Crítica | 19 | 8% | El mejor stock inicial alcanza en menos de la mitad de los días hábiles |
| Alta | 49 | 19% | Alcanza entre el 50% y el 70% de los días |
| Media | 152 | 45% | Alcanza entre el 70% y el 90% de los días |
| Sin intervención | 101 | 15% | Alcanza en el 90% de los días o más |
| Sin dato de capacidad | 74 | 13% | No se pudo cruzar con el archivo de capacidad |

**Recomendaciones:**

1. **Antes de las 5 h, cargar cada estación con su stock recomendado** y no llenarlas todas. Por ejemplo, Constitución con 37 de sus 48 anclajes, Retiro II con 29 de 40 y Madero Office con solo 5 de 28, porque a la mañana se llena. Con ese ajuste solo, 101 estaciones no necesitan más intervención en 9 de cada 10 días.
2. **A media mañana (de 10 a 12 h), una ruta que lleve bicis de las oficinas a Constitución.** Las estaciones de Puerto Madero, Monserrat y San Nicolás llegan a su pico entre las 9 y las 13 h, que es justo cuando Constitución toca su mínimo (13 h). El mismo camión resuelve los dos problemas en un viaje.
3. **Ampliar Constitución.** Es la estación más usada (256 movimientos por día hábil) y, aun con el mejor stock inicial, en un día malo hay que reponerle 31 bicis y retirarle 22. Ningún otro caso se acerca.
4. **Estaciones chicas con mucha demanda:** Planetario (7 anclajes), José Artigas (6) y Teatro Picadero (8) quedan críticas porque tienen muy pocos anclajes para la demanda que reciben. Sumar anclajes ahí es más barato que rebalancearlas todos los días.

Consultas: [`sql/20_rebalanceo.sql`](sql/20_rebalanceo.sql). La tabla `rebalanceo` tiene la recomendación para cada una de las 395 estaciones.

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
- **Rebalanceo:**
  - Cada viaje es una salida (−1) en su estación de origen y una llegada (+1) en la de destino. Para cada estación y día hábil se acumula el saldo viaje a viaje, y así se obtiene la mayor pérdida y la mayor ganancia de ese día.
  - Una estación que arranca con *S* bicis "aguanta" un día si *S* ≥ la mayor pérdida del día y si *S* + la mayor ganancia del día ≤ capacidad. Se prueban todos los *S* posibles, de 0 a la capacidad, y se elige el que aguanta más días.
  - Se trabaja con días reales y no con el día promedio, porque el promedio esconde los días malos. Por la misma razón, lo que hay que mover se informa con el percentil 90.
- **Capacidad de las estaciones:** el GeoJSON de estaciones trae la capacidad (`ANCLAJES`), pero su id no coincide con el de los viajes y reutiliza números de estación. Por eso el cruce se hace por número de estación y se valida con el nombre (similitud ≥ 0,85) o con la distancia (menos de 300 m). Así queda bien asignada la capacidad de estaciones que concentran el 91% de los viajes. Las demás quedan sin dato en lugar de quedar con una capacidad que no es la suya.

## Limitaciones

- **Los viajes no incluyen los movimientos de los camiones de rebalanceo**, así que no se sabe cuántas bicis había realmente en cada estación. El análisis mide la demanda de los usuarios, no el estado de las estaciones.
- **Demanda censurada:** cuando una estación está vacía, nadie puede sacar una bici, y ese viaje no queda registrado. Por eso, en las estaciones que se vacían seguido, la demanda real es mayor que la medida.
- **Capacidad:** el archivo de capacidad es posterior a 2024 y no tiene fecha de actualización, así que puede no reflejar la capacidad de cada estación durante todo el año. 74 estaciones, con el 13% de los movimientos, quedan sin dato.
- **Usuarios:** el archivo de usuarios del portal solo incluye a quienes se registraron en 2024 (el 32% de los viajes), así que no se analiza la edad.

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
