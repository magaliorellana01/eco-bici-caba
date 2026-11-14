-- =====================================================================
-- 50. Pregunta 5: ¿Cómo evolucionó el uso entre años?
-- Entrada: raw_viajes_historicos (2019 a 2023, otro formato), viajes (2024)
-- Salida:  embudo_historico   -> viajes que saca cada filtro, por año
--          evolucion_diaria   -> viajes, usuarios y estaciones activas por día
--          evolucion_mensual  -> lo mismo por mes, para ver la tendencia
--          evolucion_anual    -> resumen por año
--
-- Los años anteriores NO se guardan viaje por viaje: se leen de los CSV y se
-- agregan por día. Así la base sigue liviana.
--
-- Formato de 2019 a 2023 (distinto del de 2024):
--   * ids con sufijo de texto: "5BAEcobici" es la estación 5
--   * duración con coma de miles: "2,814" son 2.814 segundos
--     (validado: coincide con la diferencia entre llegada y salida)
--   * el portal ya sacó los viajes de menos de 1 minuto. Para comparar
--     parejo, se aplican a todos los años los mismos filtros que a 2024.
-- =====================================================================


create or replace view viajes_historicos_marcados as
with convertidos as (
    select
        fecha_origen_recorrido::timestamp                                    as fecha_inicio,
        try_cast(replace(duracion_recorrido, ',', '') as integer)            as duracion_seg,
        try_cast(replace(id_estacion_origen, 'BAEcobici', '') as integer)    as id_estacion_origen,
        try_cast(replace(id_estacion_destino, 'BAEcobici', '') as integer)   as id_estacion_destino,
        try_cast(replace(id_usuario, 'BAEcobici', '') as bigint)             as id_usuario,
        nombre_estacion_origen,
        nombre_estacion_destino
    from raw_viajes_historicos
)
select
    *,
    year(fecha_inicio) as anio,
    -- Mismos criterios que sql/01_limpieza.sql, en el mismo orden.
    case
        when id_estacion_destino is null or duracion_seg is null
            then '1. Sin destino o sin duración'
        when regexp_matches(upper(coalesce(nombre_estacion_origen, '')), 'CDO|REPARACION')
          or regexp_matches(upper(coalesce(nombre_estacion_destino, '')), 'CDO|REPARACION')
            then '2. Estación logística (depósito o taller)'
        when duracion_seg < 60
            then '3. Menos de 1 minuto'
        when id_estacion_origen = id_estacion_destino and duracion_seg < 120
            then '4. Devuelta en la misma estación en menos de 2 minutos'
        when duracion_seg > 3 * 3600
            then '5. Más de 3 horas'
    end as motivo_descarte
from convertidos;


create or replace table embudo_historico as
select
    anio,
    coalesce(motivo_descarte, 'Viajes válidos') as paso,
    count(*)                                    as viajes
from viajes_historicos_marcados
group by all
order by anio, paso;


-- Todos los años juntos, con las columnas que se comparan.
create or replace view viajes_todos_los_anios as
select fecha_inicio, duracion_seg, id_estacion_origen, id_usuario
from viajes_historicos_marcados
where motivo_descarte is null
union all
select fecha_inicio, duracion_seg, id_estacion_origen, id_usuario
from viajes;


create or replace table evolucion_diaria as
select
    fecha_inicio::date                         as fecha,
    year(fecha_inicio)                         as anio,
    -- Lunes a viernes vs fin de semana. No se separan los feriados porque
    -- no hay calendario de feriados para 2019 y 2020; por eso los resúmenes
    -- usan la mediana, que casi no se mueve por los pocos feriados del año.
    case when isodow(fecha_inicio) <= 5 then 'Lunes a viernes' else 'Fin de semana' end as tipo_dia,
    count(*)                                   as viajes,
    count(distinct id_usuario)                 as usuarios,
    count(distinct id_estacion_origen)         as estaciones_activas,
    round(median(duracion_seg) / 60, 1)        as duracion_mediana_min
from viajes_todos_los_anios
group by all
order by fecha;


create or replace view evolucion_mensual as
select
    date_trunc('month', fecha)::date                                       as mes,
    sum(viajes)                                                            as viajes,
    round(median(viajes) filter (where tipo_dia = 'Lunes a viernes'))      as mediana_viajes_lunes_a_viernes,
    round(median(viajes) filter (where tipo_dia = 'Fin de semana'))        as mediana_viajes_fin_de_semana,
    max(estaciones_activas)                                                as estaciones_activas
from evolucion_diaria
group by mes
order by mes;


-- Usuarios distintos por año: se cuentan sobre los viajes (no sumando los
-- de cada día, porque el mismo usuario viaja muchos días).
create or replace table evolucion_anual as
with usuarios as (
    select
        year(fecha_inicio)                 as anio,
        count(distinct id_usuario)         as usuarios,
        count(distinct id_estacion_origen) as estaciones_usadas
    from viajes_todos_los_anios
    group by anio
),
dias as (
    select
        anio,
        min(fecha)                                                         as primer_dia,
        count(distinct date_trunc('month', fecha))                         as meses_con_datos,
        sum(viajes)                                                        as viajes,
        round(median(viajes) filter (where tipo_dia = 'Lunes a viernes'))  as mediana_viajes_lunes_a_viernes,
        round(median(viajes) filter (where tipo_dia = 'Fin de semana'))    as mediana_viajes_fin_de_semana,
        round(100 * sum(viajes) filter (where tipo_dia = 'Fin de semana') / sum(viajes), 1)
                                                                           as pct_viajes_fin_de_semana,
        round(median(duracion_mediana_min), 1)                             as duracion_mediana_min,
        round(median(estaciones_activas))                                  as estaciones_activas_dia
    from evolucion_diaria
    group by anio
)
select
    d.anio,
    d.primer_dia,
    d.meses_con_datos,
    d.viajes,
    u.usuarios,
    round(d.viajes / u.usuarios, 1) as viajes_por_usuario,
    u.estaciones_usadas,
    d.estaciones_activas_dia,
    d.mediana_viajes_lunes_a_viernes,
    d.mediana_viajes_fin_de_semana,
    d.pct_viajes_fin_de_semana,
    d.duracion_mediana_min,
    -- Viajes por estación activa: separa "hay menos estaciones" de "cada
    -- estación se usa menos".
    round(d.mediana_viajes_lunes_a_viernes / d.estaciones_activas_dia, 1)
        as viajes_por_estacion_lunes_a_viernes
from dias as d
join usuarios as u using (anio)
order by d.anio;
