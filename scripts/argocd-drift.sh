#!/usr/bin/env bash
# Compara cada Application declarada en este repo con el objeto vivo en el cluster.
#
# POR QUE EXISTE ESTO
#
# Las Applications de este repo se aplican A MANO (`kubectl apply -f`). No hay app-of-apps que
# las gestione, asi que NADIE reconcilia el fichero contra el objeto vivo: si alguien cambia algo
# en el cluster y no lo baja a git, la divergencia se queda ahi, estable y en silencio, hasta que
# alguien vuelve a aplicar el fichero. Ese dia el cambio entra de golpe sin que nadie lo decida.
#
# Es exactamente lo que paso con `keycloak-local-dev` y `cnpg-operator` (issue #65): las dos
# declaraban `automated: {prune: true, selfHeal: true}` en git y en el cluster no lo tenian. Un
# `kubectl apply` las habria convertido en auto-sync con prune sobre los realms de produccion y
# sobre las CRDs de CNPG respectivamente.
#
# POR QUE NO ES UN `diff` A PELO
#
# El API server BORRA los zero-value al guardar el objeto: `allowEmpty: false`, `prune: false` y
# `group: ""` estan en el fichero y no aparecen en lo vivo, aunque nadie haya tocado nada. Comparar
# en crudo marca 6 de las 8 Applications como divergentes, todas en falso. Por eso este script
# normaliza —quita recursivamente las claves con valor `false`, `null` o `""`— antes de comparar.
# Si alguna vez lo reescribes con `diff` o con `kubectl diff`, vuelves a tener los 6 falsos.
#
# QUE COMPARA: `project`, `source`, `destination`, `syncPolicy` e `ignoreDifferences`. Lo demas
# (`status`, `metadata` gestionado por Argo, `operation`) es del servidor y no se declara.
#
# Uso:
#   ./scripts/argocd-drift.sh              # todas las Applications de apps/
#   ./scripts/argocd-drift.sh -q           # solo el resumen, sin el detalle git-vs-vivo
#
# Salida: una linea por Application. Termina en 1 si hay alguna divergencia, para que sirva si
# algun dia se engancha a algo que mire el exit code.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
QUIET=0

[[ "${1:-}" == "-q" || "${1:-}" == "--quiet" ]] && QUIET=1

command -v kubectl >/dev/null || { echo "ERROR: hace falta kubectl" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || {
  echo "ERROR: hace falta PyYAML (python3 -c 'import yaml')" >&2; exit 2; }

# Los ficheros se descubren, no se listan: una lista fija se queda vieja en cuanto
# alguien anade un chart.
mapfile -t FILES < <(grep -rl --include='*.yaml' '^kind: Application$' "$REPO_ROOT/apps" | sort)

[[ ${#FILES[@]} -gt 0 ]] || { echo "ERROR: no se encontro ninguna Application bajo apps/" >&2; exit 2; }

# El JSON de las Applications lo pide python, no bash: pasarlo por variable de entorno revienta
# con "argument list too long" en cuanto hay unas cuantas Applications en el cluster.
QUIET="$QUIET" REPO_ROOT="$REPO_ROOT" ARGOCD_NS="$ARGOCD_NS" \
python3 - "${FILES[@]}" <<'PY'
import json, os, subprocess, sys, yaml

CAMPOS = ['project', 'source', 'destination', 'syncPolicy', 'ignoreDifferences']

def normaliza(x):
    """Quita lo que el API server no guarda: false, null y cadena vacia.

    Sin esto, `allowEmpty: false` en el fichero y ausente en lo vivo cuenta como
    divergencia, y salen 6 falsos positivos de 8."""
    if isinstance(x, dict):
        return {k: normaliza(v) for k, v in x.items()
                if v is not False and v is not None and v != ''}
    if isinstance(x, list):
        return [normaliza(v) for v in x]
    return x

def clave(x):
    return json.dumps(normaliza(x), sort_keys=True)

salida = subprocess.run(
    ['kubectl', '-n', os.environ['ARGOCD_NS'], 'get', 'applications.argoproj.io', '-o', 'json'],
    capture_output=True, text=True)
if salida.returncode != 0:
    sys.exit(f"ERROR: kubectl fallo: {salida.stderr.strip()}")

live = {a['metadata']['name']: a['spec']
        for a in json.loads(salida.stdout)['items']}
quiet = os.environ['QUIET'] == '1'
root = os.environ['REPO_ROOT'].rstrip('/') + '/'

hay_drift = False

for path in sorted(sys.argv[1:]):
    corto = path[len(root):] if path.startswith(root) else path
    doc = yaml.safe_load(open(path))
    nombre = doc['metadata']['name']
    git = doc['spec']
    vivo = live.get(nombre)

    if vivo is None:
        hay_drift = True
        print(f"AUSENTE  {nombre:32} declarada en {corto}, no existe en el cluster")
        print(f"         -> kubectl apply -f {corto}")
        continue

    difs = [c for c in CAMPOS if clave(git.get(c)) != clave(vivo.get(c))]

    if not difs:
        print(f"OK       {nombre:32} {corto}")
        continue

    hay_drift = True
    print(f"DIVERGE  {nombre:32} en {', '.join(difs)}  ({corto})")
    if quiet:
        continue
    for c in difs:
        print(f"           git : {json.dumps(normaliza(git.get(c)), sort_keys=True)}")
        print(f"           vivo: {json.dumps(normaliza(vivo.get(c)), sort_keys=True)}")

if hay_drift:
    print()
    print("Hay divergencia. NO la resuelvas aplicando el fichero por inercia: decide campo a")
    print("campo de que lado esta la intencion, y mira si hay un README que ya la tenga escrita.")
    sys.exit(1)

print()
print(f"Las {len(sys.argv) - 1} Applications coinciden con el cluster.")
PY
