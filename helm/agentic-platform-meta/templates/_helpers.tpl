{{/* vim: set filetype=mustache: */}}

{{- define "agentic-platform-meta.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "agentic-platform-meta.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels stamped on every rendered object so they are traceable back to the
meta-package release (the app-of-apps parent).
*/}}
{{- define "agentic-platform-meta.labels" -}}
app.kubernetes.io/name: {{ include "agentic-platform-meta.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
app.kubernetes.io/part-of: agentic-platform
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
application.giantswarm.io/team: {{ index .Chart.Annotations "io.giantswarm.application.team" | quote }}
helm.sh/chart: {{ include "agentic-platform-meta.chart" . | quote }}
{{- end -}}

{{/*
OCI chart URL for a component: the base repository (oci://host/path) joined with
the chart name. Single indirection so the version range stays a value.
*/}}
{{- define "agentic-platform-meta.chartURL" -}}
{{- printf "%s/%s" (trimSuffix "/" .repository) .chart -}}
{{- end -}}
