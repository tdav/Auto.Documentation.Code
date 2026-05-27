# Эталонные примеры «до / после» (few-shot)

> Образцы стиля для `doc-cs`, извлечённые из реального кода проекта (ADO.NET +
> `Oracle.ManagedDataAccess`, namespace `Sample`). Claude переносит этот стиль на
> новый код. Формат: блок «До» (код как есть) и «После» (с XML-doc).
>
> **Точность по коду важнее гипотез.** Например, GUID-колонки в этом проекте
> хранятся НЕ как `RAW(16)`: `SV_GUID` биндится `OracleDbType.Int64` (числовой),
> а `TV_GUID`/`TV_REQUESTGUID` — `OracleDbType.Varchar2` (строковый). Документируй
> то, что видишь в `Parameters.Add(...)` и `dr[...].ToXxx()`, а не дефолтную
> эвристику.

---

## Пример 1 — INSERT справочника с проверкой уникальности

**До** (`SvItemDao.Insert`):

```csharp
public SvItemModel Insert(SvItemModel model)
{
    if (model == null) throw new AppException(2, "Маълумот берилмаган", "Model==null");
    model.Validate();
    // SELECT SV_ID ... WHERE SV_ID = '{model.Id}' AND SV_RECORDSTATUS=1  → дубликат?
    // INSERT INTO DICT.SV_ITEM (...14 колонок...) VALUES (...)
    return model;
}
```

**После:**

```csharp
/// <summary>
/// Добавляет новую запись в справочник «Уровни доступа»
/// (<c>DICT.SV_ITEM</c>), предварительно проверяя, что код ещё не занят
/// активной записью.
/// </summary>
/// <remarks>
/// Перед вставкой выполняет <c>SELECT</c> по <c>SV_ID</c> среди активных
/// записей (<c>SV_RECORDSTATUS = 1</c>); при совпадении прерывается с
/// исключением. В <c>INSERT</c> наименование раскладывается по языковым
/// колонкам <c>SV_NAME00</c>..<c>SV_NAME05</c> (<c>SV_NAME03</c> —
/// транслитерация в латиницу). <c>SV_RECORDSTATUS</c> и <c>SV_USER</c>
/// жёстко заданы значением <c>1</c>, <c>SV_DATEENTER</c> — <c>SYSDATE</c>.
/// <c>SV_GUID</c> передаётся как число (<c>OracleDbType.Int64</c>).
/// </remarks>
/// <param name="model">
/// Модель новой записи; проходит <see cref="SvItemModel.Validate"/>
/// перед вставкой.
/// </param>
/// <returns>Та же модель <paramref name="model"/>.</returns>
/// <exception cref="AppException">
/// Код 2 — если <paramref name="model"/> равен <see langword="null"/>.
/// </exception>
/// <exception cref="System.Exception">
/// Если активная запись с тем же <c>SV_ID</c> уже существует.
/// </exception>
public SvItemModel Insert(SvItemModel model) { /* … */ }
```

---

## Пример 2 — soft-delete через UPDATE

**До** (`SvItemDao.Delete`):

```csharp
public Int64 Delete(Int64 inId)
{
    if (inId <= 0) throw new AppException(2, "Маълумот берилмаган", "Model==null");
    // UPDATE DICT.SV_ITEM SET SV_RECORDSTATUS = 0 WHERE SV_ID = :p_ID
}
```

**После:**

```csharp
/// <summary>
/// Логически удаляет запись справочника «Уровни доступа», переводя
/// <c>SV_RECORDSTATUS</c> в <c>0</c>; физически строка сохраняется.
/// </summary>
/// <remarks>
/// Выполняет <c>UPDATE DICT.SV_ITEM SET SV_RECORDSTATUS = 0 WHERE
/// SV_ID = :p_ID</c>. Это soft-delete: запись остаётся в истории и
/// перестаёт попадать в выборки активных строк (<c>SV_RECORDSTATUS = 1</c>).
/// </remarks>
/// <param name="inId">Первичный ключ удаляемой записи (<c>SV_ID</c>).</param>
/// <returns>Число обновлённых строк (ожидается 1).</returns>
/// <exception cref="AppException">
/// Код 2 — если <paramref name="inId"/> ≤ 0; код 5 — если активная запись
/// с таким <c>SV_ID</c> не найдена.
/// </exception>
public Int64 Delete(Int64 inId) { /* … */ }
```

---

## Пример 3 — async INSERT большой транзакционной таблицы

**До** (`TvRequestDao.InsertAsync`):

```csharp
public async Task<TvRequestModel> InsertAsync(TvRequestModel model)
{
    if (model == null) throw new AppException(2, "Маълумот берилмаган", "Model==null");
    model.Validate();
    model.PreviousId = await new CheckUnique("APP.TV_REQUEST").GetPreviuosIdAsync(model.Guid, DbConnection);
    model.Id = new Sequence().GetSequence("APP.SQ_TV_REQUEST", DbConnection);
    // INSERT INTO APP.TV_REQUEST (...~60 колонок...) VALUES (...)
    await new Application.Application(DbConnection).InsertAsync(new ModelApplication(model));
    return model;
}
```

**После:**

```csharp
/// <summary>
/// Регистрирует новую заявку в таблице
/// <c>APP.TV_REQUEST</c> и создаёт связанную запись приложения.
/// </summary>
/// <remarks>
/// Идентификатор берётся из последовательности
/// <c>APP.SQ_TV_REQUEST</c>; <c>TV_PREVIOUSID</c> — из предыдущей
/// версии записи с тем же <c>TV_GUID</c> (версионирование). Один <c>INSERT</c>
/// на ~60 колонок (данные записи, вложенные блоки, суммы, статусы),
/// <c>TV_DATEENTER</c> = <c>SYSDATE</c>. После вставки вызывает
/// <see cref="Application.Application.InsertAsync"/> для журнала приложений.
/// <c>TV_GUID</c> и <c>TV_REQUESTGUID</c> хранятся как строки
/// (<c>VARCHAR2</c>), не как <c>RAW</c>.
/// </remarks>
/// <param name="model">
/// Модель заявки; проходит <see cref="TvRequestModel.Validate"/>.
/// </param>
/// <returns>
/// Та же модель с заполненными <see cref="TvRequestModel.Id"/> и
/// <see cref="TvRequestModel.PreviousId"/>.
/// </returns>
/// <exception cref="AppException">
/// Код 2 — если <paramref name="model"/> равен <see langword="null"/>.
/// </exception>
/// <exception cref="Oracle.ManagedDataAccess.Client.OracleException">
/// При нарушении ограничений целостности таблицы.
/// </exception>
public async Task<TvRequestModel> InsertAsync(TvRequestModel model) { /* … */ }
```

---

## Пример 4 — async SELECT по GUID с маппингом

**До** (`TvRequestDao.GetAsync`):

```csharp
public async Task<TvRequestModel> GetAsync(string inGuid, Language language)
{
    if (inGuid.IsEmpty()) throw new AppException(2, "Маълумот берилмаган", "Model==null");
    // SELECT * FROM APP.TV_REQUEST WHERE TV_RECORDSTATUS = 1 AND TV_GUID = :p_GUID
    // oda.Fill(dt) внутри Task.Run; mapping.SetModel(dr, language)
}
```

**После:**

```csharp
/// <summary>
/// Загружает активную заявку по её глобальному идентификатору
/// <c>TV_GUID</c> из <c>APP.TV_REQUEST</c>.
/// </summary>
/// <remarks>
/// <c>SELECT * ... WHERE TV_RECORDSTATUS = 1 AND TV_GUID = :p_GUID</c>;
/// строка результата маппится через
/// <see cref="TvRequestMapping.SetModel(System.Data.DataRow, Language)"/>.
/// Заполнение <see cref="System.Data.DataTable"/> обёрнуто в
/// <see cref="System.Threading.Tasks.Task.Run"/>, так как
/// <see cref="Oracle.ManagedDataAccess.Client.OracleDataAdapter"/>
/// синхронный.
/// </remarks>
/// <param name="inGuid">Значение <c>TV_GUID</c> искомой заявки.</param>
/// <param name="language">Язык декодирования справочных значений.</param>
/// <returns>Заполненная модель заявки.</returns>
/// <exception cref="AppException">
/// Код 2 — если <paramref name="inGuid"/> пуст; код 5 — если активная
/// заявка не найдена.
/// </exception>
public async Task<TvRequestModel> GetAsync(string inGuid, Language language) { /* … */ }
```

---

## Пример 5 — маппер DataRow → модель

**До** (`TvRequestMapping.SetModel`):

```csharp
public TvRequestModel SetModel(DataRow dr, Language language)
{
    return new TvRequestModel()
    {
        Id = dr["TV_ID"].ToInt64(),
        Guid = dr["TV_GUID"].ToStr(),
        PreviousId = dr["TV_PREVIOUSID"].ToNullableInt64(),
        // ... десятки колонок, вложенные Person / RequestStatus / TvRequestData
    };
}
```

**После:**

```csharp
/// <summary>
/// Преобразует строку <see cref="DataRow"/> таблицы
/// <c>APP.TV_REQUEST</c> в модель <see cref="TvRequestModel"/>,
/// декодируя справочные коды на указанный язык.
/// </summary>
/// <remarks>
/// Колонки читаются через extension-конвертеры (<c>ToInt64</c>, <c>ToStr</c>,
/// <c>ToNullableInt64</c>, <c>ToNullableDateTime</c>). Вложенный блок
/// <see cref="TvRequestDataModel"/> заполняется только при непустом
/// <c>TV_PROTOCOLSERIALNUMBER</c>; блок <see cref="ModelRequestLink"/> —
/// только при непустом <c>TV_REQUEST</c>. Справочные значения
/// (<c>TV_RECORDSTATUS</c>, <c>TV_DIVISION</c>, <c>TV_SEX</c> и др.)
/// декодируются через <see cref="Dictionaries.DecModel"/>.
/// </remarks>
/// <param name="dr">Строка результата запроса к <c>TV_REQUEST</c>.</param>
/// <param name="language">Язык декодирования справочников.</param>
/// <returns>Модель заявки, заполненная из <paramref name="dr"/>.</returns>
public TvRequestModel SetModel(DataRow dr, Language language) { /* … */ }
```
