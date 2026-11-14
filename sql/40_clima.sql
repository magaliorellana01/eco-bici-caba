-- =====================================================================
-- 40. Pregunta 4: ¿Cómo influyen la lluvia y la temperatura?
-- Entrada: viajes, calendario, raw_clima_diario, raw_clima_horario
-- Salida:  dias_clima            -> una fila por día: viajes y clima
--          efecto_lluvia         -> viajes según cuánto llovió en el día
--          efecto_lluvia_horaria -> viajes en una hora con lluvia vs sin lluvia
--          efecto_temperatura    -> viajes según la temperatura máxima
--
-- Solo días hábiles: en días no hábiles hay pocos viajes y el uso es de
-- paseo, así que mezclarlos confundiría el efecto del clima con el del día.
--
-- Problema a controlar: la estacionalidad. En invierno llueve distinto,
-- hace frío y además hay vacaciones. Por eso cada día lluvioso se compara
-- con los días secos DEL MISMO MES, y no con el promedio del año.
-- =====================================================================


create or replace table dias_clima as
with viajes_dia as (
    select fecha_inicio::date as fecha, count(*) as viajes
    from viajes
    group by fecha
)
select
    c.fecha,
    c.mes,
    c.tipo_dia,
    coalesce(v.viajes, 0)           as viajes,
    k.temperature_2m_max            as temp_max,
    k.temperature_2m_min            as temp_min,
    k.temperature_2m_mean           as temp_media,
    k.precipitation_sum             as lluvia_mm,
    k.precipitation_hours           as horas_con_lluvia,
    -- Umbrales habituales en meteorología: menos de 1 mm es un día seco.
    case
        when k.precipitation_sum < 1  then '1. Seco (menos de 1 mm)'
        when k.precipitation_sum < 10 then '2. Lluvia leve (1 a 10 mm)'
        when k.precipitation_sum < 25 then '3. Lluvia moderada (10 a 25 mm)'
        else '4. Lluvia fuerte (25 mm o más)'
    end                             as categoria_lluvia
from calendario as c
join raw_clima_diario as k using (fecha)
left join viajes_dia  as v using (fecha)
order by c.fecha;


-- Cada día hábil, comparado con la mediana de los días hábiles secos de su mes.
create or replace view efecto_lluvia as
with referencia as (
    select mes, median(viajes) as viajes_dia_seco
    from dias_clima
    where tipo_dia = 'Hábil' and lluvia_mm < 1
    group by mes
)
select
    d.categoria_lluvia,
    count(*)                                                   as dias,
    round(avg(d.viajes))                                       as viajes_promedio,
    round(100 * (median(d.viajes / r.viajes_dia_seco) - 1), 1) as variacion_vs_dia_seco_pct
from dias_clima as d
join referencia as r using (mes)
where d.tipo_dia = 'Hábil'
group by d.categoria_lluvia
order by d.categoria_lluvia;


-- Hora por hora: viajes que empiezan en una hora con lluvia (1 mm o más),
-- comparados con la misma hora del día, en días hábiles secos del mismo mes.
create or replace view efecto_lluvia_horaria as
with viajes_hora as (
    select date_trunc('hour', fecha_inicio) as momento, count(*) as viajes
    from viajes
    group by momento
),
horas as (
    select
        h.momento,
        month(h.momento)                       as mes,
        hour(h.momento)                        as hora,
        h.precipitation                        as lluvia_mm,
        coalesce(v.viajes, 0)                  as viajes
    from raw_clima_horario as h
    join calendario as c on c.fecha = h.momento::date and c.tipo_dia = 'Hábil'
    left join viajes_hora as v using (momento)
),
referencia as (
    select mes, hora, median(viajes) as viajes_hora_seca
    from horas
    where lluvia_mm = 0
    group by mes, hora
)
select
    case
        when h.lluvia_mm = 0   then '1. Sin lluvia'
        when h.lluvia_mm < 1   then '2. Llovizna (menos de 1 mm)'
        when h.lluvia_mm < 4   then '3. Lluvia (1 a 4 mm)'
        else '4. Lluvia fuerte (4 mm o más)'
    end                                                         as lluvia_en_la_hora,
    count(*)                                                    as horas,
    round(100 * (median(h.viajes / r.viajes_hora_seca) - 1), 1) as variacion_vs_hora_seca_pct
from horas as h
join referencia as r using (mes, hora)
-- Se excluye la madrugada: con muy pocos viajes, los porcentajes no son estables.
where h.hora between 6 and 23
  and r.viajes_hora_seca > 0
group by lluvia_en_la_hora
order by lluvia_en_la_hora;


-- Temperatura, solo en días hábiles secos, para separarla del efecto lluvia.
-- Ojo: la temperatura va de la mano con la estación del año (en julio hace
-- frío y además hay vacaciones de invierno), así que este efecto no está
-- tan aislado como el de la lluvia.
create or replace view efecto_temperatura as
select
    (floor(temp_max / 5) * 5)::int                 as temp_max_desde,
    (floor(temp_max / 5) * 5)::int + 5             as temp_max_hasta,
    count(*)                                       as dias,
    round(avg(viajes))                             as viajes_promedio
from dias_clima
where tipo_dia = 'Hábil' and lluvia_mm < 1
group by all
-- Rangos con menos de 10 días (los extremos) no dan un promedio confiable.
having count(*) >= 10
order by temp_max_desde;
