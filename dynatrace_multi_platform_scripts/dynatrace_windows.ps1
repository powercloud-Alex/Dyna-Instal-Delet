Clear-Host

Write-Host "========================================="
Write-Host " Dynatrace Windows Host"
Write-Host "========================================="

Write-Host "1 - Check"
Write-Host "2 - Cleanup"
Write-Host "3 - Install"

$option = Read-Host "Seleccione opcion"

switch ($option) {

  "1" {
    Get-Service | findstr /I dynatrace
    Get-Process | findstr /I oneagent
  }

  "2" {
    Stop-Service oneagent -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Program Files\dynatrace" -Recurse -Force -ErrorAction SilentlyContinue
  }

  "3" {
    $tenant = Read-Host "Tenant URL"
    $token = Read-Host "API Token"

    Invoke-WebRequest -Uri "$tenant/api/v1/deployment/installer/agent/windows/default/latest?Api-Token=$token" -OutFile "Dynatrace-OneAgent.exe"

    Start-Process .\Dynatrace-OneAgent.exe -Wait
  }

  default {
    Write-Host "Opcion invalida"
  }
}
