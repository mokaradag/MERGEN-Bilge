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
  ana söyleşi "Model Değiştir" dili). Oda dikeyde alt boşluk bırakmadan yayılır.
- **Yan panel**: Katılımcılar paneli varsayılan olarak daha yüksektir; Katılımcılar
  ile Ortak Belgeler arasında **sürüklenebilir ayraç** vardır (yükseklik oturum
  boyunca `sessionStorage`'da korunur; klavye ok tuşlarıyla da ayarlanabilir).
- **Mesaj balonları** ana söyleşiyle uyumlu: aralarında yeterli dikey boşluk,
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
- Sınıflandırma saf yardımcıdadır (`ortak_sunum_durumu`): son kalp atışı
  ≤120 sn → `Çevrimİçi`; ≤300 sn → `Boşta`; aksi → `ÇevrimDışı`.
- Zaman damgası biçimine dayanıklıdır: POSIXct, ISO `T` ayraçlı veya kesirli
  saniyeli (`DATETIME2(7)`) metin — hangi biçim gelirse gelsin güvenli UTC an'a
  çözülür. Böylece bir sürücü/biçim farkı çevrim içi kullanıcıyı sessizce
  `ÇevrimDışı` göstermez (davet panelinde çevrim içi listenin boş kalmasının
  önceki kök nedeni; regresyon:
  `tests/testthat/test-ortak-oturum-davet-online-behavior.R`).
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

Persona kalıcılığı `test-ortak-oturum-db-behavior.R` içinde de kapsanır:
oluşturmada deterministik varsayılan, Sahip günceller, geçersiz persona ve
yetkisiz katılımcı reddedilir.

Testler çevrimdışı ve deterministiktir: gerçek SQL Server, LLM, tarayıcı, SSO
veya ağ gerekmez. Gerçek SQL Server Türkçe yazma davranışı, VM'deki mevcut
encoding preflight kapılarıyla doğrulanmalıdır (RUNBOOK).

## 12. Tamamlanan Takip İşleri ve Kalan Sınırlamalar

### 12.1 Tamamlanan takip işleri (bu değişiklik seti)

1. **Canlı ortak Bilge Yolaç çalıştırması — BAĞLANDI.** Ortak BY odaları artık
   tek kullanıcılı Bilge Yolaç deneyiminin ortak sürümüdür: Proje Dizini
   (oda başına PAYLAŞILAN çalışma alanı, `ortak_oturumlar/oturum_<id>/calisma_alani/`),
   model katmanları (Hızlı/Dengeli/Güçlü), Hazır Senaryolar, Dizin İçeriği,
   Eklentiler (salt-okunur). "Yapay Zekâya Sor" bir BY odasında
   `run_claude_code()`'u PAYLAŞILAN çalışma alanında koşturur
   (`R/module_ortak_oturum_bilge_yolac.R` → `motor$by_calistir`); çalıştırma
   `ortak_db_by_calistirma_kaydet`'e, üretilen dosyalar
   `ortak_db_dosya_kaydet` ile ortak belge deposuna yazılır ve odaya belge
   bildirimi düşer. CLI bu ortamda yoksa sahte başarı ÜRETİLMEZ: durum "CLI
   Bağlı Değil" gösterilir ve soru genel LLM yoluna güvenli düşer. Mini oyun
   bilinçli olarak ortak moda taşınmaz.
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
  yoklamada yeniden çizilmez; yeni mesajlarda otomatik dip kaydırma eklendi
  (§2 "Arayüz / UX sözleşmesi").

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
