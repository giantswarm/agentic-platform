{{/*
ServiceAccount the agent pod runs as. Defaults to the agent name.
Input: an agents.definitions entry.
*/}}
{{- define "agentic-platform.agentServiceAccount" -}}
{{- .serviceAccount | default .name -}}
{{- end -}}

{{/*
Name of the per-agent muster RemoteMCPServer (the agent's toolServer).
Input: an agents.definitions entry.
*/}}
{{- define "agentic-platform.musterServerName" -}}
{{- printf "muster-%s" .name -}}
{{- end -}}
