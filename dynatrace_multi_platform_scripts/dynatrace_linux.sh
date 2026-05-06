#!/bin/bash

clear

echo "========================================="
echo " Dynatrace Linux Host"
echo "========================================="

echo "1 - Check"
echo "2 - Cleanup"
echo "3 - Install"
read -rp "Seleccione opcion: " OPTION

case $OPTION in
  1)
    echo "[CHECK] Verificando OneAgent..."
    ps aux | grep -i oneagent | grep -v grep || echo "No encontrado"
    systemctl status oneagent 2>/dev/null || true
    ;;

  2)
    echo "[CLEANUP] Eliminando OneAgent..."
    sudo /opt/dynatrace/oneagent/agent/uninstall.sh 2>/dev/null || true
    sudo systemctl stop oneagent 2>/dev/null || true
    sudo rm -rf /opt/dynatrace
    ;;

  3)
    read -rp "Tenant URL: " TENANT
    read -rsp "API Token: " TOKEN
    echo ""

    wget -O Dynatrace-OneAgent.sh "$TENANT/api/v1/deployment/installer/agent/unix/default/latest?Api-Token=$TOKEN&arch=x86&flavor=default"
    chmod +x Dynatrace-OneAgent.sh
    sudo ./Dynatrace-OneAgent.sh
    ;;

  *)
    echo "Opcion invalida"
    ;;
esac