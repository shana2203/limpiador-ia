param([switch]$Diagnostico)
$ErrorActionPreference = 'Stop'
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$roamingAppData = [Environment]::GetFolderPath('ApplicationData')
$userProfile = [Environment]::GetFolderPath('UserProfile')
$windowsPrefix = [IO.Directory]::GetParent([Environment]::SystemDirectory).FullName.TrimEnd('\') + '\'

$driveRoots = @([IO.DriveInfo]::GetDrives() | Where-Object {
    $_.IsReady -and $_.DriveType -in 'Fixed','Removable'
} | Select-Object -ExpandProperty Name)
$script:driveRoot = [IO.Path]::GetPathRoot([Environment]::SystemDirectory)

function Test-SafePath($path) {
    if ([IO.Path]::GetPathRoot($path) -notin $driveRoots) { return $false }
    if ($path.StartsWith($windowsPrefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    try {
        for ($part = $path; $part; $part = [IO.Path]::GetDirectoryName($part)) {
            if (([IO.File]::GetAttributes($part) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $false
            }
        }
        return $true
    } catch { return $false }
}

$aiApps = @('Claude','Codex','ChatGPT','Cursor','Windsurf','LM Studio','Perplexity')
$programApps = @('Chrome','Edge','Brave','Firefox','VS Code','Discord','Slack','Teams','GitHub Desktop','Epic Games Launcher','NVIDIA · sombreadores','Eden · sombreadores')
$windowsApp = 'Windows · DirectX'
$allApps = $aiApps + $programApps + $windowsApp
$largeScope = 'Archivos grandes'
$binScope = 'Papelera de la unidad'
$usageScope = 'Uso de la unidad'
$chosenReviewApp = 'Carpeta elegida'
$reviewApps = @('Salidas de Codex','Temporales de Claude','Imagen de Winhance','Escritorio','Copias de Suyu')
$processPatterns = @{
    Claude = '^claude'; Codex = '^(codex(?:$|-(?!windows-sandbox-service$))|chatgpt)'
    ChatGPT = '^chatgpt'; Cursor = '^cursor'; Windsurf = '^windsurf'
    'LM Studio' = '^(lm studio|lmstudio|lms|llmster)(?:$|[- ])'
    Perplexity = '^perplexity'; Chrome = '^chrome'; Edge = '^msedge'
    Brave = '^brave'; Firefox = '^firefox'; 'VS Code' = '^code(?:$|[ -])'
    Discord = '^discord'; Slack = '^slack'; Teams = '^(ms-teams|teams)(?:$|-)'
    'Salidas de Codex' = '^(codex|chatgpt)'; 'Temporales de Claude' = '^claude'
    'Imagen de Winhance' = '^(winhance|dism|dismhost)(?:$|[- ])'
    'Copias de Suyu' = '^suyu'; 'Eden · sombreadores' = '^(eden|eden-emu)(?:$|[- ])'
    'GitHub Desktop' = '^githubdesktop'; 'Epic Games Launcher' = '^(epicgameslauncher|epicwebhelper)'
}
$cacheNames = 'Cache','Code Cache','GPUCache','GPUPersistentCache','GrShaderCache','ShaderCache','DawnGraphiteCache','DawnWebGPUCache'
$browserRoots = @{
    Chrome = 'Google\Chrome\User Data'
    Edge = 'Microsoft\Edge\User Data'
    Brave = 'BraveSoftware\Brave-Browser\User Data'
}

function Get-ChildFolders($path, $mask = '*') {
    if (Test-SafePath $path) {
        Get-ChildItem -LiteralPath $path -Directory -Filter $mask -ErrorAction SilentlyContinue
    }
}

function Get-CacheRoots($app) {
    $paths = if ($app -eq $windowsApp) {
        Join-Path $localAppData 'D3DSCache'
    } elseif ($app -eq 'NVIDIA · sombreadores') {
        Join-Path $localAppData 'NVIDIA\DXCache'
    } elseif ($app -eq 'Eden · sombreadores') {
        Join-Path $roamingAppData 'eden\cache\shader'
    } elseif ($app -eq 'Firefox') {
        Get-ChildFolders "$localAppData\Mozilla\Firefox\Profiles" |
            ForEach-Object { Join-Path $_.FullName 'cache2' }
    } else {
        $profiles = if ($browserRoots.ContainsKey($app)) {
            $base = Join-Path $localAppData $browserRoots[$app]
            Get-ChildFolders $base |
                Where-Object Name -Match '^(Default|Profile \d+)$' |
                Select-Object -ExpandProperty FullName
        } else {
            switch ($app) {
                'Claude' {
                    Join-Path $roamingAppData 'Claude'
                    Get-ChildFolders "$localAppData\Claude-Data" 'claude_*' | ForEach-Object {
                        $_.FullName
                        Get-ChildFolders (Join-Path $_.FullName 'Partitions') | Select-Object -ExpandProperty FullName
                    }
                    Get-ChildFolders "$localAppData\Packages" 'Claude_*' |
                        ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude' }
                }
                'Codex' {
                    Join-Path $roamingAppData 'Codex\web\Codex'
                    Join-Path $roamingAppData 'Codex\web\Codex\Default'
                    Get-ChildFolders "$localAppData\Packages" 'OpenAI.Codex_*' | ForEach-Object {
                        $base = Join-Path $_.FullName 'LocalCache\Roaming\Codex\web\Codex'
                        $base
                        Join-Path $base 'Default'
                    }
                }
                'ChatGPT' {
                    Join-Path $roamingAppData 'ChatGPT'
                    Get-ChildFolders "$localAppData\Packages" '*ChatGPT*' | ForEach-Object {
                        Join-Path $_.FullName 'LocalCache\Roaming\ChatGPT'
                        $webview = Join-Path $_.FullName 'LocalState\EBWebView'
                        Join-Path $webview 'Default'
                    }
                }
                'Cursor' { Join-Path $roamingAppData 'Cursor' }
                'Windsurf' { Join-Path $roamingAppData 'Windsurf' }
                'LM Studio' { Join-Path $roamingAppData 'LM Studio' }
                'Perplexity' { Join-Path $roamingAppData 'Perplexity' }
                'VS Code' { Join-Path $roamingAppData 'Code' }
                'Discord' { Join-Path $roamingAppData 'discord' }
                'Slack' { Join-Path $roamingAppData 'Slack' }
                'Teams' { Join-Path $roamingAppData 'Microsoft\Teams' }
                'GitHub Desktop' { Join-Path $roamingAppData 'GitHub Desktop' }
                'Epic Games Launcher' {
                    Get-ChildFolders "$localAppData\EpicGamesLauncher\Saved" 'webcache*' |
                        Select-Object -ExpandProperty FullName
                }
            }
        }
        foreach ($profilePath in $profiles) {
            foreach ($name in $cacheNames) { Join-Path $profilePath $name }
        }
    }
    foreach ($path in $paths) {
        if ([IO.Directory]::Exists($path) -and (Test-SafePath $path)) { $path }
    }
}

function Get-ReviewRoots($app) {
    switch ($app) {
        $chosenReviewApp { $script:largeFolder }
        'Salidas de Codex' {
            $documents = [Environment]::GetFolderPath('MyDocuments')
            if ($documents) { Join-Path $documents 'Codex' }
            Join-Path $userProfile 'Documents\Codex'
        }
        'Temporales de Claude' { Join-Path $localAppData 'Temp\claude' }
        'Imagen de Winhance' { Join-Path $localAppData 'Temp\WinhanceWIM\sources' }
        'Escritorio' { [Environment]::GetFolderPath('DesktopDirectory') }
        'Copias de Suyu' {
            Get-ChildFolders $roamingAppData 'suyu.backup-*' | Select-Object -ExpandProperty FullName
        }
    }
}

function Test-LargeCandidate($file, $app, $cutoff) {
    if ($file.Attributes -band [IO.FileAttributes]::Hidden) { return $false }
    switch ($app) {

        'Salidas de Codex' { return $file.Length -ge 16MB -and $file.FullName -match '\\outputs\\' }
        'Temporales de Claude' { return $file.Length -ge 16MB -and $file.LastWriteTimeUtc -le $cutoff }
        'Imagen de Winhance' { return $file.Name -eq 'install.wim' -and $file.DirectoryName -eq (Join-Path $localAppData 'Temp\WinhanceWIM\sources') }
        'Escritorio' { return $file.Length -ge 256MB -and (Test-ScriptFolder $file.DirectoryName) }
        'Copias de Suyu' { return $file.Length -ge 64MB }
        $chosenReviewApp {
            return $file.Length -ge 64MB -and
                $file.Extension -in '.zip','.7z','.rar','.tar','.gz','.iso','.wim','.img','.bak','.mp4','.mkv','.mov','.avi','.wav','.flac','.psd','.blend','.pdf','.tif','.tiff' -and
                (Test-ScriptFolder $file.DirectoryName)
        }
    }
    return $false
}

function Get-ScanRoots($scope, $folder) {
    if ($scope -eq $largeScope) {
        foreach ($app in $reviewApps + $chosenReviewApp) {
            foreach ($path in Get-ReviewRoots $app) {
                if ($path -and [IO.Path]::GetPathRoot($path) -eq $script:driveRoot -and [IO.Directory]::Exists($path) -and (Test-SafePath $path)) {
                    [pscustomobject]@{ App = $app; Path = $path }
                }
            }
        }
        return
    }
    $apps = switch ($scope) {
        'Todas las cachés' { $allApps }
        'Aplicaciones de IA' { $aiApps }
        'Otros programas' { $programApps }
        'Caché de Windows' { $windowsApp }
        'Scripts' { 'Scripts' }
        default { $scope }
    }
    foreach ($app in $apps) {
        $paths = if ($app -eq 'Scripts') { $folder } else { Get-CacheRoots $app }
        foreach ($path in $paths) {
            if ([IO.Path]::GetPathRoot($path) -eq $script:driveRoot) { [pscustomobject]@{ App = $app; Path = $path } }
        }
    }
}
function Test-ScriptFolder($path) {
    $root = [IO.Path]::GetPathRoot($path)
    if ($root -ne $script:driveRoot) { return $false }
    $allowedRoot = if ($root -eq [IO.Path]::GetPathRoot($userProfile)) {
        [IO.Path]::GetFullPath($userProfile).TrimEnd('\') + '\'
    } else { $root }
    if (-not $path.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $relative = $path.Substring($allowedRoot.Length)
    if (-not $relative -or $relative -match '(^|\\)(\.[^\\]+|\$[^\\]+|AppData|Windows(?:\.old)?|Program Files(?: \(x86\))?|ProgramData|System Volume Information|Recovery|WindowsApps|WpSystem|XboxGames|Games|Juegos(?: Port)?|Emuladores|Steam(?:Library|Apps)?|Epic Games|node_modules|venv|__pycache__)(\\|$)') { return $false }
    if (-not (Test-SafePath $path)) { return $false }

    for ($part = $path; $part.Length -ge $allowedRoot.Length; $part = [IO.Path]::GetDirectoryName($part)) {
        if ($part -eq $root) { break }
        $attributes = [IO.File]::GetAttributes($part)
        if ($attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) { return $false }
        if (Test-Path -LiteralPath (Join-Path $part '.git')) { return $false }
    }
    return $true
}

function Get-Candidates($root, $app, $cutoff) {
    if (-not (Test-SafePath $root)) { return }
    if ($app -eq 'Temporales de Claude') { $cutoff = [DateTime]::UtcNow.AddDays(-3) }
    if ($app -in $windowsApp,'NVIDIA · sombreadores','Eden · sombreadores') {
        $cutoff = [DateTime]::UtcNow.AddDays(-7)
    }
    $largeFiles = $app -in ($reviewApps + $chosenReviewApp)
    $oldCache = $app -in $windowsApp,'NVIDIA · sombreadores','Eden · sombreadores'
    $folders = New-Object 'System.Collections.Generic.Stack[string]'
    $folders.Push($root)
    while ($folders.Count) {
        $folder = $folders.Pop()
        if ($app -in 'Scripts','Escritorio',$chosenReviewApp -and -not (Test-ScriptFolder $folder)) { continue }
        foreach ($entry in Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue) {
            if ($entry.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::System)) { continue }
            if ($entry.PSIsContainer) {
                $folders.Push($entry.FullName)
                continue
            }
            if ($app -eq 'Scripts') {
                if ($entry.Attributes -band [IO.FileAttributes]::Hidden) { continue }
                if ($entry.Extension -notin '.ps1','.bat','.cmd','.py','.js','.mjs','.ts','.sh','.vbs','.rb','.ahk','.lua') { continue }
                if ($entry.LastWriteTimeUtc -gt $cutoff) { continue }
            }
            if ($oldCache -and $entry.LastWriteTimeUtc -gt $cutoff) { continue }
            if ($largeFiles -and -not (Test-LargeCandidate $entry $app $cutoff)) { continue }
            [pscustomobject]@{
                App = $app
                Path = $entry.FullName
                Length = $entry.Length
                Modified = $entry.LastWriteTimeUtc
                Created = $entry.CreationTimeUtc
            }
        }
    }
}

$logFolder = Join-Path $localAppData 'LimpiadorIA'
$cleanupLogPath = Join-Path $logFolder 'registro-limpieza.log'

function Open-CleanupLog {
    if (-not (Test-SafePath $localAppData)) { throw 'La ubicación del registro no está disponible.' }
    [void][IO.Directory]::CreateDirectory($logFolder)
    if (-not (Test-SafePath $logFolder) -or
        ((Test-Path -LiteralPath $cleanupLogPath) -and -not (Test-SafePath $cleanupLogPath))) {
        throw 'La ubicación del registro está protegida.'
    }
    $stream = [IO.File]::Open($cleanupLogPath, 'Append', 'Write', 'Read')
    try {
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($true))
        $writer.AutoFlush = $true
        return $writer
    } catch {
        $stream.Dispose()
        throw
    }
}

function Write-CleanupLog($writer, $action, $sourceName, [long]$bytes, $detail) {
    $stamp = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz')
    $writer.WriteLine("$stamp | $action | $sourceName | $bytes bytes | $detail")
}

function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return '{0:N2} GB' -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return '{0:N2} MB' -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return '{0:N1} KB' -f ($bytes / 1KB) }
    return "$bytes B"
}

if ($Diagnostico) {
    foreach ($app in $allApps) {
        $roots = @(Get-CacheRoots $app)
        $files = @(foreach ($root in $roots) { Get-Candidates $root $app })
        [pscustomobject]@{
            Aplicacion = $app
            Carpetas = $roots.Count
            Archivos = $files.Count
            Tamano = Format-Size (($files | Measure-Object Length -Sum).Sum)
        }
    }
    return
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Get-Color($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }

$ink = Get-Color '#142A32'
$muted = Get-Color '#4E6670'
$surface = Get-Color '#FFFFFF'
$background = Get-Color '#EFF5F4'
$border = Get-Color '#D4E1DF'
$accent = Get-Color '#0B6658'

$form = New-Object Windows.Forms.Form
$form.Text = 'Limpiador de IA'
if ($launcherIcon) { $form.Icon = $launcherIcon }
$form.ClientSize = New-Object Drawing.Size(1160, 740)
$form.MinimumSize = New-Object Drawing.Size(660, 470)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.ForeColor = $ink
$form.BackColor = $background
$form.AutoScaleMode = 'Dpi'

$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Padding = New-Object Windows.Forms.Padding(24)
$layout.ColumnCount = 1
$layout.RowCount = 7
foreach ($height in 108,76,65,-1,62,0,32) {
    if ($height -ge 0) { $style = New-Object Windows.Forms.RowStyle('Absolute', $height) }
    else { $style = New-Object Windows.Forms.RowStyle('Percent', 100) }
    [void]$layout.RowStyles.Add($style)
}
$form.Controls.Add($layout)

$banner = New-Object Windows.Forms.Panel
$banner.Dock = 'Fill'
$banner.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
$banner.BackColor = Get-Color '#173B3B'
$layout.Controls.Add($banner, 0, 0)

$heading = New-Object Windows.Forms.Label
$heading.Text = 'Limpiador de IA'
$heading.Font = New-Object Drawing.Font('Segoe UI Semibold', 25)
$heading.ForeColor = $surface
$heading.AutoSize = $false
$banner.Controls.Add($heading)

$subtitle = New-Object Windows.Forms.Label
$subtitle.Text = 'Revisá el espacio de tus discos y elegí qué archivos limpiar.'
$subtitle.ForeColor = Get-Color '#D0E7DF'
$subtitle.AutoSize = $false
$banner.Controls.Add($subtitle)

$filters = New-Object Windows.Forms.FlowLayoutPanel
$filters.Dock = 'Fill'
$filters.WrapContents = $true
$filters.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
$filters.Padding = New-Object Windows.Forms.Padding(12, 6, 12, 4)
$filters.BackColor = $surface
$layout.Controls.Add($filters, 0, 2)

$driveLabel = New-Object Windows.Forms.Label
$driveLabel.Text = 'Unidad'
$driveLabel.AutoSize = $true
$driveLabel.Margin = New-Object Windows.Forms.Padding(4, 9, 8, 0)
$filters.Controls.Add($driveLabel)
$drivePicker = New-Object Windows.Forms.ComboBox
$drivePicker.DropDownStyle = 'DropDownList'
$drivePicker.FlatStyle = 'Flat'
$drivePicker.Width = 64
$drivePicker.Margin = New-Object Windows.Forms.Padding(0, 7, 12, 0)
$drivePicker.Items.AddRange([object[]]@($driveRoots | ForEach-Object { $_.TrimEnd('\') }))
$drivePicker.SelectedItem = $script:driveRoot.TrimEnd('\')
$filters.Controls.Add($drivePicker)

$origin = New-Object Windows.Forms.Label
$origin.Text = 'Origen'
$origin.AutoSize = $true
$origin.Margin = New-Object Windows.Forms.Padding(4, 9, 8, 0)
$filters.Controls.Add($origin)

$source = New-Object Windows.Forms.ComboBox
$source.DropDownStyle = 'DropDownList'
$source.FlatStyle = 'Flat'
$source.DrawMode = 'OwnerDrawFixed'
$drawPickerItem = {
    param($sender, $eventArgs)
    if ($eventArgs.Index -lt 0 -or -not $script:theme) { return }
    $selected = $eventArgs.State -band [Windows.Forms.DrawItemState]::Selected
    $color = if ($selected) { $script:theme.Header } else { $script:theme.Surface }
    $brush = New-Object Drawing.SolidBrush($color)
    try { $eventArgs.Graphics.FillRectangle($brush, $eventArgs.Bounds) }
    finally { $brush.Dispose() }
    [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, [string]$sender.Items[$eventArgs.Index], $sender.Font, $eventArgs.Bounds, $script:theme.Ink, [Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis')
    $eventArgs.DrawFocusRectangle()
}
$source.Add_DrawItem($drawPickerItem)
$drivePicker.DrawMode = 'OwnerDrawFixed'
$drivePicker.Add_DrawItem($drawPickerItem)
$source.BackColor = $background
$source.ForeColor = $ink
$source.Margin = New-Object Windows.Forms.Padding(0, 7, 12, 0)
$source.Width = 175
$source.Items.AddRange(@('Todas las cachés','Aplicaciones de IA','Otros programas','Caché de Windows',$usageScope,$largeScope,$binScope,'Scripts') + $aiApps + $programApps)
$source.SelectedIndex = 0
$filters.Controls.Add($source)

function Add-Button($parent, $title, [switch]$primary) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $title
    $button.AutoSize = $true
    $button.MinimumSize = New-Object Drawing.Size(88, 34)
    $button.Padding = New-Object Windows.Forms.Padding(10, 0, 10, 0)
    $button.Margin = New-Object Windows.Forms.Padding(0, 3, 8, 0)
    $button.FlatStyle = 'Flat'
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    $button.FlatAppearance.BorderColor = $border
    $button.BackColor = $surface
    $button.ForeColor = $ink
    if ($primary) {
        $button.FlatAppearance.BorderSize = 0
        $button.BackColor = $accent
        $button.ForeColor = $surface
    }
    $parent.Controls.Add($button)
    return $button
}

$scan = Add-Button $filters 'Analizar' -Primary
$choose = Add-Button $filters 'Elegir carpeta'
$ageFilter = New-Object Windows.Forms.FlowLayoutPanel
$ageFilter.WrapContents = $false
$ageFilter.AutoSize = $true
$ageFilter.AutoSizeMode = 'GrowAndShrink'
$ageFilter.Margin = New-Object Windows.Forms.Padding(0)
$filters.Controls.Add($ageFilter)
$days = New-Object Windows.Forms.NumericUpDown
$days.Minimum = 1
$days.Maximum = 3650
$days.Value = 90
$days.Width = 65
$days.Margin = New-Object Windows.Forms.Padding(6, 7, 0, 0)
$ageFilter.Controls.Add($days)
$ageLabel = New-Object Windows.Forms.Label
$ageLabel.Text = 'días sin modificar'
$ageLabel.AutoSize = $true
$ageLabel.ForeColor = $muted
$ageLabel.Margin = New-Object Windows.Forms.Padding(8, 9, 0, 0)
$ageFilter.Controls.Add($ageLabel)
$script:scriptFolder = $null

$list = New-Object Windows.Forms.ListView
$list.Dock = 'Fill'
$list.Margin = New-Object Windows.Forms.Padding(0)
$list.BackColor = $surface
$list.ForeColor = $ink
$list.BorderStyle = 'None'
$list.View = 'Details'
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.ShowItemToolTips = $true
[void]$list.Columns.Add('Archivo', 185)
[void]$list.Columns.Add('Origen', 145)
[void]$list.Columns.Add('Tamaño', 108)
[void]$list.Columns.Add('Modificado', 160)
[void]$list.Columns.Add('Ubicación', 480)
$layout.Controls.Add($list, 0, 3)

$actions = New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Fill'
$actions.Margin = New-Object Windows.Forms.Padding(0, 12, 0, 0)
$layout.Controls.Add($actions, 0, 4)
$clean = Add-Button $actions 'Limpiar marcados' -Primary
$selectCache = Add-Button $actions 'Marcar toda la caché'
$clear = Add-Button $actions 'Desmarcar todo'
$openBin = Add-Button $actions 'Abrir Papelera'
$emptyBin = Add-Button $actions 'Vaciar Papelera de la unidad' -Primary
$viewLog = Add-Button $actions 'Ver registro'
$status = New-Object Windows.Forms.Label
$status.Dock = 'Fill'
$status.ForeColor = $muted
$status.AutoEllipsis = $true
$layout.Controls.Add($status, 0, 6)

$progress = if ('CleanupProgressBar' -as [type]) { New-Object CleanupProgressBar } else { New-Object Windows.Forms.ProgressBar }
$progress.Dock = 'Fill'
$progress.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 5)
$progress.AccessibleName = 'Progreso de la operación'
$progress.Visible = $false
$layout.Controls.Add($progress, 0, 5)
$script:working = $false

function Start-Progress($message, [int]$total = 0) {
    $script:working = $true
    if ('WindowAppearance' -as [type]) { $script:workInputGuard = [WindowAppearance]::GuardWorkInput($form.Handle) }
    else { $filters.Enabled = $actions.Enabled = $themeButton.Enabled = $list.Enabled = $false }
    $layout.RowStyles[5].Height = [Math]::Max(22, $form.Font.Height)
    Resize-Content
    $status.Text = $message
    if ($progress -is [Windows.Forms.ProgressBar]) {
        $progress.Maximum = [Math]::Max(1, $total)
        $progress.Value = 0
        $progress.Style = if ($total -gt 0) { 'Continuous' } else { 'Marquee' }
    } else {
        $progress.Begin($total)
    }
    $progress.Visible = $true
    $form.Refresh()
}

function Stop-Progress {
    $progress.Visible = $false
    if ($progress -isnot [Windows.Forms.ProgressBar]) { $progress.End() }
    $layout.RowStyles[5].Height = 0
    $script:working = $false
    if ($script:workInputGuard) {
        [Windows.Forms.Application]::RemoveMessageFilter($script:workInputGuard)
        $script:workInputGuard = $null
    } else {
        $filters.Enabled = $actions.Enabled = $themeButton.Enabled = $list.Enabled = $true
    }
    Resize-Content
}

function Show-ThemedDialog($title, $message, [switch]$confirm) {
    $dialog = New-Object Windows.Forms.Form
    try {
        $t = $script:theme
        $dialog.Text = $title
        $dialog.Font = $form.Font
        $dialog.BackColor = $t.Surface
        $dialog.ForeColor = $t.Ink
        $dialog.FormBorderStyle = 'FixedDialog'
        $dialog.StartPosition = 'CenterParent'
        $dialog.MinimizeBox = $dialog.MaximizeBox = $dialog.ShowInTaskbar = $false
        if ($form.Icon) { $dialog.Icon = $form.Icon }

        $padding = [Math]::Max(18, $dialog.Font.Height)
        $width = [Math]::Min(600, [Windows.Forms.Screen]::FromControl($form).WorkingArea.Width - 60)
        $body = New-Object Windows.Forms.Label
        $body.Text = $message
        $body.UseMnemonic = $false
        $body.AutoSize = $true
        $body.MaximumSize = [Drawing.Size]::new($width - 2 * $padding, 0)
        $body.Location = [Drawing.Point]::new($padding, $padding)
        $dialog.Controls.Add($body)

        $buttons = New-Object Windows.Forms.FlowLayoutPanel
        $buttons.FlowDirection = 'RightToLeft'
        $buttons.WrapContents = $false
        $buttons.Padding = [Windows.Forms.Padding]::new(0, 0, ($padding - 8), 0)
        $buttons.Top = $body.Bottom + $padding
        $buttons.Width = $width
        $dialog.Controls.Add($buttons)
        $cancel = Add-Button $buttons $(if ($confirm) { 'Cancelar' } else { 'Aceptar' })
        $cancel.DialogResult = if ($confirm) { 'Cancel' } else { 'OK' }
        $dialog.AcceptButton = $dialog.CancelButton = $cancel
        $defaultButton = $cancel
        if ($confirm) {
            $yes = Add-Button $buttons 'Confirmar'
            $yes.DialogResult = 'Yes'
        }
        foreach ($button in $buttons.Controls) {
            $button.BackColor = $t.Surface
            $button.ForeColor = $t.Ink
            $button.FlatAppearance.BorderColor = $t.Border
            $button.FlatAppearance.MouseOverBackColor = $t.Hover
        }
        if (-not $confirm) {
            $defaultButton.BackColor = $t.Accent
            $defaultButton.ForeColor = $t.OnAccent
        }
        $buttons.Height = $buttons.GetPreferredSize([Drawing.Size]::new($width, 0)).Height
        $dialog.ClientSize = [Drawing.Size]::new($width, $buttons.Bottom + $padding)
        $dialog.ActiveControl = $defaultButton
        if ('WindowAppearance' -as [type]) { [WindowAppearance]::SetDarkTitleBar($dialog.Handle, $script:darkMode) }
        return $dialog.ShowDialog($form)
    } finally { $dialog.Dispose() }
}
function Show-CleanupResult($label, [int]$completed, [int]$pending, [long]$size, $details) {
    $text = "${label}: $completed ($(Format-Size $size))`nPendientes: $pending"
    if ($details) { $text += "`n`n$details" }

    [void](Show-ThemedDialog 'Resultado de la limpieza' $text)
}
$metrics = New-Object Windows.Forms.TableLayoutPanel
$metrics.Dock = 'Fill'
$metrics.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 12)
$metrics.ColumnCount = 3
$metrics.RowCount = 1
for ($i = 0; $i -lt 3; $i++) {
    [void]$metrics.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 33.3333)))
}
$layout.Controls.Add($metrics, 0, 1)

function Add-Metric($column, $title) {
    $card = New-Object Windows.Forms.Panel
    $card.Dock = 'Fill'
    $card.Margin = New-Object Windows.Forms.Padding(0, 0, (12 * [int]($column -lt 2)), 0)
    $metrics.Controls.Add($card, $column, 0)
    $label = New-Object Windows.Forms.Label
    $label.Text = $title
    $label.AutoSize = $true
    $label.Location = New-Object Drawing.Point(14, 7)
    $card.Controls.Add($label)
    $value = New-Object Windows.Forms.Label
    $value.Text = '—'
    $value.AutoSize = $true
    $value.Location = New-Object Drawing.Point(12, 27)
    $value.Font = New-Object Drawing.Font('Segoe UI Semibold', 15)
    $card.Controls.Add($value)
    [pscustomobject]@{ Panel = $card; Caption = $label; Value = $value }
}

$foundMetric = Add-Metric 0 'Tamaño analizado'
$markedMetric = Add-Metric 1 'Tamaño marcado'
$freeMetric = Add-Metric 2 'Espacio libre'
$foundValue = $foundMetric.Value
$markedValue = $markedMetric.Value
$freeValue = $freeMetric.Value

$themeButton = Add-Button $banner 'Modo oscuro'
$themeButton.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$themeButton.AutoSize = $false
$themeButton.Size = New-Object Drawing.Size(132, 36)
$themeButton.Left = $banner.ClientSize.Width - $themeButton.Width - 18
$themeButton.Top = 18
$themeButton.AccessibleName = 'Cambiar tema de la aplicación'

$light = @{
    Ink = '#18313B'; Muted = '#506973'; Surface = '#FFFFFF'; Background = '#ECF2F3'
    Stripe = '#F4F8F8'; Border = '#C8D7DA'; Accent = '#086759'; OnAccent = '#FFFFFF'
    Banner = '#173B3B'; Header = '#DBEAE8'; Hover = '#D7E8E5'
}
$dark = @{
    Ink = '#E7F1F2'; Muted = '#B3C6CB'; Surface = '#17262D'; Background = '#0D171E'
    Stripe = '#1C3038'; Border = '#38515A'; Accent = '#84E3C4'; OnAccent = '#0D3028'
    Banner = '#17393B'; Header = '#283F47'; Hover = '#294651'
}
foreach ($palette in $light,$dark) {
    foreach ($key in @($palette.Keys)) { $palette[$key] = Get-Color $palette[$key] }
}

function Set-Theme {
    $script:theme = if ($script:darkMode) { $dark } else { $light }
    $t = $script:theme
    $form.BackColor = $t.Background
    $form.ForeColor = $t.Ink
    $progress.BackColor = $t.Border
    $progress.ForeColor = $t.Accent
    $banner.BackColor = $t.Banner
    $filters.BackColor = $t.Surface
    $drivePicker.BackColor = $source.BackColor = $days.BackColor = $t.Background
    $drivePicker.ForeColor = $driveLabel.ForeColor = $source.ForeColor = $days.ForeColor = $origin.ForeColor = $t.Ink
    $ageLabel.ForeColor = $status.ForeColor = $t.Muted
    foreach ($metric in $foundMetric,$markedMetric,$freeMetric) {
        $metric.Panel.BackColor = $t.Surface
        $metric.Caption.ForeColor = $t.Muted
        $metric.Value.ForeColor = $t.Ink
    }
    foreach ($button in $scan,$clean,$choose,$selectCache,$clear,$themeButton,$openBin,$emptyBin,$viewLog) {
        $primary = $button -in $scan,$clean,$emptyBin -and $button.Enabled
        $button.BackColor = if ($primary) { $t.Accent } else { $t.Surface }
        $button.ForeColor = if ($primary) { $t.OnAccent } else { $t.Ink }
        $button.FlatAppearance.BorderColor = $t.Border
        $button.FlatAppearance.MouseOverBackColor = if ($primary) { $t.Accent } else { $t.Hover }
    }
    $themeButton.Text = if ($script:darkMode) { 'Modo claro' } else { 'Modo oscuro' }
    $list.BackColor = $t.Surface
    $list.ForeColor = $t.Ink
    $list.BeginUpdate()
    try {
        foreach ($row in $list.Items) {
            $row.BackColor = if ($row.Index % 2) { $t.Stripe } else { $t.Surface }
        }
    } finally { $list.EndUpdate() }
    $list.Invalidate()
    $source.Invalidate()
    $drivePicker.Invalidate()
    if ('WindowAppearance' -as [type]) { [WindowAppearance]::SetDarkTitleBar($form.Handle, $script:darkMode) }
}

$list.OwnerDraw = $true
$list.Add_DrawColumnHeader({
    param($sender, $eventArgs)
    $brush = New-Object Drawing.SolidBrush($script:theme.Header)
    try { $eventArgs.Graphics.FillRectangle($brush, $eventArgs.Bounds) }
    finally { $brush.Dispose() }
    $bounds = $eventArgs.Bounds
    $bounds.X += 7
    $bounds.Width = [Math]::Max(0, $bounds.Width - 7)
    [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics, $eventArgs.Header.Text, $sender.Font, $bounds, $script:theme.Ink, [Windows.Forms.TextFormatFlags]'Left,VerticalCenter,EndEllipsis')
})
$list.Add_DrawItem({ param($sender, $eventArgs) $eventArgs.DrawDefault = $true })
$list.Add_DrawSubItem({ param($sender, $eventArgs) $eventArgs.DrawDefault = $true })
$themeButton.Add_Click({ $script:darkMode = -not $script:darkMode; Set-Theme })
$script:darkMode = $false

function Resize-Content {
    if ($form.WindowState -eq 'Minimized' -or $script:adjustingLayout) { return }
    $width = $layout.ClientSize.Width - $layout.Padding.Horizontal
    if ($width -le 0) { return }
    $script:adjustingLayout = $true
    try {
        $padding = [Math]::Max(14, $form.Font.Height + 2)
        $gap = [Math]::Max(5, [int]($form.Font.Height * 0.35))
        $buttonTextSize = [Windows.Forms.TextRenderer]::MeasureText('Modo oscuro', $themeButton.Font)
        $buttonWidth = [Math]::Max(132, $buttonTextSize.Width + $themeButton.Padding.Horizontal + 8)
        $buttonHeight = [Math]::Max(36, $buttonTextSize.Height + 10)
        $buttonLeft = $width - $padding - $buttonWidth
        $themeButton.SetBounds($buttonLeft, $padding, $buttonWidth, $buttonHeight)

        $headingWidth = [Math]::Max(1, $buttonLeft - $padding - $gap)
        $headingHeight = $heading.GetPreferredSize([Drawing.Size]::new($headingWidth, 0)).Height + 3
        $heading.SetBounds($padding, $padding, $headingWidth, $headingHeight)
        $subtitleTop = [Math]::Max($heading.Bottom, $themeButton.Bottom) + $gap
        $subtitleWidth = [Math]::Max(1, $width - 2 * $padding)
        $subtitleHeight = $subtitle.GetPreferredSize([Drawing.Size]::new($subtitleWidth, 0)).Height + 3
        $subtitle.SetBounds($padding, $subtitleTop, $subtitleWidth, $subtitleHeight)
        $layout.RowStyles[0].Height = $subtitle.Bottom + $padding + $banner.Margin.Vertical

        $toolbarHeight = $filters.GetPreferredSize([Drawing.Size]::new($width, 0)).Height
        $layout.RowStyles[2].Height = [Math]::Max(65, $toolbarHeight + $filters.Margin.Vertical + 5)
        $fixedHeight = $layout.Padding.Vertical + ($form.Height - $form.ClientSize.Height)
        foreach ($index in 0,1,2,4,5,6) { $fixedHeight += $layout.RowStyles[$index].Height }
        $minimumHeight = [Math]::Max(470, [int]($fixedHeight + 95))
        $screenHeight = [Windows.Forms.Screen]::FromControl($form).WorkingArea.Height
        $form.MinimumSize = [Drawing.Size]::new($form.MinimumSize.Width, [Math]::Min($minimumHeight, $screenHeight))

        $usable = $list.ClientSize.Width - [Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 4
        $list.Columns[0].Width = [Math]::Max(135, [int]($usable * 0.19))
        $list.Columns[1].Width = [Math]::Max(92, [int]($usable * 0.13))
        $list.Columns[2].Width = [Math]::Max(80, [int]($usable * 0.10))
        $list.Columns[3].Width = [Math]::Max(116, [int]($usable * 0.15))
        $fixedWidth = $list.Columns[0].Width + $list.Columns[1].Width + $list.Columns[2].Width + $list.Columns[3].Width
        $list.Columns[4].Width = [Math]::Max(130, $usable - $fixedWidth)
    } finally {
        $script:adjustingLayout = $false
    }
}
$windowSettingsKey = 'Software\LimpiadorIA\Ventana'
$script:lastWindowState = [Windows.Forms.FormWindowState]::Normal

function Restore-WindowSize {
    try {
        $settings = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($windowSettingsKey)
        if (-not $settings) { return }
        try {
            $script:darkMode = $settings.GetValue('TemaOscuro', 0) -eq 1
            $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $savedWidth = [int]$settings.GetValue('Ancho', $form.Width)
            $savedHeight = [int]$settings.GetValue('Alto', $form.Height)
            $width = [Math]::Max($form.MinimumSize.Width, [Math]::Min($savedWidth, $area.Width))
            $height = [Math]::Max($form.MinimumSize.Height, [Math]::Min($savedHeight, $area.Height))
            $form.Size = New-Object Drawing.Size($width, $height)
            if ([int]$settings.GetValue('Maximizada', 0) -eq 1) {
                $script:lastWindowState = [Windows.Forms.FormWindowState]::Maximized
                $form.WindowState = $script:lastWindowState
            }
        } finally { $settings.Dispose() }
    } catch {
        # Keep the usable default when the preference is unavailable.
    }
}

function Save-WindowSize {
    try {
        $size = if ($form.WindowState -eq 'Normal') { $form.Size } else { $form.RestoreBounds.Size }
        if ($size.Width -le 0 -or $size.Height -le 0) { return }
        $settings = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($windowSettingsKey)
        try {
            $settings.SetValue('Ancho', $size.Width, 'DWord')
            $settings.SetValue('Alto', $size.Height, 'DWord')
            $settings.SetValue('TemaOscuro', [int]$script:darkMode, 'DWord')
            $settings.SetValue('Maximizada', [int]($script:lastWindowState -eq 'Maximized'), 'DWord')
        } finally { $settings.Dispose() }
    } catch {
        # A preference write failure must not prevent closing the app.
    }
}

$form.Add_Resize({
    if ($form.WindowState -ne 'Minimized') { $script:lastWindowState = $form.WindowState }
    Resize-Content
})
$form.Add_Shown({ Resize-Content })
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:working) { $eventArgs.Cancel = $true }
    else { Save-WindowSize }
})
function Update-FreeSpace {
    $freeMetric.Caption.Text = "Libre en $($script:driveRoot.TrimEnd('\'))"
    try { $freeValue.Text = Format-Size ([IO.DriveInfo]::new($script:driveRoot).AvailableFreeSpace) }
    catch { $freeValue.Text = '—' }
}

function Update-Status {
    $marked = 0L
    if ($list.CheckBoxes) { foreach ($row in $list.CheckedItems) { $marked += $row.Tag.Length } }
    $markedValue.Text = Format-Size $marked

    Update-FreeSpace
    $status.Text = "$($list.Items.Count) archivos encontrados · $($list.CheckedItems.Count) marcados"
    $clean.Enabled = $list.CheckBoxes -and $list.CheckedItems.Count -gt 0
    $clean.BackColor = if ($clean.Enabled) { $script:theme.Accent } else { $script:theme.Surface }
    $clean.ForeColor = if ($clean.Enabled) { $script:theme.OnAccent } else { $script:theme.Muted }
}

function Reset-Results {
    $list.Items.Clear()
    $foundMetric.Caption.Text = 'Tamaño analizado'
    $foundValue.Text = '—'
    $scriptsMode = $source.SelectedItem -eq 'Scripts'
    $ageFilter.Visible = $scriptsMode
    $binMode = $source.SelectedItem -eq $binScope
    $reviewMode = $source.SelectedItem -eq $largeScope
    $usageMode = $source.SelectedItem -eq $usageScope
    $choose.Visible = $scriptsMode -or $reviewMode
    $list.CheckBoxes = -not ($usageMode -or $binMode)
    $list.Columns[1].Text = if ($usageMode) { 'Tipo' } else { 'Origen' }
    $selectCache.Visible = -not ($scriptsMode -or $reviewMode -or $binMode -or $usageMode)
    $openBin.Visible = $emptyBin.Visible = $binMode
    $emptyBin.Enabled = $false
    $emptyBin.Text = "Vaciar Papelera de $($script:driveRoot.TrimEnd('\'))"
    $clean.Visible = $clear.Visible = -not ($binMode -or $usageMode)
    Resize-Content
    $clean.Text = if ($scriptsMode -or $reviewMode) { 'Enviar marcados a la Papelera' } else { 'Borrar caché marcada' }
    Update-Status
    $status.Text = if ($scriptsMode -and $script:scriptFolder) { $script:scriptFolder }
        elseif ($reviewMode -and $script:largeFolder) { $script:largeFolder }
        elseif ($reviewMode) { 'Analizá las ubicaciones conocidas o elegí una carpeta personal.' }
        elseif ($usageMode) { 'Analizá la unidad para ver qué carpetas ocupan más espacio.' }
        else { 'Elegí un origen y hacé clic en Analizar.' }
}
Set-Theme
Reset-Results
$source.Add_SelectedIndexChanged({ Reset-Results })
$drivePicker.Add_SelectedIndexChanged({
    if (-not $drivePicker.SelectedItem) { return }
    $script:driveRoot = "$($drivePicker.SelectedItem)\"
    $script:scriptFolder = $null
    $script:largeFolder = $null
    $source.SelectedItem = $usageScope
    Reset-Results
})
$days.Add_ValueChanged({ Reset-Results })
$choose.Add_Click({
    $picker = New-Object Windows.Forms.FolderBrowserDialog
    $scriptsMode = $source.SelectedItem -eq 'Scripts'
    $picker.Description = if ($scriptsMode) { 'Elegí una carpeta con tus scripts en la unidad seleccionada.' }
                          else { 'Elegí una carpeta personal para revisar archivos grandes en la unidad seleccionada.' }
    $picker.SelectedPath = if ($script:driveRoot -eq [IO.Path]::GetPathRoot($userProfile)) { $userProfile } else { $script:driveRoot }
    try {
        if ($picker.ShowDialog($form) -ne 'OK') { return }
        if (-not (Test-ScriptFolder $picker.SelectedPath)) {
            [void][Windows.Forms.MessageBox]::Show($form, 'Elegí una carpeta personal de la unidad seleccionada, fuera de carpetas protegidas y repositorios Git.', 'Carpeta excluida')
            return
        }
        if ($scriptsMode) { $script:scriptFolder = $picker.SelectedPath }
        else { $script:largeFolder = $picker.SelectedPath }
        Reset-Results
        $status.Text = $picker.SelectedPath
    } finally { $picker.Dispose() }
})
function Show-RecycleBinSize {
    $emptyBin.Enabled = $false
    $volume = $script:driveRoot.TrimEnd('\')
    try {
        if (-not ('DriveRecycleBin' -as [type])) { throw 'Abrí el limpiador desde el ejecutable.' }
        $info = [DriveRecycleBin]::Query($script:driveRoot)
        $foundValue.Text = Format-Size $info.Bytes

    Update-FreeSpace
        $emptyBin.Enabled = $info.Items -gt 0
        $status.Text = "$($info.Items) elementos en la Papelera de $volume. Podés revisarlos en Windows antes de vaciarla."
    } catch {
        $status.Text = "No se pudo consultar la Papelera de la unidad. $($_.Exception.GetBaseException().Message)"
    }
}

$viewLog.Add_Click({
    if (-not [IO.File]::Exists($cleanupLogPath)) {
        $status.Text = 'Todavía no hay limpiezas registradas.'
        return
    }
    try {
        if (-not (Test-SafePath $cleanupLogPath)) { throw 'La ubicación del registro está protegida.' }
        $notepad = Join-Path ([Environment]::SystemDirectory) 'notepad.exe'
        Start-Process -FilePath $notepad -ArgumentList ('"{0}"' -f $cleanupLogPath)
    } catch {
        [void][Windows.Forms.MessageBox]::Show($form, $_.Exception.GetBaseException().Message, 'Registro de limpieza')
    }
})

$openBin.Add_Click({
    $explorer = Join-Path ([IO.Directory]::GetParent([Environment]::SystemDirectory).FullName) 'explorer.exe'
    Start-Process -FilePath $explorer -ArgumentList 'shell:RecycleBinFolder'
})

$emptyBin.Add_Click({
    if ($script:working -or $source.SelectedItem -ne $binScope -or -not $emptyBin.Enabled) { return }
    $volume = $script:driveRoot.TrimEnd('\')
    $message = "¿Eliminar definitivamente todos los elementos de la Papelera de $volume?"
    if ((Show-ThemedDialog "Vaciar Papelera de $volume" $message -Confirm) -ne 'Yes') { return }

    $before = $after = $null
    $problem = $null
    try {
        $before = [DriveRecycleBin]::Query($script:driveRoot)
        if ($before.Items -le 0) { return }
        $writer = Open-CleanupLog
        try {
            Start-Progress "Vaciando la Papelera de $volume…"
            try { [DriveRecycleBin]::Empty($form.Handle, $script:driveRoot) }
            catch { $problem = $_.Exception.GetBaseException().Message }
            $after = [DriveRecycleBin]::Query($script:driveRoot)
            $removed = [Math]::Max(0, $before.Items - $after.Items)
            $removedBytes = [Math]::Max(0, $before.Bytes - $after.Bytes)
            if ($removed) {
                Write-CleanupLog $writer 'Eliminación definitiva' "Papelera de $volume" $removedBytes "$removed elementos retirados"
            }
        } finally { $writer.Dispose() }
    } catch { $problem = $_.Exception.GetBaseException().Message }
    finally {
        if ($script:working) { Stop-Progress }
        Show-RecycleBinSize
    }

    if ($after) {
        Show-CleanupResult 'Elementos eliminados' $removed $after.Items $removedBytes $problem
    } elseif ($problem) {
        [void][Windows.Forms.MessageBox]::Show($form, $problem, "Papelera de $volume", 'OK', 'Warning')
    }
})
$usageTimer = New-Object Windows.Forms.Timer
$usageTimer.Interval = 125
$script:usageTask = $null
$form.Add_FormClosed({ $usageTimer.Dispose() })

$usageTimer.Add_Tick({
    if (-not $script:usageTask.IsCompleted) { return }
    $usageTimer.Stop()
    try {
        $usage = $script:usageTask.GetAwaiter().GetResult()
        $list.BeginUpdate()
        try {
            foreach ($entry in $usage.Entries) {
                $row = New-Object Windows.Forms.ListViewItem([IO.Path]::GetFileName($entry.Path))
                if ($list.Items.Count % 2 -eq 1) { $row.BackColor = $script:theme.Stripe }
                $row.ToolTipText = $entry.Path
                $kind = if ($entry.Directory) { 'Carpeta' } else { 'Archivo' }
                [void]$row.SubItems.Add($kind)
                [void]$row.SubItems.Add((Format-Size $entry.Bytes))
                [void]$row.SubItems.Add('—')
                [void]$row.SubItems.Add($entry.Path)
                [void]$list.Items.Add($row)
            }
        } finally { $list.EndUpdate() }
        $foundMetric.Caption.Text = 'Ocupado en la unidad'
        $foundValue.Text = Format-Size $usage.Used
        Update-FreeSpace
        $status.Text = 'Tamaños aproximados por carpeta. Elegí «Archivos grandes» o «Scripts» para limpiar.'
        if ($usage.Skipped) { $status.Text += " Se omitieron $($usage.Skipped) enlaces o ubicaciones inaccesibles." }
    } catch {
        $status.Text = "No se pudo medir la unidad. $($_.Exception.GetBaseException().Message)"
    } finally {
        $script:usageTask = $null
        Stop-Progress
    }
})

function Start-UsageScan {
    try {
        if (-not ('DriveUsage' -as [type])) { throw 'Abrí el limpiador desde el ejecutable.' }
        $script:usageTask = [DriveUsage]::ScanAsync($script:driveRoot)
        Start-Progress "Midiendo las carpetas de $($script:driveRoot.TrimEnd('\'))…"
        $usageTimer.Start()
    } catch {
        $status.Text = "No se pudo iniciar el análisis. $($_.Exception.GetBaseException().Message)"
    }
}
function Invoke-Scan {
    if ($script:working) { return }
    Reset-Results
    $app = [string]$source.SelectedItem
    if ($app -eq $binScope) { Show-RecycleBinSize; return }
    if ($app -eq $usageScope) { Start-UsageScan; return }
    if ($app -eq 'Scripts' -and -not $script:scriptFolder) {
        $status.Text = 'Primero elegí una carpeta personal.'
        return
    }
    $form.UseWaitCursor = $true
    Start-Progress 'Analizando…'
    $script:bulk = $true
    $list.BeginUpdate()
    try {
        $roots = @(Get-ScanRoots $app $script:scriptFolder)
        $cutoff = [DateTime]::UtcNow.AddDays(-[double]$days.Value)
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $total = 0L
        $rows = New-Object 'System.Collections.Generic.List[Windows.Forms.ListViewItem]'
        foreach ($root in $roots) {
            $status.Text = "Analizando $($root.App)…"
            [Windows.Forms.Application]::DoEvents()
            Get-Candidates $root.Path $root.App $cutoff | ForEach-Object {
                if ($seen.Add($_.Path)) {
                    $row = New-Object Windows.Forms.ListViewItem([IO.Path]::GetFileName($_.Path))
                    if ($rows.Count % 2 -eq 1) { $row.BackColor = $script:theme.Stripe }
                    $row.Tag = $_
                    $row.ToolTipText = $_.Path
                    [void]$row.SubItems.Add($_.App)
                    [void]$row.SubItems.Add((Format-Size $_.Length))
                    [void]$row.SubItems.Add($_.Modified.ToLocalTime().ToString('g'))
                    [void]$row.SubItems.Add([IO.Path]::GetDirectoryName($_.Path))
                    $rows.Add($row)
                    $total += $_.Length
                }
            }
        }
        [Windows.Forms.ListViewItem[]]$displayRows = @(if ($app -eq $largeScope) { $rows | Sort-Object { $_.Tag.Length } -Descending } else { $rows.ToArray() })
        $list.Items.AddRange([Windows.Forms.ListViewItem[]]$displayRows)
        if ($app -eq $largeScope) {
            for ($i = 0; $i -lt $list.Items.Count; $i++) {
                $list.Items[$i].BackColor = if ($i % 2) { $script:theme.Stripe } else { $script:theme.Surface }
            }
        }
        Update-Status
        $foundValue.Text = Format-Size $total
        if ($list.Items.Count -eq 0) { $status.Text = 'No se encontraron archivos para este origen.' }
    } catch {
        Reset-Results
        $status.Text = "No se pudo completar el análisis. $($_.Exception.Message)"
    } finally {
        $list.EndUpdate()
        $script:bulk = $false
        $form.UseWaitCursor = $false
        Stop-Progress
    }
}
$scan.Add_Click({ Invoke-Scan })
$list.Add_ItemChecked({ if (-not $script:bulk) { Update-Status } })

function Set-CacheSelection([bool]$checked) {
    $script:bulk = $true
    $list.BeginUpdate()
    try { foreach ($row in $list.Items) { $row.Checked = $checked } }
    finally {
        $list.EndUpdate()
        $script:bulk = $false
        Update-Status
    }
}
$selectCache.Add_Click({ if ($source.SelectedItem -notin 'Scripts',$largeScope,$binScope,$usageScope) { Set-CacheSelection $true } })
$clear.Add_Click({ Set-CacheSelection $false })

$clean.Add_Click({
    if ($script:working) { return }
    $app = [string]$source.SelectedItem
    $scriptsMode = $app -eq 'Scripts'
    $reviewMode = $app -eq $largeScope
    $recycleFiles = $scriptsMode -or $reviewMode
    $marked = @($list.CheckedItems | ForEach-Object { $_ })
    if (-not $marked.Count) { return }
    $question = if ($recycleFiles) {
        "¿Enviar $($marked.Count) archivos a la Papelera? El espacio se libera cuando los eliminás de la Papelera."
    } else {
        "¿Borrar permanentemente $($marked.Count) archivos de caché? Se omitirán los de aplicaciones abiertas."
    }
    if ((Show-ThemedDialog 'Confirmar limpieza' $question -Confirm) -ne 'Yes') { return }
    try { $writer = Open-CleanupLog }
    catch {
        [void][Windows.Forms.MessageBox]::Show($form, "No se pudo abrir el registro. $($_.Exception.GetBaseException().Message)", 'Limpieza cancelada')
        return
    }
    $logAction = if ($recycleFiles) { 'Enviado a la Papelera' } else { 'Eliminación definitiva' }
    $logError = $null
    $form.UseWaitCursor = $true
    $script:bulk = $true
    $processSnapshotTime = [DateTime]::MinValue
    $processes = @()
    $activeApps = @{}
    $blocked = @{}
    $done = 0
    $removedRows = New-Object 'System.Collections.Generic.HashSet[Windows.Forms.ListViewItem]'
    $processed = 0
    $lastUpdate = [Diagnostics.Stopwatch]::StartNew()
    Start-Progress "Procesando 0 de $($marked.Count) archivos…" $marked.Count
    $bytes = 0L
    $errors = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($row in $marked) {
            $entry = $row.Tag
            try {
                if (-not $scriptsMode) {
                    if (([DateTime]::UtcNow - $processSnapshotTime).TotalSeconds -ge 1) {
                        $processes = @(Get-Process | Select-Object -ExpandProperty ProcessName)
                        $processSnapshotTime = [DateTime]::UtcNow
                        $activeApps.Clear()
                    }
                    $pattern = $processPatterns[$entry.App]
                    if ($pattern -and -not $activeApps.ContainsKey($entry.App)) {
                        $activeApps[$entry.App] = [bool]($processes -match $pattern)
                    }
                    if ($activeApps[$entry.App]) {
                        $blocked[$entry.App] = $true
                        continue
                    }
                }
                if ([IO.Path]::GetPathRoot($entry.Path) -ne $script:driveRoot -or -not (Test-SafePath $entry.Path)) { throw 'Ruta no disponible o protegida.' }
                $file = Get-Item -LiteralPath $entry.Path -Force
                if ($file.PSIsContainer -or $file.Attributes -band [IO.FileAttributes]::System -or
                    $file.Length -ne $entry.Length -or $file.LastWriteTimeUtc -ne $entry.Modified -or
                    $file.CreationTimeUtc -ne $entry.Created) { throw 'El archivo cambió desde el análisis.' }
                if ($recycleFiles) {
                    if ($scriptsMode -and ($file.Attributes -band [IO.FileAttributes]::Hidden -or -not (Test-ScriptFolder $file.DirectoryName))) {
                        throw 'El script está en una ubicación excluida.'
                    }
                    if ($reviewMode -and -not (Test-LargeCandidate $file $entry.App ([DateTime]::UtcNow.AddDays(-3)))) {
                        throw 'El archivo ya no cumple los criterios de revisión.'
                    }
                    if (-not ('DriveRecycleBin' -as [type])) { throw 'Abrí el limpiador desde el ejecutable.' }
                    $probe = [IO.File]::Open($file.FullName, 'Open', 'Read', 'Delete')
                    $probe.Dispose()
                    [DriveRecycleBin]::Recycle($form.Handle, $file.FullName)
                } else {
                    # Deny concurrent access while deleting so a cache still open is left alone.
                    $handle = [IO.File]::Open($file.FullName, 'Open', 'Read', 'Delete')
                    try { [IO.File]::Delete($file.FullName) } finally { $handle.Dispose() }
                }
                [void]$removedRows.Add($row)
                $done++
                $bytes += $entry.Length
            } catch {
                $errors.Add("$($entry.Path) — $($_.Exception.Message)")
                continue
            } finally {
                $processed++
                if ($lastUpdate.ElapsedMilliseconds -ge 90 -or $processed -eq $marked.Count) {
                    if ($progress -is [Windows.Forms.ProgressBar]) { $progress.Value = $processed }
                    else { $progress.Advance($processed) }
                    $status.Text = "Procesando $processed de $($marked.Count) archivos…"
                    $progress.Refresh()
                    $status.Refresh()
                    [Windows.Forms.Application]::DoEvents()
                    $lastUpdate.Restart()
                }
            }
            try { Write-CleanupLog $writer $logAction $entry.App $entry.Length $entry.Path }
            catch {
                $logError = "La limpieza se detuvo porque falló el registro de este archivo: $($entry.Path)"
                break
            }
        }
    } finally {
        try {
            $writer.Dispose()
            $list.BeginUpdate()
            try {
                if ($removedRows.Count -ge 64 -and $removedRows.Count -ge $list.Items.Count / 4) {
                    $remainingRows = New-Object 'System.Collections.Generic.List[Windows.Forms.ListViewItem]'
                    foreach ($row in $list.Items) {
                        if (-not $removedRows.Contains($row)) { $remainingRows.Add($row) }
                    }
                    $list.Items.Clear()
                    $list.Items.AddRange($remainingRows.ToArray())
                } else {
                    foreach ($row in $removedRows) { $list.Items.Remove($row) }
                }
            } finally { $list.EndUpdate() }
        } finally { Stop-Progress }
        $script:bulk = $false
        $form.UseWaitCursor = $false
        Update-Status
    }
    $foundValue.Text = Format-Size (($list.Items | ForEach-Object { $_.Tag.Length } | Measure-Object -Sum).Sum)
    $result = if ($recycleFiles) { 'Archivos enviados a la Papelera' } else { 'Archivos eliminados' }
    $pending = $marked.Count - $done
    $status.Text = "${result}: $done · Pendientes: $pending"
    $details = New-Object 'System.Collections.Generic.List[string]'
    if ($logError) { $details.Add($logError) }
    if ($blocked.Count) {
        $appsInUse = ($blocked.Keys | Sort-Object) -join ', '
        $details.Add("Aplicaciones abiertas: $appsInUse.")
    }
    if ($errors.Count) {
        $example = $errors[0]
        $details.Add("$($errors.Count) archivos no se pudieron limpiar. Primer caso:`n$example")
    }
    Show-CleanupResult $result $done $pending $bytes ($details -join "`n`n")
})

Restore-WindowSize
Set-Theme
Resize-Content
[void]$form.ShowDialog()
$form.Dispose()
