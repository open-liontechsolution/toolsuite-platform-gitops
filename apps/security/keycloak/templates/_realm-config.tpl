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
      - name: IMPORT_VARSUBSTITUTION_ENABLED
        value: "false"
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
