# Cómo restaurar un backup de las apps de 4housing

Este archivo viaja **dentro de cada backup**, así que sirve aunque GitHub no esté disponible.

## Qué hay en cada backup

Hay un backup por **unidad** (una base Supabase con las apps que la usan):

| Unidad       | Proyecto Supabase      | Apps                                                                     |
|--------------|------------------------|--------------------------------------------------------------------------|
| `compras`    | `aaqpzamcdxldhqyuqlgm` | Compras                                                                  |
| `plataforma` | `wcpkpwxhqdcdljfwzcmy` | Comercial (CRM), Labo Comercial, Diseño, Planificación Taller, Portal    |

En SharePoint, en `Backups-Apps/<unidad>/`:

```
diario/1-lunes.tar.gz.age … 7-domingo.tar.gz.age   → los últimos 7 días
semanal/semana-1 … semana-4.tar.gz.age             → los últimos 4 domingos
mensual/01 … 12.tar.gz.age                          → el día 1 de cada mes (último año)
ULTIMO_BACKUP_OK.txt                                → fecha y sha256 del último backup bueno
```

Cada `.tar.gz.age` tiene un `.info.txt` al lado con la fecha real y el sha256.
Además, SharePoint guarda las versiones anteriores de cada archivo (Historial de versiones).

Adentro del archivo (una vez descifrado):

```
<unidad>-<fecha>/
  db/roles.sql, db/schema.sql, db/data.sql   → para restaurar en un proyecto Supabase NUEVO
  db/completo.dump                           → copia completa (pg_restore), sirve para recuperar tablas sueltas
  db/filas_por_tabla.tsv                     → cantidad aproximada de filas, para controlar
  storage/<bucket>/…                         → todos los archivos subidos (facturas, adjuntos, etc.)
  repos/<app>.bundle                         → el código completo con todo el historial git
  MANIFEST.txt                               → sha256 de cada archivo
```

## 0. Elegir qué backup usar

- **Se rompió algo hoy / alguien borró datos** → el diario de ayer.
- **Virus, hackeo o datos corruptos desde hace días** → elegí uno **anterior** al incidente
  (mirá la fecha en `.info.txt`). Ante la duda, el semanal o el mensual.
- Si sospechás que SharePoint también fue comprometido, usá *Historial de versiones* del
  archivo o la papelera de reciclaje del sitio.

## 1. Descifrar

Necesitás la **clave privada age** (archivo `AGE-SECRET-KEY-…`) que está guardada fuera de
línea (ver "Dónde está la clave" en `backup/README.md` del repo 4housing-compras).
Sin esa clave el backup **no se puede abrir**: no se guarda en GitHub ni en SharePoint.

```bash
# Instalar age: https://github.com/FiloSottile/age/releases  (Windows: age.exe)
sha256sum 3-miercoles.tar.gz.age        # compará con el .info.txt
age -d -i clave-backup.txt 3-miercoles.tar.gz.age | tar -xzf -
```

## 2A. Restaurar TODO en un proyecto Supabase nuevo (desastre total / hackeo)

1. Crear un proyecto nuevo en https://supabase.com (misma región, misma versión de Postgres).
2. En *Project Settings → Database → Connection string* copiar la **Session pooler** URI.
3. Restaurar (con `psql` 15 o superior):

   ```bash
   export NUEVA="postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres"
   psql "$NUEVA" --single-transaction --variable ON_ERROR_STOP=1 \
     --file db/roles.sql --file db/schema.sql \
     --command 'SET session_replication_role = replica' \
     --file db/data.sql
   ```

4. Storage: crear los buckets (ver `storage/_buckets.json`, respetar si son públicos) y subir
   el contenido de `storage/<bucket>/` (desde el panel o con `supabase storage cp -r`).
5. Auth: en *Authentication → Providers* volver a configurar **Azure** (mismo client ID/secret
   de Entra ID) y agregar las URLs de redirección de las apps.
6. Edge Functions (unidad `plataforma`): el código está en `repos/4housing-comercial.bundle`,
   carpeta `supabase/functions`. Desplegar con `supabase functions deploy` y volver a cargar los
   secretos (token de Tango, etc.), que **no** se incluyen en el backup.
7. Apuntar las apps al proyecto nuevo: cambiar `SB_URL` y la anon key en el `index.html`
   de cada app y publicar.
8. **Si fue un hackeo:** rotar todas las claves (service key, contraseña de la base,
   secretos de Azure, token de Tango) antes de volver a operar.

## 2B. Recuperar una tabla o algunos registros (alguien borró datos)

No hace falta pisar la base de producción. Restaurá la tabla en un esquema aparte y copiá lo
que falta:

```bash
pg_restore --list db/completo.dump | grep ' TABLE DATA public ogs '   # buscar la tabla
# Opción simple: restaurar el dump completo en un proyecto Supabase de prueba (o un Postgres
# local) y desde ahí copiar las filas con INSERT … SELECT o exportando a CSV.
pg_restore -d "$BASE_DE_PRUEBA" --no-owner --no-privileges -t ogs db/completo.dump
```

## 3. Restaurar el código de una app

```bash
git clone repos/4housing-compras.bundle 4housing-compras
cd 4housing-compras && git remote set-url origin https://github.com/4housing/4housing-compras.git
git push --mirror origin      # solo si el repo de GitHub se perdió o fue vandalizado
```

GitHub Pages se vuelve a activar en *Settings → Pages* del repo.

## 4. Controlar que quedó bien

- Comparar las filas por tabla con `db/filas_por_tabla.tsv` (es aproximado).
- Entrar a cada app con un usuario real y revisar datos de los últimos días.
