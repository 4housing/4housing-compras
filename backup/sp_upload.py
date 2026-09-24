#!/usr/bin/env python3
"""Sube un archivo a SharePoint (Microsoft Graph) reemplazando el que ya exista.

Uso: sp_upload.py <archivo_local> <ruta/destino/en/la/biblioteca>

Variables de entorno:
  SP_TENANT_ID, SP_CLIENT_ID, SP_CLIENT_SECRET  app registrada en Entra ID
                                               (permiso de aplicación Sites.Selected)
  SP_SITE   sitio destino, p.ej. 4housing22.sharepoint.com:/sites/Backups
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

GRAPH = "https://graph.microsoft.com/v1.0"
CHUNK = 320 * 1024 * 32  # 10 MiB, múltiplo de 320 KiB como exige Graph


def http(method, url, token=None, data=None, headers=None, retries=5):
    h = dict(headers or {})
    if token:
        h["Authorization"] = "Bearer " + token
    for i in range(retries):
        try:
            req = urllib.request.Request(url, data=data, headers=h, method=method)
            with urllib.request.urlopen(req, timeout=300) as r:
                body = r.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503, 504) or i == retries - 1:
                raise SystemExit(f"Graph {method} {e.code}: {e.read()[:500]!r}")
        except urllib.error.URLError:
            if i == retries - 1:
                raise
        time.sleep(2 ** (i + 1))


def get_token():
    tenant = os.environ["SP_TENANT_ID"]
    body = urllib.parse.urlencode({
        "client_id": os.environ["SP_CLIENT_ID"],
        "client_secret": os.environ["SP_CLIENT_SECRET"],
        "scope": "https://graph.microsoft.com/.default",
        "grant_type": "client_credentials",
    }).encode()
    r = http("POST", f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token", data=body,
             headers={"Content-Type": "application/x-www-form-urlencoded"})
    return r["access_token"]


def main():
    local, remote = sys.argv[1], sys.argv[2].strip("/")
    token = get_token()
    site = http("GET", f"{GRAPH}/sites/{os.environ['SP_SITE']}", token)
    drive = http("GET", f"{GRAPH}/sites/{site['id']}/drive", token)
    path = urllib.parse.quote(remote)
    session = http("POST", f"{GRAPH}/drives/{drive['id']}/root:/{path}:/createUploadSession", token,
                   data=json.dumps({"item": {"@microsoft.graph.conflictBehavior": "replace"}}).encode(),
                   headers={"Content-Type": "application/json"})
    size = os.path.getsize(local)
    sent = 0
    with open(local, "rb") as f:
        while sent < size:
            chunk = f.read(CHUNK)
            end = sent + len(chunk) - 1
            # La URL de la sesión ya viene autorizada: no lleva token.
            res = http("PUT", session["uploadUrl"], data=chunk, headers={
                "Content-Length": str(len(chunk)),
                "Content-Range": f"bytes {sent}-{end}/{size}",
            })
            sent = end + 1
    print(f"  subido {remote} ({size / 1048576:.1f} MiB)")
    return res


if __name__ == "__main__":
    main()
