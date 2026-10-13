{{/* Name used for all objects in this release. */}}
{{- define "supportflow.fullname" -}}
{{- printf "%s-api" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels on every object. */}}
{{- define "supportflow.labels" -}}
app.kubernetes.io/name: supportflow
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.release.version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
supportflow/environment: {{ .Values.environment }}
{{- end -}}

{{/* Labels that select the API pods. */}}
{{- define "supportflow.selectorLabels" -}}
app.kubernetes.io/name: supportflow
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end -}}

{{/* Security settings shared by the API pods and the migration Job. */}}
{{- define "supportflow.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "supportflow.containerSecurityContext" -}}
allowPrivilegeEscalation: false
privileged: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/* Environment variables shared by the API and the migration Job. */}}
{{- define "supportflow.env" -}}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.secretName }}
      key: {{ .Values.database.urlKey }}
- name: APP_VERSION
  value: {{ .Values.release.version | quote }}
- name: GIT_COMMIT
  value: {{ .Values.release.commit | quote }}
{{- end -}}
