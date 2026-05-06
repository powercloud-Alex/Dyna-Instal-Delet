#!/bin/bash
  1)
    echo ""
    echo "1 - Check"
    echo "2 - Cleanup"
    echo "3 - Install"
    echo "4 - Verify"

    read -rp "Seleccione opcion: " ACTION

    case $ACTION in
      1) bash dynatrace_automatizacion_OK.sh check ;;
      2) bash dynatrace_automatizacion_OK.sh cleanup ;;
      3) bash dynatrace_automatizacion_OK.sh install ;;
      4) bash dynatrace_automatizacion_OK.sh verify ;;
    esac
    ;;

  2)
    echo "Ejecutar desde Windows:"
    echo "powershell -ExecutionPolicy Bypass -File .\dynatrace_windows.ps1"
    ;;

  3|4)
    echo ""
    echo "1 - Check"
    echo "2 - Cleanup"
    echo "3 - Install"
    echo "4 - Verify"

    read -rp "Seleccione opcion: " ACTION

    case $ACTION in
      1) bash dynatrace_automatizacion_OK.sh check ;;
      2) bash dynatrace_automatizacion_OK.sh cleanup ;;
      3) bash dynatrace_automatizacion_OK.sh install ;;
      4) bash dynatrace_automatizacion_OK.sh verify ;;
    esac
    ;;

  *)
    echo "Modo invalido"
    ;;
esac
```bash
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
    echo "Ejecutar desde Windows:"
    echo "powershell -ExecutionPolicy Bypass -File .\\dynatrace_windows.ps1"
    ;;

  3)
    bash dynatrace_k8s.sh
    ;;

  4)
    bash dynatrace_k8s.sh
    ;;

  *)
    echo "Modo invalido"
    ;;
esac