# DungeonClear CMaNGOS

Addon de control visual para **World of Warcraft 1.12.1** que permite manejar
DungeonClear en un servidor CMaNGOS con PlayerBots compatible.

La interfaz permite confirmar el bot tanque del grupo, iniciar una ruta,
pausar, reanudar, detener, reintentar, consultar el estado y administrar las
rutas publicadas por el servidor.

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

## Versión

Versión publicada: **0.7.0-routes-r1**.
