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

case $MODE in
  1)
    bash dynatrace_linux.sh
    ;;
  2)
    echo "powershell -ExecutionPolicy Bypass -File .\\dynatrace_windows.ps1"
    ;;
  3)
    bash dynatrace_k8s.sh
    ;;
  4)
    bash dynatrace_k8s.sh
    ;;
esac
