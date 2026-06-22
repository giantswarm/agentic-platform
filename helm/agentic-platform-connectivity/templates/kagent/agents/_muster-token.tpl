{{/*
ServiceAccount whose token an agent presents to muster (M2M subject). Defaults to
the agent name, which is the SA the kagent controller creates for the Agent CR.
Input: an agents.list entry.
*/}}
{{- define "agentic-platform.agentServiceAccount" -}}
{{- .serviceAccount | default .name -}}
{{- end -}}

{{/*
Name of the per-agent muster RemoteMCPServer (the agent's toolServer).
Input: an agents.list entry.
*/}}
{{- define "agentic-platform.musterServerName" -}}
{{- printf "muster-%s" .name -}}
{{- end -}}

{{/*
Name of the headersFrom Secret holding "Bearer <token>" for one agent.
Input: dict "root" $ "agent" <agents.list entry>.
*/}}
{{- define "agentic-platform.musterTokenSecretName" -}}
{{- $root := .root -}}
{{- $agent := .agent -}}
{{- $agent.tokenSecret | default (printf "%s-muster-token-%s" (include "name" $root) $agent.name) -}}
{{- end -}}

{{/*
Pod spec shared by one agent's muster-token bootstrap Job and refresh CronJob.
Input: dict "root" $ "agent" <agents.list entry>.

The Job runs as the agent's own ServiceAccount. A projected serviceAccountToken
volume mints a short-lived token for that SA, scoped to the muster audience, so
muster authenticates the agent under its own identity. The init container reads the
token, prepends "Bearer ", and renders a Secret manifest; the distroless kubectl
container applies it. kagent's RemoteMCPServer reads that Secret via headersFrom and
its controller re-resolves the header when the Secret changes, so refreshing the
Secret rotates the token in place without a restart.
*/}}
{{- define "agentic-platform.musterTokenPodSpec" -}}
{{- $root := .root -}}
{{- $agent := .agent -}}
{{- $kagentNs := $root.Values.kagent.namespaceOverride | default $root.Release.Namespace -}}
{{- $tokenSecretName := include "agentic-platform.musterTokenSecretName" (dict "root" $root "agent" $agent) -}}
{{- $identitySA := include "agentic-platform.agentServiceAccount" $agent -}}
{{- $resourceId := $root.Values.muster.muster.oauth.server.resourceIdentifier -}}
{{- $hostname := first $root.Values.ingress.hostnames -}}
{{- if and (not $resourceId) (not $hostname) -}}
  {{- fail "set muster.muster.oauth.server.resourceIdentifier or ingress.hostnames[0]: required to compute the muster token audience" -}}
{{- end -}}
{{- $musterAudience := $resourceId | default (printf "https://%s/mcp" $hostname) -}}
serviceAccountName: {{ $identitySA }}
restartPolicy: OnFailure
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  seccompProfile:
    type: RuntimeDefault
volumes:
  - name: muster-token
    projected:
      sources:
        - serviceAccountToken:
            audience: {{ $musterAudience | quote }}
            expirationSeconds: {{ $root.Values.agents.muster.tokenExpirationSeconds | int64 }}
            path: token
  - name: work
    emptyDir: {}
  - name: tmp
    emptyDir: {}
initContainers:
  - name: render
    image: {{ printf "%s/%s:%s" $root.Values.agents.muster.busyboxImage.registry $root.Values.agents.muster.busyboxImage.repository $root.Values.agents.muster.busyboxImage.tag | quote }}
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: true
    command:
      - /bin/sh
      - -ec
      - |
        header="$(printf 'Bearer %s' "$(cat /var/run/muster-token/token)" | base64 | tr -d '\n')"
        cat > /work/secret.yaml <<EOF
        apiVersion: v1
        kind: Secret
        metadata:
          name: {{ $tokenSecretName }}
          namespace: {{ $kagentNs }}
        type: Opaque
        data:
          token: ${header}
        EOF
    volumeMounts:
      - name: muster-token
        mountPath: /var/run/muster-token
        readOnly: true
      - name: work
        mountPath: /work
containers:
  - name: apply
    image: {{ printf "%s/%s:%s" $root.Values.agents.muster.kubectlImage.registry $root.Values.agents.muster.kubectlImage.repository $root.Values.agents.muster.kubectlImage.tag | quote }}
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      readOnlyRootFilesystem: true
    args:
      - apply
      - -f
      - /work/secret.yaml
      - --cache-dir=/tmp/.kube/cache
    volumeMounts:
      - name: work
        mountPath: /work
        readOnly: true
      - name: tmp
        mountPath: /tmp
{{- end -}}
