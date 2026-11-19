param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $project 'Setup-Limpiador-IA.msi' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$app = Get-Item -LiteralPath (Join-Path $project 'Limpiador-IA.exe')
$icon = Join-Path $PSScriptRoot 'Limpiador-IA.ico'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('Limpiador-MSI-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)

function Invoke-Sql($sql, $record) {
    $view = $database.OpenView($sql)
    try { if ($null -eq $record) { $view.Execute() } else { $view.Execute($record) } }
    finally { $view.Close(); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) }
}

function Set-ComField($object, $name, [int]$index, $value) {
    [void]$object.GetType().InvokeMember($name, 'SetProperty', $null, $object, @($index, $value))
}

function Add-Row($table, [string[]]$columns, [object[]]$values) {
    $record = $installer.CreateRecord($columns.Count)
    try {
        for ($index = 0; $index -lt $values.Count; $index++) {
            $value = $values[$index]
            if ($null -eq $value) { continue }
            if ($value -is [IO.FileInfo]) { $record.SetStream($index + 1, $value.FullName) }
            elseif ($value -is [int]) { Set-ComField $record 'IntegerData' ($index + 1) $value }
            else { Set-ComField $record 'StringData' ($index + 1) ([string]$value) }
        }
        $quoted = ($columns | ForEach-Object { '`{0}`' -f $_ }) -join ', '
        $parameters = (($columns | ForEach-Object { '?' }) -join ', ')
        Invoke-Sql ('INSERT INTO `{0}` ({1}) VALUES ({2})' -f $table,$quoted,$parameters) $record
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) }
}

$ddf = Join-Path $stage 'payload.ddf'
$cab = Join-Path $stage 'payload.cab'
$package = Join-Path $stage 'Limpiador.msi'
$installer = $database = $summary = $null
try {
    @"
.OPTION EXPLICIT
.Set Cabinet=ON
.Set Compress=ON
.Set CompressionType=LZX
.Set DiskDirectoryTemplate="$stage"
.Set CabinetNameTemplate=payload.cab
.Set InfFileName="$stage\payload.inf"
.Set RptFileName="$stage\payload.rpt"
"$($app.FullName)" MainExe
"@ | Set-Content -LiteralPath $ddf -Encoding ascii
    & (Join-Path ([Environment]::SystemDirectory) 'makecab.exe') /F $ddf | Out-Null
    if ($LASTEXITCODE -or -not [IO.File]::Exists($cab)) { throw 'No se pudo crear el gabinete de instalación.' }

    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase($package, 3)
    $schema = @"
CREATE TABLE ``Property`` (``Property`` CHAR(72) NOT NULL, ``Value`` CHAR(0) LOCALIZABLE PRIMARY KEY ``Property``)
CREATE TABLE ``Directory`` (``Directory`` CHAR(72) NOT NULL, ``Directory_Parent`` CHAR(72), ``DefaultDir`` CHAR(255) NOT NULL LOCALIZABLE PRIMARY KEY ``Directory``)
CREATE TABLE ``Component`` (``Component`` CHAR(72) NOT NULL, ``ComponentId`` CHAR(38), ``Directory_`` CHAR(72) NOT NULL, ``Attributes`` SHORT NOT NULL, ``Condition`` CHAR(255), ``KeyPath`` CHAR(72) PRIMARY KEY ``Component``)
CREATE TABLE ``Feature`` (``Feature`` CHAR(38) NOT NULL, ``Feature_Parent`` CHAR(38), ``Title`` CHAR(64) LOCALIZABLE, ``Description`` CHAR(255) LOCALIZABLE, ``Display`` SHORT, ``Level`` SHORT NOT NULL, ``Directory_`` CHAR(72), ``Attributes`` SHORT NOT NULL PRIMARY KEY ``Feature``)
CREATE TABLE ``FeatureComponents`` (``Feature_`` CHAR(38) NOT NULL, ``Component_`` CHAR(72) NOT NULL PRIMARY KEY ``Feature_``, ``Component_``)
CREATE TABLE ``File`` (``File`` CHAR(72) NOT NULL, ``Component_`` CHAR(72) NOT NULL, ``FileName`` CHAR(255) NOT NULL LOCALIZABLE, ``FileSize`` LONG NOT NULL, ``Version`` CHAR(72), ``Language`` CHAR(20), ``Attributes`` SHORT, ``Sequence`` SHORT NOT NULL PRIMARY KEY ``File``)
CREATE TABLE ``Media`` (``DiskId`` SHORT NOT NULL, ``LastSequence`` SHORT NOT NULL, ``DiskPrompt`` CHAR(64) LOCALIZABLE, ``Cabinet`` CHAR(255), ``VolumeLabel`` CHAR(32), ``Source`` CHAR(72) PRIMARY KEY ``DiskId``)
CREATE TABLE ``Shortcut`` (``Shortcut`` CHAR(72) NOT NULL, ``Directory_`` CHAR(72) NOT NULL, ``Name`` CHAR(128) NOT NULL LOCALIZABLE, ``Component_`` CHAR(72) NOT NULL, ``Target`` CHAR(72) NOT NULL, ``Arguments`` CHAR(255), ``Description`` CHAR(255) LOCALIZABLE, ``Hotkey`` SHORT, ``Icon_`` CHAR(72), ``IconIndex`` SHORT, ``ShowCmd`` SHORT, ``WkDir`` CHAR(72), ``DisplayResourceDLL`` CHAR(255), ``DisplayResourceId`` SHORT, ``DescriptionResourceDLL`` CHAR(255), ``DescriptionResourceId`` SHORT PRIMARY KEY ``Shortcut``)
CREATE TABLE ``Icon`` (``Name`` CHAR(72) NOT NULL, ``Data`` OBJECT NOT NULL PRIMARY KEY ``Name``)
CREATE TABLE ``InstallExecuteSequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)
CREATE TABLE ``AdminExecuteSequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)
CREATE TABLE ``InstallUISequence`` (``Action`` CHAR(72) NOT NULL, ``Condition`` CHAR(255), ``Sequence`` SHORT PRIMARY KEY ``Action``)
"@
    foreach ($definition in ($schema -split '\r?\n')) { Invoke-Sql $definition $null }

    $properties = [ordered]@{
        ProductName = 'Limpiador de IA'
        Manufacturer = 'Limpiador de IA'
        ProductVersion = '1.0.0'
        ProductLanguage = '3082'
        ProductCode = '{82DBCC49-18B8-463A-B491-AE582E8B33C3}'
        UpgradeCode = '{971DA232-086F-40CD-8B24-1E1AE6AFB1D8}'
        ALLUSERS = '1'
        ARPPRODUCTICON = 'Limpiador.ico'
        ARPNOMODIFY = '1'
        ARPNOREPAIR = '1'
    }
    foreach ($property in $properties.GetEnumerator()) {
        Add-Row 'Property' @('Property','Value') @($property.Key,$property.Value)
    }

    $dirColumns = 'Directory','Directory_Parent','DefaultDir'
    Add-Row 'Directory' $dirColumns @('TARGETDIR',$null,'SourceDir')
    Add-Row 'Directory' $dirColumns @('ProgramFiles64Folder','TARGETDIR','.')
    Add-Row 'Directory' $dirColumns @('INSTALLFOLDER','ProgramFiles64Folder','LIMP_IA|Limpiador de IA')
    Add-Row 'Directory' $dirColumns @('ProgramMenuFolder','TARGETDIR','.')

    Add-Row 'Component' @('Component','ComponentId','Directory_','Attributes','KeyPath') @(
        'AppComponent','{A1E2E01A-AEE8-405A-BB68-6267BEBC36EC}','INSTALLFOLDER',256,'MainExe')
    Add-Row 'Feature' @('Feature','Title','Display','Level','Directory_','Attributes') @(
        'App','Limpiador de IA',2,1,'INSTALLFOLDER',0)
    Add-Row 'FeatureComponents' @('Feature_','Component_') @('App','AppComponent')
    Add-Row 'File' @('File','Component_','FileName','FileSize','Attributes','Sequence') @(
        'MainExe','AppComponent','LIMP_IA.EXE|Limpiador-IA.exe',[int]$app.Length,16384,1)
    Add-Row 'Media' @('DiskId','LastSequence','Cabinet') @(1,1,'#payload.cab')
    Add-Row '_Streams' @('Name','Data') @('payload.cab',(Get-Item -LiteralPath $cab))
    Add-Row 'Icon' @('Name','Data') @('Limpiador.ico',(Get-Item -LiteralPath $icon))
    Add-Row 'Shortcut' @('Shortcut','Directory_','Name','Component_','Target','Description','Icon_','IconIndex','ShowCmd','WkDir') @(
        'StartMenuLink','ProgramMenuFolder','LIMP_IA|Limpiador de IA','AppComponent','[#MainExe]',
        'Revisa y limpia archivos del disco','Limpiador.ico',0,1,'INSTALLFOLDER')

    $execute = [ordered]@{
        CostInitialize=800; FileCost=900; CostFinalize=1000; InstallValidate=1400
        InstallInitialize=1500; ProcessComponents=1600; UnpublishFeatures=1800
        RemoveShortcuts=3200; RemoveFiles=3500; InstallFiles=4000; CreateShortcuts=4500
        RegisterUser=6000; RegisterProduct=6100; PublishFeatures=6300; PublishProduct=6400; InstallFinalize=6600
    }
    $admin = [ordered]@{
        CostInitialize=800; FileCost=900; CostFinalize=1000; InstallValidate=1400
        InstallInitialize=1500; InstallAdminPackage=3900; InstallFiles=4000; InstallFinalize=6600
    }
    foreach ($action in $execute.GetEnumerator()) {
        Add-Row 'InstallExecuteSequence' @('Action','Sequence') @($action.Key,$action.Value)
    }
    foreach ($action in $admin.GetEnumerator()) {
        Add-Row 'AdminExecuteSequence' @('Action','Sequence') @($action.Key,$action.Value)
    }
    foreach ($action in ([ordered]@{CostInitialize=800;FileCost=900;CostFinalize=1000;ExecuteAction=1300}).GetEnumerator()) {
        Add-Row 'InstallUISequence' @('Action','Sequence') @($action.Key,$action.Value)
    }

    $summary = $database.SummaryInformation(12)
    foreach ($entry in ([ordered]@{
        2='Instalador de Limpiador de IA'; 3='Limpiador de IA'; 4='Limpiador de IA'; 7='x64;3082'
        9=([guid]::NewGuid().ToString('B').ToUpperInvariant()); 14=500; 15=2
    }).GetEnumerator()) {
        Set-ComField $summary 'Property' $entry.Key $entry.Value
    }
    $summary.Persist()
    $database.Commit()
} finally {
    foreach ($object in $summary,$database,$installer) {
        if ($object) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($object) }
    }
}

try { Copy-Item -LiteralPath $package -Destination $OutputPath -Force }
finally {
    foreach ($file in $ddf,$cab,$package,(Join-Path $stage 'payload.inf'),(Join-Path $stage 'payload.rpt')) { [IO.File]::Delete($file) }
    [IO.Directory]::Delete($stage)
}
Get-Item -LiteralPath $OutputPath
