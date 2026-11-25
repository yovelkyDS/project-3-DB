<#
=====================================================================
 SIG-TEC · instalador para Windows (PowerShell 5.1+ / PowerShell 7)

   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1

 Qué hace:
   1. Comprueba Docker Desktop y Docker Compose v2 (intenta iniciar Docker Desktop si está detenido).
   2. Crea .env desde .env.example y genera contraseñas aleatorias (sin mostrarlas).
   3. Si hay bash disponible (Git for Windows o WSL), delega en scripts/setup.sh,
      que es el instalador completo y probado.
   4. Si no hay bash, ejecuta el flujo equivalente con docker compose directamente
      (construcción, arranque, migraciones, datos de prueba y verificación).

 Nota: este script no se pudo ejecutar en el entorno donde se desarrolló el
 proyecto (macOS); el flujo de referencia es scripts/setup.sh.
=====================================================================
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Log($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }

# PowerShell 5.1 convierte algunos mensajes de stderr de programas nativos en
# ErrorRecord. Con ErrorActionPreference=Stop eso abortaba el instalador antes
# de poder iniciar Docker Desktop. Esta función conserva el código de salida y
# silencia únicamente la prueba esperada de disponibilidad.
function Test-DockerDaemon {
    $previousPreference = $ErrorActionPreference
    $ready = $false
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        docker info *> $null
        $ready = ($LASTEXITCODE -eq 0)
    } catch {
        $ready = $false
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return $ready
}

function Test-BashExecutable($path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $false }
    $previousPreference = $ErrorActionPreference
    $works = $false
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $path -lc 'exit 0' *> $null
        $works = ($LASTEXITCODE -eq 0)
    } catch {
        $works = $false
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return $works
}

# 1. Docker -------------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker no está instalado. Instale Docker Desktop: https://docs.docker.com/desktop/setup/install/windows-install/  (winget install -e --id Docker.DockerDesktop)"
}
docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Docker Compose v2 no disponible (actualice Docker Desktop)." }

if (-not (Test-DockerDaemon)) {
    $dockerCli = (Get-Command docker).Source
    $desktopCandidates = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Docker\Docker Desktop.exe'),
        (Join-Path (Split-Path (Split-Path (Split-Path $dockerCli -Parent) -Parent) -Parent) 'Docker Desktop.exe')
    ) | Select-Object -Unique
    $dd = $desktopCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $dd) {
        throw 'Docker Desktop no está instalado completamente. Instálelo con: winget install -e --id Docker.DockerDesktop'
    }
    Log "Iniciando Docker Desktop desde $dd"
    Start-Process -FilePath $dd -WindowStyle Hidden
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep 2
        if (Test-DockerDaemon) { break }
    }
    if (-not (Test-DockerDaemon)) {
        throw 'Docker Desktop abrió, pero el motor Linux no respondió en 3 minutos. Abra Docker Desktop, revise el aviso mostrado y compruebe WSL 2 con: wsl --status'
    }
}
Log "Docker listo: $(docker --version)"

# 2. .env -----------------------------------------------------------------
function New-Secret {
    $bytes = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    (([Convert]::ToBase64String($bytes)) -replace '[^A-Za-z0-9]', '').Substring(0, 32)
}
$envFile = Join-Path $Root '.env'
if (-not (Test-Path $envFile)) { Copy-Item (Join-Path $Root '.env.example') $envFile; Log '.env creado' }
$lines = Get-Content $envFile | ForEach-Object {
    if ($_ -match '^([A-Z0-9_]+)=__GENERAR__$') { "$($Matches[1])=$(New-Secret)" } else { $_ }
}
# Sin BOM y con fin de línea LF para que también lo lea bash
[System.IO.File]::WriteAllText($envFile, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
Log '.env listo (los valores no se muestran)'

# 3. Delegar en un bash funcional si existe -------------------------------
# WindowsApps\bash.exe puede existir aunque WSL no tenga una distribución
# utilizable. Preferimos Git Bash y probamos cada candidato antes de delegar.
$pathBash = (Get-Command bash -ErrorAction SilentlyContinue).Source
$bashCandidates = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    (Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'),
    $pathBash
) | Where-Object { $_ } | Select-Object -Unique
$bashPath = $bashCandidates | Where-Object { Test-BashExecutable $_ } | Select-Object -First 1
if ($bashPath) {
    Log "Ejecutando scripts/setup.sh con $bashPath"
    & $bashPath scripts/setup.sh
    exit $LASTEXITCODE
}
Log 'No se encontró Bash funcional; se usará el flujo nativo de PowerShell.'

# 4. Flujo equivalente sin bash --------------------------------------------
$nodes = 'pg-central','pg-cartago','pg-san-jose','pg-san-carlos','pg-alajuela','pg-limon'
Log 'Construyendo imagen'; docker compose build pg-central; if ($LASTEXITCODE) { throw 'build falló' }
Log 'Iniciando nodos';     docker compose up -d @nodes;      if ($LASTEXITCODE) { throw 'up falló' }
Log 'Esperando healthy'
for ($i = 0; $i -lt 150; $i++) {
    $ok = $true
    foreach ($n in $nodes) {
        $id = docker compose ps -q $n
        $st = if ($id) { docker inspect -f '{{.State.Health.Status}}' $id } else { 'ausente' }
        if ($st -ne 'healthy') { $ok = $false }
    }
    if ($ok) { break }; Start-Sleep 2
}
if (-not $ok) { throw 'Algún nodo no quedó healthy (docker compose logs)' }
foreach ($s in 'scripts/db/migrate.sh all', 'scripts/db/seed.sh campus', 'scripts/db/verify.sh') {
    Log $s
    docker compose --profile tools run --rm -T sigtec-tools -c $s
    if ($LASTEXITCODE) { throw "$s falló" }
}
Log 'SIG-TEC desplegado. Pruebas: docker compose --profile tools run --rm -T sigtec-tools tests/container/run_sql_tests.sh all'
