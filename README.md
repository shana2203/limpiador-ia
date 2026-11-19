# Limpiador de IA

Aplicación para Windows x64 que analiza el uso de las unidades y permite limpiar cachés y archivos seleccionados. La limpieza requiere confirmación y la aplicación conserva un registro local.

## Descargas

En [Releases](../../releases/latest) están el instalador `Setup-Limpiador-IA.msi` y la versión portátil `Limpiador-IA.exe`. La aplicación solicita permisos de administrador al abrir.

## Compilación

Desde PowerShell en la carpeta del repositorio:

```powershell
& '.\Codigo fuente\Compilar.ps1'
& '.\Codigo fuente\Compilar-Instalador.ps1'
```

Los dos archivos se generan en la carpeta principal.
