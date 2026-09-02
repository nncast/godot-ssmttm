# Footstep samples

`entities/surface_audio.gd` picks these up automatically — no inspector wiring.
Drop numbered `.wav` files into the folder for each surface:

```
assets/audio/footsteps/<surface>/walk_01.wav  walk_02.wav  ...
assets/audio/footsteps/<surface>/run_01.wav   run_02.wav   ...
```

Surfaces: `sand`, `grass`, `road`, `stairs`, `water`.
Numbering starts at `01` and is scanned up to `12`; a surface picks one at
random per step and jitters the pitch, so 4–6 variants already sound natural.

A surface with no files is silent, and a surface with only `walk_*` files
reuses those when running — so you can add packs one at a time.

Which surface a step uses comes from the level's own TileMapLayers (see
`SURFACE_LAYERS` in `surface_audio.gd`), tested in priority order:
`road` → `stairs` → `grass` → `sand` → `sandfade` → `sea`. First layer with a
tile under the player wins, so road painted over sand sounds like road.

`sea` maps to the `water` folder. The ocean *ambience* loop is separate and
already wired — it lives in `assets/audio/ambiance/` and fades in over the
last 16 tiles as you approach the `sea` layer.
