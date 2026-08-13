# WhatsApp MCP — Dos números en Windows 11

Guía paso a paso para conectar **dos números de WhatsApp propios** a Claude Desktop en una PC con **Windows 11**, usando el servidor MCP de código abierto [verygoodplugins/whatsapp-mcp](https://github.com/verygoodplugins/whatsapp-mcp) (licencia MIT, mantenido activamente).

Al terminar vas a tener dos herramientas MCP separadas — por ejemplo `whatsapp` y `whatsapp2` — cada una conectada a un número distinto, y Claude va a poder leer, buscar, enviar e **interpretar** (imágenes, audios, videos, PDFs) mensajes de ambas líneas.

> Este proyecto es un fork mantenido de [lharries/whatsapp-mcp](https://github.com/lharries/whatsapp-mcp). Todo corre 100% local en tu PC — los mensajes se guardan en una base SQLite en tu máquina y solo se envían a Claude cuando vos se lo pedís explícitamente.

---

## 0. Qué vas a instalar

| Componente | Para qué sirve |
|---|---|
| Git | Descargar el código del proyecto |
| Go 1.25+ | Compilar y correr el "puente" (bridge) que habla con WhatsApp |
| MSYS2 (+ gcc) | Windows necesita un compilador de C para compilar la base de datos SQLite del bridge |
| Python 3.11+ | Correr el servidor MCP que Claude usa para leer/enviar mensajes |
| uv | Gestor de paquetes de Python que usa este proyecto |
| Claude Desktop | La app donde vas a hablar con Claude |
| FFmpeg (opcional) | Conversión de notas de voz para poder escucharlas/transcribirlas |

---

## 1. Instalar los requisitos (PowerShell como Administrador)

Abrí **PowerShell como Administrador** (clic derecho → "Ejecutar como administrador") y corré:

```powershell
winget install --id Git.Git -e
winget install --id GoLang.Go -e
winget install --id Python.Python.3.12 -e
winget install --id MSYS2.MSYS2 -e
winget install --id Gyan.FFmpeg -e
```

Cerrá y volvé a abrir PowerShell después de esto (para que el `PATH` se actualice).

### Instalar `uv`

```powershell
irm https://astral.sh/uv/install.ps1 | iex
```

### Habilitar CGO (necesario en Windows para compilar el bridge)

El bridge usa una librería de SQLite que necesita un compilador de C. Abrí **MSYS2 UCRT64** desde el menú Inicio una vez (para que termine su instalación inicial) y luego, en PowerShell normal:

```powershell
# Agregá gcc de MSYS2 al PATH de esta sesión
$env:Path += ";C:\msys64\ucrt64\bin"

# Instalá gcc si no vino incluido
C:\msys64\usr\bin\bash.exe -lc "pacman -Sy --noconfirm mingw-w64-ucrt-x86_64-gcc"

# Decile a Go que use CGO
go env -w CGO_ENABLED=1
```

> Para que `gcc` quede disponible en **todas** las sesiones futuras de PowerShell (no solo esta), agregá `C:\msys64\ucrt64\bin` a la variable de entorno `Path` del sistema: Configuración → Sistema → Información del sistema → Configuración avanzada del sistema → Variables de entorno.

Verificá que todo quedó instalado:

```powershell
git --version
go version
python --version
uv --version
gcc --version
```

---

## 2. Descargar el proyecto (una sola vez)

```powershell
cd $HOME\Documents
git clone https://github.com/verygoodplugins/whatsapp-mcp.git
cd whatsapp-mcp
```

Vas a usar **esta misma carpeta** para los dos números — solo vas a duplicar la subcarpeta del bridge.

---

## 3. Número 1 — primer bridge (puerto 8080)

```powershell
cd $HOME\Documents\whatsapp-mcp\whatsapp-bridge
go run .
```

- La primera vez va a mostrar un **código QR en la terminal**.
- En el celular del **Número 1**: WhatsApp → Configuración → Dispositivos vinculados → Vincular un dispositivo → escaneá el QR.
- Cuando diga "Connected to WhatsApp!", dejá esta ventana de PowerShell **abierta** (es el bridge corriendo). Podés minimizarla.

La sesión y los mensajes quedan guardados localmente en `whatsapp-bridge\store\`.

---

## 4. Número 2 — segundo bridge (puerto 8081)

Abrí una **nueva** ventana de PowerShell (dejá la del paso 3 corriendo) y duplicá la carpeta del bridge:

```powershell
cd $HOME\Documents\whatsapp-mcp
Copy-Item -Recurse whatsapp-bridge whatsapp-bridge-2 -Exclude store
```

Ahora corré el segundo bridge en un puerto distinto:

```powershell
cd $HOME\Documents\whatsapp-mcp\whatsapp-bridge-2
$env:WHATSAPP_BRIDGE_PORT = "8081"
go run .
```

Va a mostrar otro código QR. Esta vez escaneálo con el **Número 2** de tu mamá (Configuración → Dispositivos vinculados → Vincular un dispositivo, en ese teléfono).

Dejá también esta ventana abierta. Ahora tenés dos bridges corriendo:

- Número 1 → `http://localhost:8080`
- Número 2 → `http://localhost:8081`

---

## 5. Conectar los dos números a Claude Desktop

Abrí (o creá) el archivo de configuración de Claude Desktop en Windows:

```
%APPDATA%\Claude\claude_desktop_config.json
```

Podés abrirlo rápido así en PowerShell:

```powershell
notepad "$env:APPDATA\Claude\claude_desktop_config.json"
```

Pegá esto (ajustá `TU_USUARIO` por el nombre de usuario real de Windows — podés confirmarlo corriendo `echo $env:USERNAME`):

```json
{
  "mcpServers": {
    "whatsapp": {
      "command": "uv",
      "args": [
        "--directory",
        "C:\\Users\\TU_USUARIO\\Documents\\whatsapp-mcp\\whatsapp-mcp-server",
        "run",
        "main.py"
      ],
      "env": {
        "WHATSAPP_API_URL": "http://localhost:8080/api",
        "WHATSAPP_DB_PATH": "C:\\Users\\TU_USUARIO\\Documents\\whatsapp-mcp\\whatsapp-bridge\\store\\messages.db",
        "WHATSMEOW_DB_PATH": "C:\\Users\\TU_USUARIO\\Documents\\whatsapp-mcp\\whatsapp-bridge\\store\\whatsapp.db"
      }
    },
    "whatsapp2": {
      "command": "uv",
      "args": [
        "--directory",
        "C:\\Users\\TU_USUARIO\\Documents\\whatsapp-mcp\\whatsapp-mcp-server",
        "run",
        "main.py"
      ],
      "env": {
        "WHATSAPP_API_URL": "http://localhost:8081/api",
        "WHATSAPP_DB_PATH": "C:\\Users\\TU_USUARIO\\Documents\\whatsapp-mcp\\whatsapp-bridge-2\\store\\messages.db",
        "WHATSMEOW_DB_PATH": "C:\\Users\\TU_USUARIO\\Documents\\whatsapp-mcp\\whatsapp-bridge-2\\store\\whatsapp.db"
      }
    }
  }
}
```

Guardá el archivo y **reiniciá Claude Desktop** por completo (cerrarlo desde la bandeja del sistema, no solo la ventana).

Si todo salió bien, en Claude Desktop (ícono del martillo/herramientas o Configuración → Developer) deberían aparecer **dos** servidores MCP: `whatsapp` y `whatsapp2`.

---

## 6. Qué le podés pedir a Claude una vez conectado

Con los dos números conectados, tu mamá puede simplemente hablarle a Claude en lenguaje natural y pedirle, por ejemplo:

**Leer y organizar**
- "Mostrame los últimos mensajes del chat con [contacto] en el número 1/2"
- "Buscá conversaciones con [nombre o teléfono]"
- "¿Qué grupos tengo en el número 2?"

**Interpretar archivos recibidos** (Claude ve/escucha el contenido directamente, no hace falta abrir WhatsApp)
- Imágenes: "¿Qué dice esta foto que me mandaron?" / "Describime esta imagen"
- Notas de voz / audios: "Transcribime el audio que me mandó [contacto]"
- Videos: "Resumime este video" / "¿Qué pasa en este clip?"
- Documentos / PDFs: "Resumime este PDF" / "Sacame los datos importantes de este documento"
- Enlaces: "Abrí este link y contame de qué trata"

**Enviar el mismo tipo de archivos**
- "Enviale esta foto a [contacto] por el número 1"
- "Mandale un audio con este mensaje a [contacto]" (Claude puede generar y enviar audio)
- "Enviale este PDF/documento a [contacto] por el número 2"
- "Mandale este video a [grupo]"

No hace falta instalar nada extra para esto: es la combinación del proyecto `whatsapp-mcp` (que ya sabe descargar y enviar imágenes, videos, documentos y audio — ver la sección *Media Support* del proyecto original) con la capacidad nativa de Claude de ver imágenes, escuchar audio, leer PDFs y video. FFmpeg (instalado en el paso 1) mejora la conversión de notas de voz para que se puedan transcribir mejor.

---

## 7. (Opcional) Que los bridges arranquen solos al prender la PC

Para no tener que abrir las dos ventanas de PowerShell manualmente cada vez:

1. Creá dos archivos `.bat`, por ejemplo `iniciar-whatsapp-1.bat` y `iniciar-whatsapp-2.bat`:

   **iniciar-whatsapp-1.bat**
   ```bat
   @echo off
   cd /d "%USERPROFILE%\Documents\whatsapp-mcp\whatsapp-bridge"
   go run .
   ```

   **iniciar-whatsapp-2.bat**
   ```bat
   @echo off
   set WHATSAPP_BRIDGE_PORT=8081
   cd /d "%USERPROFILE%\Documents\whatsapp-mcp\whatsapp-bridge-2"
   go run .
   ```

2. Presioná `Win + R`, escribí `shell:startup` y Enter — se abre la carpeta de inicio de Windows.
3. Creá un acceso directo a cada `.bat` dentro de esa carpeta.

Así, cada vez que se prenda la PC de tu mamá, los dos bridges arrancan solos (va a ver dos ventanas de consola minimizables — eso es normal, son los puentes corriendo).

---

## 8. Problemas comunes

| Problema | Solución |
|---|---|
| `gcc: command not found` al correr `go run .` | Falta CGO/MSYS2. Repetí el paso 1 y confirmá `gcc --version` |
| El QR no aparece o se corta | Achicá la ventana de fuente en PowerShell (Propiedades → Fuente) o correlo desde Windows Terminal |
| `401 Unauthorized` al usar las herramientas en Claude | Reiniciá el bridge correspondiente para que regenere `.bridge-token`, y después reiniciá Claude Desktop |
| Claude no ve ninguno de los dos servidores | Revisá que el JSON de `claude_desktop_config.json` sea válido (comas, llaves) y que las rutas con `C:\\Users\\...` usen doble backslash |
| El firewall de Windows pregunta por `go.exe` o `whatsapp-bridge.exe` | Permitir acceso en redes privadas — es tráfico local (localhost) entre el bridge y el servidor MCP |

---

## Créditos

- Proyecto base: [verygoodplugins/whatsapp-mcp](https://github.com/verygoodplugins/whatsapp-mcp) (MIT)
- Fork original: [lharries/whatsapp-mcp](https://github.com/lharries/whatsapp-mcp) por Luke Harries
