#!/usr/bin/env bash
# Genera el backup completo de una unidad (base Supabase + Storage + código),
# lo cifra con age y lo sube a SharePoint con rotación diaria/semanal/mensual.
#
# Uso: run_backup.sh <unidad>      (unidad = nombre en backup/config.json)
#
# Variables de entorno:
#   DB_URL                 cadena de conexión Postgres (Session pooler, puerto 5432)
#   SUPABASE_SERVICE_KEY   service_role / sb_secret_ del proyecto (para Storage)
#   AGE_RECIPIENTS         una o más claves públicas age (una por línea)
#   GH_TOKEN               opcional: token de lectura si algún repo pasa a privado
#   SP_*                   ver sp_upload.py
#   SKIP_UPLOAD=1          genera el archivo cifrado pero no lo sube (pruebas)
set -euo pipefail

UNIDAD="$1"
DIR="$(cd "$(dirname "$0")" && pwd)"
CFG="$DIR/config.json"
REF=$(jq -r --arg u "$UNIDAD" '.unidades[] | select(.nombre==$u) | .supabase_ref' "$CFG")
[ -n "$REF" ] && [ "$REF" != "null" ] || { echo "Unidad desconocida: $UNIDAD" >&2; exit 1; }
RAIZ_SP=$(jq -r '.carpeta_sharepoint' "$CFG")

: "${DB_URL:?Falta DB_URL}" "${SUPABASE_SERVICE_KEY:?Falta SUPABASE_SERVICE_KEY}" "${AGE_RECIPIENTS:?Falta AGE_RECIPIENTS}"

export TZ=America/Argentina/Buenos_Aires
FECHA=$(date +%F)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/$UNIDAD-$FECHA"
mkdir -p "$OUT"/{db,storage,repos}

echo "== [$UNIDAD] Base de datos"
# 1) Formato recomendado por Supabase para restaurar en un proyecto nuevo.
supabase db dump --db-url "$DB_URL" -f "$OUT/db/roles.sql" --role-only
supabase db dump --db-url "$DB_URL" -f "$OUT/db/schema.sql"
supabase db dump --db-url "$DB_URL" -f "$OUT/db/data.sql" --use-copy --data-only
# 2) Copia completa en formato custom (incluye auth, storage metadata, etc.):
#    sirve para restaurar tablas sueltas con pg_restore.
pg_dump "$DB_URL" -Fc -f "$OUT/db/completo.dump"
pg_restore --list "$OUT/db/completo.dump" > /dev/null   # verifica que el dump sea legible
psql "$DB_URL" -At -F $'\t' -c "select schemaname||'.'||relname, n_live_tup from pg_stat_user_tables order by 1" \
  > "$OUT/db/filas_por_tabla.tsv"
echo "  $(wc -l < "$OUT/db/filas_por_tabla.tsv") tablas"

echo "== [$UNIDAD] Storage"
python3 "$DIR/storage_dump.py" "$REF" "$OUT/storage"

echo "== [$UNIDAD] Código"
for repo in $(jq -r --arg u "$UNIDAD" '.unidades[] | select(.nombre==$u) | .repos[]' "$CFG"); do
  url="https://github.com/4housing/$repo.git"
  [ -n "${GH_TOKEN:-}" ] && url="https://x-access-token:$GH_TOKEN@github.com/4housing/$repo.git"
  git clone -q --mirror "$url" "$WORK/$repo.git"
  git -C "$WORK/$repo.git" bundle create -q "$OUT/repos/$repo.bundle" --all
  echo "  $repo ok"
done

cp "$CFG" "$DIR/RESTAURAR.md" "$OUT/"
{
  echo "unidad: $UNIDAD"
  echo "fecha: $(date -Iseconds)"
  echo "supabase_ref: $REF"
  echo "commit_script: ${GITHUB_SHA:-local}"
  echo
  (cd "$OUT" && find . -type f ! -name MANIFEST.txt -print0 | sort -z | xargs -0 sha256sum)
} > "$OUT/MANIFEST.txt"

echo "== [$UNIDAD] Empaquetado y cifrado"
ARCH="$WORK/$UNIDAD.tar.gz.age"
RECIP=()
while read -r k; do [ -n "$k" ] && RECIP+=(-r "$k"); done <<< "$AGE_RECIPIENTS"
tar -C "$WORK" -czf - "$UNIDAD-$FECHA" | age "${RECIP[@]}" -o "$ARCH"
SHA=$(sha256sum "$ARCH" | cut -d' ' -f1)
printf 'unidad: %s\nfecha: %s\nsha256: %s\ntamaño: %s bytes\n' "$UNIDAD" "$(date -Iseconds)" "$SHA" "$(stat -c %s "$ARCH")" > "$WORK/info.txt"
echo "  $(du -h "$ARCH" | cut -f1) cifrado"

# Rotación: cada ranura se sobreescribe, así el espacio queda acotado.
#   diario/  7 archivos (uno por día de la semana)
#   semanal/ 4 archivos (los domingos, semana ISO mod 4)
#   mensual/ 12 archivos (el día 1 de cada mes)
DIAS=(x 1-lunes 2-martes 3-miercoles 4-jueves 5-viernes 6-sabado 7-domingo)
DESTINOS=("diario/${DIAS[$(date +%u)]}")
[ "$(date +%u)" = 7 ] && DESTINOS+=("semanal/semana-$(( 10#$(date +%V) % 4 + 1 ))")
[ "$(date +%d)" = 01 ] && DESTINOS+=("mensual/$(date +%m)")

if [ "${SKIP_UPLOAD:-}" = 1 ]; then
  cp "$ARCH" "${KEEP_DIR:-.}/"
  echo "SKIP_UPLOAD: no se sube. Destinos: ${DESTINOS[*]}"
  exit 0
fi

echo "== [$UNIDAD] Subida a SharePoint"
for d in "${DESTINOS[@]}"; do
  python3 "$DIR/sp_upload.py" "$ARCH" "$RAIZ_SP/$UNIDAD/$d.tar.gz.age"
  python3 "$DIR/sp_upload.py" "$WORK/info.txt" "$RAIZ_SP/$UNIDAD/$d.info.txt"
done
python3 "$DIR/sp_upload.py" "$WORK/info.txt" "$RAIZ_SP/$UNIDAD/ULTIMO_BACKUP_OK.txt"
echo "== [$UNIDAD] Listo"
