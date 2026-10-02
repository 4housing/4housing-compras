-- Índices: IPIM Nacional (INDEC) como columna nueva en compras_idx_ipc.
-- Correr a mano en el SQL Editor de Supabase del proyecto wcpk (wcpkpwxhqdcdljfwzcmy),
-- ANTES de publicar el index.html que muestra la columna (si no, cargar un período de IPC
-- falla porque la app manda el campo ipim y la columna no existe).
--
-- No borra ni modifica nada existente: agrega la columna "ipim" y la completa con los 80
-- períodos del histórico que pasó Micaela (IPIM.xlsx, 2020/01 a 2026/08). Si un período
-- todavía no existe en la tabla (ej. no se cargó el IPC de ese mes), se crea la fila solo con IPIM.
-- La columna "empalme" (IPC Nac. empalme IPIM) queda como está.
-- RLS: la tabla ya tiene su policy (authenticated + tiene_sector('compras')); una columna nueva
-- queda cubierta por esa misma policy, no hace falta tocarla.

begin;

alter table public.compras_idx_ipc add column if not exists ipim numeric;

with datos(periodo, ipim) as (values
  (202001, 446.3),
  (202002, 451.3),
  (202003, 455.6),
  (202004, 449.7),
  (202005, 451.3),
  (202006, 467.8),
  (202007, 484.4),
  (202008, 504.2),
  (202009, 522.9),
  (202010, 547.3),
  (202011, 570.1),
  (202012, 595.2),
  (202101, 628.3),
  (202102, 666.5),
  (202103, 692.4),
  (202104, 725.5),
  (202105, 748.8),
  (202106, 772.3),
  (202107, 789.5),
  (202108, 809.4),
  (202109, 832.0),
  (202110, 855.7),
  (202111, 880.9),
  (202112, 900.8),
  (202201, 934.3),
  (202202, 978.6),
  (202203, 1040.5),
  (202204, 1102.0),
  (202205, 1158.9),
  (202206, 1214.8),
  (202207, 1300.8),
  (202208, 1407.2),
  (202209, 1484.3),
  (202210, 1555.2),
  (202211, 1653.1),
  (202212, 1754.6),
  (202301, 1868.3),
  (202302, 1999.6),
  (202303, 2100.8),
  (202304, 2246.4),
  (202305, 2405.5),
  (202306, 2585.7),
  (202307, 2767.1),
  (202308, 3284.9),
  (202309, 3587.5),
  (202310, 3858.7),
  (202311, 4287.0),
  (202312, 6603.4),
  (202401, 7788.9),
  (202402, 8579.9),
  (202403, 9044.9),
  (202404, 9356.9),
  (202405, 9682.8),
  (202406, 9940.1),
  (202407, 10246.5),
  (202408, 10458.6),
  (202409, 10665.3),
  (202410, 10791.5),
  (202411, 10941.223782),
  (202412, 11034.043786),
  (202501, 11200.301972),
  (202502, 11384.050547),
  (202503, 11552.832553),
  (202504, 11880.250204),
  (202505, 11849.378594),
  (202506, 12044.4),
  (202507, 12387.3),
  (202508, 12771.7),
  (202509, 13243.426977),
  (202510, 13387.004502),
  (202511, 13599.3),
  (202512, 13925.559845),
  (202601, 14157.7),
  (202602, 14296.3),
  (202603, 14780.133332),
  (202604, 15542.5),
  (202605, 15931.96761),
  (202606, 16104.174032),
  (202607, 16233.7),
  (202608, 16580.328144)
),
upd as (
  update public.compras_idx_ipc t set ipim = d.ipim
  from datos d where t.periodo = d.periodo
  returning t.periodo
)
insert into public.compras_idx_ipc (periodo, ipim)
select d.periodo, d.ipim from datos d
where not exists (select 1 from upd u where u.periodo = d.periodo)
  and not exists (select 1 from public.compras_idx_ipc t where t.periodo = d.periodo);

commit;

-- Control (debe dar 80 filas con ipim, de 202001 a 202608):
select count(ipim) as con_ipim, min(periodo) filter (where ipim is not null) as desde,
       max(periodo) filter (where ipim is not null) as hasta
from public.compras_idx_ipc;
