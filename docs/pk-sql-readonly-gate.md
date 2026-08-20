# Proje ve Kaynak Analizi — SQL Salt-Okunur Kapısı ve Faz 3b Uyumluluğu

**Durum:** 20 Ağustos 2026 itibarıyla Windows VM'de doğrulandı.

Bu belge, `R/helpers_pk_sql_readonly.R` ile Faz 3b metadata üreticisinin birlikte uyguladığı SQL güvenlik/uyumluluk sözleşmesinin **nihai durumunu** açıklar. Operatör adımları için [`pk-phase3b-operator-runbook.md`](pk-phase3b-operator-runbook.md), genel tasarım için [`proje-kaynak-analizi-master-plan.md`](proje-kaynak-analizi-master-plan.md) §5.1 okunmalıdır.

Bu değişikliklerin amacı salt-okunur kapısını gevşetmek değil, üretimde zaten çalışan güvenli SQL Server biçimlerini kapalı-başarısız kurallar altında açıkça tanımaktır:

1. `SET NOCOUNT ON;` + tek salt-okunur `SELECT`/CTE.
2. Yalnızca yerel `#temp` tablolarla staging yapan ve sonunda tek salt-okunur sonuç `SELECT`/CTE'si döndüren analitik batch.
3. Aynı yerel-temp batch içinde, yalnızca daha önce oluşturulmuş yerel `#temp` tablolar üzerinde performans amacıyla `CREATE [UNIQUE] [CLUSTERED|NONCLUSTERED] INDEX` kullanan SSMS tipi analitik sorgular.

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

Yerel-temp istisnası bu genel yasakları kaldırmaz. `SELECT ... INTO` ve `CREATE INDEX` yalnızca aşağıdaki dar ve yapısal olarak kanıtlanan yerel `#temp` batch sözleşmesinin içinde kabul edilir.

## 2. Güvenli `SET NOCOUNT ON` öneki

SQL Server sorgu kütüphanesinde yaygın olan şu biçim kabul edilir:

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

Çok ifadeli bir batch yalnızca `pk_sql_analyze_local_temp_batch()` yapıyı eksiksiz kanıtlayabilirse kabul edilir. Güncel sözleşme hem klasik ön-temizlikli biçimi hem de SSMS'te yaygın olan doğrudan staging biçimini kapsar:

```sql
-- Ön-temizlik isteğe bağlıdır; varsa aynı #temp adını hedeflemelidir.
IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;
SELECT ... INTO #T ...;

-- İsteğe bağlı; hedef daha önce bu batch içinde oluşturulmuş yerel #temp olmalıdır.
CREATE CLUSTERED INDEX IX_T ON #T(...);
CREATE NONCLUSTERED INDEX IX_T_2 ON #T(...) INCLUDE (...);

SELECT ... INTO #T2
FROM #T ...;

CREATE NONCLUSTERED INDEX IX_T2 ON #T2(...);

WITH Sonuc AS (...)
SELECT ...
FROM Sonuc;

DROP TABLE IF EXISTS #T, #T2;
```

Kurallar:

- yalnızca **yerel** `#temp` adları kabul edilir; `##global` temp tablolar kabul edilmez;
- `OBJECT_ID('tempdb..#T') ... DROP TABLE #T` ön-temizliği **isteğe bağlıdır**; kullanılırsa hemen arkasındaki staging ifadesi aynı `#T` adını hedeflemelidir;
- staging ifadesi `SELECT ... INTO #T` olmalıdır;
- `INTO #T` bölümü çıkarıldığında kalan `SELECT`, mevcut salt-okunur kapının **bütün** yasaklarından tekrar geçmelidir;
- `CREATE INDEX` yalnızca aynı batch içinde daha önce kanıtlanmış biçimde oluşturulan yerel `#temp` tablolar üzerinde kabul edilir; kalıcı tablo veya `##global` temp hedefi reddedilir;
- staging tamamlandıktan sonra **tam olarak bir** sonuç `SELECT` veya `WITH ... SELECT` bulunmalıdır;
- sonuçtan sonra yalnızca aynı batch'in oluşturduğu yerel `#temp` tablolar temizlenebilir;
- hem `DROP TABLE #T` hem de `DROP TABLE IF EXISTS #T, #T2, ...` biçimi desteklenir; her hedef bir kez ve yalnızca daha önce oluşturulmuş yerel `#temp` olmalıdır;
- `GO`, ek sonuç `SELECT`'leri, kalıcı DDL/DML, `EXEC`, sequence mutasyonu, belirsiz ifadeler veya yaratılmayan temp tabloyu temizleme girişimi batch'i reddeder.

Bu, kalıcı `SELECT ... INTO dbo.Tablo`, kalıcı `CREATE INDEX`, genel DDL veya başka veri yazma biçimlerine izin vermez.

## 4. Faz 3b metadata üreticisi temp tabloları veya indeksleri çalıştırmaz

SQL Server'ın `sys.dm_exec_describe_first_result_set` tanımlayıcısı aynı batch içinde oluşturulan `#temp` tabloları her durumda çözemediği için Faz 3b özel bir metadata yolu kullanır.

`pk_sql_analyze_local_temp_batch()` batch'i güvenli olarak doğruladıktan sonra, **yalnızca metadata tanımlama amacıyla** staging zinciri eşdeğer CTE'lere dönüştürülür. Fiziksel `CREATE INDEX` ifadeleri sonuç şemasını değiştirmediği için bu metadata-only dönüşümünde çalıştırılmaz. Örneğin:

```sql
SELECT ... INTO #BaseData ...;
CREATE CLUSTERED INDEX IX_Base ON #BaseData(...);
SELECT ... INTO #AssignmentCounts FROM #BaseData ...;
WITH Sonuc AS (...)
SELECT ... FROM Sonuc;
```

metadata tanımlayıcısına kavramsal olarak şu biçimde gönderilir:

```sql
WITH __pk_meta_local_temp_001 AS (
  SELECT ...
),
__pk_meta_local_temp_002 AS (
  SELECT ... FROM __pk_meta_local_temp_001 ...
),
Sonuc AS (
  ...
)
SELECT ...
FROM Sonuc;
```

Önemli sınırlar:

- Faz 3b `#temp` tablo oluşturmaz;
- Faz 3b `CREATE INDEX` çalıştırmaz;
- metadata üreticisine `DBI::dbExecute()`, `dbWriteTable()`, `dbCreateTable()` veya benzeri yazma API'leri eklenmemiştir;
- `tools/pk/helpers_meta_generator_db.R` bağlantı/pool mimarisi değiştirilmemiştir;
- `sample` yolu ve gerçek uygulama çalıştırması **orijinal SQL'i değiştirmeden** kullanır;
- CTE dönüşümü yalnızca `describe` çağrısına verilen metadata metnidir;
- final sonuç zaten `WITH ... SELECT` ise üretilen staging CTE'leri aynı `WITH` zincirine güvenli biçimde eklenir;
- üretilen CTE adı orijinal SQL ile çakışırsa dönüşüm fail-closed hata verir.

Dolayısıyla metadata üreticisi için mevcut "yalnızca okur" ratchet'i aynen korunur.

## 5. Runtime davranışı

Gerçek Proje ve Kaynak Analizi çalıştırmasında SQL yeniden yazılmaz. Kapı batch'i güvenli olarak sınıflandırırsa uygulama sorgu kütüphanesindeki **orijinal SQL'i** mevcut Unicode/ODBC yürütme yoluyla çalıştırır.

Bu ayrım bilinçlidir:

- **güvenlik sınıflandırması:** orijinal SQL üzerinde;
- **Faz 3b statik metadata tanımı:** gerektiğinde eşdeğer CTE üzerinde;
- **runtime yürütme:** orijinal SQL üzerinde;
- **sample:** orijinal SQL üzerinde ve ayrıca `meta_sample_safe = TRUE` açık kürasyon kapısıyla.

Dolayısıyla SSMS'te çalışan, yerel temp tablo ve indeks kullanan güvenli analitik batch için sorgu dosyasını CTE'ye çevirmek veya SQL metnini değiştirmek gerekmez. R/ODBC yolu aynı batch'i aynı bağlantı kapsamında çalıştırabilir; uyumluluk katmanı yalnızca uygulama güvenlik kapısının bu dar güvenli biçimi tanımasını sağlar.

## 6. Değiştirilmeyen ratchet'ler ve mimari sınırlar

Bu çalışma sırasında aşağıdaki sınırlar özellikle korunmuştur:

- `PK_SQL_FORBIDDEN_KEYWORDS` genel olarak gevşetilmedi;
- `CREATE`, `DROP` ve `INTO` genel izinli anahtar kelimelere dönüştürülmedi;
- Faz 3b araçlarında veri değiştiren DBI çağrıları yasak kalmaya devam ediyor;
- maintainability ratchet eşikleri değiştirilmedi;
- metadata generator DB bağlantı/pool davranışı değiştirilmedi;
- `R/library_query_meta.R`, `R/library_query_meta_auto.R` veya alias dosyasına generator yazma izni verilmedi;
- üretim SQL dosyaları bu uyumluluk için değiştirilmedi;
- RLS ve post-fetch gerçek-kolon doğrulaması değiştirilmedi.

Bu sınırlar, sonraki bir düzeltmede "kolaylık" gerekçesiyle kaldırılmamalıdır.

## 7. İlgili nihai değişiklikler

Bu uyumluluk üç dar kod adımında geldi:

- `4958e4699c7bd9291e6fb176ed67b36f30fd206f` — **Allow safe SET NOCOUNT ON read-only batches**
- `a87a51559db6835af582decd85eaf3f54dd93cd0` — **Allow safe local-temp analytical batches**
- `24b6a3e1e26bd41490191747624f57f0d55553b9` — **Support indexed local-temp SQL batches**

Son adım şu uyumluluğu ekledi:

- ön-temizlik olmadan başlayan güvenli `SELECT ... INTO #temp` staging;
- yalnızca daha önce oluşturulmuş yerel temp tablolar üzerinde `CREATE [NON]CLUSTERED INDEX`;
- final `WITH ... SELECT` sonuç zinciri;
- `DROP TABLE IF EXISTS #A, #B, ...` toplu temizlik;
- metadata-only dönüşümde indekslerin atlanması ve final CTE zincirinin üretilen staging CTE'leriyle birleştirilmesi.

Kod kapsamı yine yalnızca şu alanlardadır:

- `R/helpers_pk_sql_readonly.R` — güvenli batch analizi ve sınıflandırma;
- `tools/pk/helpers_meta_generator_fetch.R` — metadata-only CTE dönüşümü;
- `tests/testthat/test-pk-sql-local-temp-batch-contract.R` — odaklı regresyon sözleşmesi.

## 8. VM doğrulama sonucu

20 Ağustos 2026'da operatör Windows VM'de güncel `pk/rebuild` koduyla Faz 3b `describe` koşusunu tekrar çalıştırdı. İlk yerel-temp uyumluluğuna ek olarak, SSMS'te çalışan ancak `SELECT ... INTO #temp` + yerel `CREATE INDEX` + final CTE + `DROP TABLE IF EXISTS` kullandığı için daha önce `multiple_statements` olarak reddedilen gerçek sorgunun da düzeldiği doğrulandı.

Sağlık raporunda bundan sonra şu ayrım beklenir:

- tam `SET NOCOUNT ON;` + tek salt-okunur sorgu → kapıdan geçer;
- kuralları eksiksiz sağlayan yerel `#temp` analitik batch → kapıdan geçer ve `describe` için metadata-only CTE yolu kullanılır;
- aynı batch içindeki kanıtlanmış yerel-temp indeksleri → izin verilir ancak metadata `describe` sırasında çalıştırılmaz;
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
2. `SELECT ... INTO #temp` + yerel temp indeksleri + final CTE + `DROP TABLE IF EXISTS` kullanan sorguların normal doğrulama yoluna girdiğini kontrol edin.
3. Yeni `BASARISIZ`/`GERI CEKILDI` sorgu oluşmadığını kontrol edin.
4. Kalıcı DDL/DML, `##global`, `EXEC`, `GO` veya belirsiz batch'lerin hâlâ reddedildiğini doğrulayın.
5. `R/library_query_meta_local.R` dosyasının gitignore'lu kaldığını doğrulayın.
6. Metadata'yı tüketmek için R sürecini yeniden başlatın.

Ayrıntılı operasyon adımları [`pk-phase3b-operator-runbook.md`](pk-phase3b-operator-runbook.md) içindedir.
