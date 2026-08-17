# Faz 3b — Sorgu metadata üreticisi: operatör kılavuzu

Bu belge **Windows VM'de elle yürütülen** Faz 3b adımını anlatır. Tasarım
gerekçesi ve sözleşme için ana kaynak
[`docs/proje-kaynak-analizi-master-plan.md`](proje-kaynak-analizi-master-plan.md)
§5.1'dir; burada yalnızca **ne yapacağınız** vardır.

Amaç iki tanedir:

1. Gerçek üretim sorgu kütüphanesi için **yapısal metadata** üretmek
   (`R/library_query_meta_local.R`).
2. `MERGEN_PK_ENGINE=v2` anlamsal/filtreli sorulara güvenle cevap verebilsin diye
   **operatör müdahalesi gereken sorguları** listeleyen bir **sağlık raporu**
   üretmek.

Üretici **yalnızca okur**. Üretim verisini değiştirmez, SQL'i onarmaz, RLS
beyanını kaldırmaz, anlamsal metadata uydurmaz.

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

---

## 2. `describe` kipi (ÖNCE BU)

`describe` kipi sorguları **çalıştırmaz**. SQL Server'ın kendi
`sys.dm_exec_describe_first_result_set` tanımlayıcısını sorar; DB yükü yok
denecek kadar azdır. İlk geçiş her zaman bu olmalıdır.

```r
Sys.setenv(MERGEN_PK_META_MODE = "describe")
source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
```

Konsolda göreceğiniz özet:

```
[PK_META_GEN] Toplam sorgu            : 169
[PK_META_GEN] Sema alinan             : 165
[PK_META_GEN] Uretilen katmana dahil  : 158
[PK_META_GEN] GERI CEKILEN            : 7
[PK_META_GEN] RLS UYUSMAZLIGI         : 3
...
```

---

## 3. Sağlık raporunu okuyun

```
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
| `BASARISIZ` (`failed`) | Şema alınamadı (tanımlayıcı dönmedi / sürücü hatası) | İnceleyin; `sample` kipi yardımcı olabilir |
| `ATLANDI` (`skipped`) | SQL salt-okunur kapısından geçemedi; **çalıştırılmadı** | SQL'i inceleyin |

`GERI CEKILDI` bir gerileme **değildir**: o sorgu bugünkü davranışında
(`Tier-0`, `pending_no_schema`) kalır ve istek zamanı RLS zorlaması **hiç
değişmez**. Yalnızca gerçek şemasını kazanmamış olur.

### İLERLEMEYİ DURDURAN bulgular

Bunlar düzeltilmeden `MERGEN_PK_ENGINE=v2` anlamsal/filtreli sorularda güvenilir
sayılmaz:

| Bulgu kodu | Anlamı | Düzeltme |
|---|---|---|
| `rls_column_missing` **(GÜVENLİK)** | Beyan edilen RLS sütunu sorgu sonucunda **yok** — D6 fail-open deliği | **Ya** SQL o güvenlik sütununu döndürsün, **ya** `rls_columns` beyanı düzeltilsin. Beyanı silerek "çözmeyin" |
| `column_meta_missing_in_schema` | Küre edilmiş metadata var olmayan bir sütuna atıf yapıyor | `R/library_query_meta.R` içindeki sütun adını düzeltin |
| `role_type_mismatch` | Küre edilmiş `role="measure"` ama sütun metin (ya da `role="date"` ama tarih değil) | Rolü veya SQL'i düzeltin |
| `grain_columns_missing_in_schema` vb. | `grain_columns` / `default_group_by` / `default_measures` / `primary_entity` var olmayan sütuna atıf yapıyor | Küresyonu düzeltin |
| `sql_not_readonly` | SQL tek bir salt-okunur SELECT değil | Sorguyu inceleyin |

Operatörün VM'de gördüğü gerçek örnek:

```
[GERI CEKILDI] gen_pro_per_01 -- ... (db=primary)
    - [blocking/GUVENLIK] rls_column_missing: Beyan edilen RLS sutunu gercek
      sonucda yok: ProjeKodu, ProgMd1Kodu.
```

Bu, v2'nin SQL döndükten sonra durmasının **tam sebebidir**: sorgu satır
döndürür, ancak yetki filtresi uygulanacak sütun sonuçta yoktur, bu yüzden
kapalı başarısız olur. Sağlık raporu artık bunu kullanıcı bir soru sormadan
**önce** listeler.

### Eylem gerektiren ama İLERLEMEYİ DURDURMAYAN bulgular

| Bulgu kodu | Anlamı |
|---|---|
| `no_semantic_capability` | Sorguda `capability` beyanı yok. Ölçü/tarih/boyut gerektiren istekler bu sorgu için SQL'den **önce** `unknown_no_semantic_metadata` ile durur. **Bu doğru davranıştır** (fail-closed) — üretici bunu doldurmaz; Tier-3 insan küresyonudur |
| `unmapped_sql_type` | SQL tipi eşlenemedi; en muhafazakâr yapıya (`character`/`dimension`) düşüldü. O sütunda toplama yapılmaz |
| `unbounded_lob_column` | Kanıtlanmış genişlik üst sınırı olmayan sütun (`nvarchar(max)`, `xml`, ...) |
| `no_primary_entity`, `no_grain`, `rls_not_declared` | Bilgilendirme / Tier-0 geri düşüşü |

---

## 4. Bulguları düzeltin ve `describe`'ı yeniden çalıştırın

Üretici **idempotent**'tir. Aynı komutu tekrar çalıştırmak güvenlidir:

* küre edilmiş metadata (`R/library_query_meta.R`) **ezilmez** — küresyon kazanır,
* operatör alias dosyası (`R/library_query_aliases_local.R`) **hiç açılmaz**,
* yalnızca `R/library_query_meta_local.R` yeniden yazılır.

Bloklayıcı bulguları düzelttikçe geri çekilen sorgular `DAHIL` durumuna geçer.

---

## 5. `sample` kipi (İKİNCİ GEÇİŞ, isteğe bağlı)

`describe` bazı sorgular için şema döndüremez (geçici tablo, dinamik SQL,
belirsiz sonuç kümesi). `sample` kipi o sorguları imleçten **yalnızca N satır**
çekerek çözer.

```r
Sys.setenv(MERGEN_PK_META_MODE = "sample")
source("tools/pk/generate_query_meta.R", encoding = "UTF-8")
```

**Kanıt sınırını bilerek kullanın.** Örnekleme yöntemi `prefix`'tir (veritabanı
dönüş sırasındaki ilk N satır) ve **temsili değildir**. Bu yüzden yalnızca
**tek yönlü** sonuçlar kaydedilir:

| Gözlem | Sonuç |
|---|---|
| Mükerrer değer görüldü | Benzersizlik **çürütülür** |
| Eşikten (`50`) fazla farklı değer görüldü | `high_cardinality = TRUE` **kanıtlanır** |
| NULL görüldü | "NULL yok" **çürütülür** |
| Mükerrer/NULL **görülmedi** | **Hiçbir şey kanıtlanmaz** (alan `NA` kalır) |
| Eşikten az farklı değer görüldü | **Hiçbir şey kanıtlanmaz** (düşük kardinalite varsayılmaz) |

500 satırlık bir örnek 501 satırlık sonucu 5 milyondan **ayırt edemez**; bu
yüzden `row_cap` geçti/kaldı iddiası **üretilmez** (`cardinality_claim:
"unknown"`).

Üretici SQL'i **sarmalamaz** (`SELECT TOP n FROM (...)` yok): üretim sorguları
`ORDER BY` / CTE / `OPTION(...)` içerebilir ve sarmalamak hem sorguyu bozar hem
de salt-okunur kapısından geçen metin ile çalışan metni ayırırdı.

---

## 6. Çıktıyı doğrulayın

```r
file.exists("R/library_query_meta_local.R")
```

`TRUE` olmalıdır. Ve **izlenmediğini** doğrulayın:

```r
system("git status --short R/library_query_meta_local.R")
```

Hiçbir şey yazmamalıdır (`.gitignore`'lu). Bu dosyayı **asla commit etmeyin**:
üretimden türetilmiş sütun envanteri ve şema istatistikleri içerir.

---

## 7. MERGEN Bilge'yi yeniden başlatın

Metadata **açılışta** yüklenir. Tarayıcı yenilemesi **yetmez**; R süreci
yeniden başlamalıdır.

Açılış logunda şunu görmelisiniz:

```
[SQL_LOADER] PK metadata sozlesmesi dogrulandi: <N> sorgu.
```

Açılış **düşerse**, `R/library_query_meta_local.R` dosyasını yeniden
adlandırın/silin ve üreticiyi tekrar çalıştırın. (Üretici bunu önlemek için
yazmadan önce aynı açılış kapısını simüle eder; buna rağmen bir açılış hatası
görürseniz sağlık raporundaki bloklayıcı bulgular listesi çıkış noktanızdır.)

---

## 8. v2'yi SENKRON test edin

```ini
MERGEN_PK_ENGINE=v2
MERGEN_PK_ASYNC=false
```

R sürecini yeniden başlatın, sonra Proje ve Kaynak Analizi'nde şunları deneyin:

1. Geniş bir soru (ör. "projeleri özetle") — Faz 3b öncesinde de çalışıyordu.
2. **Filtreli/özel bir soru** — Faz 3b'nin düzeltmeyi hedeflediği durum.
3. Belirli bir kişi/proje soran bir soru — RLS yolunu tetikler.

Hâlâ `capability_missing` / `unknown_no_semantic_metadata` alıyorsanız bu bir
hata **değildir**: o sorgunun anlamsal küresyonu (`capability`, `grain`,
`additive`, `unit`, `primary_entity`) henüz yapılmamıştır. Üretici bunu
kasıtlı olarak uydurmaz.

**`MERGEN_PK_ASYNC` bu aşamada `false` kalır.** Faz 6 ayrı bir kapıdır.

---

## 9. Anlamsal küresyon (Tier-3, elle)

Telemetriye göre en çok kullanılan ~30 sorguyu `R/library_query_meta.R` içinde
küre edin. Sağlık raporunun "ANLAMSAL KURESYON BEKLEYEN SORGULAR" bölümü listeyi
verir.

`R/library_query_meta.R` **izlenir**, bu yüzden içine yalnızca şunlar girer:

* kararlı, anlamsal yetenek kimlikleri (sütun adı **değil**),
* sentetik ya da dışa aktarımı onaylanmış alias'lar,
* `grain`, `additive`, `unit`, `percent_scale`, `primary_entity`, `intents`,
  `default_measures`, `row_cap`.

Gerçek üretim proje/program adları **yalnızca** gitignore'lu
`R/library_query_aliases_local.R` içine girer ve o dosyayı **üretici asla
yazmaz** — orası tamamen sizindir.

---

## 10. Yapılandırma anahtarları

| Anahtar | Varsayılan | Anlamı |
|---|---|---|
| `MERGEN_PK_META_MODE` | `sample` | `describe` veya `sample`. **İlk geçişi `describe` yapın.** Geçersiz değer sessizce varsayılana düşmez, hata verir |
| `MERGEN_PK_META_SAMPLE_ROWS` | `500` | `sample` kipinde sorgu başına en fazla satır |
| `MERGEN_PK_META_HIGH_CARD_MIN` | `50` | Bu sayıdan fazla farklı değer `high_cardinality = TRUE` kanıtlar (tek yönlü) |
| `MERGEN_PK_META_SQL_TIMEOUT_SEC` | `120` | Sorgu başına zaman aşımı |
| `MERGEN_PK_META_MAX_RESULT_MB` | `64` | Örnekleme sonuç tavanı |
| `MERGEN_PK_META_RESUME` | `TRUE` | Kesilen koşuyu kaldığı yerden sürdür. Temiz koşu için `FALSE` |

Devam durumu `artifacts/pk-meta/generator-state.json` içinde tutulur ve
**yalnızca DB gözlemlerini** taşır; karar/küresyon her koşuda yeniden hesaplanır,
böylece bir küresyon değişikliği önbellek yüzünden kaçırılmaz. Kip değişirse
önbellek yok sayılır.

---

## 11. Güvenlik ve gizlilik özeti

* Üretici **yalnızca okur**: her SQL üretimin kullandığı **aynı**
  `pk_sql_classify_readonly()` kapısından geçer; reddedilen SQL çalıştırılmaz.
  `dbExecute`/`dbWriteTable` gibi veri değiştiren çağrılar üreticide **yoktur**.
* Rapora ve loglara **DSN, kimlik bilgisi, parola, uç nokta** girmez; sürücü
  hata metinleri maskelenir. Reddedilen SQL'in **ham metni** rapora girmez.
* Rapora **üretim satır değerleri** girmez; yalnızca şema/sütun adları ve sayımlar.
* Üretilen dosya **saf ASCII**'dir (ASCII dışı karakterler `\uXXXX` kaçışıyla
  yazılır), böylece Windows/WINDOWS-1254 kod sayfasında `source()` kesilmesi
  sınıfı tamamen kapanır. Türkçe sütun adları bozulmadan geri okunur.
* Yazma **atomiktir**: geçici dosyaya yaz → parse et → yalnızca başarılıysa
  yerine taşı. Yarım/bozuk dosya asla yerine geçmez.
* Bu koşu **hiçbir** fail-closed kapıyı zayıflatmaz. Geri çekilen bir sorgu
  bugünkü Tier-0 davranışında kalır ve istek zamanı RLS doğrulaması koşulsuzdur.

---

## 12. Kanıt sınırı (dürüstlük)

Bu koşu **yalnızca** raporun `passed`/`ok` dediği adımların kanıtıdır. Şunları
**kanıtlamaz**: tarayıcı UX, SSO kimlik zamanlaması, LLM seçim doğruluğu,
gerçek Excel çıktısı, eşzamanlı oturum yanıt hızı ya da Faz 6 asenkron
davranışı. Bunlar `RUNBOOK.md` ve `bash tools/vm_evidence_gate.sh` kapılarıdır.
