# dotnet-doc-skills

Набор из четырёх Claude Code skill'ов для документирования C#/.NET кода **с выводом на русском языке**.

| Skill | Что делает |
|---|---|
| **`doc-cs`** | Генерирует inline XML-doc комментарии (`///`) прямо в `.cs`-файлах по рекомендациям Microsoft (`summary`, `param`, `returns`, `remarks`, `exception`, `inheritdoc` и др.). |
| **`doc-md`** | Генерирует внешнюю Markdown-документацию: отдельный `.md`-файл на каждый класс. Структура папок `documentation/api/` повторяет структуру solution. Добавляет гиперссылки на унаследованные типы и на типы из других файлов проекта. |
| **`doc-db`** | Реконструирует структуру реляционной БД (Oracle) **исключительно из исходного кода**: SQL-литералов в C#, вызовов `OracleDbType.*` и обращений к `DataRow["COL"].ToInt64()/ToStr()/ToNullableInt64()`. Результат — единый `database.md` с таблицами, типами колонок и (эвристически выведенными) связями. К базе данных не подключается. |
| **`doc-folder`** | Генерирует один обзорный `README.md` в корне указанной папки — навигационную карту мульти-проектного каталога для будущего claude code и человека. Рекурсивно находит проекты (`.csproj`) и описывает каждый публичный тип кратким абзацем (назначение, логика, зависимости — без сигнатур). Структура: проекты → namespace → классы. Пишется рядом с кодом, всегда перезаписывается. |

Ориентирован на legacy ADO.NET проекты с «сырым» SQL в строковых литералах, где маппинг колонок не очевиден и не восстанавливается из EF Core.

## Установка

### Способ 1 — через marketplace (стандартный)

```text
/plugin marketplace add tdav/Auto.Documentation.Code
/plugin install dotnet-doc-skills@dotnet-doc-skills
```

**Если получаете ошибку SSH** (`Permission denied (publickey)`), выполните один раз в терминале, чтобы git использовал HTTPS вместо SSH:

```bash
git config --global url."https://github.com/".insteadOf "git@github.com:"
```

После этого повторите команды выше.

### Способ 2 — ручная установка через HTTPS (если marketplace не работает)

```bash
# Клонируем репозиторий напрямую в папку плагинов
git clone https://github.com/tdav/Auto.Documentation.Code.git "%USERPROFILE%\.claude\plugins\marketplaces\tdav-Auto.Documentation.Code"
```

Затем в Claude Code:

```text
/plugin install dotnet-doc-skills@dotnet-doc-skills
```

### Способ 3 — из локальной папки

Если репозиторий уже скачан (например, в `C:\Works_AI\Auto.Documentation.Code`):

```text
/plugin install dotnet-doc-skills@C:\Works_AI\Auto.Documentation.Code
```

---

После установки все четыре skill'а доступны во всех проектах. Вызов:

```text
/doc-cs путь к .cs-файлу, классу или папке [--force]
/doc-md путь к .cs-файлу, классу или папке (корень solution)
/doc-db путь к корню проекта или к папке DA-классов
/doc-folder путь к папке (мульти-проектной)
```

`doc-cs` и `doc-folder` помечены `disable-model-invocation: true` — массовое редактирование исходников / генерация обзора запускается только явной командой (`/doc-cs`, `/doc-folder`). `doc-db` безопасен (пишет лишь `database.md`) и может срабатывать автоматически по фразам «опиши БД», «составь database.md».

## Структура результатов (оптимизирована под поиск)

Результаты задуманы как навигируемая информационная документация — пригодная
сразу для AI/RAG, поиска в Git/IDE и статических генераторов (DocFX/MkDocs):

- **YAML-frontmatter** в каждом `.md` (`title`, `type`, `namespace`, `layer`,
  `source`, `tables`, `tags`, `summary`) — единая схема в
  [`skills/doc-md/references/frontmatter-schema.md`](skills/doc-md/references/frontmatter-schema.md).
- **Единое оглавление** `documentation/api/index.md` — точка входа со списком всех
  классов по namespace.
- **Перекрёстные ссылки код↔БД.** Класс объявляет затронутые таблицы в поле
  `tables:`, а схема БД обратно ссылается на использующие её классы — «где
  трогают таблицу X?» решается за один переход.
- **Параллелизм ≤ 10.** `doc-cs` и `doc-md` на крупных проектах распараллеливают
  работу волнами не более 10 субагентов; единая frontmatter-схема и общий реестр
  типов держат вывод консистентным.

## Структура репозитория

```text
.
├── .claude-plugin/
│   ├── marketplace.json        # регистрация marketplace (плагин в корне, source: "./")
│   └── plugin.json             # метаданные плагина
├── skills/
│   ├── doc-cs/
│   │   ├── SKILL.md
│   │   └── references/         # таблица XML-тегов, стиль-правила, примеры
│   ├── doc-md/
│   │   ├── SKILL.md
│   │   ├── references/         # единая frontmatter-схема
│   │   └── assets/             # шаблоны class.md и index.md
│   ├── doc-db/
│   │   ├── SKILL.md
│   │   ├── references/         # типы Oracle, соглашения имён, алгоритм извлечения
│   │   ├── assets/             # шаблон database.md
│   │   └── scripts/            # опциональный prescan для крупных проектов
│   └── doc-folder/
│       ├── SKILL.md
│       ├── references/         # правила описания класса для README
│       └── assets/             # шаблон readme.md
├── doc.md                      # исходное исследование и обоснование дизайна
├── IMPLEMENTATION_NOTES.md     # принятые решения по реализации
├── README.md
└── LICENSE
```

## Настройка под свой проект

`doc-db` содержит доменные эвристики (префиксы `SV_`/`TV_`, схемы `DICT`/`APP`, мультиязычные колонки `*_NAME00`..`*_NAME05`, soft-delete `*_RECORDSTATUS`). Это **дефолты** — перед первым серьёзным прогоном откройте [`skills/doc-db/references/naming-conventions.md`](skills/doc-db/references/naming-conventions.md) и приведите соглашения к вашей базе. Особенно подтвердите языковую раскладку `NAME00..NAME05`.

Качество `doc-cs` резко растёт, если добавить 3–5 эталонных примеров «до/после» из вашего реального кода в [`skills/doc-cs/references/examples-ru.md`](skills/doc-cs/references/examples-ru.md) — Claude хорошо переносит стиль из few-shot.

## Ограничения

- Связи (FK) `doc-db` выводит **эвристически** по совпадению имён и JOIN-условиям и всегда помечает словом «предположительно». Источник истины — DBA/DDL, а не этот skill.
- `doc-db` сознательно **не** подключается к БД, не читает EF Core и `.sql`-файлы — только C#-код.
- `scripts/prescan.sh` — bash-скрипт; на Windows запускается через Git Bash или WSL.

Подробное обоснование дизайна — в [`doc.md`](doc.md).

## Лицензия

[MIT](LICENSE)
