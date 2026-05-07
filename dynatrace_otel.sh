#!/bin/bash

clear

echo "========================================="
echo " Dynatrace OpenTelemetry Collector"
echo "========================================="

echo "1 - Check OTel"
echo "2 - Install OTel"
echo "3 - Test Trace"
echo "4 - Cleanup OTel"

read -rp "Seleccione opcion: " ACTION

case "$ACTION" in

1)

  echo ""
  echo "[CHECK] OpenTelemetry Collector"

  kubectl get pods -n dynatrace | grep -i otel

  kubectl get svc -n dynatrace | grep -i otel

  ;;

2)

  echo ""
  echo "[INSTALL] OpenTelemetry Collector"

  kubectl create namespace dynatrace --dry-run=client -o yaml | kubectl apply -f -

  read -rp "Dynatrace OTLP Endpoint: " DT_ENDPOINT

  echo ""
  read -s -p "Dynatrace API Token: " DT_API_TOKEN
  echo ""
  echo "[OK] API Token cargado"

  kubectl create secret generic dynatrace-otelcol-dt-api-credentials \
    -n dynatrace \
    --dry-run=client -o yaml \
    --from-literal=DT_ENDPOINT="$DT_ENDPOINT" \
    --from-literal=DT_API_TOKEN="$DT_API_TOKEN" | kubectl apply -f -

  echo "[OK] Secret creado"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap

metadata:
  name: dynatrace-otel-config
  namespace: dynatrace

data:
  config.yaml: |

    receivers:
      otlp:
        protocols:

          grpc:
            endpoint: "0.0.0.0:4317"

          http:
            endpoint: "0.0.0.0:4318"

    exporters:

      otlphttp:
        endpoint: \${env:DT_ENDPOINT}

        timeout: 30s

        tls:
          insecure_skip_verify: true

        headers:
          Authorization: "Api-Token \${env:DT_API_TOKEN}"

    service:

      pipelines:

        traces:
          receivers: [otlp]
          exporters: [otlphttp]

        metrics:
          receivers: [otlp]
          exporters: [otlphttp]

        logs:
          receivers: [otlp]
          exporters: [otlphttp]
EOF

echo "[OK] ConfigMap creado"

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment

metadata:
  name: dynatrace-otel
  namespace: dynatrace

spec:

  replicas: 1

  selector:
    matchLabels:
      app: dynatrace-otel

  template:

    metadata:
      labels:
        app: dynatrace-otel

    spec:

      containers:

      - name: otel-collector

        image: otel/opentelemetry-collector-contrib:latest

        args:
          - "--config=/etc/otelcol/config.yaml"

        env:

        - name: DT_ENDPOINT
          valueFrom:
            secretKeyRef:
              name: dynatrace-otelcol-dt-api-credentials
              key: DT_ENDPOINT

        - name: DT_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: dynatrace-otelcol-dt-api-credentials
              key: DT_API_TOKEN

        ports:
        - containerPort: 4317
        - containerPort: 4318

        volumeMounts:
        - name: config
          mountPath: /etc/otelcol

      volumes:
      - name: config
        configMap:
          name: dynatrace-otel-config

---
apiVersion: v1
kind: Service

metadata:
  name: dynatrace-otel
  namespace: dynatrace

spec:

  selector:
    app: dynatrace-otel

  ports:

  - name: grpc
    port: 4317
    targetPort: 4317

  - name: http
    port: 4318
    targetPort: 4318
EOF

echo "[OK] Deployment creado"

kubectl get pods -n dynatrace

  ;;

3)

  echo ""
  echo "[TEST] Trace OpenTelemetry"

  kubectl delete pod otel-test -n dynatrace --ignore-not-found

  START=$(date +%s%N)
  END=$((START + 1000000000))

  kubectl run otel-test \
    --image=curlimages/curl \
    --restart=Never \
    -n dynatrace \
    -- curl -s -X POST http://dynatrace-otel:4318/v1/traces \
    -H "Content-Type: application/json" \
    -d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"test-service\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"5B8EFFF798038103D269B633813FC60C\",\"spanId\":\"EEE19B7EC3C1B174\",\"name\":\"test-span\",\"startTimeUnixNano\":\"$START\",\"endTimeUnixNano\":\"$END\",\"kind\":2,\"status\":{\"code\":1}}]}]}]}"

  echo ""
  echo "[INFO] Esperando pod test..."

  sleep 5

  kubectl logs otel-test -n dynatrace

  ;;

4)

  echo ""
  echo "[CLEANUP] OpenTelemetry Collector"

  kubectl delete deployment dynatrace-otel -n dynatrace --ignore-not-found

  kubectl delete svc dynatrace-otel -n dynatrace --ignore-not-found

  kubectl delete configmap dynatrace-otel-config -n dynatrace --ignore-not-found

  kubectl delete secret dynatrace-otelcol-dt-api-credentials -n dynatrace --ignore-not-found

  kubectl delete pod otel-test -n dynatrace --ignore-not-found

  ;;

*)

  echo "Opcion invalida"

  ;;

esac
