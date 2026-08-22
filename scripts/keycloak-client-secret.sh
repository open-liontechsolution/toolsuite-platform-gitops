#!/usr/bin/env bash
# Devuelve el secreto de un client confidencial de Keycloak.
#
# POR QUE EXISTE ESTO
#
# Los clients se declaran en `apps/security/keycloak/realms/` y los aplica keycloak-config-cli
# (issues #49 y #50), pero el secreto de un client confidencial NO se declara: lo genera
# Keycloak al crearlo. Es deliberado y es lo que hace que el modelo funcione —config-cli, con
# `secret` ausente en el fichero, ni lo compara ni lo toca (`ClientImportService.isClientEqual`
# devuelve true sin llegar a consultarlo), asi que la reconciliacion de las 04:00 no lo rota.
#
# La consecuencia es que hay que ir a buscarlo al servidor una vez, y esa es la unica razon de
# este script: que ese paso deje rastro y sea siempre el mismo, en vez de un `kcadm.sh` a mano
# desde el pod que no aparece en ningun repositorio.
#
# EL SECRETO SALE POR STDOUT Y NADA MAS, para que se pueda encadenar sin tocar disco:
#
#   ./scripts/keycloak-client-secret.sh deal-tracker-dev deal-tracker-api \
#     | kubeseal --raw --from-file=/dev/stdin --namespace deal-tracker-qa --name deal-tracker-config \
#       --controller-name sealed-secrets --controller-namespace kube-system
#
# Ese ciphertext va a `deal-tracker/overlays/*` de k3s-local-apps-manifests, bajo
# KEYCLOAK_ADMIN_CLIENT_SECRET. El sellado es por namespace: el mismo secreto para dos
# namespaces se sella dos veces, y los ciphertexts salen distintos.
#
# NO ES COMO LA CONTRASENA DE `keycloak-user.sh`. Aquella es temporal y muere en el primer
# login; esta es de larga vida y da acceso a la Admin API con `manage-users`. No se guarda en
# disco, no se pega en un chat y no se deja en el scrollback mas de lo imprescindible.
#
# LAS CREDENCIALES DE ADMIN NO SALEN DEL POD: `kcadm.sh` se autentica dentro del contenedor con
# las variables que este ya recibe por `envFrom` del secret `keycloak-admin-credentials`.
#
# El helper `kc()` y las comprobaciones son una COPIA de las de `scripts/keycloak-user.sh`. Con
# dos consumidores un `scripts/lib/kc.sh` es una indireccion que no paga; si aparece un tercero,
# se extrae entonces. Si tocas uno, mira el otro.
#
# Uso:
#   ./scripts/keycloak-client-secret.sh <realm> <clientId>
#
# Ejemplos:
#   ./scripts/keycloak-client-secret.sh deal-tracker-dev deal-tracker-api
#   KC_NS=security-prod KC_POD=keycloak-prod-0 \
#     ./scripts/keycloak-client-secret.sh deal-tracker-prod deal-tracker-api
#
# HAY DOS INSTANCIAS DE KEYCLOAK, y este script habla con UNA. Desde la issue #62:
#
#   realm                | instancia            | como apuntarle
#   ---------------------|----------------------|-------------------------------------------
#   deal-tracker-dev     | security-dev         | (por defecto)
#   (QA usa ese mismo)   |                      |
#   deal-tracker-prod    | security-prod        | KC_NS=security-prod KC_POD=keycloak-prod-0
#
# Equivocarse de instancia NO da un error util: el realm sencillamente "no existe" en el pod
# al que has apuntado, y ese es el mensaje que sale.
#
# Entorno (por defecto, la instancia de dev/QA):
#   KC_NS=security-dev  KC_POD=keycloak-dev-0  KC_CONTAINER=keycloak
set -euo pipefail

: "${KUBECONFIG:=${HOME}/.kube/k3slocal.yaml}"
export KUBECONFIG
KC_NS="${KC_NS:-security-dev}"
KC_POD="${KC_POD:-keycloak-dev-0}"
KC_CONTAINER="${KC_CONTAINER:-keycloak}"

command -v kubectl >/dev/null || { echo "falta kubectl en el PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "falta python3 en el PATH" >&2; exit 1; }

uso() {
  sed -n '/^# Uso:/,/^#   KC_NS/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit "${1:-1}"
}

# --- ejecucion dentro del pod ------------------------------------------------
kc() { # kc <script-sh>
  kubectl exec -i -n "$KC_NS" "$KC_POD" -c "$KC_CONTAINER" -- sh -c "
    set -e
    K=/opt/keycloak/bin/kcadm.sh
    \$K config credentials --server http://localhost:8080 --realm master \
      --user \"\$KEYCLOAK_ADMIN\" --password \"\$KEYCLOAK_ADMIN_PASSWORD\" >/dev/null
    $1
  " </dev/null
}

comprobar_pod() {
  kubectl get pod -n "$KC_NS" "$KC_POD" >/dev/null 2>&1 \
    || { echo "no encuentro el pod $KC_POD en $KC_NS (¿KC_NS/KC_POD?)" >&2; exit 1; }
}

comprobar_realm() { # comprobar_realm <realm>
  kc "\$K get realms/$1 --fields realm" >/dev/null 2>&1 \
    || { echo "el realm '$1' no existe en $KC_POD" >&2; exit 1; }
}

# --- ------------------------------------------------------------------------
[ $# -eq 2 ] || { case "${1:-}" in -h|--help|ayuda) uso 0 ;; *) uso 1 ;; esac; }
realm="$1"; client="$2"

comprobar_pod
comprobar_realm "$realm"

# `get clients -q clientId=x` filtra por igualdad exacta (a diferencia de la busqueda de
# usuarios, que es por prefijo), pero el filtro se repite aqui por si eso cambia: devolver el
# secreto del client equivocado seria un fallo silencioso y caro.
id="$(kc "\$K get clients -r $realm -q clientId=$client --fields id,clientId" 2>/dev/null \
  | python3 -c '
import json,sys
try: datos = json.load(sys.stdin)
except Exception: sys.exit(0)
for c in datos:
    if c.get("clientId") == sys.argv[1]:
        print(c["id"]); break
' "$client")"

[ -n "$id" ] || { echo "el client '$client' no existe en el realm '$realm'" >&2; exit 1; }

secreto="$(kc "\$K get clients/$id/client-secret -r $realm --fields value" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("value",""))')"

# Un client sin secreto no hace fallar a kcadm: devuelve `{"type":"secret"}` sin `value` y
# rc=0. Pasa con los publicos (publicClient: true) y con algunos builtin de Keycloak como
# `broker`. Sin esta comprobacion el `kubeseal` de la tuberia sellaria una cadena vacia tan
# contento, y el fallo no apareceria hasta que el backend recibiese un 401.
[ -n "$secreto" ] || {
  echo "'$client' no tiene secreto en '$realm': ¿es un client publico, o uno builtin sin secreto?" >&2
  exit 1
}

cat >&2 <<TXT

  ────────────────────────────────────────────────────────────────
  realm:   $realm
  client:  $client
  ────────────────────────────────────────────────────────────────
  Este secreto es DE LARGA VIDA: no caduca y da acceso a la Admin
  API del realm. No es como la contrasena temporal que reparte
  keycloak-user.sh. No lo guardes en disco ni lo pegues en un chat:
  encadenalo a kubeseal y que el unico sitio donde repose sea el
  SealedSecret de k3s-local-apps-manifests.

TXT

printf '%s' "$secreto"
