{{/* Component image ref: global repo + component tag */}}
{{- define "todo.image" -}}
{{- $ctx := .ctx -}}
{{- printf "%s:%s" $ctx.Values.global.image.repository .tag -}}
{{- end -}}

{{- define "todo.commonLabels" -}}
app.kubernetes.io/name: todo-app
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
