{{/* vim: set filetype=mustache: */}}
{{/*
RBAC letting a set of deputy ServiceAccounts (e.g. mcp-kubernetes) impersonate one
agent's M2M identity at the local apiserver. The deputy authenticates with its own
SA token and adds Impersonate-* headers; this RBAC authorises those headers.

Kubernetes maps Impersonate-User: system:serviceaccount:NS:NAME to a namespaced
"serviceaccounts" check in NS, not a "users" check at cluster scope. So when the
granted user is SA-prefixed we render a namespaced Role on serviceaccounts; a plain
username instead takes a cluster-scoped "users" rule. Group impersonation is always
cluster-scoped, and system:authenticated must be impersonable because the deputy
appends it to the impersonated group set.

Input dict:
  ctx           — root context (.), for name/labels helpers
  agentName     — agent identifier, used in object names
  user          — granted impersonated user (SA-prefixed or plain)
  groups        — list of granted impersonated groups
  impersonators — list of {name, namespace} SAs permitted to impersonate
  clusterRoles  — list of ClusterRole names to bind the granted groups to (authz,
                  e.g. read-all); one ClusterRoleBinding per role. May be empty.
*/}}
{{- define "agentic-platform.agentImpersonation" -}}
{{- $ctx := .ctx -}}
{{- $base := printf "%s-%s-impersonate" (include "name" $ctx) .agentName -}}
{{- $isSA := hasPrefix "system:serviceaccount:" .user -}}
{{- $groupNames := .groups | default list -}}
{{- if not (has "system:authenticated" $groupNames) -}}
{{- $groupNames = append $groupNames "system:authenticated" -}}
{{- end -}}
{{- if $isSA -}}
{{- $parts := splitList ":" .user -}}
{{- $saNs := index $parts 2 -}}
{{- $saName := index $parts 3 -}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $base }}
  namespace: {{ $saNs }}
  labels:
    {{- include "labels.common" $ctx | nindent 4 }}
rules:
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["impersonate"]
    resourceNames: [{{ $saName | quote }}]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $base }}
  namespace: {{ $saNs }}
  labels:
    {{- include "labels.common" $ctx | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ $base }}
subjects:
  {{- range .impersonators }}
  - kind: ServiceAccount
    name: {{ .name }}
    namespace: {{ .namespace }}
  {{- end }}
{{- end }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ $base }}
  labels:
    {{- include "labels.common" $ctx | nindent 4 }}
rules:
  {{- if not $isSA }}
  - apiGroups: [""]
    resources: ["users"]
    verbs: ["impersonate"]
    resourceNames: [{{ .user | quote }}]
  {{- end }}
  - apiGroups: [""]
    resources: ["groups"]
    verbs: ["impersonate"]
    resourceNames:
      {{- range $groupNames }}
      - {{ . | quote }}
      {{- end }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ $base }}
  labels:
    {{- include "labels.common" $ctx | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ $base }}
subjects:
  {{- range .impersonators }}
  - kind: ServiceAccount
    name: {{ .name }}
    namespace: {{ .namespace }}
  {{- end }}
{{- range .clusterRoles }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ printf "%s-%s" $base . }}
  labels:
    {{- include "labels.common" $ctx | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ . | quote }}
subjects:
  {{- range $.groups }}
  - kind: Group
    name: {{ . | quote }}
    apiGroup: rbac.authorization.k8s.io
  {{- end }}
{{- end }}
{{- end -}}
