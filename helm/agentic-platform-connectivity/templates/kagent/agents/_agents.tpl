{{/*
ServiceAccount an agent runs as: its identity when acting on behalf of a user
(the RFC 8693 actor presented to muster). Defaults to the agent name.
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
