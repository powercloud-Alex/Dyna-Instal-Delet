#!/bin/bash
# ============================================================
# Dynatrace - Check / Cleanup / Install
# Autor: PowerCloud
# Uso:
#   bash dynatrace_automation.sh check
#   bash dynatrace_automation.sh cleanup
#   bash dynatrace_automation.sh install
#   bash dynatrace_automation.sh verify
#
# Opciones:
#   --tenant https://xxxx.apps.dynatrace.com
#   --namespace dynatrace
#   --api-token <TOKEN>
#   --ingest-token <TOKEN>
#   --cluster-url https://api.ocp.example.com:6443
#   --cluster-user usuario
#   --delete-crds
#   --dry-run
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

MODE="${1:-check}"
shift || true

DT_NAMESPACE="dynatrace"
TENANT=""
ENV_ID=""
API_TOKEN=""
INGEST_TOKEN=""
CLUSTER_URL=""
CLUSTER_USER=""
CLUSTER_PASS=""
DELETE_CRDS=false
DRY_RUN=false
KCTL=""

log()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
found()  { echo -e "${RED}[FOUND]${NC} $*"; }
action() { echo -e "${BLUE}[ACTION]${NC} $*"; }
title()  { echo -e "\n${BOLD}${BLUE}============================================================${NC}"; echo -e "${BOLD}${BLUE} $*${NC}"; echo -e "${BOLD}${BLUE}============================================================${NC}"; }

usage() {
  cat <<EOF

Uso:
  bash $0 [check|cleanup|install|verify] [opciones]

Modos:
  check       Verifica si hay Dynatrace instalado
  cleanup     Borra recursos Dynatrace
  install     Instala Dynatrace Operator + DynaKube
  verify      Valida estado post instalacion

Opciones:
  --tenant <URL>          Tenant Dynatrace. Si no se pasa, lo pide.
  --namespace <NS>        Namespace. Default: dynatrace.
  --api-token <TOKEN>     API token. Si install lo necesita y no se pasa, lo pide.
  --ingest-token <TOKEN>  Ingest token. Si install lo necesita y no se pasa, lo pide.
  --cluster-url <URL>     URL API cluster OpenShift/K8s para login opcional.
  --cluster-user <USER>   Usuario cluster para login opcional.
  --delete-crds           Borra CRDs Dynatrace durante cleanup.
  --dry-run               Muestra acciones sin ejecutar borrado/instalacion.

Ejemplos:
  bash $0 check
  bash $0 cleanup --tenant https://abc12345.apps.dynatrace.com
  bash $0 cleanup --delete-crds
  bash $0 install
  bash $0 install --tenant https://abc12345.apps.dynatrace.com

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant) TENANT="${2:-}"; shift 2 ;;
    --namespace) DT_NAMESPACE="${2:-}"; shift 2 ;;
    --api-token) API_TOKEN="${2:-}"; shift 2 ;;
    --ingest-token) INGEST_TOKEN="${2:-}"; shift 2 ;;
    --cluster-url) CLUSTER_URL="${2:-}"; shift 2 ;;
    --cluster-user) CLUSTER_USER="${2:-}"; shift 2 ;;
    --delete-crds) DELETE_CRDS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Parametro desconocido: $1"; shift ;;
  esac
done

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    eval "$@"
  fi
}

detect_kctl() {
  if command -v oc >/dev/null 2>&1; then
    KCTL="oc"
  elif command -v kubectl >/dev/null 2>&1; then
    KCTL="kubectl"
  else
    KCTL=""
  fi
}

request_tenant() {
  if [ -z "$TENANT" ]; then
    echo ""
    read -r -p "Tenant Dynatrace URL ej https://abc12345.apps.dynatrace.com: " TENANT
  fi

  if [ -z "$TENANT" ]; then
    warn "Tenant obligatorio."
    exit 1
  fi

  ENV_ID=$(echo "$TENANT" | sed 's|https://||' | cut -d'.' -f1)

  if [[ ! "$TENANT" =~ ^https://[a-zA-Z0-9-]+\.apps\.dynatrace\.com$ ]] && \
     [[ ! "$TENANT" =~ ^https://[a-zA-Z0-9-]+\.live\.dynatrace\.com$ ]]; then
    warn "Formato de tenant no reconocido: $TENANT"
    read -r -p "Continuar igual? escribir SI: " CONTINUE
    [ "$CONTINUE" = "SI" ] || exit 0
  fi

  ok "Tenant: $TENANT"
  ok "Env ID: $ENV_ID"
}

request_cluster_login_optional() {
  detect_kctl

  if [ -z "$KCTL" ]; then
    warn "No se encontro oc ni kubectl. Se omiten acciones Kubernetes."
    return
  fi

  echo ""
  log "Cliente Kubernetes detectado: $KCTL"

  if [ "$KCTL" = "oc" ]; then
    if ! $KCTL whoami >/dev/null 2>&1; then
      warn "No hay sesion activa en OpenShift."
      read -r -p "Desea hacer oc login ahora? (s/N): " DO_LOGIN
      if [[ "$DO_LOGIN" =~ ^[sS]$ ]]; then
        [ -z "$CLUSTER_URL" ] && read -r -p "Cluster API URL: " CLUSTER_URL
        [ -z "$CLUSTER_USER" ] && read -r -p "Usuario cluster: " CLUSTER_USER
        read -r -s -p "Clave cluster: " CLUSTER_PASS
        echo ""
        run_cmd "$KCTL login \"$CLUSTER_URL\" -u \"$CLUSTER_USER\" -p \"$CLUSTER_PASS\""
      fi
    else
      ok "Sesion OpenShift activa como: $($KCTL whoami 2>/dev/null)"
    fi
  else
    if ! $KCTL cluster-info >/dev/null 2>&1; then
      warn "kubectl no tiene conexion activa al cluster."
      warn "Configure kubeconfig antes de install/cleanup."
    else
      ok "kubectl conectado al cluster."
    fi
  fi
}

request_tokens_for_install() {
  if [ "$MODE" != "install" ]; then
    return
  fi

  echo ""
  if [ -z "$API_TOKEN" ]; then
    read -r -s -p "Dynatrace API Token: " API_TOKEN
    echo ""
  fi

  if [ -z "$INGEST_TOKEN" ]; then
    read -r -s -p "Dynatrace Data Ingest Token: " INGEST_TOKEN
    echo ""
  fi

  if [ -z "$API_TOKEN" ] || [ -z "$INGEST_TOKEN" ]; then
    warn "API token e Ingest token son obligatorios para instalar."
    exit 1
  fi
}

check_oneagent() {
  title "1. OneAgent - Host"

  if pgrep -x "oneagentwatchdog" >/dev/null 2>&1 || pgrep -f "oneagent" >/dev/null 2>&1; then
    found "Proceso OneAgent activo"
    ps aux | grep -i oneagent | grep -v grep || true
  else
    ok "Proceso OneAgent no encontrado"
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service 2>/dev/null | grep -qi "oneagent"; then
    found "Servicio systemd OneAgent encontrado"
    systemctl status oneagent 2>/dev/null | head -10 || true
  else
    ok "Servicio systemd OneAgent no encontrado"
  fi

  [ -d "/opt/dynatrace/oneagent" ] && found "Existe /opt/dynatrace/oneagent" || ok "No existe /opt/dynatrace/oneagent"
  [ -d "/opt/dynatrace" ] && found "Existe /opt/dynatrace" || ok "No existe /opt/dynatrace"
  [ -f "/opt/dynatrace/oneagent/agent/uninstall.sh" ] && found "Uninstaller encontrado" || ok "Uninstaller no encontrado"
}

check_kubernetes() {
  title "2. Kubernetes / OpenShift - Dynatrace"

  if [ -z "$KCTL" ]; then
    warn "Sin oc/kubectl"
    return
  fi

  if $KCTL get namespace "$DT_NAMESPACE" >/dev/null 2>&1; then
    found "Namespace $DT_NAMESPACE existe"
    $KCTL get all -n "$DT_NAMESPACE" 2>/dev/null || true
  else
    ok "Namespace $DT_NAMESPACE no existe"
  fi

  $KCTL get dynakube -n "$DT_NAMESPACE" 2>/dev/null || ok "No hay DynaKube o CRD no instalado"
  $KCTL get crd 2>/dev/null | grep -i dynatrace || ok "No hay CRDs Dynatrace"
  $KCTL get clusterrole 2>/dev/null | grep -i dynatrace || ok "No hay ClusterRoles Dynatrace"
  $KCTL get clusterrolebinding 2>/dev/null | grep -i dynatrace || ok "No hay ClusterRoleBindings Dynatrace"
  $KCTL get mutatingwebhookconfiguration 2>/dev/null | grep -i dynatrace || ok "No hay MutatingWebhooks Dynatrace"
  $KCTL get validatingwebhookconfiguration 2>/dev/null | grep -i dynatrace || ok "No hay ValidatingWebhooks Dynatrace"
  $KCTL get priorityclass 2>/dev/null | grep -i dynatrace || ok "No hay PriorityClasses Dynatrace"
  $KCTL get csidriver 2>/dev/null | grep -i dynatrace || ok "No hay CSIDrivers Dynatrace"

  log "Pods Dynatrace en todos los namespaces:"
  $KCTL get pods -A 2>/dev/null | grep -i dynatrace || ok "No hay pods Dynatrace"
}

check_helm() {
  title "3. Helm"

  if ! command -v helm >/dev/null 2>&1; then
    warn "helm no disponible"
    return
  fi

  helm list -n "$DT_NAMESPACE" 2>/dev/null | grep -i dynatrace || ok "No hay release Dynatrace en $DT_NAMESPACE"
  helm list -A 2>/dev/null | grep -i dynatrace || ok "No hay releases Dynatrace globales"
}

cleanup_oneagent() {
  title "CLEANUP 1. OneAgent Host"

  if [ -f "/opt/dynatrace/oneagent/agent/uninstall.sh" ]; then
    action "Ejecutando uninstaller"
    run_cmd "sudo /opt/dynatrace/oneagent/agent/uninstall.sh || true"
  else
    ok "Uninstaller no encontrado"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    run_cmd "sudo systemctl stop oneagent 2>/dev/null || true"
    run_cmd "sudo systemctl disable oneagent 2>/dev/null || true"
  fi

  if [ -d "/opt/dynatrace" ]; then
    action "Eliminando /opt/dynatrace"
    run_cmd "sudo rm -rf /opt/dynatrace"
  fi
}

cleanup_kubernetes() {
  title "CLEANUP 2. Kubernetes / OpenShift"

  if [ -z "$KCTL" ]; then
    warn "Sin oc/kubectl"
    return
  fi

  if $KCTL get dynakube -n "$DT_NAMESPACE" >/dev/null 2>&1; then
    action "Eliminando DynaKube"
    run_cmd "$KCTL delete dynakube --all -n \"$DT_NAMESPACE\" --timeout=120s || true"
  fi

  if command -v helm >/dev/null 2>&1; then
    RELEASES=$(helm list -n "$DT_NAMESPACE" -q 2>/dev/null | grep -i dynatrace || true)
    for rel in $RELEASES; do
      action "Helm uninstall $rel"
      run_cmd "helm uninstall \"$rel\" -n \"$DT_NAMESPACE\" || true"
    done
  fi

  action "Eliminando recursos comunes Dynatrace"
  run_cmd "$KCTL delete daemonset,statefulset,deployment,service,configmap,secret,serviceaccount,role,rolebinding -n \"$DT_NAMESPACE\" -l app.kubernetes.io/name=dynatrace-operator --ignore-not-found=true || true"
  run_cmd "$KCTL delete daemonset,statefulset,deployment,service,configmap,secret,serviceaccount,role,rolebinding -n \"$DT_NAMESPACE\" -l app.kubernetes.io/part-of=dynatrace --ignore-not-found=true || true"

  action "Eliminando secrets conocidos"
  for s in dynakube dynatrace-tokens dynatrace-docker-registry dynakube-api; do
    run_cmd "$KCTL delete secret \"$s\" -n \"$DT_NAMESPACE\" --ignore-not-found=true || true"
  done

  if $KCTL get namespace "$DT_NAMESPACE" >/dev/null 2>&1; then
    action "Eliminando namespace $DT_NAMESPACE"
    run_cmd "$KCTL delete namespace \"$DT_NAMESPACE\" --timeout=180s || true"
  fi

  action "Eliminando webhooks y permisos cluster-wide"
  $KCTL get mutatingwebhookconfiguration 2>/dev/null | grep -i dynatrace | awk '{print $1}' | while read -r x; do [ -n "$x" ] && run_cmd "$KCTL delete mutatingwebhookconfiguration \"$x\" || true"; done
  $KCTL get validatingwebhookconfiguration 2>/dev/null | grep -i dynatrace | awk '{print $1}' | while read -r x; do [ -n "$x" ] && run_cmd "$KCTL delete validatingwebhookconfiguration \"$x\" || true"; done
  $KCTL get clusterrole 2>/dev/null | grep -i dynatrace | awk '{print $1}' | while read -r x; do [ -n "$x" ] && run_cmd "$KCTL delete clusterrole \"$x\" || true"; done
  $KCTL get clusterrolebinding 2>/dev/null | grep -i dynatrace | awk '{print $1}' | while read -r x; do [ -n "$x" ] && run_cmd "$KCTL delete clusterrolebinding \"$x\" || true"; done

  action "Eliminando PriorityClasses Dynatrace"
  $KCTL get priorityclass 2>/dev/null | grep -i dynatrace | awk '{print $1}' | while read -r x; do [ -n "$x" ] && run_cmd "$KCTL delete priorityclass \"$x\" || true"; done

  action "Eliminando CSIDrivers Dynatrace"
  $KCTL get csidriver 2>/dev/null | grep -i dynatrace | awk '{print $1}' | while read -r x; do [ -n "$x" ] && run_cmd "$KCTL delete csidriver \"$x\" || true"; done

  if [ "$DELETE_CRDS" = true ]; then
    warn "Borrando CRDs Dynatrace por --delete-crds"
    $KCTL get crd 2>/dev/null | grep -i dynatrace | awk '{print $1}' | while read -r x; do [ -n "$x" ] && run_cmd "$KCTL delete crd \"$x\" || true"; done
  else
    warn "CRDs no borrados. Para borrarlos usar --delete-crds"
  fi
}

cleanup_crio_hooks() {
  title "CLEANUP 3. CRI-O Hooks"

  for dir in /etc/containers/oci/hooks.d /usr/share/containers/oci/hooks.d /run/containers/oci/hooks.d; do
    if [ -d "$dir" ]; then
      action "Buscando hooks Dynatrace en $dir"
      run_cmd "sudo find \"$dir\" -name \"*dynatrace*\" -delete 2>/dev/null || true"
    fi
  done
}

install_dynatrace() {
  title "INSTALL. Dynatrace Operator + DynaKube"

  if [ -z "$KCTL" ]; then
    warn "No se puede instalar sin oc/kubectl"
    exit 1
  fi

  if ! command -v helm >/dev/null 2>&1; then
    warn "helm es requerido para instalar el Operator."
    exit 1
  fi

  action "Creando namespace $DT_NAMESPACE"
  run_cmd "$KCTL create namespace \"$DT_NAMESPACE\" --dry-run=client -o yaml | $KCTL apply -f -"

  action "Creando secret dynakube"
  run_cmd "$KCTL -n \"$DT_NAMESPACE\" delete secret dynakube --ignore-not-found=true"
  run_cmd "$KCTL -n \"$DT_NAMESPACE\" create secret generic dynakube --from-literal=\"apiToken=$API_TOKEN\" --from-literal=\"dataIngestToken=$INGEST_TOKEN\""

  action "Instalando Dynatrace Operator con Helm"
  run_cmd "helm upgrade --install dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator --namespace \"$DT_NAMESPACE\" --atomic"

  cat > /tmp/dynakube.yaml <<EOF
apiVersion: dynatrace.com/v1beta5
kind: DynaKube
metadata:
  name: dynakube
  namespace: $DT_NAMESPACE
spec:
  apiUrl: https://$ENV_ID.live.dynatrace.com/api
  tokens: dynakube

  oneAgent:
    cloudNativeFullStack: {}

  activeGate:
    capabilities:
      - routing
      - kubernetes-monitoring

  metadataEnrichment:
    enabled: true
EOF

  action "Aplicando DynaKube"
  if [ "$DRY_RUN" = true ]; then
    cat /tmp/dynakube.yaml
  else
    $KCTL apply -f /tmp/dynakube.yaml
  fi

  ok "Instalacion enviada."
}

verify_dynatrace() {
  title "VERIFY. Estado Dynatrace"

  if [ -z "$KCTL" ]; then
    warn "Sin oc/kubectl"
    return
  fi

  $KCTL get namespace "$DT_NAMESPACE" 2>/dev/null || true
  $KCTL get pods -n "$DT_NAMESPACE" -o wide 2>/dev/null || true
  $KCTL get dynakube -n "$DT_NAMESPACE" 2>/dev/null || true
  $KCTL describe dynakube dynakube -n "$DT_NAMESPACE" 2>/dev/null || true
  $KCTL get events -n "$DT_NAMESPACE" --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
}

header() {
  echo ""
  echo -e "${BOLD}${CYAN}============================================================${NC}"
  echo -e "${BOLD}${CYAN} DYNATRACE - AUTOMATIZACION GENERICA${NC}"
  echo -e "${BOLD}${CYAN} Modo      : $MODE${NC}"
  echo -e "${BOLD}${CYAN} Namespace : $DT_NAMESPACE${NC}"
  echo -e "${BOLD}${CYAN} Tenant    : $TENANT${NC}"
  echo -e "${BOLD}${CYAN} Env ID    : $ENV_ID${NC}"
  echo -e "${BOLD}${CYAN}============================================================${NC}"
  echo ""
}

case "$MODE" in
  check|cleanup|install|verify) ;;
  *) usage; exit 1 ;;
esac

request_tenant
request_cluster_login_optional
request_tokens_for_install
header

case "$MODE" in
  check)
    check_oneagent
    check_kubernetes
    check_helm
    ok "CHECK completado"
    ;;

  cleanup)
    warn "Se eliminaran recursos Dynatrace."
    warn "Namespace: $DT_NAMESPACE"
    warn "Tenant: $TENANT"
    read -r -p "Para confirmar escriba SI: " CONFIRM
    [ "$CONFIRM" = "SI" ] || { log "Cancelado."; exit 0; }

    cleanup_oneagent
    cleanup_kubernetes
    cleanup_crio_hooks
    verify_dynatrace
    ok "CLEANUP completado"
    ;;

  install)
    install_dynatrace
    verify_dynatrace
    ok "INSTALL completado"
    ;;

  verify)
    verify_dynatrace
    ok "VERIFY completado"
    ;;
esac



