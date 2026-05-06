#!/bin/bash
echo "========================================="

echo "1 - Check"
echo "2 - Cleanup"
echo "3 - Install"
read -rp "Seleccione opcion: " OPTION

case $OPTION in

  1)
    $KCTL get ns dynatrace 2>/dev/null
    $KCTL get pods -A | grep -i dynatrace || true
    ;;

  2)
    echo "Eliminando Dynatrace..."

    helm uninstall dynatrace-operator -n dynatrace 2>/dev/null || true

    $KCTL delete dynakube --all -n dynatrace 2>/dev/null || true
    $KCTL delete namespace dynatrace 2>/dev/null || true

    $KCTL get mutatingwebhookconfiguration | grep dynatrace | awk '{print $1}' | xargs -r $KCTL delete mutatingwebhookconfiguration
    $KCTL get validatingwebhookconfiguration | grep dynatrace | awk '{print $1}' | xargs -r $KCTL delete validatingwebhookconfiguration
    $KCTL get clusterrole | grep dynatrace | awk '{print $1}' | xargs -r $KCTL delete clusterrole
    $KCTL get clusterrolebinding | grep dynatrace | awk '{print $1}' | xargs -r $KCTL delete clusterrolebinding
    $KCTL get priorityclass | grep dynatrace | awk '{print $1}' | xargs -r $KCTL delete priorityclass
    $KCTL get csidriver | grep dynatrace | awk '{print $1}' | xargs -r $KCTL delete csidriver
    ;;

  3)
    read -rp "Tenant URL: " TENANT
    read -rsp "API Token: " API_TOKEN
    echo ""
    read -rsp "Data Ingest Token: " INGEST_TOKEN
    echo ""

    $KCTL create namespace dynatrace 2>/dev/null || true

    $KCTL -n dynatrace create secret generic dynakube \
      --from-literal="apiToken=$API_TOKEN" \
      --from-literal="dataIngestToken=$INGEST_TOKEN" \
      --dry-run=client -o yaml | $KCTL apply -f -

    helm upgrade --install dynatrace-operator \
      oci://public.ecr.aws/dynatrace/dynatrace-operator \
      -n dynatrace

cat <<EOF | $KCTL apply -f -
apiVersion: dynatrace.com/v1beta5
kind: DynaKube
metadata:
  name: dynakube
  namespace: dynatrace
spec:
  apiUrl: https://$(echo $TENANT | sed 's|https://||' | cut -d'.' -f1).live.dynatrace.com/api
  tokens: dynakube

  oneAgent:
    cloudNativeFullStack: {}

  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring
EOF

    ;;

  *)
    echo "Opcion invalida"
    ;;
esac
