# Faz 3b — Sorgu metadata üreticisi: operatör kılavuzu

Bu belge **Windows VM'de elle yürütülen** Faz 3b adımını anlatır. Tasarım
gerekçesi ve sözleşme için ana kaynak
[`docs/proje-kaynak-analizi-master-plan.md`](proje-kaynak-analizi-master-plan.md)
§5.1'dir. SQL salt-okunur kapısının güncel teknik sözleşmesi için ayrıca
[`pk-sql-readonly-gate.md`](pk-sql-readonly-gate.md) okunmalıdır.

Amaç iki tanedir:

1. Gerçek üretim sorgu kütüphanesi için **yapısal metadata** üretmek
   (`R/library_query_meta_local.R`).
2. `MERGEN_PK_ENGINE=v2` anlamsal/filtreli sorulara güvenle cevap verebilsin diye
   **operatör müdahalesi gereken sorguları** listeleyen bir **sağlık raporu**
   üretmek.

Üretici **yalnızca okur**. Üretim verisini değiştirmez, SQL'i onarmaz, RLS
beyanını kaldırmaz, anlamsal metadata uydurmaz. 20 Ağustos 2026 itibarıyla
Windows VM'de `SET NOCOUNT ON`, güvenli scalar `DECLARE` önekleri, doğrulanmış
yerel `#temp` staging ve aynı batch içindeki güvenli yerel-temp indeksleri
kullanan sorgular için uyumluluk yolu doğrulanmıştır.

---

## 0. Önkoşullar

| Koşul | Neden |
|---|---|
| Windows VM, RStudio, **depo kökü** çalışma dizini | Üretici `query_library`'yi R içinde yürür; SSMS/PowerShell ile çalışmaz |
| `.Renviron` içinde geçerli `DB_DSN` (ve kullanılan `DB_DSN_2`/`DB_DSN_3`) | Şema bilgisi gerçek veritabanından alınır |
| `MERGEN_PK_ASYNC=false` | Faz 6 bu aşamada **açılmaz** |
| Uygulama şu an açılabiliyor olmalı | Üretici aynı bootstrap'i kullanır |

Mümkünse **salt-okunur** bir DB principal'i kullanın. Üretici kendi tarafında
salt-okunur kapısı uygular, ancak veritabanı seviyesinde de kısıtlamak en
güvenli olanıdır.

---

## 1. Betiğin geldiğini doğrulayın

```r
file.exists("tools/pk/generate_query_meta.R")
```

`TRUE` dönmelidir. `FALSE` ise `pk/rebuild` dalını çekmemişsiniz demektir.

20 Ağustos 2026 SQL uyumluluk düzeltmelerini Windows VM'e elle taşıyorsanız
scalar `DECLARE` desteği için `R/helpers_pk_sql_readonly.R` güncel olmalıdır.
Yerel-temp uyumluluğu da kullanılacaksa aşağıdaki iki dosyanın birlikte güncel
kalması gerekir:

```text
R/helpers_pk_sql_readonly.R
tools/pk/helpers_meta_generator_fetch.R
```

`tools/pk/helpers_meta_generator_db.R` için bu uyumluluk adına ayrı bir bağlantı
veya pool değişikliği gerekmez.

---

## 2. `describe` kipi (ÖNCE BU)

`describe` kipi sorguları veri örneklemek amacıyla **çalıştırmaz**. Normal
sorgularda SQL Server'ın
`sys.dm_exec_describe_first_result_set` tanımlayıcısını kullanır. İlk geçiş her
zaman bu olmalıdır.

Temiz bir doğrulama koşusu için:

```r
Sys.setenv(
  MERGEN_PK_META_MODE = "describe",
  MERGEN_PK_META_RESUME = "false"
)
source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
```

Daha sonra kaldığınız yerden devam etmek istiyorsanız
`MERGEN_PK_META_RESUME=true` kullanılabilir.

Konsol özetindeki toplamları sabit bir sayı olarak belgelemeyin: üretim sorgu
kütüphanesi zamanla değişebilir. Kanonik sonuç her koşunun kendi sağlık
artefaktıdır.

### 2.1 `SET NOCOUNT ON` uyumluluğu

Salt-okunur kapısı şu SQL Server biçimini kabul eder:

```sql
SET NOCOUNT ON;
SELECT ...
```

veya:

```sql
SET NOCOUNT ON;
WITH ...
SELECT ...
```

Bu, genel bir `SET` izni değildir. **Yalnızca tam `SET NOCOUNT ON` öneki**
tüketilir; arkasındaki sorgu mevcut SELECT/CTE ve yan-etki kapılarının
tamamından geçmek zorundadır. `SET NOCOUNT ON` aşağıdaki güvenli scalar
`DECLARE` öneklerinin önünde de bulunabilir; başka `SET` biçimleri reddedilir.

### 2.2 Scalar `DECLARE` + tek sonuç sorgusu uyumluluğu

Bazı SSMS sorguları yalnızca tarih/eşik gibi scalar değerleri başta hesaplayıp
sonraki tek sonuç sorgusunda kullanır. Örneğin:

```sql
DECLARE @CutoffDate DATE = DATEADD(day, -90, GETDATE());
DECLARE @Today DATE = CAST(GETDATE() AS date);

SELECT ...
FROM ...
WHERE SomeDate < @CutoffDate;
```

Bu biçim güncel kapıda kabul edilir. Final ifade CTE de olabilir:

```sql
DECLARE @Today DATE = CAST(GETDATE() AS date);
WITH x AS (...)
SELECT ...
FROM x;
```

Kurallar:

- sonuçtan önce bir veya daha fazla `DECLARE @degisken ...` ifadesi olabilir;
- `DECLARE ... TABLE` ve `DECLARE ... CURSOR` reddedilir;
- `NEXT VALUE FOR`, DML/DDL, `EXEC` veya başka bir yan etkili/yasaklı aile
  bildirimlerden birinde görünürse batch reddedilir;
- bildirimlerden sonra **tam olarak bir** salt-okunur `SELECT` veya
  `WITH ... SELECT` bulunmalıdır;
- ek sonuç `SELECT`'leri genel çok-ifade kapısına geri düşer ve reddedilir;
- isteğe bağlı `SET NOCOUNT ON;` yalnız batch'in en başında kabul edilir.

Bu uyumluluk için üretim SQL'ini değiştirmeyin. `describe` yolu scalar
`DECLARE` batch'ini **orijinal metniyle** SQL Server tanımlayıcısına verir;
gerçek uygulama da aynı orijinal SQL'i Unicode/ODBC yolu üzerinden çalıştırır.
Dolayısıyla SSMS'te çalışan bu sorgu biçimi R tarafından da çalıştırılabilir ve
metadata üretimi için CTE'ye ya da başka bir sorguya çevrilmesi gerekmez.

### 2.3 Yerel `#temp` analitik batch uyumluluğu

Bazı üretim sorguları bir veya daha fazla yerel `#temp` tabloyu staging için
kullanır. Çok ifadeli batch yalnızca yapısı eksiksiz kanıtlanabiliyorsa kabul
edilir. Güncel sözleşme hem klasik ön-temizlikli biçimi hem de SSMS'te yaygın
olan doğrudan staging + indeks biçimini kapsar:

```sql
-- İsteğe bağlı ön-temizlik; varsa staging ile aynı adı hedeflemelidir.
IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;
SELECT ... INTO #T ...;

-- İsteğe bağlı; yalnızca bu batch içinde daha önce oluşturulmuş #temp üzerinde.
CREATE CLUSTERED INDEX IX_T ON #T(...);
CREATE NONCLUSTERED INDEX IX_T_2 ON #T(...) INCLUDE (...);

SELECT ... INTO #T2
FROM #T ...;

WITH Sonuc AS (...)
SELECT ...
FROM Sonuc;

DROP TABLE IF EXISTS #T, #T2;
```

Kuralların özeti:

- yalnız yerel `#temp`; `##global` kabul edilmez,
- `OBJECT_ID('tempdb..#T') ... DROP TABLE #T` ön-temizliği isteğe bağlıdır;
  kullanılırsa hemen sonraki staging ile aynı `#temp` adını hedeflemelidir,
- staging `SELECT`'i `INTO #temp` bölümü çıkarıldıktan sonra mevcut read-only
  kapının bütün yasaklarından tekrar geçer,
- `CREATE [UNIQUE] [CLUSTERED|NONCLUSTERED] INDEX` yalnızca daha önce aynı batch
  içinde oluşturulmuş yerel `#temp` tabloyu hedefleyebilir,
- staging bittikten sonra tam olarak bir sonuç `SELECT` veya `WITH ... SELECT`
  bulunur,
- final temizlik hem `DROP TABLE #T` hem de
  `DROP TABLE IF EXISTS #T, #T2, ...` olabilir; yalnızca aynı batch'in
  oluşturduğu temp tablolar birer kez temizlenebilir,
- `GO`, kalıcı DDL/yazma, kalıcı `CREATE INDEX`, `EXEC`, ek sonuç `SELECT`'i,
  sequence mutasyonu veya belirsiz yapı batch'i reddeder.

SQL Server statik tanımlayıcısı aynı batch içinde oluşturulan `#temp` tabloları
her durumda çözemediği için **yalnızca metadata tanımı sırasında** doğrulanmış
staging zinciri eşdeğer CTE'lere dönüştürülür. Fiziksel temp indeksleri sonuç
şemasını değiştirmediği için `describe` dönüşümünde çalıştırılmaz. Final sonuç
zaten `WITH ... SELECT` ise üretilen staging CTE'leri aynı CTE zincirine güvenli
biçimde eklenir.

Faz 3b bunun için `#temp` tablo oluşturmaz, `CREATE INDEX` çalıştırmaz ve
`DBI::dbExecute()` kullanmaz. Gerçek uygulama ve `sample` yolu **orijinal SQL'i
değiştirmeden** çalıştırır.

Ayrıntılı sözleşme:
[`pk-sql-readonly-gate.md`](pk-sql-readonly-gate.md).

---

## 3. Sağlık raporunu okuyun

```text
artifacts/pk-meta/<zaman-damgasi>/health.txt    <- insan tarafından okunur
artifacts/pk-meta/<zaman-damgasi>/health.json   <- makine tarafından okunur
```

Bu dizin **gitignore'ludur** ve üretim sorgu adlarını/sütun adlarını içerir;
kurumsal ağ dışına **çıkarılmaz**.

### Sorgu durumları

| Durum | Anlamı | Eylem |
|---|---|---|
| `DAHIL` (`ok`) | Şema alındı, doğrulama geçti, üretilen katmana girdi | Yok |
| `GERI CEKILDI` (`withheld`) | Şema alındı **ama** bloklayıcı bulgu var; sorgu üretilen katmana **alınmadı** | **Düzeltin** |
| `BASARISIZ` (`failed`) | Sorgu envanterlenemedi. Şema/sürücü/bağlantı sorunu veya katalog/yapılandırma kusuru olabilir | Bulgu koduna göre düzeltin; her `failed` için `sample` çözüm değildir |
| `ATLANDI` (`skipped`) | SQL salt-okunur kapısından geçemedi; **çalıştırılmadı** | SQL'i ve [`pk-sql-readonly-gate.md`](pk-sql-readonly-gate.md) sözleşmesini inceleyin |

`BASARISIZ` durumu "şema alınamadı"dan **daha geniştir**; bu yüzden sağlık özeti
`failed_queries` ile `schema_failures` sayımlarını ayrı raporlar.

`GERI CEKILDI` bir gerileme **değildir**: o sorgu bugünkü davranışında
(`Tier-0`, `pending_no_schema`) kalır ve istek zamanı RLS zorlaması değişmez.

Geçici bir hata yüzünden `BASARISIZ` olan bir sorgunun **önceki geçerli**
metadata'sı, kaynak parmak izi değişmediği sürece katmanda korunur; rapor bunu
`preserved_previous` olarak işaretler. SQL, hedef veya etkin `date_columns`
beyanı değiştiyse eski girdi `removed_stale_fingerprint` ile kaldırılır.

### İLERLEMEYİ DURDURAN bulgular

| Bulgu kodu | Anlamı | Düzeltme |
|---|---|---|
| `rls_column_missing` **(GÜVENLİK)** | Beyan edilen RLS sütunu sorgu sonucunda yok | SQL veya `rls_columns` beyanını düzeltin; beyanı silerek "çözmeyin" |
| `column_meta_missing_in_schema` | Küre edilmiş metadata var olmayan sütuna atıf yapıyor | `R/library_query_meta.R` içindeki sütun adını düzeltin |
| `role_type_mismatch` | Küre edilmiş rol gerçek sütun tipiyle uyuşmuyor | Rolü veya SQL'i düzeltin |
| `grain_columns_missing_in_schema` vb. | Grain/default/primary-entity atfı gerçek sonuçta yok | Küresyonu düzeltin |
| `sql_not_readonly` | SQL mevcut read-only sözleşmesine uymuyor | SQL'i ve güvenlik sözleşmesini inceleyin |

`sql_not_readonly` artık "her çok ifadeli SQL reddedilir" demek değildir. Tam
`SET NOCOUNT ON;` öneki, güvenli scalar `DECLARE` önekleri + tek sonuç sorgusu ve
yalnızca kuralları eksiksiz sağlayan yerel `#temp` analitik batch dar
istisnalardır. Yerel-temp istisnası daha önce oluşturulmuş temp tablolar
üzerindeki performans indekslerini ve güvenli toplu `DROP TABLE IF EXISTS`
temizliğini de kapsar. Diğer çok ifadeli yapılar kapalı-başarısız reddedilir.

### Eylem gerektiren ama İLERLEMEYİ DURDURMAYAN bulgular

| Bulgu kodu | Anlamı |
|---|---|
| `no_semantic_capability` | Sorguda `capability` beyanı yok; semantik istek SQL'den önce fail-closed durur. Tier-3 insan küresyonudur |
| `unmapped_sql_type` | SQL tipi eşlenemedi; en muhafazakâr yapıya (`character`/`dimension`) düşüldü |
| `unbounded_lob_column` | Kanıtlanmış genişlik üst sınırı olmayan sütun (`nvarchar(max)`, `xml`, ...) |
| `no_primary_entity`, `no_grain`, `rls_not_declared` | Bilgilendirme / Tier-0 geri düşüşü |

---

## 4. Bulguları düzeltin ve `describe`'ı yeniden çalıştırın

Üretici **idempotent**'tir:

- küre edilmiş metadata (`R/library_query_meta.R`) ezilmez — küresyon kazanır,
- `R/library_query_aliases_local.R` üretici tarafından asla yazılmaz,
- yalnızca `R/library_query_meta_local.R` yeniden yazılır,
- geçici DB/sürücü hatasında önceki geçerli metadata korunur,
- bloklayıcı bulgu nedeniyle geri çekilen sorgunun bayat girdisi bırakılmaz.

`R/library_query_meta_local.R` üretimden türetilen otomatik metadata
artefaktıdır ve meşru biçimde çok büyüyebilir. Büyük-dosya/maintainability
ratchet'lerinden hariç tutulması ratchet eşiklerini gevşetme gerekçesi değildir.

---

## 5. `sample` kipi (İKİNCİ GEÇİŞ, isteğe bağlı ve AÇIK İZİNLİ)

`describe` hâlâ bazı desteklenmeyen/dinamik/belirsiz sorgular için şema
döndüremeyebilir. **Güvenli scalar `DECLARE` + tek sonuç sorgusu ile doğrulanmış
yerel `#temp` staging, yerel-temp indeksleri veya final CTE kullanımı artık sırf
bu yapılar nedeniyle `sample` gerektirmez**; scalar `DECLARE` normal tanımlayıcı
yolunu, yerel-temp ise metadata-only CTE yolunu kullanır.

`sample` yalnızca kalan gerçek istisnalar için düşünülmelidir.

**Önemli güvenlik kuralı:** `dbFetch(n=...)` sunucu işini sınırlamaz; yalnızca
istemciye aktarılacak satır sayısını sınırlar. Bu yüzden gerçek üretim
örneklemesi ancak ilgili sorgu insan tarafından incelenip açıkça şu beyanı
taşıyorsa çalışır:

```r
meta_sample_safe = TRUE
```

Bu beyan **toplu eklenmez**. Yoksa üretici sorguyu çalıştırmadan
`sample_not_server_bounded` olarak başarısız raporlar.

Örnek komut:

```r
Sys.setenv(MERGEN_PK_META_MODE = "sample")
source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
```

İzin verilmiş örnekleme `prefix` yöntemidir ve temsili değildir. Bu yüzden
yalnızca tek yönlü kanıtlar güvenlidir:

| Gözlem | Sonuç |
|---|---|
| Mükerrer değer görüldü | Benzersizlik çürütülür |
| Eşikten fazla farklı değer görüldü | `high_cardinality = TRUE` kanıtlanır |
| NULL görüldü | "NULL yok" iddiası çürütülür |
| Mükerrer/NULL görülmedi | Hiçbir şey kanıtlanmaz |
| Eşikten az farklı değer görüldü | Düşük kardinalite kanıtlanmaz |

Önek satır sayısı etkin `row_cap` değerini gerçekten geçtiyse bu aşım tek başına
kanıttır ve `row_cap_exceeded` olarak raporlanabilir. Bunun dışındaki tam
kardinalite iddiaları örnekten çıkarılmaz.

Üretici SQL'i `SELECT TOP n FROM (...)` biçiminde sarmalamaz. `sample` yolu
orijinal SQL'i üretimin kullandığı Unicode parametre yolu üzerinden çalıştırır.

---

## 6. Çıktıyı doğrulayın

```r
file.exists("R/library_query_meta_local.R")
```

`TRUE` olmalıdır. İzlenmediğini doğrulayın:

```r
system("git status --short R/library_query_meta_local.R")
```

Hiçbir şey yazmamalıdır. Bu dosyayı **asla commit etmeyin**.

Sağlık raporunda özellikle şunları kontrol edin:

1. Güvenli scalar `DECLARE` önekleri + tek final `SELECT`/CTE kullanan sorgular
   artık `multiple_statements` nedeniyle `ATLANDI` oluyor mu? Olmamalı.
2. Önceden `multiple_statements` nedeniyle atlanan tam `SET NOCOUNT ON` sorgular
   artık `DAHIL`/normal doğrulama yoluna girmiş mi?
3. Kuralları sağlayan yerel `#temp` analitik sorgular artık sırf çok ifadeli
   oldukları için `ATLANDI` oluyor mu? Olmamalı.
4. `SELECT ... INTO #temp` sonrasında yalnızca aynı batch'in oluşturduğu temp
   tabloları hedefleyen `CREATE CLUSTERED/NONCLUSTERED INDEX` kullanan sorgular
   normal doğrulama yoluna girmiş mi?
5. Final sonucu `WITH ... SELECT` olan sorgular metadata-only CTE dönüşümünde
   başarılı mı?
6. `DROP TABLE IF EXISTS #A, #B, ...` kullanan güvenli toplu temizlik yanlış
   pozitif üretmeden kabul edilmiş mi?
7. Yeni `BASARISIZ`/`GERI CEKILDI` sayısı oluşmuş mu?
8. `TABLE`/`CURSOR` declaration, sequence mutasyonu, kalıcı DDL/DML, `##global`,
   `EXEC`, `GO` veya belirsiz çok ifadeli SQL'ler hâlâ `ATLANDI` mı?

20 Ağustos 2026'daki son Windows VM `describe` doğrulamasında daha önce iki
scalar `DECLARE` nedeniyle `multiple_statements` olarak atlanan SSMS sorgusu SQL
metni değiştirilmeden düzeldi. Aynı temiz koşuda sağlık özeti **170 toplam / 170
şema alınan / 170 üretilen**, **0 güvenlik-gate atlama**, **0 başarısız**, **0
geri çekilen** ve **0 Tier-0 kalan** gösterdi. Rapordaki 170 anlamsal kürasyon
uyarısı beklenen Tier-3 işidir; yapısal metadata başarısızlığı değildir.

Bu sayılar yalnızca o koşunun kanıtıdır, kalıcı bir ratchet değildir. Sorgu
kütüphanesi zamanla değişebileceği için her koşunun kendi
`health.txt`/`health.json` çıktısını kanıt olarak saklayın.

---

## 7. MERGEN Bilge'yi yeniden başlatın

Metadata açılışta yüklenir. Tarayıcı yenilemesi yetmez; R süreci yeniden
başlamalıdır.

Açılış logunda şunu görmelisiniz:

```text
[SQL_LOADER] PK metadata sozlesmesi dogrulandi: <N> sorgu.
```

Açılış düşerse `R/library_query_meta_local.R` dosyasını yeniden adlandırın/silin,
sağlık raporundaki bloklayıcı bulguları inceleyin ve R sürecini yeniden başlatın.
Aynı oturumda bellekte bayat metadata nesnesi kalabileceği için yalnızca dosyayı
silmek her zaman yeterli değildir.

Mükerrer/eksik sorgu kimliği gibi katalog kusurları ayrı teşhis edilir; `sample`
kipi bunları çözmez.

---

## 8. v2'yi SENKRON test edin

```ini
MERGEN_PK_ENGINE=v2
MERGEN_PK_ASYNC=false
```

R sürecini yeniden başlatın, sonra Proje ve Kaynak Analizi'nde:

1. geniş bir soru,
2. filtreli/özel bir soru,
3. belirli bir kişi/proje soran RLS kapsamlı bir soru

deneyin.

`capability_missing` / `unknown_no_semantic_metadata` alıyorsanız bu tek başına
Faz 3b hatası değildir; ilgili sorgunun anlamsal Tier-3 küresyonu henüz yok
olabilir. Üretici semantik capability/grain/additive/unit bilgisi uydurmaz.

`MERGEN_PK_ASYNC=false` bu aşamada korunur.

---

## 9. Anlamsal küresyon (Tier-3, elle)

Telemetriye göre en çok kullanılan sorguları `R/library_query_meta.R` içinde
küre edin. Buraya yalnız kararlı anlamsal yetenek kimlikleri, onaylı sentetik
alias'lar ve `grain`, `additive`, `unit`, `primary_entity`, `intents`,
`default_measures`, `row_cap` gibi insan kararı gereken alanlar girer.

Gerçek üretim proje/program adları yalnız gitignore'lu
`R/library_query_aliases_local.R` içinde tutulur ve üretici bu dosyayı yazmaz.

---

## 10. Yapılandırma anahtarları

| Anahtar | Varsayılan | Anlamı |
|---|---|---|
| `MERGEN_PK_META_MODE` | `describe` | `describe` veya `sample`; geçersiz değer hata verir |
| `MERGEN_PK_META_SAMPLE_ROWS` | `500` | `sample` kipinde sorgu başına istemci aktarım satır tavanı |
| `MERGEN_PK_META_HIGH_CARD_MIN` | `50` | Bu sayıdan fazla farklı değer `high_cardinality = TRUE` kanıtlar. `sample` kipinde `MERGEN_PK_META_SAMPLE_ROWS` değerinden KESİNLİKLE KÜÇÜK olmalıdır; aksi hâlde kanıt ulaşılamaz olur ve koşu hata ile durur |
| `MERGEN_PK_META_SQL_TIMEOUT_SEC` | `120` | Sorgu başına zaman aşımı |
| `MERGEN_PK_META_MAX_RESULT_MB` | `64` | Örnekleme sonuç bayt tavanı |
| `MERGEN_PK_META_RESUME` | `TRUE` | Kesilen koşuyu sürdür; temiz koşu için `FALSE` |
| `MERGEN_PK_META_RESUME_MAX_AGE_SEC` | `21600` | Devam önbelleğindeki DB kanıtının azami yaşı (saniye); `0` = sınırsız (teşhis) |
| `MERGEN_PK_META_SAMPLE_UNICODE` | `TRUE` | `sample` SQL'ini üretimin Unicode parametre yolu ile gönder |

Tümü `.Renviron.example` içinde belgelenmiştir.
