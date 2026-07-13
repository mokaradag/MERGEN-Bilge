# Ortak Oturumlar (İşbirlikçi Çalışma Odaları)

Bu belge, MERGEN Bilge "Ortak Oturumlar" özelliğinin ürün amacını, navigasyonunu,
rol/davet/canlı durum modelini, oda içi mesajlaşma ile yapay zekâ akışı ayrımını,
ortak belge sahipliğini, veritabanı kurulumunu, güvenlik beklentilerini ve test
kapsamını açıklar. Çalışma kuralları için [`../CLAUDE.md`](../CLAUDE.md), operasyon
için [`../RUNBOOK.md`](../RUNBOOK.md) otoritatif kalır.

## 1. Ürün Amacı

Ortak Oturumlar, MERGEN Bilge'yi tek kullanıcılı bir asistandan **ekip tabanlı bir
yapay zekâ çalışma odasına** genişletir:

- Birden fazla kullanıcı aynı paylaşılan oturumda çalışır.
- Bir katılımcının yapay zekâya sorduğu sorunun yanıtını **tüm katılımcılar** görür.
- Katılımcılar yapay zekâya gitmeyen **oda içi mesajlarla** kendi aralarında yazışır.
- Kullanıcılar davet edilir (Mergen içi bildirim veya e-posta taslağı).
- Ajan/yapay zekâ üretimi belgeler önce **ortak oda belgesi** olur; isteyen
  katılımcı açık eylemle kendi kişisel klasörüne kopyalar.
- Ortak oturum geçmişi sonradan ayrı listelerde geri çağrılır.

İki ortak oturum türü vardır (`KaynakTuru`):

| Tür | Açıklama |
|---|---|
| `NormalSohbet` | Normal MERGEN Bilge sohbetinin paylaşılan hâli. |
| `BilgeYolaç` | Bilge Yolaç/ajan çalışmasının paylaşılan hâli; üretilen dosyalar ortak belgedir. |

### Kişisel geçmiş / ortak geçmiş ayrımı (değişmez kural)

Ortak oturum verisi **hiçbir zaman** kişisel tablolara yazılmaz:

- Kişisel sohbetler `MB_Chats` / `MB_Messages` içinde kalır.
- Kişisel Bilge Yolaç oturumları `MB_ClaudeCode_Sessions` / `MB_ClaudeCode_Runs` içinde kalır.
- Ortak oturumlar yalnızca `MB_Ortak*` / `MB_Kullanici_CanliDurum` / `MB_Bildirimler`
  ailesine yazar.

Kullanıcının zihinsel modeli nettir:

- **"Söyleşi Geçmişim"** = kişisel normal sohbetlerim.
- **"Bilge Yolaç Oturumlarım"** = kişisel ajan oturumlarım.
- **"Ortak Çalışmalarım"** = ekip oturumları.

## 2. Navigasyon

| Menü | Sekme | İçerik |
|---|---|---|
| Söyleşi Yönetimi > **Ortak Söyleşiler** | `ortak_sohbetler` | Yalnızca `NormalSohbet` türündeki ortak oturumlar. |
| Bilge Yolaç > **Ortak Bilge Yolaç Oturumları** | `ortak_bilge_yolac` | Yalnızca `BilgeYolaç` türündeki ortak oturumlar. |
| **Ortak Çalışmalarım** | `ortak_calismalar` | Tümü + Davetlerim + Arşivlenmiş Ortak Oturumlar; oda bu sayfada açılır. |

Üç sekme de tek modül kimliğinden (`ortak_calismalar_module`) beslenir (Destek
modülü deseni). Oda UI'si yalnızca hub yüzeyine gömülür; diğer sekmelerden "Aç"
hub sekmesine yönlendirir.

### Arayüz / UX sözleşmesi

Ortak yüzeyler ana uygulamayla aynı sakin, profesyonel dili paylaşır (tema
token'ları; koyu + açık tema):

- **Başlık**: standart uygulama başlık deseni (`chat-header settings-header-fixed`),
  ikonsuz; `ORTAK` rozeti Yönetici (`ADMIN`) / Bilge Yolaç (`AJAN`) rozetleriyle
  aynı dolgulu pill dilinde. Başlık, kabuğun yatay dolgusunun dışına taşarak
  diğer sayfalarla aynı hizada durur (sağ/sol boşluk yoktur).
- **Filtreler** (Tümü / Davetlerim / Arşivlenmiş) radio yerine **sekme çubuğu**
  görünümündedir; davet paneli filtresi de aynı dili kullanır.
- **Butonlar** sakin, kompakt uygulama dilinde (aşırı turuncu değil): birincil
  eylemler dingin indigo (`--oo-accent`), "Yenile" Söyleşi Geçmişi ile aynı teal.
- **Oturum kartları** ince üst aksan şeridi + hover yükselmesiyle profesyoneldir.
- **Composer**: model ve persona açılır menüleri girdi kutusunun ALTINDA,
  "Odaya Yaz" / "Yapay Zekâya Sor" ile aynı satırdadır (dikey alan tasarrufu;
  ana söyleşi "Model Değiştir" dili). "Yeni bağlam başlat" ve kalıcı
  "Sohbeti Temizle" düğmeleri doğrudan yan yanadır; temizleme yalnızca
  `katilimci_yonet` yetkisinde çizilir. Oda açıkken shinydashboard
  `content-wrapper.oo-oda-acik-kok > content > tab-content > active tab-pane`
  zinciri de flex hâline getirilir; oda parent flex/min-height zinciriyle dikeyde alt boşluk
  bırakmadan yayılır.
- **Yan panel**: Katılımcılar paneli varsayılan olarak daha yüksektir; Katılımcılar
  ile Ortak Belgeler arasında **sürüklenebilir ayraç** vardır (yükseklik oturum
  boyunca `sessionStorage`'da korunur; klavye ok tuşlarıyla da ayarlanabilir).
- **Mesaj balonları** ana söyleşiyle uyumlu: aralarındaki dikey boşluk Shiny
  `uiOutput` sarmalayıcısına değil, gerçek balon kapsayıcısı `.oo-mesaj-listesi`
  üzerine uygulanır;
  sakin renk paleti, persona kimlikli yapay zekâ balonu.
- **Akıcılık**: bir katılımcının soru göndermesi tüm ekranı dondurmaz. LLM
  çağrısı worker'da async koşar; 4 sn'lik yoklama sırasında Shiny "recalculating"
  soluklaşması ortak oda yüzeylerinde kapatılır (genel griye-dönme/donma hissi
  giderilir). Model/persona açılır menüleri yalnızca ROL değişince yeniden çizilir
  (yoklamada seçim/odak bozulmaz). Yeni mesajlar geldiğinde kullanıcı diptedeyse
  akış otomatik en alta kayar.

## 3. Oda İçi Mesajlaşma / Yapay Zekâ Ayrımı

Oda mesaj alanında iki AYRI eylem vardır ve UI bu ayrımı kaçırılamaz yapar:

- **"Odaya Yaz"** → `MesajTuru = OdaMesajı`, `Hedef = Katılımcılar`. **ASLA LLM
  tetiklemez.** Kalıcıdır ve tüm içerik erişimli katılımcılara görünür.
- **"Yapay Zekâya Sor"** → `MesajTuru = YapayZekaSorusu`, `Hedef = YapayZeka`.
  Buton altında açık uyarı vardır: *"Bu mesaj yapay zekâya gönderilecek ve yanıt
  tüm katılımcılar tarafından görülecek."* Yanıt `YapayZekaYanıtı` olarak kalıcı
  olur ve tüm katılımcılara görünür.

Yönlendirme kararı saf yardımcıdadır: `ortak_mesaj_yonlendirme_plani()`
(`R/helpers_ortak_oturum_permissions.R`). LLM bağlamına yalnızca
`YapayZekaSorusu`/`YapayZekaYanıtı` çiftleri girer; oda mesajları otomatik olarak
bağlama **girmez** (`ortak_yz_sohbet_gecmisi()`).

### Yanıt üretimi ve eşzamanlılık

- Oda başına **tek aktif üretim** kuralı DB kilidiyle uygulanır
  (`MB_OrtakOturum_AktifUretimler`; `ortak_db_uretim_kilidi_al/birak`).
- Üretim sürerken ikinci soru denemesi açık Türkçe mesajla reddedilir:
  *"Yanıt üretimi sürüyor"*. `MB_OrtakOturum_YapayZekaKuyrugu` tablosu ileride
  gerçek kuyruk davranışı için şemada hazırdır (bkz. §10 Sınırlamalar).
- Soru üretim başlamadan ÖNCE kalıcılaştırılır; yanıt tamamlanınca kalıcılaşır.
- LLM çağrısı `tracked_future_promise(task_fn = ...)` ile worker'da koşar
  (`task_type = "ortak_oturum_llm"`); DB kalıcılığı ve kilit bırakma ana
  süreçteki promise callback'indedir. Oda 4 sn'lik yoklama ile tüm katılımcılarda
  senkron kalır (istemci başına ayrı LLM çağrısı YOKTUR; oda başına tek çağrı).
- Model `ORTAK_OTURUM_MODEL` ortam değişkeniyle, yoksa `api_config$local_models[1]`
  ile seçilir. API anahtarı merkezi özellik-anahtar yardımcısından gelir
  (`mb_api_key_get_feature_key_value`, CLAUDE.md 1F sözleşmesi).
- **Reaktif bağlam güvenliği (kritik):** ağır üretim işi `session$onFlushed`'a
  ve kuyruk zinciri `promises::then` callback'ine ertelendiği için REAKTİF ALAN
  içinde ama reaktif BAĞLAM (consumer) DIŞINDA koşar. Orada bir `reactiveVal`'ı
  doğrudan okumak *"Operation not allowed without an active reactive context"*
  hatası fırlatır. `etkin_model()` bu yüzden `secili_model`'i
  `shiny::isolate(...)` ile okur. Ertelenmiş/asenkron yoldan erişilen her
  reaktif okuma `isolate()` ile sarılmalı ya da erteleme öncesi gözlemcide
  yakalanmalıdır; aksi halde HER soru *"Yapay zekâ yanıtı başlatılamadı; lütfen
  tekrar deneyin."* hatasıyla düşer. (`shiny::testServer` gövdeyi aktif reaktif
  bağlamda çalıştırdığı için bu hatayı maskeler; regresyon testi çıplak
  `MockShinySession` + `withReactiveDomain` kullanır:
  `tests/testthat/test-ortak-oturum-yz-reactive-context-behavior.R`.)

### Yapay zekâ personası

Her ortak oturumun etkin bir **personası** vardır (mevcut beş MERGEN Bilge
personası: `emre`, `selin`, `deniz`, `can`, `ipek` — `R/config_characters.R`
tek kaynak). Yapay zekâ yanıtları jenerik "Yapay Zekâ" etiketi yerine seçili
personanın adı ve aksan renkli avatarıyla gösterilir; yanıt persona sistem
talimatıyla üretilir (`ortak_oturum_persona_sistem_prompt()`).

- Persona `MB_OrtakOturumlar.SecilenPersona` kolonunda saklanır (aşamalı devreye
  alma: idempotent `ALTER`; kolon kurulu değilse tüm yol güvenli düşer).
- Oluşturmada persona yazılmaz; okuma NULL/NA ise `ortak_oturum_persona_kimligi()`
  oturum kimliğinden **deterministik ve kararlı** bir varsayılan türetir (persona
  metadata'sı olmayan eski oturumlar da güvenli ve çeşitli görünür).
- Personayı yalnızca `katilimci_yonet` yetkisi olan rol (**Sahip / Oturum
  Yöneticisi**) değiştirebilir (`ortak_db_persona_guncelle()`, işlem içinde
  yetki doğrulanır). Değişiklik oda kaydında saklanır ve yoklamayla tüm
  katılımcıların mesaj avatarlarına/adlarına yansır.
- Persona açılır menüsü composer aksiyon satırında model açılır menüsünün
  yanındadır; yetkisi olmayan katılımcıya salt-okunur persona rozeti gösterilir.
- Saf yardımcılar `R/helpers_ortak_oturum_sunum.R` içindedir:
  `ortak_oturum_persona_kimligi()`, `ortak_oturum_persona_gorunumu()`,
  `ortak_persona_secenekleri()`, `ortak_oturum_persona_sistem_prompt()`.

## 4. Roller ve Yetkiler

DB'de saklanan roller Türkçedir: `Sahip`, `OturumYöneticisi`, `Katılımcı`, `İzleyici`.

| Yetki | Sahip | OturumYöneticisi | Katılımcı | İzleyici |
|---|---|---|---|---|
| Odayı okuma | ✔ | ✔ | ✔ | ✔ |
| Odaya yazma | ✔ | ✔ | ✔ | ✖ |
| Yapay zekâya sorma | ✔ | ✔ | ✔ | ✖ |
| Katılımcı davet etme | ✔ | ✔ | ✖ | ✖ |
| Katılımcı yönetme (Sahip hariç) | ✔ | ✔ | ✖ | ✖ |
| Rol değiştirme | ✔ | ✖ | ✖ | ✖ |
| Odayı herkes için arşivleme/kapatma | ✔ | ✖ | ✖ | ✖ |
| Ortak belgeyi kişisel klasöre kopyalama | ✔ | ✔ | ✔ | ✔ |

Kurallar `ortak_rol_yetkileri()` saf matrisinde tek kaynaktır; bilinmeyen rol
**fail-closed** davranır (hiçbir yetki verilmez). UI gizlemesi güvenlik değildir:
her yazma/okuma DB katmanında yeniden doğrulanır.

### Sahiplik kuralları

- Odayı oluşturan kullanıcı `Sahip` rolüyle otomatik `Katıldı` olur.
- **Her odada her zaman en az bir Sahip kalır:** Sahip odadan "Ayrıl" ile
  çıkamaz; önce "Katılımcıyı Yönet > Sahipliği Devret" ile devretmeli ya da
  odayı herkes için arşivlemelidir.
- Sahiplik devri tek işlemde yapılır (`ortak_db_sahiplik_devret`): hedef `Sahip`
  olur, önceki Sahip `OturumYöneticisi`ne düşer. Yalnızca içerik erişimli
  (daveti kabul etmiş) katılımcıya devredilebilir.
- `Sahip` rolü başka hiçbir yolla atanamaz/yönetilemez
  (`ortak_katilimci_yonetilebilir_mi` + rol güncelleme koruması).

## 5. Davet ve Canlı Durum Modeli

### Davet paneli ("Katılımcı Çağır")

`MB_Users` üzerinden tüm bilinen kullanıcılar listelenir: görünen ad
(`KaynakAdi`), kullanıcı adı, e-posta, departman + canlı durum + mevcut
davet/katılım durumu + atanacak rol. Sekmeler: **Çevrim İçi Kullanıcılar / Tüm
Kullanıcılar / Davet Edilenler**; ad/kullanıcı adı/e-posta/departman araması vardır.

Aday süzme kararı saf ve test edilebilirdir: `ortak_davet_aday_kullanicilar()`
(`R/helpers_ortak_oturum_sunum.R`) kullanıcı dizinine canlı durum + mevcut
katılım durumu ekler ve seçili sekmeye göre süzer (kendisi ve zaten `Katıldı`
olan kullanıcılar her sekmede elenir). Panel açılırken canlı durum anlık
görüntüsü TAZE okunur (`ortak_db_canli_durumlar()`), 4 sn oda yoklaması
beklenmez; böylece çevrim içi kullanıcılar ilk render'da doğru listelenir.

- **Çevrim içi kullanıcı** → birincil eylem **"Mergen İçinden Çağır"**: davet
  kaydı + uygulama içi bildirim (`MB_Bildirimler`, `OrtakOturumÇağrı`). Alıcının
  ekranında modal belirir: *"{Ad} sizi ortak oturuma çağırıyor."* — **Katıl /
  Daha Sonra / Reddet**.
- **Çevrim dışı kullanıcı** → birincil eylem **"E-posta Taslağı Hazırla"**:
  e-posta OTOMATİK GÖNDERİLMEZ; içeriksiz güvenli taslak `mailto:` bağlantısıyla
  davet edenin kendi e-posta istemcisinde açılır, davet eden gözden geçirip
  kendisi gönderir. Taslak hazırlama zamanı `SonGonderimZamani` alanına yazılır
  (gönderim kanıtı DEĞİLDİR).

### E-posta güvenlik kuralı

Taslak yalnızca şunları içerir: davet eden ad, oturum başlığı ve "MERGEN
Bilge'ye giriş yapıp **Ortak Çalışmalarım > Davetlerim** bölümünden kabul edin"
yönergesi. Sohbet içeriği, yapay zekâ yanıtı, belge adı/yolu/bağlantısı veya
yetkilendirmeyi atlatan URL **asla** eklenmez; `ortak_davet_eposta_guvenli_mi()`
bu sınırı doğrular. SMTP altyapısı yoktur; `R/helpers_ortak_oturum_email.R`
temiz bir servis dikişidir (ileride gerçek gönderim eklenirse durum kaydı zorunludur).

### Davet kabulü = içerik erişimi

- Davet edilen kullanıcı kabul edene kadar yalnızca davet METADATA'sını görür
  (davet eden, başlık, tür, rol, katılımcı sayısı). Oda mesajları, belgeler ve
  katılımcı ayrıntıları KAPALIDIR (`ortak_icerik_erisimi_var_mi`, fail-closed).
- Kabul → `KatilimDurumu = Katıldı` + içerik erişimi. Red → `Reddetti`.
- Davet yalnızca muhatabı tarafından ve yalnızca `Bekliyor` durumundayken yanıtlanır.

### Canlı durum (kalp atışı)

- Tarayıcı 30 sn'de bir kalp atışı gönderir (`www/js/ortak_oturumlar.js`);
  sunucu tarafı 20 sn kısma uygular (SQL Server yük koruması) ve
  `MB_Kullanici_CanliDurum` içinde kullanıcı+oturum anahtarı başına tek satır
  upsert edilir.
- Tazelik (yaş) **veritabanının KENDİ saatiyle** hesaplanır — R'nin `Sys.time()`
  değeri ile ODBC'nin `DATETIME2`'yi POSIXct'e çevirirken uyguladığı saat dilimi
  yorumu KARŞILAŞTIRILMAZ. `ortak_db_canli_durumlar()` sunucu-tarafı bir yaş
  sütunu seçer — SQL Server'da `DATEDIFF(SECOND, c.SonKalpAtisiZamani,
  SYSUTCDATETIME())`, SQLite'ta `CAST((julianday('now') -
  julianday(c.SonKalpAtisiZamani)) * 86400 AS INTEGER)` — ve R yalnızca bu yaşı
  Türkçe duruma eşler (`ortak_sunum_durumu`, tek eşik kaynağı: `ref - yas`):
  ≤120 sn → `Çevrimİçi`; ≤300 sn → `Boşta`; aksi → `ÇevrimDışı`. Böylece istemci
  tarafı ODBC saat dilimi/an dönüşümü denklemden çıkar; taze bir kalp atışının
  geçmişe kayıp çevrim içi kullanıcıyı sessizce `ÇevrimDışı` göstermesi (davet
  panelinde çevrim içi listenin boş kalmasının kök nedeni) önlenir.
- Kullanıcı başına EN GÜNCEL (en küçük yaş) satır tutulur. NA yaş en eski
  (`Inf`); NEGATİF yaş (R yazımı ile DB "şimdi"si arasında küçük saat kayması,
  kalp atışı "gelecekte") TAZE demektir — dedup'ta en öne sıralanır,
  sınıflandırmada `0`'a sabitlenir (çevrim içi). Yaş sorgusu beklenmedik bir
  lehçede başarısız olursa eski `SonKalpAtisiZamani` + `ortak_sunum_durumu()`
  yoluna güvenli düşülür. Yazma yolu (`ortak_db_kalp_atisi`) da AYNI DB saatini
  kullanır: `SonKalpAtisiZamani`/`OlusturmaZamani` R `.oo_db_now()` parametresiyle
  değil, DB-saat SQL ifadesiyle (`SYSUTCDATETIME()` / SQLite `datetime('now')`)
  yazılır. Böylece yazma ve okuma tek saati paylaşır; DB saati R'den ILERI olsa
  bile taze bir kalp atışı eşiği aşıp yanlışça çevrim dışı görünmez. Başarısızlıkta
  loglar (`Canlı durum kalp atışı yazılamadı`).
- `ortak_sunum_durumu` yine de POSIXct / ISO `T` / kesirli-saniyeli metin
  biçimlerine dayanıklıdır (güvenli düşüş yolu ve başka çağıranlar için).
  Regresyon: `tests/testthat/test-ortak-oturum-canli-durum-behavior.R` ve
  `tests/testthat/test-ortak-oturum-davet-online-behavior.R`.
- Durum göstergesi yalnızca renge dayanmaz: nokta + `title`/`aria-label` metni.
- SSO placeholder kimlik (0) ile canlı durum yazılmaz.

### Davet güvenceleri

- Davet spam koruması: oturum başına 10 dakikada en çok 15 davet
  (`oo_davet_hiz_siniri_asildi_mi`), ayrıca zaten `DavetEdildi`/`Katıldı` olan
  kullanıcıya yinelenen davet üretilmez.
- Süresi dolan davetler bakım temizliğinde `SüresiDoldu` yapılır (§8).

## 6. Ortak Belge Modeli

- Ajan/yapay zekâ üretimi dosya önce **ortak oda belgesidir**: fiziksel kopya
  yapılandırılmış MERGEN dosya kökü altındaki
  `ortak_oturumlar/oturum_<OrtakOturumID>/` dizinine alınır; metadata
  `MB_OrtakOturum_Dosyalar`a yazılır (DB'ye dosya içeriği yazılmaz).
- Hiçbir katılımcının kişisel klasörüne OTOMATİK yazılmaz.
- Oda "Ortak Belgeler" bölümünde her belge için: ad, tür, boyut, üreten,
  zaman, kullanıcının kopya durumu ve **"Kendi Dosyalarıma Kaydet"** eylemi
  gösterilir.
- "Kendi Dosyalarıma Kaydet" → `ortak_dosya_kisisel_kopyala()`: yetki denetimi
  (içerik erişimi + `belge_kopyala`), kaynak yolun ortak belge kökü İÇİNDE
  olduğunun doğrulanması (traversal koruması), mevcut Dosya Yönetimi kaydı
  (`global_register_file`) ve kullanıcı başına kopya durumu
  (`MB_OrtakOturum_DosyaKopyalari`: `Bekliyor/Kopyalandı/Reddetti/Hata`).
  Zaten kopyalanmış belge ikinci kez fiziksel kopyalanmaz.
- Fiziksel dosyası kaybolan belgeler bakım taramasında `Silindi` işaretlenir.

### 6.1 Paylaşılan belge GİRDİLERİ (katılımcı yüklemeleri)

Ortak Belgeler yalnızca üretilen çıktı değil, aynı zamanda **paylaşılan model
girdisidir** (`R/helpers_ortak_oturum_belgeler.R` +
`R/module_ortak_oturum_belge_paneli.R`):

- `yapay_zeka_sor` yetkili katılımcılar (Sahip / Oturum Yöneticisi / Katılımcı)
  odaya belge **yükler**, **kaldırır** ve **bağlam seçimini** değiştirir;
  İzleyici yalnızca görür. Her eylem sunucu tarafında fail-closed yetki
  denetiminden geçer.
- Yüklemeler tekil oturum yüklemeleriyle **AYNI doğrulama sınırından** geçer:
  `validate_uploaded_file` (boyut sınırı `getOption("mergen.upload_max_mb", 25L)`,
  `fm_normal_allowed_extensions()` uzantı beyaz listesi, traversal/UTF-8/bidi
  dosya adı kuralları).
- Fiziksel dosyalar mergen_uploads (MCP taban) altında **oturuma özel
  deterministik klasörde** saklanır: `<mcp_base>/ortak_oturum_<OrtakOturumID>/`
  (kişisel `user_<id>` klasörlerinin ortak oturum karşılığı). Oturumlar arası
  fiziksel izolasyon korunur; DDL değişmez — yükleme kaynağı ve seçim durumu
  `MB_OrtakOturum_Dosyalar.MetaJson` içinde taşınır
  (`{"kaynak":"KatilimciYuklemesi","secili":true}`).
- **Yalnızca SEÇİLİ belgeler** sonraki yapay zekâ sorusunun bağlamına girer
  (`ortak_db_secili_belgeler` → `ortak_belge_baglam_sistem_mesaji`; içerik
  `readFileContentToString` ile tekil oturumla aynı ayrıştırıcıdan okunur,
  dosya başına bütçelenir ve Kaynakça talimatı taşır). Seçim paylaşılan
  durumdur: tüm katılımcılar aynı seçimi görür. Yeni yüklenen belge varsayılan
  seçilidir; yükleme odaya `BelgeBildirimi` mesajı bırakır.
- Kaldırma soft delete'tir (`DosyaDurumu='Silindi'`) + yalnızca belge kökleri
  İÇİNDEKİ fiziksel dosya silinir. Katılımcı yüklemeleri de
  "Kendi Dosyalarıma Kaydet" ile kişisel klasöre kopyalanabilir (yükleme kökü
  meşru kaynak köküdür).

### 6.2 Araç seçici ve sohbeti temizleme

- Composer'daki **araç seçici** (`R/helpers_ortak_oturum_arac.R` +
  `R/module_ortak_oturum_arac.R`) Yapılandırma > Analiz Araçları kataloğunu
  (`api_config$tool_mode_config`, tek kaynak) listeler; araç-özel ayarlar
  menü içinde düzenlenir: Proje ve Kaynak Analizi için **Derin Düşünme +
  Detay Seviyesi**, Excel Analizi / Kodlama Desteği için **Derin Düşünme +
  Düşünme Seviyesi** (model çözümü `resolve_runtime_model_for_request`),
  Süreç Yönetimi için **Süreç Akışı** seçimi. Görsel Oluşturma ortak
  odalarda desteklenmez (metin dışı çıktı) ve devre dışı listelenir.
- Araç etkinken **model seçimi kilitlenir** (araç kendi modelini kullanır);
  araç temizlenince oda model seçimi geri gelir. Aktif araç, ayar özeti ve ×
  temizleme düğmesi taşıyan bir **rozetle** gösterilir. Tekil oturumdaki
  belge/araç uyumluluk kontrolü ortak odada UYGULANMAZ (bilinçli karar).
- Araç seçimi **soru mesajının MetaJson'una yazılır**; üretim (doğrudan veya
  kalıcı kuyruk devralması) araç bağlamını HER ZAMAN soru satırından okur.
  Yürütme planı (`oo_arac_uretim_plani`): sql_analysis → pk boru hattı
  (tekil oturumla aynı `pk_analiz_process_request` / `pk_deep_analysis_process`),
  process/app_expert → Langflow worker (`call_langflow_chat`;
  belge bağlamı akışa enjekte edilmez), diğerleri → araç modeliyle normal
  LLM yolu (+ özetleme sistem notu).
- **Langflow sohbet belleği ODA kapsamlıdır**: `session_id` soran katılımcıya
  değil oda + akışa anahtarlanır (`mergen_build_langflow_session_id("oda",
  "oo_<oturum_id>", flow_id)`), böylece aynı odadaki farklı katılımcıların
  devam soruları tek paylaşılan bağlamda sürer; farklı odalar ve farklı
  akışlar birbirinden yalıtıktır.
- **Odaya yazılan araç hataları redakte edilir** (`oo_arac_oda_guvenli_yanit`):
  ham SQL/ODBC/DSN/sürücü tanılaması içeren hata metinleri paylaşılan
  transkripte geçmeden genel Türkçe mesaja indirgenir (ayrıntı sunucu
  günlüğünde kalır); olağan analiz yanıtları değişmeden geçer.
- **BilgeYolaç odalarında araç seçici ve belge bağlam kontrolleri SUNULMAZ**
  (sorular BY köprüsüne gider; araçlar o yolda çalışmaz). Soru metadata'sına
  araç planı yazılmaz ve belge anlık görüntüsü BOŞ sabitlenir
  (`oo_arac_soru_meta_hazirla`); belge paneli dürüst bir notla üretilen
  dosyaları LİSTELEMEYE devam eder (indirme/kopyalama korunur, "Bağlama dahil
  et" seçimi çizilmez).
- **"Sohbeti Temizle"** (çöp kutusu) bağlam sıfırlamadan (sihirli değnek)
  FARKLIDIR: açık onay modalı ister ve odadaki TÜM mesajları KALICI siler
  (`ortak_db_sohbet_temizle`; yalnızca `katilimci_yonet` yetkisi, üretim
  sürerken reddedilir, kuyruk temizlenir, odaya sistem notu yazılır; ortak
  belgeler silinmez).

## 7. Ortak Oturum Oluşturma ve Paylaşım Başlangıcı

"Yeni Ortak Oturum" akışı tür + başlık + paylaşım başlangıç tipi ister.
Varsayılan HER ZAMAN en güvenli seçenektir; mevcut kişisel içerik sessizce
paylaşılamaz:

- `NormalSohbet`: `SadeceBundanSonrası` (varsayılan) /
  `GeçmişKopyasıAktarıldı` / `BoşOrtakOturum`.
- `BilgeYolaç`: `SadeceYeniÇalıştırmalar` (varsayılan) /
  `Salt-OkunurÖzetAktarımı` / `TümGeçmişVeBelgeKopyası`.

Seçim `PaylasimBaslangicTipi` alanına yazılır. Kopya aktarımları kişisel kaydın
SAHİPLİĞİNİ değiştirmez; kopyalanan içerik ortak oturumda ayrı kayıt olur.
(Mevcut sürümde geçmiş-kopyalama seçenekleri kayıt düzeyinde saklanır; içerik
aktarım otomasyonu için bkz. §10 Sınırlamalar.)

## 8. Arşiv, Denetim İzi ve Bakım

### Arşiv ayrımı

- **Kullanıcı arşivi** (`KullaniciGorunumDurumu = KullanıcıArşivledi`): yalnızca
  o kullanıcının listesinden gizler; diğer katılımcılar etkilenmez. "Geri
  Yükle" ile döner.
- **Oda arşivi/kapatma** (`OturumDurumu = Arşivlendi/Kapandı`): herkes için
  geçerlidir ve yalnızca `oturum_kapat` yetkisiyle (Sahip) yapılır; işlem
  içinde rol yeniden doğrulanır.

### Denetim izi (`MB_OrtakOturum_Olaylar`)

Hassas eylemler olay günlüğüne yazılır: `KullanıcıKatıldı`, `KullanıcıAyrıldı`,
`MesajEklendi`, `YanıtBaşladı`, `YanıtTamamlandı`, `BelgeÜretildi`,
`BelgeKopyalandı`, `DavetGönderildi`, `DavetReddedildi`, `RolDeğişti`,
`SahiplikDevredildi`, `OturumArşivlendi`, `OturumKapatıldı`.

### Bakım temizliği (`ortak_db_bakim_temizlik`)

Oturum başına bir kez fırsatçı tetiklenir (ilk kalp atışında) ve operatör
tarafından da çağrılabilir; **yıkıcı değildir**:

- 30 günden eski `Bekliyor` davetler → `SüresiDoldu`.
- 30 günden eski okunmamış bildirimler → `SüresiDoldu` + okundu.
- 7 günden eski kalp atışı satırları silinir (geçici telemetri).
- Fiziksel dosyası kaybolmuş ortak belgeler → `Silindi` işareti.

### Tutanak dışa aktarma

Oda başlığındaki **"Tutanağı İndir"**, mesaj akışını + belge listesini UTF-8
BOM'lu `.txt` olarak indirir (`ortak_tutanak_metni` +
`ortak_tutanak_dosyaya_yaz`). Yetki denetimi sunucu tarafındadır: içerik
erişimi olmayan istek içerik alamaz.

### Yönetici görünürlüğü

`ortak_db_istatistikler()` yalnızca sayaç/oran döner: toplam/aktif oda, toplam
mesaj, yapay zekâ soru sayısı, belge/kopya sayıları, davet kabul oranı ve hatalı
üretim sayısı. (Yönetici paneline pano sekmesi bağlanması için bkz. §10.)

## 9. Veritabanı Kurulumu ve Geri Alma

- Kurulum betiği: [`sql/2026-07-ortak-oturumlar.sql`](sql/2026-07-ortak-oturumlar.sql)
- Geri alma: [`sql/2026-07-ortak-oturumlar-rollback.sql`](sql/2026-07-ortak-oturumlar-rollback.sql)

Operasyon kuralları ([`../RUNBOOK.md`](../RUNBOOK.md) §9B):

1. Betikler UYGULAMA AÇILIŞINDA OTOMATİK ÇALIŞTIRILMAZ; yalnızca DBA/operatör
   SSMS'te, DOĞRULANMIŞ DB yedeği aldıktan sonra uygular.
2. Ana betik idempotenttir; mevcut tabloları/PK'ları DEĞİŞTİRMEZ, veri silmez.
   Aşamalı devreye alma kolonları idempotent `ALTER` ile eklenir:
   `MB_OrtakOturum_AktifUretimler.KismiYanit` (kısmi yanıt yayını) ve
   `MB_OrtakOturumlar.SecilenPersona` (oda personası). Kolon kurulu değilse
   uygulama sessizce güvenli düşer.
3. İş kuralı değerleri Türkçe `N'...'` sabitleridir (CHECK kısıtlarıyla).
4. Rollback yalnızca yeni ortak tabloları FK sırasının tersine düşürür
   (`SecilenPersona`/`KismiYanit` kolonları tabloyla birlikte düşer);
   `MB_Chats`, `MB_Messages`, `MB_Users`, `MB_ClaudeCode_*` tablolarına dokunmaz.
   Disk üzerindeki `ortak_oturumlar/` klasörünü SİLMEZ (ayrı, bilinçli adım).
5. Tablolar kurulmadan uygulama çalışmaya devam eder: DB katmanı tablo yokken
   güvenli boş/NULL döner ve sayfa "tablolar hazır değil" durumu gösterir
   (aşamalı devreye alma).

Tablolar: `MB_OrtakOturumlar`, `MB_OrtakOturum_Katilimcilar`,
`MB_OrtakOturum_Davetler`, `MB_Kullanici_CanliDurum`, `MB_Bildirimler`,
`MB_OrtakOturum_Mesajlar`, `MB_OrtakOturum_YapayZekaKuyrugu`,
`MB_OrtakOturum_AktifUretimler`, `MB_OrtakBilgeYolac_Oturumlar`,
`MB_OrtakBilgeYolac_Calistirmalar`, `MB_OrtakOturum_Dosyalar`,
`MB_OrtakOturum_DosyaKopyalari`, `MB_OrtakOturum_Olaylar`.
Kolon özetleri için [`database-schema.md`](database-schema.md).

## 10. Güvenlik Beklentileri

- Her ortak okuma/yazma sunucu tarafında şu zinciri doğrular: kimlik doğrulanmış
  kullanıcı → katılımcı satırı → katılım durumu (içerik erişimi) → rol yetkisi →
  oturum durumu. UI gizlemesi tek başına güvenlik DEĞİLDİR.
- Doğrudan olay/URL erişimi fail-closed'dur: katılımcı olmayan kullanıcı boş
  sonuç alır; kilit/rol kontrolleri işlem içindedir.
- Kullanıcı ve yapay zekâ kontrollü tüm metinler escape edilir; yapay zekâ
  yanıtı yalnızca `render_safe_markdown_html()` güvenli yolundan render edilir.
- Türkçe metin bütünlüğü merkezi DB yardımcılarıyla korunur: görünür metin
  `normalize_db_visible_value`, Türkçe enum'lar `normalize_db_technical_value`,
  tüm bağlama `normalize_db_params`; okuma sınırında
  `normalize_db_read_visible_value`. `DB_CLIENT_ENCODING=WINDOWS-1254` üretim
  sözleşmesi değişmez.
- DB'ye/loga gizli değer (API anahtarı, token, ortam değişkeni, ham kimlik)
  yazılmaz; e-posta taslağı içerik sızdırmaz.
- Dosya yolları ortak belge kökü içinde doğrulanır; path traversal reddedilir.

## 11. Test Kapsamı

| Test | Kapsam |
|---|---|
| `tests/testthat/test-ortak-oturum-permissions-behavior.R` | Rol matrisi, fail-closed bilinmeyen rol, içerik erişimi, mesaj yönlendirme (yalnızca `YapayZekaSorusu` LLM), canlı durum eşikleri, kullanıcı/oda arşiv görünürlüğü, e-posta taslağı güvenliği. |
| `tests/testthat/test-ortak-oturum-db-behavior.R` | Gerçek SQLite ile: tablo-yok güvenli düşüş, oturum oluşturma + Türkçe gidiş-dönüş, İzleyici/yabancı yazamaz-okuyamaz, davet kabul/red akışı, oda başına tek üretim kilidi, kullanıcı-arşivi kişiselliği, Sahip'e özel oda arşivi, sahiplik devri, ortak belge + kişisel kopya + idempotentlik, kaynak türü liste ayrımı, kalp atışı upsert, bakım temizliği, istatistik/tutanak. |
| `tests/testthat/test-ortak-oturum-sql-contract.R` | SQL betiği: tablolar, idempotent guard'lar, Türkçe `N'...'` değerleri, ana betikte yıkıcı ifade yok, rollback yalnızca yeni tabloları düşürür, betik açılışa bağlı değil. |
| `tests/testthat/test-ortak-oturum-ui-contract.R` | "Odaya Yaz"/"Yapay Zekâya Sor" ayrımı, davet paneli eylem metinleri, XSS escape davranışı, JS seçici güvenliği + kalp atışı sözleşmesi, tema token/açık tema/responsive CSS, manifest+bölge üyeliği, navigasyon sekmeleri, kaynak manifesti bölüm sırası. |
| `tests/testthat/test-ortak-oturum-davet-online-behavior.R` | "Katılımcı Çağır" çevrim içi listeleme regresyonu: canlı durum sınıflandırmasının POSIXct/kesirli-saniye/ISO biçimlerine dayanıklılığı ve saf `ortak_davet_aday_kullanicilar()` süzme kararı (çevrim içi listelenir, çevrim dışı/kendisi/katılmış elenir, Davet Edilenler ve Tüm Kullanıcılar filtreleri). |
| `tests/testthat/test-ortak-oturum-canli-durum-behavior.R` | `ortak_db_canli_durumlar()` DB-saat tazeliği regresyonu (gerçek SQLite): sunucu-tarafı yaş (`julianday`/`DATEDIFF`) ile taze→Çevrimİçi, 3 dk→Boşta, 10 dk→ÇevrimDışı; kullanıcı başına en güncel (en küçük yaş) satır; negatif yaş (saat kayması) taze sayılır; çıktı sözleşmesi (`YasSaniye` sızdırılmaz); boş tablo güvenli boş çerçeve. |
| `tests/testthat/test-ortak-oturum-yz-reactive-context-behavior.R` | Yapay zekâ üretiminin reaktif-bağlam güvenliği regresyonu (çıplak `MockShinySession` + `withReactiveDomain`, testServer maskelemesini atlar): reaktif bağlam DIŞINDA reactiveVal okuma hatası belgelenir, `motor$uret` ertelenmiş (onFlushed benzeri) yolda patlamaz, "başlatılamadı" toast'ı çıkmaz ve `YapayZekaYanıtı` kalıcılaşır. |

Persona kalıcılığı `test-ortak-oturum-db-behavior.R` içinde de kapsanır:
oluşturmada deterministik varsayılan, Sahip günceller, geçersiz persona ve
yetkisiz katılımcı reddedilir.

Testler çevrimdışı ve deterministiktir: gerçek SQL Server, LLM, tarayıcı, SSO
veya ağ gerekmez. Gerçek SQL Server Türkçe yazma davranışı, VM'deki mevcut
encoding preflight kapılarıyla doğrulanmalıdır (RUNBOOK).

## 12. Tamamlanan Takip İşleri ve Kalan Sınırlamalar

### 12.1 Tamamlanan takip işleri (bu değişiklik seti)

1. **Canlı ortak Bilge Yolaç çalıştırması — GERÇEK AJAN AKIŞI.** Ortak BY
   odaları tek kullanıcılı Bilge Yolaç deneyiminin ortak sürümüdür: Proje
   Dizini, model katmanları (Hızlı/Dengeli/Güçlü — kompozerde de genel model
   menüsünün YERİNE çizilir; persona/araç seçicileri BY odasında çizilmez),
   Hazır Senaryolar, Dizin İçeriği, Eklentiler (salt-okunur). "Yapay Zekâya
   Sor" bir BY odasında tek kullanıcılı sayfanın GERÇEK stream-json boru
   hattını (`run_claude_code_streaming`; aynı CLI argüman güvenlik ilkesi,
   çalışma dizini politikası, zaman aşımı, resume ve çıktı ayrıştırması)
   odanın ETKİN çalışma dizininde koşturur
   (`R/module_ortak_oturum_by_calistirma.R` → `motor$by_calistir`). Araç
   kullanımı / kabuk komutu / metin deltaları çalıştırma sırasında ilerleme
   dosyasına yazılır (`oo_by_ilerleme_kayitlari`), başlatan oturum bunları
   `KismiYanit` üzerinden yayınlar ve TÜM katılımcılar terminal-dilli canlı
   ajan yüzeyinde (`oo-kismi-yanit-by`) görür; başlatan katılımcı veya
   katılımcı yöneten roller süren çalıştırmayı **Durdur** ile güvenle
   sonlandırabilir (oda-kapsamlı durdurma bayrak dosyası; sunucu tarafında
   fail-closed yetki doğrulaması; kayıt `Durduruldu` durumuyla düşer).
   Çalıştırma `ortak_db_by_calistirma_kaydet`'e, üretilen dosyalar
   `ortak_db_dosya_kaydet` ile ortak belge deposuna yazılır ve odaya belge
   bildirimi düşer. Model veya proje dizini değişimi CLI devam (resume)
   bağlamını sıfırlar ve odaya görünür sistem notu düşer. CLI bu ortamda
   yoksa sahte başarı ÜRETİLMEZ ve soru normal sohbet LLM'ine SESSİZCE
   DÜŞMEZ: odaya açık "CLI bağlı değil; komut çalıştırılamadı" engelleyici
   mesajı düşer, kilit bırakılır ve komut sohbette yeniden gönderilebilir
   biçimde kalır. Mini oyun bilinçli olarak ortak moda taşınmaz.

   **Çalışma alanı paneli (yeniden tasarım).** Panel, tek kullanıcılı Bilge
   Yolaç ayar kartlarının oda sürümüdür ve VARSAYILAN KAPALI açılır: sohbet
   birincil yüzeydir, panel gövdesi kendi içinde kayar ve yoklama/üretim
   döngüsü yalnızca iç kartları tazelediği için kullanıcının aç/kapa tercihi
   korunur (tercih `sessionStorage`'da saklanır; iskelet yalnızca oda/erişim
   değişince yeniden çizilir). **Proje Dizini** yazma yetkili roller
   (Sahip/Oturum Yöneticisi) için DÜZENLENEBİLİR yol girdisidir: yazılan yol
   merkezi Bilge Yolaç çalışma dizini politikası (`cc_policy_validate_workdir`)
   ARTI oda izolasyon kapısından (`ortak_by_ozel_dizin_dogrula`) geçer —
   uygulamanın yönettiği dosya köklerine (başka odanın çalışma alanı, kişisel
   yükleme kovaları) işaret edilemez. Varsayılan, oda başına paylaşılan
   `ortak_oturumlar/oturum_<id>/calisma_alani/` klasörüdür; "sıfırla" eylemi
   her zaman bu klasöre döndürür. Saf yardımcılar
   `R/helpers_ortak_oturum_by_calisma_alani.R` içindedir.

   **Uygulama geneli yerleşim koruması.** Oda açıkken paylaşılan
   `.content-wrapper` üzerine uygulanan `oo-oda-acik-kok` sınıfı SEKMEYE
   DUYARLI merkez güncelleyiciyle (`window.MergenOrtakOturum.kokGuncelle`)
   yönetilir: kullanıcı başka bir sayfaya geçince sınıf kaldırılır, hub
   sekmesine dönünce yeniden uygulanır. Sınıfın diğer sekmelerde asılı
   kalması, tüm sayfaları 100vh/overflow kilidine sokan uygulama geneli
   yerleşim (daralma/kırpılma) regresyonunun kök nedeniydi.
2. **Yapay zekâ kuyruğu — UYGULANDI.** Kilit doluyken gelen sorular kaybolmaz;
   `MB_OrtakOturum_YapayZekaKuyrugu`'na eklenir (`ortak_db_kuyruk_ekle`).
   Üretim biten oturum kuyruğun başındaki soruyu sıralı devralır
   (`ortak_db_kuyruk_sonraki_al`; ilk giren ilk çıkar). Üretim durumu paneli
   süren üretimi + bekleyen kuyruğu (soran + soru önizlemesi) gösterir. Bayat
   kilit (varsayılan 15 dk) devralınır; oda süresiz kilitlenmez.
3. **Geçmiş kopyalama otomasyonu — UYGULANDI.** "Mevcut geçmişin kopyasını
   aktar" seçilince odaya girmeden önce AÇIK ONAY modalı kişisel söyleşi
   seçtirir; seçilen `MB_Chats`/`MB_Messages` satırları ortak odaya kopyalanır
   (`ortak_db_gecmis_kopyala`; soru→YapayZekaSorusu, yanıt→YapayZekaYanıtı,
   zaman damgaları korunur). KAYNAK kişisel kayıt hiçbir zaman
   değiştirilmez/silinmez; yalnızca okunur.
4. **Yanıt akışı (artımlı yayın) — UYGULANDI.** Süren yanıt token-token akış
   dosyasına yazılır ve ~2 sn'de bir `MB_OrtakOturum_AktifUretimler.KismiYanit`
   kolonuna yansıtılır; tüm katılımcılar yoklamayla canlı ön izlemeyi görür.
   `KismiYanit` kolonu kurulu değilse (eski şema) sessizce düşer ve nihai yanıt
   normal yoldan dağıtılır (aşamalı devreye alma). Kurulum betiği 8b adımı bu
   kolonu idempotent ekler.

### 12.2 Çevrim içi keşif / davet (bu değişiklik seti)

- Kalp atışı artık UYGULAMA GENELİNDEDİR (`www/js/ortak_oturumlar.js`):
  kullanıcı hangi sayfada olursa olsun 30 sn'de bir gönderilir; böylece başka
  sayfalardaki oturum açmış kullanıcılar davet panelinde "çevrim içi" görünür.
- Davet paneli çevrim içi/boşta kullanıcıları listeler; "Mergen İçinden Çağır"
  gerçek uygulama içi davet + `MB_Bildirimler` çağrısı üretir (yalnızca e-posta
  taslağı değildir). Çıkarılan kullanıcı katılımcı listesinden anında düşer
  (`ortak_db_katilimci_listesi(sadece_aktif = TRUE)`).
- Oda düzeyi arşiv "Geri Yükle" artık gerçekten çalışır: Sahip odayı herkes
  için yeniden Aktif yapar (`ortak_db_oturum_durum_guncelle(..., "Aktif")`);
  yetkisiz kullanıcı yalnızca kendi görünümünü geri getirir.
- **Çevrim içi listeleme dayanıklılığı — DÜZELTİLDİ.** Canlı durum
  sınıflandırması artık POSIXct / ISO `T` / kesirli-saniye zaman biçimlerine
  dayanıklıdır; aday süzme saf, test edilebilir `ortak_davet_aday_kullanicilar()`
  yardımcısına taşındı ve panel açılırken canlı durum TAZE okunur. Böylece
  çevrim içi kullanıcılar varken "Çevrim İçi Kullanıcılar" listesinin boş kalması
  regresyonu kapatıldı.

### 12.2b Persona ve UX iyileştirmeleri (bu değişiklik seti)

- **Yapay zekâ personası — UYGULANDI.** Her oda beş MERGEN Bilge personasından
  birini kullanır (§3 "Yapay zekâ personası"); yanıtlar persona adı/avatarıyla
  ve persona sistem talimatıyla üretilir. Sahip/Oturum Yöneticisi composer'daki
  persona menüsünden değiştirir; `MB_OrtakOturumlar.SecilenPersona` kolonunda
  saklanır (aşamalı devreye alma, deterministik varsayılan).
- **UX cilası — UYGULANDI.** Sürüklenebilir yan panel ayracı (daha yüksek
  Katılımcılar paneli), sekme filtre çubuğu, kompakt composer model/persona
  satırı, sakin buton/rozet dili (aşırı turuncu giderildi), profesyonel oturum
  kartları, standart başlık hizası ve Yeni Ortak Oturum modalı radyoları. Yoklama
  sırasındaki genel griye-dönme/donma hissi giderildi; model/persona menüleri
  yoklamada yeniden çizilmez; oda açıkken mesaj akışı içten kayar ve composer
  görünür kalır; yeni mesajlarda otomatik dip kaydırma eklendi
  (§2 "Arayüz / UX sözleşmesi").

### 12.2c Oda içi UX ve performans (bu değişiklik seti)

- **Biriken konsol uyarısı — GİDERİLDİ.** Oda 4 sn'lik yoklaması artık DB verisini
  `reactiveVal` yuvalarına yazar (`fetch_now()`); `reactiveVal` `identical()`
  değeri atandığında invalide etmediği için değişmeyen veri yeniden render
  edilmez ve `Shiny.bindAll` yeniden tetiklenmez (birikip artan "Duplicate input
  IDs" uyarısının kök nedeni buydu). yz üretim durumu paneli sayaç yerine
  `ctx$aktif_uretim()` / `ctx$bekleyenler()` okur. `canli_rv` ham kalp atışı zaman
  damgasını taşımaz; yalnızca durum/oda-görünürlüğü değişince değişir.
- **İyimser gönderim — UYGULANDI.** "Yapay Zekâya Sor" tıklanınca kullanıcı
  balonu ve "… sordu · yanıt üretiliyor…" durumu ANINDA görünür; kilit alma,
  bağlam kurma ve worker gönderimi `session$onFlushed` ile sonraki flush'a
  ertelenir (ölü bekleme süresi giderildi). `iyimser_uretim` bayrağı gerçek
  üretim başlayınca veya 15 sn sonra temizlenir.
- **Model/Persona seçici — UYGULANDI.** Ana Söyleşi "Model Değiştir" bileşeni
  (`shinyWidgets::dropdown`) yeniden kullanılır; saf HTML üreticileri
  `oo_model_secici_html()` / `oo_persona_secici_html()`
  (`R/module_ortak_oturum_room_ui.R`), stiller `css/ortak_oturumlar_room.css`.
  Persona menüsü 5 personayı aksan noktası + ad ile listeler.
- **Avatarlar — UYGULANDI.** Kullanıcı fotoğrafı
  `mb_sidebar_user_avatar_url(GonderenSicil)` (mesaj sorgusu `u.Sicil` seçer),
  yapay zekâ persona görseli `get_character_asset_paths(persona_id)$avatar`;
  görsel yüklenemezse `onerror` ile baş harf yedeğe geçilir.
- **Yeni bağlam düğmesi — UYGULANDI.** "Odaya Yaz" yanındaki ikon düğme
  (`oda_baglam_temizle`) `ortak_baglam_sifirlama_notu()` metniyle bir
  `SistemMesajı` işareti ekler; `ortak_yz_sohbet_gecmisi()` yalnızca en son
  işaretten sonraki soru/yanıtları LLM bağlamına alır. Transkript korunur, tüm
  katılımcılar sistem notunu görür.
- **CSS bölünmesi — UYGULANDI.** Oda odaklı stiller `css/ortak_oturumlar_room.css`
  dosyasına ayrıldı (frontend tek dosya satır bütçesi korunur); manifest + bölge
  kaydı `R/config_ui_assets.R` ve `R/config_ui_asset_zones.R` içindedir.

### 12.2d İki üretim hatası düzeltmesi (bu değişiklik seti)

- **Yapay zekâ yanıtı başlatılamadı — GİDERİLDİ (reaktif bağlam).** Ertelenmiş
  `motor$uret` (`session$onFlushed`) ve kuyruk zinciri (`promises::then`
  callback'i) reaktif ALAN içinde ama reaktif BAĞLAM DIŞINDA koşar; `etkin_model()`
  orada `secili_model` `reactiveVal`'ını doğrudan okuduğu için HER soru
  *"Yapay zekâ yanıtı başlatılamadı; lütfen tekrar deneyin."* hatasıyla düşüyordu.
  Okuma `shiny::isolate(...)` ile sarıldı (§3 "Reaktif bağlam güvenliği").
  `shiny::testServer` bu hatayı maskelediği için regresyon testi çıplak
  `MockShinySession` + `withReactiveDomain` kullanır
  (`tests/testthat/test-ortak-oturum-yz-reactive-context-behavior.R`).
- **Çevrim içi kullanıcılar listelenmiyor — GİDERİLDİ (DB-saat tazeliği).**
  Tazelik artık R'nin `Sys.time()`'ı ile ODBC'nin `DATETIME2`'yi POSIXct'e çevirme
  yorumu karşılaştırılarak değil, veritabanının KENDİ saatiyle (`DATEDIFF` /
  SQLite `julianday`) hesaplanır; R yalnızca yaşı `ortak_sunum_durumu` eşikleriyle
  sınıflandırır (§5 "Canlı durum"). Böylece istemci tarafı ODBC saat dilimi/an
  dönüşümü — davet panelinin "Çevrim İçi Kullanıcılar" sekmesinin boş kalmasının
  kök nedeni — tamamen devre dışı bırakılır. Yazma yolu da aynı DB saatini
  kullanır (`ortak_db_kalp_atisi` → `SYSUTCDATETIME()` / SQLite `datetime('now')`),
  böylece R↔DB saat kayması her iki yönde de (DB ileri/geri) taze kalp atışını
  etkilemez (PR #590 kod incelemesi geri bildirimi). Negatif yaş güvenlik ağı
  olarak taze sayılır; yaş sorgusu başarısız olursa eski yola güvenli düşülür.
  Regresyon: `tests/testthat/test-ortak-oturum-canli-durum-behavior.R`.

### 12.2d Ortak Bilge Yolaç ajan yenilemesi + oda UI düzeltmeleri (bu değişiklik seti)

- **Gerçek kodlama-ajanı yürütmesi — UYGULANDI.** BY köprüsü blok
  `run_claude_code()` çağrısından tek kullanıcılı sayfanın stream-json boru
  hattına (`run_claude_code_streaming`) geçirildi; ayrıntı §12.1 madde 1.
  Yeni odak dosyalar: `R/module_ortak_oturum_by_calistirma.R` (çalıştırma
  köprüsü + KismiYanit ilerleme yayıncısı + Durdur) ve
  `R/helpers_ortak_oturum_by_akis.R` (yan dosyalar + ilerleme kayıtları/metni;
  SAF). `run_claude_code_streaming` isteğe bağlı `stop_file` (durdurma bayrak
  dosyası; yalnızca GERÇEK dosya durdurur) ve `api_key` (çalışma anında alt
  süreç ortamına enjekte; `cc_apply_runtime_api_key_env`) parametreleri kazandı.
- **Sessiz LLM düşüşü kaldırıldı.** BY odasında köprü/CLI yoksa soru ARTIK
  normal sohbet LLM'ine gitmez; `ortak_by_kopru_kullanilamiyor_mesaji()` ile
  açık engelleyici sistem mesajı düşer ve kilit bırakılır. Kompozerde BY odası
  için genel model menüsü yerine model katmanları (Hızlı/Dengeli/Güçlü;
  `motor$by_model_secici_ui`) çizilir; persona ve araç seçicileri BY odasında
  çizilmez. Model/dizin değişimi `ClaudeCliSessionID`'yi sıfırlar (resume
  yeniden kapsamlanır) ve odaya sistem notu düşer. Proje dizini doğrulaması
  http/https web adreslerini açık mesajla reddeder; Dizin İçeriği "okunamadı"
  ile "henüz boş" durumlarını ayrı mesajlarla gösterir.
- **Kompozer seçicileri YUKARI açılır.** Model/Persona/Araç menüleri
  (`shinyWidgets::dropdown ... up = TRUE` → `sw-dropup-content`) kompozerden
  yukarı açılır; panel içi kaydırma sınırı (`max-height: min(56vh, 460px)`)
  yakınlaştırılmış/dar görünümlerde menüyü ekran içinde tutar
  (`css/ortak_oturumlar_room.css`).
- **Ortak Belgeler yükleme yüzeyi + boş durum — YENİDEN TASARLANDI.** Kompakt
  sürükle-bırak hedefi ("Belgeleri buraya sürükleyin veya **Belge Seç**",
  tür/boyut ipucu, erişilebilir etiketler; `oo_belge_yukleme_alani_html`).
  Bırakılan dosyalar `www/js/ortak_oturumlar.js` delege köprüsüyle gizli
  fileInput'a atanır ve MEVCUT doğrulanmış sunucu yolundan
  (`ortak_db_belge_yukle`) geçer. Boş durum panel alanını doldurur, metin
  kırpılmaz ve belge yokken kaydırma çubuğu üretmez. Ortak Çalışmalarım liste
  kartları `uiOutput` sarmalayıcısına taşınan ızgara kurallarıyla birbirine
  değmez (`.oo-oturum-listesi > .shiny-html-output`).
- Regresyon: `tests/testthat/test-ortak-oturum-by-calistirma-behavior.R`,
  `tests/testthat/test-ortak-oturum-secici-yon-contract.R`,
  `tests/testthat/test-ortak-oturum-belge-panel-ui-contract.R`.

### 12.2.1 Ortak Söyleşi/BY paritesi ve iki hata düzeltmesi (bu değişiklik seti)

Bu tur, ortak odaları tekil oturum deneyimine yaklaştırdı ve iki üretim
hatasını kökten giderdi. Değişiklikler mümkün olan her yerde kanıtlanmış
tekil oturum bileşenlerini yeniden kullanır (yeni paralel davranış üretmez).

- **"Kendi Dosyalarıma Kaydet" her zaman "Belge kopyalanırken hata oluştu"
  veriyordu — DÜZELTİLDİ.** Kök neden: `global_register_file`, MCP tabanı
  altındaki bir kaynağı "zaten depoda" sayıp KOPYALAMADAN indeksliyor;
  katılımcı yüklemeleri MCP tabanındaki ortak oda klasöründe durduğu için
  kişisel "kopya" aslında ortak dosyanın TAKMA ADI oluyordu (ortak belge
  silininde kişisel kayıt kırılıyordu) ve kopya-durumu satırının yazılamaması
  gerçek bir kopyadan sonra bile tüm işlemi "hata" gösteriyordu.
  `ortak_dosya_kisisel_kopyala()` artık (1) `mergen_user_upload_dir(user_id)`
  altına AÇIK fiziksel kopya yapar (görünen ad korunur), (2) o kopyayı
  indeksler (ikinci kopya YOK — zaten kullanıcı kovasında), (3) kopya-durumu
  satırını BEST-EFFORT sayar (tablo/yazım yoksa kopya yine BAŞARILI raporlanır).
  `ortak_oturum_dosya_koku()`/`ortak_oturum_yukleme_koku()` kökleri Windows/UNC
  güvenli oluşturur/doğrular ve ulaşılamayan `MERGEN_FILES_ROOT` durumunda MCP
  tabanına düşer. Gerçek dosya deposu zinciriyle test:
  `tests/testthat/test-ortak-oturum-kisisel-kopya-behavior.R`.
- **"Yükleme Klasörümü Çalışma Alanına Kopyala" her zaman "Çalışma alanı
  oluşturulamadı. 0 dosya…" veriyordu — DÜZELTİLDİ.**
  `R/helpers_ortak_oturum_ws_kopyalama.R` aşamalı çözüm
  (`oo_ws_hedef_cozumle` → `ozel`/`paylasilan`/`kok_yapilandirma` ve hangi
  aşamanın başarısız olduğunu söyleyen Türkçe mesaj), güvenli özyinelemeli
  kopya (`oo_ws_kopyalama_calistir`; doğru kopyalanan/atlanan/başarısız
  sayaçları, yarım kopya bırakmaz, kök-içi doğrulaması) ve TEK doğru bildirim
  (`oo_ws_kopyalama_bildirimi`) sağlar. Başarı/başarısızlıktan bağımsız Dizin
  İçeriği tazelenir; çift bildirim yoktur. Test:
  `tests/testthat/test-ortak-oturum-ws-kopyalama-behavior.R`.
- **Ortak Söyleşi araç paritesi.** (a) **Dosya Özetleme** artık tekil oturumla
  aynı ayar uzayını taşır: **Detay** (Kısa Özet/Standart/Detaylı) + **Odak**
  (Genel/Sayısal Veri/Karar & Öneri/Karşılaştırma); `oo_arac_ozetleme_sistem_notu`
  `build_summarization_system_prompt`'u gerçek belge sayısıyla kullanır.
  (b) **Excel Analizi** artık tekil oturumun GERÇEK MCP araç yürütmesini koşar
  (`oo_arac_mcp_uret` → `call_llm_worker` + `mcp_registry_snapshot`): dosya
  analizi, kolon istatistiği, SQL ve grafik üretimi; grafikler yanıt metnine
  gömülü ```chartlab blokları olarak döner ve her katılımcının oturumunda
  `oo_yanit_icerik_html` ile render edilir. (c) **Görsel Oluşturma** ortak
  odalarda bilinçli olarak DEVRE DIŞI kalır: `oo_arac_devre_disi_nedeni("image")`
  ile açık Türkçe gerekçe (tüm katılımcılara güvenli görsel dağıtımı henüz
  sağlanmadı; Ana Söyleşi'yi kullanın) seçici ipucunda gösterilir.
  Bu üretim yolu yardımcıları araç seçici saf karar katmanından
  `R/helpers_ortak_oturum_arac_uretim.R` dosyasına ayrıldı (fonksiyon bütçesi).
- **Araç ayarları erişilebilirliği.** Araç-özel ayarlar artık açılır menünün
  İÇİNDE saklı DEĞİLDİR: `oo_arac_ayar_paneli_html` bunları aktif araç rozetinin
  yanında HER ZAMAN erişilebilir bir panelde çizer (araç seçilince ayarlar
  görünür kalır).
- **Ortak Belgeler ön izleme.** `ortak_belge_onizleme_icerigi()` +
  `belge_onizle` gözlemcisi (`R/module_ortak_oturum_belge_paneli.R`) belgeyi
  indirmeden modalda gösterir (görseller oturum-kapsamlı URL, metin kaçışlı
  `<pre>`); içerik erişimli her katılımcı ön izleyebilir, kaynak kök-içi
  doğrulanır.
- **Kod bloğu render'ı.** Ortak oda yapay zekâ yanıtları artık tekil oturum boru
  hattından geçer (`R/helpers_ortak_oturum_yanit_icerik.R` → `process_message_content`
  ile `.code-container`, dil algılama, kopyalama, CodeMirror; çift kaçış YOK).
  Ekran görüntüsündeki `&lt;iostream&gt;` regresyonu giderildi.
- **Katılımcı-güvenli otomatik kaydırma.** `www/js/ortak_oturumlar.js` akışı
  yalnızca yerel kullanıcı zaten dipteyse en alta kaydırır; geçmiş okuyan
  katılımcı çekilmez. Yerel kullanıcının kendi "Odaya Yaz"/"Yapay Zekâya Sor"
  tıklaması dibe sabitler (yalnızca tıklayan tarayıcıda).
- **Ortak Bilge Yolaç canlı deneyimi + persona.** Uyarlanır yoklama (aktif
  üretimde 1,5 sn), başlatan oturumda DB tur gecikmesiz yerel ön izleme
  (`motor$canli_onizleme`, istek-id kapsamlı), 1 sn'lik ilerleme yayını,
  sunucu-tohumlu geçen-süre sayacı (`ortak_sunum_gecen_saniye` + JS ileri
  sayım) ve BY odalarında da PERSONA seçimi (ajan yanıtı persona talimatıyla
  üretilir) eklendi. Üretilen dosyalar `ortak_by_uretilen_dosya_filtrele` ile
  geçici/yarım dosyalardan arındırılıp ortak belge olarak kaydedilir.
- Regresyon: `tests/testthat/test-ortak-oturum-kisisel-kopya-behavior.R`,
  `tests/testthat/test-ortak-oturum-ws-kopyalama-behavior.R`,
  `tests/testthat/test-ortak-oturum-yanit-icerik-behavior.R`,
  `tests/testthat/test-ortak-oturum-arac-behavior.R`,
  `tests/testthat/test-ortak-oturum-by-calistirma-behavior.R`,
  `tests/testthat/test-ortak-oturum-ui-contract.R`.

### 12.3 Kalan sınırlamalar

1. **Yönetici panosu:** `ortak_db_istatistikler()` hazır; Yönetici Paneli'ne
   pano sekmesi bağlanması takip işidir (module_admin_bilge_yolac deseni).
2. **Gerçek e-posta gönderimi:** SMTP altyapısı olmadığı için yalnızca güvenli
   taslak (mailto) yolu vardır; kurumsal SMTP eklenirse gönderim durumu
   `MB_OrtakOturum_Davetler` üzerinde izlenmelidir.
3. **Token-token gerçek WebSocket yayını:** Ortak odada canlı ön izleme DB
   üzerinden 2 sn'lik yoklamayla dağıtılır (artımlı yayın); istemciye
   doğrudan token-token WebSocket push takip işidir. Bağlantı koparsa
   katılımcılar nihai durumu yoklama/DB üzerinden kurtarır.
4. **Canlı VM doğrulaması:** SQL Server üzerinde Türkçe değerlerin at-rest
   doğrulaması (SSMS), `KismiYanit` ve `SecilenPersona` ALTER'larının
   uygulanması, çok kullanıcılı gerçek oda denemesinde persona/çevrim içi
   davet/donma-giderme akışları, SSO'lu çok kullanıcılı gerçek oda denemesi ve
   gerçek Claude Code CLI köprüsü Windows VM kapısında yapılmalıdır; bulut
   testleri SQLite/parse ile davranış kanıtıdır.
