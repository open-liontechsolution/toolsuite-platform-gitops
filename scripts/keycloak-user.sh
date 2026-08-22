#!/usr/bin/env bash
# Alta, baja y reseteo de usuarios de un realm de Keycloak.
#
# POR QUE EXISTE ESTO, Y POR QUE NO ES UN FICHERO DE realms/
#
# Los realms y los clients se declaran en git y los aplica keycloak-config-cli (issues #49
# y #50). Las PERSONAS no, y es deliberado:
#
#   * config-cli no sabe borrarlos. `UserImportService` registra "Purging users isn't
#     supported" incluso con `users: []`, asi que un usuario declarado en git no se puede
#     dar de baja quitandolo del fichero — se quedaria para siempre.
#   * Peor: el CronJob de reconciliacion corre cada noche con `cache.enabled: false`. Si
#     los usuarios estuvieran declarados, deshabilitar a alguien a mano duraria hasta las
#     04:00, que lo volveria a poner `enabled: true`. La baja seria imposible de sostener.
#   * Y las credenciales de personas reales no van a un repositorio, ni cifradas: la
#     contrasena que reparte este script es TEMPORAL y de un solo uso, asi que no hay nada
#     que guardar en ningun sitio. Un vault aqui no protegeria nada, solo alargaria la vida
#     de un secreto que deberia morir en el primer login.
#
# Lo que este script arregla no es "que sea automatico", es que el alta DEJE RASTRO y sea
# siempre la misma. La alternativa —`kcadm.sh` a mano desde el pod— es como se creo el
# primer usuario de produccion, y no aparece en ningun repositorio.
#
# La unica entrada `users:` que hay en realms/ es el service account del client
# `deal-tracker-api` (issue #61): no es una persona, no tiene contrasena y se retira borrando
# su client, asi que las tres razones de arriba no le aplican y config-cli no sabe asignarle
# su rol de otra forma. Su secreto se saca con `scripts/keycloak-client-secret.sh`.
#
# EL MODELO DE ALTA: contrasena temporal + UPDATE_PASSWORD forzado.
# El realm no tiene SMTP (`smtpServer: {}`), asi que `resetPasswordAllowed` es false y NO
# hay "he olvidado mi contrasena". Por eso el alta entrega una contrasena de usar y tirar
# por un canal fuera de banda y obliga a cambiarla en el primer login: la definitiva no
# pasa nunca por aqui, ni por un chat, ni por el historial del shell.
# Mientras no haya SMTP, `reset` es el unico camino de recuperacion y lo ejecuta un
# administrador. Ver `docs/KEYCLOAK_USERS.md`.
#
# LAS CREDENCIALES DE ADMIN NO SALEN DEL POD. `kcadm.sh` se autentica dentro del contenedor
# con las variables que este ya recibe por `envFrom` del secret `keycloak-admin-credentials`.
# Sacar ese secret al portatil para hablar con la API desde fuera seria copiar la llave del
# reino a un disco mas.
#
# Uso:
#   ./scripts/keycloak-user.sh listar <realm>
#   ./scripts/keycloak-user.sh crear  [opciones] <realm> <usuario> <correo> [nombre] [apellido]
#   ./scripts/keycloak-user.sh reset  <realm> <usuario>
#   ./scripts/keycloak-user.sh baja   <realm> <usuario>     # deshabilita, NO borra
#   ./scripts/keycloak-user.sh alta   <realm> <usuario>     # revierte una baja
#
# Ejemplos:
#   ./scripts/keycloak-user.sh crear deal-tracker-prod ana ana@example.com Ana Perez
#   ./scripts/keycloak-user.sh listar deal-tracker-prod
#
# La contrasena se GENERA aqui y se imprime UNA vez. Generarla es lo preferible: 24 caracteres
# aleatorios son mejores que lo que elige una persona, y ademas es temporal.
#
# Para elegirla tu hay tres caminos, y la diferencia importa:
#
#   --dictar        la pide por teclado sin eco y con confirmacion. No aparece en el historial
#                   del shell. Es el bueno para un usuario real.
#   tuberia         para tomarla de un gestor de contrasenas sin que pase por el terminal:
#                   pass show dealtracker/ana | ... crear deal-tracker-prod ana ana@example.com
#   --password VAL  en la linea de comandos. El mas comodo y el unico que SE QUEDA EN EL
#                   HISTORIAL del shell, donde sigue siendo valida hasta que alguien haga el
#                   primer login. Pensado para usuarios desechables de dev/QA, donde eso da
#                   igual; para un usuario real usa --dictar.
#
# Del lado del pod los tres son iguales de discretos: la contrasena viaja siempre por la entrada
# estandar hacia el `-f -` de kcadm, nunca en su linea de comandos.
#
# Entorno (por defecto, el unico Keycloak que existe en el cluster):
#   KC_NS=security-dev  KC_POD=keycloak-dev-0  KC_CONTAINER=keycloak
set -euo pipefail

: "${KUBECONFIG:=${HOME}/.kube/k3slocal.yaml}"
export KUBECONFIG
KC_NS="${KC_NS:-security-dev}"
KC_POD="${KC_POD:-keycloak-dev-0}"
KC_CONTAINER="${KC_CONTAINER:-keycloak}"

command -v kubectl >/dev/null || { echo "falta kubectl en el PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "falta python3 en el PATH" >&2; exit 1; }

# La entrada estandar se consume AQUI, entera y una sola vez, antes de hablar con el cluster.
# `kubectl exec -i` conecta la stdin del script al pod, asi que la primera comprobacion que
# hiciera el script —mirar si el realm existe— se comeria la contrasena dictada por tuberia
# y el alta seguiria adelante con una generada, sin que nadie se enterase.
DICTADO=""
DICTAR=0
PASSWORD_ARG=""
if [ ! -t 0 ]; then DICTADO="$(cat)"; fi

# Las opciones se aceptan en cualquier posicion; lo demas se devuelve en RESTO. Un `shift` dentro
# de una funcion solo mueve sus propios parametros, de ahi el array en vez de reescribir "$@".
RESTO=()
parsear_opciones() {
  RESTO=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --dictar)     DICTAR=1; shift ;;
      --password)   PASSWORD_ARG="${2:?--password necesita un valor}"; shift 2 ;;
      --password=*) PASSWORD_ARG="${1#*=}"; shift ;;
      --)           shift; while [ $# -gt 0 ]; do RESTO+=("$1"); shift; done ;;
      -*)           echo "opcion desconocida: $1" >&2; exit 1 ;;
      *)            RESTO+=("$1"); shift ;;
    esac
  done
  if [ "$DICTAR" -eq 1 ] && [ -n "$PASSWORD_ARG" ]; then
    echo "--dictar y --password son incompatibles: elige quien pone la contrasena" >&2; exit 1
  fi
}

uso() {
  sed -n '/^# Uso:/,/^#   KC_NS/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# --- ejecucion dentro del pod ------------------------------------------------
#
# El script remoto va en argv (no lleva secretos: realm, usuario y correo son publicos) y
# los DATOS van por la entrada estandar. Esa separacion es el punto: una contrasena en argv
# la ve cualquiera con `ps`, tanto en el pod como en este portatil.
kc() { # kc <script-sh>   — la stdin de la funcion viaja al pod
  kubectl exec -i -n "$KC_NS" "$KC_POD" -c "$KC_CONTAINER" -- sh -c "
    set -e
    K=/opt/keycloak/bin/kcadm.sh
    \$K config credentials --server http://localhost:8080 --realm master \
      --user \"\$KEYCLOAK_ADMIN\" --password \"\$KEYCLOAK_ADMIN_PASSWORD\" >/dev/null
    $1
  "
}

comprobar_pod() {
  kubectl get pod -n "$KC_NS" "$KC_POD" >/dev/null 2>&1 \
    || { echo "no encuentro el pod $KC_POD en $KC_NS (¿KC_NS/KC_POD?)" >&2; exit 1; }
}

comprobar_realm() { # comprobar_realm <realm>
  kc "\$K get realms/$1 --fields realm" </dev/null >/dev/null 2>&1 \
    || { echo "el realm '$1' no existe en $KC_POD" >&2; exit 1; }
}

id_de() { # id_de <realm> <usuario>  -> imprime el id, o vacio si no existe
  # `get users -q username=x` hace busqueda por prefijo (`ana` casaria con `anabel`), asi
  # que el filtro exacto se hace aqui y no se delega en Keycloak.
  kc "\$K get users -r $1 -q username=$2 --fields id,username" </dev/null 2>/dev/null \
    | python3 -c '
import json,sys
try: datos = json.load(sys.stdin)
except Exception: sys.exit(0)
for u in datos:
    if u.get("username") == sys.argv[1]:
        print(u["id"]); break
' "$2"
}

json_usuario() { # json_usuario <usuario> <correo> <nombre> <apellido> <password>
  # Construido con python3 y no con printf: un apostrofo en el apellido —O'Neill— o una
  # comilla en el nombre romperia el JSON a mano, y el error saldria como un 400 opaco.
  #
  # La credencial va DENTRO del alta a proposito. Crear el usuario y ponerle la contrasena
  # despues son dos llamadas, y cada `kcadm.sh` arranca una JVM dentro del pod: medido, ~20 s
  # cada una. Con `credentials` en el propio representation el alta entera es UNA llamada, y
  # ademas deja de existir la ventana en la que el usuario existe sin contrasena.
  python3 -c '
import json,sys
u = {"username": sys.argv[1], "email": sys.argv[2], "enabled": True,
     "emailVerified": True,
     # UPDATE_PASSWORD: la temporal que reparte este script muere en el primer login.
     "requiredActions": ["UPDATE_PASSWORD"],
     "credentials": [{"type": "password", "temporary": True, "value": sys.argv[5]}]}
if sys.argv[3]: u["firstName"] = sys.argv[3]
if sys.argv[4]: u["lastName"]  = sys.argv[4]
print(json.dumps(u))
' "$@"
}

leer_password() { # imprime la contrasena: la de --password, la dictada, la de stdin o una generada
  if [ -n "$PASSWORD_ARG" ]; then
    printf '%s' "$PASSWORD_ARG"
    return
  fi
  if [ "$DICTAR" -eq 1 ]; then
    # Se lee de /dev/tty y no de la entrada estandar: esta funcion corre dentro de una
    # sustitucion de comandos, y la stdin del script ya puede venir de una tuberia.
    [ -c /dev/tty ] || { echo "--dictar necesita un terminal; sin el, pasala por tuberia" >&2; exit 1; }
    local uno dos
    read -rsp "Contrasena temporal para '$2' (no se muestra): " uno </dev/tty; echo >&2
    read -rsp "Repitela: "                                     dos </dev/tty; echo >&2
    [ -n "$uno" ]        || { echo "contrasena vacia: nada que hacer" >&2; exit 1; }
    [ "$uno" = "$dos" ]  || { echo "no coinciden" >&2; exit 1; }
    printf '%s' "$uno"
    return
  fi
  if [ -n "$DICTADO" ]; then
    local dictada="$DICTADO"
    dictada="${dictada//$'\r'/}"
    dictada="${dictada%"${dictada##*[!$'\n']}"}"
    [ -n "$dictada" ] || { echo "contrasena vacia por stdin: nada que hacer" >&2; exit 1; }
    printf '%s' "$dictada"
    return
  fi
  # Sin `head -c`: cierra la tuberia antes de tiempo y con `pipefail` el SIGPIPE de openssl
  # tumbaria el script. `cut` consume toda la entrada.
  { openssl rand -base64 48 || true; } | tr -dc 'A-Za-z0-9' | cut -c1-24
}

fijar_password() { # fijar_password <realm> <id> <password-por-stdin>
  # `-f -` lee el cuerpo JSON de la entrada estandar: asi la contrasena no aparece en la
  # linea de comandos de kcadm dentro del pod. `temporary: true` es lo que dispara la
  # pantalla de cambio de contrasena en el primer login.
  python3 -c '
import json,sys
print(json.dumps({"type": "password", "temporary": True,
                  "value": sys.stdin.read()}))
' | kc "\$K update users/$2/reset-password -r $1 -f - >/dev/null"
}

# --- subcomandos -------------------------------------------------------------
cmd_listar() {
  local realm="${1:?falta el realm}"
  comprobar_realm "$realm"
  kc "\$K get users -r $realm --fields id,username,email,enabled,requiredActions" </dev/null
}

cmd_crear() {
  parsear_opciones "$@"; set -- ${RESTO[@]+"${RESTO[@]}"}
  local realm="${1:?falta el realm}" usuario="${2:?falta el usuario}" correo="${3:?falta el correo}"
  local nombre="${4:-}" apellido="${5:-}"
  comprobar_realm "$realm"
  local password; password="$(leer_password "$realm" "$usuario")"

  # NO se comprueba antes si el usuario existe: eso seria otra llamada, otros ~20 s, y el
  # propio Keycloak ya responde 409 al duplicado. Correr esto dos veces por error no crea un
  # segundo usuario ni le pisa la contrasena a alguien que ya esta usando la plataforma
  # —para eso esta `reset`, que se pide a solas y con su nombre.
  local salida estado=0
  salida="$(json_usuario "$usuario" "$correo" "$nombre" "$apellido" "$password" \
    | kc "\$K create users -r $realm -f -" 2>&1)" || estado=$?

  if [ "$estado" -ne 0 ]; then
    case "$salida" in
      *409*|*onflict*|*xists*)
        echo "'$usuario' ya existe en '$realm'. Para darle contrasena nueva:" >&2
        echo "  $0 reset $realm $usuario" >&2 ;;
      *) echo "$salida" >&2 ;;
    esac
    exit 1
  fi

  echo "✔ '$usuario' creado en '$realm'"
  entregar "$usuario" "$password"
}

cmd_reset() {
  parsear_opciones "$@"; set -- ${RESTO[@]+"${RESTO[@]}"}
  local realm="${1:?falta el realm}" usuario="${2:?falta el usuario}"
  comprobar_realm "$realm"
  local id; id="$(id_de "$realm" "$usuario")"
  [ -n "$id" ] || { echo "'$usuario' no existe en '$realm'" >&2; exit 1; }

  local password; password="$(leer_password "$realm" "$usuario")"
  printf '%s' "$password" | fijar_password "$realm" "$id"
  # `reset-password` con `temporary: true` ya deja la accion pendiente, pero si el usuario
  # se la habia quitado al cambiarla, hay que volver a ponerla explicitamente.
  printf '{"requiredActions":["UPDATE_PASSWORD"]}' | kc "\$K update users/$id -r $realm -f - >/dev/null"

  echo "✔ contrasena de '$usuario' reseteada en '$realm'"
  entregar "$usuario" "$password"
}

cmd_baja() {
  local realm="${1:?falta el realm}" usuario="${2:?falta el usuario}"
  comprobar_realm "$realm"
  local id; id="$(id_de "$realm" "$usuario")"
  [ -n "$id" ] || { echo "'$usuario' no existe en '$realm'" >&2; exit 1; }

  # Deshabilitar y no borrar: el `keycloak_sub` es la clave con la que el backend aprovisiona
  # `app_user`, y borrarlo en Keycloak dejaria huerfanas sus filas de `interest` y
  # `notification` sin que nada las recoja. Deshabilitado, el token deja de emitirse y los
  # datos siguen atados a su dueño por si vuelve.
  printf '{"enabled":false}' | kc "\$K update users/$id -r $realm -f - >/dev/null"
  echo "✔ '$usuario' deshabilitado en '$realm' (no borrado: sus datos siguen atados a su sub)"
}

cmd_alta() {
  local realm="${1:?falta el realm}" usuario="${2:?falta el usuario}"
  comprobar_realm "$realm"
  local id; id="$(id_de "$realm" "$usuario")"
  [ -n "$id" ] || { echo "'$usuario' no existe en '$realm'" >&2; exit 1; }
  printf '{"enabled":true}' | kc "\$K update users/$id -r $realm -f - >/dev/null"
  echo "✔ '$usuario' rehabilitado en '$realm'"
}

entregar() { # entregar <usuario> <password>
  # Si la contrasena la ha tecleado quien ejecuta esto, no se le devuelve: ya la sabe, y
  # imprimirla solo la deja en el scrollback del terminal, que es justo lo que --dictar evita.
  local linea="  contrasena:  $2"
  [ "$DICTAR" -eq 1 ]        && linea="  contrasena:  (la que has tecleado)"
  [ -n "$PASSWORD_ARG" ]     && linea="  contrasena:  (la que pasaste en --password)"
  cat >&2 <<TXT

  ────────────────────────────────────────────────────────────────
  usuario:     $1
$linea
  ────────────────────────────────────────────────────────────────
  Es TEMPORAL: Keycloak la pedira cambiar en el primer login.
  Entregala por un canal fuera de banda y no la guardes en ningun
  sitio — no vuelve a mostrarse, y si se pierde se hace un 'reset'.
  Sin SMTP en el realm no hay "he olvidado mi contrasena": la
  recuperacion pasa siempre por un administrador.

TXT
}

# --- despacho ----------------------------------------------------------------
[ $# -ge 1 ] || uso 1
comando="$1"; shift
comprobar_pod
case "$comando" in
  listar) cmd_listar "$@" ;;
  crear)  cmd_crear  "$@" ;;
  reset)  cmd_reset  "$@" ;;
  baja)   cmd_baja   "$@" ;;
  alta)   cmd_alta   "$@" ;;
  -h|--help|ayuda) uso 0 ;;
  *) echo "subcomando desconocido: $comando" >&2; uso 1 ;;
esac
