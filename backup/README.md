# Backup diario de las apps

Todos los días a las 03:00 (hora Argentina) el workflow `.github/workflows/backup-apps.yml`
hace un backup completo de cada base Supabase, sus archivos de Storage y el código de todas
las apps, lo **cifra** y lo sube a SharePoint. Para restaurar: [`RESTAURAR.md`](RESTAURAR.md).

## Qué se respalda

Las 6 apps usan **dos** proyectos Supabase, así que hay un backup por proyecto ("unidad"),
definido en [`config.json`](config.json):

- **compras** → base `aaqpzamcdxldhqyuqlgm` + repo `4housing-compras`
- **plataforma** → base `wcpkpwxhqdcdljfwzcmy` (compartida) + repos `4housing-comercial`,
  `labo-comercial`, `diseno-4housing`, `planificacion-taller`, `portal`

Cada backup incluye: roles + esquema (tablas, RLS, funciones, triggers) + datos, un dump
completo `pg_dump -Fc` (incluye usuarios de `auth`), todos los archivos de todos los buckets,
y el historial git completo de cada repo.

**No incluye** (hay que tenerlos anotados aparte): secretos de Edge Functions (token de Tango,
etc.), configuración del proveedor Azure en Supabase Auth, flujos de Power Automate.

## Rotación (se va sobreescribiendo)

`Backups-Apps/<unidad>/` en SharePoint:

| Carpeta    | Archivos | Cuándo                         | Cubre            |
|------------|----------|--------------------------------|------------------|
| `diario/`  | 7        | todos los días (uno por día)   | última semana    |
| `semanal/` | 4        | los domingos                   | último mes       |
| `mensual/` | 12       | el día 1                       | último año       |

El espacio queda fijo en ~23 copias por unidad. Si pasa algo (virus, hackeo) y tardamos días
en darnos cuenta, siempre hay una copia anterior al incidente.

## Por qué cifrado

El backup contiene toda la información de la empresa. Se cifra con
[age](https://age-encryption.org) usando **solo la clave pública**: GitHub y SharePoint nunca
ven la clave privada. Si alguien entra a SharePoint o a la cuenta de Microsoft, no puede leer
los backups. La contracara: **si se pierde la clave privada, los backups no sirven**.

## Puesta en marcha (una sola vez)

### 1. Clave de cifrado

En una computadora de confianza (Windows: bajar `age.exe` de
https://github.com/FiloSottile/age/releases):

```bash
age-keygen -o clave-backup-4housing.txt
```

Imprime la clave pública (`age1…`). La clave privada queda en el archivo.

**Dónde está la clave:** guardar `clave-backup-4housing.txt` en **al menos dos** lugares fuera
de Microsoft 365 y de GitHub (ej.: gestor de contraseñas + pendrive en caja fuerte). Conviene
generar una segunda clave para otra persona de confianza y poner las dos públicas (una por
línea) en `BACKUP_AGE_RECIPIENTS`: cualquiera de las dos abre el backup.

### 2. Sitio de SharePoint

Crear un sitio **dedicado** (ej. `Backups`) con acceso solo para administradores, para que un
usuario comprometido no pueda borrar los backups. Dejar activado el historial de versiones de
la biblioteca y, si el plan lo permite, una directiva de retención de Microsoft Purview.

### 3. App en Entra ID para subir a SharePoint

1. *Entra ID → Registros de aplicaciones → Nuevo*: `4housing-backups`.
2. *Permisos de API → Microsoft Graph → Permisos de aplicación → `Sites.Selected`* →
   Conceder consentimiento de administrador. (Solo le da acceso a los sitios que le habilites,
   no a todo SharePoint.)
3. Darle permiso de escritura **solo** al sitio de backups (Graph Explorer, como admin):
   ```
   POST https://graph.microsoft.com/v1.0/sites/4housing22.sharepoint.com:/sites/Backups:/permissions
   { "roles": ["write"],
     "grantedToIdentities": [{ "application": { "id": "<client-id>", "displayName": "4housing-backups" } }] }
   ```
   (Si da error con la ruta, primero `GET …/sites/4housing22.sharepoint.com:/sites/Backups` y usar el `id`.)
4. *Certificados y secretos → Nuevo secreto de cliente* (anotar vencimiento: al vencer, el
   backup falla y avisa).

### 4. Secretos y variables en GitHub

*Settings → Secrets and variables → Actions* del repo que corre el workflow:

| Tipo     | Nombre                    | Valor                                                                 |
|----------|---------------------------|-----------------------------------------------------------------------|
| Secret   | `DB_URL_COMPRAS`          | Supabase compras → *Connect* → **Session pooler** URI (con password)  |
| Secret   | `SERVICE_KEY_COMPRAS`     | Supabase compras → *API Keys* → service_role / secret key             |
| Secret   | `DB_URL_PLATAFORMA`       | ídem, proyecto `wcpkpwxhqdcdljfwzcmy`                                 |
| Secret   | `SERVICE_KEY_PLATAFORMA`  | ídem                                                                  |
| Secret   | `SP_CLIENT_SECRET`        | secreto de la app del paso 3                                          |
| Secret   | `BACKUP_TEAMS_WEBHOOK_URL`| opcional: webhook de Teams para avisar fallas                         |
| Secret   | `BACKUP_GH_TOKEN`         | opcional: token de solo lectura, si algún repo pasa a privado         |
| Variable | `BACKUP_AGE_RECIPIENTS`   | clave(s) pública(s) `age1…`, una por línea                            |
| Variable | `SP_TENANT_ID`            | `c408b6d8-ae0b-4d30-9056-da52e18116c4`                                |
| Variable | `SP_CLIENT_ID`            | client ID de la app del paso 3                                        |
| Variable | `SP_SITE`                 | `4housing22.sharepoint.com:/sites/Backups`                            |

Usar la URI **Session pooler** (no la "Direct connection"): los servidores de GitHub no
tienen IPv6.

### 5. Probar

*Actions → Backup de apps → Run workflow*. Revisar que aparezcan los archivos en SharePoint y
**hacer una restauración de prueba** (ver `RESTAURAR.md`, sección 2B) con la clave privada.
Repetir la prueba de restauración cada 3–6 meses: un backup que nunca se probó no es un backup.

## Si falla

GitHub manda un mail al que configuró el workflow y, si está `BACKUP_TEAMS_WEBHOOK_URL`, avisa
por Teams. `ULTIMO_BACKUP_OK.txt` en cada carpeta muestra la fecha del último backup bueno.

Ojo: GitHub desactiva los workflows programados de repos públicos después de 60 días sin
commits. Si el repo queda quieto tanto tiempo, reactivarlo desde la pestaña Actions.

## Probar localmente

```bash
SKIP_UPLOAD=1 KEEP_DIR=/tmp DB_URL=... SUPABASE_SERVICE_KEY=... AGE_RECIPIENTS=age1... \
  backup/run_backup.sh compras
```

Requiere `supabase` CLI (usa Docker), `pg_dump`/`psql` ≥ versión del servidor, `age`, `jq`.
