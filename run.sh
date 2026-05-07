#!/bin/bash

clear

echo "========================================="
echo " Dynatrace Automation"
echo "========================================="

echo "1 - Linux Host"
echo "2 - Windows Host"
echo "3 - Kubernetes"
echo "4 - OpenShift"

read -rp "Seleccione modo: " MODE

echo ""
echo "1 - Check"
echo "2 - Cleanup"
echo "3 - Install"
echo "4 - Verify"

read -rp "Seleccione opcion: " ACTION

case "$ACTION" in
  1) bash dynatrace_automatizacion_OK.sh check ;;
  2) bash dynatrace_automatizacion_OK.sh cleanup ;;
  3) bash dynatrace_automatizacion_OK.sh install ;;
  4) bash dynatrace_automatizacion_OK.sh verify ;;
  *) echo "Opcion invalida" ;;
esac
