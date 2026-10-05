<#
  First-launch setup with a small progress window instead of a console.

  Everything the app needs beyond the shipped source - Python, FFmpeg and the
  Python packages - is installed here. Once that is done this script is a fast
  no-op that launches the app directly, so only the first run shows a window.

  -SelfTest renders the window with sample text and exits, for checking layout.
#>
param([switch]$SelfTest)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$logDir = Join-Path $root "logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "setup.log"
$venvPy = Join-Path $root ".venv\Scripts\python.exe"
$marker = Join-Path $root ".venv\.deps-installed"
$reqFile = Join-Path $root "requirements.txt"

function Write-Log($text) {
    Add-Content -Path $log -Value ("{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $text) -Encoding utf8
}

function Start-App {
    Start-Process -FilePath $venvPy -ArgumentList "-m", "app.main" -WorkingDirectory $root -WindowStyle Hidden
}

# --- fast path: already set up, just start ------------------------------
if (-not $SelfTest -and (Test-Path $venvPy) -and (Test-Path $marker)) {
    $reqHash = (Get-FileHash $reqFile -Algorithm SHA256).Hash
    if ((Get-Content $marker -Raw).Trim() -eq $reqHash) { Start-App; exit 0 }
}

# --- progress window -----------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "neolunaruby setup"
$form.Size = New-Object System.Drawing.Size(470, 200)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(14, 20, 22)
$form.ForeColor = [System.Drawing.Color]::FromArgb(217, 230, 228)
$icon = Join-Path $root "assets\neolunaruby.ico"
if (Test-Path $icon) { $form.Icon = New-Object System.Drawing.Icon($icon) }

$title = New-Object System.Windows.Forms.Label
$title.Text = "Setting things up"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(57, 197, 187)
$title.Location = New-Object System.Drawing.Point(22, 20)
$title.Size = New-Object System.Drawing.Size(410, 28)
$form.Controls.Add($title)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Starting..."
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$status.Location = New-Object System.Drawing.Point(22, 52)
$status.Size = New-Object System.Drawing.Size(420, 20)
$form.Controls.Add($status)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Style = "Marquee"
$bar.MarqueeAnimationSpeed = 30
$bar.Location = New-Object System.Drawing.Point(22, 80)
$bar.Size = New-Object System.Drawing.Size(420, 14)
$form.Controls.Add($bar)

$note = New-Object System.Windows.Forms.Label
$note.Text = "This happens once and takes about 5-10 minutes." + [Environment]::NewLine + "You can leave it running in the background."
$note.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$note.ForeColor = [System.Drawing.Color]::FromArgb(116, 137, 140)
$note.Location = New-Object System.Drawing.Point(22, 104)
$note.Size = New-Object System.Drawing.Size(420, 36)
$form.Controls.Add($note)

$form.Show()
[System.Windows.Forms.Application]::DoEvents()

function Set-Status($text) {
    $status.Text = $text
    Write-Log $text
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Failure($message) {
    $bar.Style = "Continuous"
    $bar.Value = 0
    $title.Text = "Setup could not finish"
    $title.ForeColor = [System.Drawing.Color]::FromArgb(225, 40, 133)
    Set-Status $message
    [System.Windows.Forms.MessageBox]::Show("$message`n`nThe full log is at:`n$log", "neolunaruby setup", "OK", "Error") | Out-Null
    $form.Close()
    exit 1
}

# Runs a command, keeps the window responsive, and surfaces the most recent
# output line so long installs do not look frozen.
function Invoke-Step($exe, $argList, $statusText, $detailPattern) {
    Set-Status $statusText
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    while (-not $proc.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
        if ($detailPattern) {
            try {
                $line = Get-Content $out -Tail 1 -ErrorAction SilentlyContinue
                if ($line -and $line -match $detailPattern) {
                    $detail = $matches[1]
                    if ($detail.Length -gt 46) { $detail = $detail.Substring(0, 46) + "..." }
                    $status.Text = "$statusText  -  $detail"
                }
            } catch {}
        }
    }
    Get-Content $out -ErrorAction SilentlyContinue | ForEach-Object { Write-Log $_ }
    Get-Content $err -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "ERR $_" }
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) {
        Show-Failure "$statusText failed (exit code $($proc.ExitCode))."
    }
}

if ($SelfTest) {
    Set-Status "Installing Python 3.13"
    Start-Sleep -Seconds 1
    Set-Status "Downloading dependencies  -  torch-2.7.1+cu128 (3.3 GB)"
    Start-Sleep -Seconds 2
    $form.Close()
    exit 0
}

try {
    # --- Python 3.13 -----------------------------------------------------
    $havePython = $false
    try { if (& py -3.13 --version 2>$null) { $havePython = $true } } catch {}
    if (-not $havePython) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Show-Failure "Python 3.13 is missing and winget is unavailable. Install Python 3.13 from python.org, then start the app again."
        }
        Invoke-Step "winget" @("install", "--id", "Python.Python.3.13", "-e", "--accept-source-agreements", "--accept-package-agreements") "Installing Python 3.13"
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    }

    # --- FFmpeg ----------------------------------------------------------
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Invoke-Step "winget" @("install", "--id", "Gyan.FFmpeg", "-e", "--accept-source-agreements", "--accept-package-agreements") "Installing audio tools"
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    }

    # --- virtual environment ---------------------------------------------
    if (-not (Test-Path $venvPy)) {
        Invoke-Step "py" @("-3.13", "-m", "venv", "`"$root\.venv`"") "Creating the Python environment"
    }

    Invoke-Step $venvPy @("-m", "pip", "install", "--upgrade", "pip") "Preparing the installer"
    Invoke-Step $venvPy @("-m", "pip", "install", "-r", "`"$reqFile`"", "--extra-index-url", "https://download.pytorch.org/whl/cu128") "Downloading dependencies" "(?:Downloading|Installing collected packages:?)\s+(.+)"

    # kokoro-onnx pulls plain onnxruntime, which shadows the GPU build
    Invoke-Step $venvPy @("-m", "pip", "uninstall", "-y", "onnxruntime") "Tidying up"
    Invoke-Step $venvPy @("-m", "pip", "install", "--force-reinstall", "--no-deps", "onnxruntime-gpu==1.23.2") "Setting up GPU support"

    Set-Content $marker ((Get-FileHash $reqFile -Algorithm SHA256).Hash) -Encoding utf8
    Set-Status "Starting the app"
    Start-App
    Start-Sleep -Milliseconds 400
    $form.Close()
} catch {
    Show-Failure $_.Exception.Message
}
