{{/*
podSpec compartido por el Job (hook PostSync) y el CronJob (reconciliacion diaria).
Los dos ejecutan exactamente lo mismo; lo unico que cambia es quien los dispara.
*/}}
{{- define "keycloak.realmConfig.name" -}}
{{- printf "%s-realm-config" .Release.Name -}}
{{- end -}}

{{/*
NO usar aqui `keycloak.name` (que devuelve "keycloakx"). La NetworkPolicy de egress del
servidor selecciona por `name=keycloakx` + `instance=<release>`, asi que unos pods con esas
etiquetas caen dentro de ella — y sus reglas permiten salida a los puertos 80 y 443, pero el
Service traduce al 8080 del pod destino, que no esta permitido: el Job no puede hablar con
Keycloak y muere por timeout a los 120s. Con nombre propio quedan fuera de esa policy, que
esta pensada para el servidor y no para esto.
*/}}
{{- define "keycloak.realmConfig.labels" -}}
app.kubernetes.io/name: keycloak-realm-config
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ include "keycloak.name" . }}
app.kubernetes.io/component: realm-config
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "keycloak.realmConfig.podSpec" -}}
restartPolicy: Never
securityContext:
  runAsNonRoot: true
{{- with .Values.realmConfig.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
  - name: keycloak-config-cli
    image: "{{ .Values.realmConfig.image.repository }}:{{ .Values.realmConfig.image.tag }}"
    imagePullPolicy: {{ .Values.realmConfig.image.pullPolicy }}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
    args:
      {{- /* SIN ESTO EL CRONJOB NO RECONCILIA NADA. keycloak-config-cli guarda un checksum
             del fichero importado y, con import.cache.enabled=true (su valor por defecto),
             se salta la aplicacion cuando el fichero no ha cambiado. Como el fichero solo
             cambia en un commit, un webOrigins roto a mano sobreviviria a todas las pasadas
             del CronJob. Medido: con el valor por defecto, la segunda pasada no revirtio el
             cambio. */}}
      - --import.cache.enabled={{ .Values.realmConfig.cache.enabled }}
      {{- /* Los import.managed.* van como argumentos y no como variables de entorno:
             el binding relajado de Spring para nombres con guion es una fuente de
             erratas silenciosas (import.managed.client-scope -> IMPORT_MANAGED_CLIENTSCOPE). */}}
      {{- range $resource, $mode := .Values.realmConfig.managed }}
      - --import.managed.{{ $resource }}={{ $mode }}
      {{- end }}
    env:
      - name: KEYCLOAK_URL
        value: {{ required "realmConfig.keycloakUrl es obligatorio" .Values.realmConfig.keycloakUrl | quote }}
      - name: KEYCLOAK_LOGIN_REALM
        value: {{ .Values.realmConfig.loginRealm | quote }}
      {{- /* El Secret guarda las credenciales como KEYCLOAK_ADMIN/KEYCLOAK_ADMIN_PASSWORD
             y config-cli espera KEYCLOAK_USER/KEYCLOAK_PASSWORD: hay que mapearlas una a
             una, con envFrom no coincidirian los nombres. */}}
      - name: KEYCLOAK_USER
        valueFrom:
          secretKeyRef:
            name: {{ .Values.realmConfig.adminSecret.name | quote }}
            key: {{ .Values.realmConfig.adminSecret.userKey | quote }}
      - name: KEYCLOAK_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ .Values.realmConfig.adminSecret.name | quote }}
            key: {{ .Values.realmConfig.adminSecret.passwordKey | quote }}
      - name: KEYCLOAK_AVAILABILITYCHECK_ENABLED
        value: "true"
      - name: KEYCLOAK_AVAILABILITYCHECK_TIMEOUT
        value: {{ .Values.realmConfig.availabilityCheckTimeout | quote }}
      - name: IMPORT_FILES_LOCATIONS
        value: "/config/*.yaml"
      {{- /* Lo que permite que un fichero de realm referencie un secreto sin llevarlo dentro:
             `$(env:VARIABLE)`. El prefijo es `$(`, NO `${`, para no chocar con las variables
             propias de Keycloak —los `${role_uma_authorization}` y los message bundles—, que
             quedan intactas. Encendido para la contrasena del SMTP (issue #60).

             DOS COSAS QUE MUERDEN AL ENCENDERLO:

             1. `import.var-substitution.undefined-is-error` viene true de fabrica, asi que una
                variable que falte NO deja una cadena rara en un realm: aborta el import ENTERO,
                y con el los DOS realms del ConfigMap. Es el comportamiento que se quiere —mejor
                que escribir `$(env:...)` como contrasena de correo—, pero implica que el Secret
                tiene que existir antes que el Job.
             2. A partir de aqui, cualquier `$(` que alguien escriba en `realms/` se interpreta
                —INCLUIDO EL DE UN COMENTARIO—. La sustitucion se hace sobre el texto crudo del
                fichero, antes de parsear el YAML, asi que un `$(` de adorno en un `#` no es
                decorativo: se intenta resolver como variable y, al no existir, tira abajo el
                import de los dos realms por el undefined-is-error de arriba. Paso al escribir
                el bloque de SMTP. Si hace falta un `$(` literal, se escapa doblando el prefijo. */}}
      - name: IMPORT_VARSUBSTITUTION_ENABLED
        value: {{ .Values.realmConfig.varSubstitution.enabled | quote }}
      {{- /* Las claves del SMTP, una variable por realm. Los nombres salen de `encryptedData`
             para que no haya dos listas que mantener: la clave del Secret, la variable de
             entorno y el `$(env:...)` del fichero de realm son el mismo nombre.
             SIN `optional`: si el Secret no esta, el pod se queda en CreateContainerConfigError
             y se ve; con `optional` arrancaria para morir despues por el undefined-is-error de
             arriba, que dice menos sobre lo que pasa. */}}
      {{- if .Values.realmConfig.smtpSecret.enabled }}
      {{- range $key, $_ := .Values.realmConfig.smtpSecret.encryptedData }}
      - name: {{ $key }}
        valueFrom:
          secretKeyRef:
            name: {{ $.Values.realmConfig.smtpSecret.name | quote }}
            key: {{ $key | quote }}
      {{- end }}
      {{- end }}
      - name: JAVA_OPTS
        value: "-XX:MaxRAMPercentage=75"
    volumeMounts:
      - name: realms
        mountPath: /config
        readOnly: true
      - name: tmp
        mountPath: /tmp
    resources:
      {{- toYaml .Values.realmConfig.resources | nindent 6 }}
volumes:
  - name: realms
    configMap:
      name: {{ include "keycloak.realmConfig.name" . }}
  - name: tmp
    emptyDir: {}
{{- end -}}
