{{ define "partials.proxy" -}}
env:
{{- if .Values.global.proxy.cores }}
- name: LINKERD2_PROXY_CORES
  value: {{.Values.global.proxy.cores | quote}}
{{- end }}
{{ if .Values.global.proxy.requireIdentityOnInboundPorts -}}
- name: LINKERD2_PROXY_INBOUND_PORTS_REQUIRE_IDENTITY
  value: {{.Values.global.proxy.requireIdentityOnInboundPorts | quote}}
{{ end -}}
- name: LINKERD2_PROXY_LOG
  value: {{.Values.global.proxy.logLevel | quote}}
- name: LINKERD2_PROXY_LOG_FORMAT
  value: {{.Values.global.proxy.logFormat | quote}}
- name: LINKERD2_PROXY_DESTINATION_SVC_ADDR
  value: {{ternary "localhost.:8086" (printf "linkerd-dst-headless.%s.svc.%s.:8086" .Values.global.namespace .Values.global.clusterDomain) (eq (toString .Values.global.proxy.component) "linkerd-destination")}}
- name: LINKERD2_PROXY_DESTINATION_PROFILE_NETWORKS
  value: {{.Values.global.clusterNetworks | quote}}
{{ if .Values.global.proxy.inboundConnectTimeout -}}
- name: LINKERD2_PROXY_INBOUND_CONNECT_TIMEOUT
  value: {{.Values.global.proxy.inboundConnectTimeout | quote}}
{{ end -}}
{{ if .Values.global.proxy.outboundConnectTimeout -}}
- name: LINKERD2_PROXY_OUTBOUND_CONNECT_TIMEOUT
  value: {{.Values.global.proxy.outboundConnectTimeout | quote}}
{{ end -}}
- name: LINKERD2_PROXY_CONTROL_LISTEN_ADDR
  value: 0.0.0.0:{{.Values.global.proxy.ports.control}}
- name: LINKERD2_PROXY_ADMIN_LISTEN_ADDR
  value: 0.0.0.0:{{.Values.global.proxy.ports.admin}}
- name: LINKERD2_PROXY_OUTBOUND_LISTEN_ADDR
  value: 127.0.0.1:{{.Values.global.proxy.ports.outbound}}
- name: LINKERD2_PROXY_INBOUND_LISTEN_ADDR
  value: 0.0.0.0:{{.Values.global.proxy.ports.inbound}}
{{ if .Values.global.proxy.isGateway -}}
- name: LINKERD2_PROXY_INBOUND_GATEWAY_SUFFIXES
  value: {{printf "svc.%s." .Values.global.clusterDomain}}
{{ end -}}
{{ if .Values.global.proxy.isIngress -}}
- name: LINKERD2_PROXY_INGRESS_MODE
  value: "true"
{{ end -}}
- name: LINKERD2_PROXY_DESTINATION_PROFILE_SUFFIXES
  {{- $internalDomain := printf "svc.%s." .Values.global.clusterDomain }}
  value: {{ternary "." $internalDomain .Values.global.proxy.enableExternalProfiles}}
- name: LINKERD2_PROXY_INBOUND_ACCEPT_KEEPALIVE
  value: 10000ms
- name: LINKERD2_PROXY_OUTBOUND_CONNECT_KEEPALIVE
  value: 10000ms
{{ if .Values.global.proxy.opaquePorts -}}
- name: LINKERD2_PROXY_INBOUND_PORTS_DISABLE_PROTOCOL_DETECTION
  value: {{.Values.global.proxy.opaquePorts | quote}}
{{ end -}}
- name: _pod_ns
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: _pod_nodeName
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: LINKERD2_PROXY_DESTINATION_CONTEXT
  value: |
    {"ns":"$(_pod_ns)", "nodeName":"$(_pod_nodeName)"}
{{ if .Values.global.proxy.disableIdentity -}}
- name: LINKERD2_PROXY_IDENTITY_DISABLED
  value: disabled
{{ else -}}
- name: LINKERD2_PROXY_IDENTITY_DIR
  value: /var/run/linkerd/identity/end-entity
- name: LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS
  value: |
  {{- required "Please provide the identity trust anchors" .Values.global.identityTrustAnchorsPEM | trim | nindent 4 }}
- name: LINKERD2_PROXY_IDENTITY_TOKEN_FILE
  value: /var/run/secrets/kubernetes.io/serviceaccount/token
- name: LINKERD2_PROXY_IDENTITY_SVC_ADDR
  value: {{ternary "localhost.:8080" (printf "linkerd-identity-headless.%s.svc.%s.:8080" .Values.global.namespace .Values.global.clusterDomain) (eq (toString .Values.global.proxy.component) "linkerd-identity")}}
- name: _pod_sa
  valueFrom:
    fieldRef:
      fieldPath: spec.serviceAccountName
- name: _l5d_ns
  value: {{.Values.global.namespace}}
- name: _l5d_trustdomain
  value: {{.Values.global.identityTrustDomain}}
- name: LINKERD2_PROXY_IDENTITY_LOCAL_NAME
  value: $(_pod_sa).$(_pod_ns).serviceaccount.identity.$(_l5d_ns).$(_l5d_trustdomain)
- name: LINKERD2_PROXY_IDENTITY_SVC_NAME
  value: linkerd-identity.$(_l5d_ns).serviceaccount.identity.$(_l5d_ns).$(_l5d_trustdomain)
- name: LINKERD2_PROXY_DESTINATION_SVC_NAME
  value: linkerd-destination.$(_l5d_ns).serviceaccount.identity.$(_l5d_ns).$(_l5d_trustdomain)
{{ end -}}
image: {{.Values.global.proxy.image.name}}:{{.Values.global.proxy.image.version}}
imagePullPolicy: {{.Values.global.proxy.image.pullPolicy}}
livenessProbe:
  httpGet:
    path: /live
    port: {{.Values.global.proxy.ports.admin}}
  initialDelaySeconds: 10
name: linkerd-proxy
ports:
- containerPort: {{.Values.global.proxy.ports.inbound}}
  name: linkerd-proxy
- containerPort: {{.Values.global.proxy.ports.admin}}
  name: linkerd-admin
readinessProbe:
  httpGet:
    path: /ready
    port: {{.Values.global.proxy.ports.admin}}
  initialDelaySeconds: 2
{{- if .Values.global.proxy.resources }}
{{ include "partials.resources" .Values.global.proxy.resources }}
{{- end }}
securityContext:
  allowPrivilegeEscalation: false
  {{- if .Values.global.proxy.capabilities -}}
  {{- include "partials.proxy.capabilities" . | nindent 2 -}}
  {{- end }}
  readOnlyRootFilesystem: true
  runAsUser: {{.Values.global.proxy.uid}}
terminationMessagePolicy: FallbackToLogsOnError
{{- if .Values.global.proxy.waitBeforeExitSeconds }}
lifecycle:
  preStop:
    exec:
      command:
        - /bin/bash
        - -c
        - sleep {{.Values.global.proxy.waitBeforeExitSeconds}}
{{- end }}
{{- if or (not .Values.global.proxy.disableIdentity) (.Values.global.proxy.saMountPath) }}
volumeMounts:
{{- if not .Values.global.proxy.disableIdentity }}
- mountPath: /var/run/linkerd/identity/end-entity
  name: linkerd-identity-end-entity
{{- end -}}
{{- if .Values.global.proxy.saMountPath }}
- mountPath: {{.Values.global.proxy.saMountPath.mountPath}}
  name: {{.Values.global.proxy.saMountPath.name}}
  readOnly: {{.Values.global.proxy.saMountPath.readOnly}}
{{- end -}}
{{- end -}}
{{- end }}
