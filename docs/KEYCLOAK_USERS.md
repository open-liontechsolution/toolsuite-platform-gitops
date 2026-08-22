# Usuarios de Keycloak: por que se dan de alta a mano y como

Los **realms y clients** de este cluster se declaran en `apps/security/keycloak/realms/` y los
aplica `keycloak-config-cli` (issues #49 y #50). Los **usuarios no**, y no es una tarea
pendiente: es una decision. Este documento la deja escrita, con lo que tendria que cambiar
para revisarla.

Con una excepcion, que no es una persona y tiene su propia seccion aqui abajo: el **service
account** del client `deal-tracker-api` (issue #61).

Las herramientas son `scripts/keycloak-user.sh` (alta y baja de personas) y
`scripts/keycloak-client-secret.sh` (el secreto de un client confidencial, para sellarlo).

## Por que los usuarios no se declaran en git

Tres razones, y cada una basta por si sola:

1. **`keycloak-config-cli` no sabe borrarlos.** Su `UserImportService` registra
   *"Purging users isn't supported"* incluso con `users: []`. Un usuario declarado en git no se
   da de baja quitandolo del fichero — se queda para siempre.
2. **La reconciliacion nocturna los resucitaria.** El CronJob corre a las 04:00 con
   `cache.enabled: false` justamente para que un cambio hecho a mano en la consola no
   sobreviva. Si los usuarios estuvieran declarados, deshabilitar a alguien duraria hasta esa
   noche. La baja seria imposible de sostener, que es lo contrario de lo que se quiere.
3. **Las credenciales de personas reales no van a un repositorio, ni cifradas.** Y aqui ni
   siquiera hay nada que guardar: la contrasena que reparte el alta es temporal y muere en el
   primer login. Un vault no protegeria nada, solo alargaria la vida de un secreto que deberia
   desaparecer.

Lo que si queda en git es **el procedimiento**. El primer usuario de produccion se creo con
`kcadm.sh` a mano desde el pod y no dejo rastro en ningun repositorio — que es exactamente lo
que la #50 dice que no hay que repetir.

## El unico usuario declarado, y por que no cuenta

Hay **una** excepcion a todo lo anterior, y esta en los dos ficheros de realm de deal-tracker
(issue #61):

```yaml
users:
  - username: service-account-deal-tracker-api
    enabled: true
    serviceAccountClientId: deal-tracker-api
    clientRoles:
      realm-management:
        - manage-users
```

No es una persona: es el **service account** que Keycloak crea solo al encender
`serviceAccountsEnabled` en el client confidencial `deal-tracker-api`, con el que el backend de
deal-tracker crea las cuentas del alta por invitacion. Va declarado porque **keycloak-config-cli
no sabe asignar ese rol de ninguna otra forma**: no es un campo del client, es un `users:` con
`serviceAccountClientId`, y no hay alternativa en su modelo de configuracion.

Ninguna de las tres razones de arriba le aplica:

1. **«config-cli no sabe borrarlos»** — un service account no se da de baja: se retira borrando su
   client, y eso si es declarativo.
2. **«la reconciliacion nocturna los resucitaria»** — aqui esa reconciliacion es la garantia, no el
   riesgo. Si alguien le anade `realm-admin` a mano desde la consola, el CronJob de las 04:00 lo
   revierte. Es exactamente el efecto que se quiere.
3. **«las credenciales de personas no van a un repositorio»** — no hay ninguna: Keycloak lo crea sin
   contrasena, y el secreto del client no se declara (ver abajo).

**Esto no abre la puerta a declarar usuarios.** La regla que queda escrita es: en `realms/` solo van
service accounts. Una persona sigue sin poder darse de baja quitandola de un fichero, que es lo que
hace insostenible declararlas.

`manage-users` es mas de lo que hace falta —permite tambien borrar y deshabilitar—, pero no existe un
rol builtin de «solo crear»: acotarlo exigiria un rol de cliente a medida. Queda dicho para que la
decision sea revisable. Lo que **no** hace falta es `view-users`: `UserPermissions.canView()` es
`hasViewRole() || canManage()`, asi que buscar si el invitado ya existe funciona con `manage-users`
solo.

### El secreto de ese client: generado por Keycloak, nunca en git

El client es confidencial, pero su secreto **no se declara en el fichero de realm**. Lo genera
Keycloak al crearlo, y config-cli no lo toca nunca: con `secret` ausente, su
`ClientImportService.isClientEqual` devuelve `true` **sin llegar a consultar el secreto real**, asi
que la reconciliacion de las 04:00 no lo rota.

**Medido el 22/08/2026**, que es lo que sostiene todo lo anterior: tras el Job de PostSync y una
pasada forzada del CronJob, el secreto de `deal-tracker-dev` era el mismo antes y despues. En la
misma comprobacion, el token de `client_credentials` llevaba
`resource_access.realm-management.roles = [manage-users]` y la Admin API respondia **200** al listar
y al buscar por `username` (o sea, `manage-users` cubre la lectura sin `view-users`), **403** contra
el otro realm, y las personas de los dos realms seguian exactamente igual —incluido el
`UPDATE_PASSWORD` pendiente de una de produccion, que no se toco.

Un detalle de la misma medicion: en vivo el client tiene un cuarto scope, `service_account`, que
**Keycloak anade solo** al encender `serviceAccountsEnabled`. No se declara en el fichero porque es
suyo, y config-cli no se lo quita en la reconciliacion.

Se saca del servidor una vez por realm, y por stdout para poder encadenarlo sin que toque disco:

```bash
./scripts/keycloak-client-secret.sh deal-tracker-dev deal-tracker-api \
  | kubeseal --raw --from-file=/dev/stdin --namespace deal-tracker-qa --name deal-tracker-config
```

El ciphertext va a `deal-tracker/overlays/*` de `k3s-local-apps-manifests`, bajo
`KEYCLOAK_ADMIN_CLIENT_SECRET`. El sellado es **por namespace**: el mismo secreto para dos namespaces
se sella dos veces y los ciphertexts salen distintos. `deal-tracker-dev` no lo lleva — ese overlay
borra las `KEYCLOAK_*` a proposito y alli el registro queda apagado por construccion.

A diferencia de la contrasena que reparte `keycloak-user.sh`, **este secreto es de larga vida**: no
caduca y da acceso a la Admin API del realm. No se guarda en disco ni se pega en un chat.

Ojo con la issue #62: al trasladar `deal-tracker-prod` a su instancia aislada, el fichero de realm
viaja pero **el secreto no** —la instancia nueva genera otro— y hay que re-sellarlo junto al
`KEYCLOAK_ISSUER_URL`, que cambia por el host.

## La politica de alta, mientras no haya SMTP

**Alta manual, contrasena temporal, cambio obligatorio en el primer login.** Sin auto-registro
y sin invitacion.

El motivo es una sola linea de los ficheros de realm: `smtpServer: {}`. Sin servidor de correo
Keycloak no puede mandar nada, y de ahi salen dos consecuencias que mandan sobre todo lo demas:

- `resetPasswordAllowed: false` — **no hay "he olvidado mi contrasena"**. La recuperacion pasa
  siempre por un administrador ejecutando `reset`.
- `verifyEmail: false` — no se puede comprobar que el correo de alta es de quien dice serlo.

Con auto-registro sobre esa base, cualquiera podria registrarse con un correo ajeno, y el
primero que olvidase su contrasena se quedaria fuera para siempre. Por eso el alta es manual:
no es que falte automatizarla, es que **el auto-registro no es seguro hasta que haya SMTP**.

**El disparador para revisar esto es configurar SMTP en el realm.** Ese dia se puede encender
`verifyEmail`, `resetPasswordAllowed` y decidir con criterio entre auto-registro e invitacion.
La contrasena del servidor de correo entraria por var-substitution desde un SealedSecret, nunca
en claro en el fichero de realm.

Mientras tanto la escala lo hace sostenible: produccion se estrena con un punado de usuarios
dados de alta uno a uno.

## Como

```bash
cd toolsuite-platform-gitops

./scripts/keycloak-user.sh listar deal-tracker-prod
./scripts/keycloak-user.sh crear  deal-tracker-prod ana ana@example.com Ana Perez
./scripts/keycloak-user.sh reset  deal-tracker-prod ana     # olvido la contrasena
./scripts/keycloak-user.sh baja   deal-tracker-prod ana     # deshabilita, NO borra
./scripts/keycloak-user.sh alta   deal-tracker-prod ana     # revierte la baja
```

`crear` **genera** la contrasena temporal, la imprime una vez y no vuelve a mostrarla. Se entrega
por un canal fuera de banda; si se pierde, se hace un `reset`. Generarla es lo preferible —24
caracteres aleatorios son mejores que lo que elige una persona, y ademas va a durar un login—, pero
se puede dictar, y el camino importa:

```bash
# Teclearla a mano: la pide sin eco y con confirmacion. NO queda en el historial del shell.
./scripts/keycloak-user.sh crear --dictar deal-tracker-prod ana ana@example.com Ana Perez

# Tomarla de un gestor de contrasenas, sin que pase por el terminal.
pass show dealtracker/ana | ./scripts/keycloak-user.sh crear deal-tracker-prod ana ana@example.com

# En la linea de comandos. Comodo, y el unico que se queda en el historial: ver abajo.
./scripts/keycloak-user.sh crear --password 'Temporal-123' deal-tracker-dev prueba prueba@example.com
```

`reset` acepta las mismas opciones.

**Cuando usar `--password` y cuando no.** Es la via comoda y esta pensada para **usuarios
desechables de dev/QA**, donde la contrasena no protege nada. El coste es que la linea entera queda
en el historial del shell, y ahi la contrasena **sigue siendo valida hasta que alguien haga el
primer login** — que en un usuario de pruebas puede no pasar nunca. Para una persona real, `--dictar`.

Lo que no cambia con ninguna de las tres: **del lado del pod la contrasena nunca aparece en una
linea de comandos**. Viaja siempre por la entrada estandar hacia el `-f -` de `kcadm.sh`.

## Como comprobar que una credencial vale

Sin navegador, con el client `admin-cli` del propio realm, que si admite `password` grant:

```bash
curl -s -X POST https://keycloak-dev.liontechsolution.com/realms/<realm>/protocol/openid-connect/token \
  -d grant_type=password -d client_id=admin-cli -d username=<usuario> \
  --data-urlencode "password=<la contrasena>"
```

Los dos errores que interesan **no significan lo mismo**, y ahi esta el valor de la prueba:

| respuesta | que quiere decir |
|---|---|
| `invalid_grant: Account is not fully set up` | la contrasena **es correcta**; lo que bloquea el token es el `UPDATE_PASSWORD` pendiente. Es el resultado esperado de un alta recien hecha. |
| `invalid_grant: Invalid user credentials` | la contrasena no vale. |
| `unauthorized_client: Client not allowed for direct access grants` | te has equivocado de client: `deal-tracker-web` lleva `directAccessGrantsEnabled: false` a proposito (solo PKCE). |

Que el primero salga es la unica forma de verificar un alta sin navegador: prueba a la vez que la
credencial se acepta y que el cambio de contrasena forzoso se esta ejerciendo de verdad.

## Detalles que conviene saber antes de usarlo

- **Las credenciales de admin no salen del pod.** `kcadm.sh` se autentica dentro del contenedor
  con las variables que ya recibe por `envFrom` del secret `keycloak-admin-credentials`. Sacar
  ese secret al portatil para hablar con la API desde fuera seria copiar la llave del reino a un
  disco mas.
- **La contrasena no pasa nunca por la linea de comandos.** Ni en el portatil ni dentro del pod:
  el script remoto va en argv (realm y usuario, que son publicos) y los datos viajan por la
  entrada estandar hacia el `-f -` de `kcadm.sh`. Una contrasena en argv la ve cualquiera con
  `ps`, y ademas se queda en el historial del shell.
- **`baja` deshabilita, no borra.** El `sub` de Keycloak es la clave con la que el backend de
  deal-tracker aprovisiona su fila de `app_user`; borrar el usuario en Keycloak dejaria
  huerfanas sus filas de `interest` y `notification` sin que nada las recoja. Deshabilitado, el
  token deja de emitirse y los datos siguen atados a su dueño por si vuelve.
- **Es lento, y es normal.** Cada invocacion de `kcadm.sh` arranca una JVM dentro del pod:
  medido, ~10 s, y cada subcomando encadena varias. Un `listar` tarda ~40 s; `crear`, alrededor de
  un minuto. Por eso el alta manda el usuario **y su credencial** en un unico `POST`, en lugar de
  crear primero y poner la contrasena despues: ahorra dos llamadas y, de paso, elimina la ventana
  en la que el usuario ya existe pero no tiene contrasena. Lo que si sigue costando una llamada
  aparte es la comprobacion de que el realm existe, y se mantiene a proposito: sin ella, teclear
  mal el nombre del realm daria un error de `kcadm` que no dice cual es el problema.
- **`crear` no comprueba antes si el usuario existe**: el propio Keycloak responde `409` al
  duplicado, y el script lo traduce a un mensaje que remite a `reset`. Ahorra una llamada, y
  correrlo dos veces por error no le pisa la contrasena a nadie que ya este usando la
  plataforma.
- **El realm por defecto vive en `security-dev`**, que es el unico Keycloak del cluster: dev, QA
  y produccion de deal-tracker son **realms** distintos de la misma instancia. Se puede apuntar a
  otro con `KC_NS`, `KC_POD` y `KC_CONTAINER`.

## Lo que el alta NO hace

No crea nada en la base de datos de la aplicacion. El backend de deal-tracker **aprovisiona la
fila de `app_user` en el primer login** (JIT, a partir de los claims `sub`, `email` y `name`),
asi que un usuario recien creado no aparece en la aplicacion hasta que entra por primera vez.
Si hace falta comprobar que un alta llego a su destino, se mira ahi y no en Keycloak.
