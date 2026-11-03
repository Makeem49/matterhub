{{/* Chart name, truncated to the 63-character DNS label limit. */}}
{{- define "matterhub.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name. */}}
{{- define "matterhub.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "matterhub.selectorLabels" -}}
app.kubernetes.io/name: {{ include "matterhub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "matterhub.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "matterhub.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: matterhub
environment: {{ .Values.environment | quote }}
{{- end -}}

{{- define "matterhub.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "matterhub.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "matterhub.image" -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}
{{- end -}}

{{/* Pod labels shared by every workload: workload identity opt-in + standard labels. */}}
{{- define "matterhub.podLabels" -}}
{{ include "matterhub.selectorLabels" . }}
app.kubernetes.io/part-of: matterhub
{{- if .Values.workloadIdentity.enabled }}
azure.workload.identity/use: "true"
{{- end }}
{{- end -}}

{{/*
Environment variables, set inline (not from a ConfigMap) because the migration Job is a
pre-install hook and runs before any regular release resources exist.
Secrets are files from Key Vault (MATTERHUB_SECRETS_DIR), never env values in the spec.
*/}}
{{- define "matterhub.env" -}}
- name: MATTERHUB_ENVIRONMENT
  value: {{ .Values.environment | quote }}
- name: MATTERHUB_LOG_LEVEL
  value: {{ .Values.config.logLevel | quote }}
- name: MATTERHUB_LOG_JSON
  value: "true"
- name: MATTERHUB_AUTH_MODE
  value: {{ .Values.config.authMode | quote }}
{{- if eq .Values.config.authMode "entra" }}
- name: MATTERHUB_ENTRA_TENANT_ID
  value: {{ required "config.entraTenantId is required when authMode=entra" .Values.config.entraTenantId | quote }}
- name: MATTERHUB_ENTRA_AUDIENCE
  value: {{ required "config.entraAudience is required when authMode=entra" .Values.config.entraAudience | quote }}
{{- end }}
- name: MATTERHUB_RETENTION_YEARS
  value: {{ .Values.config.retentionYears | quote }}
- name: MATTERHUB_DATABASE_HOST
  value: {{ required "config.database.host is required" .Values.config.database.host | quote }}
- name: MATTERHUB_DATABASE_PORT
  value: {{ .Values.config.database.port | quote }}
- name: MATTERHUB_DATABASE_NAME
  value: {{ .Values.config.database.name | quote }}
- name: MATTERHUB_DATABASE_USER
  value: {{ .Values.config.database.user | quote }}
- name: MATTERHUB_DATABASE_SSLMODE
  value: {{ .Values.config.database.sslmode | quote }}
{{- with .Values.config.applicationInsightsConnectionString }}
- name: APPLICATIONINSIGHTS_CONNECTION_STRING
  value: {{ . | quote }}
{{- end }}
{{- if .Values.keyVault.enabled }}
- name: MATTERHUB_SECRETS_DIR
  value: /mnt/secrets-store
{{- else if .Values.existingSecret.name }}
- name: MATTERHUB_DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret.name }}
      key: {{ .Values.existingSecret.passwordKey }}
{{- end }}
{{- end -}}

{{/* Usage: include "matterhub.volumes" (dict "root" . "spc" "name-of-secretproviderclass") */}}
{{- define "matterhub.volumes" -}}
- name: tmp
  emptyDir:
    sizeLimit: 64Mi
{{- if .root.Values.keyVault.enabled }}
- name: secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ .spc }}
{{- end }}
{{- end -}}

{{- define "matterhub.volumeMounts" -}}
- name: tmp
  mountPath: /tmp
{{- if .Values.keyVault.enabled }}
- name: secrets-store
  mountPath: /mnt/secrets-store
  readOnly: true
{{- end }}
{{- end -}}

{{/* SecretProviderClass spec, shared by the release and by the migration hook. */}}
{{- define "matterhub.secretProviderClassSpec" -}}
provider: azure
parameters:
  usePodIdentity: "false"
  clientID: {{ required "workloadIdentity.clientId is required when keyVault.enabled=true" .Values.workloadIdentity.clientId | quote }}
  keyvaultName: {{ required "keyVault.name is required when keyVault.enabled=true" .Values.keyVault.name | quote }}
  tenantId: {{ required "keyVault.tenantId is required when keyVault.enabled=true" .Values.keyVault.tenantId | quote }}
  objects: |
    array:
      - |
        objectName: {{ .Values.keyVault.databasePasswordSecretName }}
        objectType: secret
        objectAlias: matterhub_database_password
{{- end -}}
