<#
.SYNOPSIS
    Instalador de WhatsApp MCP para Claude Desktop en Windows 11.

.DESCRIPTION
    Instala y configura todo lo necesario para conectar uno o dos numeros de
    WhatsApp a Claude Desktop:
      - Dependencias (Git, Go, compilador C, Python, uv, FFmpeg, Claude Desktop)
      - Descarga y compilacion del puente (bridge) de WhatsApp
      - Carpetas de datos independientes por numero
      - Configuracion de Claude Desktop (fusionada, sin borrar otros servidores)
      - Permisos para enviar archivos desde Descargas, Escritorio, Documentos e Imagenes
      - Lanzadores y arranque automatico al encender la PC

    El script se puede volver a ejecutar sin problema: detecta lo que ya esta
    hecho y no lo repite.

.PARAMETER Numeros
    Cuantos numeros de WhatsApp configurar (1 o 2). Por defecto 2.

.PARAMETER CarpetaInstalacion
    Donde instalar. Por defecto C:\Users\<usuario>\WhatsAppMCP

.PARAMETER OmitirDependencias
    No instalar programas con winget (util si ya los tienes todos).

.EXAMPLE
    .\instalar.ps1
    Instalacion completa para dos numeros.

.EXAMPLE
    .\instalar.ps1 -Numeros 1
    Instalacion para un solo numero.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 2)]
    [int]$Numeros = 2,

    [string]$CarpetaInstalacion = "$env:USERPROFILE\WhatsAppMCP",

    [int]$Puerto1 = 8080,
    [int]$Puerto2 = 8081,

    [switch]$OmitirDependencias
)

$ErrorActionPreference = 'Stop'
try { $OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# ----------------------------------------------------------------------------
# Utilidades de salida
# ----------------------------------------------------------------------------

$script:PasoNumero = 0

function Write-Paso {
    param([string]$Texto)
    $script:PasoNumero++
    Write-Host ""
    Write-Host "[$script:PasoNumero] $Texto" -ForegroundColor Cyan
    Write-Host ("-" * 70) -ForegroundColor DarkGray
}

function Write-Ok      { param([string]$T) Write-Host "    OK    $T" -ForegroundColor Green }
function Write-Info    { param([string]$T) Write-Host "          $T" -ForegroundColor Gray }
function Write-Aviso   { param([string]$T) Write-Host "    AVISO $T" -ForegroundColor Yellow }
function Write-Fallo   { param([string]$T) Write-Host "    ERROR $T" -ForegroundColor Red }

function Test-Comando {
    param([string]$Nombre)
    $null -ne (Get-Command $Nombre -ErrorAction SilentlyContinue)
}

function Update-PathSesion {
    # Recarga el PATH desde el registro para ver programas recien instalados
    # sin tener que cerrar y reabrir PowerShell.
    $maquina = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $usuario = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($maquina, $usuario | Where-Object { $_ }) -join ';'
}

function Install-ConWinget {
    param(
        [string]$Id,
        [string]$Nombre,
        [string]$ComandoPrueba
    )

    if ($ComandoPrueba -and (Test-Comando $ComandoPrueba)) {
        Write-Ok "$Nombre ya esta instalado"
        return $true
    }

    Write-Info "Instalando $Nombre ..."
    $argumentos = @(
        'install', '--id', $Id, '-e',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity'
    )

    & winget @argumentos 2>&1 | Out-String | Write-Verbose

    # winget devuelve 0 al instalar y -1978335189 si ya estaba instalado
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
        Update-PathSesion
        Write-Ok "$Nombre listo"
        return $true
    }

    Write-Aviso "No se pudo instalar $Nombre automaticamente (codigo $LASTEXITCODE)"
    return $false
}

# ----------------------------------------------------------------------------
# Comprobaciones iniciales
# ----------------------------------------------------------------------------

Write-Host ""
Write-Host "===============================================================" -ForegroundColor White
Write-Host " Instalador de WhatsApp MCP para Claude Desktop (Windows)" -ForegroundColor White
Write-Host " Numeros a configurar: $Numeros" -ForegroundColor White
Write-Host " Carpeta: $CarpetaInstalacion" -ForegroundColor White
Write-Host "===============================================================" -ForegroundColor White

Write-Paso "Comprobando el sistema"

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Fallo "Se necesita PowerShell 5.1 o superior. Version actual: $($PSVersionTable.PSVersion)"
    exit 1
}
Write-Ok "PowerShell $($PSVersionTable.PSVersion)"

if (-not (Test-Comando 'winget')) {
    Write-Fallo "No se encontro 'winget' (Instalador de aplicaciones de Windows)."
    Write-Info "Instalalo desde la Microsoft Store buscando 'Instalador de aplicaciones'"
    Write-Info "y vuelve a ejecutar este script."
    exit 1
}
Write-Ok "winget disponible"

# ----------------------------------------------------------------------------
# 1. Dependencias
# ----------------------------------------------------------------------------

if ($OmitirDependencias) {
    Write-Paso "Dependencias (omitidas por parametro)"
    Update-PathSesion
} else {
    Write-Paso "Instalando programas necesarios"
    Write-Info "Esto puede tardar varios minutos la primera vez."

    Install-ConWinget -Id 'Git.Git'            -Nombre 'Git'            -ComandoPrueba 'git'    | Out-Null
    Install-ConWinget -Id 'GoLang.Go'          -Nombre 'Go'             -ComandoPrueba 'go'     | Out-Null
    Install-ConWinget -Id 'Python.Python.3.12' -Nombre 'Python'         -ComandoPrueba 'python' | Out-Null
    Install-ConWinget -Id 'astral-sh.uv'       -Nombre 'uv'             -ComandoPrueba 'uv'     | Out-Null
    Install-ConWinget -Id 'Gyan.FFmpeg'        -Nombre 'FFmpeg'         -ComandoPrueba 'ffmpeg' | Out-Null
    Install-ConWinget -Id 'Anthropic.Claude'   -Nombre 'Claude Desktop' -ComandoPrueba ''       | Out-Null

    # uv tambien se puede instalar con su script oficial si winget falla
    if (-not (Test-Comando 'uv')) {
        Write-Info "Instalando uv con el instalador oficial ..."
        try {
            Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
            Update-PathSesion
        } catch {
            Write-Aviso "No se pudo instalar uv automaticamente: $($_.Exception.Message)"
        }
    }
}

# ----------------------------------------------------------------------------
# 2. Compilador de C (CGO) - obligatorio en Windows para la base de datos
# ----------------------------------------------------------------------------

Write-Paso "Configurando el compilador de C (necesario para SQLite)"

$rutaUcrt = 'C:\msys64\ucrt64\bin'

if (-not (Test-Comando 'gcc')) {
    if (-not (Test-Path $rutaUcrt)) {
        Write-Info "Instalando MSYS2 (trae el compilador gcc) ..."
        Install-ConWinget -Id 'MSYS2.MSYS2' -Nombre 'MSYS2' -ComandoPrueba '' | Out-Null
    }

    if (Test-Path 'C:\msys64\usr\bin\bash.exe') {
        Write-Info "Instalando gcc dentro de MSYS2 (puede tardar) ..."
        & C:\msys64\usr\bin\bash.exe -lc "pacman -Sy --noconfirm --needed mingw-w64-ucrt-x86_64-gcc" 2>&1 |
            Out-String | Write-Verbose
    }

    if (Test-Path $rutaUcrt) {
        # Anadir gcc al PATH del usuario de forma permanente
        $pathUsuario = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($pathUsuario -notlike "*$rutaUcrt*") {
            [Environment]::SetEnvironmentVariable('Path', "$pathUsuario;$rutaUcrt", 'User')
            Write-Ok "gcc anadido al PATH de forma permanente"
        }
        $env:Path += ";$rutaUcrt"
    }
}

if (Test-Comando 'gcc') {
    Write-Ok "Compilador gcc disponible"
} else {
    Write-Fallo "No se encontro gcc. El puente no se puede compilar sin el."
    Write-Info "Abre 'MSYS2 UCRT64' desde el menu Inicio una vez, cierra la ventana,"
    Write-Info "y vuelve a ejecutar este script."
    exit 1
}

& go env -w CGO_ENABLED=1
Write-Ok "CGO habilitado en Go"

# ----------------------------------------------------------------------------
# 3. Descargar el codigo del proyecto
# ----------------------------------------------------------------------------

Write-Paso "Descargando el proyecto WhatsApp MCP"

$repoUrl  = 'https://github.com/verygoodplugins/whatsapp-mcp.git'
$carpetaCodigo = Join-Path $CarpetaInstalacion 'whatsapp-mcp'

if (-not (Test-Path $CarpetaInstalacion)) {
    New-Item -ItemType Directory -Path $CarpetaInstalacion -Force | Out-Null
}

if (Test-Path (Join-Path $carpetaCodigo '.git')) {
    Write-Info "El proyecto ya existe, actualizando ..."
    Push-Location $carpetaCodigo
    try {
        & git pull --ff-only 2>&1 | Out-String | Write-Verbose
        Write-Ok "Proyecto actualizado"
    } catch {
        Write-Aviso "No se pudo actualizar, se usa la version que ya estaba"
    } finally {
        Pop-Location
    }
} else {
    & git clone --depth 1 $repoUrl $carpetaCodigo 2>&1 | Out-String | Write-Verbose
    if (-not (Test-Path $carpetaCodigo)) {
        Write-Fallo "No se pudo descargar el proyecto desde $repoUrl"
        exit 1
    }
    Write-Ok "Proyecto descargado en $carpetaCodigo"
}

# ----------------------------------------------------------------------------
# 4. Compilar el puente una sola vez
# ----------------------------------------------------------------------------

Write-Paso "Compilando el puente de WhatsApp"
Write-Info "La primera vez puede tardar unos minutos."

$carpetaBridge = Join-Path $carpetaCodigo 'whatsapp-bridge'
$ejecutable    = Join-Path $carpetaBridge 'whatsapp-bridge.exe'

Push-Location $carpetaBridge
try {
    $env:CGO_ENABLED = '1'
    & go build -o whatsapp-bridge.exe . 2>&1 | Out-String | Write-Verbose

    if (-not (Test-Path $ejecutable)) {
        Write-Fallo "La compilacion fallo."
        Write-Info "Ejecuta este script otra vez con -Verbose para ver el detalle:"
        Write-Info "    .\instalar.ps1 -Verbose"
        exit 1
    }
    Write-Ok "Puente compilado: whatsapp-bridge.exe"
} finally {
    Pop-Location
}

# ----------------------------------------------------------------------------
# 5. Carpetas de datos independientes por numero
# ----------------------------------------------------------------------------
# El puente guarda su sesion en una subcarpeta 'store' RELATIVA a la carpeta
# desde donde se ejecuta. Por eso no hace falta duplicar el codigo: basta con
# ejecutar el mismo .exe desde dos carpetas distintas.

Write-Paso "Creando carpetas de datos (una por numero)"

$carpetaDatos = Join-Path $CarpetaInstalacion 'datos'
$instancias = @()

for ($i = 1; $i -le $Numeros; $i++) {
    $puerto = if ($i -eq 1) { $Puerto1 } else { $Puerto2 }
    $ruta   = Join-Path $carpetaDatos "numero-$i"

    if (-not (Test-Path $ruta)) {
        New-Item -ItemType Directory -Path $ruta -Force | Out-Null
    }

    $instancias += [pscustomobject]@{
        Indice        = $i
        Nombre        = if ($i -eq 1) { 'whatsapp' } else { "whatsapp$i" }
        Puerto        = $puerto
        Carpeta       = $ruta
        StoreMensajes = Join-Path $ruta 'store\messages.db'
        StoreSesion   = Join-Path $ruta 'store\whatsapp.db'
    }

    Write-Ok "Numero $i  ->  puerto $puerto  ->  $ruta"
}

# ----------------------------------------------------------------------------
# 6. Permitir el envio de archivos desde las carpetas normales del usuario
# ----------------------------------------------------------------------------
# Por seguridad el puente solo lee archivos de una carpeta 'outbox' oculta.
# Sin esto, enviar un PDF desde Descargas devuelve "403 Forbidden".
# IMPORTANTE: en Windows el separador de rutas es ';' (no ':' como en Mac/Linux).

Write-Paso "Habilitando el envio de archivos (fotos, PDFs, videos, audios)"

$carpetasPermitidas = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('MyPictures'),
    [Environment]::GetFolderPath('MyVideos'),
    (Join-Path $env:USERPROFILE 'Downloads')
) | Where-Object { $_ -and (Test-Path $_ -PathType Container -ErrorAction SilentlyContinue) }

$outbox = Join-Path $env:USERPROFILE '.local\share\whatsapp-mcp\outbox'
if (-not (Test-Path $outbox)) {
    New-Item -ItemType Directory -Path $outbox -Force | Out-Null
    $carpetasPermitidas += $outbox
}

$mediaRoots = ($carpetasPermitidas | Select-Object -Unique) -join ';'

foreach ($c in ($carpetasPermitidas | Select-Object -Unique)) {
    Write-Ok "Permitida: $c"
}

# ----------------------------------------------------------------------------
# 7. Lanzadores
# ----------------------------------------------------------------------------

Write-Paso "Creando lanzadores"

$carpetaLanzadores = Join-Path $CarpetaInstalacion 'lanzadores'
if (-not (Test-Path $carpetaLanzadores)) {
    New-Item -ItemType Directory -Path $carpetaLanzadores -Force | Out-Null
}

foreach ($inst in $instancias) {
    # .cmd: hace 'cd' a la carpeta de datos para que el store quede ahi
    $cmd = @"
@echo off
title WhatsApp MCP - Numero $($inst.Indice) (puerto $($inst.Puerto))
set "WHATSAPP_BRIDGE_PORT=$($inst.Puerto)"
set "WHATSAPP_MEDIA_ROOTS=$mediaRoots"
set "WHATSAPP_DEVICE_NAME=Claude (Numero $($inst.Indice))"
cd /d "$($inst.Carpeta)"
"$ejecutable"
"@
    $rutaCmd = Join-Path $carpetaLanzadores "numero-$($inst.Indice).cmd"
    Set-Content -Path $rutaCmd -Value $cmd -Encoding ASCII

    # .vbs: arranca el .cmd sin ventana visible (para el arranque automatico)
    $vbs = @"
Set s = CreateObject("WScript.Shell")
s.Run """$rutaCmd""", 0, False
"@
    $rutaVbs = Join-Path $carpetaLanzadores "numero-$($inst.Indice)-silencioso.vbs"
    Set-Content -Path $rutaVbs -Value $vbs -Encoding ASCII

    Write-Ok "Lanzador numero $($inst.Indice) creado"
}

# ----------------------------------------------------------------------------
# 8. Configurar Claude Desktop (fusionando, sin borrar otros servidores MCP)
# ----------------------------------------------------------------------------

Write-Paso "Configurando Claude Desktop"

$carpetaClaude = Join-Path $env:APPDATA 'Claude'
$archivoConfig = Join-Path $carpetaClaude 'claude_desktop_config.json'
$carpetaServidorMcp = Join-Path $carpetaCodigo 'whatsapp-mcp-server'

if (-not (Test-Path $carpetaClaude)) {
    New-Item -ItemType Directory -Path $carpetaClaude -Force | Out-Null
}

# Leer la configuracion existente para NO borrar otros servidores ya configurados
$config = $null
if (Test-Path $archivoConfig) {
    $copia = "$archivoConfig.respaldo-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $archivoConfig $copia
    Write-Ok "Respaldo de la configuracion anterior: $(Split-Path $copia -Leaf)"

    try {
        $config = Get-Content $archivoConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Aviso "El archivo de configuracion existente no es valido, se creara uno nuevo"
        $config = $null
    }
}

if ($null -eq $config) {
    $config = [pscustomobject]@{}
}

$nombresExistentes = @($config.PSObject.Properties | ForEach-Object { $_.Name })
if ($nombresExistentes -notcontains 'mcpServers' -or $null -eq $config.mcpServers) {
    $config | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{}) -Force
}

foreach ($inst in $instancias) {
    $entrada = [pscustomobject]@{
        command = 'uv'
        args    = @('--directory', $carpetaServidorMcp, 'run', 'main.py')
        env     = [pscustomobject]@{
            WHATSAPP_API_URL     = "http://localhost:$($inst.Puerto)/api"
            WHATSAPP_DB_PATH     = $inst.StoreMensajes
            WHATSMEOW_DB_PATH    = $inst.StoreSesion
            WHATSAPP_MEDIA_ROOTS = $mediaRoots
        }
    }

    $config.mcpServers | Add-Member -NotePropertyName $inst.Nombre -NotePropertyValue $entrada -Force
    Write-Ok "Servidor MCP '$($inst.Nombre)' configurado (puerto $($inst.Puerto))"
}

$json = $config | ConvertTo-Json -Depth 10
$sinBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($archivoConfig, $json, $sinBom)
Write-Ok "Guardado en $archivoConfig"

# ----------------------------------------------------------------------------
# 9. Arranque automatico
# ----------------------------------------------------------------------------

Write-Paso "Configurando el arranque automatico al encender la PC"

$carpetaInicio = [Environment]::GetFolderPath('Startup')
$shell = New-Object -ComObject WScript.Shell

foreach ($inst in $instancias) {
    $destinoVbs = Join-Path $carpetaLanzadores "numero-$($inst.Indice)-silencioso.vbs"
    $acceso = Join-Path $carpetaInicio "WhatsApp MCP - Numero $($inst.Indice).lnk"

    $sc = $shell.CreateShortcut($acceso)
    $sc.TargetPath = $destinoVbs
    $sc.WorkingDirectory = $inst.Carpeta
    $sc.Description = "Puente de WhatsApp MCP para el numero $($inst.Indice)"
    $sc.Save()

    Write-Ok "Arranque automatico del numero $($inst.Indice) configurado"
}

# ----------------------------------------------------------------------------
# 10. Vinculacion de los numeros (codigo QR)
# ----------------------------------------------------------------------------

Write-Paso "Vinculacion de los numeros de WhatsApp"

$faltanVincular = @()
foreach ($inst in $instancias) {
    if (Test-Path $inst.StoreSesion) {
        Write-Ok "Numero $($inst.Indice) ya esta vinculado"
    } else {
        $faltanVincular += $inst
    }
}

if ($faltanVincular.Count -gt 0) {
    Write-Host ""
    Write-Host "  Falta vincular $($faltanVincular.Count) numero(s) escaneando un codigo QR." -ForegroundColor Yellow
    Write-Host "  Se abrira una ventana por cada numero." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  En el telefono correspondiente:" -ForegroundColor White
    Write-Host "    WhatsApp  ->  Configuracion  ->  Dispositivos vinculados" -ForegroundColor White
    Write-Host "               ->  Vincular un dispositivo  ->  escanear el QR" -ForegroundColor White
    Write-Host ""

    foreach ($inst in $faltanVincular) {
        $respuesta = Read-Host "  Vincular ahora el numero $($inst.Indice)? (s/n)"
        if ($respuesta -match '^[sSyY]') {
            $rutaCmd = Join-Path $carpetaLanzadores "numero-$($inst.Indice).cmd"
            Start-Process -FilePath $rutaCmd
            Write-Info "Ventana abierta. Escanea el QR con el telefono del numero $($inst.Indice)."
            Read-Host "  Presiona ENTER cuando el numero $($inst.Indice) diga 'Connected to WhatsApp'"
        } else {
            Write-Info "Puedes vincularlo despues ejecutando:"
            Write-Info "    $(Join-Path $carpetaLanzadores "numero-$($inst.Indice).cmd")"
        }
    }
} else {
    Write-Info "Iniciando los puentes ..."
    foreach ($inst in $instancias) {
        $rutaVbs = Join-Path $carpetaLanzadores "numero-$($inst.Indice)-silencioso.vbs"
        Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$rutaVbs`"" -WindowStyle Hidden
    }
    Start-Sleep -Seconds 5
}

# ----------------------------------------------------------------------------
# 11. Comprobacion final
# ----------------------------------------------------------------------------

Write-Paso "Comprobando que todo funciona"

foreach ($inst in $instancias) {
    $url = "http://localhost:$($inst.Puerto)/api/health"
    try {
        $null = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        Write-Ok "Numero $($inst.Indice): el puente responde en el puerto $($inst.Puerto)"
    } catch {
        $codigo = 0
        try { $codigo = [int]$_.Exception.Response.StatusCode } catch { $codigo = 0 }
        if ($codigo -eq 401 -or $codigo -eq 403) {
            # 401 significa que el servidor esta vivo y pidiendo autenticacion: correcto
            Write-Ok "Numero $($inst.Indice): el puente responde en el puerto $($inst.Puerto)"
        } else {
            Write-Aviso "Numero $($inst.Indice): el puente no responde todavia en el puerto $($inst.Puerto)"
            Write-Info "Inicialo con: $(Join-Path $carpetaLanzadores "numero-$($inst.Indice).cmd")"
        }
    }
}

# ----------------------------------------------------------------------------
# Resumen
# ----------------------------------------------------------------------------

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host " Instalacion terminada" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Ultimo paso: cierra Claude Desktop POR COMPLETO (incluido el" -ForegroundColor White
Write-Host " icono junto al reloj, clic derecho -> Salir) y vuelve a abrirlo." -ForegroundColor White
Write-Host ""
Write-Host " Despues podras pedirle a Claude cosas como:" -ForegroundColor White
foreach ($inst in $instancias) {
    Write-Host "   - `"Muestrame los ultimos mensajes de $($inst.Nombre)`"" -ForegroundColor Gray
}
Write-Host "   - `"Transcribeme el audio que me mando Maria`"" -ForegroundColor Gray
Write-Host "   - `"Envia esta foto de mi carpeta Descargas a Juan`"" -ForegroundColor Gray
Write-Host ""
Write-Host " Carpeta de instalacion: $CarpetaInstalacion" -ForegroundColor Gray
Write-Host " Lanzadores manuales:    $carpetaLanzadores" -ForegroundColor Gray
Write-Host ""
