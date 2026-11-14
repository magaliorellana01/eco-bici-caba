-- =====================================================================
-- 10. Pregunta 1: ¿Cuándo se usa? ¿Para ir a trabajar o para pasear?
-- Entrada: viajes, calendario
-- Salida:  viajes_patron      -> patrón de cada viaje (ida, vuelta, circular...)
--          uso_por_hora       -> viajes promedio por hora, día hábil vs no hábil
--          uso_por_dia_semana -> viajes promedio por día de la semana
--          perfil_uso         -> indicadores de trabajo vs paseo por franja
-- =====================================================================


-- Patrón de cada viaje, mirando los viajes del mismo usuario en el mismo día:
--   * Ida:      va de A a B y su siguiente viaje del día es de B a A.
--   * Vuelta:   va de B a A y su viaje anterior del día fue de A a B.
--   * Circular: sale y vuelve a la misma estación (típico de un paseo).
--   * Otro:     cualquier otro viaje.
-- Un par ida-vuelta en el día es una señal fuerte de viaje pendular
-- (casa-trabajo, casa-facultad), pero muy estricta: no detecta a quien va
-- en bici y vuelve en subte. Por eso se agrega una segunda señal:
--   * ruta_habitual: el usuario hizo ese mismo recorrido (en cualquier
--     sentido) en 5 días distintos o más del año.
create or replace table viajes_patron as
with vecinos as (
    select
        id_recorrido,
        id_estacion_origen,
        id_estacion_destino,
        count(distinct fecha_inicio::date) over (
            partition by
                id_usuario,
                least(id_estacion_origen, id_estacion_destino),
                greatest(id_estacion_origen, id_estacion_destino)
        ) as dias_con_esta_ruta,
        lead(id_estacion_origen)  over dia_usuario as siguiente_origen,
        lead(id_estacion_destino) over dia_usuario as siguiente_destino,
        lag(id_estacion_origen)   over dia_usuario as anterior_origen,
        lag(id_estacion_destino)  over dia_usuario as anterior_destino
    from viajes
    window dia_usuario as (
        partition by id_usuario, fecha_inicio::date
        order by fecha_inicio
    )
)
select
    id_recorrido,
    case
        when id_estacion_origen = id_estacion_destino
            then 'Circular'
        when siguiente_origen = id_estacion_destino
         and siguiente_destino = id_estacion_origen
            then 'Ida'
        when anterior_origen = id_estacion_destino
         and anterior_destino = id_estacion_origen
            then 'Vuelta'
        else 'Otro'
    end as patron,
    id_estacion_origen <> id_estacion_destino
        and dias_con_esta_ruta >= 5 as ruta_habitual
from vecinos;


-- Viajes promedio por hora de inicio. Se divide por la cantidad de días
-- de cada tipo, no por los días con viajes, para no inflar el promedio.
create or replace view uso_por_hora as
with viajes_hora as (
    select
        c.tipo_dia,
        hour(v.fecha_inicio) as hora,
        count(*)             as viajes
    from viajes as v
    join calendario as c on c.fecha = v.fecha_inicio::date
    group by c.tipo_dia, hora
),
dias as (
    select tipo_dia, count(*) as cantidad_dias
    from calendario
    group by tipo_dia
)
select
    h.tipo_dia,
    h.hora,
    h.viajes,
    round(h.viajes / d.cantidad_dias, 1) as viajes_promedio_por_dia
from viajes_hora as h
join dias as d using (tipo_dia)
order by h.tipo_dia, h.hora;


-- Viajes promedio por día de la semana. Los feriados se muestran aparte
-- para que un feriado que cae un martes no baje el promedio de los martes.
create or replace view uso_por_dia_semana as
with viajes_dia as (
    select
        c.fecha,
        c.dia_semana_num,
        case when c.feriado is not null then 'Feriado' else c.dia_semana end as dia,
        count(v.id_recorrido) as viajes
    from calendario as c
    left join viajes as v on v.fecha_inicio::date = c.fecha
    group by all
)
select
    dia,
    count(*)              as cantidad_dias,
    round(avg(viajes))    as viajes_promedio,
    round(median(viajes)) as viajes_mediana
from viajes_dia
group by dia
order by min(case when dia = 'Feriado' then 8 else dia_semana_num end);


-- Indicadores de "trabajo vs paseo" por tipo de día y franja horaria.
create or replace view perfil_uso as
select
    c.tipo_dia,
    case
        when hour(v.fecha_inicio) between 7 and 9   then '1. Mañana (7 a 10 h)'
        when hour(v.fecha_inicio) between 16 and 19 then '3. Tarde (16 a 20 h)'
        else '2. Resto del día'
    end                                                          as franja,
    count(*)                                                     as viajes,
    round(100 * avg(p.ruta_habitual::int), 1)                    as pct_ruta_habitual,
    round(100 * avg((p.patron in ('Ida', 'Vuelta'))::int), 1)    as pct_ida_y_vuelta,
    round(100 * avg((p.patron = 'Circular')::int), 1)            as pct_circular,
    round(median(v.duracion_seg) / 60, 1)                        as duracion_mediana_min,
    round(100 * avg((v.duracion_seg > 30 * 60)::int), 1)         as pct_mas_de_30_min
from viajes as v
join calendario    as c on c.fecha = v.fecha_inicio::date
join viajes_patron as p using (id_recorrido)
group by grouping sets ((c.tipo_dia), (c.tipo_dia, franja))
order by c.tipo_dia, franja nulls first;
