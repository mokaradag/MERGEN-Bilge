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
| Savunma birimleri | 5 kahraman (sahada tek) + 3 inşa edilebilir KULE (Gözcü/Topçu/Kripto; sınırsız kopya, 3 kademe, satılır) |
| Kampanya | 6 harita (Bağlam Kapısı → Çelişki Kavşağı → Bilgi Çekirdeği → Veri Labirenti → Sinyal Vadisi → Karar Zirvesi), doğrusal kilit zinciri |
| Render | Canvas 2D, 2.5D derinlik (varlıklar ızgara Y'sine göre sıralanır, gövdeler tabandan yukarı uzanır, gölge/derinlik ölçeği). Three.js/framework YOK |
| Tam ekran | Üst çubukta genişletme düğmesi (`hud-tamekran`); Fullscreen API + boyut değişiminde tuval yeniden ölçeklenir |
| Müzik | Oyun KENDİ müzik setini çalar (menü + seviye grupları, gruptan rastgele parça); MERGEN arka fon müziği VE boşta konuşma oyun sayfasında TAM susturulur (`MusicManager.duck("oyun")` → owner tam sessizlik) |

## 2. Mimari

### 2.1 R katmanı (manifest bölümü: `bilge_savunmasi`, seam: `bilge_yolac`)

| Dosya | Sorumluluk |
| --- | --- |
| `R/config_bilge_savunmasi.R` | Özellik bayrağı, sürüm/boyut sabitleri, persona oyun manifesti (`bs_persona_manifest`), 6 haritalık katalog + zorluk, deterministik haftalık meydan okuma (`bs_haftalik_meydan_okuma`), oyun müzik kataloğu (`bs_muzik_gruplari`/`bs_muzik_katalogu` — grup klasörlerini tarar, UTF-8 URL üretir), başarım kataloğu. Saf; Shiny/DB yok. |
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
2. `bilge_savunmasi_denge.js` — TÜM sayısal denge: kahramanlar (maliyet/menzil/hasar/yükseltme/yetenek), **KULELER** (`kuleler`/`kuleAl`/`kuleIstatistik`/`kuleYatirim`; Gözcü/Topçu/Kripto, 3 kademe), 12 tehdit + 4 patron, ekonomi, zorluk ve haftalık değiştirici çarpanları.
3. `bilge_savunmasi_haritalar.js` — 6 harita: ızgara, rota ara noktaları, tema renkleri, `muzikGrubu` (bolum_1/bolum_2), dalga kompozisyon planları. `siraliListe()` tek kaynaktan türetilir.
4. `bilge_savunmasi_dalga.js` — deterministik doğuş programı; patron kuralı (`dalga %% 4 == 0` veya son dalga) R ile birebir aynı.
5. `bilge_savunmasi_sim_kuleler.js` — KULE simülasyon uzantısı: yerleştirme/yükseltme/satış, en ileri hedefe kilitlenme, alan hasarı + zırh delme çözümü, kule seri durumu. Saf (Math.random YOK); `sim`e `bagla()` ile eklenir.
6. `bilge_savunmasi_sim.js` — çizimden bağımsız saf simülasyon: hareket/hedefleme/hasar/yavaşlatma/işaret/kalkan/onarım/ekonomi/yetenekler + kule tik'i, olay kaydı, kule dahil kontrol noktası serileştirme, `ozetPaketi()`.
7. `bilge_savunmasi_varliklar.js` — 2.5D görsel varlık yükleyici: yerel SVG kule/dekor/düşman sprite'ları (yoksa prosedürel yedek), kule gövde çizimi, dekor yerleşimi. Dış URL yok.
8. `bilge_savunmasi_cizim_zemin.js` — statik zemin ressamı (offscreen bir kez): degrade, nebula, altıgen plaka, tanecik, yıldız, devre izleri, rotalar/portallar, inşa-edilemez doku, vinyet.
9. `bilge_savunmasi_cizim.js` — Canvas 2D dinamik katman: dekor + tehditler + KULELER + kahramanlar derinlik (ızgara Y) sırasıyla çizilir; portre diskli kahramanlar; kule sprite/prosedürel; menzil çemberleri; kalite seviyeleri.
10. `bilge_savunmasi_efekt.js` — havuzlanmış parçacıklar, yüzen metin, sınırlı sarsıntı; alan vuruşu efekti; azaltılmış harekette kapalı.
11. `bilge_savunmasi_girdi.js` — fare/dokunmatik/klavye (1-5 kahraman, 6-8 KULE, Q, Boşluk, F, Esc); kule seçim/yerleşim; `coz()` tüm dinleyicileri söker.
12. `bilge_savunmasi_hud.js` — üst çubuk (hız/duraklat/**tam ekran**/çık), kahraman + KULE inşa kartları, yan panel (kahraman/kule yükseltme-satış + dalga önizleme), kaplamalar.
13. `bilge_savunmasi_ses.js` — grup tabanlı oyun müziği (menü + seviye grupları; gruptan rastgele parça, ardışık tekrar azaltma, bayat parça koruması) + isteğe bağlı efektler + MERGEN müziği owner tam-sessiz köprüsü.
14. `bilge_savunmasi_sahne.js` — sahne destek katmanı: tam ekran yönetimi (Fullscreen API + boyut dinleme), menü/seviye müzik orkestrasyonu, öğretici metinleri, plan rehber paneli, kule olay bağlayıcıları (idempotent).
15. `bilge_savunmasi_kopru.js` — Shiny köprüsü: `bs-*` mesajları <-> `BS.olaylar`; boyut sınırlı JSON gönderimi, istemci jetonu üretimi.
16. `bilge_savunmasi_menu.js` — menü panelleri (6 harita kampanya dahil), zengin liderlik satırı, Öncü Uzman seçim ekranı, ayar uygulama.
17. `bilge_savunmasi_sonuc.js` — zafer/yenilgi paneli, plan yayınlama akışı, kalıcılıksız modda görsel amaçlı yerel puan aynası.
18. `bilge_savunmasi_uygulama.js` — orkestratör: tembel başlatma, koşu akışı, RAF döngüsü, kule/tam ekran olay yönlendirmesi (sahne katmanına delege), sekme/görünürlük duraklatması + müzik sürdürme, kaynak temizliği.

CSS: `www/css/bilge_savunmasi.css` (koyu varsayılan + `html[data-theme="light"]`
incelmeleri; kule kartları/panel; `:fullscreen` stili; oyun görünümü kalan
dikey alanı `flex`/`:has()` ile doldurur — alt boşluk bırakılmaz).

**Render kararının gerekçesi:** Oyun 2B ızgara + az sayıda hareketli varlık
çizer; Canvas 2D bu iş için en basit, VDI-dostu ve bakımı en ucuz çözümdür.
2.5D derinlik, gerçek 3B motor yerine ucuz numaralarla verilir: varlıklar
ızgara Y'sine göre sıralanıp alttaki üstte çizilir (doğal örtme), gövdeler
hücre tabanından yukarı uzanır, zemin gölgesi ve hafif derinlik ölçeği eklenir.
Three.js/GPU beklentisi bu oyuna değer katmaz. DPR 2 ile sınırlanır, statik
arka plan (zemin ressamı) bir kez çizilir, parçacıklar havuzlu ve kalite
seviyesine göre sınırlıdır (yüksek 220 / dengeli 120 / performans 40).

### 2.3 Çalışma Alanı retro karşılaması (oyun DEĞİL)

`www/js/bilge_yolac_karsilama.js` + `www/css/bilge_yolac_welcome.css`:
Çalışma Alanı karşılamasında CLI-esintili esprili terminal kutusu (daktilo
ipucu satırı) ve zenginleştirilmiş `claude_code_pixel_chars.js` verisiyle
çizilen 8-bit persona sahnesi vardır (yürüme/koşma/düşünme/selamlama/zıplama/
uyuma; tıklayınca persona değişir). Sahne dekoratiftir: Shiny girdisi göndermez,
ses çalmaz, yalnızca karşılama görünürken çalışır ve mesaj gelince/sekme
değişince durur; azaltılmış hareket tercihinde tek karedir. Bilge Savunması
yalnızca kendi sekmesinden açılır; karşılama ekranında oyun geçiş düğmesi yoktur.

**Persona piksel sprite seti (paylaşımlı):** `claude_code_pixel_chars.js` beş
kanonik personayı (emre/selin/deniz/can/ipek) BEŞER kareyle
(idle/nefes/düşünme A/düşünme B/selamlama) ve GENİŞLETİLMİŞ paletle taşır
(1-3 kıyafet, 4-5 deri, 6 saç, 7 detay, 8 aksesuar); her persona saç/kıyafet/
aksesuarla görsel olarak ayırt edilir ve renkler kanonik aksan renkleriyle
hizalıdır. Ortak çizici `www/js/pixel_sprite_render.js` (`window.MergenPixelSprite`)
açık/koyu temaya DUYARLI kontur uygular (açık temada koyu, koyu temada açık) ve
eski color/darkColor/lightColor verisiyle geriye uyumludur. HEM Bilge Yolaç
düşünme animasyonu (`claude_code.js`) HEM karşılama sahnesi bu ortak çiziciyi
kullanır; yükleme sırası persona verisi → `pixel_sprite_render.js` → tüketiciler.

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
- **Kuleler (Kingdom Rush esintili; sınırsız kopya, 3 kademe, satılır):**
  - **Gözcü Kulesi:** hızlı tekil atış; kalabalık zayıf tehditlere ideal.
  - **Veri Topçusu:** yavaş ama ALAN hasarlı gülle; sürülere karşı etkili.
  - **Kripto Işını:** ZIRH DELİCI enerji ışını; zırhlı/kalkanlı tehditleri erir.
  Kuleler en ileri hedefe kilitlenir (klasik kule savunma); kahramanlarla
  birlikte kurulur. Kule eklenmesiyle savunma gücü arttığı için tehdit
  dayanıklılığı yeniden dengelendi (can çarpanı Normal 1.18 / Gelişmiş 1.7)
  ve elit tehditler eklendi (Veri Solucanı, Gölge İstek, Veri Hortumu).
- **Öncü Uzman:** her koşu premium seçim ekranıyla başlar; seçilen personanın
  İLK konuşlandırması ücretsizdir ve yetenek beklemesi %20 kısadır.
- **Ekonomi:** satış %70 iade (kahraman ayrıca bir kademe düşer); dalga bonusu,
  erken başlatma bonusu, İpek üretimi.
- **Yıldız:** zafer 1; kalan çekirdek >= %60 iki; >= %90 üç.
- **Kampanya (6 harita, doğrusal kilit):** Bağlam Kapısı (8 dalga, tek rota,
  öğretici) → Çelişki Kavşağı (10, çift rota) → Bilgi Çekirdeği (12, elit) →
  Veri Labirenti (12, uzun kıvrımlı tek rota) → Sinyal Vadisi (14, çift vadi,
  4 patron) → Karar Zirvesi (16, üç rota, final). Sonraki harita önceki
  tamamlanınca, Gelişmiş zorluk o haritanın Normal bitişiyle açılır (sunucu da
  doğrular). Her harita bir müzik grubuna bağlıdır (1-3 → bolum_1, 4-6 →
  bolum_2). Kısayollar: 1-5 kahraman seç, 6-8 kule seç, Q yetenek, Boşluk
  duraklat, F hız (1x/2x), Esc iptal/menü; üst çubuk genişletme düğmesi tam
  ekran.

**Oyun müziği:** Bilge Savunması kendi müzik setini çalar; MERGEN uygulama arka
fon müziği VE boşta AI konuşması oyun sayfasında TAM susturulur (`oyun` sahibi,
`audio_lifecycle_guard.js`'de tam sessizlik; `bilge_savunmasi` boşta-sessiz
sayfalar kümesinde). Klasörler: `www/assets/bilge_savunmasi/muzik/menu`
(menü teması), `.../bolum_1`, `.../bolum_2` (seviye grupları). Her klasöre
birden çok parça konabilir; istemci gruptan rastgele parça seçer, parça bitince
aynı gruptan yenisine geçer. Otomatik yüksek sesli çalma yoktur (ilk kullanıcı
etkileşiminden sonra başlar). Dosya yoksa oyun sessiz ve tam işlevlidir.

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
- Türetilmiş/iyileştirilmiş oyun görselleri, müzik veya isteğe bağlı ses
  dosyaları için ayrılmış klasör: `www/assets/bilge_savunmasi/` (ayrıntı:
  klasördeki `README.md`).
  - `gorseller/kuleler/<tip>_<kademe>.svg` — kule silüetleri (repoda özgün
    SVG'ler var; `gozetleme`/`veri_topu`/`kripto_isik`, kademe 1-3).
  - `gorseller/dekor/<ad>.svg` — sahne süsleri (kristal/anten/sunucu/kaya/
    veri_agaci/bayrak); inşa edilemez hücrelerde dekoratif.
  - `gorseller/dusmanlar/<id>.svg` — İSTEĞE BAĞLI düşman sprite'ları; yoksa
    prosedürel gövde çizilir. Her görsel eksikse zarif prosedürel yedeğe düşülür.
  - `muzik/menu`, `muzik/bolum_1`, `muzik/bolum_2` — oyun müzik grupları
    (`.mp3`/`.ogg`/`.m4a`; birden çok parça → rastgele çalma). Operatör bu
    klasörlere kendi lisanslı/CC0 müziğini koyar.
  - `heroes/` — isteğe bağlı optimize kahraman görselleri.
  - `ses/` — isteğe bağlı efektler (`efekt_vurus.mp3`, `efekt_dalga.mp3`,
    `efekt_yetenek.mp3`, `efekt_yerlestir.mp3`, `efekt_yukselt.mp3`,
    `efekt_patron.mp3`, `efekt_sizinti.mp3`, `efekt_zafer.mp3`,
    `efekt_yenilgi.mp3`); eski tekil `muzik_dongu.mp3` yalnızca müzik grupları
    boşken geriye uyum için çalınır.
  Tüm varlıklar isteğe bağlıdır; yoksa oyun sessiz/prosedürel yedekle tam
  işlevlidir. CDN/dış indirme yasaktır; SVG'ler MERGEN Bilge için özgündür.

## 9. Test ve Doğrulama

Odaklı testler (tümü çevrimdışı/deterministik):

```r
testthat::test_file("tests/testthat/test-bilge-savunmasi-config-behavior.R")     # + müzik kataloğu, 6 harita
testthat::test_file("tests/testthat/test-bilge-savunmasi-validation-behavior.R")
testthat::test_file("tests/testthat/test-bilge-savunmasi-db-behavior.R")         # RSQLite
testthat::test_file("tests/testthat/test-bilge-savunmasi-lifecycle-contract.R")
testthat::test_file("tests/testthat/test-bilge-savunmasi-kule-muzik-contract.R") # kule/müzik/tam ekran/2.5D
testthat::test_file("tests/testthat/test-persona-sprite-contract.R")             # sprite paleti + tema-duyarlı çizici
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
