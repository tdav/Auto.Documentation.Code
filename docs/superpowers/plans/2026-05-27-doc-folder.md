# doc-folder Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить в плагин `dotnet-doc-skills` новый skill `doc-folder`, который генерирует один обзорный `README.md` в корне указанной мульти-проектной папки (проекты → namespace → классы с описанием логики каждого класса).

**Architecture:** Skill — это набор markdown-инструкций для LLM + правки JSON-манифестов плагина. Новый каталог `skills/doc-folder/` (SKILL.md + assets/шаблон + references/правила), правка единой frontmatter-схемы в `doc-md`, обновление двух манифестов. Автотестов нет (вывод — недетерминированный markdown); проверка — статическая валидация артефактов (JSON-parse, наличие frontmatter-полей и секций) + ручной прогон на реальном коде.

**Tech Stack:** Claude Code skills (Markdown + YAML frontmatter), JSON-манифесты плагина, PowerShell 7 для валидации, git.

---

## File Structure

**Создать:**
- `skills/doc-folder/references/class-summary-style-ru.md` — правила описания класса (Task 1). Один источник стиля для Pass 2, читается субагентами.
- `skills/doc-folder/assets/readme.md.template` — шаблон выходного README (Task 2).
- `skills/doc-folder/SKILL.md` — основной skill: frontmatter, алгоритм, границы (Task 4).

**Изменить:**
- `skills/doc-md/references/frontmatter-schema.md` — добавить секцию `type: folder-overview` (Task 3). Единый источник истины по frontmatter.
- `.claude-plugin/plugin.json` — `description` + version 1.0.6 → 1.1.0 (Task 5).
- `.claude-plugin/marketplace.json` — описания плагина (Task 5).

**Порядок:** сначала зависимые артефакты (reference, template, schema), затем SKILL.md (ссылается на них), затем манифесты, затем финальная сводная валидация.

---

## Task 1: references/class-summary-style-ru.md

Правила описания класса. На них ссылается SKILL.md и их читает каждый субагент Pass 2 — поэтому создаём первым.

**Files:**
- Create: `skills/doc-folder/references/class-summary-style-ru.md`

- [ ] **Step 1: Создать файл с полным содержимым**

````markdown
# Правила описания класса для README (skill doc-folder)

Эти правила обязан прочитать каждый субагент Pass 2 перед генерацией, иначе
объём и стиль описаний разъедутся между агентами.

## Формат записи одного класса

```markdown
#### `ИмяТипа` — короткая роль (3-5 слов)
Слой: <layer> · `<namespace>` · [`<относительный/путь.cs>`](<относительный/путь.cs>)

<Абзац 3-6 строк>
```

## Что писать в абзаце (в этом порядке)

1. **Назначение (1-2 предложения).** Что класс делает в целом и его роль в
   системе/слое. Это главное — нужно объяснить, «что делает класс в целом».
2. **Логика (1-2 предложения).** Как именно работает: ключевые операции,
   инварианты, побочные эффекты (версионирование, soft-delete-фильтр,
   оркестрация вызовов, кеширование и т.п.).
3. **Зависимости/использование (1 строка).** Что инжектируется/используется и
   кто вызывает класс, если это видно из кода.

## Чего НЕ делать

- Не воспроизводить сигнатуры методов и таблицы параметров — это формат `doc-md`.
- Не перечислять все члены подряд; только то, что объясняет назначение/логику.
- Не выдумывать факты, которых нет в коде, `///` или имени. Лучше короче.
- Не дублировать имя класса («Класс SvItemDao — это класс, который…»).
- Не использовать ALL-CAPS MUST/NEVER.

## Источник фактов (приоритет)

1. Существующий `/// <summary>` над типом — если есть, опирайся на него.
2. Тело класса: SQL-литералы, вызываемые сервисы, поля, базовый тип.
3. Имя типа и суффиксы: `*Dao`/`*Repository` — доступ к данным; `*Service` —
   бизнес-логика; `*Dto`/`*Model` — модель; `*Controller` — контроллер;
   `*Mapping` — маппер.

## Слой (layer) — те же значения, что в doc-md

`data-access` · `service` · `model` · `mapping` · `controller` · `util` · `other`.
См. `../../doc-md/references/frontmatter-schema.md`, раздел «Как выбирать layer».

## Примеры

**Хорошо:**

```markdown
#### `SvItemDao` — репозиторий справочника «Уровни доступа»
Слой: data-access · `Sample.Dico` · [`src/Dico/SvItemDao.cs`](src/Dico/SvItemDao.cs)

Инкапсулирует CRUD к таблице `DICT.SV_ITEM` через ADO.NET. `Insert` версионирует
запись через `SV_PREVIOUSID`, `GetAll` отдаёт только активные строки
(`SV_RECORDSTATUS = 1`). Зависит от `AppContext`, используется `AccessService`.
```

**Плохо** (дублирует имя, перечисляет сигнатуры, пусто по смыслу):

```markdown
#### `SvItemDao`
Класс SvItemDao. Методы: Insert(SvItem m), Update(SvItem m), GetById(long id),
GetAll(). Содержит логику работы с базой данных.
```
````

- [ ] **Step 2: Проверить наличие файла и ключевых секций**

Run:
```powershell
Test-Path skills\doc-folder\references\class-summary-style-ru.md
Select-String -Path skills\doc-folder\references\class-summary-style-ru.md -Pattern '## Что писать в абзаце','## Чего НЕ делать','## Источник фактов' | ForEach-Object { $_.Line }
```
Expected: `True`, затем три строки заголовков секций.

- [ ] **Step 3: Commit**

```powershell
git add skills/doc-folder/references/class-summary-style-ru.md
git commit -m "Add doc-folder class-summary style reference"
```

---

## Task 2: assets/readme.md.template

Шаблон выходного README. На него ссылается Pass 3 в SKILL.md.

**Files:**
- Create: `skills/doc-folder/assets/readme.md.template`

- [ ] **Step 1: Создать файл с полным содержимым**

````markdown
---
title: {{ИмяПапки}} — обзор кода
type: folder-overview
generator: doc-folder
root: {{относительный-путь-папки-или-точка}}
projects: [{{Проект1}}, {{Проект2}}]
generated: {{YYYY-MM-DD}}
tags: [overview, csharp, navigation]
summary: Обзорная карта классов мульти-проектной папки.
---

# {{ИмяПапки}} — обзор кода

> Сгенерировано skill `doc-folder` (плагин `dotnet-doc-skills`).
> Назначение файла: карта папки для навигации, в т.ч. для AI-агента.
> Дата генерации: {{YYYY-MM-DD}}.

## Проекты

| Проект | TFM | Namespace | Описание |
|---|---|---|---|
| [`{{Проект1}}`](#{{anchor1}}) | {{tfm}} | `{{root-namespace}}` | {{одно предложение}} |
| [`{{Проект2}}`](#{{anchor2}}) | {{tfm}} | `{{root-namespace}}` | {{одно предложение}} |

<!-- Строка ниже добавляется ТОЛЬКО если рядом есть documentation/ от doc-md/doc-db: -->
Детальная API-дока: [`documentation/api/`](documentation/api/index.md) · Схема БД: [`documentation/database.md`](documentation/database.md)

---

## {{Проект1}}

**Путь:** `{{относительный/путь/Проект1.csproj}}` · **TFM:** {{tfm}}

<!-- Подзаголовок namespace опускается, если в проекте один namespace -->
### `{{namespace}}` (namespace)

#### `{{ИмяТипа}}` — {{короткая роль}}
Слой: {{layer}} · `{{namespace}}` · [`{{относительный/путь.cs}}`]({{относительный/путь.cs}})

{{Абзац 3-6 строк: назначение + логика + зависимости. См. references/class-summary-style-ru.md.}}

---

## {{Проект2}}

**Путь:** `{{относительный/путь/Проект2.csproj}}` · **TFM:** {{tfm}}

#### `{{ИмяТипа}}` — {{короткая роль}}
Слой: {{layer}} · `{{namespace}}` · [`{{относительный/путь.cs}}`]({{относительный/путь.cs}})

{{Абзац 3-6 строк.}}

---
````

- [ ] **Step 2: Проверить наличие файла и frontmatter-маркеров**

Run:
```powershell
Test-Path skills\doc-folder\assets\readme.md.template
Select-String -Path skills\doc-folder\assets\readme.md.template -Pattern '^type: folder-overview','^generator: doc-folder' | ForEach-Object { $_.Line }
```
Expected: `True`, затем `type: folder-overview` и `generator: doc-folder`.

- [ ] **Step 3: Commit**

```powershell
git add skills/doc-folder/assets/readme.md.template
git commit -m "Add doc-folder README output template"
```

---

## Task 3: Расширить frontmatter-schema.md секцией folder-overview

Единая frontmatter-схема живёт в `doc-md`. Добавляем туда `type: folder-overview`, чтобы формат остался общим (поиск/RAG/статические генераторы).

**Files:**
- Modify: `skills/doc-md/references/frontmatter-schema.md`

- [ ] **Step 1: Прочитать текущий файл**

Run:
```powershell
Get-Content skills\doc-md\references\frontmatter-schema.md
```
Expected: содержимое со секциями «## Схема для класса», «## Схема для схемы БД (`type: database-schema`)», «## Правила полей».

- [ ] **Step 2: Вставить секцию folder-overview перед «## Правила полей»**

Найти строку `## Правила полей` и вставить ПЕРЕД ней следующий блок (Edit: old_string = `## Правила полей`, new_string = блок ниже + `\n\n## Правила полей`):

````markdown
## Схема для обзора папки (`type: folder-overview`) — файл `README.md`

Генерируется skill `doc-folder`: один обзорный `README.md` в корне папки.

```yaml
---
title: Sample.Solution — обзор кода   # имя документируемой папки
type: folder-overview
generator: doc-folder                  # метка происхождения файла
root: .                                 # относительный путь документируемой папки
projects: [Sample.Dico, Sample.App]   # имена .csproj-проектов папки
generated: 2026-05-27                   # дата генерации (YYYY-MM-DD)
tags: [overview, csharp, navigation]
summary: Обзорная карта классов мульти-проектной папки.   # одна строка, с точкой
---
```
````

- [ ] **Step 3: Расширить enum `type` в таблице правил полей**

Edit:
- old_string: `` | `type` | да | enum | `class` \| `interface` \| `enum` \| `database-schema`. Только нижний регистр. | ``
- new_string: `` | `type` | да | enum | `class` \| `interface` \| `enum` \| `database-schema` \| `folder-overview` \| `index`. Только нижний регистр. | ``

- [ ] **Step 4: Добавить правила новых полей в конец таблицы правил полей**

Edit (old_string — последняя строка таблицы правил полей, `summary`; new_string — та же строка плюс четыре новые):

- old_string: `` | `summary` | да | строка | Одно предложение, с точкой. Без переносов. | ``
- new_string (дословно, 5 строк):

```
| `summary` | да | строка | Одно предложение, с точкой. Без переносов. |
| `generator` | для folder-overview | строка | Имя skill-генератора, напр. `doc-folder`. Метка происхождения файла. |
| `root` | для folder-overview | путь | Относительный путь документируемой папки (`.` если это корень). |
| `projects` | для folder-overview | список | Имена `.csproj`-проектов в папке. |
| `generated` | для folder-overview | дата | Дата генерации в формате `YYYY-MM-DD`. |
```

- [ ] **Step 5: Проверить, что секция и поля добавлены**

Run:
```powershell
Select-String -Path skills\doc-md\references\frontmatter-schema.md -Pattern 'folder-overview','^\| `generator`','^\| `projects`' | ForEach-Object { $_.Line }
```
Expected: минимум 3 совпадения (заголовок секции с `folder-overview`, строка `generator`, строка `projects`).

- [ ] **Step 6: Commit**

```powershell
git add skills/doc-md/references/frontmatter-schema.md
git commit -m "Extend frontmatter schema with folder-overview type"
```

---

## Task 4: skills/doc-folder/SKILL.md

Основной файл skill. Ссылается на reference (Task 1), template (Task 2), schema (Task 3) — поэтому идёт после них.

**Files:**
- Create: `skills/doc-folder/SKILL.md`

- [ ] **Step 1: Создать файл с полным содержимым**

`````markdown
---
name: doc-folder
description: >
  Генерирует ОДИН обзорный README.md в корне указанной папки — навигационную
  карту мульти-проектной папки для будущего claude code и человека. Рекурсивно
  находит все .cs, определяет проекты (.csproj) и описывает каждый публичный
  тип кратким абзацем: что класс делает в целом, его логика/роль и зависимости —
  без сигнатур методов и таблиц параметров. Структура README: проекты →
  namespace → классы. Язык вывода — РУССКИЙ. Используй, когда пользователь
  говорит «doc-folder», «сделай README для папки», «опиши проекты в каталоге»,
  «карта кода папки», «обзор классов в папке» — даже без слова «skill». Это НЕ
  генератор inline /// (для этого — doc-cs), НЕ детальная API-дока по .md на
  класс (для этого — doc-md) и НЕ схема БД (для этого — doc-db).
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Write, Bash, Task
argument-hint: путь к папке (мульти-проектной)
---

# doc-folder — обзорный README.md для мульти-проектной папки

## Когда срабатывать
Пользователь просит обзорную карту кода папки: «doc-folder», «сделай README для
папки», «опиши проекты в каталоге», «обзор классов». Вывод — один `README.md`
в корне указанной папки, а НЕ дока по классам (`doc-md`) и не `///` (`doc-cs`).

## Общий алгоритм (три прохода)

### Pass 1 — обнаружение (главная сессия, Glob + Grep)
1. **Аргумент — путь к папке.** Если не передан — спроси путь.
2. **Найди все .cs:** `Glob("<папка>/**/*.cs")`. Исключи `bin/`, `obj/` и
   сгенерированные файлы: `*.g.cs`, `*.Designer.cs`, `*.AssemblyInfo.cs`,
   `*.AssemblyAttributes.cs`.
3. **Найди проекты:** `Glob("<папка>/**/*.csproj")`. Для каждого определи имя
   (файл без расширения), корневую папку, root-namespace (`<RootNamespace>` или
   имя проекта), `TargetFramework(s)`.
4. **Привяжи каждый .cs к проекту** по ближайшему `.csproj` вверх по дереву.
   `.cs` без проекта собери в группу «Вне проектов».
5. **Извлеки из каждого .cs** (Grep): `namespace`, ПУБЛИЧНЫЕ типы
   (`public ... class|interface|enum|record|struct`), базовый тип/интерфейсы,
   наличие `/// <summary>`. Только `public` — `internal`/`private` пропускай.

### Pass 2 — описание классов (LLM; опц. субагенты ≤ 10)
Для каждого public-типа сформируй запись ~3-6 строк строго по
`references/class-summary-style-ru.md` (прочитай файл до генерации):
назначение (что класс делает в целом) + логика/роль + зависимости/использование.
Без сигнатур методов и таблиц параметров.

### Pass 3 — сборка README (главная сессия)
1. Собери `README.md` по `assets/readme.md.template` (структура ниже).
2. Если существуют `documentation/api/` (от `doc-md`) или
   `documentation/database.md` (от `doc-db`) — добавь строку ссылок на них.
   Если их нет — строку не добавляй.
3. **Запиши** через `Write` в `<указанная папка>/README.md`. Файл
   **всегда перезаписывается** — это снимок текущего кода.

## Структура README (проекты → namespace → классы)
- **Frontmatter** `type: folder-overview` (схема —
  `../doc-md/references/frontmatter-schema.md`, единый источник истины).
- **Шапка**: назначение файла + дата генерации.
- **Сводная таблица проектов**: Проект | TFM | Namespace | Описание.
- **Раздел на каждый проект** → подзаголовки по `namespace` → записи классов.
- Если в проекте один `namespace` — уровень группировки опусти, классы списком.

Полный шаблон — `assets/readme.md.template`. Пример записи класса:

```markdown
#### `SvItemDao` — репозиторий справочника «Уровни доступа»
Слой: data-access · `Sample.Dico` · [`src/Dico/SvItemDao.cs`](src/Dico/SvItemDao.cs)

Инкапсулирует CRUD к таблице `DICT.SV_ITEM` через ADO.NET. `Insert` версионирует
запись через `SV_PREVIOUSID`, `GetAll` отдаёт только активные строки
(`SV_RECORDSTATUS = 1`). Зависит от `AppContext`, используется `AccessService`.
```

## Обработка больших папок (параллелизм ≤ 10)
Опционально. Pass 1 и Pass 3 — всегда в главной сессии (один выходной файл,
блоки склеивает главная). Pass 2 распараллеливай субагентами `Task` волнами
не более 10: каждому передай его `.cs`-файлы и путь к
`references/class-summary-style-ru.md` (обязан прочитать до генерации, иначе
объём и стиль описаний разъедутся). Субагент возвращает готовые markdown-блоки
классов — главная сессия компонует их в единый README.

## Соглашения
- Язык вывода — русский; имена типов/членов/проектов — как в коде.
- Только public-типы. Не выдумывай назначение — лучше короче.
- Не воспроизводи сигнатуры методов и таблицы параметров (это `doc-md`).
- Относительные пути в ссылках считай от `README.md` в корне указанной папки.
- Ссылки на `documentation/...` ставь только если файлы существуют.

## Когда отказаться
- Просят inline `///` в `.cs` → `doc-cs`.
- Просят детальную доку по классу (`.md` на класс, таблицы методов) → `doc-md`.
- Просят описать схему БД → `doc-db`.
`````

- [ ] **Step 2: Проверить frontmatter и обязательные поля**

Run:
```powershell
Test-Path skills\doc-folder\SKILL.md
Select-String -Path skills\doc-folder\SKILL.md -Pattern '^name: doc-folder','^disable-model-invocation: true','^allowed-tools:','^argument-hint:' | ForEach-Object { $_.Line }
```
Expected: `True`, затем четыре строки (`name: doc-folder`, `disable-model-invocation: true`, `allowed-tools: ...`, `argument-hint: ...`).

- [ ] **Step 3: Проверить ключевые секции алгоритма и границ**

Run:
```powershell
Select-String -Path skills\doc-folder\SKILL.md -Pattern 'Pass 1','Pass 2','Pass 3','## Когда отказаться' | ForEach-Object { $_.Line }
```
Expected: совпадения по всем трём проходам и секции «Когда отказаться».

- [ ] **Step 4: Commit**

```powershell
git add skills/doc-folder/SKILL.md
git commit -m "Add doc-folder SKILL.md"
```

---

## Task 5: Обновить манифесты плагина

Зарегистрировать `doc-folder` в описаниях и поднять версию.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: plugin.json — обновить description**

Edit:
- old_string: `"description": "C#/.NET documentation skills with Russian output. doc-cs: inline XML-doc comments per Microsoft recommended tags. doc-md: external Markdown docs (one .md per class, mirrors solution structure, cross-links). doc-db: reverse-engineers an Oracle relational schema purely from C# source.",`
- new_string: `"description": "C#/.NET documentation skills with Russian output. doc-cs: inline XML-doc comments per Microsoft recommended tags. doc-md: external Markdown docs (one .md per class, mirrors solution structure, cross-links). doc-db: reverse-engineers an Oracle relational schema purely from C# source. doc-folder: single in-place README.md overview of a multi-project folder (projects -> namespaces -> classes with per-class purpose/logic).",`

- [ ] **Step 2: plugin.json — поднять версию**

Edit:
- old_string: `"version": "1.0.6",`
- new_string: `"version": "1.1.0",`

- [ ] **Step 3: plugin.json — добавить keyword (опционально, для поиска)**

Edit:
- old_string: `    "reverse-engineering",
    "russian"`
- new_string: `    "reverse-engineering",
    "readme",
    "russian"`

- [ ] **Step 4: marketplace.json — обновить top-level description**

Edit:
- old_string: `  "description": "Three Claude Code skills for documenting C#/.NET code: doc-cs generates Russian-language XML-doc comments; doc-md generates external Markdown docs (one .md per class, mirrors solution structure); doc-db reverse-engineers an Oracle DB schema from raw ADO.NET code.",`
- new_string: `  "description": "Four Claude Code skills for documenting C#/.NET code: doc-cs generates Russian-language XML-doc comments; doc-md generates external Markdown docs (one .md per class, mirrors solution structure); doc-db reverse-engineers an Oracle DB schema from raw ADO.NET code; doc-folder generates a single in-place README.md overview of a multi-project folder.",`

- [ ] **Step 5: marketplace.json — обновить plugins[0].description**

Edit:
- old_string: `      "description": "C#/.NET documentation skills (Russian output): doc-cs (inline XML-doc), doc-md (external Markdown, one file per class), doc-db (Oracle schema reverse-engineering from ADO.NET code).",`
- new_string: `      "description": "C#/.NET documentation skills (Russian output): doc-cs (inline XML-doc), doc-md (external Markdown, one file per class), doc-db (Oracle schema reverse-engineering from ADO.NET code), doc-folder (single in-place README.md folder overview).",`

- [ ] **Step 6: Валидировать оба JSON и проверить версию/наличие doc-folder**

Run:
```powershell
$p = Get-Content .claude-plugin\plugin.json -Raw | ConvertFrom-Json
$m = Get-Content .claude-plugin\marketplace.json -Raw | ConvertFrom-Json
"version=$($p.version)"
"plugin.desc has doc-folder: $($p.description -like '*doc-folder*')"
"market.desc has doc-folder: $($m.description -like '*doc-folder*')"
"market.plugin.desc has doc-folder: $($m.plugins[0].description -like '*doc-folder*')"
```
Expected:
```
version=1.1.0
plugin.desc has doc-folder: True
market.desc has doc-folder: True
market.plugin.desc has doc-folder: True
```
(Если `ConvertFrom-Json` бросает ошибку — JSON сломан, исправь синтаксис до коммита.)

- [ ] **Step 7: Commit**

```powershell
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "Register doc-folder in plugin manifests, bump to 1.1.0"
```

---

## Task 6: Финальная сводная валидация и ручная проверка

Убедиться, что плагин целостен, и описать ручной прогон (автотестов нет по решению пользователя).

**Files:** (только проверка, изменений нет)

- [ ] **Step 1: Проверить полную структуру нового skill**

Run:
```powershell
Get-ChildItem skills\doc-folder -Recurse -File | ForEach-Object { $_.FullName.Replace((Get-Location).Path + '\', '') }
```
Expected (три файла):
```
skills\doc-folder\SKILL.md
skills\doc-folder\assets\readme.md.template
skills\doc-folder\references\class-summary-style-ru.md
```

- [ ] **Step 2: Проверить, что рабочее дерево чистое (всё закоммичено)**

Run:
```powershell
git status --short
```
Expected: пустой вывод (нет незакоммиченных изменений).

- [ ] **Step 3: Сверить, что все 4 skill видны и frontmatter каждого валиден**

Run:
```powershell
Get-ChildItem skills -Directory | ForEach-Object {
  $f = Join-Path $_.FullName 'SKILL.md'
  $name = (Select-String -Path $f -Pattern '^name:\s*(.+)$').Matches.Groups[1].Value
  "$($_.Name) -> name: $name"
}
```
Expected:
```
doc-cs -> name: doc-cs
doc-db -> name: doc-db
doc-folder -> name: doc-folder
doc-md -> name: doc-md
```

- [ ] **Step 4: Ручная проверка (выполняет человек/агент, не автотест)**

Прогнать skill на реальной мульти-проектной папке и глазами оценить результат:

1. В сессии Claude Code вызвать: `/doc-folder <путь к реальной папке с .csproj>`
   (или попросить «сделай README для папки <путь>»).
2. Проверить, что создан `<путь>/README.md` и в нём:
   - frontmatter с `type: folder-overview`, `generator: doc-folder`, корректным
     списком `projects`;
   - сводная таблица всех `.csproj`-проектов папки;
   - на каждый public-тип — абзац 3-6 строк про назначение/логику (не одна
     строка, не таблица параметров);
   - относительные ссылки на `.cs` открываются;
   - строка ссылок на `documentation/...` присутствует только если та папка есть.
3. Повторно вызвать на той же папке — README должен полностью перегенерироваться
   без ошибок (всегда перезаписывается).

Контрольный чек-лист соответствия spec (§9 Критерии приёмки) —
`docs/superpowers/specs/2026-05-27-doc-folder-design.md`.

---

## Self-Review

- **Spec coverage:** §1 назначение/границы → Task 4 (SKILL.md description + «Когда отказаться»). §2 параметры/триггеры/frontmatter → Task 4 Step 1. §3 алгоритм 3 прохода → Task 4. §4 структура README + frontmatter → Task 2 (template) + Task 3 (schema). §5 формат класса → Task 1 (reference) + пример в Task 4. §6 всегда перезаписывать → Task 4 Pass 3 + «Соглашения». §7 файлы и манифесты → Tasks 1-5. §8 соглашения/запреты → Task 1 + Task 4. §9 критерии приёмки → Task 6 ручная проверка. Все секции покрыты.
- **Placeholder scan:** Плейсхолдеры вида `{{...}}` присутствуют ТОЛЬКО внутри `readme.md.template` (Task 2) — это намеренные слоты шаблона, а не пропуски плана. Все шаги содержат полное содержимое/команды.
- **Type/имя consistency:** `type: folder-overview`, `generator: doc-folder`, поля `root`/`projects`/`generated` одинаковы в Task 2 (template), Task 3 (schema), Task 4 (SKILL.md ссылается на schema). Имена файлов и пути совпадают между File Structure и задачами.
