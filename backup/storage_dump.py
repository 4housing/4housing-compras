#!/usr/bin/env python3
"""Descarga TODOS los archivos de Supabase Storage (todos los buckets) a una carpeta local.

Uso: storage_dump.py <supabase_ref> <carpeta_destino>
Requiere la variable de entorno SUPABASE_SERVICE_KEY (service_role o sb_secret_...).

Solo imprime cantidades, nunca nombres de archivo: el log de Actions de un repo
público es visible para cualquiera.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

PAGE = 1000


def headers(key):
    h = {"apikey": key}
    # Las keys legacy (JWT) van también en Authorization; las nuevas sb_secret_ no.
    if key.startswith("eyJ"):
        h["Authorization"] = "Bearer " + key
    return h


def request(url, key, body=None, retries=4):
    data = json.dumps(body).encode() if body is not None else None
    h = headers(key)
    if data is not None:
        h["Content-Type"] = "application/json"
    for i in range(retries):
        try:
            req = urllib.request.Request(url, data=data, headers=h, method="POST" if data else "GET")
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except Exception:
            if i == retries - 1:
                raise
            time.sleep(2 ** (i + 1))


def list_objects(base, key, bucket, prefix=""):
    """Recorre el bucket recursivamente. Las entradas sin id son carpetas."""
    offset = 0
    while True:
        body = {"prefix": prefix, "limit": PAGE, "offset": offset,
                "sortBy": {"column": "name", "order": "asc"}}
        items = json.loads(request(f"{base}/storage/v1/object/list/{urllib.parse.quote(bucket)}", key, body))
        for it in items:
            path = f"{prefix}/{it['name']}" if prefix else it["name"]
            if it.get("id") is None:
                yield from list_objects(base, key, bucket, path)
            else:
                yield path
        if len(items) < PAGE:
            return
        offset += PAGE


def main():
    ref, dest = sys.argv[1], sys.argv[2]
    key = os.environ["SUPABASE_SERVICE_KEY"]
    base = f"https://{ref}.supabase.co"
    buckets = json.loads(request(f"{base}/storage/v1/bucket", key))
    os.makedirs(dest, exist_ok=True)
    with open(os.path.join(dest, "_buckets.json"), "w") as f:
        json.dump(buckets, f, indent=2)
    total = 0
    for b in buckets:
        name = b["name"]
        n = 0
        for path in list_objects(base, key, name):
            local = os.path.join(dest, name, *path.split("/"))
            os.makedirs(os.path.dirname(local), exist_ok=True)
            url = f"{base}/storage/v1/object/{urllib.parse.quote(name)}/{urllib.parse.quote(path)}"
            with open(local, "wb") as f:
                f.write(request(url, key))
            n += 1
        print(f"  bucket #{buckets.index(b) + 1}: {n} archivos")
        total += n
    print(f"  Storage: {len(buckets)} buckets, {total} archivos")


if __name__ == "__main__":
    main()
