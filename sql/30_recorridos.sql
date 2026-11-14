-- =====================================================================
-- 30. Pregunta 3: ¿Cuáles son los recorridos más frecuentes?
-- Entrada: viajes, estaciones, calendario
-- Salida:  recorridos               -> una fila por par origen-destino (con sentido),
--                                      con coordenadas para dibujar líneas en un mapa
--          top_recorridos           -> los 20 recorridos más usados por tipo de día,
--                                      sin importar el sentido (A-B = B-A)
--          concentracion_recorridos -> qué % de los viajes cubren los N más usados
-- =====================================================================


create or replace table recorridos as
select
    v.id_estacion_origen,
    v.id_estacion_destino,
    eo.nombre                                              as origen,
    ed.nombre                                              as destino,
    eo.barrio                                              as barrio_origen,
    ed.barrio                                              as barrio_destino,
    eo.lat as lat_origen,  eo.lon as lon_origen,
    ed.lat as lat_destino, ed.lon as lon_destino,
    -- Distancia en línea recta: el recorrido real por las calles es más largo.
    round(distancia_m(eo.lat, eo.lon, ed.lat, ed.lon))     as distancia_m,
    count(*)                                               as viajes,
    count(*) filter (where c.tipo_dia = 'Hábil')           as viajes_habiles,
    count(*) filter (where c.tipo_dia = 'No hábil')        as viajes_no_habiles,
    round(median(v.duracion_seg) / 60, 1)                  as duracion_mediana_min
from viajes as v
join calendario as c  on c.fecha = v.fecha_inicio::date
join estaciones as eo on eo.id_estacion = v.id_estacion_origen
join estaciones as ed on ed.id_estacion = v.id_estacion_destino
group by all;


-- Recorridos sin sentido: A -> B y B -> A se suman, porque casi todos los
-- recorridos frecuentes se usan parecido en las dos direcciones (ida y vuelta).
-- Se excluyen los circulares (misma estación de origen y destino).
create or replace view top_recorridos as
with pares as (
    select
        least(id_estacion_origen, id_estacion_destino)    as estacion_a,
        greatest(id_estacion_origen, id_estacion_destino) as estacion_b,
        sum(viajes_habiles)    as viajes_habiles,
        sum(viajes_no_habiles) as viajes_no_habiles,
        any_value(distancia_m) as distancia_m
    from recorridos
    where id_estacion_origen <> id_estacion_destino
    group by estacion_a, estacion_b
),
por_tipo_dia as (
    unpivot pares
    on viajes_habiles as 'Hábil', viajes_no_habiles as 'No hábil'
    into name tipo_dia value viajes
)
select
    p.tipo_dia,
    rank() over (partition by p.tipo_dia order by p.viajes desc) as puesto,
    ea.nombre || ' ↔ ' || eb.nombre                             as recorrido,
    ea.barrio                                                    as barrio_a,
    eb.barrio                                                    as barrio_b,
    p.viajes,
    p.distancia_m
from por_tipo_dia as p
join estaciones as ea on ea.id_estacion = p.estacion_a
join estaciones as eb on eb.id_estacion = p.estacion_b
qualify puesto <= 20
order by p.tipo_dia, puesto;


-- Concentración: qué tan repartida está la demanda entre los pares.
create or replace view concentracion_recorridos as
with pares as (
    select
        least(id_estacion_origen, id_estacion_destino)    as estacion_a,
        greatest(id_estacion_origen, id_estacion_destino) as estacion_b,
        sum(viajes) as viajes
    from recorridos
    where id_estacion_origen <> id_estacion_destino
    group by estacion_a, estacion_b
),
ranking as (
    select
        viajes,
        row_number() over (order by viajes desc) as puesto,
        sum(viajes) over ()                      as total
    from pares
)
select
    top_n,
    round(100 * sum(viajes) / any_value(total), 1) as pct_viajes
from ranking
cross join (values (10), (100), (1000)) as t(top_n)
where puesto <= top_n
group by top_n
order by top_n;
