-- =====================================================================
-- 03. Calendario
-- Entrada: raw_feriados
-- Salida:  calendario -> una fila por día de 2024, con el tipo de día
--
-- Un feriado que cae un miércoles se comporta como un domingo, así que
-- el análisis separa los días en "Hábil" y "No hábil" (fin de semana o
-- feriado) en lugar de usar solo el día de la semana.
-- =====================================================================

create or replace table calendario as
with dias as (
    select unnest(range(date '2024-01-01', date '2025-01-01', interval 1 day))::date as fecha
)
select
    d.fecha,
    year(d.fecha)                     as anio,
    month(d.fecha)                    as mes,
    isodow(d.fecha)                   as dia_semana_num,   -- 1 = lunes, 7 = domingo
    case isodow(d.fecha)
        when 1 then 'Lunes'   when 2 then 'Martes'  when 3 then 'Miércoles'
        when 4 then 'Jueves'  when 5 then 'Viernes' when 6 then 'Sábado'
        else 'Domingo'
    end                               as dia_semana,
    f.nombre                          as feriado,
    case
        when f.fecha is not null   then 'No hábil'
        when isodow(d.fecha) >= 6  then 'No hábil'
        else 'Hábil'
    end                               as tipo_dia
from dias as d
left join raw_feriados as f on f.fecha = d.fecha
order by d.fecha;
