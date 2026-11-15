# CATDOKU

Proyecto creado con `glasnost new` (plantilla `ecs-welcome`, framework 2.0.0-beta.2-93-g5f95824).
Un juego mínimo con el ECS de GlasnostFWK: una nave que se mueve con las flechas
del cursor y tres drones que patrullan.

```sh
glasnost build      # compila a build/ (CATDOKU.BIN, .CDT y .DSK)
glasnost run        # abre el .DSK en el emulador: RUN"CATDOKU
glasnost test       # comprueba el proyecto y que compila
glasnost config --title "OTRO TITULO"   # cambia título, vídeo o memoria extendida
```

Tu código está en `main.s` y `common.inc`. Lo que escribe `glasnost`
(`generated/`, y las claves `name`, `amsdos_name`, `profile`, `transparency` y
`extended_memory` de `glasnost.manifest.json`) se regenera con `glasnost config`: no lo
edites a mano. Para usar un sistema del framework añade su componente
en `ecs.components` y su módulo en `modules` de `glasnost.manifest.json`, y ejecuta
`glasnost config` para regenerar lo generado. Guía paso a paso (mapa y sprites importados de PNG y TMX,
animación, colisiones): `docs/guide/first-game.md` en el SDK.

## Repositorio

Este proyecto es un repositorio Git independiente del framework y no tiene remoto.
Crea el suyo en tu hosting y enlázalo con `glasnost remote <URL>` (rechaza la URL del
framework); después, `git push -u origin main`. `glasnost update` solo usa ramas locales:
no hace fetch ni push.
