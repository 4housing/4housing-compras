-- Pañol · cambia el galpón 'LA HUELLA 610' por 'HUE 610' en lo ya cargado y saca el viejo del diccionario.
-- Correr A MANO en el SQL Editor. Si hubiera un período CERRADO con erogaciones en 'LA HUELLA 610', el candado de cierres hace fallar
-- todo el bloque (no queda nada a medias): reabrir ese mes, correr esto y volver a cerrar.
begin;
insert into public.compras_panol_galpones (nombre, creado_por) values ('HUE 610', 'sql') on conflict do nothing;
update public.compras_panol_egresos set galpon = 'HUE 610' where galpon = 'LA HUELLA 610';
delete from public.compras_panol_galpones where upper(btrim(nombre)) = 'LA HUELLA 610';
commit;
