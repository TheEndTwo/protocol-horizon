# Запуск Protocol Horizon GPT-6.1

Нужен Godot **4.7.2 stable**. Лаунчер не скачивает движок и не предполагает его путь на Mac: он проверяет `GODOT_BIN`, затем `godot`/`godot4` в `PATH`, а на macOS — приложение Godot, найденное Spotlight по bundle ID `org.godotengine.godot`.

## Запуск из корня репозитория

```bash
bash ProtocolHorizonGPT61/tools/run_macos.command
```

Если Godot не найден автоматически, укажите фактический путь к исполняемому файлу, установленный на вашем Mac:

```bash
GODOT_BIN="<фактический путь к исполняемому файлу Godot 4.7.2>" bash ProtocolHorizonGPT61/tools/run_macos.command
```

Вместо Terminal можно открыть Godot, выбрать **Import**, указать `ProtocolHorizonGPT61/project.godot` и запустить проект из редактора.

## Проверки в текущей Linux-среде разработки

Установленный здесь Godot 4.7.2 stable находится по пути `/tmp/horizon-tools/Godot_v4.7.2-stable_linux.x86_64`. Команды ниже относятся к этой среде; на другой машине используйте её фактический путь к Godot.

Импорт проекта в headless-режиме:

```bash
/tmp/horizon-tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path ProtocolHorizonGPT61 --editor --import
```

Stage 0 тест:

```bash
/tmp/horizon-tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path ProtocolHorizonGPT61 --script res://tests/stage0_test.gd
```

Графический запуск проекта в текущей Linux-среде (здесь уже работает Xvfb на `:99`):

```bash
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 /tmp/horizon-tools/Godot_v4.7.2-stable_linux.x86_64 --path ProtocolHorizonGPT61 --position 0,0 --resolution 432x768 --audio-driver Dummy
```

Для ручной проверки запустите проект, нажмите **«К меню»**, затем **«Назад»** и убедитесь, что переходы между стартовой технической сценой и техническим главным меню работают.

## Границы этапа 0

Это только технический каркас запуска, переходов сцен и загрузки/проверки канонического `ContentRegistry`. Это **не** готовый игровой интерфейс: экономика, настройки и сохранение пока не реализуются; художественное оформление UI также не входит в этап 0. Для будущего формата сохранения зарезервировано имя `user://protocol_horizon_gpt61_save_v1.json` со схемой 1, но на этапе 0 файлы сохранения не записываются; это возможно только после одобрения этапа 0 и перехода к этапу 1. Запуск и проверка на macOS и iPhone не выполнялись.
