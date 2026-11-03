-- Pago por renglón (Tesorería): el tesorero elige cuánto paga de cada renglón. Oct/Nov 2026.
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, ANTES de publicar el index.html.
-- Aditivo: una columna nueva y nullable. Los pagos existentes quedan en NULL y siguen con el reparto automático
-- (no se modifica nada de lo pasado). RLS: no cambia (la tabla ya está gateada por sector).
-- Formato: {"<n° de renglón desde 0>": importe en moneda de la OG}, ej. {"1": 675000, "2": 225000}
-- Reversible: alter table public.compras_pagos drop column reparto;
alter table public.compras_pagos add column if not exists reparto jsonb;
