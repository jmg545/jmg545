<#
  alarma.ps1
  Ventana minima: escribes una hora, Enter, se envia la orden al Pixel y se cierra.

  Uso normal (desde el acceso directo):
      alarma.bat
  Uso desde consola, sin ventana (util para probar):
      powershell -NoProfile -File alarma.ps1 -Hora "10h20"
      powershell -NoProfile -File alarma.ps1 -Hora "10h20" -DryRun
#>
param(
    [string]$Hora,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Configuracion (endpoint + token). Vive fuera de este archivo y no se versiona.
# ----------------------------------------------------------------------------
function Get-Config {
    $ruta = Join-Path $PSScriptRoot 'alarma.config.ps1'
    if (-not (Test-Path $ruta)) {
        throw 'Falta alarma.config.ps1 (copia alarma.config.example.ps1 y rellenalo).'
    }
    return (& $ruta)
}

# ----------------------------------------------------------------------------
# "10h20" / "10:20" / "1020" / "15h" / "7h" / "7:45" / "10 h 20"  ->  hora+minuto
# ----------------------------------------------------------------------------
function ConvertTo-HoraMinuto {
    param([string]$Texto)

    if ($null -eq $Texto) { $Texto = '' }
    $t = ($Texto -replace '\s', '').ToLowerInvariant()
    if ($t -eq '') { throw 'Escribe una hora.' }

    $t = $t -replace '[.,;]', ':'   # tolera 10.20
    $t = $t -replace '[h:]+', ':'   # unifica separadores: 10h20 -> 10:20
    $t = $t -replace ':$', ''       # 15h -> 15

    if     ($t -match '^(\d{1,2}):(\d{1,2})$') { $h = [int]$Matches[1]; $m = [int]$Matches[2] }
    elseif ($t -match '^\d{1,2}$')             { $h = [int]$t;          $m = 0 }
    elseif ($t -match '^(\d)(\d{2})$')         { $h = [int]$Matches[1]; $m = [int]$Matches[2] }
    elseif ($t -match '^(\d{2})(\d{2})$')      { $h = [int]$Matches[1]; $m = [int]$Matches[2] }
    else   { throw "No entiendo '$Texto'. Ejemplos: 10h20, 10:20, 1020, 15h, 7h45." }

    if ($h -gt 23) { throw "Hora fuera de rango: $h (debe ser 0-23)." }
    if ($m -gt 59) { throw "Minutos fuera de rango: $m (deben ser 0-59)." }

    return @{ Hour = $h; Minute = $m }
}

# ----------------------------------------------------------------------------
# Si la hora de hoy ya ha pasado, es manana.
# ----------------------------------------------------------------------------
function Get-ProximaFecha {
    param([int]$Hour, [int]$Minute)

    $ahora    = Get-Date
    $objetivo = [datetime]::new($ahora.Year, $ahora.Month, $ahora.Day, $Hour, $Minute, 0)
    if ($objetivo -le $ahora) { $objetivo = $objetivo.AddDays(1) }
    return $objetivo
}

# ----------------------------------------------------------------------------
# Publicacion de la orden (un solo POST JSON).
# ----------------------------------------------------------------------------
function Send-Alarma {
    param([hashtable]$Cfg, [int]$Hour, [int]$Minute, [datetime]$Cuando)

    $json = ([ordered]@{
        token  = $Cfg['Token']
        hour   = $Hour
        minute = $Minute
        date   = $Cuando.ToString('yyyy-MM-dd')
    } | ConvertTo-Json -Compress)

    if ($DryRun) { return $json }

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    $headers = @{ 'Priority' = 'high' }
    if ($Cfg['AuthHeader']) { $headers['Authorization'] = $Cfg['AuthHeader'] }

    Invoke-RestMethod -Uri $Cfg['Endpoint'] -Method Post -Headers $headers `
        -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($json)) `
        -TimeoutSec 10 | Out-Null

    return $json
}

function Enviar {
    param([string]$Texto)

    $hm     = ConvertTo-HoraMinuto $Texto
    $cuando = Get-ProximaFecha -Hour $hm.Hour -Minute $hm.Minute
    $cfg    = Get-Config
    return (Send-Alarma -Cfg $cfg -Hour $hm.Hour -Minute $hm.Minute -Cuando $cuando)
}

# ----------------------------------------------------------------------------
# Modo consola (sin ventana)
# ----------------------------------------------------------------------------
if ($Hora) {
    try   { Write-Output (Enviar $Hora); exit 0 }
    catch { Write-Output "ERROR: $($_.Exception.Message)"; exit 1 }
}

# ----------------------------------------------------------------------------
# Ventana
# ----------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'Alarma'
$form.ClientSize      = New-Object System.Drawing.Size(300, 118)
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition   = 'CenterScreen'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ShowInTaskbar   = $false
$form.TopMost         = $true

$lblPregunta          = New-Object System.Windows.Forms.Label
$lblPregunta.Text     = '¿A qué hora?'
$lblPregunta.Location = New-Object System.Drawing.Point(12, 10)
$lblPregunta.AutoSize = $true
$lblPregunta.Font     = New-Object System.Drawing.Font('Segoe UI', 11)

$txtHora              = New-Object System.Windows.Forms.TextBox
$txtHora.Location     = New-Object System.Drawing.Point(12, 38)
$txtHora.Size         = New-Object System.Drawing.Size(276, 30)
$txtHora.Font         = New-Object System.Drawing.Font('Segoe UI', 14)
$txtHora.TextAlign    = 'Center'

$lblError             = New-Object System.Windows.Forms.Label
$lblError.Location    = New-Object System.Drawing.Point(12, 78)
$lblError.Size        = New-Object System.Drawing.Size(276, 32)
$lblError.ForeColor   = [System.Drawing.Color]::Firebrick
$lblError.Font        = New-Object System.Drawing.Font('Segoe UI', 8.5)

$form.Controls.AddRange(@($lblPregunta, $txtHora, $lblError))

$txtHora.Add_KeyDown({
    param($sender, $e)

    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $e.SuppressKeyPress = $true
        $form.Close()
        return
    }
    if ($e.KeyCode -ne [System.Windows.Forms.Keys]::Enter) { return }

    $e.SuppressKeyPress = $true
    $lblError.Text = ''
    $form.Cursor   = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        Enviar $txtHora.Text | Out-Null
        $form.Close()
    }
    catch {
        $form.Cursor   = [System.Windows.Forms.Cursors]::Default
        $lblError.Text = $_.Exception.Message
        $txtHora.SelectAll()
        $txtHora.Focus()
    }
})

$form.Add_Shown({ $form.Activate(); $txtHora.Focus() })
[void]$form.ShowDialog()
