{{/*
Resolve a value for a microservice, falling back to .Values.defaults.

Usage:
  {{ include "sv.svcDefault" (dict "svc" $svc "key" "replicas" "default" 1) }}
*/}}
{{- define "sv.replicas" -}}
{{- $svc := .svc -}}
{{- $defaults := .defaults -}}
{{- default $defaults.replicas $svc.replicas -}}
{{- end -}}

{{- define "sv.readinessProbe" -}}
{{- $svc := .svc -}}
{{- $defaults := .defaults -}}
{{- $r := merge ($svc.probes | default dict).readiness $defaults.probes.readiness -}}
initialDelaySeconds: {{ $r.initialDelaySeconds }}
periodSeconds: {{ $r.periodSeconds }}
failureThreshold: {{ $r.failureThreshold }}
{{- end -}}

{{- define "sv.livenessProbe" -}}
{{- $svc := .svc -}}
{{- $defaults := .defaults -}}
{{- $l := merge ($svc.probes | default dict).liveness $defaults.probes.liveness -}}
initialDelaySeconds: {{ $l.initialDelaySeconds }}
periodSeconds: {{ $l.periodSeconds }}
failureThreshold: {{ $l.failureThreshold }}
{{- end -}}

{{- define "sv.labels" -}}
app: {{ .name }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/managed-by: {{ .release | default "Helm" }}
{{- end -}}
