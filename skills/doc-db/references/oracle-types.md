# Маппинг OracleDbType → Oracle SQL → .NET

Используется в Pass 2 для определения типа колонки. Источник — Oracle Data
Provider for .NET (ODP.NET) на docs.oracle.com.

| OracleDbType | Oracle SQL | `dr.To*()` | Документируется как |
|---|---|---|---|
| `Int64` | `NUMBER(19)` | `ToInt64()` | `NUMBER(19)` / целое |
| `Int32` | `NUMBER(10)` | `ToInt32()` | `NUMBER(10)` / целое |
| `Int16` | `NUMBER(5)` | `ToInt16()` | `NUMBER(5)` / целое |
| `Varchar2` | `VARCHAR2(n)` | `ToStr()` | `VARCHAR2` / строка |
| `NVarchar2` | `NVARCHAR2(n)` | `ToStr()` | `NVARCHAR2` (Юникод) |
| `Char` | `CHAR(n)` | `ToStr()` | `CHAR` (фикс. длина) |
| `Date` | `DATE` | `ToDateTime()` / `ToNullableDateTime()` | дата-время |
| `TimeStamp` | `TIMESTAMP` | `ToDateTime()` / `ToNullableDateTime()` | метка времени |
| `Decimal` | `NUMBER(p,s)` | `ToDecimal()` | `NUMBER` (десятичное) |
| `Double` | `BINARY_DOUBLE` | `ToDouble()` | число с плав. точкой |
| `Clob` | `CLOB` | `ToStr()` (большие строки) | `CLOB` |
| `NClob` | `NCLOB` | `ToStr()` | `NCLOB` |
| `Blob` | `BLOB` | `byte[]` | `BLOB` |
| `Raw` (16) | `RAW(16)` | `ToGuid()` | `RAW(16)` (GUID) |

## Приоритет определения типа

1. **`OracleDbType` из bind-параметра** — самый надёжный источник.
2. **`.ToXxx()`-конвертер** при чтении `DataRow` — если bind не найден.
3. **Эвристика по имени колонки** (см. `naming-conventions.md`) — последний
   резерв:
   - `*_ID`, `*_PREVIOUSID` → `NUMBER(19)`
   - `*_GUID` → `RAW(16)`
   - `*_DATE*`, `*_DATEENTER`, `*_DATEUPDATE` → `DATE`
   - `*_NAME*`, `*_COMMENT` → `VARCHAR2` / `NVARCHAR2`
   - `*_RECORDSTATUS` → `NUMBER(1)`

Длину (`n`, `p,s`) из кода обычно не видно — оставляй `VARCHAR2(…)`, `NUMBER`.
