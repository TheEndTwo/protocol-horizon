# ProtocolHorizonGPT61

- Новый изолированный проект. Старые проекты и исходный ZIP не изменять.
- Этап 0 принят владельцем 09.11.2026. Сейчас разрешён только этап 1; этап 2 требует отдельной приёмки.
- Главный контракт: `../MASTER_PROMPT_GPT61_PROTOCOL_HORIZON_V9_FROM_SCRATCH.md` (09.11.2026).
- Архивные документы в `docs/source/` подчинены контракту: имя проекта ProtocolHorizonGPT61, сезон 60, стоп после каждого этапа.
- Godot 4.7.2, GDScript, 432×768, portrait, canvas_items. Без старых сцен/скриптов.
- `data/canon/` — неизменённые оригиналы; ID не переименовывать. Research/story — разные пространства имён.
- `assets/style_refs/` — только референсы, не runtime UI. WAV — прототипные.
- Схема 1 и `user://protocol_horizon_gpt61_save_v1.json`; сохранение реализуется только на этапе 1.
- После правок: импорт Godot, `--headless --path . --script tests/stage0_test.gd`; для UI нужен графический запуск и свежий скриншот.
