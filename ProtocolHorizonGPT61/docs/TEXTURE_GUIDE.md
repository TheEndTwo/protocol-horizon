# Placeholder texture replacement guide

The art under **assets/placeholders/** is original, intentionally simple vector placeholder art. Replace the SVG contents in place to preserve the paths loaded by **components/EarthCanvas.gd**; the component does not depend on the drawings' internal IDs or colors.

| Asset | Use | Preferred replacement canvas | Alpha and safe margin |
|---|---|---:|---|
| base_panorama.svg | Wide Earth base terrain and distant industrial horizon | 1200 × 840 | Opaque/full bleed; keep the horizon around the upper third |
| fe_rock_face.svg | Fe iron-rock mine face | 1200 × 840 | Opaque/full bleed; leave the central rock face readable |
| pd_geology_lens.svg | Pd geological lens / cutaway | 1200 × 840 | Opaque/full bleed; keep the lens near the center |
| ir_vertical_drill.svg | Ir vertical drill and cooling site | 1200 × 840 | Opaque/full bleed; keep the shaft and cooling equipment distinct |
| rail_line.svg | Base transport rail and site foreground rail | 1200 × 180 | Transparent; reserve about 4% at each edge |
| fe_horizon_ledge.svg | Repeated Fe depth ledges | 720 × 150 | Transparent; keep important detail within the middle 84% |
| weak_point.svg | D01 Fe weak-point target marker | 64 × 64 | Transparent; preserve the dark outer ring and bright center for contrast |
| building_*.svg | Ten individual base-location structures | 192 × 160 | Transparent; retain about 10% clear margin |
| worker_miner.svg | Hired worker with pickaxe | 160 × 192 | Transparent; retain about 12% clear margin |
| machine_drill.svg, machine_loader.svg | Purchased site equipment | 256 × 192 | Transparent; retain about 10% clear margin |

The base and site backgrounds use aspect-cover scaling. Keep important landmarks away from the outer 8% because a wider or taller canvas may crop the edges. Transparent sprites use aspect-preserving scaling and can have generous empty margins; keep their subject centered and do not bake captions, buttons, counters, or game-state badges into the art.

The base-location textures are separate so a single facility can be redrawn without changing the other hotspots. Preserve these filenames and the existing SVG alpha channel when replacing them. SVG is convenient for the current placeholders; a raster replacement can use the same stem and .png extension only after updating its resource path in EarthCanvas.gd.

EarthCanvas.is_weak_hit(position) accepts a canvas-local tap position and returns true only inside the current Fe weak-point target after canonical research D01 is active. Connect mine_hit(position) without changing its Vector2 payload; the receiver can pass canvas.is_weak_hit(position) as the tap precision value.

## Замена арта через JSON

Чтобы оставить исходные заглушки в покое, положите PNG в assets/custom/ и укажите переопределение в data/art_overrides.json. Ключ — имя файла-заглушки без расширения; значение — полный res://-путь к пользовательской текстуре:

    {
      "fe_rock_face": "res://assets/custom/fe.png",
      "building_mine": "res://assets/custom/building_mine.png"
    }

EarthCanvas передаёт каждый путь через ArtLibrary.texture_for(). Библиотека проверяет ресурс и возвращает исходную заглушку, если override отсутствует или недоступен. После изменения JSON или PNG перезапустите игру: текстуры и файл переопределений кэшируются на время процесса. Godot должен сначала импортировать новые PNG.

Для PNG с прозрачностью используйте чистый край без чёрной или белой подложки. Premultiplied alpha должна соответствовать настройкам импорта/композитинга проекта; не премультиплицируйте уже премультиплицированные пиксели повторно. На прозрачных спрайтах держите примерно 10–12% безопасного поля, а важные детали panoramas — не ближе 8% к краю кадра, чтобы их не обрезало при aspect-cover.
