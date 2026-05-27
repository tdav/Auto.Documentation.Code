# Алгоритм извлечения схемы (regex + псевдокод)

Полные шаблоны для Pass 1 и логика склейки многострочных SQL для Pass 2.

## Regex для Pass 1 (через Grep)

### 1) SQL-литералы

```regex
INSERT\s+INTO\s+(?<table>[A-Z0-9_.]+)\s*\(\s*(?<cols>[^)]+)\s*\)\s*VALUES\s*\(\s*(?<vals>[^)]+)\s*\)
UPDATE\s+(?<table>[A-Z0-9_.]+)\s+SET\s+(?<sets>.+?)\s+WHERE\s+(?<where>.+?)["@]
SELECT\s+(?<cols>.+?)\s+FROM\s+(?<table>[A-Z0-9_.]+)\b
DELETE\s+FROM\s+(?<table>[A-Z0-9_.]+)\b
```

### 2) Bind-параметры

```regex
\.Parameters\.Add\(\s*"(?<pname>:?p_[A-Z0-9_]+)"\s*,\s*OracleDbType\.(?<otype>[A-Za-z0-9]+)
```

### 3) DataRow-маппинг

```regex
dr\[\s*"(?<col>[A-Z0-9_]+)"\s*\]\s*\.\s*(?<conv>ToInt64|ToInt32|ToStr|ToString|ToDateTime|ToNullableInt64|ToNullableInt32|ToNullableDateTime|ToDecimal|ToBool|ToGuid|ToClob)\s*\(\)
```

> Конвенция `dr["COL"].ToXxx()` подтверждена для целевого проекта. Если в вашем
> коде иначе (`dr.GetInt64(i)`, `Convert.ToInt64(dr[..])`, ORM-маппинг) —
> добавьте свои варианты в группу `conv` и в шаблон №3.

## Pass 2 — склейка многострочных SQL (псевдокод)

Regex рвётся на SQL, собранных через конкатенацию или интерполяцию. Claude
склеивает их обратно семантически:

```text
для каждого .cs-файла:
    найди начало SQL-литерала: @"..." или $"..." или "..." с ключевым словом
        (INSERT|UPDATE|SELECT|DELETE)
    пока строка продолжается оператором + или $"...{var}..." или verbatim @"":
        присоедини следующий фрагмент
    нормализуй пробелы и переносы
    убери интерполяционные вставки {var} → оставь маркер <expr> (не колонка)
    примени regex SQL-литералов к собранной строке
```

Особые случаи:
- **Конкатенация:** `@"INSERT INTO T (" + cols + ") VALUES (..."` — список
  колонок в переменной; ищи объявление `cols` рядом.
- **StringBuilder:** собери из `.Append("...")` по порядку.
- **Интерполяция:** `$"... WHERE ID = {id}"` — `{id}` это bind, не колонка.

## Формат `_tmp/sql-facts.json` (опциональный prescan)

Для проектов > 200 файлов `scripts/prescan.sh` выгружает факты, чтобы не
сжигать контекст на сам скан:

```json
{
  "tables": {
    "DICT.SV_ITEM": {
      "insertColumns": ["SV_ID", "SV_GUID", "SV_PREVIOUSID", "..."],
      "selectColumns": ["SV_ID", "SV_NAME00"],
      "whereColumns": ["SV_ID"],
      "binds": { ":p_ID": "Int64", ":p_GUID": "Raw" },
      "dataRowReads": { "SV_ID": "ToInt64", "SV_GUID": "ToGuid" },
      "sourceFiles": ["DataAccess/SvItemDao.cs"]
    }
  }
}
```

Claude читает этот JSON вместо повторного скана исходников и переходит сразу к
Pass 2.

## Триггеры пересмотра regex

| Симптом | Действие |
|---|---|
| В `database.md` появляется `UNKNOWN_TABLE` | Расширь regex SQL-литералов — вероятно экзотический синтаксис склейки. |
| Колонки теряются | Проверь конкатенацию/StringBuilder; добавь шаблон. |
| Тип всегда «по имени» | bind-параметры не матчатся — проверь шаблон №2 (формат имени параметра). |
