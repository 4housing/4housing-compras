-- Sueldos % (compras_idx_sueldos.pct): corrige 2026/07, que quedó cargado como porcentaje (2.82)
-- cuando el resto de la columna está en fracción (2026/06 = 0.0289 = 2,89%).
-- Correr a mano en el SQL Editor de wcpk ANTES de publicar el index.html que muestra la columna en %
-- (si no, 2026/07 se vería como 282,00%).
-- Solo toca esa fila y solo si sigue mayor a 1 (si ya se corrigió, no hace nada).

update public.compras_idx_sueldos
set pct = pct / 100
where periodo = 202607 and pct > 1;

-- Control: ninguna fila debería quedar con pct > 1 (= más de 100% mensual).
select periodo, ars, pct from public.compras_idx_sueldos
where pct > 1 or periodo >= 202601
order by periodo desc;
