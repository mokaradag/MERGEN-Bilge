# Proje ve Kaynak Analizi — SQL Salt-Okunur Kapısı ve Faz 3b Uyumluluğu

**Durum:** 20 Ağustos 2026 itibarıyla Windows VM'de doğrulandı.

Bu belge, `R/helpers_pk_sql_readonly.R` ile Faz 3b metadata üreticisinin birlikte uyguladığı SQL güvenlik/uyumluluk sözleşmesinin **nihai durumunu** açıklar. Operatör adımları için [`pk-phase3b-operator-runbook.md`](pk-phase3b-operator-runbook.md), genel tasarım için [`proje-kaynak-analizi-master-plan.md`](proje-kaynak-analizi-master-plan.md) §5.1 okunmalıdır.

Bu değişikliklerin amacı salt-okunur kapısını gevşetmek değil, üretimde zaten çalışan iki güvenli SQL Server biçimini kapalı-başarısız kurallar altında açıkça tanımaktır:

1. `SET NOCOUNT ON;` + tek salt-okunur `SELECT`/CTE.
2. Yalnızca yerel `#temp` tablolarla staging yapan ve sonunda tek salt-okunur sonuç `SELECT`'i döndüren analitik batch.

## 1. Korunan temel kural

Kapı hâlâ **fail-closed** çalışır. Varsayılan olarak yalnızca tek bir salt-okunur `SELECT`, son gövdesi `SELECT` olan CTE veya eşdeğer parantezli `SELECT` kabul edilir. Ayrıştırma belirsizse sorgu çalıştırılmaz.

Aşağıdaki aileler reddedilmeye devam eder:

- `MERGE`, `INSERT`, `UPDATE`, `DELETE`, `UPSERT`;
- kalıcı `CREATE`, `DROP`, `ALTER`, `TRUNCATE`, `RENAME`;
- `GRANT`, `DENY`, `REVOKE`;
- `EXEC`/`EXECUTE`, `sp_`, `xp_`;
- genel `SELECT ... INTO`;
- genel `SET`, `DECLARE`, `USE`, `GO`, transaction ifadeleri;
- `OPENROWSET`, `OPENQUERY`, `OPENDATASOURCE`, `BULK` ve benzeri dış erişim biçimleri;
- `NEXT VALUE FOR` gibi `SELECT` görünümünde olsa da sunucu durumunu değiştiren ifadeler.

Literal, yorum ve tırnaklı/köşeli tanımlayıcı içindeki sözcükler güvenlik anahtar kelimesi sayılmaz; sınıflandırıcı önce bu bölgeleri maskeler.

## 2. Güvenli `SET NOCOUNT ON` öneki

SQL Server sorgu kütüphanesinde yaygın olan şu biçim artık kabul edilir:

```sql
SET NOCOUNT ON;
WITH x AS (...)
SELECT ...
```

veya:

```sql
SET NOCOUNT ON;
SELECT ...
```

İstisna **yalnızca tam `SET NOCOUNT ON` ifadesidir**. Başka bir `SET` biçimi, ek bir üçüncü ifade veya arkasında salt-okunur olmayan SQL varsa sorgu normal kapalı-başarısız kurala döner ve reddedilir.

Bu uyumluluk, `SET` anahtar kelimesini genel olarak güvenli saymaz ve yasaklı anahtar kelime listesini azaltmaz.

## 3. Yerel `#temp` analitik batch sözleşmesi

Çok ifadeli bir batch yalnızca `pk_sql_analyze_local_temp_batch()` aşağıdaki yapıyı eksiksiz kanıtlayabilirse kabul edilir:

```sql
IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;
SELECT ... INTO #T ...;

-- Aynı çift başka yerel #temp tablolar için tekrarlanabilir.

SELECT ...
FROM #T ...;

DROP TABLE #T;
```

Kurallar:

- yalnızca **yerel** `#temp` adları kabul edilir; `##global` temp tablolar kabul edilmez;
- her staging tablosu için önce aynı adı hedefleyen `OBJECT_ID('tempdb..#T') ... DROP TABLE #T` koruması bulunmalıdır;
- staging ifadesi `SELECT ... INTO #T` olmalıdır;
- `INTO #T` bölümü çıkarıldığında kalan `SELECT`, mevcut salt-okunur kapının **bütün** yasaklarından tekrar geçmelidir;
- staging tamamlandıktan sonra **tam olarak bir** sonuç `SELECT`/CTE bulunmalıdır;
- sonuçtan sonra yalnızca aynı batch'in oluşturduğu yerel `#temp` tabloların birer kez temizlenmesi kabul edilir;
- `GO`, ek sonuç `SELECT`'leri, belirsiz ifadeler veya yaratılmayan bir temp tabloyu temizleme girişimi batch'i reddeder.

Bu, kalıcı `SELECT ... INTO dbo.Tablo`, DDL veya başka veri yazma biçimlerine izin vermez.

## 4. Faz 3b metadata üreticisi temp tabloları çalıştırmaz

SQL Server'ın `sys.dm_exec_describe_first_result_set` tanımlayıcısı aynı batch içinde oluşturulan `#temp` tabloları her durumda çözemediği için Faz 3b özel bir metadata yolu kullanır.

`pk_sql_analyze_local_temp_batch()` batch'i güvenli olarak doğruladıktan sonra, **yalnızca metadata tanımlama amacıyla** staging zinciri eşdeğer CTE'lere dönüştürülür. Örneğin:

```sql
SELECT ... INTO #BaseData ...;
SELECT ... INTO #AssignmentCounts FROM #BaseData ...;
SELECT ... FROM #BaseData JOIN #AssignmentCounts ...;
```

metadata tanımlayıcısına kavramsal olarak şu biçimde gönderilir:

```sql
WITH __pk_meta_local_temp_001 AS (
  SELECT ...
),
__pk_meta_local_temp_002 AS (
  SELECT ... FROM __pk_meta_local_temp_001 ...
)
SELECT ...
FROM __pk_meta_local_temp_001
JOIN __pk_meta_local_temp_002 ...;
```

Önemli sınırlar:

- Faz 3b `#temp` tablo oluşturmaz;
- metadata üreticisine `DBI::dbExecute()`, `dbWriteTable()`, `dbCreateTable()` veya benzeri yazma API'leri eklenmemiştir;
- `tools/pk/helpers_meta_generator_db.R` bağlantı/pool mimarisi değiştirilmemiştir;
- `sample` yolu ve gerçek uygulama çalıştırması **orijinal SQL'i değiştirmeden** kullanır;
- CTE dönüşümü yalnızca `describe` çağrısına verilen metadata metnidir;
- üretilen CTE adı orijinal SQL ile çakışırsa dönüşüm fail-closed hata verir.

Dolayısıyla metadata üreticisi için mevcut "yalnızca okur" ratchet'i aynen korunur.

## 5. Runtime davranışı

Gerçek Proje ve Kaynak Analizi çalıştırmasında SQL yeniden yazılmaz. Kapı batch'i güvenli olarak sınıflandırırsa uygulama sorgu kütüphanesindeki **orijinal SQL'i** mevcut Unicode/ODBC yürütme yoluyla çalıştırır.

Bu ayrım bilinçlidir:

- **güvenlik sınıflandırması:** orijinal SQL üzerinde;
- **Faz 3b statik metadata tanımı:** gerektiğinde eşdeğer CTE üzerinde;
- **runtime yürütme:** orijinal SQL üzerinde;
- **sample:** orijinal SQL üzerinde ve ayrıca `meta_sample_safe = TRUE` açık kürasyon kapısıyla.

## 6. Değiştirilmeyen ratchet'ler ve mimari sınırlar

Bu çalışma sırasında aşağıdaki sınırlar özellikle korunmuştur:

- `PK_SQL_FORBIDDEN_KEYWORDS` genel olarak gevşetilmedi;
- Faz 3b araçlarında veri değiştiren DBI çağrıları yasak kalmaya devam ediyor;
- maintainability ratchet eşikleri değiştirilmedi;
- metadata generator DB bağlantı/pool davranışı değiştirilmedi;
- `R/library_query_meta.R`, `R/library_query_meta_auto.R` veya alias dosyasına generator yazma izni verilmedi;
- üretim SQL dosyaları bu uyumluluk için değiştirilmedi;
- RLS ve post-fetch gerçek-kolon doğrulaması değiştirilmedi.

Bu sınırlar, sonraki bir düzeltmede "kolaylık" gerekçesiyle kaldırılmamalıdır.

## 7. İlgili nihai değişiklikler

Bu uyumluluğun son hali iki kod adımında geldi:

- `4958e4699c7bd9291e6fb176ed67b36f30fd206f` — **Allow safe SET NOCOUNT ON read-only batches**
- `a87a51559db6835af582decd85eaf3f54dd93cd0` — **Allow safe local-temp analytical batches**

Yerel-temp değişikliği yalnızca şu alanları etkiler:

- `R/helpers_pk_sql_readonly.R` — güvenli batch analizi ve sınıflandırma;
- `tools/pk/helpers_meta_generator_fetch.R` — metadata-only CTE dönüşümü;
- `tests/testthat/test-pk-sql-local-temp-batch-contract.R` — odaklı regresyon sözleşmesi.

`SET NOCOUNT ON` değişikliği de aynı read-only sınıflandırıcı üzerinde dar bir istisnadır.

## 8. VM doğrulama sonucu

20 Ağustos 2026'da operatör Windows VM'de güncel `pk/rebuild` koduyla Faz 3b `describe` koşusunu tekrar çalıştırdı ve daha önce `multiple_statements` nedeniyle atlanan hedef sorguların düzeldiğini doğruladı.

Sağlık raporunda bundan sonra şu ayrım beklenir:

- tam `SET NOCOUNT ON;` + tek salt-okunur sorgu → kapıdan geçer;
- kuralları eksiksiz sağlayan yerel `#temp` analitik batch → kapıdan geçer ve `describe` için metadata-only CTE yolu kullanılır;
- diğer çok ifadeli/yan etkili/belirsiz batch'ler → `sql_not_readonly` ile atlanır.

Sorgu kütüphanesi sayısı zamanla değişebileceği için bu belge sabit bir toplam/success sayısını güvenlik sözleşmesi olarak kullanmaz. Kanonik kanıt her koşunun kendi `artifacts/pk-meta/<timestamp>/health.txt` ve `health.json` dosyalarıdır.

## 9. Operatör için kısa kontrol listesi

Windows VM'de bu uyumluluğu taşımak için en az şu iki dosyanın güncel olması gerekir:

```text
R/helpers_pk_sql_readonly.R
tools/pk/helpers_meta_generator_fetch.R
```

Temiz `describe` koşusu:

```r
Sys.setenv(
  MERGEN_PK_META_MODE = "describe",
  MERGEN_PK_META_RESUME = "false"
)
source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
```

Sonra:

1. `health.txt` içinde hedef sorguların `multiple_statements` nedeniyle atlanmadığını doğrulayın.
2. Yeni `BASARISIZ`/`GERI CEKILDI` sorgu oluşmadığını kontrol edin.
3. `R/library_query_meta_local.R` dosyasının gitignore'lu kaldığını doğrulayın.
4. Metadata'yı tüketmek için R sürecini yeniden başlatın.

Ayrıntılı operasyon adımları [`pk-phase3b-operator-runbook.md`](pk-phase3b-operator-runbook.md) içindedir.
