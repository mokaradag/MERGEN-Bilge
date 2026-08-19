# Proje ve Kaynak Analizi — Salt-Okunur SQL Kapısı

Bu belge, PR #705 üzerindeki güncel `pk_sql_classify_readonly()` sözleşmesini açıklar. Amaç, üretim sorgu kütüphanesini değiştirmeden SQL Server/SSMS ile uyumlu sorguları çalıştırabilmek ve aynı anda D23 ile getirilen fail-closed güvenlik sınırını korumaktır.

## Güncel sözleşme

Kapı normalde yalnızca tek bir salt-okunur `SELECT` veya son ifadesi `SELECT` olan bir CTE zincirini kabul eder. Bunun tek dar batch istisnası şudur:

```sql
SET NOCOUNT ON;
<tek bir salt-okunur SELECT veya CTE + SELECT>
```

Bu istisna SQL Server sorgu kütüphanesinde bulunan ve SSMS'te çalışan sorguların R/ODBC yolunda da kullanılabilmesi içindir. `SET NOCOUNT ON` sonuç satırlarını veya veritabanı verisini değiştirmez; yalnızca etkilenen satır sayısı mesajlarının gönderilmesini bastırır.

**Sorgu dosyası değiştirilmez.** Kapıdan geçen batch metni ile yürütme katmanına verilen batch metni aynıdır. Böylece sorgu kütüphanesinde ayrı bir R sürümü veya otomatik SQL yeniden yazımı oluşmaz.

## İzin verilen örnekler

```sql
SELECT * FROM SentetikTablo;
```

```sql
WITH c AS (
    SELECT 1 AS a
)
SELECT * FROM c;
```

```sql
SET NOCOUNT ON;
WITH c AS (
    SELECT 1 AS a
)
SELECT * FROM c
OPTION (RECOMPILE);
```

Başta yorum bulunması, CR/LF/CRLF satır sonları veya sondaki noktalı virgül bu sözleşmeyi değiştirmez.

## Reddedilen örnekler

Aşağıdaki biçimler fail-closed olarak reddedilir:

```sql
SET NOCOUNT OFF;
SELECT * FROM t;
```

```sql
SET ANSI_NULLS ON;
SELECT * FROM t;
```

```sql
SET NOCOUNT ON;
DELETE FROM t;
```

```sql
SET NOCOUNT ON;
SELECT 1;
SELECT 2;
```

```sql
SET NOCOUNT ON;
EXEC dbo.BirYordam;
```

Ayrıca mevcut D23 korumaları aynen sürer: `MERGE`, `INSERT`, `UPDATE`, `DELETE`, `SELECT ... INTO`, veri değiştiren CTE, DDL/DCL, `BACKUP`/`RESTORE`, `EXEC`/`EXECUTE`, `sp_`/`xp_`, `NEXT VALUE FOR`, tanınmayan/ayrıştırılamayan sözdizimi ve gerçek çok ifadeli batch'ler kabul edilmez.

## Neden kapıyı genel olarak gevşetmiyoruz?

`SET NOCOUNT ON` için genel bir "SET komutlarına izin ver" kuralı yoktur. İstisna, maskelenmiş ilk ifadenin tam olarak `SET NOCOUNT ON` olması ve batch'te yalnızca bir ikinci çalıştırılabilir ifade bulunması şartıyla uygulanır. İkinci ifade daha sonra normal salt-okunur kapısının tüm yasaklı anahtar kelime, saklı yordam, sequence ve `SELECT`/CTE kontrollerinden geçer.

Bu nedenle değişiklik, çok ifadeli batch'leri genel olarak açmaz ve mevcut güvenlik ratchet'lerini gevşetmez.

## Yürütme yolları

Aynı sınıflandırıcı aşağıdaki yollar için ortaktır:

- normal Proje ve Kaynak Analizi,
- v2 motoru,
- Deep Analysis,
- Faz 3b metadata üreticisi.

Bu ortaklık önemlidir: `health.txt` içinde kabul edilen bir sorgunun uygulama çalıştırma yolunda farklı bir güvenlik kuralına takılması veya tersinin olması istenmez.

## Test sözleşmesi

`tests/testthat/test-pk-sql-readonly-gate-contract.R` şu sınırları kilitler:

- `SET NOCOUNT ON;` + tek `SELECT` kabul edilir,
- `SET NOCOUNT ON;` + tek CTE/`SELECT` + `OPTION (RECOMPILE)` kabul edilir,
- `SET NOCOUNT OFF` ve başka `SET` biçimleri reddedilir,
- `NOCOUNT` arkasındaki yazma/`EXEC` biçimleri reddedilir,
- `NOCOUNT` arkasındaki ek ikinci sorgu reddedilir,
- D23'ün mevcut write/DDL/DCL/sequence/literal/comment/CRLF korumaları korunur.

## Operatör notu

`health.txt` içinde daha önce aşağıdaki gibi görülen bir bulgu:

```text
[blocking] sql_not_readonly: ... gerekce=multiple_statements
```

sorgunun tek ek ifadesi `SET NOCOUNT ON;` ve devamı güvenli bir `SELECT`/CTE ise artık bu nedenle oluşmamalıdır. Başka bir session ayarı veya ek ifade varsa `sql_not_readonly` beklenen ve doğru davranıştır.

Faz 3b çalışma adımları ve sağlık raporu yorumlama için [`pk-phase3b-operator-runbook.md`](pk-phase3b-operator-runbook.md) kullanılmalıdır.

## Master plan notu

`proje-kaynak-analizi-master-plan.md` içindeki D23, temel güvenlik hedefini hâlâ doğru tanımlar: fail-closed, statement-aware ve tüm yürütme yollarında ortak bir salt-okunur kapı. Bu belgedeki **tam `SET NOCOUNT ON;` öneki istisnası**, üretim SQL kütüphanesiyle doğrulanan uyumluluk gereksinimi nedeniyle D23'ün "hiç ikinci ifade yok" ifadesine yapılan dar uygulama düzeltmesidir. Başka hiçbir çok-ifade biçimi için emsal oluşturmaz.
