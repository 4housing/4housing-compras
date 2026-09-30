# 4housing-compras — Contexto del proyecto

App interna de **Compras y Operaciones** de 4housing (compras, tesorería, depósito,
pañol, herramientas, mantenimiento, stock). Parte del portal unificado 4housing.

## Stack

- **Frontend:** un solo archivo `index.html` (HTML/CSS/JS vanilla, sin frameworks).
  Acceso a datos por **REST crudo** con wrappers propios (`sbFetch` / `sbFetchAll`),
  no con el query builder de supabase-js. Renombrar tablas = buscar strings de URL
  (`sbFetch('/compras_...')`), no `.from()`.
- **Hosting:** GitHub Pages, org `4housing`, repo `4housing-compras`.
  URL: https://4housing.github.io/4housing-compras/
- **Backend:** Supabase **unificado** del portal → proyecto `wcpkpwxhqdcdljfwzcmy` (wcpk).
  Login **Microsoft (Azure)** vía Supabase Auth. El ref/URL del proyecto es lo que
  usa la app (no el nombre visible del proyecto).
- **Storage:** bucket privado **`facturas`** (subida con token del usuario, descarga
  con URL firmada). Policies: sector compras.

## Datos y acceso (migración sept 2026 desde el proyecto viejo aaqp)

- Todas las tablas tienen prefijo **`compras_`** (ej. `compras_ogs`, `compras_pagos`,
  `compras_proveedores`, `compras_articulos`, `compras_stock_saldos`, …).
- **RLS por sector:** todas gateadas con `tiene_sector('compras')`. Las 4 tablas de
  referencia (`compras_usd_diario`, `compras_usd_diario_oficial`, `compras_idx_facpce`,
  `compras_clasif_renglon`) además son legibles por el sector `eerr`.
- **Control de acceso propio** de la app: `compras_usuarios_autorizados` (flags
  `es_comprador` / `es_tesorero` / `es_certificador` / `ve_confidencial` / `es_admin`).
  Encima está la compuerta de sector del portal. Helper SQL `compras_flag('...')`.
  **Pendiente:** unificar este modelo de roles con el del portal (a definir con Mica/Pablo).
- Datos confidenciales (cuentas, aux_*) solo los ve quien tiene `ve_confidencial`;
  caja/pagos solo los edita `es_tesorero`.

## Reglas de trabajo — NO NEGOCIABLES

1. **No romper lo que ya funciona.** Preferí agregar antes que modificar. Si tocás
   código compartido, `grep` de todos los usos primero. Probá lo que tocaste, no solo
   lo que agregaste.
2. **SQL nunca se ejecuta solo.** Se entrega como `.sql` y lo corre una persona a mano
   en el SQL Editor de Supabase. Sin escritura directa a producción salvo autorización puntual.
3. **Orden de deploy:** primero el SQL (si agrega tablas/columnas), después el HTML.
4. **RLS siempre `authenticated`, nunca `anon`.** Toda tabla nueva con compuerta de
   sector (`tiene_sector('compras')`).
5. **Secretos nunca en `index.html`** (es público). anon/publishable es pública por
   diseño; tokens y service keys, jamás.
6. **Validá el JS con `node --check`** antes de terminar (valida sintaxis, no
   comportamiento: si tocaste algo existente, verificá que siga andando).
7. **Cambios incrementales y aditivos:** una feature por PR, chico y reversible.
8. **Decisiones estructurales se cierran antes de codear.**
9. **Git:** `git pull` antes de empezar; ramas por feature + PR o coordinar antes de
   tocar el `index.html`; commits chicos, descriptivos, en español. Tras `stash pop`/merge,
   chequeá que no queden marcadores de conflicto (`<<<<<<<`) antes de commitear.
10. **Nombres de tablas por sector:** `compras_` acá; el resto `fhcomercial_`,
    `labocomercial_`, `diseno_`, `planificacion_`, `eerr_`, `logistica_`. `core_` reservado.
11. **Datos de negocio nunca al repo público** (dumps `.sql` gitignoreados).
12. **Diagnosticar con evidencia** (`grep`/`diff`), no adivinar. Reportar resultados
    con fidelidad: si algo falla o se saltó, decirlo con la salida real.

## Cómo entregar

- HTML/JS: archivo completo actualizado, validado con `node --check`.
- SQL: archivo `.sql` separado; nunca ejecutado contra producción sin que lo revise y
  corra una persona.
