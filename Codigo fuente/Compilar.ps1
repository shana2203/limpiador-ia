$ErrorActionPreference = 'Stop'
$windows = [IO.Directory]::GetParent([Environment]::SystemDirectory).FullName
$compiler = Join-Path $windows 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$automation = Join-Path $windows 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'

$output = Join-Path (Split-Path -Parent $PSScriptRoot) 'Limpiador-IA.exe'

Push-Location -LiteralPath $PSScriptRoot
try {
    & $compiler /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /win32icon:Limpiador-IA.ico "/reference:$automation" /win32manifest:Limpiador.manifest /resource:Limpiador-IA.ps1,Limpiador.ps1 "/out:$output" Launcher.cs
    if ($LASTEXITCODE) { throw "Error al compilar ($LASTEXITCODE)." }
} finally {
    Pop-Location
}
