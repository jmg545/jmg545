# Alarma PC → Pixel

Utilidad mínima para Windows: abres un acceso directo, escribes una hora, pulsas Enter
y se crea una alarma real en el Pixel 10a. Sin `.exe`, sin servidor, sin procesos residentes.

```
┌─────────────────────────┐
│ ¿A qué hora?            │
│                         │
│         10h20           │
│                         │
└─────────────────────────┘
```

---

## Paso 1 — Arquitectura final

```
Windows                          Internet                 Pixel 10a
────────────────────────────     ─────────────────        ─────────────────────────
acceso directo
   → alarma.bat
       → powershell alarma.ps1
           ventana WinForms
           parsea "10h20"
           decide hoy/mañana
           1 POST HTTPS  ──────►  ntfy.sh/<topic>  ──FCM──►  app ntfy
           se cierra                                            │ broadcast intent
                                                                ▼
                                                            Tasker
                                                            (perfil Intent Received)
                                                                │ SET_ALARM
                                                                ▼
                                                            Reloj de Google
                                                            alarma nativa 10:20
```

Piezas, y nada más:

| Dónde | Qué | Residente |
|---|---|---|
| PC | `alarma.bat` + `alarma.ps1` + `alarma.config.ps1` | No. Vive ~2 s |
| Nube | `ntfy.sh` (servicio público gratuito, sin cuenta) | No es tuyo |
| Pixel | app **ntfy** (recibe por FCM) + **Tasker** (1 perfil, 1 tarea) | No (usa FCM, no servicio en primer plano) |

El PC envía un único POST con este cuerpo:

```json
{"token":"<secreto>","hour":10,"minute":20,"date":"2026-08-12"}
```

---

## Paso 2 — Por qué ntfy.sh y no las alternativas

| Opción | Complej. | Coste | Latencia | Fiabilidad | Apps a instalar | Servicio en marcha | Integración Tasker |
|---|---|---|---|---|---|---|---|
| **ntfy.sh** ✅ | Muy baja | 0 € | ~1 s (FCM) | Alta | ntfy (gratis, open source) | Ninguno | **Nativa**: broadcast `io.heckel.ntfy.MESSAGE_RECEIVED` → evento *Intent Received* |
| HTTP directo a Tasker (LAN) | Baja | 0 € | ~50 ms | Media | ninguna | Servidor HTTP de Tasker siempre activo | Nativa (evento *HTTP Request*) |
| Webhook genérico (IFTTT, Make, Zapier…) | Media | 0–10 € | 5 s – varios min | Media | la del servicio | El del proveedor | Indirecta |
| Join | Baja | ~5 € pago único | ~1 s | Alta | Join | Ninguno | Excelente (mismo autor que Tasker) |
| Pushbullet | Media | 0 € con límite (~500/mes) | ~2 s | Media | Pushbullet | Ninguno | Mala: hay que leer la notificación con AutoNotification |
| Pushover | Media | ~5 € por plataforma | ~2 s | Alta | Pushover | Ninguno | Mala: igual, vía notificación |
| Telegram | Alta | 0 € | 1–5 s | Alta | Telegram | Bot + polling o lectura de notificación | Mala |

**Elegida: ntfy.sh.** Es la única que cumple las cuatro cosas a la vez: gratis y sin cuenta,
sin nada corriendo ni en el PC ni (de forma permanente) en el móvil, latencia de ~1 s,
y **un evento nativo de Tasker** que recibe la orden ya troceada en variables. El PC sólo
tiene que hacer un `POST`, que en PowerShell es una línea.

**Descartadas y por qué:**

- **Join** es técnicamente igual de buena (o marginalmente mejor por venir del mismo autor
  que Tasker), pero cuesta dinero y requiere cuenta. Si algún día ntfy.sh falla, es el plan B
  y sólo hay que cambiar la URL en `alarma.config.ps1`.
- **Pushbullet / Pushover / Telegram**: ninguna entrega el mensaje *a Tasker*. Habría que
  capturar la notificación con AutoNotification o hacer polling. Más piezas, más frágil, peor latencia.
- **Webhooks tipo IFTTT/Make**: añaden un intermediario con cuenta, cuotas y latencias de
  hasta minutos. Para una alarma eso es inaceptable.

**Sobre la opción Wi-Fi directa (PC ↔ Pixel en la misma red):** *sí* es posible y es la de
menor latencia. Tasker tiene un evento **HTTP Request** que levanta un servidor HTTP en el
puerto que elijas; el PC haría el mismo `POST` a `http://<ip-del-pixel>:1821/alarma`.
Ventajas: cero nube, cero terceros, ~50 ms. Inconvenientes reales:

- Sólo funciona en casa. Fuera de la Wi-Fi no hay alarma.
- La IP del Pixel cambia salvo que reserves DHCP en el router.
- El Wi-Fi del móvil se duerme; el servidor de Tasker tiene que estar activo y el Pixel
  despierto, lo que **sí** implica algo permanente en el teléfono.

Por eso no es la opción por defecto. Pero **el código la soporta sin cambios**: sólo hay que
poner esa URL en `Endpoint` dentro de `alarma.config.ps1`. Es el mismo POST JSON.

---

## Paso 3 — Qué instalar y configurar en el Pixel

1. **App ntfy** — instálala desde **Google Play** (importante: la versión de Play usa Firebase
   y entrega al instante *sin* servicio en primer plano; la de F-Droid necesita una conexión
   permanente y consume batería).
2. Genera un nombre de *topic* aleatorio (en el PC, ver Paso 4) y en la app: **+** → escribe el
   topic → *Subscribe*.
3. **Silencia el topic** en la app (mantén pulsado sobre él → *Mute*). Así no verás notificación:
   sólo queremos que dispare Tasker.
4. Ajustes de ntfy: comprueba que **Broadcast messages** está activado (viene activado).
5. **Tasker** instalado, y en Android: *Ajustes → Aplicaciones → ntfy* y *Tasker* →
   **Batería → Sin restricciones**. Es el único ajuste que de verdad afecta a la fiabilidad.
6. Tasker ya declara el permiso `SET_ALARM`, no hay que hacer nada más.

---

## Paso 4 — Qué archivos hay en Windows

Los tres en la misma carpeta, por ejemplo `C:\Utilidades\alarma\`:

| Archivo | Para qué |
|---|---|
| `alarma.bat` | Lanzador. Es a lo que apunta el acceso directo. 3 líneas. |
| `alarma.ps1` | Todo: ventana, validación, hoy/mañana, envío. |
| `alarma.config.ps1` | Tu endpoint y tu token. **No se sube al repo.** |

`alarma.config.example.ps1` es sólo la plantilla.

No hace falta `.exe`, ni Python, ni .NET SDK, ni instalar nada: `powershell.exe` 5.1 y WinForms
ya vienen en Windows. Arranque medido: ~0,3–0,6 s con `-NoProfile`. El proceso muere al enviar.

Para generar el topic y el token, pega esto en PowerShell:

```powershell
"Endpoint = 'https://ntfy.sh/alarma-{0}'" -f [guid]::NewGuid().ToString('N')
"Token    = '{0}'"                        -f [guid]::NewGuid().ToString('N')
```

Copia las dos líneas resultantes a `alarma.config.ps1`.

---

## Paso 5 — Contenido de los archivos

Están en esta carpeta:

- [`alarma.bat`](alarma.bat)
- [`alarma.ps1`](alarma.ps1)
- [`alarma.config.example.ps1`](alarma.config.example.ps1) → cópialo a `alarma.config.ps1`

Lo único que hay que editar es `alarma.config.ps1`.

> **Nota de codificación:** `alarma.ps1` está guardado en **UTF-8 con BOM**. Es obligatorio para
> que Windows PowerShell 5.1 muestre bien la `¿` y la `é` de «¿A qué hora?». Si lo editas, guarda
> con esa misma codificación (Notepad: *Guardar como → UTF-8 con BOM*; VS Code: «UTF-8 with BOM»).

---

## Paso 6 — Crear el acceso directo de Windows

1. Botón derecho en el escritorio → **Nuevo → Acceso directo**.
2. Ubicación: `C:\Utilidades\alarma\alarma.bat`
3. Nombre: `Alarma`.
4. Botón derecho en el acceso directo → **Propiedades**:
   - **Ejecutar: Minimizada** ← evita ver la ventana negra de `cmd`.
   - **Tecla de método abreviado**: por ejemplo `Ctrl + Alt + A`, para abrirla sin ratón.
   - *Cambiar icono…* si quieres uno de reloj (`%SystemRoot%\System32\imageres.dll`).

Si te molesta el parpadeo de `cmd` (~0,2 s), cambia el **Destino** del acceso directo por:

```
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Utilidades\alarma\alarma.ps1"
```

y ya no hay `.bat` de por medio ni parpadeo alguno. El `.bat` sigue ahí para quien prefiera
lanzarlo a mano.

---

## Paso 7 — Configurar Tasker

### Perfil

*Profile* → **Event → System → Intent Received**
- **Action:** `io.heckel.ntfy.MESSAGE_RECEIVED`

### Tarea: «Crear alarma»

| # | Acción | Ajustes |
|---|---|---|
| 1 | *Variables → Variable Set* | Name `%json`, To `%message`, marcar **Structure Output (JSON, etc)** |
| 2 | *Task → Stop* | **If** `%json.token` **≠** `<tu token>` |
| 3 | *System → Send Intent* | Action `android.intent.action.SET_ALARM`<br>Extra `android.intent.extra.alarm.HOUR:%json.hour`<br>Extra `android.intent.extra.alarm.MINUTES:%json.minute`<br>Extra `android.intent.extra.alarm.SKIP_UI:true`<br>Package `com.google.android.deskclock`<br>Target **Activity** |
| 4 | *Alert → Flash* (opcional) | `Alarma %json.hour:%json.minute` |

Detalles que importan:

- **Los extras llegan como variables locales**: `%message`, `%topic`, `%title`, `%priority`.
  Si dudas, pon primero un *Flash `%message`* y comprueba que ves el JSON.
- **`SET_ALARM` es la forma correcta y más fiable** de crear una alarma *nativa*: es la API
  pública de Android (`AlarmClock.ACTION_SET_ALARM`), la implementa el Reloj de Google, no
  necesita root ni plugins, y con `SKIP_UI:true` crea la alarma sin abrir ninguna pantalla.
- **Tasker convierte solo los extras al tipo correcto**: si el valor se puede leer como entero
  o booleano, lo envía como `int`/`boolean`, que es justo lo que `SET_ALARM` exige. Por eso
  `HOUR:%json.hour` funciona.
- **Sobre la fecha:** `SET_ALARM` acepta hora y minuto, **no fecha**. El Reloj programa siempre
  la *próxima* aparición de esa hora — es decir, hoy si aún no ha pasado y mañana si ya pasó,
  exactamente la misma regla que aplica el PC. El campo `date` del JSON viaja como confirmación
  explícita y sirve para descartar mensajes viejos; si algún día quieres una alarma a más de
  24 h vista, ahí es donde habría que cambiar el enfoque.

<details>
<summary>Plan B si tu ROM no acepta los extras enteros de <em>Send Intent</em></summary>

Sustituye la acción 3 por cinco *Java Function*, que fuerzan el tipo explícitamente:

1. `Return: intent` — `new Intent(String)` con `android.intent.action.SET_ALARM`
2. `intent.setFlags(int)` → `268435456` *(FLAG_ACTIVITY_NEW_TASK)*
3. `intent.putExtra(String, int)` → `android.intent.extra.alarm.HOUR`, `%json.hour`
4. `intent.putExtra(String, int)` → `android.intent.extra.alarm.MINUTES`, `%json.minute`
5. `intent.putExtra(String, boolean)` → `android.intent.extra.alarm.SKIP_UI`, `true`
6. `CONTEXT.startActivity(Intent)` → `intent`

Y si el JSON estructurado te da problemas, cambia el formato a texto plano en `alarma.ps1`
(`token|fecha|hora|minuto`) y usa *Variable Split* con separador `|`.
</details>

### Confirmación opcional PC ← Pixel

Añade al final de la tarea un *Net → HTTP Request*: `POST` a
`https://ntfy.sh/<tu-topic>-ok` con cuerpo `ok %json.hour:%json.minute`. No es necesario para
que funcione; sólo si quieres verlo desde el PC.

---

## Paso 8 — Prueba completa

### Lo que ya está verificado (ejecutado de verdad)

Parseo, rangos y regla hoy/mañana, con `-DryRun` (fecha del sistema: **2026-08-11 04:18**):

```
'10h20'    -> {"token":"...","hour":10,"minute":20,"date":"2026-08-11"}
'10:20'    -> {"token":"...","hour":10,"minute":20,"date":"2026-08-11"}
'1020'     -> {"token":"...","hour":10,"minute":20,"date":"2026-08-11"}
'15h'      -> {"token":"...","hour":15,"minute":0, "date":"2026-08-11"}
'7h'       -> {"token":"...","hour":7, "minute":0, "date":"2026-08-11"}
'7:45'     -> {"token":"...","hour":7, "minute":45,"date":"2026-08-11"}
'10 h 20'  -> {"token":"...","hour":10,"minute":20,"date":"2026-08-11"}
'930'      -> {"token":"...","hour":9, "minute":30,"date":"2026-08-11"}
'9'        -> {"token":"...","hour":9, "minute":0, "date":"2026-08-11"}
'abc'      -> ERROR: No entiendo 'abc'. Ejemplos: 10h20, 10:20, 1020, 15h, 7h45.
'25h'      -> ERROR: Hora fuera de rango: 25 (debe ser 0-23).
'12h90'    -> ERROR: Minutos fuera de rango: 90 (deben ser 0-59).
'99:99'    -> ERROR: Hora fuera de rango: 99 (debe ser 0-23).
```

Y el salto de día (siendo las 04:18):

```
'3h'    -> date 2026-08-12   (ya ha pasado hoy → mañana)
'4:18'  -> date 2026-08-12   (justo ahora → mañana)
'4:19'  -> date 2026-08-11   (aún no ha llegado → hoy)
'23h59' -> date 2026-08-11
```

### Lo que falta por probar desde tu PC

El envío real por red **no se pudo ejecutar** desde el entorno donde se escribió esto: su proxy
de salida deniega `ntfy.sh` (403 en el CONNECT). La lógica y la construcción de la petición
están probadas; el salto de red hay que confirmarlo en el PC, así:

**Prueba 1 — transporte (sin ventana, sin Tasker).** En el Pixel abre la app ntfy suscrita al
topic y *quítale* el mute un momento. En el PC:

```powershell
cd C:\Utilidades\alarma
.\alarma.ps1 -Hora "10h20"
```

Debe imprimir el JSON y en el Pixel debe llegar una notificación con ese JSON en ~1 s.
Vuelve a silenciar el topic.

**Prueba 2 — Tasker.** Con Tasker configurado y el topic silenciado, repite el comando.
No debe verse notificación, pero el Reloj debe tener una alarma nueva a las 10:20.

**Prueba 3 — la real.**

```
doble clic en el acceso directo (o Ctrl+Alt+A)
  → aparece la ventana con el cursor ya dentro
  → escribes  10h20
  → Enter
  → la ventana desaparece
  → ~1 s después, Reloj del Pixel: alarma 10:20 activada
```

**Prueba 4 — error.** Escribe `25h` y Enter: la ventana **no** se cierra y muestra
«Hora fuera de rango: 25 (debe ser 0-23)». `Esc` cierra sin enviar.

### Si algo falla

| Síntoma | Dónde mirar |
|---|---|
| No aparece la ventana | Ejecuta `alarma.ps1` desde una consola PowerShell y lee el error |
| «Falta alarma.config.ps1» | No copiaste la plantilla |
| El PC envía pero el móvil no recibe | Topic distinto en PC y app; o ntfy con restricción de batería |
| Llega la notificación pero no hay alarma | Falla el perfil de Tasker: *Flash `%message`* para ver si dispara |
| Dispara Tasker pero no se crea la alarma | Extras del intent: usa el «Plan B» de Java Function |

---

## Seguridad

**Dónde vive el secreto.** En `alarma.config.ps1`, texto plano, junto al script, y en Tasker
(acción 2 de la tarea). No aparece nunca en la ventana ni en el `.bat`. Está en `.gitignore`,
así que no se sube al repositorio.

**Qué protege y qué no.**

- No abres ningún puerto: ni en el PC ni en el Pixel. Ambos son *clientes* que hablan hacia
  fuera por HTTPS. Ésta es la ventaja de seguridad grande frente a montar un endpoint propio.
- El topic de ntfy.sh es un secreto de ~128 bits (un GUID). En el servidor público de ntfy no
  hay ACL en el plan gratuito: quien conozca el nombre del topic puede publicar y leer en él.
  Adivinarlo por fuerza bruta no es realista.
- El `token` dentro del JSON es una segunda barrera: aunque alguien acertara el topic, Tasker
  descarta cualquier mensaje sin el token correcto. Ojo: quien *escuche* el topic sí vería el
  token; entonces la protección vuelve a ser el secreto del topic.
- **Riesgo residual honesto:** si el topic se filtrase (lo pegas en algún sitio, se te cuela en
  una captura), un tercero podría crear alarmas en tu móvil. Molesto, no grave — no hay datos
  personales en el mensaje, sólo una hora. Se arregla en 10 segundos: genera otro topic, cámbialo
  en `alarma.config.ps1` y en la app.
- ntfy.sh ve el contenido (hora, minuto, token). No hay cifrado extremo a extremo. Como el
  contenido es «10:20», el impacto es nulo.
- Si aun así quieres cero terceros: usa el modo LAN del Paso 2 (`Endpoint` apuntando al servidor
  HTTP de Tasker), que no sale de tu red — a cambio de que sólo funcione en casa.
