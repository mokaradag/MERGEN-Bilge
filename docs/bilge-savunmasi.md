# Bilge Savunması — Kule Savunma Oyunu Tasarım ve Operasyon Rehberi

Bilge Savunması, MERGEN Bilge içinde **Bilge Yolaç > Bilge Savunması** sekmesinde
yaşayan adanmış kule savunma oyunudur. Eski Bilge Yolaç karşılama mini oyununun
yerini alır: Çalışma Alanı karşılaması artık dekoratif retro 8-bit sahnedir,
oyunun tamamı kendi sayfasındadır. Bu belge mimariyi, oynanışı, kalıcılığı,
eşzamansız çok oyunculu modeli, anti-hile sınırlarını ve operasyon akışını
tek yerde toplar.

## 1. Hızlı Özet

| Konu | Karar |
| --- | --- |
| Sayfa | `Bilge Yolaç > Bilge Savunması` (`tabName = "bilge_savunmasi"`) |
| Özellik bayrağı | `MERGEN_BILGE_SAVUNMASI_ENABLED` (varsayılan açık; kapalı değerler: `false/0/off/hayır/kapalı`) |
| Kalıcılık | `MB_Game_*` ailesi (10 tablo); tablolar yoksa oyun kalıcılıksız serbest modda çalışır, uygulama ÇÖKMEZ |
| Kurulum | `docs/sql/2026-07-bilge-savunmasi.sql` — MANUEL, idempotent, DBA uygular |
| Geri alma | `docs/sql/2026-07-bilge-savunmasi-rollback.sql` — YIKICI, yalnızca yedek + bayrak kapatma sonrası |
| Persona kimliği | TEK kaynak `R/config_characters.R`; oyun yalnızca rol/yetenek META'sı ekler |
| Nihai puan | Her zaman SUNUCU hesaplar (`bs_kosu_ozeti_dogrula`); istemci beyanı sınırlarla kırpılır |
| Çok oyunculu | EŞZAMANSIZ: haftalık meydan okuma, savunma planları, topluluk operasyonu. Gerçek zamanlı ağ/PvP YOK |
| Render | Canvas 2D (katmanlı; offscreen statik arka plan + dinamik katman). Three.js/framework YOK |
| Müzik | Oyun sayfası açıkken MERGEN arka fon müziği owner tabanlı kısılır (`MusicManager.duck("oyun")`) |

## 2. Mimari

### 2.1 R katmanı (manifest bölümü: `bilge_savunmasi`, seam: `bilge_yolac`)

| Dosya | Sorumluluk |
| --- | --- |
| `R/config_bilge_savunmasi.R` | Özellik bayrağı, sürüm/boyut sabitleri, persona oyun manifesti (`bs_persona_manifest`), harita/zorluk katalogları, deterministik haftalık meydan okuma (`bs_haftalik_meydan_okuma`), başarım kataloğu. Saf; Shiny/DB yok. |
| `R/helpers_bilge_savunmasi_validation.R` | SAF doğrulama/puanlama: `bs_kosu_ozeti_dogrula`, `bs_puan_yeniden_hesapla`, `bs_yildiz_hesapla`, `bs_plan_dogrula`, `bs_kontrol_noktasi_dogrula`, `bs_liderlik_sirala`, `bs_yuk_coz` (boyut sınırlı JSON). |
| `R/helpers_db_bilge_savunmasi_cekirdek.R` | `.bs_db_*` bağlantı/`try`/lehçe altyapısı, tablo erişilebilirlik önbelleği, profil (oluştur/paket yükle/ayar). |
| `R/helpers_db_bilge_savunmasi_kosu.R` | Koşu yaşam döngüsü: jetonla idempotent `bs_db_start_run`, kontrol noktaları, TEK transaction'da idempotent `bs_db_finalize_run` (koşu + kampanya + kahraman + profil + başarımlar), `bs_db_abandon_run`. |
| `R/helpers_db_bilge_savunmasi_topluluk.R` | Eşzamansız çok oyunculu DB: sezonlar, liderlik (ad/rumuz/departman ile), plan yayınla/oku/yumuşak sil, topluluk katkıları. |
| `R/module_bilge_savunmasi_ui.R` | Saf sayfa iskeleti: menü kartları, canvas/HUD bağlama noktaları. Bayrak kapalıyken sakin bilgi kartı. |
| `R/module_bilge_savunmasi.R` | Sunucu modülü: `page_opened` -> `bs-init`; koşu başlat/bitir/bırak, kontrol noktası, liderlik/plan/topluluk/ayar işleyicileri. |

Kablolar: `ui.R` (menü alt öğesi bayrak korumalı + `tabItem`),
`R/server_module_wiring.R` (`bilge_savunmasi_server_fn`, bayrak korumalı),
`R/server_observers_navigation.R` (`bilge_savunmasi_module-page_opened`).

### 2.2 JS katmanı (varlık grubu: `bilge_savunmasi`, bölge: `bilge_yolac_oyun`)

Yükleme sırası bağımlılık sırasıdır (bkz. `ui_asset_js_order_rules`):

1. `bilge_savunmasi_cekirdek.js` — isim alanı (`window.BilgeSavunmasi`), mulberry32 tohumlu RNG, olay yayıncısı, kalite/erişilebilirlik durumu, `htmlKacis`.
2. `bilge_savunmasi_denge.js` — TÜM sayısal denge: kahramanlar (maliyet/menzil/hasar/yükseltme/yetenek), 10 tehdit + 3 patron, ekonomi, zorluk ve haftalık değiştirici çarpanları.
3. `bilge_savunmasi_haritalar.js` — 3 harita: ızgara, rota ara noktaları, tema renkleri, dalga kompozisyon planları.
4. `bilge_savunmasi_dalga.js` — deterministik doğuş programı; patron kuralı (`dalga %% 4 == 0` veya son dalga) R ile birebir aynı.
5. `bilge_savunmasi_sim.js` — çizimden bağımsız saf simülasyon: hareket/hedefleme/hasar/yavaşlatma/işaret/kalkan/onarım/ekonomi/yetenekler, olay kaydı, kontrol noktası serileştirme, `ozetPaketi()`.
6. `bilge_savunmasi_cizim.js` — Canvas 2D: offscreen statik arka plan, portre diskli kahramanlar (yüz oranı korunur; yüklenemezse aksan renkli baş harf), kalite seviyeleri (yüksek/dengeli/performans).
7. `bilge_savunmasi_efekt.js` — havuzlanmış parçacıklar, yüzen metin, sınırlı sarsıntı; azaltılmış harekette kapalı.
8. `bilge_savunmasi_girdi.js` — fare/dokunmatik/klavye (1-5, Q, Boşluk, F, Esc); `coz()` tüm dinleyicileri söker.
9. `bilge_savunmasi_hud.js` — üst çubuk, kahraman kartları, yan panel (yükseltme/satış + dalga önizleme), kaplamalar (geri sayım/duraklat/onay/öğretici).
10. `bilge_savunmasi_ses.js` — İSTEĞE BAĞLI yerel sesler (`assets/bilge_savunmasi/ses/*`; yoksa sessiz no-op) + MERGEN müziği owner duck köprüsü.
11. `bilge_savunmasi_kopru.js` — Shiny köprüsü: `bs-*` mesajları <-> `BS.olaylar`; boyut sınırlı JSON gönderimi, istemci jetonu üretimi.
12. `bilge_savunmasi_menu.js` — menü panelleri (kampanya/haftalık/planlar/topluluk/kahramanlar/ilerleme/ayarlar/yardım), zengin liderlik satırı, Öncü Uzman seçim ekranı, ayar uygulama.
13. `bilge_savunmasi_sonuc.js` — zafer/yenilgi paneli, plan yayınlama akışı, kalıcılıksız modda görsel amaçlı yerel puan aynası.
14. `bilge_savunmasi_uygulama.js` — orkestratör: tembel başlatma, koşu akışı, RAF döngüsü (sabit adım sim + gerçek zaman fx), sekme/görünürlük duraklatması, kaynak temizliği.

CSS: `www/css/bilge_savunmasi.css` (koyu varsayılan + `html[data-theme="light"]`
incelmeleri; oyun tuvali/seçim kaplaması bilinçli koyu kalır).

**Render kararının gerekçesi:** Oyun 2B ızgara + az sayıda hareketli varlık
çizer; Canvas 2D bu iş için en basit, VDI-dostu ve bakımı en ucuz çözümdür.
Three.js sahne kurulumтого maliyeti ve GPU beklentisi bu oyuna değer katmaz;
harici oyun framework'ü CDN'siz/çevrimdışı sözleşmeyi zorlaştırırdı.
DPR 2 ile sınırlanır, statik arka plan bir kez çizilir, parçacıklar havuzlu ve
kalite seviyesine göre sınırlıdır (yüksek 220 / dengeli 120 / performans 40).

### 2.3 Çalışma Alanı retro karşılaması (oyun DEĞİL)

`www/js/bilge_yolac_karsilama.js` + `www/css/bilge_yolac_welcome.css`:
Çalışma Alanı karşılamasında CLI-esintili esprili terminal kutusu (daktilo
ipucu satırı + `[OYNA] Bilge Savunması'nı Aç` retro düğmesi) ve mevcut
`claude_code_pixel_chars.js` verisiyle çizilen 8-bit persona sahnesi vardır
(yürüme/koşma/düşünme/selamlama/zıplama/uyuma animasyon kataloğu; tıklayınca
persona değişir). Sahne dekoratiftir: Shiny girdisi göndermez, ses çalmaz,
yalnızca karşılama görünürken çalışır ve mesaj gelince/sekme değişince durur;
azaltılmış hareket tercihinde tek karedir.

## 3. Oynanış

- **Amaç:** Rotalardan akan bilgi/karar tehditleri (Gürültü, Yanlış Bağlam,
  Çelişki, Belirsizlik, Doğrulanmamış Varsayım, Bilgi Aşırı Yükü, Bozuk Veri,
  Yönlendirme Saldırısı, Sahte Kesinlik, Dağınık İstek) Bilgi Çekirdeği'ne
  ulaşmadan etkisizleştirilir. Sızıntı çekirdeği düşürür (patron 3, normal 1).
- **Döngü:** dalga önizle -> savunucu yerleştir -> dalgayı (erken bonusla)
  başlat -> kaynak kazan -> yükselt/geri çek/yetenek kullan -> patron dalgası
  -> sonuç + yıldız + kalıcı ilerleme.
- **Kahramanlar (her biri sahada TEK):**
  - **Emre — Komuta:** dengeli hasar; yakın savunuculara atış hızı aurası;
    `Çözüm Dalgası` (alan hasarı + hız desteği).
  - **Selin — Onarım:** çekirdeğe periyodik onarım (dalga başına toplam +3
    SINIRI sunucu toleransıyla birebir); K3'te gizli tehditleri görür;
    `Sinyal Taraması` (anında onarım + gizli açığa çıkarma).
  - **Deniz — Kontrol:** yavaşlatan atışlar (K3'te küçük alan yavaşı);
    `Rota Projesi` (geniş bölgesel yavaşlatma).
  - **Can — Doğrulama:** zırh delme, en güçlü hedefe kilitlenme, işaretleme
    (işaretliye herkes +%25, Can kritik vurur); `Doğrulama Işını` (tek hedefe
    yüksek hasar, patrona ek çarpan).
  - **İpek — Destek:** yakınlara menzil bonusu, periyodik kaynak; K3'te
    çekirdek kalkanı; `Rehber Halkası` (çekirdek kalkanı + anlık kaynak).
- **Öncü Uzman:** her koşu premium seçim ekranıyla başlar; seçilen personanın
  İLK konuşlandırması ücretsizdir ve yetenek beklemesi %20 kısadır.
- **Ekonomi:** satış %70 iade + bir kademe düşer (yeniden konumlandırma
  bedeli); dalga bonusu, erken başlatma bonusu, İpek üretimi.
- **Yıldız:** zafer 1; kalan çekirdek >= %60 iki; >= %90 üç.
- **Kampanya:** Bağlam Kapısı (8 dalga, tek rota, öğretici) -> Çelişki
  Kavşağı (10 dalga, çift rota) -> Bilgi Çekirdeği (12 dalga, elit + Kaos
  Çekirdeği). Sonraki harita önceki tamamlanınca, Gelişmiş zorluk o haritanın
  Normal bitişiyle açılır (sunucu da doğrular). Kısayollar: 1-5 seç, Q
  yetenek, Boşluk duraklat, F hız (1x/2x), Esc iptal/menü.

Determinizm: dalga programları tohumdan üretilir; savaş çözümünde rastgelelik
yoktur (kritik = işaret mekaniği). `Math.random` yalnızca dekoratif katmanda.

## 4. Kalıcılık ve Veri Modeli

Tablolar (ayrıntı: `docs/database-schema.md` ve DDL): `MB_Game_Profiles`,
`MB_Game_CampaignProgress`, `MB_Game_HeroProgress`, `MB_Game_Runs`
(UserID+ClientToken UNIQUE), `MB_Game_RunCheckpoints` (RunID+Wave UNIQUE),
`MB_Game_Achievements` (basarim/acilim), `MB_Game_ChallengeSeasons`
(WeekCode UNIQUE), `MB_Game_ChallengeEntries` (Sezon+User UNIQUE),
`MB_Game_Blueprints`, `MB_Game_CommunityContributions` (RunID UNIQUE).

İlkeler: yalnızca parametreli SQL + merkezi `normalize_db_*` yardımcıları;
tüm okuma/yazma `UserID` izoleli; durum/mod değerleri Türkçe (`Aktif`,
`Tamamlandı`, `Yenilgi`, `Bırakıldı`, `Reddedildi` / `kampanya`, `haftalik`,
`plan`); JSON kolonları uygulama tarafında boyut sınırlı; gizli değer ve
ikili içerik ASLA yazılmaz. Kontrol noktaları patron dalgalarında ve her 3
dalgada bir alınır; sayfaya dönüşte "Devam Et" akışı son noktadan başlatır.

## 5. Anti-Hile / Sunucu Otoritesi

- Koşu kimliği SUNUCU verir; `ClientToken` yeniden denemeleri idempotent
  yapar (düşen mesaj ödül çoğaltamaz; sonuçlanmış koşu saklanan paketi döner).
- `bs_kosu_ozeti_dogrula` şunları zorlar: şema/oyun sürümü; harita-zorluk-tohum
  eşleşmesi; dalga sırası tekdüzeliği; dalga başına düşman üst sınırı;
  çekirdek aralığı ve dalga başına +3 onarım toleransı; zafer koşulu; süre
  makullüğü (dalga başına >= 6 sn) VE sunucu saatiyle uyum (+90 sn tolerans);
  kanonik kahraman kimlikleri.
- Puan istemciden alınmaz: dalga puanları `bs_dalga_puan_siniri` ile kırpılır,
  çekirdek/zafer bonusu ve zorluk çarpanı sunucuda eklenir; XP koşu başına
  400 ile sınırlıdır. Geçersiz özet koşuyu `Reddedildi` yapar ve HİÇBİR
  ilerleme yazmaz.
- Plan yükleri katı şemadan geçer (yalnızca bilinen alanlar, kanonik kimlik,
  koordinat/seviye/adet sınırları, kontrol karakteri temizliği); yayın sonrası
  değişmez; eski şema sürümü zarifçe reddedilir.

## 6. Eşzamansız Çok Oyunculu

- **Haftalık Meydan Okuma:** `bs_haftalik_meydan_okuma()` Europe/Istanbul ISO
  haftasından deterministik hafta kodu + tohum + harita rotasyonu + değiştirici
  üretir; herkes aynı bileşimi oynar. Sıralama şeffaftır ve UI'da yazılıdır:
  puan > kalan çekirdek > dalga > süre > erken gönderim. Liderlik satırı
  zengin gösterir: ad (`KaynakAdi`), rumuz (`KullaniciAdi`), departman —
  e-posta/sicil istemciye TAŞINMAZ. Giriş, koşu bazında idempotenttir; yalnızca
  daha iyi sonuç mevcut girişi değiştirir.
- **Savunma Planları:** sonuçlanmış koşudan yayınlanır (koşunun gerçek
  harita/tohum/zorluk üçlüsü doğrulanır); başka oyuncu "Aynı Koşulda Dene"
  ile aynı tohumla oynar; koşu sırasında Plan Rehberi paneli yaratıcının
  dalga-işaretli yerleşim zaman çizelgesini gösterir (hayalet karşılaştırma),
  sonuç ekranı puan farkını söyler. Sahibi yumuşak siler.
- **Topluluk Operasyonu:** sonuçlanan HER koşu haftalık ortak hedefe
  (etkisizleştirilen tehdit; koşu başına 600 ile sınırlı) bir kez katkı yazar;
  panel toplamları ve kişisel katkıyı gösterir. Canlı ko-op DEĞİLDİR.

## 7. Operasyon: Devreye Alma / Geri Alma

Aşamalı devreye alma (RUNBOOK 9C ile aynı):

1. Uygulama kodunu dağıt; istenirse `.Renviron`'a
   `MERGEN_BILGE_SAVUNMASI_ENABLED=FALSE` yazıp sayfayı gizle.
2. DB YEDEĞİ al; `docs/sql/2026-07-bilge-savunmasi.sql`'i SSMS'te çalıştır
   (idempotent; betiğin sonundaki doğrulama SELECT'i 10 satır göstermeli).
3. Bayrağı aç (`TRUE` yap veya satırı sil) ve R sürecini yeniden başlat.
4. Smoke: sayfayı aç ("İlerleme kaydediliyor" rozeti), kısa bir koşu bitir,
   SSMS'te `MB_Game_Runs`/`MB_Game_Profiles` satırlarını ve Türkçe alanları
   doğrula; ikinci kullanıcıyla izolasyonu doğrula.
5. Geri alma: önce bayrağı kapat + yeniden başlat (veri durur, sayfa gizlenir);
   veri de silinecekse YEDEK sonrası rollback betiğini çalıştır.

Tablolar kurulmadan bayrak açık kalırsa oyun "Kalıcılık kapalı" rozetiyle
serbest modda çalışır; liderlik/plan/ilerleme panelleri açıklayıcı not
gösterir. Bu desteklenen bir ara durumdur.

## 8. Varlık Hazırlığı (persona görselleri ve ses)

- Oyun, kahraman görsellerini KANONİK persona varlıklarından okur:
  `www/characters/resim/<id>/portrait.png` (beş sağlanan portre) ve yedek
  olarak `characters/avatar/<id>/avatar.png`. Bu ikililer bulut checkout'ta
  bilinçli olarak yoktur (on-prem VM çalışma kopyasındadır); görsel
  yüklenemezse oyun aksan renkli baş harf diskine düşer, oran bozulmaz,
  orijinal dosyalar üzerine YAZILMAZ.
- Türetilmiş/iyileştirilmiş oyun görselleri veya isteğe bağlı ses dosyaları
  için ayrılmış klasör: `www/assets/bilge_savunmasi/` (`heroes/`, `ses/`).
  Ses dosyaları (`muzik_dongu.mp3`, `efekt_vurus.mp3`, `efekt_dalga.mp3`,
  `efekt_yetenek.mp3`, `efekt_yerlestir.mp3`, `efekt_yukselt.mp3`,
  `efekt_patron.mp3`, `efekt_sizinti.mp3`, `efekt_zafer.mp3`,
  `efekt_yenilgi.mp3`) tamamen isteğe bağlıdır; yoksa oyun sessiz ve tam
  işlevlidir. CDN/dış indirme yasaktır.

## 9. Test ve Doğrulama

Odaklı testler (tümü çevrimdışı/deterministik):

```r
testthat::test_file("tests/testthat/test-bilge-savunmasi-config-behavior.R")
testthat::test_file("tests/testthat/test-bilge-savunmasi-validation-behavior.R")
testthat::test_file("tests/testthat/test-bilge-savunmasi-db-behavior.R")      # RSQLite
testthat::test_file("tests/testthat/test-bilge-savunmasi-lifecycle-contract.R")
```

Kablolama değişikliklerinde ek olarak: `test-source-manifest-sections-contract.R`,
`test-seam-registry-contract.R`, `test-ui-asset-manifest-contract.R`,
`test-ui-asset-zones-contract.R`, `test-character-personas-contract.R`,
`test-frontend-maintainability-ratchet.R`, `test-maintainability-ratchet.R`.

VM'de manuel doğrulama listesi: ilk açılış + öğretici; kampanya zaferi ve
yıldızlar; sekmeden ayrılıp dönünce duraklatma/devam; yenile sonrası "Devam
Et"; haftalık gönderim + liderlikte ad/rumuz/departman; plan yayınla/dene/sil;
topluluk ilerlemesi; klavye + dokunmatik; azaltılmış hareket; ses kapalıyken
tam deneyim; açık/koyu tema; performans kalitesi; tablolar yokken serbest mod;
görsel eksikken baş harf yedeği; iki kullanıcı veri izolasyonu; oyun sayfası
açıkken MERGEN müziğinin kısılıp sayfadan çıkınca normale dönmesi.

## 10. Sorun Giderme

| Belirti | Muhtemel neden / çözüm |
| --- | --- |
| Menüde "Bilge Savunması" yok | Bayrak kapalı (`MERGEN_BILGE_SAVUNMASI_ENABLED`); R sürecini yeniden başlat. |
| "Kalıcılık kapalı" rozeti | `MB_Game_*` tabloları yok/erişilemiyor; 9C kurulumunu uygula; loglarda `Bilge Savunması tabloları` uyarısını ara. |
| Sonuç "Sonuç Doğrulanamadı" | `MB_Game_Runs.RejectReason` alanına bak (ör. `sure_sunucu_uyumu`, `kosu_eslesmesi`); istemci saati/sürüm uyumsuzluğu olabilir. |
| Liderlikte "Oyuncu #id" | `MB_Users` adı boş veya sorgu erişilemedi; maske bilinçli güvenli düşüştür. |
| Kahraman görseli baş harf | Portre dosyası checkout'ta yok (bulutta normal) veya yüklenemedi; VM'de `www/characters/resim/<id>/portrait.png` varlığını doğrula. |
| Müzik oyun sayfasında kısılmıyor | `MusicManager` yüklü mü; `bilge_savunmasi_ses.js` duck köprüsü owner `"oyun"` ile çağrılır. |
