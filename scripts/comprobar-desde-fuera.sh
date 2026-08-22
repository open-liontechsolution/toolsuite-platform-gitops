#!/usr/bin/env bash
# Comprueba un host publico DESDE FUERA de esta red, por SSH al VPS de OVH.
#
# POR QUE EXISTE ESTO
#
# En España hay bloqueos judiciales por IP durante las retransmisiones de futbol que dejan sin
# ruta rangos enteros del plan gratuito de Cloudflare —104.21.0.0/16 y 172.67.0.0/16—, donde
# caen todos nuestros hosts. Mientras dura, un `curl` desde casa se cuelga hasta el timeout y
# NO SIGNIFICA NADA: el servicio puede estar perfectamente. El 22/08/2026 la ventana duro seis
# horas seguidas desde las 17:00, no noventa minutos, y por el camino parecio que un despliegue
# habia tumbado produccion. No lo habia hecho.
#
# El VPS de NetBird esta en OVH (Francia), fuera de la jurisdiccion del bloqueo, asi que ve la
# realidad. Detalle largo en docs/guides/troubleshooting.md.
#
# DOS TRAMPAS QUE COSTARON UN RATO, y son la razon de que esto sea un script y no una linea:
#
#   1. SIN USER-AGENT DE NAVEGADOR, CLOUDFLARE DEVUELVE 403. El UA por defecto de curl desde
#      una IP de datacenter dispara el desafio antibot: responde `403` con la cabecera
#      `cf-mitigated: challenge`, en 70ms. Se lee como "el host esta caido" y es justo lo
#      contrario — el host esta vivo y quien corta es Cloudflare. Con UA de navegador pasa.
#   2. La IP del VPS no se escribe aqui: sale del inventario de kxs-ansible, que es su dueño.
#
# Uso:
#   ./scripts/comprobar-desde-fuera.sh                       # los hosts de siempre
#   ./scripts/comprobar-desde-fuera.sh <host> [<host>...]    # los que le digas
#   ./scripts/comprobar-desde-fuera.sh --oidc <host> <realm> # lee el issuer del realm
#
# Entorno:
#   KXS=~/Proyectos/kxs-ansible    donde vive el inventario y la clave SSH
set -euo pipefail

KXS="${KXS:-$HOME/Proyectos/kxs-ansible}"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36"

HOSTS_POR_DEFECTO=(
  dealtracker.liontechsolution.com
  keycloak.liontechsolution.com
  keycloak-dev.liontechsolution.com
)

[[ -d "$KXS" ]] || { echo "no encuentro $KXS (¿KXS?)" >&2; exit 1; }
command -v ssh >/dev/null || { echo "hace falta ssh" >&2; exit 2; }

# La IP y el usuario salen del inventario, que es donde estan declarados de verdad.
leer_inventario() {
  python3 - "$KXS/inventory/hosts.yml" <<'PY'
import sys, yaml
def buscar(n):
    if isinstance(n, dict):
        if 'netbird-vps' in n:
            return n['netbird-vps']
        for v in n.values():
            r = buscar(v)
            if r:
                return r
    return None
h = buscar(yaml.safe_load(open(sys.argv[1])))
if not h:
    sys.exit("no encuentro netbird-vps en el inventario")
print(h['ansible_host'], h.get('ansible_user', 'ubuntu'))
PY
}

read -r VPS_IP VPS_USER <<<"$(leer_inventario)"
CLAVE="$KXS/.sshkeys/netbird-vps"
[[ -f "$CLAVE" ]] || { echo "no encuentro la clave $CLAVE" >&2; exit 1; }

remoto() { # remoto <script-sh>
  ssh -i "$CLAVE" -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new \
    "$VPS_USER@$VPS_IP" "$1"
}

if [[ "${1:-}" == "--oidc" ]]; then
  HOST="${2:?falta el host}"; REALM="${3:?falta el realm}"
  remoto "curl -sS -m 20 -A '$UA' 'https://$HOST/realms/$REALM/.well-known/openid-configuration'" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(f"  {k:24}= {d[k]}") for k in ["issuer","authorization_endpoint","token_endpoint","jwks_uri"]]'
  exit 0
fi

HOSTS=("$@")
[[ ${#HOSTS[@]} -eq 0 ]] && HOSTS=("${HOSTS_POR_DEFECTO[@]}")

echo "desde $VPS_USER@$VPS_IP (OVH, fuera del bloqueo):"
for h in "${HOSTS[@]}"; do
  printf '  %-38s ' "$h"
  remoto "curl -sS -m 20 -A '$UA' -o /dev/null -w 'http=%{http_code} t=%{time_total}s\n' 'https://$h/'" \
    || echo "sin respuesta"
done
