# DungeonClear CMaNGOS

Addon de control visual para **World of Warcraft 1.12.1** que permite manejar
DungeonClear en un servidor CMaNGOS con PlayerBots compatible.

La interfaz permite confirmar el bot tanque del grupo, iniciar una ruta,
pausar, reanudar, detener, reintentar, consultar el estado y administrar las
rutas publicadas por el servidor.

El repositorio también incluye las rutas JSON vigentes y el esquema usado por
el cargador de DungeonClear.

## Requisitos

- Cliente de World of Warcraft 1.12.1 (`Interface: 11200`).
- Servidor CMaNGOS con PlayerBots y el protocolo DungeonClear instalado.
- Un grupo con PlayerBots y exactamente un tanque reconocido por el servidor.

El addon es la interfaz de usuario; la lógica de navegación y la validación de
rutas permanecen en el servidor. No funciona por sí solo en un servidor CMaNGOS
sin la implementación de DungeonClear.

## Instalación

1. Descarga o clona este repositorio.
2. Copia la carpeta `DungeonClearCMangos` dentro de
   `World of Warcraft/Interface/AddOns/`.
3. Comprueba que la estructura final sea:

   ```text
   Interface/AddOns/DungeonClearCMangos/
   ├── DungeonClearCMangos.toc
   └── DungeonClearCMangos.lua
   ```

4. Inicia el juego y activa **DungeonClear CMaNGOS** en la pantalla de addons.
5. Entra con el personaje que controlará al grupo y escribe `/dc`.

### Rutas del servidor

Copia los archivos de `server/routes/` al directorio de rutas configurado por
DungeonClear. En una integración estándar del módulo PlayerBots, la ubicación
de fuente es:

```text
src/modules/PlayerBots/playerbot/dungeonclear/routes/
```

Copia `server/schema/dungeon-route.v1.schema.json` en el subdirectorio
`routes/schema/`. Conserva los nombres de archivo; cada `id` es utilizado por
el addon y por los comandos del servidor.

Rutas incluidas:

- `deadmines.v1`
- `scarlet_monastery.graveyard.v1`
- `scarlet_monastery.library.v1`

Las rutas y el esquema necesitan una implementación reciente de DungeonClear.
Antes de usarlas en producción se deben compilar las pruebas del servidor y
realizar un recorrido normal dentro del juego, sin teletransportes ni saltos
manuales.

## Uso básico

1. Forma el grupo con los PlayerBots.
2. Pulsa **Confirmar tank** o ejecuta `/dc tank`.
3. Pulsa **Actualizar** para obtener el estado más reciente.
4. Selecciona una ruta válida, por ejemplo `deadmines.v1`.
5. Pulsa **Iniciar**.

Los controles sensibles solo se habilitan cuando el tanque fue confirmado,
el estado del servidor es reciente y no existe otra orden pendiente. **Detener**
y **Saltar** requieren una segunda pulsación dentro de cuatro segundos.

## Comandos

| Comando | Descripción |
| --- | --- |
| `/dc` | Muestra u oculta la ventana. |
| `/dc show` / `/dc hide` | Muestra u oculta la ventana. |
| `/dc tank` | Busca y confirma el único tanque del grupo. |
| `/dc on [ruta]` | Inicia DungeonClear, opcionalmente con una ruta explícita. |
| `/dc off` | Detiene la ejecución. |
| `/dc pause` / `/dc resume` | Pausa o reanuda la ejecución. |
| `/dc retry` / `/dc skip` | Reintenta o salta el paso actual. |
| `/dc status` | Solicita el estado actual. |
| `/dc route list` | Solicita al servidor la lista de rutas. |
| `/dc route show <id>` | Muestra información de una ruta. |
| `/dc route validate <id>` | Solicita validar una ruta. |
| `/dc route reload <id>` | Recarga una ruta; requiere permisos en el servidor. |
| `/dc debugui` | Muestra u oculta el panel de diagnóstico local. |
| `/dc proto` | Imprime el estado del protocolo. |
| `/dc resetpos` | Restaura la posición de la ventana. |
| `/dc help` | Muestra la ayuda en el chat. |

## Protocolo y seguridad

Las órdenes de ejecución usan mensajes privados versionados con sesión,
secuencia y revisión. El addon valida el remitente y descarta respuestas
caducadas o pertenecientes a otra sesión. Las consultas de rutas usan el canal
de comandos compatible con PlayerBots y son únicamente informativas: el
servidor sigue siendo la autoridad para permisos, disponibilidad y validez.

La configuración local se guarda en `DungeonClearCMangosDB`. Actualizar el
addon no requiere borrar las variables guardadas.

## Pruebas

`tests/UiTests.lua` ejecuta el addon contra una simulación limitada de la API
de WoW Vanilla. Requiere Lua 5.0.x:

```text
lua tests/UiTests.lua DungeonClearCMangos/DungeonClearCMangos.lua
```

La prueba cubre 58 verificaciones del flujo de tanque, controles, caducidad de
mensajes, selección de rutas y rechazo de entradas inválidas.

## Prompt de integración para una IA

Copia el siguiente prompt y entrégaselo a una IA con acceso al repositorio de
CMaNGOS/PlayerBots que deseas modificar:

```text
Integra el repositorio https://github.com/luisval16/DungeonClear en este árbol
de CMaNGOS Classic con PlayerBots.

Objetivo:
1. Instalar DungeonClearCMangos como addon del cliente WoW 1.12.1, sin modificar
   ni borrar sus SavedVariables existentes.
2. Integrar los JSON de server/routes y el esquema de server/schema en el
   directorio de rutas que realmente utiliza DungeonClear en PlayerBots.
3. Comprobar que el backend existente implementa el protocolo que usa el addon:
   comandos privados `dc v1`, respuestas `DC1|...`, confirmación de tanque y
   comandos `dc route list/show/validate/reload`.
4. Si falta código del backend, no inventes una integración superficial: primero
   localiza la arquitectura, CMake, registros de acciones/triggers, cargador JSON,
   máquina de estados, telemetría y configuración de PlayerBots. Presenta las
   incompatibilidades y agrega únicamente la implementación necesaria siguiendo
   los patrones y la ABI del árbol de destino.

Reglas de trabajo:
- Inspecciona el repositorio de destino antes de editar y preserva cambios ajenos.
- Haz una copia recuperable de cada archivo instalado que vaya a sustituirse.
- No copies rutas antiguas ni mantengas duplicados con el mismo `id`.
- Usa `server/schema/dungeon-route.v1.schema.json` como contrato y valida todos
  los JSON. Los campos o políticas desconocidos deben fallar de forma segura.
- El servidor es la autoridad para ruta, permisos, grupo, tanque, mapa, instancia,
  estado, revisión y finalización; el addon nunca debe inventar esos datos.
- Conserva los identificadores exactos de ruta y los nombres de archivo.
- No inicies ni detengas el servidor o el cliente sin autorización expresa.
- No uses teletransporte, summon, skip ni movimiento manual como prueba de éxito.
- Compila primero las pruebas de DungeonClear y las regresiones de PlayerBots.
- Verifica Deadmines, Scarlet Monastery Graveyard y Scarlet Monastery Library.
- Para Library, conserva la política de seguridad de Arcanist Doan y exige una
  comprobación real del retiro ante Arcane Bubble/Detonation.
- Trata una validación técnica como distinta de una prueba completa dentro del
  juego; documenta claramente todo lo que quede pendiente.

Entrega:
- Lista exacta de archivos añadidos o modificados.
- Ubicación final del addon, rutas y esquema.
- Resultado de validación JSON, compilación y pruebas.
- Evidencia de que no quedaron versiones antiguas o rutas duplicadas.
- Instrucciones de rollback y pasos manuales pendientes para la prueba en juego.
```

## Versión

Versión publicada: **0.7.0-routes-r1**.
