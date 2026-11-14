-- =====================================================================
-- 02. Tabla de estaciones
-- Entrada: viajes_marcados (de 01), raw_estaciones_shp, raw_estaciones_geojson
-- Salida:  estaciones -> una fila por estación que aparece en los viajes
--                        válidos, con barrio, comuna y capacidad
--
-- La fuente principal son los propios viajes: traen id, nombre, dirección
-- y coordenadas de cada estación. Los otros dos archivos solo agregan datos:
--   * shapefile (sept-2024): barrio, comuna y emplazamiento. Cruza por id.
--   * GeoJSON: capacidad (ANCLAJES). Su id NO coincide con el de los viajes
--     y reutiliza números de estación, así que se cruza por número y se
--     valida con el nombre o la distancia (ver más abajo).
-- =====================================================================

-- Distancia aproximada en metros entre dos puntos. A la escala de una ciudad
-- alcanza con la aproximación plana (error menor al 1%).
create or replace macro distancia_m(lat1, lon1, lat2, lon2) as
    111320 * sqrt(
        pow(lat1 - lat2, 2)
        + pow((lon1 - lon2) * cos(radians(lat1)), 2)
    );

-- Nombre comparable: sin tildes, en mayúsculas y sin espacios de más.
create or replace macro normalizar(texto) as
    trim(regexp_replace(upper(strip_accents(texto)), '\s+', ' ', 'g'));


create or replace table estaciones as
with apariciones as (
    select
        id_estacion_origen        as id_estacion,
        nombre_estacion_origen    as nombre_original,
        direccion_estacion_origen as direccion,
        lat_estacion_origen       as lat,
        long_estacion_origen      as lon,
        fecha_origen_recorrido    as fecha
    from viajes_marcados
    where motivo_descarte is null
    union all
    select
        id_estacion_destino,
        nombre_estacion_destino,
        direccion_estacion_destino,
        lat_estacion_destino,
        long_estacion_destino,
        fecha_destino_recorrido
    from viajes_marcados
    where motivo_descarte is null
),

-- Una fila por estación, con los datos de su aparición más reciente.
base as (
    select
        id_estacion,
        nombre_original,
        direccion,
        lat,
        lon,
        min(fecha) over (partition by id_estacion) as primer_uso,
        max(fecha) over (partition by id_estacion) as ultimo_uso
    from apariciones
    qualify row_number() over (partition by id_estacion order by fecha desc) = 1
),

-- El nombre viene como "147 - Constitución", "131- HOSPITAL DE CLÍNICAS",
-- "227 -Club Ciudad...": se separa el número del nombre.
con_numero as (
    select
        *,
        try_cast(regexp_extract(nombre_original, '^\s*(\d+)', 1) as integer) as numero,
        trim(regexp_replace(nombre_original, '^\s*\d+\s*-\s*', '')) as nombre
    from base
),

-- Barrio: el id del shapefile es el mismo que el de los viajes. Igual se
-- exige que esté a menos de 300 m, por si la estación se mudó.
barrio_shp as (
    select
        e.id_estacion,
        s.BARRIO     as barrio,
        s.COMUNA     as comuna,
        s.EMPLAZAMIE as emplazamiento
    from con_numero as e
    join raw_estaciones_shp as s
      on s.ID = e.id_estacion
     and distancia_m(e.lat, e.lon, s.LATITUD, s.LONGITUD) < 300
),

-- Capacidad: candidatos del GeoJSON con el mismo número de estación.
-- Como el GeoJSON reutiliza números, el cruce solo se acepta si además
-- el nombre se parece (similitud >= 0,85) o están a menos de 300 m.
-- Si hay más de un candidato válido, gana el de nombre más parecido.
capacidad_geojson as (
    select
        e.id_estacion,
        g.ANCLAJES   as capacidad,
        g.BARRIO     as barrio,
        g.COMUNA     as comuna,
        g.EMPLAZAMIE as emplazamiento
    from con_numero as e
    join raw_estaciones_geojson as g
      on g.NUMERO = e.numero
    where jaro_winkler_similarity(normalizar(e.nombre), normalizar(g.NOMBRE)) >= 0.85
       or distancia_m(e.lat, e.lon, g.Lat, g.Lon) < 300
    qualify row_number() over (
        partition by e.id_estacion
        order by
            jaro_winkler_similarity(normalizar(e.nombre), normalizar(g.NOMBRE)) desc,
            distancia_m(e.lat, e.lon, g.Lat, g.Lon)
    ) = 1
)

select
    e.id_estacion,
    e.numero,
    e.nombre,
    e.direccion,
    e.lat,
    e.lon,
    -- Si el shapefile no tiene la estación, se usa el barrio del GeoJSON.
    coalesce(b.barrio, c.barrio)               as barrio,
    coalesce(b.comuna, c.comuna)               as comuna,
    coalesce(b.emplazamiento, c.emplazamiento) as emplazamiento,
    -- 0 anclajes no es una capacidad real (estación desactivada): queda nulo.
    nullif(c.capacidad, 0)                     as capacidad,
    e.primer_uso,
    e.ultimo_uso
from con_numero as e
left join barrio_shp        as b using (id_estacion)
left join capacidad_geojson as c using (id_estacion)
order by e.id_estacion;
