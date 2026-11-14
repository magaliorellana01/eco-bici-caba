-- =====================================================================
-- 01. Limpieza de viajes
-- Entrada: raw_viajes (CSV original de 2024, sin modificar)
-- Salida:  viajes_marcados  -> todos los viajes, con el motivo de descarte
--          embudo_limpieza  -> cuántos viajes saca cada filtro
--          viajes           -> viajes válidos, base de todo el análisis
-- =====================================================================

-- Cada viaje recibe como mucho UN motivo de descarte: el primero que cumple,
-- en el orden del CASE. Así el embudo suma exacto y no cuenta dos veces.
-- Es una vista (no una tabla) para no guardar los 3,5 millones de viajes
-- dos veces en la base.
drop table if exists viajes_marcados;
create or replace view viajes_marcados as
with numerados as (
    select
        *,
        row_number() over (
            partition by id_recorrido
            order by fecha_origen_recorrido
        ) as aparicion
    from raw_viajes
)
select
    *,
    case
        when aparicion > 1
            then '1. Viaje duplicado'
        -- Estaciones que no son para el público: depósitos (CDO) y taller.
        -- "-CDO CUCHA CUCHA-" la usan 21 usuarios en todo el año y la mayoría
        -- de sus viajes vuelven a la misma estación en segundos.
        -- También aparecen "-- CDO Chacarita -- (Temporal)" y "REPARACION DE K7".
        when regexp_matches(upper(nombre_estacion_origen), 'CDO|REPARACION')
          or regexp_matches(upper(nombre_estacion_destino), 'CDO|REPARACION')
            then '2. Estación logística (depósito o taller)'
        -- Retiro fallido o arrepentimiento: nadie viaja en menos de un minuto.
        when duracion_recorrido < 60
            then '3. Menos de 1 minuto'
        -- Sacó la bici y la devolvió en el mismo lugar enseguida
        -- (bici con falla, asiento roto, etc.).
        when id_estacion_origen = id_estacion_destino
         and duracion_recorrido < 120
            then '4. Devuelta en la misma estación en menos de 2 minutos'
        -- El 99% de los viajes dura menos de 100 minutos. Por encima de
        -- 3 horas son casi siempre bicis mal ancladas o devueltas tarde.
        when duracion_recorrido > 3 * 3600
            then '5. Más de 3 horas'
    end as motivo_descarte
from numerados;


-- Embudo: viajes eliminados por cada filtro y viajes que quedan.
create or replace table embudo_limpieza as
with total as (
    select count(*) as n from viajes_marcados
),
eliminados as (
    select motivo_descarte as paso, count(*) as eliminados
    from viajes_marcados
    where motivo_descarte is not null
    group by motivo_descarte
)
select '0. Dataset original' as paso, null::bigint as eliminados, n as quedan
from total
union all
select
    paso,
    eliminados,
    (select n from total) - sum(eliminados) over (order by paso) as quedan
from eliminados;


-- Tabla final de viajes válidos.
create or replace table viajes as
select
    id_recorrido,
    fecha_origen_recorrido  as fecha_inicio,
    fecha_destino_recorrido as fecha_fin,
    duracion_recorrido      as duracion_seg,
    id_estacion_origen,
    id_estacion_destino,
    id_usuario::bigint      as id_usuario,
    modelo_bicicleta,
    genero
from viajes_marcados
where motivo_descarte is null;
