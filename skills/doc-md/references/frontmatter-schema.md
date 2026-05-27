# Единая схема YAML-frontmatter

Каждый генерируемый `.md`-файл начинается с этого frontmatter. Единый формат
служит сразу трём потребителям: AI/RAG (метаданные для поиска), GitHub/grep
(`grep "^tables:"`), статическому сайту (DocFX/MkDocs читают frontmatter).

> **Критично при параллельной генерации.** Все субагенты обязаны прочитать этот
> файл перед записью. Имена и регистр полей менять нельзя — иначе поиск по полю
> ломается (`namespace` ≠ `Namespace` ≠ `ns`).

## Схема для класса (`type: class`)

```yaml
---
title: SvItemDao                      # имя класса, как в коде
type: class                            # class | interface | enum
namespace: Sample.Dico                   # полное пространство имён
layer: data-access                     # см. допустимые значения ниже
source: src/Dico/SvItemDao.cs         # относительный путь к .cs от корня репо
tables: [DICT.SV_ITEM]               # таблицы Oracle, которые класс трогает; [] если нет
tags: [repository, oracle, crud]       # свободные теги, нижний регистр, kebab-case
summary: Репозиторий справочника «Уровни доступа».   # ОДНА строка, с точкой
---
```

## Схема для схемы БД (`type: database-schema`) — файл `database.md`

```yaml
---
title: Структура БД проекта <название>
type: database-schema
tables: [DICT.SV_ITEM, APP.TV_REQUEST]   # все таблицы файла
tags: [oracle, schema, reverse-engineered]
summary: Схема БД, восстановленная из ADO.NET-кода.
---
```

## Схема для обзора папки (`type: folder-overview`) — файл `README.md`

Генерируется skill `doc-folder`: один обзорный `README.md` в корне папки.

```yaml
---
title: Sample.Solution — обзор кода   # имя документируемой папки
type: folder-overview
generator: doc-folder                  # метка происхождения файла
root: .                                # относительный путь документируемой папки
projects: [Sample.Dico, Sample.App]   # имена .csproj-проектов папки
generated: 2026-05-27                  # дата генерации (YYYY-MM-DD)
tags: [overview, csharp, navigation]
summary: Обзорная карта классов мульти-проектной папки.   # одна строка, с точкой
---
```

## Правила полей

| Поле | Обяз. | Тип | Правила |
|---|---|---|---|
| `title` | да | строка | Без кавычек, если нет спецсимволов YAML (`:`, `#`). |
| `type` | да | enum | `class` \| `interface` \| `enum` \| `database-schema` \| `folder-overview` \| `index`. Только нижний регистр. |
| `namespace` | для class | строка | Как в коде. |
| `layer` | для class | enum | `data-access` \| `service` \| `model` \| `mapping` \| `controller` \| `util` \| `test` \| `other`. |
| `source` | для class | путь | Относительный от корня репозитория, через `/`. |
| `tables` | для class / database-schema | список | Имена в формате `СХЕМА.ТАБЛИЦА`. Пустой список `[]`, если класс не работает с БД. **Это мост к `doc-db`.** |
| `tags` | да | список | Нижний регистр, kebab-case. 2–5 тегов. |
| `summary` | да | строка | Одно предложение, с точкой. Без переносов. |
| `generator` | для folder-overview | строка | Имя skill-генератора, напр. `doc-folder`. Метка происхождения файла. |
| `root` | для folder-overview | путь | Относительный путь документируемой папки (`.` если это корень). |
| `projects` | для folder-overview | список | Имена `.csproj`-проектов в папке. |
| `generated` | для folder-overview | дата | Дата генерации в формате `YYYY-MM-DD`. |

## Как заполнять `tables`

Просканируй тело класса на SQL-литералы (`INSERT INTO`, `FROM`, `UPDATE`,
`DELETE FROM`) и обращения `dr["..."]`. Перечисли все упомянутые таблицы в
формате `СХЕМА.ТАБЛИЦА`. Это поле связывает класс с разделами `database.md`
(skill `doc-db`) и позволяет за один переход находить, какой код трогает таблицу.

## Как выбирать `layer`

- `data-access` — репозитории/DAO с прямым SQL (`OracleCommand`, `DataRow`).
- `mapping` — мапперы `DataRow → модель`.
- `model` — DTO/модели данных.
- `service` — бизнес-логика, оркестрация.
- `controller` — контроллеры API/UI.
- `util` — вспомогательные утилиты.
- `test` — классы тестовых проектов (NUnit/xUnit/MSTest).
- `other` — если не подходит ничего выше.
