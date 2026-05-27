---
name: doc-db
description: >
  Реконструирует структуру реляционной БД проекта (Oracle) ИСКЛЮЧИТЕЛЬНО
  из исходного кода: SQL-строк-литералов в C# (INSERT/UPDATE/SELECT/DELETE
  с bind-параметрами :p_*), вызовов OracleDbType.* и обращений к
  DataRow["COL"].ToInt64()/ToStr()/ToDateTime()/ToNullableInt64() в
  mapping-классах. НЕ читает EF Core, НЕ читает .sql-файлы, НЕ подключается
  к БД. Результат — файлы *.md в папке documentation/ на РУССКОМ с разделами по
  каждой таблице: назначение, колонки с типами и описаниями, связи (FK
  выводятся эвристически по именам и помечаются «предположительно»).
  Используй skill, когда пользователь говорит «опиши БД», «сделай
  database.md», «реверсни схему из кода», «какие таблицы используются»,
  «doc-db» — даже если он не использует слово «schema». Это НЕ генератор
  C#-комментариев (для этого — doc-cs).
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Write, Bash
argument-hint: путь к корню проекта или к папке DA-классов
---

# doc-db — реверс-инжиниринг схемы БД из C#-кода

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

### Pass 3 — сохранение результата

1. **Frontmatter.** Каждый файл начинай с YAML-frontmatter (`type:
   database-schema`, `tables:` со списком всех таблиц файла) по образцу
   `assets/database.md.template`. Имена полей должны соответствовать секции
   `database-schema` единой схемы `../doc-md/references/frontmatter-schema.md`
   (единый источник истины) — это держит формат общим с `doc-md` для поиска,
   RAG и статических генераторов.
2. **Обратные ссылки код↔БД.** В блоке «Используется в коде» каждой таблицы
   ставь ссылку на `.md`-файл класса, сгенерированный `doc-md` (каталог
   `documentation/api/`). Путь считай от файла схемы: для `database.md` в корне
   `documentation/` это `api/<mirror>/Class.md` (например, для `Sample.Dico` —
   `api/Dico/SvItemDao.md`; середина пути берётся из структуры solution,
   которую зеркалит `doc-md`). Это обратный мост: из таблицы — к коду, который
   её трогает; в обратную сторону класс ссылается на таблицу через своё поле
   `tables:`.
3. Сохрани каждый `.md` через `Write` по пути `documentation/<имя>.md`
   (например, `documentation/database.md`). `Write` создаёт папку автоматически.
4. Если схема большая и разбита по модулям — допустимо несколько файлов
   (`documentation/dict.md`, `documentation/app.md` и т.д.), но всегда
   в папке `documentation/`.

> **Без параллелизма.** `doc-db` агрегирует факты в сводный файл, а не работает
> пофайлово, — субагенты тут не нужны (в отличие от `doc-cs`/`doc-md`).

## Соглашения проекта (учитывай!)

- `SV_*` — справочники (Static Values), схема `DICT`.
- `TV_*` — транзакционные таблицы (Transaction Values), обычно `APP`.
- `*_RECORDSTATUS` — soft-delete: `1` активна, `0` удалена.
- `*_USER`, `*_DATEENTER`, `*_COMMENT` — аудит.
- `*_NAME00`..`*_NAME05` — мультиязычные (00 — основной, далее переводы;
  точную раскладку языков попроси у пользователя один раз и зафиксируй
  в шапке database.md).

> Эти соглашения — **дефолты**. Перед серьёзным прогоном сверь их с
> `references/naming-conventions.md` и поправь под свою базу.

## Формат вывода

Все сгенерированные файлы сохраняются в папку `documentation/` в корне
проекта (создаётся автоматически через `Bash: mkdir -p documentation`).
Пример итогового файла — `documentation/database.md`.

Полный шаблон — `assets/database.md.template`. Пример итогового файла:

````markdown
---
title: Структура БД проекта <название>
type: database-schema
tables: [DICT.SV_ITEM, APP.TV_REQUEST]
tags: [oracle, schema, reverse-engineered]
summary: Схема БД, восстановленная из ADO.NET-кода.
---

# Структура БД проекта <название>

> Восстановлена автоматически из исходного кода (skill `doc-db`).
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
**Назначение.** Справочник ролей/уровней доступа пользователей клиентского
приложения. Используется при отрисовке дерева прав. Источник: `SvItemDao.cs`.

| Колонка | Тип Oracle | .NET / DataRow | Назначение |
|---|---|---|---|
| `SV_ID` | `NUMBER(19)` | `ToInt64()` | **PK.** Суррогатный идентификатор. |
| `SV_GUID` | `RAW(16)` | `ToGuid()` | Глобальный уникальный идентификатор для синхронизации. |
| `SV_PREVIOUSID` | `NUMBER(19)` | `ToNullableInt64()` | Самоссылка на предыдущую версию (версионирование). FK → `DICT.SV_ITEM.SV_ID`. |
| `SV_RECORDSTATUS` | `NUMBER(1)` | `ToInt32()` | Soft-delete. |
| `SV_USER` | `NUMBER(19)` | `ToInt64()` | Аудит: ID пользователя. **Предположительно** FK → `DICT.SV_USER.SV_ID`. |
| `SV_DATEENTER` | `DATE` | `ToDateTime()` | Аудит: дата создания/изменения. |
| `SV_COMMENT` | `VARCHAR2(…)` | `ToStr()` | Комментарий пользователя. |
| `SV_NAME00` | `NVARCHAR2(…)` | `ToStr()` | Наименование (локаль 0). |
| `SV_NAME01` | `NVARCHAR2(…)` | `ToStr()` | Наименование (локаль 1). |
| `SV_NAME02` | `NVARCHAR2(…)` | `ToStr()` | Наименование (локаль 2). |
| `SV_NAME03` | `NVARCHAR2(…)` | `ToStr()` | Наименование (локаль 3). |
| `SV_NAME04` | `NVARCHAR2(…)` | `ToStr()` | Резервная языковая колонка. |
| `SV_NAME05` | `NVARCHAR2(…)` | `ToStr()` | Резервная языковая колонка. |
| `SV_SYSTEM` | `NUMBER(19)` | `ToInt64()` | FK на справочник систем. **Предположительно** → `DICT.SV_SYSTEM.SV_ID`. |

**Связи.**
- `SV_PREVIOUSID` → `DICT.SV_ITEM.SV_ID` (self, версионирование).
- `SV_USER` → `DICT.SV_USER.SV_ID` (предположительно).
- `SV_SYSTEM` → `DICT.SV_SYSTEM.SV_ID` (предположительно).

**Используется в коде.**
- [`SvItemDao`](api/DataAccess/Dico/SvItemDao.md) → `Insert(SvItem)` — INSERT всех 14 колонок.
- [`SvItemDao`](api/DataAccess/Dico/SvItemDao.md) → `Update(SvItem)` — UPDATE по `SV_ID`.
- [`SvItemDao`](api/DataAccess/Dico/SvItemDao.md) → `GetById(long)` — SELECT по `SV_ID`.
- [`SvItemDao`](api/DataAccess/Dico/SvItemDao.md) → `GetAll()` — SELECT с фильтром `SV_RECORDSTATUS = 1`.

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
````

## Что делать НЕ нужно
- Не выдумывай таблицы и колонки, которых нет в коде.
- Не утверждай FK как факт без явного JOIN-условия — пиши «предположительно».
- Не лезь в EF Core-миграции, не запускай `dotnet ef dbcontext scaffold`.
- Не подключайся к реальной БД.

## Когда отказаться
Если просят «добавь summary к классу» — это `doc-cs`, переключайся.
