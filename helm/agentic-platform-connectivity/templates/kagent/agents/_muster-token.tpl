{{/*
Pod spec shared by the muster-token bootstrap Job and the refresh CronJob.

A projected serviceAccountToken volume mints a short-lived token for the Job's
own ServiceAccount (kagent-muster-client, the identity muster trusts), scoped to
the muster audience. The init container reads it, prepends "Bearer ", and renders
a Secret manifest; the distroless kubectl container applies it. kagent's
RemoteMCPServer reads that Secret via headersFrom and its controller re-resolves
the header when the Secret changes, so refreshing the Secret rotates the token in
place without a restart.
*/}}
{{- define "agentic-platform.musterTokenPodSpec" -}}
{{- $kagentNs := .Values.kagent.namespaceOverride | default .Release.Namespace -}}
{{- $tokenSecretName := printf "%s-kagent-muster-token" (include "name" .) -}}
{{- $resourceId := .Values.muster.muster.oauth.server.resourceIdentifier -}}
{{- $hostname := first .Values.ingress.hostnames -}}
{{- if and (not $resourceId) (not $hostname) -}}
  {{- fail "set muster.muster.oauth.server.resourceIdentifier or ingress.hostnames[0]: required to compute the muster token audience" -}}
{{- end -}}
{{- $musterAudience := $resourceId | default (printf "https://%s/mcp" $hostname) -}}
serviceAccountName: kagent-muster-client
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
            expirationSeconds: {{ .Values.agents.muster.tokenExpirationSeconds | int64 }}
            path: token
  - name: work
    emptyDir: {}
  - name: tmp
    emptyDir: {}
initContainers:
  - name: render
    image: {{ printf "%s/%s:%s" .Values.agents.muster.busyboxImage.registry .Values.agents.muster.busyboxImage.repository .Values.agents.muster.busyboxImage.tag | quote }}
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
    image: {{ printf "%s/%s:%s" .Values.agents.muster.kubectlImage.registry .Values.agents.muster.kubectlImage.repository .Values.agents.muster.kubectlImage.tag | quote }}
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
