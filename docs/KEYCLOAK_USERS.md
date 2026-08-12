# Usuarios de Keycloak: por que se dan de alta a mano y como

Los **realms y clients** de este cluster se declaran en `apps/security/keycloak/realms/` y los
aplica `keycloak-config-cli` (issues #49 y #50). Los **usuarios no**, y no es una tarea
pendiente: es una decision. Este documento la deja escrita, con lo que tendria que cambiar
para revisarla.

La herramienta es `scripts/keycloak-user.sh`.

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

# Tomarla de un gestor de contrasenas.
pass show dealtracker/ana | ./scripts/keycloak-user.sh crear deal-tracker-prod ana ana@example.com
```

Lo que no hay que hacer es `echo 'micontrasena' | ...`: eso si se queda en el historial, que es
justo lo que `--dictar` evita. `reset` acepta el mismo `--dictar`.

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
