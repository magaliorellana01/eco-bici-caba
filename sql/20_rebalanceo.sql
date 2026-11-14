-- =====================================================================
-- 20. Pregunta 2: ¿Qué estaciones se vacían o se llenan?
-- Entrada: viajes, estaciones, calendario
-- Salida:  flujo_horario -> llegadas, salidas y saldo acumulado por estación
--                           y hora, en un día hábil promedio
--          saldo_diario  -> para cada estación y día hábil, cuántas bicis
--                           llegó a perder y a ganar en el día
--          rebalanceo    -> diagnóstico y recomendación por estación
--
-- Idea: si una estación arranca el día con S bicis, a cada momento tiene
-- S + (llegadas - salidas acumuladas hasta ese momento). En un día dado:
--   * no se vacía si S >= la mayor pérdida del día
--   * no se llena si S + la mayor ganancia del día <= capacidad
-- Se prueban todos los S posibles (de 0 a la capacidad) y se elige el que
-- cubre más días hábiles. Si ni el mejor S cubre el 90% de los días, la
-- estación necesita que se muevan bicis durante el día.
--
-- Solo días hábiles: es donde están los picos y donde el rebalanceo
-- importa. Los viajes no incluyen los movimientos de los camiones de
-- rebalanceo, así que el saldo refleja solo la demanda de los usuarios.
-- =====================================================================


-- Cada viaje genera una salida (-1) en su origen y una llegada (+1) en su destino.
create or replace view movimientos_habiles as
select v.id_estacion_origen as id_estacion, v.fecha_inicio as momento, -1 as delta
from viajes as v
join calendario as c on c.fecha = v.fecha_inicio::date and c.tipo_dia = 'Hábil'
union all
select v.id_estacion_destino, v.fecha_fin, 1
from viajes as v
join calendario as c on c.fecha = v.fecha_fin::date and c.tipo_dia = 'Hábil';


-- Días hábiles en que cada estación estuvo en servicio. Las estaciones
-- que se abrieron durante el año se promedian solo sobre sus días activos.
create or replace view dias_activos as
select e.id_estacion, count(*) as dias_habiles
from estaciones as e
join calendario as c
  on c.fecha between e.primer_uso::date and e.ultimo_uso::date
 and c.tipo_dia = 'Hábil'
group by e.id_estacion;


-- Día hábil promedio, hora por hora. Se completa la grilla de 24 horas
-- para que las horas sin movimientos cuenten como 0 en el acumulado.
create or replace table flujo_horario as
with por_hora as (
    select
        id_estacion,
        hour(momento)                    as hora,
        count(*) filter (where delta = 1)  as llegadas,
        count(*) filter (where delta = -1) as salidas
    from movimientos_habiles
    group by id_estacion, hora
),
grilla as (
    select id_estacion, dias_habiles, unnest(range(24)) as hora
    from dias_activos
)
select
    g.id_estacion,
    g.hora,
    round(coalesce(p.llegadas, 0) / g.dias_habiles, 2)                    as llegadas_prom,
    round(coalesce(p.salidas, 0) / g.dias_habiles, 2)                     as salidas_prom,
    round((coalesce(p.llegadas, 0) - coalesce(p.salidas, 0)) / g.dias_habiles, 2) as saldo_prom,
    round(sum((coalesce(p.llegadas, 0) - coalesce(p.salidas, 0)) / g.dias_habiles)
          over (partition by g.id_estacion order by g.hora), 2)          as saldo_acumulado_prom
from grilla as g
left join por_hora as p using (id_estacion, hora)
order by g.id_estacion, g.hora;


-- Para cada estación y día: el saldo acumulado viaje a viaje, y de ahí la
-- mayor pérdida y la mayor ganancia del día (contando desde las 0 h).
create or replace table saldo_diario as
with acumulado as (
    select
        id_estacion,
        momento::date as fecha,
        sum(delta) over (
            partition by id_estacion, momento::date
            order by momento
            rows between unbounded preceding and current row
        ) as saldo
    from movimientos_habiles
)
select
    id_estacion,
    fecha,
    greatest(0, -min(saldo)) as perdida_maxima,
    greatest(0, max(saldo))  as ganancia_maxima
from acumulado
group by id_estacion, fecha;


-- Diagnóstico por estación. Se trabaja con días reales y no con el día
-- promedio, porque el promedio esconde los días malos.
create or replace table rebalanceo as
with stock_candidato as (
    -- Para cada stock inicial posible, en qué % de días hábiles alcanza.
    select
        d.id_estacion,
        s.stock,
        avg((d.perdida_maxima <= s.stock
             and s.stock + d.ganancia_maxima <= e.capacidad)::int) as pct_dias_cubiertos
    from saldo_diario as d
    join estaciones as e using (id_estacion)
    cross join lateral (select unnest(range(e.capacidad + 1)) as stock) as s
    where e.capacidad is not null
    group by d.id_estacion, s.stock
),
mejor_stock as (
    -- El stock que cubre más días; ante un empate, el más bajo.
    select
        id_estacion,
        stock               as stock_recomendado,
        pct_dias_cubiertos
    from stock_candidato
    qualify row_number() over (
        partition by id_estacion
        order by pct_dias_cubiertos desc, stock
    ) = 1
),
intervencion as (
    -- Arrancando con el stock recomendado, cuántas bicis faltan (hay que
    -- reponer) o sobran (hay que retirar) en un día malo: percentil 90.
    select
        d.id_estacion,
        ceil(quantile_cont(greatest(0, d.perdida_maxima - m.stock_recomendado), 0.9))
            as reponer_p90,
        ceil(quantile_cont(greatest(0, m.stock_recomendado + d.ganancia_maxima - e.capacidad), 0.9))
            as retirar_p90
    from saldo_diario as d
    join mejor_stock  as m using (id_estacion)
    join estaciones   as e using (id_estacion)
    group by d.id_estacion
),
curva as (
    select
        id_estacion,
        round(sum(llegadas_prom + salidas_prom))     as movimientos_dia,
        arg_min(hora, saldo_acumulado_prom)          as hora_mas_vacia,
        arg_max(hora, saldo_acumulado_prom)          as hora_mas_llena,
        round(min(saldo_acumulado_prom), 1)          as perdida_prom,
        round(max(saldo_acumulado_prom), 1)          as ganancia_prom
    from flujo_horario
    group by id_estacion
)
select
    e.id_estacion,
    e.nombre,
    e.barrio,
    e.lat,
    e.lon,
    e.capacidad,
    c.movimientos_dia,
    c.hora_mas_vacia,
    c.hora_mas_llena,
    -- Con qué cantidad de bicis conviene arrancar el día (antes de las 5 h)
    -- y en qué % de los días hábiles alcanza con eso, sin mover nada.
    m.stock_recomendado,
    round(100 * m.pct_dias_cubiertos, 1) as pct_dias_cubiertos,
    -- Lo que hay que mover durante un día malo (9 de cada 10 días alcanza).
    i.reponer_p90,
    i.retirar_p90,
    -- Prioridad según en qué % de los días alcanza con el stock inicial.
    case
        when e.capacidad is null           then '5. Sin dato de capacidad'
        when m.pct_dias_cubiertos < 0.5    then '1. Crítica'
        when m.pct_dias_cubiertos < 0.7    then '2. Alta'
        when m.pct_dias_cubiertos < 0.9    then '3. Media'
        else '4. Sin intervención'
    end as prioridad,
    -- Qué tipo de intervención necesita. Si una necesidad no duplica a la
    -- otra, la estación necesita las dos cosas en el mismo día.
    case
        when e.capacidad is null or m.pct_dias_cubiertos >= 0.9 then null
        when i.reponer_p90 >= 2 * i.retirar_p90 then 'Se vacía'
        when i.retirar_p90 >= 2 * i.reponer_p90 then 'Se llena'
        else 'Se vacía y se llena'
    end as tipo_problema
from estaciones as e
join curva             as c using (id_estacion)
left join mejor_stock  as m using (id_estacion)
left join intervencion as i using (id_estacion)
where e.id_estacion in (select id_estacion from saldo_diario)
order by m.pct_dias_cubiertos nulls last, c.movimientos_dia desc;
