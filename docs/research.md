# Исследование и проект Claude Code skill для автодокументации .NET/C# проектов (Oracle ADO.NET, raw SQL)

## TL;DR

- **Готовых Claude Code skill'ов, решающих именно эту задачу (русскоязычные XML-doc + реверс схемы Oracle из строковых SQL-литералов и `DataRow["…"]`-мэппингов), не существует.** Релевантные .NET-skill-каталоги — `Aaronontheweb/dotnet-skills` (31 skill, согласно README репозитория `dotnet-skills-evals`), `wshaddix/dotnet-skills` (167 skill'ов и 16 специализированных агентов, согласно их README), `managedcode/dotnet-skills`, codewithmukesh «.NET Claude Kit» (47 skill'ов, 10 specialist agents, 15 Roslyn-MCP tools для .NET 10/C# 14, согласно codewithmukesh.com/resources/dotnet-claude-kit), `ClaudSkills/dotnet-development`, плюс официальный `anthropics/skills` — покрывают coding standards, EF Core, тестирование и DocFX-сборку, но ни один не нацелен на (а) русскоязычную XML-doc генерацию и (б) восстановление схемы БД из сырого ADO.NET кода. Из готового переиспользуется только структура skill-creator от Anthropic.
- **Дизайн: ОДИН плагин-каталог с ДВУМЯ независимыми skill-директориями (`doccs/SKILL.md` и `docmd/SKILL.md`), а не один skill с двумя режимами.** Прямое обоснование — из «SKILL.md Spec: Every Field and Frontmatter Key» (agensi.io/learn/skill-md-format-reference): *«Keep it focused. A skill should do one thing well. A 2,000-word skill that covers code review, testing, deployment, and documentation will underperform four separate 500-word skills.»* Плюс у двух задач принципиально разные `allowed-tools`, разные политики триггера и разные триггер-фразы.
- **Извлечение схемы из C#-кода — двухпроходный гибрид regex + LLM-склейка.** Источник истины №1 — `INSERT INTO TABLE (col,col,…) VALUES (:p1,:p2,…)`-литералы (точный список и порядок колонок). Типы определяются по `OracleDbType.*` параметров и `dr["COL"].ToInt64()/ToStr()/ToDateTime()/ToNullableInt64()` конвертерам. PK выводится по соглашению `<PFX>_ID`; FK — эвристически по совпадению имён колонок с PK других таблиц и по JOIN-условиям. Все выведенные FK помечаются словом «**предположительно**» — это сознательный честный хедж.

## Key Findings

### 1. Существующие Claude Code skill'ы

| Каталог / skill | Содержимое | Можно ли переиспользовать |
|---|---|---|
| `anthropics/skills` (официальный) | `skill-creator`, `docx`, `pdf`, `pptx`, `xlsx`, `mcp-builder`, `brand-guidelines`, `webapp-testing` | Шаблон директории и стиль инструкций — да. C#-skill нет. |
| `Aaronontheweb/dotnet-skills` | 31 skill (точное число — из README `Aaronontheweb/dotnet-skills-evals`): `modern-csharp-coding-standards`, `efcore-patterns`, `docfx-specialist`, `dotnet-slopwatch`, спецагенты по перформансу/concurrency | `docfx-specialist` полезен как ориентир по тону, но он про *сборку* DocFX, а не *генерацию* XML-doc. |
| `wshaddix/dotnet-skills` | 167 skills + 16 specialized agents (README: «A comprehensive Claude Code plugin with 167 skills and 16 specialized agents for professional .NET development») | Самый широкий каталог. Узко-документационных skill'ов нет; `csharp-api-design` — полезен как стилевой ориентир. |
| `managedcode/dotnet-skills` | Кросс-агентный (Claude/Copilot/Codex/Gemini), MSBuild/static-deps-scanner | Не про doc-генерацию. |
| codewithmukesh «.NET Claude Kit» | «47 curated skills, 10 specialist agents, 16 slash commands, 10 always-loaded rules, 15 Roslyn-powered MCP tools, 7 automation hooks, and 5 project templates — all built for .NET 10 and C# 14» (codewithmukesh.com) | Roslyn-MCP инструменты потенциально полезны для точного парсинга C#, но платформа .NET 10/C# 14 несовместима «как есть» с legacy. |
| `ClaudSkills/dotnet-development` | Один общий skill | Слишком общий. |
| Классические doc-инструменты (GhostDoc, Sandcastle/SHFB, DocFX, Doxygen, dotnet-document, VSdocman, AtomineerUtils) | Шаблонная генерация по имени метода + рендер XML-doc → HTML/CHM | **Антипаттерн для `<summary>`:** GhostDoc известен тем, что `GetUserById` превращает в «Gets the user by id» — тавтология. DocFX полезен как downstream-потребитель сгенерированных нами XML-комментариев. |

**Вывод:** переиспользовать целиком нечего; структуру директории, frontmatter и принцип прогрессивного раскрытия берём у `anthropics/skills/skill-creator`.

### 2. Microsoft рекомендованные XML-теги (источник: learn.microsoft.com/ru-ru/dotnet/csharp/language-reference/xmldoc/recommended-tags)

Канонический набор тегов, который skill обязан знать:

| Тег | Назначение | Применяется к |
|---|---|---|
| `<summary>` | Краткое описание (для IntelliSense) | Любой публичный член |
| `<remarks>` | Развёрнутые сведения; Markdown в `CDATA` для DocFX | Тип, метод, свойство |
| `<param name="x">` | Описание параметра; имя обязано совпадать с сигнатурой (иначе CS1572/CS1573) | Метод/конструктор |
| `<paramref name="x"/>` | Ссылка на параметр внутри текста | Внутри `<summary>`/`<remarks>` |
| `<returns>` | Описание возвращаемого значения | Метод |
| `<exception cref="T">` | Какие исключения и в каких случаях | Метод/свойство/индексатор/событие |
| `<value>` | Что представляет значение свойства | Свойство |
| `<typeparam name="T">` | Описание параметра-типа дженерика | Generic |
| `<typeparamref name="T"/>` | Ссылка на параметр-тип | Внутри текста |
| `<example>` + `<code>` | Пример использования + кодовый блок | Метод/тип |
| `<c>` | Инлайн-код | Внутри текста |
| `<see cref="…"/>`, `<see href="…">`, `<see langword="…"/>` | Ссылка на код / URL / ключевое слово | Внутри текста |
| `<seealso cref="…"/>` | Ссылка в разделе «См. также» | Любой |
| `<para>` / `<br/>` | Абзац / перенос | Внутри текста |
| `<list type="bullet\|number\|table">` | Списки/таблицы (DocFX v2 поддерживает ровно 2 колонки в `table` — issue dotnet/docfx#5492) | Внутри текста |
| `<inheritdoc cref="…" path="…"/>` | Наследование документации | Override-ы, реализации интерфейсов |
| `<include file="…" path="…"/>` | Подключение комментариев из внешнего XML | Любой |

Ключевые правила Microsoft, которые skill переносит как мягкие требования:

- Документировать все публичные типы и их публичные члены; приватные — опционально.
- Минимум — `<summary>`; полные предложения, точка в конце.
- При мульти-параметрах — несколько `<param>` (иначе предупреждение компилятора).
- HTML-теги `<b>`, `<i>`, `<u>`, `<br/>`, `<a>` валидны.
- Экранирование: `<` → `&lt;`, `>` → `&gt;`.

**Важный нюанс `<inheritdoc/>`:** Visual Studio автонаследует доку в IntelliSense и Quick Info, но компилятор НЕ кладёт это в выходной XML-файл — для NuGet-публикации тег нужен явно. Это прямо указано на странице Microsoft Learn: *«это автоматическое наследование применяется только в Visual Studio IDE и не влияет на XML-файл документации, созданный компилятором»*.

### 3. Habr 102177 (Гайдар, «Создание документации в .NET»)

Прямой fetch не прошёл (read timeout), но контент извлечён через snippet'ы web_search. Ключевые тезисы автора, учтённые в skill:

- Документацию писать **во второй половине** разработки, когда API стабилен.
- Включать в `.csproj`: `<GenerateDocumentationFile>true</GenerateDocumentationFile>` (по умолчанию выключено).
- Сборка офлайн-доки — Sandcastle + Sandcastle Help File Builder (chm-формат).
- GhostDoc — как ускоритель *ввода* XML-разметки, но автор фактически признаёт, что прозу нужно писать самому.

### 4. Reddit r/csharp/comments/1ehijwv

> ⚠️ **Содержимое треда мне получить не удалось.** Reddit блокирует прямой fetch (`SITE_BLOCKED`), зеркала (`old.reddit.com`, `libreddit`, `.json` endpoint) — `PERMISSIONS_ERROR`, web_search не вернул ни одного фрагмента, индексирующего этот тред. Если содержимое треда критично, его нужно достать вручную (например, через archive.org) и при необходимости скорректировать стилевые правила skill'а.

Поэтому раздел «community best practices» построен на смежных источниках (Microsoft Learn, Habr 102177, Red Gate Simple Talk «.NET Code Documentation with Sandcastle», блог JetBrains, agensi.io). Общеизвестные выводы (которые не выдаются за цитаты из конкретного треда):

- **Не дублировать имя метода в `<summary>`.** `GetUserById` → плохо: «Получает пользователя по идентификатору». Хорошо: «Загружает запись `DICT.SV_ITEM` по первичному ключу `SV_ID`; используется при отрисовке дерева доступов в клиентском приложении оператора».
- **XML-doc оправдан для публичного API** (NuGet/SDK) и **для data-access слоя**, где мэппинг колонок не очевиден; для тривиальных property — шум.
- LLM-генерация (Claude, Copilot, JetBrains AI Assistant) — современная замена шаблонным GhostDoc/AtomineerUtils, которые дают тавтологию.

### 5. Лучшие практики XML-doc в современных .NET 8/9/10 проектах

1. **Включить XML-файл** в каждом `.csproj`:
   ```xml
   <PropertyGroup>
     <GenerateDocumentationFile>true</GenerateDocumentationFile>
     <NoWarn>$(NoWarn);CS1591</NoWarn> <!-- не ругаться на legacy-публичные члены без doc -->
   </PropertyGroup>
   ```
2. **`<inheritdoc/>`** — для override-ов и реализаций интерфейсов экономит до 60% строк. Для публикуемых библиотек ставить явно.
3. **`<remarks>` с `CDATA`-обёрткой** — даёт нормальный Markdown в DocFX без `<para>`-капусты.
4. **`cref` валидируется компилятором** (предупреждение CS1574 на битую ссылку) — ссылайтесь через `cref`, а не через голый текст.
5. **`<exception>` — с причиной, не только с типом.**

### 6. Методология извлечения схемы БД из C#-кода

**Pass 1 — статика по regex.** Сканируем `.cs`-файлы (через `Grep`) тремя группами шаблонов:

```regex
# 1) SQL-литералы
INSERT\s+INTO\s+(?<table>[A-Z0-9_.]+)\s*\(\s*(?<cols>[^)]+)\s*\)\s*VALUES\s*\(\s*(?<vals>[^)]+)\s*\)
UPDATE\s+(?<table>[A-Z0-9_.]+)\s+SET\s+(?<sets>.+?)\s+WHERE\s+(?<where>.+?)["@]
SELECT\s+(?<cols>.+?)\s+FROM\s+(?<table>[A-Z0-9_.]+)\b
DELETE\s+FROM\s+(?<table>[A-Z0-9_.]+)\b

# 2) Bind-параметры
\.Parameters\.Add\(\s*"(?<pname>:?p_[A-Z0-9_]+)"\s*,\s*OracleDbType\.(?<otype>[A-Za-z0-9]+)

# 3) DataRow-маппинг
dr\[\s*"(?<col>[A-Z0-9_]+)"\s*\]\s*\.\s*(?<conv>ToInt64|ToInt32|ToStr|ToString|ToDateTime|ToNullableInt64|ToNullableInt32|ToNullableDateTime|ToDecimal|ToBool|ToGuid|ToClob)\s*\(\)
```

**Pass 2 — семантическая склейка LLM-ом.** Многострочные SQL, собранные через `@"…" + "…"` или интерполяцию `$"…{var}…"`, regex может разорвать; Claude хорошо склеивает их обратно. Если объём кода большой — отдельный bash-скрипт `prescan.sh` извлекает «факты» в JSON, чтобы не сжигать контекст на сам скан.

**OracleDbType → SQL → .NET (для документации):**

| OracleDbType | Oracle SQL | `dr.To*()` | Документируется как |
|---|---|---|---|
| `Int64` | `NUMBER(19)` | `ToInt64()` | `NUMBER(19)` / целое |
| `Int32` | `NUMBER(10)` | `ToInt32()` | `NUMBER(10)` / целое |
| `Varchar2` | `VARCHAR2(n)` | `ToStr()` | `VARCHAR2` / строка |
| `NVarchar2` | `NVARCHAR2(n)` | `ToStr()` | `NVARCHAR2` (Юникод) |
| `Date` / `TimeStamp` | `DATE` / `TIMESTAMP` | `ToDateTime()` / `ToNullableDateTime()` | дата-время |
| `Decimal` | `NUMBER(p,s)` | `ToDecimal()` | `NUMBER` (десятичное) |
| `Clob` / `NClob` | `CLOB` / `NCLOB` | `ToStr()` (большие строки) | `CLOB` |
| `Blob` | `BLOB` | `byte[]` | `BLOB` |
| `Raw` (16) | `RAW(16)` | `ToGuid()` | `RAW(16)` (GUID) |

(Источник маппинга — Oracle Data Provider for .NET документация на docs.oracle.com и подтверждение в обсуждениях про OracleDbType vs Int размеры.)

**Эвристики на колонки (русские описания для базы проекта):**

| Шаблон имени | Эвристическое описание |
|---|---|
| `SV_ID`, `TV_ID`, `<PFX>_ID` | **PK** — суррогатный идентификатор (`NUMBER(19)`). |
| `*_GUID` | Глобальный уникальный идентификатор записи (`RAW(16)`/GUID); используется для синхронизации между средами. |
| `*_PREVIOUSID` | Самоссылка на предыдущую версию записи (паттерн «история через linked list»). |
| `*_RECORDSTATUS` | Soft-delete: `1` — активна, `0` — удалена/архивная. |
| `*_USER` | ID пользователя последней операции (audit). |
| `*_DATEENTER`, `*_DATEUPDATE` | Дата создания / последнего изменения (audit). |
| `*_COMMENT` | Произвольный комментарий. |
| `*_NAME00`..`*_NAME05` | Мультиязычные наименования (00 — основной, далее переводы; точную раскладку нужно подтвердить у пользователя). |
| `*_SYSTEM`, `*_SYSTEMID` | FK на справочник «Систем». |
| `TV_REQUESTID` + `TV_REQUESTGUID` | Двойная FK на таблицу заявок: numeric + GUID. |
| `TV_PERSONID` | FK на справочник физлиц. |

**FK выводится по двум сигналам:** (1) имя колонки совпадает с PK другой таблицы; (2) колонка встречается в JOIN-условиях SELECT. Все выведенные FK skill маркирует «**предположительно**» — это сознательный честный хедж.

### 7. Лучшие практики Claude Code Skill (источники: code.claude.com/docs/en/skills, platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices, github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)

- **Структура.** `skill-name/SKILL.md` (обязательно) + опциональные `scripts/` (исполняемый код, не загружается в контекст), `references/` (доп. документация, читается по требованию), `assets/` (шаблоны).
- **Frontmatter.** Обязательны `name` (≤ 64 символа, lower-kebab-case, совпадает с именем папки) и `description` (≤ 1024 символа). Опциональны: `allowed-tools`, `disable-model-invocation`, `user-invocable`, `argument-hint`.
- **Прогрессивное раскрытие** в три уровня: метаданные (~100 слов) всегда в системном промпте; тело SKILL.md (целевой бюджет — **под 500 строк**, прямая цитата из skill-creator: *«Keep SKILL.md under 500 lines; if you're approaching this limit, add an additional layer of hierarchy»*) грузится при триггере; `references/`/`scripts/` — по требованию.
- **Description должен быть «pushy».** Прямая цитата из `anthropics/skills/skill-creator/SKILL.md`: *«currently Claude has a tendency to 'undertrigger' skills … please make the skill descriptions a little bit 'pushy'»* — то есть добавлять «Use this whenever …, even if the user doesn't explicitly say …».
- **Императивная форма** (`«Прочитай», «Сопоставь», «Сгенерируй»`).
- **Избегать all-caps MUST/NEVER** — объяснять причину; цитата из skill-creator: *«If you find yourself writing ALWAYS or NEVER in all caps … that's a yellow flag — if possible, reframe and explain the reasoning»*.
- **Один skill = одна задача.** Дословно из «SKILL.md Spec: Every Field and Frontmatter Key» (agensi.io/learn/skill-md-format-reference): *«Keep it focused. A skill should do one thing well. A 2,000-word skill that covers code review, testing, deployment, and documentation will underperform four separate 500-word skills.»*

### Решение: два skill'а, не один с двумя режимами

1. **Разные `allowed-tools`.** `doccs` массово пишет в `.cs` (нужен `Edit`/`Write` по широкой маске). `docmd` пишет только в `database.md` (узкая маска, безопаснее).
2. **Разные политики триггера.** `doccs` ставится с `disable-model-invocation: true` — массовое редактирование исходников опасно, нужно явное `/doccs`. `docmd` безопасен и может авто-триггериться по «опиши БД», «составь database.md».
3. **Разные триггер-фразы.** Описание `doccs` — про XML-doc и Markdown-doc; `docmd` — про схему БД. Слияние снизит точность авто-вызова.
4. **Пользователь явно требует независимый запуск.**
5. **Anthropic skill-creator не запрещает разделение** — он рекомендует объединять только варианты *одного* workflow через `references/`. Здесь workflow разные.

Каталог:

```
.claude/skills/
├── doccs/
│   ├── SKILL.md
│   ├── references/
│   │   ├── xml-tags-ru.md          # копия recommended-tags Microsoft на русском
│   │   ├── style-rules-ru.md       # стопфразы и правила для summary/remarks/exception
│   │   └── examples-ru.md          # эталонные «до/после» из реального кода
│   └── assets/
│       ├── class.md.template
│       └── method.md.template
└── docmd/
    ├── SKILL.md
    ├── references/
    │   ├── oracle-types.md         # таблица OracleDbType → SQL → .NET
    │   ├── naming-conventions.md   # SV_/TV_, *_ID, *_GUID, NAME00-05, RECORDSTATUS
    │   └── extraction-algorithm.md # regex и алгоритм двухпроходного парсинга
    ├── assets/
    │   └── database.md.template
    └── scripts/
        └── prescan.sh              # опциональный bash-prescan для больших проектов
```

## Details

### Полный `doccs/SKILL.md`

```markdown
---
name: doccs
description: >
  Генерирует документацию C#/.NET кода в ДВУХ независимых формах: (1) inline
  XML-doc комментарии (///) непосредственно в .cs-файлах по рекомендациям
  Microsoft (summary, param, returns, remarks, exception, typeparam,
  paramref, value, example, see, seealso, inheritdoc); (2) внешние Markdown
  файлы с описанием классов и членов в docs/api/. Язык вывода — РУССКИЙ.
  Используй этот skill, когда пользователь просит «задокументируй»,
  «добавь XML-комментарии», «напиши документацию к классу/методу»,
  «оформи /// для …», «сгенерируй .md для класса», «doccs» — даже если
  он не упомянул слово «skill». Это НЕ генератор database.md
  (для схемы БД — docmd).
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
argument-hint: путь к .cs-файлу, классу или папке; режим (--inline | --md | --both)
---

# doccs — генератор XML-doc и Markdown-документации для C#

## Когда срабатывать
Пользователь явно просит документировать C#-код. Триггерные глаголы:
«задокументируй», «добавь summary», «оформи XML-doc», «сгенерируй .md
для класса», «doccs».

## Общий алгоритм

1. **Уточни область.** Если аргумент не задан — спроси, что документировать:
   файл, класс, метод или папку (`src/**/*.cs`).
2. **Уточни режим:** `--inline` (только `///` в `.cs`), `--md` (только
   внешние `.md` в `docs/api/`), `--both` (по умолчанию, если не возразят).
3. **Прочитай целевые файлы** через `Read`/`Glob`. Если файлов > 20 —
   обрабатывай партиями по 5–10, иначе переполнишь контекст.
4. **Для каждого публичного типа и члена** сгенерируй XML-doc по правилам.
5. **Не трогай уже задокументированные** члены с непустым `<summary>` —
   только добавь недостающие теги (`<param>`, `<returns>`, `<exception>`).
6. **Сохрани** через `Edit` (inline) и/или `Write` (.md).

## Правила содержания

### Чего НЕ делать
- **Не дублируй имя метода/класса в `<summary>`.** «Метод для вставки
  записи» — мусор; имя уже это сказало.
- **Не пиши шаблонные `<param>`** вроде «Идентификатор». Объясняй
  *семантику*: «Первичный ключ записи `DICT.SV_ITEM` (`SV_ID`).»
- **Не выдумывай исключения**, которых код не бросает. `<exception>` —
  только если видишь `throw` или это очевидно из ADO.NET-контекста
  (`OracleException` при `ExecuteNonQuery`, `InvalidOperationException`
  при закрытом соединении).
- **Не используй ALL-CAPS MUST/NEVER в тексте документации.**
- **Не используй `<list type="table">`** в XML-doc (DocFX поддерживает
  только 2 колонки). Таблицы — только в **внешних** `.md`.

### Что делать
- `<summary>` — **одно предложение**: «что делает и зачем». Шире —
  в `<remarks>`.
- `<param>` — семантика, не тип.
- `<returns>` — что вернётся, когда null/-1/пустая коллекция.
- `<exception>` — **причина**, не только тип.
- Для override/реализаций — `<inheritdoc/>` (для NuGet ставить явно;
  Visual Studio автонаследует в IDE, но НЕ в выходной XML).
- Для async — упомяни `Task`/`ValueTask` и `CancellationToken`.
- В `<remarks>` для DA-классов **всегда**: имя таблицы Oracle, тип
  операции, затронутые колонки, bind-параметры.

### Полный набор тегов
См. `references/xml-tags-ru.md`. Базовый набор:
`<summary>`, `<remarks>`, `<param>`, `<paramref>`, `<returns>`,
`<exception>`, `<value>`, `<typeparam>`, `<typeparamref>`, `<example>`,
`<code>`, `<c>`, `<see>`, `<seealso>`, `<inheritdoc>`, `<include>`,
`<para>`, `<br/>`, `<list type="bullet|number">`, `<a>`.
Экранирование: `<` → `&lt;`, `>` → `&gt;`.

## Пример: SvItemDao.Insert (как должно быть сгенерировано)

```csharp
/// <summary>
/// Вставляет новую запись справочника «Уровни доступа» в таблицу
/// <c>DICT.SV_ITEM</c>.
/// </summary>
/// <remarks>
/// Выполняет одиночный <c>INSERT</c> со всеми 14 колонками, включая
/// мультиязычные наименования <c>SV_NAME00</c>..<c>SV_NAME05</c> и
/// аудит-поля (<c>SV_USER</c>, <c>SV_DATEENTER</c>). Поле
/// <c>SV_PREVIOUSID</c> используется для версионирования: при правке
/// существующей записи в него передаётся <see cref="SvItem.Id"/>
/// предыдущей версии, иначе <c>null</c>. <c>SV_RECORDSTATUS</c>
/// отвечает за soft-delete: <c>1</c> — активна, <c>0</c> — архивная.
/// Bind-параметры: <c>:p_ID</c>, <c>:p_GUID</c>, <c>:p_PREVID</c>,
/// <c>:p_RS</c>, <c>:p_USER</c>, <c>:p_DATE</c>, <c>:p_COMMENT</c>,
/// <c>:p_N00</c>..<c>:p_N05</c>, <c>:p_SYS</c>.
/// </remarks>
/// <param name="m">
/// DTO-модель новой записи; поля <see cref="SvItem.Guid"/> и
/// <see cref="SvItem.System"/> обязательны, остальные допускают
/// <see langword="null"/>.
/// </param>
/// <returns>
/// Количество вставленных строк (ожидается 1). При нарушении
/// уникальности <c>SV_GUID</c> метод выбрасывает исключение,
/// а не возвращает 0.
/// </returns>
/// <exception cref="Oracle.ManagedDataAccess.Client.OracleException">
/// Возникает при нарушении ограничений целостности (например,
/// дублирующий <c>SV_GUID</c>) или при недоступности схемы <c>DICT</c>.
/// </exception>
/// <seealso cref="Update(SvItem)"/>
/// <seealso cref="GetById(long)"/>
public long Insert(SvItem m) { /* … */ }
```

### Внешний Markdown `docs/api/SvItemDao.md`

```markdown
# Класс `SvItemDao`

**Назначение:** репозиторий доступа к справочнику «Уровни доступа»
(`DICT.SV_ITEM`). Реализует CRUD-операции через
`Oracle.ManagedDataAccess`.

## Методы

### `long Insert(SvItem m)`
Вставка новой записи в `DICT.SV_ITEM`.

| Параметр | Семантика |
|---|---|
| `m.Id` | PK (`SV_ID`, `NUMBER(19)`) |
| `m.Guid` | глобальный идентификатор (`SV_GUID`, `RAW(16)`) |
| `m.PreviousId` | ссылка на предыдущую версию (`SV_PREVIOUSID`, nullable) |
| `m.System` | FK на справочник систем (`SV_SYSTEM`) |
| `m.Name00..Name05` | мультиязычные наименования |

См. также: [`Update`](#updatesvitem-m), [`GetById`](#getbyidlong-id).
```

## Post-process (опционально, напомнить пользователю)
1. `<GenerateDocumentationFile>true</GenerateDocumentationFile>` в `.csproj`.
2. `<NoWarn>$(NoWarn);CS1591</NoWarn>` для legacy без doc.
3. DocFX для HTML-сайта (не задача этого skill'а).

## Когда отказаться
Если просят «сгенерировать database.md» / «опиши схему БД» — переключайся
на `docmd`.
```

### Полный `docmd/SKILL.md`

```markdown
---
name: docmd
description: >
  Реконструирует структуру реляционной БД проекта (Oracle) ИСКЛЮЧИТЕЛЬНО
  из исходного кода: SQL-строк-литералов в C# (INSERT/UPDATE/SELECT/DELETE
  с bind-параметрами :p_*), вызовов OracleDbType.* и обращений к
  DataRow["COL"].ToInt64()/ToStr()/ToDateTime()/ToNullableInt64() в
  mapping-классах. НЕ читает EF Core, НЕ читает .sql-файлы, НЕ подключается
  к БД. Результат — единый файл database.md на РУССКОМ с разделами по
  каждой таблице: назначение, колонки с типами и описаниями, связи (FK
  выводятся эвристически по именам и помечаются «предположительно»).
  Используй skill, когда пользователь говорит «опиши БД», «сделай
  database.md», «реверсни схему из кода», «какие таблицы используются»,
  «docmd» — даже если он не использует слово «schema». Это НЕ генератор
  C#-комментариев (для этого — doccs).
allowed-tools: Read, Grep, Glob, Write, Bash
argument-hint: путь к корню проекта или к папке DA-классов
---

# docmd — реверс-инжиниринг схемы БД из C#-кода

## Алгоритм (двухпроходный)

### Pass 1 — статический сбор фактов (через Grep)

1. **SQL-литералы.** `INSERT INTO`, `UPDATE`, `SELECT`, `DELETE FROM`.
   Извлеки имя таблицы и список колонок. Подробные regex —
   `references/extraction-algorithm.md`.
2. **Bind-параметры.** `Parameters.Add("…", OracleDbType.…)` — связка
   «имя параметра → тип Oracle». Соедини с колонкой через VALUES-список
   (порядок колонок == порядок параметров).
3. **DataRow-маппинг.** `dr["COL"].ToXxx()` — колонка → .NET-тип.

### Pass 2 — семантический разбор (LLM)

Для каждой таблицы:

1. **Сводный список колонок** = объединение колонок из INSERT
   (приоритетный источник — там точный порядок), DataRow-чтений
   и SELECT-списков.
2. **Тип колонки** в порядке приоритета: `OracleDbType` из bind →
   `.ToXxx()`-конвертер → эвристика по имени (`*_ID`/`*_PREVIOUSID` →
   `NUMBER(19)`, `*_GUID` → `RAW(16)`, `*_DATE*` → `DATE`,
   `*_NAME*`/`*_COMMENT` → `VARCHAR2`/`NVARCHAR2`).
3. **Назначение колонки** — по `references/naming-conventions.md` плюс
   контекст (если колонка читается в форме «дерево доступов» — упомяни).
4. **PK** — `<PFX>_ID` или единственная колонка в `WHERE` UPDATE/DELETE.
5. **FK (предположительные).** Имя колонки = PK другой таблицы → FK.
   Особые случаи: `*_PREVIOUSID` — самоссылка (версионирование);
   `*_REQUESTID + *_REQUESTGUID` — двойная FK (numeric + GUID) на
   таблицу заявок; `*_SYSTEM` — FK на справочник систем.
   **Маркируй «предположительно».**

## Соглашения проекта (учитывай!)

- `SV_*` — справочники (Static Values), схема `DICT`.
- `TV_*` — транзакционные таблицы (Transaction Values), обычно `APP`.
- `*_RECORDSTATUS` — soft-delete: `1` активна, `0` удалена.
- `*_USER`, `*_DATEENTER`, `*_COMMENT` — аудит.
- `*_NAME00`..`*_NAME05` — мультиязычные (00 — основной, далее переводы;
  точную раскладку языков попроси у пользователя один раз и зафиксируй
  в шапке database.md).

## Формат вывода

```markdown
# Структура БД проекта <название>

> Восстановлена автоматически из исходного кода (skill `docmd`).
> Не является источником истины; для production-схемы — DBA.
> Дата генерации: <YYYY-MM-DD>.

## Соглашения
- Префиксы: `SV_*` — справочники (`DICT`), `TV_*` — транзакционные (`APP`).
- Аудит: `*_USER`, `*_DATEENTER`, `*_COMMENT`.
- Soft-delete: `*_RECORDSTATUS` (1 — активна, 0 — архивная).
- Мультиязычные: `*_NAME00`..`*_NAME05` — наименования на разных
  языках/локалях проекта (раскладка настраивается под вашу базу).

## Таблицы

### `DICT.SV_ITEM` — справочник «Уровни доступа»
**Назначение.** Справочник ролей/уровней доступа пользователей клиентского приложения.
Используется при отрисовке дерева прав. Источник: `SvItemDao.cs`.

| Колонка | Тип Oracle | .NET / DataRow | Назначение |
|---|---|---|---|
| `SV_ID` | `NUMBER(19)` | `ToInt64()` | **PK.** Суррогатный идентификатор. |
| `SV_GUID` | `RAW(16)` | `ToGuid()` | Глобальный уникальный идентификатор для синхронизации. |
| `SV_PREVIOUSID` | `NUMBER(19)` | `ToNullableInt64()` | Самоссылка на предыдущую версию (версионирование). FK → `DICT.SV_ITEM.SV_ID`. |
| `SV_RECORDSTATUS` | `NUMBER(1)` | `ToInt32()` | Soft-delete. |
| `SV_USER` | `NUMBER(19)` | `ToInt64()` | Аудит: ID пользователя. **Предположительно** FK → `DICT.SV_USER.SV_ID`. |
| `SV_DATEENTER` | `DATE` | `ToDateTime()` | Аудит: дата создания/изменения. |
| `SV_COMMENT` | `VARCHAR2(…)` | `ToStr()` | Комментарий пользователя. |
| `SV_NAME00` | `NVARCHAR2(…)` | `ToStr()` | Наименование (рус.). |
| `SV_NAME01` | `NVARCHAR2(…)` | `ToStr()` | Наименование (локаль 1). |
| `SV_NAME02` | `NVARCHAR2(…)` | `ToStr()` | Наименование (локаль 2). |
| `SV_NAME03` | `NVARCHAR2(…)` | `ToStr()` | Наименование (англ.). |
| `SV_NAME04` | `NVARCHAR2(…)` | `ToStr()` | Резервная языковая колонка. |
| `SV_NAME05` | `NVARCHAR2(…)` | `ToStr()` | Резервная языковая колонка. |
| `SV_SYSTEM` | `NUMBER(19)` | `ToInt64()` | FK на справочник систем. **Предположительно** → `DICT.SV_SYSTEM.SV_ID`. |

**Связи.**
- `SV_PREVIOUSID` → `DICT.SV_ITEM.SV_ID` (self, версионирование).
- `SV_USER` → `DICT.SV_USER.SV_ID` (предположительно).
- `SV_SYSTEM` → `DICT.SV_SYSTEM.SV_ID` (предположительно).

**Используется в коде.**
- `SvItemDao.Insert(SvItem)` — INSERT всех 14 колонок.
- `SvItemDao.Update(SvItem)` — UPDATE по `SV_ID`.
- `SvItemDao.GetById(long)` — SELECT по `SV_ID`.
- `SvItemDao.GetAll()` — SELECT с фильтром `SV_RECORDSTATUS = 1`.

---

### `APP.TV_REQUEST` — заявки
**Назначение.** Транзакционная таблица заявок (выпуск/отзыв доступа).
Источник: `TvRequestMapping.cs`, `TvRequestDao.cs`.

| Колонка | Тип Oracle | .NET / DataRow | Назначение |
|---|---|---|---|
| `TV_ID` | `NUMBER(19)` | `ToInt64()` | **PK.** |
| `TV_GUID` | `RAW(16)` | `ToGuid()` | Глобальный идентификатор заявки. |
| `TV_REQUESTID` | `NUMBER(19)` | `ToNullableInt64()` | Numeric-ссылка на родительскую заявку. **Предположительно** → `APP.TV_REQUEST.TV_ID` (self). |
| `TV_REQUESTGUID` | `RAW(16)` | `ToGuid()` | GUID-дубль той же ссылки (для кросс-системной синхронизации). |
| `TV_PERSONID` | `NUMBER(19)` | `ToInt64()` | FK на справочник физлиц. **Предположительно** → `DICT.SV_PERSON.SV_ID`. |
| `TV_RECORDSTATUS` | `NUMBER(1)` | `ToInt32()` | Soft-delete. |
| `TV_USER` | `NUMBER(19)` | `ToInt64()` | Аудит. |
| `TV_DATEENTER` | `DATE` | `ToDateTime()` | Аудит. |
| `TV_COMMENT` | `VARCHAR2(…)` | `ToStr()` | Комментарий. |

**Связи.**
- `TV_REQUESTID/TV_REQUESTGUID` → `APP.TV_REQUEST.TV_ID/TV_GUID` (self,
  предположительно).
- `TV_PERSONID` → `DICT.SV_PERSON.SV_ID` (предположительно).

---

## Граф связей (упрощённый)

```text
DICT.SV_ITEM ─┬─► DICT.SV_ITEM    (self, SV_PREVIOUSID)
                ├─► DICT.SV_USER      (SV_USER, предп.)
                └─► DICT.SV_SYSTEM    (SV_SYSTEM, предп.)

APP.TV_REQUEST ─┬─► APP.TV_REQUEST    (self, TV_REQUESTID/TV_REQUESTGUID)
                └─► DICT.SV_PERSON    (TV_PERSONID, предп.)
```
```

## Что делать НЕ нужно
- Не выдумывай таблицы и колонки, которых нет в коде.
- Не утверждай FK как факт без явного JOIN-условия — пиши «предположительно».
- Не лезь в EF Core-миграции, не запускай `dotnet ef dbcontext scaffold`.
- Не подключайся к реальной БД.

## Когда отказаться
Если просят «добавь summary к классу» — это `doccs`, переключайся.
```

### Дополнительные файлы (краткое содержание)

**`doccs/references/xml-tags-ru.md`** — расширенная копия таблицы тегов из раздела 2 с примерами правильного и неправильного использования каждого тега. Загружается Claude'ом по требованию.

**`doccs/references/style-rules-ru.md`** — чек-лист «как НЕ писать summary», список стопфраз («Получает …», «Устанавливает …», «Метод для …»), фразы-замены, чек-лист «что обязательно для DA-классов».

**`doccs/references/examples-ru.md`** — 3–5 эталонных «до/после» примеров из реального проекта (заполняется пользователем после первой итерации).

**`docmd/references/extraction-algorithm.md`** — полные regex из раздела 6 плюс псевдокод склейки многострочных SQL (`@"…" + "…"`, интерполяции `$"…{x}…"`), плюс описание формата `_tmp/sql-facts.json`.

**`docmd/references/oracle-types.md`** — таблица OracleDbType → SQL → .NET из раздела 6.

**`docmd/references/naming-conventions.md`** — пустой шаблон, который пользователь заполняет специфичными для своего проекта префиксами и языковой раскладкой.

**`docmd/scripts/prescan.sh`** — bash-скрипт для проектов > 200 файлов: grep'ом извлекает SQL-литералы, OracleDbType-объявления и DataRow-маппинги в `_tmp/sql-facts.json`. Исполняется через `Bash`, сам код в контекст не попадает (прогрессивное раскрытие 3-го уровня).

## Recommendations

### Этап 1 — поставить базовую версию (1 день)

1. Создать `.claude/skills/doccs/` и `.claude/skills/docmd/` (project-scope, чтобы коллеги тоже видели после `git pull`) с приведёнными SKILL.md.
2. Скопировать в `doccs/references/xml-tags-ru.md` таблицу тегов из Microsoft Learn ru.
3. Создать пустые `naming-conventions.md`, `examples-ru.md` (заполнятся на этапе 2).
4. Запустить `/doccs` на одном небольшом DA-классе (`SvItemDao.cs`) и убедиться, что summary НЕ вырождается в «Метод для вставки записи».
5. Запустить `/docmd` на папке `DataAccess/` и просмотреть `database.md`.

### Этап 2 — обогатить контекст (2–3 дня)

6. Заполнить `docmd/references/naming-conventions.md` **специфичными для вашего проекта** именами таблиц/колонок. Особенно важно подтвердить языковую раскладку `NAME00..NAME05` (кириллица/латиница/англ.) — я угадал её эвристически.
7. Добавить в `doccs/references/examples-ru.md` 3–5 эталонных «до/после» примеров из вашего реального кода — это резко поднимет качество, потому что Claude отлично переносит стиль из few-shot.
8. Если есть DBA — попросить выгрузить настоящий DDL и сравнить с `database.md`, чтобы откалибровать эвристики FK.

### Этап 3 — масштабирование (по необходимости)

9. При объёме `.cs` > 200 файлов — добавить `docmd/scripts/prescan.sh`. Скрипт исполняется через `Bash`, его код в контекст не попадает (прогрессивное раскрытие 3-го уровня).
10. Опционально подключить **DocFX** для сборки XML-doc в HTML-сайт (отдельный воркфлоу, не входит в этот skill).
11. Если потребуется автогенерация для PostgreSQL/SQL Server — форкнуть `docmd` в `docmd-pg` с заменой `OracleDbType` → `NpgsqlDbType` и регенерацией таблицы маппинга.

### Триггеры пересмотра

| Симптом | Действие |
|---|---|
| Summary получаются тавтологичными типа «Метод для …» | Расширь `doccs/references/style-rules-ru.md` контр-примерами. |
| В `database.md` появляется `UNKNOWN_TABLE` | Расширь regex в `extraction-algorithm.md`; вероятно, у вас экзотический синтаксис склейки SQL. |
| FK угадываются неправильно > 30% случаев | Добавь в `database.md` раздел «**Подтверждённые связи**» (ручной override) и попроси skill его уважать на повторных запусках. |
| Контекст переполняется на больших проектах | Включи `docmd/scripts/prescan.sh` для предварительного скана. |

## Caveats

- **Содержимое Reddit-треда `r/csharp/comments/1ehijwv` мне получить не удалось** — Reddit заблокировал прямой fetch (`SITE_BLOCKED`), зеркала (`old.reddit.com`, libreddit, JSON API) — `PERMISSIONS_ERROR`, web_search не вернул фрагментов. Раздел «community best practices» построен на смежных источниках (Microsoft Learn, Habr 102177, Red Gate Simple Talk, JetBrains blog, agensi.io). Если содержимое треда критично — достаньте его вручную (например, через archive.org) и при необходимости скорректируйте `doccs/references/style-rules-ru.md`.
- **Habr 102177 — direct fetch заблокирован по таймауту**, но ключевые тезисы извлечены через snippet'ы web_search (`GenerateDocumentationFile`, Sandcastle + SHFB, GhostDoc как ускоритель ввода). Часть деталей статьи может остаться неучтённой.
- **`<inheritdoc/>` имеет важный нюанс:** Visual Studio наследует доку в IntelliSense без явного тега, но компилятор НЕ кладёт это в выходной XML — для NuGet-публикации тег нужен явно. Это прямо указано на странице Microsoft Learn ru.
- **DocFX v2 поддерживает `<list type="table">` только с двумя колонками** (issue dotnet/docfx#5492). Skill `doccs` это учитывает: в XML-doc используются `<list type="bullet">` для перечислений; Markdown-таблицы — только в внешних `.md`.
- **Эвристика FK по именам неизбежно даёт ложные срабатывания.** Колонка `TV_USER` может ссылаться на `DICT.SV_USER`, а может — на `DICT.SV_OPERATOR` или вообще на внешнюю систему. Skill всегда хеджирует словом «предположительно» — не убирайте этот хедж без подтверждения от DBA.
- **Roslyn-парсинг SQL-литералов внутри C# точнее regex** (особенно для интерполяций `$"…{x}…"` и сложных конкатенаций), но требует MCP-сервер с Roslyn (см. «.NET Claude Kit» от codewithmukesh как референс с 15 Roslyn MCP tools). Базовая версия skill'а использует regex + LLM-склейку — этого достаточно для типичного ADO.NET-кода. Если точность недостаточна — переход на Roslyn MCP оправдан.
- **`docmd` НЕ подключается к самой БД сознательно.** Если есть доступ к Oracle, дополнительно сверьтесь через `SELECT … FROM ALL_TAB_COLUMNS / ALL_CONSTRAINTS` — это даст ground truth для калибровки эвристик.
- **Skill'ы не были протестированы на production-репозитории.** Перед массовым прогоном сделайте `git checkout -b skill-test` и проверьте diff.
- **Описания и примеры частично основаны на гипотезе** о вашей доменной модели (клиентское приложение оператора, дерево доступов, заявки, записи). Если домен другой — поправьте формулировки в `examples-ru.md`, и skill подхватит новый стиль.