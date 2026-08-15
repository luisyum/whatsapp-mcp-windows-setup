# WhatsApp MCP en Windows 11 — instalador para dos números

Conecta **uno o dos números de WhatsApp** a Claude Desktop en una PC con **Windows 11**, con un solo comando.

Una vez instalado, Claude puede leer, buscar y responder mensajes de ambas líneas, **interpretar** lo que te mandan (fotos, notas de voz, videos, PDFs) y **enviar** ese mismo tipo de archivos.

Usa el servidor MCP de código abierto [verygoodplugins/whatsapp-mcp](https://github.com/verygoodplugins/whatsapp-mcp) (licencia MIT). Todo corre **localmente en tu PC**: los mensajes se guardan en una base de datos SQLite en tu máquina y solo llegan a Claude cuando tú se lo pides.

---

## Instalación rápida (recomendada)

1. Abre **PowerShell como Administrador**: clic derecho en el botón de Inicio → *Terminal (Administrador)*.

2. Copia y pega este bloque completo, y presiona Enter:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
irm https://raw.githubusercontent.com/luisyum/whatsapp-mcp-windows-setup/main/instalar.ps1 -OutFile "$env:TEMP\instalar.ps1"
& "$env:TEMP\instalar.ps1"
```

3. El instalador hace todo solo: descarga los programas necesarios, compila el puente, configura Claude Desktop y prepara el arranque automático. Tarda entre 10 y 20 minutos la primera vez.

4. Cuando te lo pida, **escanea el código QR** con cada teléfono:
   > WhatsApp → Configuración → Dispositivos vinculados → Vincular un dispositivo

5. Al terminar, **cierra Claude Desktop por completo** (clic derecho en el ícono junto al reloj → Salir) y vuelve a abrirlo.

Listo. Claude ya tiene los dos números.

### Opciones del instalador

```powershell
# Un solo número en lugar de dos
.\instalar.ps1 -Numeros 1

# Instalar en otra carpeta
.\instalar.ps1 -CarpetaInstalacion "D:\WhatsAppMCP"

# Si ya tienes Git, Go, Python y demás instalados
.\instalar.ps1 -OmitirDependencias

# Ver el detalle de cada paso (útil si algo falla)
.\instalar.ps1 -Verbose
```

El instalador se puede **volver a ejecutar** sin problema: detecta lo que ya está hecho y no lo repite. Tampoco borra otros servidores MCP que ya tengas configurados en Claude Desktop (hace un respaldo de tu configuración antes de tocarla).

---

## Qué le puedes pedir a Claude

**Leer y organizar**
- "Muéstrame los últimos mensajes del chat con María en el número 2"
- "Busca conversaciones con el 6-1234-5678"
- "¿Qué grupos tengo en el número 1?"
- "Resume lo que me escribieron hoy"

**Interpretar lo que te mandan** — Claude ve y escucha el contenido directamente
- Fotos: "¿Qué dice la foto que me mandó Juan?"
- Notas de voz: "Transcríbeme el audio de María"
- Videos: "Resume el video que me enviaron al grupo"
- PDFs y documentos: "Sácame los datos importantes del PDF que me mandaron"

**Enviar archivos**
- "Envía la foto que está en mi carpeta Descargas a Juan"
- "Mándale este PDF a María por el número 2"
- "Envía un audio a mi hermana diciéndole que llego tarde"

> El instalador habilita el envío desde tus carpetas **Descargas, Escritorio, Documentos, Imágenes y Videos**. Por seguridad, el puente no lee archivos fuera de esas carpetas.

---

## Cómo funciona

```
   Teléfono 1  ──QR──┐
                     │   ┌─────────────────────────┐
                     ├──▶│  Puente 1 (puerto 8080) │──┐
                     │   └─────────────────────────┘  │   ┌──────────────────┐
                     │                                ├──▶│  Claude Desktop  │
   Teléfono 2  ──QR──┤   ┌─────────────────────────┐  │   └──────────────────┘
                     └──▶│  Puente 2 (puerto 8081) │──┘
                         └─────────────────────────┘
```

Cada número tiene su propio **puente** (un programa pequeño que habla con WhatsApp) escuchando en un puerto distinto, y su propia carpeta de datos. Claude los ve como dos herramientas separadas: `whatsapp` y `whatsapp2`.

Estructura que crea el instalador:

```
C:\Users\<usuario>\WhatsAppMCP\
├── whatsapp-mcp\          código descargado y el puente compilado
├── datos\
│   ├── numero-1\store\    sesión y mensajes del número 1
│   └── numero-2\store\    sesión y mensajes del número 2
└── lanzadores\            accesos para iniciar cada puente
```

---

## Instalación manual (alternativa)

Solo si prefieres hacerlo paso a paso o el instalador falla.

<details>
<summary>Ver los pasos manuales</summary>

### 1. Programas necesarios

En PowerShell como Administrador:

```powershell
winget install --id Git.Git -e
winget install --id GoLang.Go -e
winget install --id Python.Python.3.12 -e
winget install --id astral-sh.uv -e
winget install --id MSYS2.MSYS2 -e
winget install --id Gyan.FFmpeg -e
winget install --id Anthropic.Claude -e
```

Cierra y vuelve a abrir PowerShell.

### 2. Compilador de C

Windows necesita un compilador de C para la base de datos SQLite del puente:

```powershell
C:\msys64\usr\bin\bash.exe -lc "pacman -Sy --noconfirm --needed mingw-w64-ucrt-x86_64-gcc"
$env:Path += ";C:\msys64\ucrt64\bin"
go env -w CGO_ENABLED=1
gcc --version   # debe responder con una versión
```

Agrega `C:\msys64\ucrt64\bin` al `Path` del usuario de forma permanente desde *Variables de entorno*.

### 3. Descargar y compilar

```powershell
mkdir "$env:USERPROFILE\WhatsAppMCP"
cd "$env:USERPROFILE\WhatsAppMCP"
git clone --depth 1 https://github.com/verygoodplugins/whatsapp-mcp.git
cd whatsapp-mcp\whatsapp-bridge
go build -o whatsapp-bridge.exe .
```

Compilar una sola vez evita que el puente se recompile en cada arranque.

### 4. Carpetas de datos

El puente guarda su sesión en una subcarpeta `store` **relativa a la carpeta desde donde se ejecuta**. Por eso **no hay que duplicar el código**: basta con ejecutar el mismo `.exe` desde dos carpetas distintas.

```powershell
mkdir "$env:USERPROFILE\WhatsAppMCP\datos\numero-1"
mkdir "$env:USERPROFILE\WhatsAppMCP\datos\numero-2"
```

### 5. Vincular el número 1

```powershell
cd "$env:USERPROFILE\WhatsAppMCP\datos\numero-1"
$env:WHATSAPP_BRIDGE_PORT = "8080"
$env:WHATSAPP_MEDIA_ROOTS = "$env:USERPROFILE\Downloads;$env:USERPROFILE\Desktop;$env:USERPROFILE\Documents;$env:USERPROFILE\Pictures"
& "$env:USERPROFILE\WhatsAppMCP\whatsapp-mcp\whatsapp-bridge\whatsapp-bridge.exe"
```

Escanea el QR con el teléfono del número 1 y deja esta ventana abierta.

> En Windows el separador de rutas de `WHATSAPP_MEDIA_ROOTS` es **punto y coma (`;`)**, no dos puntos. La documentación del proyecto original menciona `:` porque está escrita para Mac y Linux.

### 6. Vincular el número 2

En una ventana **nueva** de PowerShell:

```powershell
cd "$env:USERPROFILE\WhatsAppMCP\datos\numero-2"
$env:WHATSAPP_BRIDGE_PORT = "8081"
$env:WHATSAPP_MEDIA_ROOTS = "$env:USERPROFILE\Downloads;$env:USERPROFILE\Desktop;$env:USERPROFILE\Documents;$env:USERPROFILE\Pictures"
& "$env:USERPROFILE\WhatsAppMCP\whatsapp-mcp\whatsapp-bridge\whatsapp-bridge.exe"
```

Escanea el QR con el teléfono del número 2.

### 7. Configurar Claude Desktop

Abre el archivo de configuración:

```powershell
notepad "$env:APPDATA\Claude\claude_desktop_config.json"
```

Reemplaza `TU_USUARIO` por tu nombre de usuario de Windows (lo ves con `echo $env:USERNAME`):

```json
{
  "mcpServers": {
    "whatsapp": {
      "command": "uv",
      "args": [
        "--directory",
        "C:\\Users\\TU_USUARIO\\WhatsAppMCP\\whatsapp-mcp\\whatsapp-mcp-server",
        "run",
        "main.py"
      ],
      "env": {
        "WHATSAPP_API_URL": "http://localhost:8080/api",
        "WHATSAPP_DB_PATH": "C:\\Users\\TU_USUARIO\\WhatsAppMCP\\datos\\numero-1\\store\\messages.db",
        "WHATSMEOW_DB_PATH": "C:\\Users\\TU_USUARIO\\WhatsAppMCP\\datos\\numero-1\\store\\whatsapp.db"
      }
    },
    "whatsapp2": {
      "command": "uv",
      "args": [
        "--directory",
        "C:\\Users\\TU_USUARIO\\WhatsAppMCP\\whatsapp-mcp\\whatsapp-mcp-server",
        "run",
        "main.py"
      ],
      "env": {
        "WHATSAPP_API_URL": "http://localhost:8081/api",
        "WHATSAPP_DB_PATH": "C:\\Users\\TU_USUARIO\\WhatsAppMCP\\datos\\numero-2\\store\\messages.db",
        "WHATSMEOW_DB_PATH": "C:\\Users\\TU_USUARIO\\WhatsAppMCP\\datos\\numero-2\\store\\whatsapp.db"
      }
    }
  }
}
```

Si ya tenías otros servidores MCP configurados, agrega solo las dos entradas nuevas dentro de `mcpServers` en lugar de reemplazar todo el archivo.

Guarda y reinicia Claude Desktop por completo.

</details>

---

## Solución de problemas

| Problema | Solución |
|---|---|
| `No se puede cargar el archivo ... porque la ejecución de scripts está deshabilitada` | Ejecuta primero `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` en la misma ventana |
| `gcc: command not found` o falla la compilación | Falta el compilador. Abre *MSYS2 UCRT64* desde el menú Inicio una vez, ciérralo y vuelve a ejecutar el instalador |
| El código QR se ve cortado o deformado | Maximiza la ventana, o reduce el tamaño de letra: clic derecho en la barra de título → Propiedades → Fuente |
| Claude no muestra los servidores de WhatsApp | Cierra Claude **por completo** desde el ícono junto al reloj (clic derecho → Salir), no solo la ventana |
| `403 Forbidden` al enviar un archivo | El archivo está fuera de las carpetas permitidas. Muévelo a Descargas, Escritorio, Documentos o Imágenes |
| `401 Unauthorized` | Reinicia el puente para que regenere su token, y luego reinicia Claude Desktop |
| Los mensajes no se actualizan | Revisa que el puente esté corriendo: debe haber un proceso `whatsapp-bridge.exe` en el Administrador de tareas |
| El firewall pregunta por `whatsapp-bridge.exe` | Permite el acceso en redes privadas. Es tráfico local entre el puente y Claude, no sale a Internet |
| Se desvinculó el teléfono | Borra la carpeta `datos\numero-N\store\whatsapp.db` y ejecuta el lanzador para escanear un QR nuevo |

### Iniciar los puentes a mano

Si el arranque automático no funcionó, ejecuta:

```
C:\Users\<usuario>\WhatsAppMCP\lanzadores\numero-1.cmd
C:\Users\<usuario>\WhatsAppMCP\lanzadores\numero-2.cmd
```

### Desinstalar

1. Borra la carpeta `C:\Users\<usuario>\WhatsAppMCP`
2. Borra los accesos directos "WhatsApp MCP" de la carpeta de inicio (`Win + R` → `shell:startup`)
3. Quita las entradas `whatsapp` y `whatsapp2` de `%APPDATA%\Claude\claude_desktop_config.json`
4. En cada teléfono: WhatsApp → Dispositivos vinculados → cerrar la sesión correspondiente

---

## Privacidad y seguridad

- **Todo es local.** Los mensajes se guardan en tu PC, en `datos\numero-N\store\messages.db`. No se suben a ningún servidor.
- **Claude solo ve lo que le pides.** Los mensajes llegan al modelo únicamente cuando haces una consulta que los necesita.
- **Envío de archivos restringido.** El puente solo lee archivos de las carpetas autorizadas, para que un mensaje malicioso no pueda hacer que se envíen archivos privados del sistema.
- **Ten en cuenta:** como cualquier servidor MCP con acceso a mensajes, esto es sensible a [inyección de instrucciones](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/). Un mensaje recibido podría intentar engañar al modelo. No le des a Claude permiso para enviar mensajes sin revisarlos si manejas información delicada.

---

## Créditos

- Servidor MCP: [verygoodplugins/whatsapp-mcp](https://github.com/verygoodplugins/whatsapp-mcp) (MIT)
- Proyecto original: [lharries/whatsapp-mcp](https://github.com/lharries/whatsapp-mcp) por Luke Harries
- Librería de WhatsApp: [whatsmeow](https://github.com/tulir/whatsmeow)

Este repositorio contiene únicamente el instalador y la documentación para Windows.
