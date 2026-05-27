# Заметки по реализации

Зафиксированные решения при реализации дизайна из [`doc.md`](doc.md).

## Что реализовано

Три Claude Code skill'а (`doc-cs` — inline XML-doc, `doc-md` — внешний Markdown,
`doc-db` — схема БД) оформлены как **публикуемый плагин marketplace** для GitHub,
а не как локальные `.claude/skills/`.

## Ключевые решения

### 1. Формат публикации — отклонение от doc.md
`doc.md` проектировал локальные `.claude/skills/doc-cs` и `.claude/skills/doc-db`.
По требованию опубликовать на GitHub структура изменена на стандартный Claude
Code plugin:

```
.claude-plugin/marketplace.json   (source: "./")
.claude-plugin/plugin.json
skills/doc-cs/   skills/doc-md/   skills/doc-db/
```

Формат сверен с реальными рабочими плагинами на машине (`diagram-design` —
single-plugin в корне; `skill-creator` — подтверждает авто-обнаружение
`skills/<name>/`). Поля манифестов: обязательны `name`, `description`.

### 2. Наименования
- marketplace = `dotnet-doc-skills`, plugin = `dotnet-doc-skills`.
- skills: `doc-cs`, `doc-md`, `doc-db` (`doc-md` выделен из исходного `doccs`).
- Публикация: `github.com/tdav/Auto.Documentation.Code`.
- Установка: `/plugin marketplace add tdav/Auto.Documentation.Code` →
  `/plugin install dotnet-doc-skills@dotnet-doc-skills`.

### 3. Конвенция чтения колонок — подтверждена
Пользователь подтвердил, что в целевом Oracle-коде колонки читаются как
`dr["COL"].ToInt64()/ToStr()/ToNullableInt64()`. Поэтому regex в
`extraction-algorithm.md` оставлены без изменений.

### 4. Доменные эвристики — дефолты, не факты
Префиксы `SV_`/`TV_`, схемы `DICT`/`APP`, языковая раскладка `NAME00..05`
(мультиязычная локализация) — **гипотезы из doc.md**. Вынесены в настраиваемый
`skills/doc-db/references/naming-conventions.md` с явной пометкой «подтвердите».
FK всегда маркируются «предположительно».

### 5. prescan.sh
Bash-скрипт (3-й уровень прогрессивного раскрытия). На Windows запускается через
Git Bash или WSL — отмечено в README. Выдаёт сырьё `_tmp/sql-facts.txt`, которое
Claude агрегирует.

### 6. Структура вывода под поиск (итерация оптимизации)
По требованию «использовать результаты как информационную документацию» добавлено
(универсально — для AI/RAG, поиска в Git и DocFX/MkDocs одновременно):
- **Единая YAML-frontmatter-схема** — `skills/doc-md/references/frontmatter-schema.md`;
  обязательна для всех генерируемых `.md` (поля `title/type/namespace/layer/source/tables/tags/summary`).
- **Оглавление** `documentation/api/index.md` — единая точка входа (генерирует `doc-md`).
- **Мост код↔БД** — поле `tables:` в классах ↔ обратные ссылки на классы в `database.md`.
- **Параллелизм ≤ 10** в `doc-cs`/`doc-md`: Pass 1 (реестр типов) последовательно
  в главной сессии, Pass 2/3 — волнами субагентов; frontmatter-схема и реестр
  передаются каждому субагенту для консистентности. `doc-db` — без параллелизма
  (агрегация). В `allowed-tools` `doc-cs`/`doc-md` добавлен `Task`.
- **Идемпотентность `doc-cs`:** файл пропускается, если у класса уже есть
  `/// <summary>` (флаг `--force` отменяет); отсев — до диспетча субагентов.
- Сознательно отложено (YAGNI): отдельный JSON-индекс, конфиги DocFX/MkDocs,
  глоссарий — добавятся, когда выбор генератора/RAG будет сделан.

## Отклонения от стандартного brainstorming-флоу

Запущен был `/superpowers:brainstorming`, но `doc.md` уже содержал законченную
спецификацию (560 строк, полный текст обоих SKILL.md). Поэтому:
- **Новый spec в `docs/superpowers/specs/` не создавался** — `doc.md` и есть spec.
- **`writing-plans` не вызывался** — план дублировал бы `doc.md`; реализация
  велась напрямую по нему.
- Эти заметки заменяют формальный spec, фиксируя только решения, которых в
  `doc.md` не было (формат публикации, имена, координаты GitHub).

## Что сделать перед публикацией

1. Заполнить `skills/doc-db/references/naming-conventions.md` под свою базу
   (особенно раскладку `NAME00..05`).
2. ✅ Примеры в `examples-ru.md` добавлены (5 «до/после» из реального кода `Sample`).
3. Прогнать `/doc-cs` и `/doc-db` на одном DA-классе, проверить качество.
4. Запушить в репозиторий `tdav/Auto.Documentation.Code` на GitHub
   (push выполняется вручную — этот шаг не автоматизирован).

## Решённые вопросы

- **Единый корень вывода `documentation/`:** `doc-md` пишет классы в
  `documentation/api/` (+ `index.md`), `doc-db` — `documentation/database.md`.
  Cross-link из схемы к классам имеет вид `api/<mirror>/Class.md`.
- **`doc-cs` — только inline `///`:** вся внешняя Markdown-генерация убрана из
  `doc-cs` и оставлена за `doc-md` (дублирование устранено).
