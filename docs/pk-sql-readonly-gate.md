# Proje ve Kaynak Analizi — SQL Salt-Okunur Kapısı ve Faz 3b Uyumluluğu

**Durum:** 20 Ağustos 2026 itibarıyla Windows VM'de doğrulandı.

Bu belge, `R/helpers_pk_sql_readonly.R` ile Faz 3b metadata üreticisinin birlikte uyguladığı SQL güvenlik/uyumluluk sözleşmesinin **nihai durumunu** açıklar. Operatör adımları için [`pk-phase3b-operator-runbook.md`](pk-phase3b-operator-runbook.md), genel tasarım için [`proje-kaynak-analizi-master-plan.md`](proje-kaynak-analizi-master-plan.md) §5.1 okunmalıdır.

Bu değişikliklerin amacı salt-okunur kapısını gevşetmek değil, üretimde zaten çalışan güvenli SQL Server biçimlerini kapalı-başarısız kurallar altında açıkça tanımaktır:

1. `SET NOCOUNT ON;` + tek salt-okunur `SELECT`/CTE.
2. Bir veya daha fazla güvenli scalar `DECLARE @degisken ...` öneki + tek salt-okunur sonuç `SELECT`/CTE.
3. Yalnızca yerel `#temp` tablolarla staging yapan ve sonunda tek salt-okunur sonuç `SELECT`/CTE'si döndüren analitik batch.
4. Aynı yerel-temp batch içinde, yalnızca daha önce oluşturulmuş yerel `#temp` tablolar üzerinde performans amacıyla `CREATE [UNIQUE] [CLUSTERED|NONCLUSTERED] INDEX` kullanan SSMS tipi analitik sorgular.

## 1. Korunan temel kural

Kapı hâlâ **fail-closed** çalışır. Varsayılan olarak yalnızca tek bir salt-okunur `SELECT`, son gövdesi `SELECT` olan CTE veya eşdeğer parantezli `SELECT` kabul edilir. Ayrıştırma belirsizse sorgu çalıştırılmaz.

Aşağıdaki aileler reddedilmeye devam eder:

- `MERGE`, `INSERT`, `UPDATE`, `DELETE`, `UPSERT`;
- kalıcı `CREATE`, `DROP`, `ALTER`, `TRUNCATE`, `RENAME`;
- `GRANT`, `DENY`, `REVOKE`;
- `EXEC`/`EXECUTE`, `sp_`, `xp_`;
- genel `SELECT ... INTO`;
- genel `SET`, genel `DECLARE`, `USE`, `GO`, transaction ifadeleri;
- `OPENROWSET`, `OPENQUERY`, `OPENDATASOURCE`, `BULK` ve benzeri dış erişim biçimleri;
- `NEXT VALUE FOR` gibi `SELECT` görünümünde olsa da sunucu durumunu değiştiren ifadeler.

`SET NOCOUNT ON` ve scalar `DECLARE` için aşağıda tanımlanan dar istisnalar bu genel yasağı kaldırmaz. Literal, yorum ve tırnaklı/köşeli tanımlayıcı içindeki sözcükler güvenlik anahtar kelimesi sayılmaz; sınıflandırıcı önce bu bölgeleri maskeler.

Yerel-temp istisnası da genel yasakları kaldırmaz. `SELECT ... INTO` ve `CREATE INDEX` yalnızca aşağıdaki dar ve yapısal olarak kanıtlanan yerel `#temp` batch sözleşmesinin içinde kabul edilir.

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

İstisna **yalnızca tam `SET NOCOUNT ON` ifadesidir**. Başka bir `SET` biçimi veya arkasında salt-okunur olmayan SQL varsa sorgu normal kapalı-başarısız kurala döner ve reddedilir.

Bu uyumluluk, `SET` anahtar kelimesini genel olarak güvenli saymaz ve yasaklı anahtar kelime listesini azaltmaz. `SET NOCOUNT ON`, aşağıdaki güvenli scalar `DECLARE` öneklerinin önünde de bulunabilir.

### 2.1 Güvenli scalar `DECLARE` öneki

SSMS'te yaygın olan, yalnızca sorgu içinde kullanılacak scalar değişkenleri hazırlayan şu biçim kabul edilir:

```sql
DECLARE @CutoffDate DATE = DATEADD(day, -90, GETDATE());
DECLARE @Today DATE = CAST(GETDATE() AS date);

SELECT ...
FROM ...
WHERE SomeDate < @CutoffDate;
```

Final ifade CTE de olabilir:

```sql
DECLARE @Today DATE = CAST(GETDATE() AS date);
WITH x AS (...)
SELECT ...
FROM x;
```

Kurallar dar tutulur:

- sonuçtan önce bir veya daha fazla `DECLARE @degisken ...` ifadesi bulunabilir;
- `DECLARE ... TABLE` ve `DECLARE ... CURSOR` kabul edilmez;
- `NEXT VALUE FOR`, DML/DDL, `EXEC`, ek sonuç `SELECT`'i veya başka yasaklı ailelerden biri herhangi bir bildirimde görünürse batch reddedilir;
- bildirimlerin ardından **tam olarak bir** salt-okunur `SELECT` veya `WITH ... SELECT` bulunmalıdır;
- isteğe bağlı `SET NOCOUNT ON;` yalnızca batch'in en başında ve mevcut tam biçimiyle kabul edilir;
- bu istisna genel `DECLARE` veya genel çok-ifade izni değildir.

Sınıflandırıcı yeni bir SQL yorumlayıcısı yazmaz; scalar bildirimleri mevcut fail-closed SELECT denetimlerinin yasaklarıyla tekrar sınar. Runtime ve `describe` yolları sorgu metnini değiştirmez. Böylece SSMS'te çalışan bu tür bir sorguyu sırf metadata üreticisi için yeniden yazmak gerekmez.

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
- scalar `DECLARE` batch'leri normal `describe` yolunda orijinal SQL metniyle SQL Server tanımlayıcısına gider;
- `sample` yolu ve gerçek uygulama çalıştırması **orijinal SQL'i değiştirmeden** kullanır;
- CTE dönüşümü yalnızca yerel-temp batch'lerinde `describe` çağrısına verilen metadata metnidir;
- final sonuç zaten `WITH ... SELECT` ise üretilen staging CTE'leri aynı `WITH` zincirine güvenli biçimde eklenir;
- üretilen CTE adı orijinal SQL ile çakışırsa dönüşüm fail-closed hata verir.

Dolayısıyla metadata üreticisi için mevcut "yalnızca okur" ratchet'i aynen korunur.

## 5. Runtime davranışı

Gerçek Proje ve Kaynak Analizi çalıştırmasında SQL yeniden yazılmaz. Kapı batch'i güvenli olarak sınıflandırırsa uygulama sorgu kütüphanesindeki **orijinal SQL'i** mevcut Unicode/ODBC yürütme yoluyla çalıştırır.

Bu ayrım bilinçlidir:

- **güvenlik sınıflandırması:** orijinal SQL üzerinde;
- **Faz 3b statik metadata tanımı:** yerel-temp gerekiyorsa eşdeğer CTE üzerinde, scalar `DECLARE` batch'lerinde orijinal SQL üzerinde;
- **runtime yürütme:** orijinal SQL üzerinde;
- **sample:** orijinal SQL üzerinde ve ayrıca `meta_sample_safe = TRUE` açık kürasyon kapısıyla.

Dolayısıyla SSMS'te çalışan güvenli scalar `DECLARE` + final `SELECT`/CTE veya yerel temp tablo ve indeks kullanan güvenli analitik batch için sorgu dosyasını değiştirmek gerekmez. R/ODBC yolu aynı batch'i aynı bağlantı kapsamında çalıştırabilir; uyumluluk katmanı yalnızca uygulama güvenlik kapısının bu dar güvenli biçimleri tanımasını sağlar.

## 6. Değiştirilmeyen ratchet'ler ve mimari sınırlar

Bu çalışma sırasında aşağıdaki sınırlar özellikle korunmuştur:

- `PK_SQL_FORBIDDEN_KEYWORDS` genel olarak gevşetilmedi;
- `DECLARE`, `CREATE`, `DROP` ve `INTO` genel izinli anahtar kelimelere dönüştürülmedi;
- scalar `DECLARE` uyumluluğu mevcut `pk_sql_classify_readonly()` içinde dar bir çok-ifade dalı olarak eklendi; yeni bir genel izin yolu açılmadı;
- `R/helpers_pk_sql_readonly.R` için yeni adlandırılmış fonksiyon eklenmedi; fonksiyon sayısı 22'de kaldı ve dosya 800 satır eşiğinin altında kaldı;
- maintainability ratchet eşikleri değiştirilmedi;
- Faz 3b araçlarında veri değiştiren DBI çağrıları yasak kalmaya devam ediyor;
- metadata generator DB bağlantı/pool davranışı değiştirilmedi;
- `R/library_query_meta.R`, `R/library_query_meta_auto.R` veya alias dosyasına generator yazma izni verilmedi;
- üretim SQL dosyaları bu uyumluluk için değiştirilmedi;
- RLS ve post-fetch gerçek-kolon doğrulaması değiştirilmedi.

Bu sınırlar, sonraki bir düzeltmede "kolaylık" gerekçesiyle kaldırılmamalıdır.

## 7. İlgili nihai değişiklikler

Bu uyumluluk dört dar kod adımında geldi:

- `4958e4699c7bd9291e6fb176ed67b36f30fd206f` — **Allow safe SET NOCOUNT ON read-only batches**
- `a87a51559db6835af582decd85eaf3f54dd93cd0` — **Allow safe local-temp analytical batches**
- `24b6a3e1e26bd41490191747624f57f0d55553b9` — **Support indexed local-temp SQL batches**
- `5e05491e3babe51c197b70b9a8971e82a480e679` — **Allow safe scalar DECLARE query batches**

Son adım, sorguyu değiştirmeden şu uyumluluğu ekledi:

- bir veya daha fazla scalar `DECLARE @degisken ...` öneki;
- arkasında tam olarak bir salt-okunur `SELECT` veya CTE sonucu;
- isteğe bağlı tam `SET NOCOUNT ON;` öneki;
- `TABLE`, `CURSOR`, `NEXT VALUE FOR`, DML/DDL, `EXEC` ve ek sonuç `SELECT`'leri için fail-closed ret;
- mevcut read-only sınıflandırıcının güvenlik yasaklarını tekrar kullanma.

Kod kapsamı şu alanlardadır:

- `R/helpers_pk_sql_readonly.R` — güvenli batch analizi ve sınıflandırma;
- `tools/pk/helpers_meta_generator_fetch.R` — yalnızca yerel-temp için metadata-only CTE dönüşümü;
- `tests/testthat/test-pk-sql-local-temp-batch-contract.R` — yerel-temp regresyon sözleşmesi;
- `tests/testthat/test-pk-sql-declare-batch-contract.R` — scalar `DECLARE` regresyon sözleşmesi.

## 8. VM doğrulama sonucu

20 Ağustos 2026'da operatör Windows VM'de güncel `pk/rebuild` koduyla Faz 3b `describe` koşusunu yeniden çalıştırdı. Daha önce SSMS'te sorunsuz çalışan ancak iki scalar `DECLARE` ifadesi nedeniyle `multiple_statements` olarak `ATLANDI` görünen gerçek sorgu, SQL metni değiştirilmeden normal doğrulama yoluna girdi.

Bu doğrulamadan sonra sağlık raporu özeti şuydu:

- toplam sorgu: **170**;
- bu koşuda şema alınan: **170**;
- aday katmana dahil: **170**;
- `GERI CEKILEN` bloklayıcı: **0**;
- şema alınamayan: **0**;
- başarısız: **0**;
- güvenlik/gate nedeniyle atlanan: **0**;
- Tier-0 kalan: **0**;
- üretilen katmana yazılan: **170**.

Raporda **170 sorgu için anlamsal kürasyon gerektiği** ayrıca görünür. Bu bir schema/gate başarısızlığı değildir; Faz 3b yapısal metadata üretir, `capability`, `grain`, `unit`, `additive` gibi anlamsal Tier-3 alanlarını kendiliğinden uydurmaz.

Sağlık raporunda bundan sonra şu ayrım beklenir:

- tam `SET NOCOUNT ON;` + tek salt-okunur sorgu → kapıdan geçer;
- güvenli scalar `DECLARE` önekleri + tek salt-okunur sonuç sorgusu → kapıdan geçer ve normal `describe` yolunu kullanır;
- kuralları eksiksiz sağlayan yerel `#temp` analitik batch → kapıdan geçer ve `describe` için metadata-only CTE yolu kullanılır;
- aynı batch içindeki kanıtlanmış yerel-temp indeksleri → izin verilir ancak metadata `describe` sırasında çalıştırılmaz;
- diğer çok ifadeli/yan etkili/belirsiz batch'ler → `sql_not_readonly` ile atlanır.

Bu **170/170** değeri yalnızca 20 Ağustos 2026 tarihli doğrulama koşusunun kanıtıdır; sorgu kütüphanesi değiştikçe sayı değişebilir ve bir ratchet değildir. Kanonik kanıt her koşunun kendi `artifacts/pk-meta/<timestamp>/health.txt` ve `health.json` dosyalarıdır.

## 9. Operatör için kısa kontrol listesi

Windows VM'de bu uyumluluğu taşımak için `R/helpers_pk_sql_readonly.R` güncel olmalıdır. Yerel-temp uyumluluğu da kullanılacaksa aşağıdaki metadata dönüşüm yardımcısı da güncel kalmalıdır:

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

1. `health.txt` içinde güvenli scalar `DECLARE` + final `SELECT`/CTE sorgularının `multiple_statements` nedeniyle atlanmadığını doğrulayın.
2. Tam `SET NOCOUNT ON` sorgularının normal doğrulama yoluna girdiğini doğrulayın.
3. `SELECT ... INTO #temp` + yerel temp indeksleri + final CTE + `DROP TABLE IF EXISTS` kullanan sorguların normal doğrulama yoluna girdiğini kontrol edin.
4. Yeni `BASARISIZ`/`GERI CEKILDI` sorgu oluşmadığını kontrol edin.
5. `TABLE`/`CURSOR` declaration, sequence mutasyonu, kalıcı DDL/DML, `##global`, `EXEC`, `GO` veya belirsiz batch'lerin hâlâ reddedildiğini doğrulayın.
6. `R/library_query_meta_local.R` dosyasının gitignore'lu kaldığını doğrulayın.
7. Metadata'yı tüketmek için R sürecini yeniden başlatın.

Ayrıntılı operasyon adımları [`pk-phase3b-operator-runbook.md`](pk-phase3b-operator-runbook.md) içindedir.