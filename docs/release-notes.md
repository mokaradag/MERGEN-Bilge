# MERGEN Bilge Değişiklik Notları

Bu belge, MERGEN Bilge değişiklik notları, doğrulama caveat'leri, özellik güncellemeleri ve operasyonel bakım notları için merkezi başvuru kaynağıdır. README ilk giriş ve yön bulma belgesi olarak kısa tutulur; ayrıntılı teknik ve operasyonel notlar burada veya ilgili derin dokümanlarda korunur.

## Genel Bakış

MERGEN Bilge değişiklik notları; yapay zekâ söyleşi deneyimi, dosya yönetimi, görsel anlama, güvenlik/SSO, Türkçe karakter dayanıklılığı, UI tema cilaları, ses akışları, Bilge Yolaç/Claude Code alanı, test/doğrulama ve bağımlılık kilitleme başlıklarını birlikte izler.

- Operasyonel ayrıntılar için [`../RUNBOOK.md`](../RUNBOOK.md).
- Mimari yön bulma için [`architecture-map.md`](architecture-map.md).
- DB tablo yapısı için [`database-schema.md`](database-schema.md).
- Bağımlılık kilitleme için [`dependency-locking.md`](dependency-locking.md) ve [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md).
- Geniş teknik referans için [`technical-reference.md`](technical-reference.md).

## Son Değişiklikler

### (Yayınlanmadı) 2026-07-25 Dosya yükleme artık arayüzü dondurmuyor (bloklamayan alım hattı)

- **Sorun.** Hem Dosya Yönetimi toplu yüklemesi hem de Ana Söyleşi yüklemesi;
  dosya doğrulama, tam dosya hash'i, kalıcı klasöre kopyalama, boyut doğrulaması
  ve dosya başına kalıcı indeks yazımını **Shiny olay döngüsünde senkron**
  yapıyordu (Dosya Yönetimi ayrıca tüm döngüyü ilerleme çubuğuyla sarıyordu).
  Çok dosyalı bir parti, yükleyen kullanıcının oturumunu ve aynı R sürecini
  paylaşan **diğer kullanıcıların oturumlarını** geçici olarak yanıtsız
  bırakabiliyordu. Etki, yavaş disk / UNC ağ paylaşımı ve 25 MB sınırına yakın
  PDF/Excel dosyalarında daha belirgindi. Ayrıca aynı dosya iki kez
  indeksleniyordu (gereksiz kilit + tam indeks yazımı).

- **Çözüm.** Her iki yükleme girişi de ortak, sınırlı eşzamanlılıklı bir arka
  plan alım hattını kullanıyor. Observer artık yalnızca ucuz planı yapıp
  **hemen dönüyor**; doğrulama/hash/kopyalama/bütünlük denetimi arka planda
  çalışıyor. Bir parti tek arka plan görevidir ve kendi dosyalarını sırayla
  işler; dosya başına sınırsız işçi açılmaz. Varsayılan olarak aynı anda en
  fazla 2 parti çalışır, kuyruk 32 parti ile sınırlıdır ve worker havuzu
  doluysa yükleme sohbet/akış/ses görevlerini aç bırakmaz.

- **Kullanıcı deneyimi.** Yükleme sırasında "N dosya arka planda işleniyor…"
  bildirimi görünür ve arayüz kullanılabilir kalır. Tablo satırları, model
  bağlamı ve özetleme işi dosyalar gerçekten kalıcılaştıktan sonra üretilir.
  Bir dosyanın hatası partiyi düşürmez; başarısız dosya kendi hatasını
  raporlar, yarım kalan kopya silinir ve diğer dosyalar normal şekilde
  tamamlanır. Kuyruk dolarsa dosya sessizce düşmez, kullanıcı açık uyarı alır.

- **Veri güvenliği.** Kayıt tam olarak bir kez yapılır ve kalıcı indeks yazımı
  parti başına tek işleme indirgenmiştir. Oturum kapanırsa dosya yine
  indekslenir (kullanıcı bir sonraki girişte görür) ama arayüz mutasyonu
  yapılmaz; "Tümünü Temizle" ile açıkça iptal edilen partinin kopyaları
  silinir ve indekse yazılmaz. Kullanıcı izolasyonu, Türkçe dosya adları,
  uzantı beyaz listesi ve 25 MB dosya-başı sınırı değişmedi.

- **Yeni operasyonel ayarlar (opsiyonel).** `MERGEN_FILE_INGESTION_MAX_CONCURRENT`
  (varsayılan `2`), `MERGEN_FILE_INGESTION_MAX_QUEUE` (varsayılan `32`),
  `MERGEN_FILE_INGESTION_METRICS` (varsayılan kapalı; dosya adı/yol içermeyen
  tek satırlık alım metrikleri).

- **Doğrulama.** Çevrimdışı davranış/sözleşme testleri eklendi
  (`test-file-ingestion-pipeline-behavior.R`, `test-file-ingestion-contract.R`)
  ve mevcut yükleme testleri yeni asenkron sözleşmeye güncellendi; operasyonel
  soak etkileşimli seridine `interactive_file_ingestion` kontrolü eklendi.
  Bakım skoru 100/100 ve küresel dosya bütçeleri değişmedi.
  **Windows VM'de doğrulanacak:** gerçek UNC kopyalama gecikmesi, Türkçe/kısa
  yol davranışı, çok kullanıcılı SSO eşzamanlılığı ve büyük parti sırasında
  ikinci tarayıcı oturumunun gerçek yanıt süresi.


### (Yayınlanmadı) 2026-07-18 Bilge Savunması: adanmış kule savunma oyunu ve eski mini oyunun emekliliği

- **Yeni sayfa: Bilge Yolaç > Bilge Savunması.** Beş kanonik MERGEN Bilge
  uzmanı (Emre/Selin/Deniz/Can/İpek) belirgin rollerle oynanabilir savunmacı
  oldu; her koşu premium "Öncü Uzman" seçim ekranıyla başlar (ilk
  konuşlandırma ücretsiz + yetenek %20 hızlı). Üç haritalık kampanya (Bağlam
  Kapısı 8, Çelişki Kavşağı 10, Bilgi Çekirdeği 12 dalga), patron dalgaları,
  3 kademeli yükseltme, hız/duraklat/erken başlatma, kalite seviyeleri
  (Yüksek/Dengeli/Performans), azaltılmış hareket ve klavye/dokunmatik desteği.
- **Sunucu-otoriter ilerleme.** Koşu kimliği sunucudan, istemci jetonuyla
  idempotent; nihai puan/yıldız/XP `bs_kosu_ozeti_dogrula()` ile sunucuda
  yeniden hesaplanır (dalga puan sınırları, süre makullüğü, çekirdek/onarım
  toleransı, sürüm ve kanonik kahraman kontrolleri). Geçersiz özet
  `Reddedildi` olur ve hiçbir ödül yazmaz.
- **Yeni `MB_Game_*` ailesi (10 tablo).** Kurulum manuel ve idempotenttir:
  `docs/sql/2026-07-bilge-savunmasi.sql` (+ yıkıcı rollback betiği; RUNBOOK
  9C). Tablolar yokken oyun kalıcılıksız serbest modda çalışır; uygulama
  çökmez. Özellik bayrağı: `MERGEN_BILGE_SAVUNMASI_ENABLED` (varsayılan açık).
- **Eşzamansız çok oyunculu.** Haftalık meydan okuma (Europe/Istanbul ISO
  haftasından deterministik tohum/harita/değiştirici), şeffaf eşitlik
  bozucularla zengin liderlik (ad + rumuz + departman; e-posta/sicil asla),
  yayın sonrası değişmez savunma planları ("Aynı Koşulda Dene" + hayalet
  kıyas) ve haftalık topluluk operasyonu. Gerçek zamanlı ağ/PvP bilinçli
  olarak YOK.
- **Eski Bilge Yolaç karşılama mini oyunu tamamen kaldırıldı** (13
  `bilge_yolac_*.js` dosyası). Çalışma Alanı karşılaması artık dekoratif
  retro 8-bit sahne: mevcut piksel persona verisiyle animasyon kataloğu
  (yürü/koş/düşün/selamla/zıpla/uyu; tıklayınca persona değişir) + Claude
  Code CLI esintili esprili daktilo ipuçları + `[OYNA]` geçiş satırı. Sahne
  oyun değildir: girdi yakalamaz, ses çalmaz, mesaj gelince durur.
- **Ses/müzik uyumu.** Oyun sayfası açıkken MERGEN arka fon müziği owner
  tabanlı kısılır (`MusicManager.duck("oyun")`), sayfadan çıkınca bırakılır.
  Oyunun kendi sesleri isteğe bağlı yerel dosyalardır; yoksa sessiz ve tam
  işlevlidir.
- **Doğrulama.** 4 yeni odaklı test dosyası (config/doğrulama/SQLite DB/yaşam
  döngüsü; ~760 iddia) + manifest/seam/bölge/persona/frontend-ratchet
  sözleşmeleri bilinçli güncellendi; parse sanity (993 dosya) ve Shiny boot
  smoke bulutta geçti. SQL Server Türkçe at-rest doğrulaması ve gerçek çok
  kullanıcılı SSO liderlik akışı VM kapılarında kanıtlanır. Ayrıntı:
  [`bilge-savunmasi.md`](bilge-savunmasi.md).


### (Yayınlanmadı) 2026-07-17 Hibrit VoxCPM2 konuşma mimarisi: kilitli persona sesleri + önceden üretilmiş karşılama/rehberlik

- **Karşılama ve sayfa rehberliği artık önceden üretilmiş persona WAV'larıyla
  anında başlıyor.** Gezinme anında LLM çağrısı kaldırıldı; 150 ortak Türkçe
  metin (10 karşılama + 14 rehberli sayfa x 10 çeşit) oturum kapsamlı karışık
  torbayla (tekrar önlemeli) seçilir ve altyazı metni her zaman ortak `.txt`
  dosyasından okunur. Ana Söyleşi, Kişiselleştirme, yönetici sayfaları ve
  Sistem Durumu bilinçli olarak rehberliksizdir.
- **Her personanın sesi kalıcı olarak kilitlendi.** `voices/<persona>/`
  altındaki onaylı `reference.wav` + `reference.txt` + `voice-lock.json`
  üçlüsü; toplu üretim, kişisel karşılama öneki, boşta konuşma ve "Yanıtları
  Seslendir" dahil TÜM sentez isteklerinde aynı konuşmacıyı garanti eder.
  Kilit yoksa/bozuksa konuşma fail-closed reddedilir; eski kayıtlı ses etiketi benzeri
  genel takma adlara veya başka personaya asla düşülmez.
- **Deterministik kişisel karşılama öneki**: "Merhaba <ad>, en son ... üzerine
  çalışmıştık." metni LLM'siz kurulur, persona onaylandığı anda sentezlenmeye
  başlar ve `VOXCPM2_PREFIX_DEADLINE_MS` içinde hazır değilse atılır — statik
  karşılamayı hiçbir koşulda geciktirmez; önek+karşılama tek konuşma yaşam
  döngüsüdür (tek müzik kısma aralığı, kesintisiz altyazı).
- **Tek konuşma yaşam döngüsü ve öncelik matrisi**: yanıt seslendirme >
  karşılama > sayfa rehberliği > boşta konuşma. Sunucu token'ları tekdüze
  artar; bayat rehberlik/önek/parça yeni konuşmaya karışamaz
  (`window.MergenSpeech`). Görselleştirici ve müzik kısma artık gerçek
  `playing` olayında başlar.
- **RStudio üretici aracı** (`tools/speech/generate_voxcpm2_assets.R`):
  aday referans üret → dinle → onayla/kilitle → 150/750 WAV üret →
  `speech_manifest.json` otomatik üret. Atomik yazım, kesinti sonrası devam,
  sınırlı yeniden deneme, eşzamanlılık kilidi ve gizli değer redaksiyonu
  içerir. Üretilen varlıklar VM-yereldir ve GitHub'a gönderilmez. Operatör
  rehberi: [`speech-operator-runbook.md`](speech-operator-runbook.md).
- **Gerçek akış altyapısı (opsiyonel)**: `VOXCPM2_STREAMING_MODE=chunked_pcm`
  ham PCM'i Web Audio kuyruğuna parça parça akıtır (tam sentez bitmeden ses
  başlar; tamamlanma kuyruk boşalmasıyla belirlenir). Varsayılan `buffered`
  modu dürüstçe "gerçek akış değil" olarak belgelenir; VM doğrulaması
  yapılmadan chunked_pcm açılmamalıdır.
- VM-tarafı kanıt gerektirir: gerçek VoxCPM2 referans klonlama alan adları,
  üretilen ses kalitesi/persona ayrıklığı ve uçtan uca karşılama/rehberlik
  oynatması Windows VM'de doğrulanır.


### (Yayınlanmadı) 2026-07-16 Langflow metin içi "Kaynak:" bölümü + `<sup>(n)</sup>` atıfları tıklanabilir oldu

- **Metin içine yazılan belge kaynakları artık tıklanabilir.** Bazı Süreç
  Yönetimi / Uygulama Uzmanı akışları kaynakları yapısal JSON alanında değil,
  yanıt METNİNİN sonuna düz bir "Kaynak:" listesi olarak yazıyordu; bu liste
  düz metin kalıyor, önizleme açılmıyordu. Yeni
  `R/helpers_langflow_inline_sources.R` katmanı (`mergen_langflow_finalize_answer`,
  `mergen_langflow_parse_prose_sources`) sondaki "Kaynak(lar/ça):" bölümünü ve
  `(1) ...` / `1) ...` / `1. ...` girişlerini ayrıştırıp mevcut imzalı Kaynakça
  işaretleyicisine yükseltir. Böylece render, güvenlik ve kalıcılık davranışı
  yapısal kaynaklarla birebir aynıdır (kayıtlı sohbet yeniden yüklemesi dahil).
  URL/mutlak yol/sürücü/`..` gezinme ve belge uzantısı taşımayan girişler
  reddedilir (kaynak uydurulmaz).
- **`<sup>(1)</sup>` üstsimge atıfları düzgün gösteriliyor ve kaynağa kayıyor.**
  Markdown ham HTML'i kaçırdığından `<sup>(1)</sup>` düz metin olarak görünüyordu.
  Atıflar artık erken `[n]` biçimine çevrilir; `citation_handler.js` bunları
  tıklanabilir `.citation-ref` üstsimge rozetine dönüştürür ve tıklandığında
  aynı mesajdaki ilgili Kaynakça girişine yumuşak kaydırıp kısa süre vurgular.
  Kaynak listesi 1..n sırasıyla numaralanmadıysa atıflar pozisyona yeniden
  eşlenir (atıf/kaynak hizası korunur).
- **`A&&B&&dosya.pdf` düz adları kırıntı yolu olarak okunur.** Bu belgelerin
  gerçek disk adları `&&` ayraçlı düz (dizin olmayan) adlardır. Kaynakça'da
  yalnızca son parça (görünen dosya adı) tıklanabilir olur; önceki kategori
  parçaları `" - "` ile birleşip soluk `.kaynakca-breadcrumb` kırıntı yolu olarak
  gösterilir. `&&` içermeyen (yapısal) yollarda mevcut davranış korunur.
- **Alt klasör çözümlemesi.** `data-filename` tam `&&` adını taşır;
  `search_file_in_folder()` özyinelemeli indeks üzerinden tam basename eşleşmesi
  ve son çare olarak tüm `&&` parçalarını içeren en iyi adayla
  (`.search_all_parts_contained()`) belgeyi alt klasörlerde de bulur.
- **Ortak Oturum tutarlılığı.** Aynı yükseltme ortak oda Langflow yolunda da
  (`.oo_langflow_yanit_metni`) uygulanır; oda `.source-link`'i
  `data-source-scope="model_bases"` kapsamını korur (çapraz-kullanıcı sızıntısı
  önlenir).
- **Sağlamlaştırma (kod incelemesi sonrası):** Eşleşmeyen/aralık dışı atıflar
  artık etkisiz kılınır (yanlış belgeye kaymaz); girişlerden sonraki metin
  ("Not:" gibi) sessizce düşürülmez; `<sup>` dönüşümü yalnızca gerçek bir
  Kaynakça bloğu varken VE etiket içeriği tamamen parantezli rakam grubuysa
  uygulanır (`m<sup>2</sup>` gibi sıradan üs/dipnot gösterimi dokunulmadan
  kalır); başlık BÜYÜK harfi de tanır (`KAYNAK:`, `KAYNAKÇA:`); öznitelikli
  `<sup>` etiketleri yakalanır (sayılar yalnızca etiket içeriğinden okunur);
  `ppt`/`pptx` dosya indeksine eklendi; numaralı girişler arasındaki boş
  satırlar listeyi kesmez; `search_file_in_folder()` artık ÖNCE tam basename
  eşleşmesini dener (ipucu-skorlu aramadan önce), böylece aynı son-parça adına
  sahip alakasız bir dosya yanlışlıkla döndürülmez.
- **İkinci sağlamlaştırma turu:** `docm` dosya indeksine eklendi (Word makro
  belgeleri de tıklanabilir); son çare parça-içerme araması artık yalnızca
  UZANTISIZ ipucu için etkin (atıflanan dosya diskte hiç yokken alakasız
  benzer adlı bir dosyayı yanlışlıkla açmaz — "bulunamadı" döner); "Grup&&
  dosya.pdf (Sayfa 3)" veya "dosya.pdf, s. 3" gibi belge uzantısından sonraki
  sayfa açıklaması ekleri artık uzantı doğrulamasını bozmadan ayrıştırılıp
  sayfa numarasına dönüştürülür.
- **Regresyon kapsamı:** `tests/testthat/test-langflow-inline-sources-behavior.R`
  (üstsimge dönüşümü, düzyazı ayrıştırma, imzalı işaretleyici yükseltme, kırıntı
  yolu render'ı, XSS kaçışı, alt klasör/`&&` dosya çözümlemesi). Mevcut
  `test-langflow-sources-behavior.R`, `test-langflow-handler-behavior.R`,
  `test-file-index.R` ve manifest/bölüm sözleşmeleri güncellendi.


### (Yayınlanmadı) 2026-07-12 Süreç Yönetimi Langflow çoklu akış onarımı + tıklanabilir belge kaynakları

- **Satır içi yorum akış listesini artık kirletmiyor.** `readRenviron()`
  `.Renviron` satır içi yorumunu değerin parçası saydığından,
  `LANGFLOW_PROCESS_FLOW_IDS` sonundaki `#yorum` (içinde `;` varsa) fazladan
  sahte akışlar üretiyor ("Akış 3") ve 2. akışın URL'sini bozuyordu
  ("URL rejected: Malformed input to a URL function"). Ayrıştırıcı artık kimlik
  değerindeki ilk `#` ve sonrasını ayıklar; ayıklama sonrası hâlâ bozuk
  (boşluk/URL-dışı karakter içeren) belirteç kalırsa TÜM liste net bir
  yapılandırma uyarısıyla reddedilir (kısmi kabul akışları kaydırıp yanlış akışa
  yönlendirebilirdi). Yorumların ayrı satıra yazılması `.Renviron.example` ve
  teknik referansta belgelendi.
- **Açık akış seçimi sessizce 1. akışa düşmez.** Dolu ama eşleşmeyen
  `selected_flow` değeri artık `""` çözümlenir ve işleyici net "seçili süreç
  akışı bulunamadı" hatası gösterir; boş seçim eskisi gibi varsayılan ilk akışı
  kullanır.
- **Açılır menüdeki Türkçe akış adlarında mojibake giderildi.** Görünen adlar
  (`LANGFLOW_PROCESS_FLOW_NAMES`) merkezi `normalize_text_utf8(...,
  repair_mojibake = TRUE)` yolundan geçer; Windows VM'de UTF-8 kaydedilmiş
  `.Renviron` değerlerinin çift kodlanması ("REHÄ°S SÃ¼reÃ§ ...") onarılır.
- **Langflow belge kaynakları tıklanabilir Kaynakça olarak geri geldi.** Yeni
  `R/helpers_langflow_sources.R` katmanı, desteklenen Langflow yanıt
  şekillerinden (results/message/sources, data/sources, artifacts/sources,
  source_documents, eski metadata dizisi) başlık/yol/sayfa/tür üstverisini
  çıkarır (kaynak uydurulmaz; model bilgisi `properties$source` yok sayılır).
  Kaynaklar içeriğe düz metin `[KAYNAK n] ...` işaretleyicisi olarak eklenir;
  render'da `process_message_content()` bloğu kaçışlı `.source-link` HTML'ine
  yükseltir (canlı mesajda ve kayıtlı sohbet yeniden yüklemesinde aynı). PDF ve
  Word kaynakları mevcut güvenli önizleme rotasından açılır
  (`source_file_clicked` -> `handle_source_file_click` -> kullanıcı kovası +
  model taban klasörleri; ipuçlarındaki `..`/sürücü parçaları ayıklanır).
  Kullanıcı mesajları asla yükseltilmez; grameri bozuk blok düz metin kalır.
- **İnceleme düzeltmeleri (P1/P2).** İşaretleyici bloğuna `openssl` bütünlük
  kodu (`kod=<hash>`) eklendi (modelin uydurduğu sahte `[KAYNAK n]` metni artık
  tıklanabilir kaynağa yükseltilmez); handler testi bu alanı hesaba katan
  regex'e geçirildi. `file_name`/`filename` alanları yol adayı sayılır (yalnızca
  başlık + dosya adı taşıyan yaygın kaynak biçimi artık reddedilmez). İşaretleyici
  temizleyici köşeli parantezleri korur (`Prosedür [Rev 2].pdf` yol=... değerinde
  bozulmaz).
- **Ortak oturum kaynak yayılımı.** Süreç/Uygulama Uzmanı ortak odalarında da
  Langflow belge kaynakları tıklanabilir Kaynakça olarak gösterilir
  (`oo_arac_langflow_uret` işaretleyiciyi ekler, `oo_mesaj_html` yükseltir).
  Güvenlik: ortak odadaki `.source-link` `data-source-scope="model_bases"`
  taşır; `handle_source_file_click()` bu kapsamda kişisel kullanıcı kovasını
  ATLAR ve yalnızca kurumsal model taban klasörlerinde çözer — böylece bir
  katılımcının atfı, tıklayan başka bir katılımcının kişisel dosyalarına
  çözümlenemez (çapraz-kullanıcı sızıntısı önlenir). Tekil sohbet varsayılan
  `personal` kapsamıyla değişmez.
- Regresyon kapsamı: `tests/testthat/test-langflow-runtime-behavior.R`
  (satır içi yorum + tam iki akış + 2. akış seçimi + UTF-8 etiketler + bozuk
  belirteç reddi + açılır menü seçenekleri),
  `tests/testthat/test-langflow-sources-behavior.R` (kaynak çıkarımı, kaynaksız
  yanıt, işaretleyici grameri + bütünlük kodu, file_name yol adayı, parantez
  koruması, XSS kaçışı, gezinme ipucu temizliği, model_bases kapsamı,
  process_message_content entegrasyonu),
  `tests/testthat/test-langflow-handler-behavior.R` (başarı yanıtında
  işaretleyici ekleme) ve yeni
  `tests/testthat/test-ortak-oturum-langflow-sources-behavior.R` (oda render
  yükseltmesi + model_bases-only tıklama çözümlemesi). Doğrulama notu:
  `bash tools/ai_validate.sh` bu oturumda cloud-quick profiliyle koşuldu; canlı
  Langflow ucu, gerçek kaynak dönen akış, çok kullanıcılı ortak oda tıklama akışı
  ve Windows VM açılır menü görselleri VM-üstü doğrulama gerektirir.

### (Yayınlanmadı) 2026-07-11 Açılış kabuk kapısı + Ortak Bilge Yolaç canlı ajan yenilemesi

- **Açılış kabuk kapısı (kenar çubuğu flaşı giderildi).** Soğuk açılışta sol
  kenar çubuğu/başlık, yükleme yedigeni %100'e ulaşmadan kısa süre
  görünebiliyordu (parça parça gelen HTML'de kabuk işaretlemesi yükleme
  katmanından ÖNCE boyanabiliyor). `app_loading_shell_gate_head_tags()`
  (`R/module_app_loading.R`, `ui.R` head'inde en erken nokta) gövde
  boyanmadan `<html>` üzerine `mergen-boot-shell-gate` sınıfını uygular ve
  `.main-header` / `.main-sidebar` / `.content-wrapper` kabuklarını
  `visibility: hidden` ile gizler (yerleşim korunur; yükleme katmanı, şerit
  seçicisi ve SSO hata yüzeyi açık istisnadır). Kapı yalnızca GÖSTERİLEN
  ilerleme %100'e ulaştığında `www/js/app_loading.js` kapanış yolunda
  bırakılır; katman hiç kurulamazsa DOMContentLoaded yetenek denetimi kabuğu
  kalıcı gizli bırakmaz. Hızlı Başlangıç'ta %100 sonrası kapanış animasyonu ve
  bekletme kısaltıldı (~1.2 sn'ye varan salt-görsel bekleme azaltımı).
  Regresyon: `tests/testthat/test-boot-shell-gate-contract.R`.
- **Ortak Bilge Yolaç gerçek kodlama-ajanı oldu.** Ortak BY odaları artık tek
  kullanıcılı Bilge Yolaç'ın stream-json boru hattını
  (`run_claude_code_streaming` + `stop_file` + çalışma anı `api_key`
  enjeksiyonu) kullanır; araç/kabuk/metin olayları tüm katılımcılara
  `KismiYanit` üzerinden canlı yayınlanır, süren çalıştırma yetkili rollerce
  durdurulabilir ve CLI yokken normal sohbet LLM'ine SESSİZ DÜŞÜŞ kaldırıldı
  (açık engelleyici mesaj + yeniden gönderilebilir komut). Kompozerde BY odası
  genel model menüsü yerine Hızlı/Dengeli/Güçlü katmanlarını gösterir;
  model/proje dizini değişimi CLI devam bağlamını sıfırlar. Ayrıntı:
  `docs/ortak-oturumlar.md` §12.2d.
- **Ortak oda UI düzeltmeleri.** Model/Persona/Araç kompozer menüleri artık
  YUKARI açılır (ekran dışına taşma giderildi); Ortak Belgeler paneli kompakt
  sürükle-bırak yükleme yüzeyi ("Belgeleri buraya sürükleyin veya Belge Seç")
  ve kırpılmayan, kaydırma çubuğu üretmeyen boş durum kazandı; Ortak
  Çalışmalarım liste kartları arasındaki boşluk `uiOutput` sarmalayıcısına
  taşınan ızgara kurallarıyla geri geldi (kartlar birbirine değmiyor).

### (Yayınlanmadı) 2026-07-11 Hızlı Başlangıç VM ölçümü güncellendi

- Son Windows VM konsol kayıtlarına göre Hızlı Başlangıç performansı
  iyileşti: sunucu yeni başlatılıp ilk kullanıcı oturum açtığında hızlı şerit
  ertelenmiş hazırlık bandı yaklaşık **13 sn** seviyesinde görülüyor
  (`character_media_ready`/`saved_chats_preview_ready`/`saved_chats_full_deferred`
  ~13.0 sn). Bu değer etkileşim hazır noktasıyla karıştırılmamalıdır:
  aynı soğuk kayıtta `welcome_client_ready` **~15.6 sn** olarak loglandı.
  Sunucu zaten çalışırken yenileme veya yeni oturum açma akışında
  `welcome_client_ready` artık yaklaşık **3.1-3.6 sn** aralığında. Bu
  değerler eski ~28 sn soğuk ve ~14 sn sıcak `welcome_client_ready`
  ölçümlerine göre belirgin iyileşmedir.

### (Yayınlanmadı) 2026-07-11 Hızlı Başlangıç açılışı artık kayıtlı sohbet ön izleme worker hazırlığını beklemiyor

- **Belirti (Windows VM):** Hızlı Başlangıç seçiliyken kimlik doğrulaması ile
  `welcome_client_ready` arasında ~9-14 sn'lik senkron duraklama vardı; soğuk
  açılışta `welcome_client_ready` ~28 sn'ye kadar çıkıyordu. Duraklamanın
  ortasında `Registered S3 method overwritten by 'quantmod'` uyarısı beliriyordu.
- **Kök neden:** Hızlı şerit ön izlemeyi `tracked_future_promise()` ile
  başlatsa da, bu sarmalayıcı gönderimden ÖNCE ANA OLAY DÖNGÜSÜNDE senkron
  bağımlılık taraması yapıyordu (`future::getGlobalsAndPackages()` +
  `.GlobalEnv` üzerinde özyinelemeli `codetools::findGlobals()`). Uygulama
  büyüdükçe bu tarama saniyeler sürüyor ve yol boyunca highcharter isim
  uzayını yükleyip quantmod/zoo S3 uyarısını kritik açılış yolunda
  tetikliyordu. `saved_chats_full_loaded=…` işaretinin geç zaman damgası tam
  listenin yüklendiğini DEĞİL, bu ön izleme gönderim yükünü gösteriyordu.
- **Düzeltme:** Ön izleme artık ilk çizimden (`welcome_client_ready`) SONRA,
  yeni dar "explicit" worker sözleşmesiyle ısıtılır
  (`R/helpers_startup_chat_preview.R` + `tracked_future_promise(..., dependency_mode = "explicit")`).
  Explicit mod otomatik taramayı ve oturum-ortamı serileştirmesini tamamen
  atlar; yalnızca DBI + iki saf fonksiyon + skaler DSN/encoding değerleri
  worker'a taşınır. Böylece quantmod/zoo uyarısı açılış yolundan (uyarıyı
  bastırarak değil, gereksiz bağımlılık yolunu kaldırarak) çıkar.
- Açılış katmanı ne ön izleme gönderim hazırlığını ne de altı satırlık DB
  sorgusunu bekler; ilk Ana Söyleşi ekranı bu sorgudan bağımsız etkileşimli
  hâle gelir. İstemci sinyali hiç gelmezse ~10 sn güvenlik zamanlayıcısı ön
  izlemeyi yine de yükler.
- **Dürüst kontrol noktaları:** `saved_chats_preview_ready` HEMEN `deferred=TRUE`
  ("Son konuşmalar arka planda yüklenecek") işaretlenir; gerçek ısıtma ayrı
  `saved_chats_preview_hydrated` anahtarıyla raporlanır; tam liste ertelemesi
  `saved_chats_full_deferred`, gerçek tamamlanma ise `saved_chats_full_loaded`
  anahtarını kullanır — aynı anahtar iki farklı durumu temsil etmez.
- Tam liste hâlâ tembeldir (Kayıtlı Söyleşiler / Söyleşi Geçmişi ilk
  açıldığında bir kez yüklenir) ve tüm yarış/kullanıcı-izolasyon korumaları
  (geç ön izleme yerel değişikliği/başlamış tam listeyi ezmez, kapanan oturum
  callback'i durum değiştirmez, kimlik ısıtma anında yeniden çözülür, geçersiz
  kimlik sorgu açmaz) korunur. Zengin Deneyim davranışı değişmedi.
- Testler: `test-startup-observers-runtime-smoke.R` (ısıtma zamanlaması,
  güvenlik zamanlayıcısı, gönderim/red hatası, kimlik yeniden çözme),
  `test-startup-chat-preview-behavior.R` (yeni; dar export sözleşmesi + okuyucu
  biçim hizası), `test-worker-monitor.R` (explicit mod otomatik taramayı
  çağırmaz, auto mod geriye dönük uyumlu, red sonrası defter temizliği).

### (Yayınlanmadı) 2026-07-09 Hızlı Başlangıç açılış regresyonu + VM test uyarı seli düzeltmesi

- Hızlı Başlangıç seçiliyken açılışın ~34 saniyeye uzamasına yol açan şerit
  yarışı düzeltildi: kayıtlı sohbet açılış kararı artık şerit çözümüne
  (`startup_lane_resolved`) kilitli. Hızlı şeritte tam söyleşi listesi açılışta
  HİÇ yüklenmez (Kayıtlı Söyleşiler / Söyleşi Geçmişi ilk açıldığında bir kez
  tembel yüklenir), "Son konuşmalar" ön izlemesi kritik açılış yolunu bloklamaz
  (arka plan worker'ında yüklenir). Zengin Deneyim davranışı değişmedi. Hızlı
  şerit kapanış sözleşmesi `connect + auth_ready + welcome_client_ready` olarak
  kaldı; sorgular DB seviyesinde kullanıcıya filtrelidir ve geçersiz/placeholder
  kimlik yükleme başlatamaz.
- Windows VM'de tam test koşusundaki `W` uyarı seli köke indirildi: uygulama
  çalıştırılmış R oturumunda `global.R` `options(encoding = "UTF-8")` bırakır;
  CP1254 yerel kod sayfasında testlerdeki `readLines(..., encoding = "UTF-8")`
  okumaları çift kod çözümüne girip `grepl` başına satır sayısı kadar
  "invalid UTF-8" uyarısı üretiyordu (repo dosyaları geçerli UTF-8; son
  commit'lerle ilgisi yok). `tests/testthat/helper_bootstrap.R` test koşumunu
  `native.enc` varsayılanına sabitler.
- Testler: `test-startup-observers-runtime-smoke.R` (hızlı/zengin/tembel/geçersiz
  kimlik senaryoları), `test-startup-lane-contract.R` yeni statik kilit,
  `test-testthat-encoding-guard-contract.R`.

### (Yayınlanmadı) 2026-07-05 Ortak Oturumlar (işbirlikçi çalışma odaları) — ilk sürüm

MERGEN Bilge'ye ekip tabanlı "Ortak Oturumlar" özelliği eklendi: paylaşılan
yapay zekâ çalışma odaları, oda içi katılımcı yazışması ("Odaya Yaz"; LLM'e
gitmez), odaya tek yanıt üreten "Yapay Zekâya Sor" akışı (oda başına DB
kilitli tek aktif üretim), Türkçe rol/durum modeli (`Sahip`,
`OturumYöneticisi`, `Katılımcı`, `İzleyici`; `DavetEdildi/Katıldı/...`),
Mergen içi davet bildirimi + içerik sızdırmayan e-posta TASLAĞI (otomatik
gönderim yok), kalp atışı tabanlı canlı durum (`Çevrimİçi/Boşta/ÇevrimDışı`),
ortak belge deposu ("Kendi Dosyalarıma Kaydet" ile açık kişisel kopya),
kullanıcı bazlı arşiv ile oda arşivi ayrımı, sahiplik devri, denetim izi
(`MB_OrtakOturum_Olaylar`), bakım temizliği ve UTF-8 BOM'lu tutanak indirme.

- **DB:** 13 yeni tablo; kurulum `docs/sql/2026-07-ortak-oturumlar.sql`
  (manuel DBA; açılışta OTOMATİK ÇALIŞTIRILMAZ), geri alma
  `docs/sql/2026-07-ortak-oturumlar-rollback.sql`. Kişisel
  `MB_Chats`/`MB_Messages`/`MB_ClaudeCode_*` aileleri DEĞİŞMEDİ; tablolar
  kurulmadan uygulama tam çalışır (aşamalı devreye alma).
- **Kod:** yeni `ortak_oturumlar` manifest bölümü (12 dosya;
  `sohbet_llm_akis` seam'i), `www/css/ortak_oturumlar.css` +
  `www/js/ortak_oturumlar.js` (manifest + `gecmis_kayit_arama` bölgesi),
  üç yeni sekme (`Ortak Çalışmalarım`, `Ortak Söyleşiler`,
  `Ortak Bilge Yolaç Oturumları`).
- **Testler:** `test-ortak-oturum-permissions-behavior.R`,
  `test-ortak-oturum-db-behavior.R` (gerçek SQLite),
  `test-ortak-oturum-sql-contract.R`, `test-ortak-oturum-ui-contract.R`;
  ilgili dondurulmuş sözleşmeler bilinçli güncellendi (bölüm sayısı 302→314,
  varlık manifest listeleri).
- **Kanıt sınırı:** Bulut doğrulaması SQLite/statik sözleşme kanıtıdır;
  SQL Server Türkçe at-rest doğrulaması, SSO'lu çok kullanıcılı oda denemesi
  ve canlı LLM yanıtı Windows VM kapılarında koşulmalıdır (RUNBOOK §9B).
  Bilinen sınırlamalar (canlı ortak Bilge Yolaç CLI köprüsü, YZ kuyruğu,
  geçmiş kopyalama otomasyonu, ortak streaming, yönetici panosu) için
  [`ortak-oturumlar.md`](ortak-oturumlar.md) §12.

### (Yayınlanmadı) 2026-07-04 Soğuk açılış ve etkileşim performans stabilizasyonu + şerit ayarı/dosya politikası düzeltmeleri

**Geçerli kanıt tabanı:** Bu çalışmadan hemen önce Windows VM'de tam kanıt kapısı (`bash tools/vm_evidence_gate.sh`, profil `vm/vm`, `MERGEN_BROWSER_UX_BASE_URL` üzerinden zorunlu tarayıcı smoke ile) **13 passed / 0 failed / 0 skipped** sonuçlandı; artifact: `artifacts/vm-evidence/20260704-085658/evidence.json` (`full_testthat` 3647.7 sn, `browser_ux_smoke` 233.8 sn PASS, `vm_preflight_real` ve `db_encoding_preflight` PASS). Bu sonuç korunacak temel çizgidir; bu bölümdeki değişikliklerden sonra VM'de kapı yeniden koşulmalıdır.

**Soğuk açılış kritik yolu (kök neden):** Açılışta üç ağır iş, tek R olay döngüsünü senkron bloklayarak `welcome_client_ready` işlenmesini geciktiriyordu; bu yüzden Hızlı Başlangıç bile "Dosyalar hazırlanıyor" aşamasında takılı görünüyordu (5 küçük dosyada bile):

1. Dosya Yönetimi kalıcı klasör taraması (`refresh_from_user_folder("initial"/"auth_ready")`): dosya başına 5-6 dosya sistemi stat çağrısı (UNC paylaşımlarında pahalı) + indeks okuma.
2. Görsel Galerisi: oturum başlangıcında görsel tarama + görsel başına ek "sonraki AI yanıtı" DB sorgusu (N+1) + `gallery_content` çıktısının `suspendWhenHidden = FALSE` ile GİZLİYKEN render edilmesi (her görselin base64 gövdesi açılış websocket yüküne biniyordu).
3. "Yeni Söyleşi": karşılamayı üç kez yıkıp kuran render zinciri + tam sohbet listesini senkron çeken DB sorgusu.

**Düzeltmeler:**

- **Tembel dosya envanteri (iki şeritte de):** Açılış tetikleri (`initial`/`auth_ready`/`startup`) artık tarama yapmaz; `file_index_ready` kontrol noktası dürüst `deferred = TRUE` ayrıntısıyla işaretlenir ve açılış etiketi "Dosyalar gerektiğinde yüklenecek" olarak değiştirildi (sahte ilerleme yok; iş gerçekten ertelenir). Gerçek tarama, Dosya Yönetimi ilk açıldığında (`page_opened`) veya manuel/araç tetiklerinde çalışır ve süresi loglanır.
- **Tembel Görsel Galerisi:** Galeri, sayfa ilk açılana kadar tarama/DB sorgusu yapmaz (`gallery_activated`); gizliyken tam kart render'ı kaldırıldı; açıklama yükleme N+1 sorgudan tek korelasyonlu sorguya indirildi (`SonrakiYanit`).
- **"Yeni Söyleşi" anındalığı:** Üçlü karşılama render'ı teke indirildi (300 ms gecikmeli üçüncü render ve `chat_start_new_chat` içindeki boşa giden ilk ekleme kaldırıldı); tam liste sorgusu yerine hafif son-6 önizleme sorgusu bellek içi listeyle birleştirilir (karşılama "Son Konuşmalar" ilk 3 doğruluğu korunur).
- **Dürüst toast sıralaması:** Kayıtlı söyleşi açılışında anında "Söyleşi yükleniyor..." geri bildirimi eklendi; "Söyleşi yüklendi" toast'ı içerik mesajlarından SONRA gönderilir (galeriden dönüşte mevcut yükleniyor durumu korunur, süre loglanır).
- **İşçi ön-ısıtma:** `prewarm_future_workers_once()` açılışta her kalıcı işçiye küçük bir paket-yükleme görevi gönderir; ilk istemin "ilk token" gecikmesindeki işçi soğuk başlangıç bileşeni kaldırılır (`MERGEN_DISABLE_FUTURES=true` iken no-op).
- **Açılış faz ölçümü:** `bootReadinessInit()` her kontrol noktası için `[STARTUP PERF] checkpoint=<ad> elapsed_ms=<süre>` satırı yazar; soğuk açılışın nerede harcandığı loglardan okunur. Dosya taraması, galeri taraması, kayıtlı söyleşi/galeri açılışı ve Yeni Söyleşi için ölçüm satırları eklendi.
- **Başlangıç Deneyimi ayarı artık kaydetmeyle uygulanır:** Yapılandırma'daki Hızlı Başlangıç/Zengin Deneyim radyosu yalnızca bekleyen form durumunu günceller; kalıcılaştırma ve canlı uygulama yalnızca "Ayarları Kaydet" ile (`mergen_apply_saved_startup_lane()`) olur. Kaydetmeden yenileme eski kayıtlı tercihi korur.
- **Radyo görünürlük/tema düzeltmesi:** Şerit radyoları onay kutusu temasıyla tutarlı özel görünüme kavuştu (koyu/açık tema, seçili iç nokta, `:focus-visible` halkası, seçili metin vurgusu).
- **Desteklenmeyen dosya politikası:** Kullanıcı klasöründeki desteklenmeyen uzantılı dosyalar (örn. ajan üretimi `.doc`) artık Dosya Yönetimi'nde "Desteklenmeyen dosya türü" durumu ve yalnızca indir/sil işlemleriyle GÖRÜNÜR; her girişte yanıltıcı "kaydedilemedi" toast'ı üretilmez ve içerik asla ayrıştırılmaz. Office eklentisi beceri dosyasına zorunlu uzantı politikası eklendi: Word çıktısı her zaman `.docx` (asla `.doc`), Excel `.xlsx`, PowerPoint `.pptx`. Desteklenen yükleme türlerinin tek kaynağı `fm_normal_allowed_extensions()` olmaya devam eder.

**Testler:** Yeni davranış testleri `test-file-manager-unsupported-file-behavior.R`, `test-startup-lane-pending-save-behavior.R`, `test-image-gallery-lazy-activation-behavior.R`; güncellenen sözleşmeler `test-startup-lane-contract.R` (bekleyen-durum sözleşmesi) ve `test-image-gallery-descriptions-db-behavior.R` (tek-sorgu sözleşmesi). İlgili mevcut dosya yöneticisi/galeri/karşılama/manifest/ratchet sözleşmeleri cloud'da 0 fail / 0 warn geçti; repo geneli parse sanity (909 dosya) geçti.

**Bilinen kısıtlar:** Uygulama hâlâ tek örnek/tek port (8009) üzerinde çalışır; yük dengeleyici/çoklu port IT onayı beklemektedir. Düşünen modellerde ilk "Düşünce Akışı" parçasının gecikmesi model TTFT + ağ geçidi/proxy tamponlamasını da içerir; uygulama tarafındaki yoklama 15-50 ms aralıkla artımlı akıtır ve `[CHAT PERF] SSE işçide ilk ham HTTP parçası alındı` / `stream.first_delta` logları gecikmenin uygulama içi mi yukarı akış mı olduğunu ayırt eder. Yukarı akış tamponlaması uygulamadan giderilemez; loglarla belgelenir.

### 2026-07 Üretim Güvenli MB_* SQL Server İndeks Yayılımı

Üretim güvenli Wave 1-4 MB_* SQL Server indeks yayılımı, daha önce yapılan ve oturum açma hatasına neden olan toplu indeksleme girişiminin yerine geçecek şekilde artık dokümante edilmiştir. Kesintinin kök nedeni kesin olarak kanıtlanmamıştır; ancak güvenli olmayan tek seferde/toplu dağıtım, şema kilitlenmesi ve/veya oturum açma yoluna yönelik aşırı agresif benzersiz indeks denemesinden kaynaklanmış olabileceği kayda geçirilmiştir. Nihai güvenli indeks seti üretim ortamında kararlı durumdadır; kullanıcılar oturum açabilmekte ve yönetici sayfalarında ilk tıklama/içerik yükleme süreleri gözle görülür biçimde hızlanmıştır.

Yeni dokümantasyon; mevcut etkin indeks envanterini, özellikle benzersiz olmayan şekilde tasarlanan `IX_MB_Feedback_User_Message` ve `IX_MB_Users_KullaniciAdi_Lookup` indekslerini ve açıkça tanımlanan `MB_Users` performans indeksinin, önceden var olan benzersiz `KullaniciAdi` kısıtı/indeksi ile birlikte çalıştığı gerçeğini kayıt altına almaktadır. Güvenli script dosyası `docs/sql/2026-07-safe-mb-performance-indexes.sql` yolundadır. Yalnızca bu güvenli performans indeksleri için kullanılacak acil geri alma scripti ise `docs/sql/2026-07-safe-mb-performance-indexes-rollback.sql` dosyasıdır. `IX_MB_Usage_Log_User_Model`, `IX_MB_Usage_Log_Chat_Message`, yalnızca geniş kapsamlı son kayıt/recent sorgularını destekleyen indeksler ve yeni herhangi bir benzersiz `IX_MB_Users_KullaniciAdi` indeksi gibi önceki adaylar; Query Store/çalışma planı kanıtı ve DBA onayı olmadan bilinçli olarak kapsam dışında bırakılmıştır.

Doğrulama notu: Temsilî yönetici liste sorguları için gözlemlenen `STATISTICS IO/TIME` sonuçları, mevcut küçük tablolarda oldukça düşük çıkmış ve kullanıcı arayüzündeki iyileşmeyle uyumlu görünmüştür. Ancak bu sonuçlar, indeks seek kullanımını veya gelecekte büyük tablolar altında kapasite dayanımını kanıtlamaz. Bu yayılım, veritabanı ağırlıklı/yönetici ekranı gecikme yollarını iyileştirmeyi amaçlamaktadır; bir soak-kapasite iddiası değildir ve yalnızca GET isteklerine dayalı soak sonuçlarında anlamlı bir değişim yaratmayabilir.

### (Yayınlanmadı) Bilge Yolaç kalıcı oturumları: Oturumlar sayfası ve Claude Code Web tarzı saklama

Bilge Yolaç, kalıcı, devam edilebilir ve incelenebilir ajan oturumlarına kavuştu. Navigasyonda "Bilge Yolaç" genişleyebilir bir gruba dönüştü: **Çalışma Alanı** (mevcut ajan tezgahı, davranışı değişmedi) ve yeni **Oturumlar** sayfası.

- **Saklama katmanı:** Yeni `MB_ClaudeCode_Sessions` + `MB_ClaudeCode_Runs` tabloları (MB_Chats/MB_Messages'tan kasıtlı olarak ayrı; kurulum betiği `docs/sql/2026-07-bilge-yolac-sessions.sql`, açılışta otomatik çalıştırılmaz). Her komut/yanıt/araç çalıştırması — başarılı, başarısız, durdurulan, zaman aşımına uğrayan — kullanıcı-izole olarak saklanır. Tablolar kurulmadıysa Bilge Yolaç uyarı loglayıp bellek-içi modda tam çalışmaya devam eder; persist hatası canlı yanıtı asla bozmaz.
- **Oturumlar sayfası:** Özet metrikler, arama + durum/model/sıralama filtreleri, zengin oturum kartları (başlık, proje dizini, son komut önizlemesi, model rozeti, devam edilebilirlik, çalıştırma/dosya sayaçları, göreli zaman) ve çalıştırma zaman çizelgeli detay modali. Liste sayfalıdır; tamamı tema token'lı olduğundan koyu ve açık temada eksiksiz çalışır; azaltılmış-hareket tercihi desteklenir.
- **Devam Et:** Kayıtlı oturum tek tıkla çalışma alanına yüklenir; geçmiş mesajlar (araç kullanımı bölümleri ve hâlâ mevcut üretilen-dosya kartları dahil) mevcut mesaj görünümüyle yeniden oynatılır. Claude CLI `--resume` yalnızca oturumun çalışma dizini hâlâ erişilebilirse kurulur; aksi halde geçmiş salt görünür kalır ve takip soruları taze CLI oturumu başlatır ("No conversation found with session ID" bu kontrolle önlenir).
- **Güvenli temizleme:** "Çıktıyı Temizle", model veya proje dizini değişimi kalıcı geçmişi SİLMEZ; yalnızca aktif oturum bağını koparır. Arşivleme yumuşak silmedir ve yalnızca Oturumlar sayfasındaki onaylı eylemle yapılır.

Yeni/değişen ana dosyalar: `R/helpers_db_claude_code_session_queries.R`, `R/helpers_db_claude_code_sessions.R`, `R/helpers_claude_code_session_persistence.R`, `R/helpers_claude_code_workbench_session_api.R`, `R/module_claude_code_sessions_ui.R`, `R/module_claude_code_sessions.R`, `www/js/claude_code_sessions.js`, `www/css/claude_code_sessions.css`, `docs/sql/2026-07-bilge-yolac-sessions.sql`.

### (Yayınlanmadı) Bilge Yolaç Oturumlar iyileştirmeleri: arşiv geri yükleme, kalıcı silme, filtre/rozet/ikon düzeltmeleri ve yönetici/sistem istatistikleri

Oturumlar sayfasının ilk sürümü üzerine odaklı UX/veri iyileştirmeleri eklendi (mevcut Çalışma Alanı, Yönetici Paneli ve Sistem Durumu davranışı korunarak):

- **Filtreler "Tümü" seçeneğini kaybetmiyor:** "Durum" ve "Model" açılır menüleri artık yerel `<select>` (selectize kapalı) kullanır; boş-değerli "Tümü" seçeneği başka bir öğe seçildikten sonra da erişilebilir kalır. Model listesi sunucu tarafında birikimli (kararlı) tutulur: bir modele göre filtrelemek diğer modelleri veya "Tümü"yü açılır listeden düşürmez, yenileme/tekrar giriş gerekmez.
- **Arşivden çıkarma (geri yükleme):** Arşivlenmiş oturum kartlarına belirgin "Geri Yükle" eylemi eklendi. `cc_db_restore_session()` `IsDeleted = 0` yaparak oturumu normal listeye kullanıcı-izole biçimde geri döndürür (arşivleme ile simetrik).
- **Kalıcı silme:** Arşivlenmiş kartlara ikinci onay adımı isteyen "Kalıcı Sil" eylemi eklendi. `cc_db_hard_delete_session()` oturumu ve tüm çalıştırmalarını tek işlemde, sahiplik doğrulaması + `UserID` sınırıyla siler (geri alınamaz). Silme/geri yükleme normal arşiv akışıyla çakışmaz. **Artefakt temizliği (Codex P2):** kalıcı silme, oturumun ürettiği indirilebilir dosyaları da kaldırır — metadata silinmeden önce `download_path` yolları toplanır, DB commit'i başarıyla tamamlandıktan SONRA yalnızca indirme kökü (`get_claude_code_download_root()`) altındaki gerçek dosyalar en iyi çaba ile silinir (`cc_policy_path_inside_roots(..., must_exist = TRUE)`). Aksi halde `bilge_yolac_downloads` altında sunulan dosyalar, daha önce açılmış indirme URL'leriyle silinmeden sonra da erişilebilir kalırdı. Kök dışı yollar asla silinmez; arşivleme/geri yükleme dosyaları KALDIRMAZ (geri alınabilir).
- **Rozet tutarlılığı:** Oturumlar sayfasındaki "AJAN" rozeti artık Çalışma Alanı ile aynı görsel dili kullanır (koyu temada aynı aksan degradesi; açık temada aynı kırmızı hap override'ı).
- **Navigasyon ikonu ayrımı:** "Bilge Yolaç" ana menüsü artık `robot` ikonu kullanır; "Çalışma Alanı" alt öğesi `terminal` ikonunu korur, böylece iki menü öğesi görsel olarak ayırt edilir.
- **Detay modali:** Modal içeriğine ölçülü bir taban yükseklik eklendi (kısa oturumlarda gereksiz kaydırma azalır). Kayıtlı oturum detayı artık her çalıştırmanın ürettiği belgeleri isim + boyut + indirme bağlantısı olarak listeler; "Devam Et" yolunda üretilen-dosya kartları zaten mevcut mesaj görünümüyle geri yüklenir.
- **Sohbet başlıkları:** Kayıtlı oturum çalışma alanına yüklendiğinde kullanıcı/AI baloncukları normal başlıklarını (gönderen adı, karakter adı, zaman/süre) korur; hidrasyon mesajı bu alanları taşır ve `claude_code.js` `addMessage` köprüsü başlıkları tek kaynaktan (`cc-message-header`) üretir.
- **Yönetici Paneli > Genel Analiz > Bilge Yolaç sekmesi:** Diğer admin sekmeleriyle aynı desende yeni bir sekme eklendi (`R/module_admin_bilge_yolac.R`). Özet metrik kartları (toplam/devam edilebilir/arşivlenmiş oturum, kullanıcı sayısı, toplam/dosyalı çalıştırma, ortalama süre), son 30 günlük oturum eğilimi ve durum dağılımı grafikleri, en aktif kullanıcı ve son oturum tabloları. Tablolar yoksa sekme güvenli biçimde sıfır/boş gösterir.
- **Sistem Durumu:** Yeni `health_check_bilge_yolac_sessions()` kontrolü, `MB_ClaudeCode_Sessions`/`MB_ClaudeCode_Runs` tablolarının erişilebilirliğini ve oturum/çalıştırma sayılarını raporlar (tablolar yoksa `not_configured`, hata fırlatmaz).
- **Codex P2 düzeltmeleri:** (1) Aktif kayıt arşivlenirken çalışma alanında GÖRÜNEN transkript de temizlenir (DB/CLI bağı koparılırken ekranda kalan arşivlenmiş sohbet, sonraki çalıştırmayı yanıltmaz). (2) `cc-set-model-selection` istemci işleyicisi, geri yüklenen model artık mevcut model listesinde yoksa Shiny'e bayat değer göndermez; etkin/ilk butonun geçerli değerine düşer.
- **Hidrasyon biçimleyici düzeltmesi:** `.cc_hydrate_safe_output_html()` artık her durumda önce ham HTML'i güvenli markdown'a kaçışlar, sonra enjekte edilen biçimleyiciyi (üretimde `format_claude_code_output`) uygular; böylece canlı yanıt yolundaki markdown görünümüyle tutarlıdır ve `render_safe_markdown_html` yüklüyken de biçimleyici sözleşmesi korunur (XSS sınırı değişmez).

Yeni/değişen ana dosyalar: `R/helpers_db_claude_code_session_lifecycle.R` (geri yükleme + kalıcı silme), `R/module_admin_bilge_yolac.R` (yönetici sekmesi), `R/helpers_health_runtime_checks.R` (+ `R/helpers_health_checks.R`, oturum sağlık kontrolü), `R/helpers_claude_code_session_persistence.R` (hidrasyon biçimleyici), `R/helpers_claude_code_workbench_session_api.R` (detach görünüm temizliği), `R/module_claude_code_sessions.R` / `R/module_claude_code_sessions_ui.R` (filtre/eylem/detay), `www/js/claude_code_sessions.js` (model fallback), `www/css/claude_code_sessions.css` / `www/css/claude_code.css` (rozet/modal), `ui.R` (menü ikonu), `R/module_admin_analytics.R` (sekme yönlendirme).

Doğrulama: odaklı sözleşme/davranış testleri (`test-claude-code-sessions-db-behavior.R`, `test-claude-code-sessions-module-contract.R`, `test-claude-code-session-persistence-behavior.R`, `test-health-check-runtime-contract.R`, `test-admin-analytics-ui-contract.R`, `test-source-manifest-sections-contract.R`, `test-maintainability-ratchet.R` + manifest/seam/production/frontend-selector sözleşmeleri) ve repo geneli parse sanity + `MERGEN_RUN_APP=false` uygulama boot smoke cloud `C.utf8` altında geçti. highcharter kurulu olmadığından admin sekmesinin grafik render testi cloud'da SKIP olur (VM'de çalışır). Gerçek SQL Server T-SQL (kalıcı silme, admin/sağlık toplu sorguları), tarayıcı UX ve VM/SSO doğrulaması Windows VM'de yapılmalıdır.

### 2026-07-03 Başlangıç deneyimi yeniden tasarımı: Hızlı Başlangıç / Zengin Deneyim şeritleri

Uygulama açılışı iki şeritli modele taşındı. Temel ilke: **Hızlı Başlangıç açılış yükünü kaldırır, işlevselliği kaldırmaz; Zengin Deneyim mevcut sinematik gösteriyi korur ve ilerleme ekranını daha şeffaf hâle getirir.**

- **Hızlı Başlangıç (fast_lane):** URL girilir → kullanıcı doğrudan Ana Söyleşi'ye iner ve hemen yazabilir. Derin uzay girişi, açılış müziği, sinematik arka plan videoları ve persona medya ön yüklemesi açılışta hiç başlatılmaz; karşılama ekranı, hızlı eylem kartları, sohbet girişi, gönder/durdur ve model seçici tam çalışır. Karşılama zeminleri statik premium koyu degradeye döner (sürekli ağır animasyon yok). Açılış katmanı yalnızca sohbet-kabuğu hazırlığını bekler (`connect` + `auth_ready` + `welcome_client_ready`); kayıtlı sohbet önizlemesi, dosya indeksi ve galeri arka planda sürmeye devam eder ve ilgili sayfalar açıldıklarında tam çalışır. Hiçbir özellik silinmez.
- **Zengin Deneyim (rich_lane):** Mevcut derin uzay girişi, giriş müziği, Keşfet akışı, "Bir daha gösterme", üç Deneyim Modu (Odak/Dinamik/Bütünleşik) ve Bütünleşik karakter seçim adımı birebir korunur. İlerleme ekranı iyileştirildi: uzun medya aşaması gerçek alt-ilerleme sayacı gösterir ("Sinematik ve persona medyası hazırlanıyor · 4 / 12") ve 6 saniyeden uzun süren gerçek aşamalarda etkin-aşama metni ("… · sürüyor") ile ekranın donmuş görünmesi engellenir. Sahte ilerleme yoktur; %100 yalnızca gerçek hazır-olma ile gelir.
- **İlk açılış şerit seçicisi:** Kayıtlı tercih yoksa tam ekran, koyu, iki kartlı seçici gösterilir (video/Three.js/persona medyası olmadan; yalnızca hafif CSS mikro-animasyon). Seçim anında `mergen_settings.startup_lane` olarak kalıcılaştırılır ve bir daha sorulmaz. Dağıtım varsayılanı `MERGEN_STARTUP_LANE` ortam değişkeniyle verilebilir (`ask_once` varsayılan, `fast_lane`, `rich_lane`); geçersiz değerler güvenle `ask_once`'a düşer.
- **Ayarlar:** Yapılandırma sayfasına "Başlangıç Deneyimi" kartı eklendi (Hızlı Başlangıç / Zengin Deneyim; değişiklik anında kalıcılaşır, tam etki sonraki açılışta). Kişiselleştirme'deki Deneyim Modu kartları Hızlı Başlangıç etkinken gizlenir ve açıklayıcı bir notla Zengin Deneyim'e yönlendirilir; Zengin Deneyim'de kartlar normal davranır. "Varsayılana Dön" şeridi `ask_once`'a döndürür (seçici yeniden sorulur).
- **Koyu sinematik başlangıç kabuğu:** Zengin Deneyim başlangıç akışı (derin uzay, Yenilikler rozeti/modalı, Keşfet, mod seçimi, Bütünleşik karakter adımı) artık kullanıcının uygulama teması açık olsa bile HER ZAMAN koyu sinematik görünümde çalışır. `theme_manager.js` sinematik koyu-tema kilidi `body.deep-space-active` yaşam döngüsünü izler; akış kapanınca kullanıcının teması geri uygulanır (uygulama açılış sonrası açık temada çalışmaya devam eder). Sinematik yüzeylerin açık-tema override'ları kaldırıldı; Destek > Yenilikler SAYFASININ açık tema okunabilirliği (`.destek-surum-tab`) korunur.
- **Mod kartı cilası:** Başlangıç mod kartları premium koyu cam yüzeye (degrade + üst iç ışık) taşındı ve spotlight parıltısı ölçülü hâle getirildi.
- **Süreç akışı sıfırlama düzeltmesi (Codex P2):** "Ayarları Sıfırla" artık gizli `#chat_process_flow` DOM seçicisini varsayılana döndürür ve bayat `input$chat_process_flow` değerini boş değerle ezer; böylece Süreç modu yeniden etkinleştirildiğinde eski akış sessizce yeniden kalıcılaşmaz.

Yeni/değişen ana dosyalar: `R/helpers_startup_lane.R` (saf şerit çözümleyici), `R/module_startup_lane.R` (şerit sunucu gözlemcileri), `www/js/app_loading_lane.js` (istemci çözümleyici + ilk açılış seçicisi; açılış katmanına satır içi gömülür), `www/js/app_loading.js` / `www/js/app_loading_media.js` (şeride duyarlı ilerleme/medya), `www/js/theme_manager.js` (sinematik koyu kilit), `www/js/modern_welcome_handler.js` (+ `welcome_modern.css`) hızlı şerit statik karşılama, Yapılandırma/Kişiselleştirme ayar yüzeyleri.

Doğrulama: `bash tools/ai_validate.sh quick` (0 failed / 0 skipped) ve odaklı sözleşme/davranış testleri (`test-startup-lane-resolver-behavior.R`, `test-startup-lane-contract.R` + güncellenen manifest/ratchet/id-surface sözleşmeleri) cloud `C.utf8` altında geçti. Gerçek tarayıcı UX, VM/SSO ve `UX_SMOKE_DONE:PASS` doğrulaması VM'de yapılmalıdır; ölçülmüş performans sayısı iddia edilmemektedir ("doğrudan Ana Söyleşi'ye iniş", "algılanan açılış yükünde azalma").


### 2026-07-02 Langflow temizliği, çoklu süreç akışı ve ikinci LLM uç noktasının kaldırılması

Kurumsal Langflow entegrasyonu (Süreç Yönetimi / Uygulama Uzmanı) sadeleştirildi ve genişletildi:

- **Düşünme animasyonu düzeltmesi:** Süreç Yönetimi ve Uygulama Uzmanı istekleri artık uygulamanın diğer düşünen-model akışlarıyla aynı standart (simüle fazlı) "Düşünce Akışı" panelini gösterir; eski görsel-oluşturma spinner'ı kaldırıldı. Langflow non-streaming olduğundan panel, yanıt gelene kadar canlı kalır ve nihai yanıtla değiştirilir. Bayat-istek/Durdur/temizlik/backpressure davranışı korunur.
- **Stale `model_id` temizliği:** `tool_mode_config` içindeki `process` ve `app_expert` girişlerinden `model_id` kaldırıldı (model Langflow akışına gömülüdür). Hızlı eylemler ve Yapılandırma sayfası bu araçlar için yerel model değişimi tetiklemez; `build_main_actions_data_from_config()` Langflow araçlarına varsayılan model enjekte etmez.
- **Model rozeti gizleme:** Sohbet başlığındaki yerel model rozeti, aktif araç `runtime == "langflow"` olduğunda gizlenir (araç adına sabit kodlanmadan). Diğer tüm araçlarda rozet davranışı değişmez.
- **İkinci LLM uç noktası kaldırıldı:** `secondary_llm_endpoint`, `secondary_llm_api_key`, `LOCAL_LLM_ENDPOINT_ALT` ve `LOCAL_LLM_ENDPOINT_ALT_API_KEY` kavramları ve `LANGFLOW_API_KEY` için eski ALT-anahtar fallback'i tamamen kaldırıldı. Yalnızca tek birincil `LOCAL_LLM_ENDPOINT` kullanılır. `LANGFLOW_API_KEY` ayrıdır ve korunur.
- **Çoklu süreç akışı seçimi:** Süreç Yönetimi artık birden fazla adlandırılmış Langflow akışını destekler. Kullanıcı, sohbet giriş alanındaki (model seçicinin yanındaki) açılır menüden akış seçer (yalnızca Süreç Yönetimi aktifken görünür). Yapılandırma: `LANGFLOW_PROCESS_FLOW_IDS` ve `LANGFLOW_PROCESS_FLOW_NAMES` (";"/"," ayraçlı). Yeni frontend varlıkları: `www/js/process_tools.js`, `www/css/process_tools.css`.

Doğrulama: ilgili odaklı testler (Langflow runtime/handler davranışı, quick-actions, chat-outputs, API model config sözleşmesi, UI asset manifest/zone, frontend/maintainability ratchet) cloud `C.UTF-8` altında geçti. Gerçek Langflow uç noktası ve tarayıcı UX doğrulaması VM'de yapılmalıdır.


### 2026-06-27 İşlem-güvenli DB havuzu üretim sertleştirmesi (streaming yolu değişmedi)

Mevcut opsiyonel, işlem-güvenli DB bağlantı havuzu (`R/helpers_db_pool.R`)
**üretim-preflight'lanabilir** ve **daha gözlemlenebilir** hâle getirildi. Bu
çalışma gerçek-zamanlı streaming yolunu (SSE polling döngüsü, tarayıcı streaming
protokolü, `streamingDelta`/`streamingUpdate`/`premiumReasoningStreamStart`/
`streamingReasoningDelta`, stop/cancel anlamları) **bilinçli olarak değiştirmez**.

- **Fail-fast bayrağı (opsiyonel, varsayılan KAPALI):** `MERGEN_DB_POOL_FAIL_FAST`
  (env > R option `mergen.db.pool_fail_fast` > `FALSE`). KAPALI iken havuz
  başlatılamazsa davranış birebir eskisidir (fail-open: doğrudan-bağlantı yoluna
  düşülür). AÇIK iken `init_db_pool_once()` ve `app.R` `onStart` havuz
  kurulamazsa açıkça durur (operatörün seçimi).
- **İşlem-güvenliği hata düzeltmesi:** havuz aktif değilken `get_connection()`
  eski/geçersiz bir `Pool` nesnesi döndürebildiği nadir durumda,
  `db_acquire_tx_connection()` bu Pool'u `dbBegin/dbCommit`'e GEÇİRMEZ; tek bir
  gerçek `poolCheckout` yoluna yönlendirir (işlem ASLA Pool nesnesi üzerinde
  çalışmaz). Yazma yolu hatayı zaten yakalar.
- **/readyz gözlemlenebilirliği:** hazırlık uç noktası `db_pool` bloğu artık
  `fail_fast` dâhil sır-güvenli sayaçları (checkout/returned/`outstanding_checkouts`/
  tx/`init_failed`/`direct_fallback`...) yayınlar; ham DSN/secret içermez.
- **VM preflight (yeni):** `tests/scripts/run_vm_db_pool_preflight_real.R` havuz
  mekaniği + gözlemlenebilirlik + fail-fast davranışını gerçek SQL Server'a karşı
  doğrular (çoklu checkout/return döngüsü, commit/rollback, Türkçe round-trip).
  Varsayılan **yıkıcı değildir**; opsiyonel `MERGEN_DB_POOL_WRITE_TEST=TRUE` ile
  etiketli tablo + DROP üzerinden Türkçe at-rest kontrolü ekler. Kapsamlı at-rest
  encoding kapısı yine `run_vm_sqlserver_pool_preflight_real.R`'dir.
- **Testler:** `tests/testthat/test-db-pool-production-readiness-contract.R` ve
  `tests/testthat/test-db-pool-failure-modes.R` eklendi (snapshot tamlığı/
  kararlılığı/sır-güvenliği, fail-fast çözümü, Pool-into-transaction koruması,
  çift-iade, başarısız-init sonrası kararlılık). Maintainability ratchet 100/100
  korundu (`helpers_db_pool.R` net **0** fonksiyon eklendi).

**Kanıtlamaz:** kapasite/throughput kazanımı, gerçek tarayıcı/websocket
eşzamanlılığı, 1000 kullanıcı veya gerçek LLM iş hacmi. `MERGEN_DB_POOL_ENABLED=TRUE`
üretimde kalıcı açılmadan önce Windows VM doğrulaması (preflight'lar + SSMS Türkçe
at-rest + attach soak) gerekir. Ayrıntı: [`database-pooling.md`](database-pooling.md)
bölüm 8, [`operational-soak-gate.md`](operational-soak-gate.md) bölüm 16.5A.


### 2026-06-27/28 uzun split proxy soak ekran kanıtı: kapasite kapısı FAIL

Operatörün son ekran kanıtları iki split `proxy_llm` soak lane'i gösterir:
`http://127.0.0.1:8008/` için `artifacts/soak/20260627-180246/` ve
`http://127.0.0.1:8009/` için `artifacts/soak/20260627-180302/`. Bu raw JSON
artifact'ları bu checkout'ta bulunamadığı için değerler ekran transkripsiyonudur.
Operatör koşumu “375+375 / 18h” olarak tarif etti; artifact ekranları ise lane
başına 350 kullanıcı, hedef 86400 saniye ve yaklaşık 86497/86505 saniye gerçek
duvar süresi gösteriyor. Raw artifact daha sonra aksini kanıtlamadıkça artifact
değerleri kaynak gerçek kabul edilir.

| Lane | Profil | Kullanıcı | Duvar süresi | İstek | Başarı | Timeout | Effective success | Eşik | Sonuç | Baskın neden |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| 8008 | `proxy_llm` | 350 | ≈86496.9s | 627226 | 256467 | 370759 | ≈0.4089 | 0.98 | **FAIL** | `connection_timeout` baskın; `response_timeout=318` |
| 8009 | `proxy_llm` | 350 | ≈86505s | 627007 | 248673 | 378334 | ≈0.3965 | 0.98 | **FAIL** | `connection_timeout` baskın; `response_timeout≈398` |

Bu, uygulama doğruluğu/gizlilik/izolasyon arızası olarak değil, connection timeout
basıncı altında çöken bir kapasite/throughput kapısı başarısızlığı olarak
okunmalıdır. Ekranlarda server alive, errors=0, raw key/prompt leak=0, key routing,
cross-session isolation, key-owner mismatch reject, upload validation, Turkish+emoji
encoding helper round-trip, mojibake=0, redaction, interactive 50 session/400 action
(success ratio 1.0) ve DB pool checkout/return hygiene kontrolleri PASS görünüyor.
Buna karşın `loadgen_loop_lag_high` (`mean_loop_lag_ms≈21998`,
`max_loop_lag_ms≈61429`) baskın load-driver/generated-connection-pressure/proxy-lane
doygunluk sinyalidir. Bu artifact başarısız bir kapasite kanıtı fakat yararlı bir
negatif/diagnostic soak kaydıdır; 1000 gerçek aktif kullanıcı, real-LLM üretim
throughput'u, gerçek browser/websocket Shiny concurrency, SQL Server at-rest Türkçe
doğruluğu veya kapalı olan 50→100→250→500→1000 capacity ladder'ı kanıtlamaz.

### 2026-06-27 Yatay-ölçekleme commit'i sonrası Cumartesi doğrudan bölünmüş yük doğrulaması

Cumartesi 2026-06-27 doğrudan bölünmüş yük doğrulaması, IT gerçek Keycloak/
ters-vekil ön-kapı rotasını yük-dengelemeli URL olarak yapılandıramadığı için iki
yerel MERGEN arka uç worker'ı (`http://127.0.0.1:8008/` ve
`http://127.0.0.1:8009/`) üzerinden yapıldı. İki-worker doğrudan bölünmüş testler
**750 toplam aktif proxy kullanıcı / 30 dakika** seviyesine kadar (375+375) geçti;
iki koşum da PASS verdi ve hata/timeout sayısı sıfırdı. Bu, yatay-ölçekleme/
backlog hipotezini destekleyen arka uç bölünmüş yük kanıtıdır; üretim
`https://mergen.com.tr/bilge` URL'sinin zaten yük-dengelemeli olduğunu kanıtlamaz
ve 1000 gerçek kullanıcı, gerçek tarayıcı/websocket eşzamanlılığı veya gerçek LLM
sağlayıcı iş hacmi kanıtı değildir.


### 2026-06-27 Çalışma-zamanı performans/yatay-ölçekleme katmanı (425 bağlantı-timeout bulgusuna yanıt)

Önceki commit (bff7fad) yalnızca soak teşhis/gözlemlenebilirlik ekledi; bu
değişiklik **gerçek çalışma-zamanı uygulama davranışını** iyileştirir. Soak
kanıtı baskın hatanın **`connection_timeout`** (CPU düşük ~%21-29, app-port TCP
~425) olduğunu gösterdi; kök sayfa GET `/` zaten önbellekli ve attach seridi
yalnız GET olduğundan darboğaz **uygulama UI/oturum işi değil, TEK SÜRECİN httpuv
TCP kabul/backlog doygunluğudur**. Bunun dürüst çözümü yatay ölçeklemedir.

**Hiçbir soak eşiği düşürülmedi, kapasite-merdiveni/timeout-atfı/UNMEASURED
dürüstlüğü ve anahtar-izolasyon/upload/redaksiyon/DB-işlem/encoding kontrolleri
korundu.** Soak gate pass/fail mantığı DEĞİŞMEDİ.

- **Sağlık/hazırlık uç noktaları** (`R/helpers_app_http_routes.R`): `GET /healthz`
  (canlılık; küçük statik JSON, DB/oturum işi yok) ve `GET /readyz` (sır-güvenli
  hazırlık + gözlemlenebilirlik anlık görüntüsü). Yük-dengeleyici birden çok
  worker'ı bunlarla güvenle havuza alıp çıkarır. `uiPattern` yalnız `/`,
  `/healthz`, `/readyz` eşler; diğer yollar etkilenmez (gerçek sunucuda doğrulandı:
  `/foozzz` -> 404). `MERGEN_HEALTH_ENDPOINT=false` ile kapatılınca `ui` bayt-bayt
  korunur.
- **Çok-worker başlatıcı** (`tools/run_mergen_workers.R`): OPT-IN yatay ölçekleme.
  `MERGEN_WORKERS=N` ile her biri farklı `MERGEN_PORT`'ta N worker sürecini bir
  kurumsal ters-vekil/yük-dengeleyici (nginx/IIS ARR/HAProxy) arkasında başlatır;
  yalnızca mevcut `processx` kullanılır (CDN/ağır bağımlılık yok). **VARSAYILAN
  tek-süreç davranışı değişmez** (`MERGEN_WORKERS` ayarsızken 1 worker).
- **Backpressure (kabul-denetimi)** (`R/helpers_request_backpressure.R`): süreç-
  geneli, TTL-ile-kendi-iyileşen eşzamanlı pahalı-işlem üst-sınırı.
  **Varsayılan KAPALI** (`MERGEN_MAX_CONCURRENT_LLM=0` -> no-op; davranış bayt-bayt
  korunur). Açıkken sınır aşımı uzun gizli timeout yerine hızlı/dostça "sunucu
  yoğun" yanıtı verir; stop/iptal bozulmaz. `send_message` girişine güvenli
  bağlandı (tüm sonlandırma/iptal yollarında bırakılır + TTL güvenlik ağı).
- **Süreç-içi çalışma-zamanı metrikleri** (`R/helpers_runtime_metrics.R`): sır-
  güvenli sayaçlar (kök sayfa önbellek hit/miss, sağlık isabeti, backpressure
  admit/reject). Attach seridinin göremediği uygulama-içi davranışı `/readyz`
  üzerinden süreç dışına sır-güvenli açar.
- Kök sayfa önbelleği (`R/helpers_index_page_cache.R`) artık hit/miss sayar (sıcak
  isabette yeniden serileştirme YOK; sözleşmeyle korunur).

**VM koşumu rerun edilene kadar KANITLANMAZ:** 425 aktif proxy kullanıcının
`effective_success_rate >= 0.98`'e ulaşması; çok-worker topolojisinin gerçek
kabul-kapasitesi kazanımı; backpressure açıkken üretim UX'i. Bunlar Windows VM'de
kademeli merdiven (100,300,350,400,425) yeniden koşularak doğrulanmalıdır.


### 2026-06-27 Soak bağlantı-timeout teşhis sertleştirmesi (450 bulgusuna yanıt)

13A'daki 450-kullanıcı `connection_timeout` doygunluğunu (CPU düşük, app-port TCP
~425) bir sonraki VM koşumunda kesin teşhis edebilmek için operasyonel soak
gate'ine teşhis/gözlemlenebilirlik katmanı eklendi. **Hiçbir eşik düşürülmedi;
UNMEASURED kontroller hâlâ sessizce PASS sayılmaz; güvenlik/anahtar-izolasyon/
redaksiyon/upload/DB-işlem/encoding kontrolleri korundu.** Yalnız
`tests/scripts/soak_*.R` ve `tests/testthat/test-operational-soak-gate-contract.R`
değişti; çalışma zamanı uygulama kodu değişmedi.

- **Yük sürücüsü realizm anahtarları** (varsayılan = mevcut "burst" davranışı):
  `MERGEN_SOAK_RAMP_UP_SECONDS`, `MERGEN_SOAK_MAX_NEW_PER_TICK`,
  `MERGEN_SOAK_THINK_TIME_MS_MIN/_MAX`, `MERGEN_SOAK_CONNECTION_REUSE`. Arrival
  deseni (`burst`/`ramped`/`paced`/`ramped_paced`) ve anahtarlar `config.json` +
  `soak_evidence.json` içinde `load_driver` olarak raporlanır. Rampa ile 450
  timeout'u kaybolursa darboğaz "bağlantı fırtınası"dır; sürerse kararlı-durum.
- **TCP durum telemetrisi**: app-port `established/syn_sent/syn_recv/time_wait/
  close_wait/listen` maksimumları (`app_tcp_max_by_state`). `syn_recv` = kabul
  kuyruğu, `time_wait` = ephemeral-port baskısı göstergesi.
- **curl zamanlama**: `metrics.connect_ms_p95` vs `metrics.ttfb_ms_p95` (bağlantı
  fazı vs app işleme ayrımı).
- **Yük-üretici telemetrisi**: `http_loadgen` (max_inflight, loop lag, scheduled/s,
  `saturation_hint`) — darboğazın istemci/loop mu sunucu mu olduğunu ayırır.
- **Merdiven teşhisi**: `recommended_probe_steps` (300/450 → 350/400/425),
  `dominant_timeout_class`, `bottleneck_hint`, genişletilmiş `bottleneck_hints`
  (`possible_connection_accept_or_backlog_saturation` vb.).

Doğrulama: `tests/testthat/test-operational-soak-gate-contract.R` ve
`tests/testthat/test-soak-readiness-scripts-contract.R` (0 fail / 0 warn / 0 skip),
`bash tools/ai_validate.sh quick` (failed_steps=0, skipped_steps=0). Son
kanıtlanmış kilometre taşı hâlâ **300 aktif proxy kullanıcı / 90 dakika**'dır;
yeni VM komutları için `docs/operational-soak-gate.md` §17. Ayrıntı:
`docs/operational-soak-gate.md` §17.


### 2026-06-27 Operasyonel proxy attach soak gate bulguları: 300 stabil, 450 timeout doygunluğu

Kullanıcının paylaştığı Windows VM ekran görüntülerinden en son proxy attach soak
bulguları dokümante edildi. Artifact yolu ekran görüntülerinde
`artifacts/soak/20260626-212908/soak_evidence.json`; JSON `created_at` değeri
`2026-06-27T02:01:24Z`. Koşum `proxy_llm` / `MERGEN_SOAK_LLM_MODE=proxy`,
`http://127.0.0.1:8009/` attach, 50 aktif kullanıcı, 1000 kullanıcı tabanı hedefi,
18000 sn hedef süre ve açık kapasite merdiveni (`100,300,450,600,750`, 5400 sn/adım,
stabil eşik 0.98) ile yapılmış görünüyor. Genel sonuç **FAIL**: ana seri
`325001` istekte `276788` başarı ve `48213` timeout ile `effective_success_rate=0.8517`
üretti; başarısız eşikler `effective_success_rate` ve `capacity_ladder_all_steps_pass`.
Timeout attribution baskın olarak `connection_timeout=47763`, ayrıca
`response_timeout=450` gösterdi.

Kapasite merdiveni sonucu: 100 kullanıcı PASS (`191973/191973`, p95≈5018 ms),
300 kullanıcı PASS (`83335/83613`, timeout 278, effective≈0.9967, p95≈27566 ms),
450 kullanıcı FAIL (`450/49415`, timeout≈47935, effective≈0.03 / raw≈0.008,
p95≈44029 ms). Son stabil staged kapasite bu koşum için **300 aktif proxy kullanıcı /
90 dakika**; önerilen sonraki hedef 450 olarak kaldı, fakat 450 readiness değildir.
Darboğaz ipucu `timeout_saturation_without_clear_resource_signal`; CPU üst sınırı
yaklaşık %29, app port TCP bağlantısı yaklaşık 425 olduğundan takip işi connection
timeout/backlog/event-loop/TCP kabul kuyruğu tarafına odaklanmalıdır.

Olumlu kontroller de kaydedildi: etkileşimli lane `50` oturum / `400` eylemde
`400/400` PASS, DB havuzu checkout=return=`451`, outstanding=0, tx commit=200 ve
rollback=50; key routing `5/5`, cross-session isolation, upload validation `7/7`,
secret leak `0`, mojibake hits `0`, DB-encoding helper round-trip ve Türkçe+emoji
escape/restore round-trip PASS. `memory_growth_mb` ve `browser_console_errors` bu
koşumda UNMEASURED olduğu için PASS sayılmaz. Bu sonuçlar 1000 gerçek aktif insan,
gerçek LLM throughput'u, gerçek browser/websocket concurrency veya SQL Server at-rest
encoding kanıtı değildir. Ayrıntılar
[`operational-soak-gate.md`](operational-soak-gate.md#13a-2026-06-2627-windows-vm-proxy-attach-soak-failure-findings)
bölümüne işlendi.


### 2026-06-25 Operasyonel soak staged milestone güncellemesi

Windows VM'de hedefe tek seferde 1000 kullanıcıyla gitmek yerine kademeli milestone
yaklaşımı benimsendi. Son console observed bulgular: 50 aktif proxy kullanıcı /
1800 sn PASS (`artifacts/soak/20260625-111352`), 10 gerçek tarayıcı oturumu browser
concurrency lane PASS (`artifacts/browser-concurrency/20260625-115948`) ve kapasite
merdiveninde 100 ile 250 aktif proxy kullanıcı / 90 dk adımları PASS
(`artifacts/soak/20260625-121812`). Son stabil staged kapasite şimdilik 250 aktif
proxy kullanıcı / 90 dk; sıradaki hedef 500 adımıdır. Bu, 1.000 gerçek aktif insan
chat oturumu veya gerçek upstream LLM throughput'u kanıtı değildir.

2026-06-24 sertleştirmesi hiçbir eşiği düşürmeden ve UNMEASURED kontrolleri PASS
saymadan soak kapısına gerçek ölçüm ve kademeli yol ekledi:

- **Sistem telemetrisi** (`tests/scripts/soak_system_telemetry.R`): ayrı arka süreç
  CPU/bellek/TCP örnekler (Windows PowerShell, Unix `/proc`/`ps`/`ss`); yük seridini
  bloklamaz, OS sayaçları okunamazsa soak'u kırmaz (UNMEASURED). Artifact:
  `system_telemetry.csv`/`_summary.json`; evidence: `max_total_cpu_percent`,
  `max_*_memory_mb`, `max_tcp_connections_to_app`.
- **Kademeli kapasite merdiveni** (`MERGEN_SOAK_CAPACITY_LADDER`): 50->100->250->500->
  1000 adımları; ilk başarısız adımda durur; son STABİL adımı (`stable_capacity_users`),
  ilk başarısızı, önerilen sonraki hedefi ve korumacı darboğaz ipuçlarını raporlar.
  Artifact: `capacity_ladder.csv`/`_summary.json`. Eklenen
  `capacity_ladder_all_steps_pass` daha **katı** bir kontroldür (eşik düşürmez).
- **Hata atfı (timeout attribution)**: başarısızlıklar
  connection/response/app_http_error/fake_llm/proxy_llm/real_llm/rate_limited
  sınıflarına ayrılır; `failures.jsonl` artık `timeout_class`/`endpoint_kind`/
  `retryable` taşır; evidence: `timeout_attribution` (breakdown + en yaygın sınıflar
  + en yavaş senaryolar).
- **Gerçek tarayıcı/websocket lane** (`tests/scripts/run_browser_concurrency_lane.R`):
  N eşzamanlı gerçek headless tarayıcı oturumu; `browser_console_errors` artık bu lane
  çalıştığında ÖLÇÜLÜR (yoksa UNMEASURED). Kullanıcı tavanı 50; ağır bağımlılık eklenmez.
- **Havuzlu SQL Server at-rest preflight**
  (`tests/scripts/run_vm_sqlserver_pool_preflight_real.R`): havuz init/checkout-return/
  commit/rollback + Türkçe at-rest round-trip; bulut/offline'da güvenle atlar; yıkıcı
  değildir (etiketli tablo oluşturur ve DROP eder).
- **Gerçek LLM throughput ayrı tutulur**: real-canary aşama sınıflandırması
  (ERR-234 -> `gateway_policy_failed`, app yük hatası DEĞİL) + opsiyonel,
  kullanıcı-tavanlı küçük throughput probe. Fake/proxy serit asla gerçek LLM
  throughput'u olarak sunulmaz.

Tüm yeni artifact'lar redaksiyondan geçer (ham DSN/anahtar/secret yazılmaz). Staged VM
komut dizisi, telemetri yorumu ve CPU/çekirdek ölçeklendirme rehberi
[`docs/operational-soak-gate.md`](operational-soak-gate.md) bölüm 16'dadır. Sözleşme
testleri: `tests/testthat/test-operational-soak-gate-contract.R` (genişletildi) ve
`tests/testthat/test-soak-readiness-scripts-contract.R` (yeni). Bu, app dayanıklılığı
+ ölçüm kanıtıdır; 1000 gerçek sürekli insan oturumu, gerçek SQL Server üretim havuzu
at-rest hazırlığı (VM preflight gerekir) veya gerçek LLM throughput kapasitesi
değildir.

### 2026-06-22 İşlem-güvenli DB bağlantı havuzu + etkileşimli soak seridi

Bu sürüm iki operasyonel dayanıklılık zaafiyetini kapatır: (1) DB bağlantı
yönetiminin havuzsuz/placeholder olması ve (2) operasyonel soak kanıtının
GET-only HTTP seridine dayanması.

**İşlem-güvenli DB bağlantı havuzu (opt-in).** Yeni `R/helpers_db_pool.R`
katmanı `pool` paketi üzerine kurulur ve şu genel API'yi sunar:
`is_db_pool_enabled`, `db_pool_config`, `init_db_pool_once`, `close_db_pool_once`,
`with_db_connection` (salt-okunur), `with_db_transaction` (işlem-güvenli),
`db_acquire_tx_connection`/`db_release_tx_connection` ve secret-safe
`db_pool_status_snapshot`. Havuz **varsayılan KAPALI**'dır
(`MERGEN_DB_POOL_ENABLED`, varsayılan `FALSE`), bu yüzden bulut/test/boot
davranışı değişmez. Açıkken `app.R` `onStart`'ta bir kez başlatılır, `onStop`'ta
kapatılır. Okuma yolları değiştirilmemiş `get_connection()` üzerinden otomatik
havuzlanır; işlem sitesi `save_message_to_db()` gerçek `poolCheckout()` ile
işlem-güvenli checkout kullanır ve **bağlantıyı iade etmeden önce rollback**
çalıştırır (havuza açık işlemle dönüş engellenir). Encoding sözleşmesi korunur:
havuz `DB_CLIENT_ENCODING`/`DB_NAME_ENCODING` değerlerini ODBC bağlantısına
geçirir. `worker_save_assistant_response()` ayrı süreçte çalıştığı için doğrudan
`worker_db_connect()` kullanmaya devam eder. Ayrıntı:
[`database-pooling.md`](database-pooling.md).

**Etkileşimli (interactive) soak seridi.** Yeni `tests/scripts/soak_interactive_lane.R`,
GET-only HTTP seridinin açmadığı sohbet/DB/streaming/stop yollarını **gerçek DB
havuzu** üzerinde (RSQLite arka ucu) alıştırır: oturum açma + anahtar izolasyonu,
sohbet/mesaj yazma (`with_db_transaction`), gerçek streaming-delta sınıflandırma,
stop/iptal kararı + niyetli işlem ROLLBACK, dosya yükleme doğrulaması ve
kullanıcı-kapsamlı geçmiş okuma. `soak_evidence.json` artık bir `interactive_lane`
bloğu (oturum/eylem sayısı, DB havuz checkout/return/sızıntı/tx sayaçları,
izolasyon/rollback/upload/mojibake) ve `interactive_metrics.csv` üretir. HTTP
seridi `MERGEN_SOAK_HTTP_LANE=false` ile kapatılarak uygulamasız bulut kanıtı
alınabilir.

**Doğrulanan (bulut/offline).** `tests/testthat/test-db-pool-behavior.R` (54 PASS,
gerçek SQLite: enable/disable, once semantiği, ödünç/iade sızıntısızlığı,
commit/rollback yalıtımı, Türkçe round-trip, gerçek-checkout, secret-safe
snapshot). `test-maintainability-ratchet.R` 100/100 korundu. App boot smoke PASS.
`test-operational-soak-gate-contract.R` 157 PASS. Uygulamasız soak koşumu
(`MERGEN_SOAK_HTTP_LANE=false`, 15 oturum/120 eylem) **PASS**: checkout=return=121,
sızıntı=0, tx commit=45/rollback=15, izolasyon PASS, mojibake 0;
`effective_success_rate`/`no_server_crash` HTTP seridi kapalı olduğu için
`UNMEASURED`.

**Henüz kanıtlanmayan (Windows VM gerekli).** Havuzun SQL Server'a karşı üretim
doğrulaması: `MERGEN_DB_POOL_ENABLED=TRUE` ile VM'de
`run_vm_encoding_preflight_real.R` Türkçe at-rest yazımı, SSMS satır teyidi ve
attach soak sınır koşumuyla gerçek-sohbet kapasite farkı. Etkileşimli serit
tek-süreçte ardışık oturumlardır ve lane-yerel SQLite kullanır; gerçek
tarayıcı/websocket eşzamanlılığını veya SQL Server T-SQL davranışını kanıtlamaz.
Gerçek LLM üretim throughput'u ayrı bir konudur (real-canary upstream gateway
`ERR-234` ile bloke kalmaya devam eder).

Aşağıdaki bölüm, güncel değişiklik notlarını kronolojik/tematik bakım izi kaybolmadan izler.

### 2026-06-19 Windows VM post-index-cache operasyonel soak notu

Root-page/index caching optimizasyonu sonrası Windows VM konsolunda izole
`GET /` timing'i pre-cache yaklaşık 0.64 saniyeden warm cache yaklaşık 0.006-0.008
saniyeye düştü; cold build hâlâ `[PERF] event=index_render elapsed_ms=740
cache=miss_build bytes=311206` olarak gözlendi. Reproduction komutu:
``curl.exe -w "%{time_total}`n" -o NUL -s http://127.0.0.1:8009/``.

Tarihsel pre-index-cache fake-lane kanıtı 22 aktif eşzamanlı kullanıcı / 300 saniye
PASS idi (`artifacts/soak/20260619-153052/soak_evidence.json`). Index-cache sonrası
VM console observed en güçlü fake-lane gözlem artık 1000 aktif eşzamanlı kullanıcı /
420 saniye PASS'tir (`artifacts/soak/20260619-205535/soak_evidence.json`, p95=8377.8
ms, throughput=7931.4/dk, 0 hata, 0 timeout). Ayrıca 250 aktif kullanıcı / 420 saniye
PASS (`artifacts/soak/20260619-204704/soak_evidence.json`, p95=1983.8 ms,
throughput=8016.8/dk), 1000 kullanıcı / 30 saniye PASS
(`artifacts/soak/20260619-204455/soak_evidence.json`, p95=9427.6 ms,
throughput=8532.4/dk) ve stress/proxy final PASS
(`artifacts/soak/20260619-210427/soak_evidence.json`, p95=734.5 ms,
throughput=8029.2/dk) gözlendi.

Bu checkout içinde `artifacts/soak/...` JSON dosyaları bulunmadığı için yeni değerler
şimdilik **VM console observed** olarak belgelenir ve kanıt JSON ile yeniden
doğrulanmalıdır. `memory_growth_mb` ve `browser_console_errors` bu koşularda
`UNMEASURED` kaldığı için ölçülmüş PASS olarak yorumlanmaz. Bu kanıt GET-only
index-serving/fake-proxy soak yolunu güçlendirir; gerçek LLM/model üretiminin
hızlandığını, browser UX'in temiz olduğunu veya 1000 eşzamanlı gerçek insan chat
oturumunun desteklendiğini kanıtlamaz.


### Operasyonel soak / yük kapısı eklendi (fake/proxy/real-canary seritleri)

MERGEN Bilge'ye, uygulamanın operasyonel kırılganlığını kullanıcılar fark etmeden
önce keşfetmek için **operasyonel soak/yük kapısı** eklendi:
`tests/scripts/run_operational_soak_gate.R` (+ `soak_*` ve `mock_llm_server.R` /
`proxy_llm_server.R` yardımcı modülleri). Tam belge:
[`operational-soak-gate.md`](operational-soak-gate.md).

Tasarım üç **serit** üzerine kuruludur: **fake** (yerel OpenAI-uyumlu sahte LLM;
ana yüksek-eşzamanlılık seridi; sıfır gerçek anahtar), **proxy** (çok sayıda sahte
kişisel anahtarla kişisel/varsayılan/eksik anahtar yönlendirme ve oturumlar arası
izolasyon kanıtı; ham anahtar loglanmaz), ve **real-canary** (tek gerçek anahtar,
çok düşük eşzamanlılık). Bu ayrım bilinçlidir: tek gerçek geliştirici anahtarı
app-seviyesi soak'un darboğazı yapılmaz ve fake/proxy/canary koşumlarından gerçek
1.000 eşzamanlı kullanıcı hazırlığı iddia edilmez. "1.000 kullanıcı" bir kullanıcı
tabanıdır; ilk ciddi aktif-eşzamanlılık hedefi 50–100'dür.

Kapı VM kanıt kapısının yerine geçmez; ayrı ve tamamlayıcıdır. Profiller:
`smoke` (varsayılan), `pilot`, `org`, `stress`, `fake_llm`, `proxy_llm`,
`real_llm`. Fake/proxy sunucular `httpuv` + `promises` + `later` ile bloklamayan
gecikme uygular (tek thread'li event loop'ta gerçek eşzamanlılık); yük `curl`
multi-handle havuzuyla sürülür. In-process alıştırmalar uygulamanın gerçek
yardımcılarını çağırarak Türkçe/emoji DB-encoding round-trip'i, yükleme
doğrulayıcı kabul/ret kararlarını, anahtar kaynak sınıflandırmasını ve oturumlar
arası anahtar izolasyonunu doğrular. Yeni paket eklenmedi.

Dürüstlük sözleşmesi VM kanıt kapısıyla aynıdır: her zaman kanıt üretilir
(`artifacts/soak/<timestamp>/`), eşik **etkin başarı oranına** uygulanır (kasıtlı
enjekte edilen faultlar hariç → beklenmeyen başarısızlıkları ölçer), ölçülemeyen
eşikler sessizce geçmez (`UNMEASURED`/`skipped_checks`), ve artifact'lar ham
anahtar/token/sır içermeyecek şekilde redaksiyondan + redaksiyon kendi-doğrulamasından
geçer. Statik + offline sözleşme koruması:
`tests/testthat/test-operational-soak-gate-contract.R`.

### Windows VM evidence gate milestone: 13/13 adım geçti

MERGEN Bilge'nin on-prem Windows VM doğrulamasında major readiness milestone kaydedildi ve **15 Haziran 2026** tarihinde yeniden doğrulandı. `tests/scripts/run_vm_evidence_gate.R` tam koşumu başarılı tamamlandı: `Toplam: 13 passed, 0 failed, 0 skipped`. Güncel statü özellikle şu adımları içerir: `full_testthat PASSED`, `browser_ux_smoke PASSED`, `vm_preflight_real PASSED`, `db_encoding_preflight PASSED`.

Başarılı koşumda tam izole testthat suite'i, VM preflight, transactional DB encoding preflight ve mandatory browser UX smoke kanıtı aynı gate altında geçti. Browser proof external-app modunda alındı: app ayrı pencerede `http://127.0.0.1:28081` üzerinde çalışırken gate `MERGEN_BROWSER_UX_BASE_URL=http://127.0.0.1:28081` ve `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true` ile koşturuldu; browser smoke `UX_SMOKE_DONE:PASS` üretti. Son artifact: `artifacts/vm-evidence/20260615-130127/evidence.json`; genel kanıt konumu `artifacts/vm-evidence/<timestamp>/evidence.json`.

Bu milestone, release/readiness açısından güçlü bir VM kanıtıdır; ancak yalnızca kanıt içinde `passed` görünen adımlar için kanıt sayılır. Uzun süreli gerçek kullanıcı yükü, manuel kırılgan-akış QA'sı ve legacy DB satırlarının temizliği ayrıca değerlendirilmelidir. Operasyonel komutlar ve troubleshooting için [`../RUNBOOK.md`](../RUNBOOK.md) içindeki evidence gate bölümü izlenir.


### Karmaşıklık azaltma: plotly bağımlılığı çalışma zamanından tamamen kaldırıldı

Grafik render yolu highcharter'a indirildikten sonra plotly'nin tek kalan kullanımı, artık hiçbir grafik tarafından kullanılmayan bağımlılık-önyükleyiciydi. Bu önyükleyici de kaldırıldı: `R/server_outputs_downloads.R` içindeki `widgetDependencyOutputsInit()` artık yalnızca highcharter `deps_hc` yükleyicisini tanımlar (`deps_pl` ve kullanılmayan `plotly_html` çıktıları silindi) ve `ui.R` içindeki gizli `plotly::plotlyOutput("deps_pl")` yükleyicisi kaldırıldı. Sonuç olarak çalışma zamanı kodunda (`R/*.R`, `ui.R`, `server.R`) hiçbir plotly referansı kalmadı.

Davranış korunur: highcharter bağımlılık yükleyicisi (`deps_hc`) ve grafik render yolu değişmedi. Plotly zaten `required_packages` içinde değildi (opsiyonel yumuşak bağımlılıktı); on-prem `renv.lock`, plotly'yi düşürmek için VM tarafında yeniden snapshot edilmelidir (bulut oturumundan `renv.lock` üretilmez).

Koruma: `tests/testthat/test-downloads-outputs-behavior.R`, `widgetDependencyOutputsInit()`'in highcharter yokken hatasız çalıştığını ve hiçbir plotly çıktısı tanımlamadığını doğrular; `tests/testthat/test-chart-engine-highcharter-only-contract.R`'ye eklenen yeni tarama, tüm çalışma zamanı R + `ui.R` + `server.R` dosyalarında plotly kod referansı (`plotly::`, `plotlyOutput`, `renderPlotly`, `"plotly"`, `deps_pl`, `plotly_html`) bulunmadığını dondurur. Doğrulama: parse sanity + odaklı sözleşme/davranış testleri (`bash tools/ai_validate.sh cloud-quick`) yeşil; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Karmaşıklık azaltma: grafik render yolu tek motorlu (highcharter) hale getirildi

ChartLab grafikleri (`R/helpers_chartlab.R`) ve etkileşimli ChartLab modülü (`R/module_chartlab.R`) her zaman highcharter ile render edilir; eski `highcharter → plotly+ggplot2 → hata` fallback zinciri ulaşılamayan ölü koddu. Bu deployment'ta highcharter daima kuruludur (`ui.R` gizli bağımlılık yükleyicisi zaten `highcharter::highchartOutput` kullanır ve on-prem `renv.lock` highcharter'ı sabitler), dolayısıyla plotly+ggplot2 dalları gerçekte hiç çalışmıyordu.

Bu render geri dönüşü kaldırıldı: container seçimi artık highcharter varsa `highchartOutput`, yoksa `shiny::uiOutput`; `wire_chart_output()` / `render_one()` highcharter varsa `renderHighchart`, yoksa zarif bir `renderUI` hata mesajı üretir (çökme yok). Kullanılmayan `have_plotly_gg` / `have_highcharter` bayrakları `R/config_file_store.R`'den temizlendi. Toplam ~208 satır ölü/ulaşılamayan kod kaldırıldı (`helpers_chartlab.R` 449→345, `module_chartlab.R` 531→432, `config_file_store.R` −5); maintainability skoru 100/100 ve en büyük dosya metriği değişmedi.

Davranış korunur: canlı highcharter render dalı bu değişiklikle hiç değişmedi (kaynak düzeyinde highcharter render satırları HEAD ile birebir aynı). `R/server_outputs_downloads.R` + `ui.R` içindeki plotly bağımlılık-önyükleyicisine (`deps_pl`/`plotly_html`) dokunulmadı; bu ayrı bir önyükleme mekanizmasıdır ve `test-downloads-outputs-behavior.R` ile korunur. Plotly'yi tamamen kaldırmak (önyükleyici + highcharter'ı zorunlu pakete almak) ayrı bir takip işidir.

Koruma: yeni `tests/testthat/test-chart-engine-highcharter-only-contract.R` sözleşme testi, render dosyalarında plotly/ggplot2 render fallback işaretçilerinin (`plotly::`, `renderPlotly`, `ggplot(`, `geom_`, `have_pl(`) bulunmadığını, highcharter render yolunun (`highchartOutput`, `renderHighchart`) ve highcharter-yoksa zarif hata davranışının korunduğunu dondurur. Mevcut ChartLab/MCP grafik testleri yeşil kalır (81 geçti, 8 atlandı — atlananlar zaten highcharter/plotly kurulu olmayan ortamda atlanan testler). Doğrulama: parse sanity + odaklı sözleşme testleri (`bash tools/ai_validate.sh cloud-quick`) yeşil; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Karmaşıklık azaltma: Yapılandırma ayarları UI'si odaklı kart yapıcılarına bölündü

Ayarlar sayfasının "Yapılandırma" alt sekmesi UI'si tek bir 710 satırlık `settingsYapilandirmaUIImpl(id)` fonksiyonuydu; kod tabanındaki en büyük tek fonksiyondu ve gezinmesi zordu. Bu fonksiyon artık ince bir kompozitör olup her ayar kartını odaklı, saf bir `.syap_*(ns)` yapıcısına delege eder: `.syap_header_row`, `.syap_model_card`, `.syap_api_key_card`, `.syap_tools_card`, `.syap_claude_code_card`, `.syap_interface_shortcuts_row`, `.syap_audio_card`, `.syap_ai_expert_card`, `.syap_image_card`, `.syap_summarization_card`, `.syap_analysis_card`.

Bu yalnızca okunabilirlik (bilişsel yük) iyileştirmesidir; davranış birebir korunur. Bölme öncesi ve sonrası render edilen HTML **bayt-bayt aynıdır** (30.629 karakter) ve sunucuya bağlanan 47 Shiny input/output kimliğinin tümü değişmeden kalır. Dosya tek dosyada tutulduğu için kaynak manifesti, yükleme sırası veya yeni dosya sözleşmeleri etkilenmez. Fonksiyon başına bilişsel yük 1×710 satırdan 1 kompozitör + 11 küçük yapıcıya indi; dosya 710 → 758 satır oldu (raporun en büyük dosya metriği 760'ta kaldığından gerileme yoktur) ve maintainability skoru 100/100 korunur.

Koruma: yeni `tests/testthat/test-settings-yapilandirma-ui-id-surface-behavior.R` karakterizasyon testi UI'yi render edip 47 kimliğin tamamını, tüm kart başlıklarını ve özel yapıları (model `data-model-meta`, eşit yükseklik satırı, araç seçici, derin düşünme anahtarı) dondurur; herhangi bir kimliğin düşmesi/yeniden adlandırılması testi kırar. Mevcut `test-settings-yapilandirma-ui-refactor-contract.R` sözleşme testi yeşil kalır. Doğrulama: parse sanity + odaklı sözleşme testleri (`bash tools/ai_validate.sh cloud-quick`) yeşil; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Karmaşıklık azaltma: oluşturulan görsel kartı HTML'i tek kanonik yardımcıda toplandı

Oluşturulan görsel kartı işaretlemesi (görsel + `MERGEN Bilge` filigranı + indir/kopyala/yazdır butonları + isteğe bağlı açıklama) üç ayrı yerde birebir aynı şekilde tekrarlanıyordu: `R/module_image_generation.R` içindeki `render_generated_image_html()` ve `render_image_from_saved_path()` ile `R/helpers_chat_message_formatting.R` içindeki `db_message_render_image_html()` (kaydedilmiş söyleşi yeniden yükleme yolu). Bu çoğaltma, kart işaretlemesinde (buton ekleme, kaçış düzeltmesi, filigran metni) yapılacak her değişikliğin üç yeri birden gerektirdiği bir bakım ve XSS sınır riskiydi.

İşaretleme artık tek kanonik saf yardımcıda toplanır: `mergen_generated_image_card_html()`, `R/helpers_markdown_safety.R` içinde. Yardımcı `message_id` ve `description` değerlerini HTML kaçışına tabi tutar; çağıran tarafça güvenli kabul edilen `img_src`'yi `src` içine olduğu gibi yerleştirir. Her üç tüketici de kart işaretlemesini bu yardımcıya delege eder. Yardımcı, `R/helpers_chat_message_formatting.R` ve `R/module_image_generation.R`'den önce yüklenir.

Davranış korunur: kart çıktısı aynıdır. Tek fark, görsel oluşturma yolundaki kartlarda `message_id` artık (sohbet biçimlendirme yolunda zaten olduğu gibi) HTML kaçışına tabi tutulur; gerçek `message_id` değerleri ASCII zaman damgası/numara olduğu için bu, çıktıyı değiştirmeyen bir güvenlik sıkılaştırmasıdır. `db_message_render_image_html()` içindeki "dosya bulunamadı"/"yüklenemedi" yer tutucu dalları kasıtlı olarak farklıdır (görsel ve buton içermez) ve yerel kalır. Sonuç olarak `R/module_image_generation.R` 765 → 723 satıra inerek sıfır olan baş boşluğunu geri kazandı; maintainability skoru 100/100 korunur.

Koruma: yeni `tests/testthat/test-generated-image-card-html-contract.R`, hem yardımcının XSS-güvenli kart sözleşmesini dondurur hem de kart buton işaretlemesinin (`image-action-btn-modern`) yalnızca kanonik yardımcıda kalıp tüketicilerde yeniden inline edilmediğini doğrular. Mevcut `test-image-generation-module-behavior.R` ve `test-chat-message-formatting-refactor-contract.R` davranış testleri yeşil kalır. Doğrulama: parse sanity ve odaklı sözleşme testleri (`bash tools/ai_validate.sh cloud-quick`) çalıştırıldı; tam runtime/app boot, tarayıcı UX ve Windows VM/SSO/DB doğrulaması bu bulut oturumunda yapılmadı.

### Görsel yükleme/önizleme, görsel anlama (vision), toast süresi, Yenile butonları ve renv bağımlılık kilidi

Dosya Yönetimi ve Ana Söyleşi yükleme alanlarında görsel dosyalar (JPG, JPEG, PNG, GIF, WEBP, BMP, SVG) artık yüklenebilir ve tabloda listelenir; desteklenmeyen tür diske kopyalanmadan önce reddedildiği için "kaydedildi ama görünmüyor" sızıntısı giderildi. Yüklenen görseller Dosya Yönetimi önizlemesinde artık doğrudan görüntülenir. **Görsel anlama (vision) artık desteklenir:** Model Bağlamı'na eklenen bir görsel, seçili model görsel girişini (Image Input) destekliyorsa yapay zekâ isteğine OpenAI uyumlu çok-kipli (multimodal) parça olarak eklenir ve içeriği sorulabilir; model desteklemiyorsa metin yolu korunur ve açık bir Türkçe not eklenir. Hangi modellerin görsel desteklediği, yetenek tablosundan (model kataloğunda "Image Input" işaretli olanlar) belirlenir; dağıtımda `MERGEN_VISION_MODELS` ortam değişkeni (ve Kodlama Uzmanı derin düşünme modelleri) ile sürülür ve `MERGEN_ENABLE_VISION=false` ile tümüyle kapatılabilir (varsayılan açık, yetenek-öncelikli). Aynı oturumda yüklenen görsel için ardışık sorular da desteklenir; görsel anlama hattı, yeniden giriş gerektirmeden mevcut oturum dosya kaydını koruyarak sonraki sorularda aynı görseli tekrar isteğe ekleyebilir. Toast bildirimleri sabit kısa süre yerine mesaj uzunluğuna göre 5–12 sn görünür. Söyleşi Geçmişi, Kayıtlı Söyleşiler, Görsel Galerisi ve tüm Yönetici/Sistem Durumu sayfalarındaki "Yenile" butonları Dosya Yönetimi ile aynı koyu/açık tema stiline getirildi.

Ayrıca uygulama artık `renv` ile bağımlılık kilidi kullanır: `R/config_packages.R` insan-okunur manifest olarak kalır, kesin sürümler `renv.lock` içinde sabitlenir. Kilit dosyası çalışan Windows VM (R 4.6.0) ortamında `Rscript tools/renv_snapshot.R` ile üretilir; kök `.Rprofile` offline/üretim güvenlidir (renv yalnızca kilit ve dolu proje kütüphanesi hazırsa etkinleşir, aksi halde global kütüphaneyle normal çalışır). **Gerçek `renv.lock`, uygulamayı çalıştıran şirket içi (on-prem) Windows VM üretim deposunda commit edilmiştir; çevrimiçi GitHub deposunda (Claude Code / Codex bulut oturumlarının gördüğü kopyada) bilinçli olarak BULUNMAZ.** Bu yüzden bir bulut checkout'unda `renv.lock` görünmemesi normaldir, eksiklik değildir; `RENV_LOCK_STATUS.md` yalnızca bu durumu belgeleyen işaretçidir. Ayrıntı: `docs/dependency-locking.md`.

### Karşılama ekranı açık tema cilası

Ana Söyleşi modern karşılama ekranında açık tema cam yüzeyleri yeniden dengelendi. Karşılama kartı daha geçirgen bir glassmorphism görünümüne çekildi; hızlı işlem kartları solid beyaz yerine açık temanın sıcak krem/yellowish zeminine uyumlu cam yüzeylerle yumuşatıldı. Kişisel selamlama başlığındaki kontrast iyileştirildi ve sağdaki nöral ağ animasyon zemini açık tema paletiyle uyumlu hale getirildi. Nöral ağ etkileşimi de yalnızca animasyon bölgesi içindeki imleç hareketlerine tepki verecek şekilde sınırlandı; video, hızlı başlangıç kartları ve tarayıcı dışına/ikinci ekrana çıkış durumlarında son imleç noktası artık düğümleri çekmeye devam etmez.

### Destek ve Yenilikler ekranları açık tema cilası

Destek alanındaki açık tema deneyimi daha okunabilir ve tutarlı hale getirildi. “Geri Bildirim & Hata” sayfasındaki 0-10 NPS puan düğmelerinin pasif kenarlıkları açık temada görünür olacak şekilde netleştirildi. “Yenilikler” sayfasında sürüm rozetleri ve kart içi “Yeni” rozeti için yüksek kontrastlı açık tema stilleri tanımlandı; sürüm seçici rozetleri gerçek sınıfı olan `.destek-surum-tab` üzerinden kapsanır.

“Yenilikler” sayfasında üst bölümün daha kullanışlı kalması için hero alanı ve sürüm rozetleri sabit kalacak, yalnızca alttaki sürüm kartı alanı dikey kaydırılacak şekilde düzenlendi. Sürüm bildirim rozetindeki ince parlayan kenar efekti korunurken standart `mask` bildirimi WebKit uyumluluk bildirimiyle birlikte kullanılır; böylece GitHub uyarısı anlaşılır hale gelirken mevcut görsel UX kaybedilmez.

“Yardım Merkezi” içindeki Yardım Asistanı sohbetinde açık tema balon kontrastı iyileştirildi. Kullanıcı mesaj balonu, tema token’ındaki `--mb-brand-support-teal` rengiyle yeşil/teal yüzey alır; bot yanıtları açık kart yüzeyinde okunabilir kalır. Bot yanıtlarında Markdown’dan gelen `<strong>`, italik, başlık, liste ve satır içi kod içerikleri açık temada kontrast sorunları oluşturmadan gösterilir.

### Yardım Merkezi açık tema sohbet cilası

Yardım Merkezi içindeki Yardım Asistanı sohbet ekranında açık tema okunabilirliği güçlendirildi. Kullanıcı mesaj balonu artık kurumsal destek teal tonu (`--mb-brand-support-teal`) üzerinden belirgin bir yüzey kullanır; bot yanıtları ise açık temada okunabilir kart yüzeyiyle ayrışır. Markdown kaynaklı kalın metinler (`<strong>`), vurgu, başlık, liste ve satır içi kod görünümleri açık zeminde kontrast kaybetmeyecek şekilde dengelendi. Değişiklik yalnızca açık temaya uygulanır; koyu tema davranışı korunur.

### Yardım Merkezi e-posta kodlama düzeltmesi

Yardım Merkezi içindeki “E-posta Destek” bağlantısının konu ve gövde alanları artık UTF-8 bayt temelli percent-encoding ile oluşturulur. Bu sayede Outlook/mailto açılışında “İyi çalışmalar dilerim,” gibi Türkçe karakter içeren varsayılan destek metinleri Windows yerel kod sayfasına bağlı bozulmadan doğru gösterilir. Düzeltme yalnızca bağlantı üretim sınırını etkiler; Yardım Merkezi’nin görünümü ve kullanıcı akışı değişmez.

### Unicode test fikstürlerinde platform kararlılığı

DB Unicode kaçış davranışını doğrulayan odak testleri, konsol veya işletim sistemi kod sayfasına bağlı bozulmaları önlemek için artık emoji ve Latin-1 kapsamındaki örnek karakterleri kaynak içinde doğrudan taşımak yerine `intToUtf8(as.integer(codepoint))` ile deterministik olarak üretir. Bu düzenleme yalnızca test fikstürlerinin platformlar arası kararlılığını güçlendirir; DB istemci kodlaması, `[[MERGEN-U+...]]` kaçış biçimi, okuma sınırında geri açma davranışı ve görünür kullanıcı deneyimi değişmez.

### LLM araç sonuçlarında veri önizleme kararlılığı

LLM ikinci geçişine aktarılan MCP araç sonuçlarında dataframe önizlemesi artık Türkçe alan adı kodlamasına daha dayanıklıdır. MCP/LLM araç sonucu dataframe önizleme çıkarımı `R/helpers_llm_worker_tool_results_preview.R` içinde izole edilmiştir; bu küçük helper `sonuç_önizleme`, `sonuc_onizleme` ve `preview` alanlarını tek noktadan çözer. `R/helpers_llm_worker_tool_results.R` araç sonucu biçimlendirme sorumluluğunda kalır ve maintainability ratchet fonksiyon bütçesini korur.

Bu değişiklik görünür kullanıcı akışını değiştirmez. Araç sonucu hâlâ “VERİTABANINDAN GELEN GERÇEK VERİ” başlığı, markdown tablo, dönen satır/sütun bilgisi, `source_table` uyarısı/değer listesi ve boş dataframe uyarısı sözleşmesini korur. Amaç, Excel Analizi ve SQL/MCP araç çıktılarında ikinci LLM sentez geçişine giden gerçek veri bağlamını daha deterministik hâle getirmektir. Bu sınır `test-maintainability-ratchet.R`, `test-source-manifest-contract.R` ve `test-llm-worker-tool-results-refactor-contract.R` kapsamıyla korunur.

### API anahtarı seçim modalı kararlılık ve tarayıcı hijyeni

Kişisel API anahtarı bulunmayan kullanıcılar için gösterilen “API Anahtarı Seçimi” onboarding modalı, Shiny özel mesaj işleyici sözleşmesine ve tarayıcı parola-formu beklentilerine uyumlu olacak şekilde güçlendirildi. İstemci tarafındaki yardımcı artık Shiny mesajlarını tek argümanlı handler’larla karşılar, kontrol yüzeyini handler kayıtlarından önce hazırlar ve yalnızca hassas olmayan `api_key_onboarding_suppressed` tercih bayrağını bildirir.

Modal içindeki API anahtarı alanı görünür kullanıcı akışını değiştirmeden non-submit form içinde, `autocomplete="new-password"` ve gizli `username` alanı ile render edilir. Böylece Chrome DevTools parola-formu verbose uyarıları kaldırılırken aynı input id’leri, kaydet/temizle düğmeleri, kurum anahtarıyla devam akışı ve güvenli anahtar saklama/doğrulama sınırı korunur. Ham API anahtarı, varsayılan kurum anahtarı veya herhangi bir secret istemciye yazılmaz ve loglanmaz.

### TTS ve AI Uzman için kurum anahtarı uyumu

Sohbet dışı ses akışları artık sohbetle aynı etkin API anahtarı çözümleme sözleşmesini kullanır. `R/helpers_feature_api_key.R`, kişisel anahtar, özellik-özel servis anahtarı, izinli varsayılan kurum anahtarı ve eski fallback anahtarı küçük ve merkezi bir yardımcıyla çözer.

Bu sayede kişisel API anahtarı bulunmayan ve “Varsayılan kurum API anahtarıyla devam et” seçeneğini kullanan kullanıcılar için normal sohbetin yanı sıra “Yanıtları Seslendir” ve “AI Uzman Konuşması” da aynı kurumsal anahtar akışıyla çalışır. Değişiklik görünür kullanıcı deneyimini değiştirmez; ham anahtarlar istemciye, loglara veya doğrulama raporlarına yazılmaz.

### SSO güvenliği ve Türkçe yol dayanıklılığı

SSO güvenlik sınırı güçlendirildi: Keycloak üzerinden gelen JWT token’ları artık claim değerleri güvenilir kabul edilmeden önce JWKS genel anahtarlarıyla kriptografik olarak doğrulanır. `SSO_VALIDATE_SIGNATURE=TRUE` güvenli varsayılandır; gerekirse `SSO_JWKS_URL` ile JWKS uç noktası elle verilebilir ve `SSO_JWKS_CACHE_TTL` ile anahtar önbellek süresi yönetilir. Yetkilendirme tarafında DB bağlantısı veya sorgu hatası oluşursa erişim fail-closed biçimde reddedilir; hata durumunda varsayılan kullanıcı yetkisi verilmez.

Türkçe karakter içeren Windows/VM yol sınırları için mojibake tespiti ve onarımı merkezi yardımcılar üzerinden korunur. `R/utils_text_encoding.R` ve `R/utils_path_helpers.R` davranışları; `test-sso-jwt-signature.R`, `test-sso-authorization-failclosed.R`, `test-sso-signature-parsing.R` ve `test-path-helpers-mojibake-behavior.R` odaklı davranış testleriyle güvence altına alınmıştır. Bu güncelleme görünür kullanıcı akışını değiştirmekten çok üretim güvenliği, kodlama bütünlüğü ve işletim güvenilirliğini artırır.

### Davranışsal test kapsamının genişletilmesi ve iki gizli hata düzeltmesi

Modül ve çalışma-zamanı mantığı için davranışsal (input→output) test kapsamı belirgin biçimde genişletildi. Daha önce yalnızca yapısal/sözleşme tarayıcılarınca (kaynak sırası, fonksiyon varlığı, ratchet) anılan ama gerçek davranışı doğrulanmayan kaynaklar için; gerçek bir DB/LLM/tarayıcı gerektirmeyen, deterministik ve çevrimdışı testler eklendi. Bu çalışmada 23 yeni `tests/testthat/test-*-behavior.R` dosyası ve yaklaşık 442 doğrulama (assertion) eklendi; hepsi tekil ve toplu koşumda 0 hata / 0 uyarı / 0 atlama ile geçti.

Kapsama alınan başlıca alanlar:

- Modül davranışları: Dosya Yönetimi istemci ek-durum kaydı ve DT tablo runtime'ı, STT modal aç/iptal/onayla akışı ve paket kilidi, ChartLab otomatik grafik türü/eksen tahmini, Görsel Oluşturma çeviri kapısı/koruma yolları/HTML üretimi ve XSS kaçışı, Derin Uzay giriş ekranı UI ve deneyim-modu eşlemesi, AI Uzman `can_speak` kapısı ve konuşma akışı, Yönetici Hata Analizi sekme UI'si ile durum/öncelik etiket+renk eşlemesi.
- Saf yardımcılar: Türkçe büyük/küçük harf dönüşümü ve kimlik çözümü, müzik URL'lerinde UTF-8 percent-encoding (Ü→%C3%9C; native %DC asla üretilmez), sohbet okuyucularındaki kullanıcı-id/zaman damgası mantığı, mesaj/Markdown→HTML işleme, sürüm geçmişi yol çözümleyici, kenar çubuğu kullanıcı baş harfleri/avatarı, modern karşılama UI oluşturucuları, toleranslı takip-sorusu bayrağı, dosya içeriği okuma, sağlık paneli biçimlendiricileri, gerekli paket doğrulaması, Bilge Yolaç metin/UTF-8 normalize ve çıktı biçimleme, log dizini/eşiği çözümleyicileri ve rozet HTML üreticileri.

Bu kapsam çalışması sırasında, yalnızca yapısal kapsama sahip olduğu için gözden kaçmış **iki gerçek gizli hata** tespit edilip cerrahi biçimde düzeltildi ve birer regresyon testiyle korunmaya alındı:

- `R/module_chartlab.R` → `make_id()`: `as.integer(as.numeric(Sys.time()) * 1000)` ifadesi 32-bit tamsayı aralığını aştığı için her grafik eklemede `NA` üretiyor ve "NAs introduced by coercion" uyarısı çıkarıyordu; grafik kimliği zaman damgasını kaybediyordu. `sprintf("%.0f", ...)` ile taşmasız tam sayısal damgaya çevrildi (davranış ve satır bütçesi korunur).
- `R/helpers_db_chat_readers.R` → `.db_chat_as_numeric_timestamp()`: `as.POSIXct()` ayrıştırılamayan bir metinde uyarı değil **hata** fırlattığından, fonksiyonun tasarlanan `0` güvenli geri dönüşü ulaşılamıyor ve sohbet listesi sıralaması bozuk bir zaman damgasında çökebiliyordu; `tryCatch(..., error = NA)` ile `0` geri dönüşü güvenceye alındı.

Bu değişiklikler yalnızca test ve iki nokta atışı düzeltmedir; görünür kullanıcı deneyimi, kodlama sözleşmeleri ve kaynak sırası değişmez. Testler `new.env(parent = globalenv())` ile yalıtılır, ağ/DB/LLM gerektirmez ve Türkçe açıklamalarla yazılmıştır.

### DOCX önizleme yarış koşulu ve yeni davranış testleri

Büyük DOCX dosyalarının önizleme modalında asenkron base64 hazırlama sonucu artık oturum belirteciyle korunur. `R/module_file_preview.R` içindeki `docx_preview_seq` değeri her DOCX modal açılışında artırılır; başarı ve hata geri çağrıları yalnızca kendi açılış belirteci hâlâ güncelse `docx_preview_container` alanına yazar veya toast gösterir. Böylece önce açılan büyük bir DOCX dosyasının geç gelen sonucu, daha sonra açılan başka bir DOCX modalını ezmez. Eski sonuçlar kullanıcı arayüzüne basılmaz; uygun olduğunda yalnızca önbelleğe alınır.

Bu sınır `tests/testthat/test-file-preview-docx-async-clobber-behavior.R` ile korunur. Test gerçek büyük dosya gerektirmez; `future::future` deterministik biçimde stub'lanır ve olmayan bir datapath üzerinden asenkron dal tetiklenir.

Aynı güncellemede davranışsal test kapsamı da genişletildi: `call_llm_with_retry`, DER/TLV yardımcıları, dosya deposu mutasyon yardımcıları, kenar çubuğu kullanıcı paneli, Claude runtime kaynak dizini çözümleme ve DB kullanıcı profili okuma davranışları için çevrimdışı ve deterministik testler eklendi. MCP dosya çözümleyicide mutlak yol güvenlik sözleşmesi de kırılgan İngilizce debug metnine değil, kalıcı davranışa bağlandı: normal kullanıcı akışında mutlak dosya yolu argümanları kabul edilmez ve Türkçe ret mesajı korunur.

### Servis bağımlı davranış testleri ve API anahtarı kayıt kararlılığı

Servis bağımlı ve derin runtime alanları için çevrimdışı, deterministik davranışsal regresyon kapsamı genişletildi. Yeni testler gerçek DB, tarayıcı, LLM veya ağ bağlantısı gerektirmeden stub/mock verilerle çalışır; amaç görünür kullanıcı deneyimini değiştirmek değil, mevcut çıktı sözleşmelerini ve hassas yardımcı davranışlarını refaktörlere karşı korumaktır.

Kapsama alınan başlıca alanlar; Yönetici Paneli grafik ve tabloları (Genel Bakış, Gelişmiş Analizler, Geri Bildirim, Sohbet Kalitesi, YZ Performansı, Zaman Analizi ve Hata Detayı ekleri), Sistem Durumu probe/UI oluşturucuları, Bilge Yolaç eklenti paneli, dosya deposu ve SQL loader yardımcıları, UI asset manifest yardımcıları, destek/geri bildirim DB yardımcıları, görsel galeri akışları, MCP/Excel araç biçimlendiricileri, PK/RLS yetki çözümleme yardımcıları, modern karşılama hızlı işlem butonları ve worker monitor defteri davranışlarıdır.

Ayrıca kişisel API anahtarı kaydında aralıklı görülebilecek bir tuz üretimi hatası cerrahi biçimde giderildi. `openssl::rand_bytes()` tarafından üretilebilen `0x00` baytları, hash yolunda `rawToChar()` nedeniyle `embedded nul in string` hatasına yol açabiliyordu; `save_user_api_key()` artık tuzdaki NUL baytlarını hash öncesinde `0x01` değerine eşleyerek mevcut şifreleme/doğrulama akışını korur ve kayıt işleminin rastlantısal olarak çökmesini engeller.

### Asenkron istek güvenliği, giriş ekranı tutarlılığı ve dosya listesi yenileme

Görsel üretimi ve özetleme gibi uzun sürebilen asenkron işlemlerde bayat istek sonuçlarının yeni kullanıcı isteğinin arayüzünü, sohbet durumunu veya yazıyor göstergesini ezmemesi için aktif istek kimliği ve durdurma durumu denetimi güçlendirildi. Bu davranış, gerçek LLM, görsel servisi, DB veya tarayıcı gerektirmeyen deterministik davranış testleriyle korunur.

Derin Uzay giriş ekranında “girişi atla” akışı, deneyim modu seçim akışıyla aynı persona/nöral renk güncellemesini gönderecek şekilde hizalandı. Böylece seçili veya varsayılan persona rengi, giriş animasyonu atlandığında da nöral animasyon tarafında tutarlı uygulanır.

Dosya Yönetimi başlığına “Yenile” düğmesi eklendi. Bu düğme mevcut kalıcı kullanıcı klasörü okuma mekanizmasını kullanarak dosya tablosunu yeniden yükler; “Tümünü Temizle” akışı korunur. Koyu ve açık tema stilleri ayrı tutulur; yeni buton kırmızı temizleme aksiyonundan görsel olarak ayrışır.

Aynı kapsamda, Bilge Yolaç doküman yardımcılarının izole test/debug kaynaklama sırasında repo kökü, tests/testthat çalışma dizini ve MERGEN_REPO_ROOT ortam değişkeni üzerinden güvenli fallback yapması belgelenen sözleşmeye uygun hale getirildi. API model/araç runtime ayrımından sonra taşınan yardımcılar için davranış testlerinin doğru kaynak dosyasını yüklemesi sağlandı.

## AI Ajanları İçin Doğrulama Profilleri

MERGEN Bilge üzerinde Codex veya Claude Code gibi AI ajanları işlem yaptığında doğrulama komutları ortam yeteneklerine göre ayrılmıştır:

- Tam bağımlılıkların kurulabildiği yerel/CI ortamlarında normal hızlı doğrulama: `bash tools/ai_validate.sh quick`
- Runtime, SSO, DB, streaming, kaynak sırası veya üretim VM etkili riskli değişikliklerde güçlü doğrulama: `bash tools/ai_validate.sh full --boot-smoke`
- Codex/Claude bulut ortamlarında ağır derleme gerektiren paketler nedeniyle tam runtime doğrulama mümkün olmadığında bulut uyumlu geri dönüş doğrulaması: `bash tools/ai_validate.sh cloud-quick`

`cloud-quick` modu, `duckdb`, `arrow`, `odbc` ve `pool` gibi ağır/runtime kaynak paketlerinin bulut ortamında uzun süren derlemelerine takılmamak için tasarlanmıştır. Bu mod, app source smoke / tam runtime boot doğrulamasını bilinçli olarak atlar; parse sanity ve odak sözleşme testlerini çalıştırır. AI ajanları `cloud-quick` kullandığında bunun tam runtime/VM doğrulaması olmadığını açıkça belirtmelidir.

Yalnızca `README.md` / `CLAUDE.md` dokümantasyon değişikliklerinde R doğrulaması çalıştırılmaz; yalnızca markdown farkı incelenir.

### Kaynak manifesti CRLF parse kararlılığı

Kaynak manifesti parse doğrulaması, Windows CRLF ve eski Mac CR satır sonlarını gerçek LF karakterine normalize edecek şekilde güçlendirildi. Böylece geçerli çok satırlı R dosyaları doğrulama sırasında literal "n" karakterleriyle bozulmaz ve "unexpected symbol" türü hatalı parse sonuçları üretilmez. Değişiklik yalnızca manifest parse doğrulama sınırını etkiler; görünür kullanıcı akışı ve uygulama davranışı değişmez.

### Teknik güncelleme özeti

- **Açılış ve medya hazırlığı:** Açılış ilerleme çubuğu artık pseudo/zaman bazlı dolum yerine gerçek boot kontrol noktaları ve medya tamponlama ilerlemesiyle ilerler. Karakter videoları ve karşılama arka plan videoları sırayla tarayıcı HTTP önbelleğine ısıtılır; yüzde 100, medya/kimlik/dosya indeksi hazır olduğunda anlamlıdır. Bilge Yolaç CLI bağlantı testi de açılış kritik yolundan ertelenerek ilerleme çubuğunu dondurmaması sağlanmıştır.

- **Erişilebilirlik:** Ana söyleşi giriş alanı, ikon-yalnız kontroller, açılır menüler ve toast bildirimleri ekran okuyucu erişilebilirliği için `aria-label`, `aria-hidden`, `role` ve `aria-live` sözleşmeleriyle güçlendirildi. Gönder/Durdur düğmesinin erişilebilir etiketi, düğmenin aktif moduna göre güncellenir.

- **Tanılama ve güvenilirlik:** Yakalanmamış Shiny hataları ve true streaming kullanıcı mesajı DB kaydetme hataları artık sır-redakteli `[RUNTIME_ERROR]` kayıtlarıyla tanılanabilir. Bu değişiklik görünür kullanıcı akışını değiştirmekten çok üretim ortamında hata kök nedeni bulma kabiliyetini artırır.

- **Claude Code / Codex bulut bootstrap dayanıklılığı:** Claude Code web oturumları için `SessionStart` hook ve bulut `Setup Script` yolu netleştirildi. RSPM indirme yönlendirmesi nedeniyle `rspm-sync.rstudio.com` allowlist gereklidir; installer gerçek paket indirmesini doğrular ve gerekirse CRAN'a düşer. Bu alan uygulama runtime/VM/DB/SSO kanıtı değil, bulut bootstrap sürecini kolaylaştıran altyapıdır.

- **Davranışsal test kapsamı:** App loading/boot readiness, health, support, chat actions/search/export, admin UI/analytics/error analysis, image generation, STT, ChartLab, AI Expert, user identity, messaging render, DB chat readers, logging resolvers, music URL encoding ve version history resolver gibi çok sayıda modül ve yardımcı için çevrimdışı, deterministik davranışsal test kapsamı genişletildi. Ayrıca `message_search` `gregexpr` uyarısı, DB chat timestamp parsing güvenli varsayılanı ve ChartLab milisaniye ID overflow uyarısı gibi küçük cerrahi düzeltmeler testlerle korunur.

### Sürüm geçmişi dosya yolu çözümleme kararlılığı

`version_history.md` dosyası repo kökünde kalır; `R/config_version_history.R` içindeki `resolve_version_history_md_path()` önce mevcut çalışma dizinindeki yerel `version_history.md` dosyasını dikkate alır, sonra üst dizinlere doğru arama yapar. Bu davranış, `tests/testthat` altından çalışan sürüm etiketi testlerinin repo kökündeki gerçek dosyayı bulmasını sağlarken, `getwd()` altında sentetik `version_history.md` oluşturan ayrıştırma testlerinin kendi geçici dosyalarını kullanmasını korur; boş/geçici dizinde dosya yoksa beklenen uyarı ve varsayılan sürüm davranışı korunur. Görünür kullanıcı arayüzü değişikliği yoktur.

### Davranışsal test kapsamı güncellemesi

`32dd9afd0d993e3590b51db296999c9ca78dd1af` güncellemesi, görünür kullanıcı akışını değiştirmeden odaklı davranışsal regresyon kapsamını genişletti. Kapsam; AI Uzman metin parçalama davranışı, API anahtarı kimlik ve varsayılan kurum anahtarı çözümleme sınırı, Bilge Yolaç plugin bileşen tespiti, prompt yol güvenliği ve araç kullanımı HTML kaçışlama sınırı, derin düşünme model çözümleme, araç türü tespiti, dosya indeksi ipuçlu arama, Sistem Durumu saf biçimlendiricileri, LLM/SSE kaynak ayrıştırma ve kaynakça üretimi, araç sonucu kısa yanıt biçimlendirme, log redaksiyonu iç yardımcıları, kullanıcı ve global hız sınırlama, metin/kod ayrıştırma, özetleme kullanıcı promptu üretimi ve sürüm geçmişi ayrıştırma alanlarını korur. Bu odak testler, ürün davranışını sabit tutarken ilerideki refaktörlerin güvenli yapılmasına yardımcı olur.

`517f80406badfd8f393f9e0648793c3481520ea7` / PR #425 güncellemesi, 31.05.2026 Pazar günü eklenen 19 committen gelen 25 odak davranışsal regresyon test dosyasını yalnızca ekleme olarak ekledi; görünür ürün davranışını doğrudan değiştirmez. Kapsam kompakt olarak API anahtarı sahipliği, etkin anahtar önceliği, uç nokta/kimlik geri dönüşü ve araç modu model çözümlemesini; Bilge Yolaç model/konfigürasyon, doküman ayrıntı düzeyi, indirmeler, çalışma deposu taraması, akış ayrıştırıcıları, güvenlik ilkesi, yol kanonikleştirme ve oturum runtime deposunu; UTF-8, mojibake, mailto kodlama, DB görünür/teknik normalizasyon, metin/log/ağaç işaretleme, atomik yazımlar ve ortak metin yardımcılarını; yükleme doğrulayıcı iç guard'ları, MCP Excel özet/adayları, MCP UNC yol normalizasyonu ve Proje/Kaynak Analizi çekirdek yardımcılarını; AI Uzman telaffuz düzeltme, persona kimliği göçü, LLM streaming delta/reasoning çıkarımı, streaming olmayan metin paketi çıkarımı, hızlı aksiyon tanıtım mesajları ve sürüm geçmişi etiket kaynağını korur.

`tests/scripts/ci_install_packages.R` için Linux paket tipi sözleşmesi ayrıca statik olarak korunur: varsayılan `pkgType` değeri Linux ortamında `source` kalmalı, `MERGEN_AI_R_PKG_TYPE` yalnızca açıkça verildiğinde (`source`/`binary`) override edilmelidir. Bu sözleşme `tests/testthat/test-ai-package-bootstrap-contract.R` ile izlenir ve `tools/setup_ai_r_environment.sh` içindeki RSPM denetimi kırılgan token eşleştirmeleriyle değil, kararlı URL parçaları (`__linux__/noble/latest`, `__linux__/jammy/latest`) üzerinden doğrulanır.

### Windows VM test kapsamı ve UTF-8 yol/anahtar kararlılığı

Windows VM üzerinde daha önce ortam gerekçesiyle atlanan bazı odak testler artık gerçek koşum kapsamına alınmıştır. SQL loader saf yardımcı testleri, `query_library` varlığı nedeniyle helper fonksiyonların dosya sonunda temizlenmesine takılmamak için kaynaklama sınırını izole eder. Plotly zarif-düşüş testi, VM’de `plotly` kurulu olsa bile fallback dalını lexical `requireNamespace()` mock’u ile doğrular. `safe_windows_short_path()` için Windows’a özel davranış artık atlanmaz; boş yol, olmayan yol ve var olan geçici dosya senaryoları gerçek Windows ayracı davranışıyla test edilir.

Aynı kapsamda kişisel API anahtarı şifreleme/çözme sınırı Türkçe karakterler için güçlendirildi: anahtar metni şifreleme öncesinde açıkça UTF-8 baytlarına çevrilir ve çözme sonrası metin UTF-8 olarak geri işaretlenir. Windows kısa yol yardımcısı da tek ters slash ayracını doğru biçimde `/` standardına çevirir. Bu güncelleme görünür kullanıcı akışını değiştirmez; Windows VM’de test güvenilirliğini, Türkçe karakter bütünlüğünü ve yol normalizasyon sözleşmesini güçlendirir.

Sıkı offline runtime sözleşmesini yerel/VM koşumuna dahil etmek için:
- `Sys.setenv(MERGEN_STRICT_OFFLINE_TESTS = "true")`
- ardından ilgili `testthat::test_file(...)` veya tam `testthat::test_dir("tests/testthat")` koşumu çalıştırılır.

Yalnızca dokümantasyon değişikliklerinde R doğrulaması çalıştırılmaz; markdown farkının incelenmesi yeterlidir.

### Doğrulama doktoru

Profil karışıklığını azaltmak için hafif bir doğrulama rehberi eklenmiştir: `tests/scripts/validation_doctor.R` ve kolaylık sarmalayıcısı olarak `tools/validation_doctor.sh`. Bu yol ağır test çalıştırmaz; uygulamayı, gerçek DB bağlantısını veya tarayıcıyı başlatmaz. Bunun yerine ortam sınıflandırmasını, tarayıcı ikilisi bulunabilirliğini, hassas ortam değişkenlerini yalnızca var/yok, uzunluk ve boolean-tarzı metaveriyle (ham değer olmadan), önerilen komut sırasını, her komutun neyi kanıtlayıp neyi kanıtlamadığını ve bloklayıcı/uyarı niteliğindeki kontrolleri raporlar.

Temel kullanım:

- `Rscript tests/scripts/validation_doctor.R --profile cloud`
- `Rscript tests/scripts/validation_doctor.R --profile local`
- `Rscript tests/scripts/validation_doctor.R --profile vm`
- `Rscript tests/scripts/validation_doctor.R --profile all`
- `bash tools/validation_doctor.sh --profile all`
- `bash tools/validation_doctor.sh all`

Çıktı ayrıca `artifacts/validation-doctor/` altında küçük bir JSON özet artifact’i üretir. Bu rehber özellikle `cloud-quick` sonucunun tam runtime, gerçek browser veya VM/SSO/SQL Server doğrulaması gibi yorumlanmasını engellemek için kullanılmalıdır. Son proof-status güçlendirmesiyle doktor çıktısı/artifact’i `doctor_runs_heavy_checks=false`, `validation_execution_status="not_run_by_validation_doctor"` ve `doctor_execution_notes` alanlarını da açıkça taşır; bu kayıtlar artifact’in yürütüm kanıtı değil profil rehberi olduğunu belirtir. Gerçek güvence yine ilgili profillerin kendisinden gelir: `bash tools/ai_validate.sh cloud-quick`, `bash tools/ai_validate.sh quick`, `bash tools/ai_validate.sh full --boot-smoke`, `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke`, VM preflight scriptleri, SQL Server Türkçe kodlama preflight ve manuel fragile-flow kanıtı ayrı ayrı çalıştırılıp değerlendirilmelidir.

AI validation yürütüm artifact’i olan `artifacts/ai-validation/<timestamp>/summary.json`, doktor artifact’inden ayrı değerlendirilmelidir. Bu dosya `profile_requested`, `profile_effective`, `validation_execution_status`, git branch/SHA/dirty çalışma ağacı özeti, `focused_contract_tests_status`, `full_testthat_suite_status`, `cloud_quick_validation_status`, `quick_repo_validation_status`, `full_validation_status`, `app_source_smoke_status`, `app_boot_smoke_status`, `browser_ux_smoke_status`, `browser_required`, VM/SSO/DB ve SQL Server Türkçe kodlama preflight durumları, manuel fragile-flow durumu, `failed_step_labels`, `skipped_step_labels` ve `proof_boundary_notes` alanlarını taşır. Bu alanlar ham DSN, endpoint, token, key, secret, password, cookie veya auth header değeri yazmamalıdır.
Son sözleşme güçlendirmesi: `tests/testthat/test-validation-doctor-contract.R`, doğrulama doktorunun ham secret-benzeri ortam değerlerini sızdırmamasını daha sıkı korur. `LOCAL_LLM_ENDPOINT`, `MERGEN_BROWSER_BIN`, DSN, URL, anahtar, token, secret ve parola benzeri değerler yalnızca `present`, `nchar`, boolean/metaveri ve `value=<hidden>` biçiminde raporlanmalıdır. Aynı sözleşme `cloud-quick` yolunun `tools/ai_validate.sh` içinde yalnızca `quick` repo profiline bağlanan bir sarmalayıcı alias olarak kalmasını; `tests/scripts/ai_repo_check.R` içine ayrı bir üçüncü profil olarak taşınmamasını korur. Bu güçlendirme çalışma zamanı kullanıcı deneyimini değiştirmez; yalnızca doğrulama profillerinin yanlış yorumlanmasını azaltır.

### Codex bulut çıktılarının yorumu

Codex/AI bulut ortamındaki `cloud-quick` sonucu yararlıdır; ancak tek başına kurum içi çalışma zamanı doğrulamasının yerine geçmez. Bu ortamda `git status --short` çıktısının temiz olması yalnızca yerel çalışma ağacında değişiklik olmadığını gösterir; `origin` remote yoksa veya fetch yapılamıyorsa checkout'ın güncel GitHub `main` ile aynı olduğu kanıtlanmış sayılmaz. Böyle bir durumda çelişkili Codex çıktıları `STALE/INCONCLUSIVE` olarak değerlendirilmelidir.

### Yanlış doğrulama iddialarını önleme

- Gerçek yürütüm kanıtı yalnızca `artifacts/ai-validation/<timestamp>/summary.json` içindeki `ai_validate` özetidir.
- `artifacts/validation-doctor/` altındaki `validation_doctor` artifact’i yalnızca rehberdir; `validation_execution_status=not_run_by_validation_doctor` ve `doctor_runs_heavy_checks=false` alanları bunun yürütüm kanıtı olmadığını açıkça belirtir.
- `cloud-quick` sonucu yalnızca kendi hafif kapsamı için geçerlidir; full validation, app boot, browser UX, VM/SSO/DB, SQL Server Türkçe kodlama veya manual fragile-flow kanıtı olarak raporlanmamalıdır.
- Answer self-check, kanıt alanlarıyla çelişen “Full validation passed”, “All validation gates passed” ve “Validation doctor passed” gibi geniş iddiaları yakalayacak şekilde güçlendirilmiştir.
- Dokümantasyon-only değişikliklerde R doğrulaması çalıştırılmamalıdır; yalnızca metin farkı gözden geçirmesi yeterlidir. Kod/doğrulama mantığı değişirse ilgili `ai_validate` profilleri ayrı kanıt olarak çalıştırılmalıdır.

### Codex ve VM kanıtı birlikte nasıl yorumlanır

Codex/cloud ortamında `cloud-quick` sonucunun başarılı olması yararlı fakat sınırlı bir kanıttır. Bu sonuç yalnızca bulut-uyumlu parse ve odak sözleşme kapsamı için geçerlidir; app source smoke, Shiny HTTP boot, gerçek tarayıcı UX smoke, VM/SSO/DB, SQL Server Türkçe kodlama veya manuel kırılgan akış kanıtı yerine geçmez. Codex ortamında `quick` veya `full --boot-smoke` ağır paket bootstrap/derleme yoluna girip tamamlanamazsa, bu tek başına VM doğrulamasını geçersiz kılmaz; yalnızca Codex tarafında ilgili kanıt üretilmediği anlamına gelir.

Runtime, SSO, DB ve Türkçe SQL Server kodlama sınırları için yetkili kanıt VM üzerinde alınan sonuçlardır. VM tarafında `bash tools/ai_validate.sh quick`, `bash tools/ai_validate.sh full --boot-smoke`, `tests/scripts/run_vm_preflight_real.R` ve `MERGEN_PREFLIGHT_DB_ENCODING_WRITE_TEST=TRUE` ile `tests/scripts/run_vm_encoding_preflight_real.R` başarıyla geçtiyse, Codex `cloud-quick` sonucu yalnızca ek/supplementary kanıt olarak yorumlanmalıdır. `validation_doctor` çıktısı ise her durumda rehberdir; yürütüm kanıtı olarak raporlanmamalıdır.

Başarılı bir `cloud-quick` koşumunda beklenen özet şudur: `environment: OK`, `parse sanity: OK`, `app source smoke: SKIPPED`, `focused contract tests: OK`, `failed_steps: 0`, `skipped_steps: 1`. Bu sonuç yine de tam runtime boot, gerçek tarayıcı, VM/SSO, gerçek DB veya SQL Server Türkçe kodlama doğrulaması anlamına gelmez.

Son doğrulama kanıtı güncellemesiyle `artifacts/ai-validation/<timestamp>/summary.json` dosyası artık istenen profil ile etkin profil ayrımını ve hangi ağır kapıların gerçekten çalışmadığını daha açık gösterir. Cloud ortamında normal `quick` koşumu ağır/runtime paketleri (`arrow`, `duckdb`, `odbc`, `pool`, `shinyWidgets` vb.) nedeniyle app source smoke aşamasında durursa, `cloud-quick` güvenli geri dönüş yolu kullanılabilir. Bu durumda `failed_steps=0`, `skipped_steps=1`, `profile_requested="cloud-quick"`, `profile_effective="quick"` ve `app_source_smoke_status="skipped"` sonucu yalnızca parse/contract kapsamı için geçerli kanıttır; tam runtime, app boot, browser UX, VM/SSO/DB, SQL Server Türkçe kodlama veya manuel fragile-flow doğrulaması olarak yorumlanmamalıdır. Windows VM/RStudio altında child `Rscript.exe` environment probe aşamasında çökerse bu, uygulama regresyonu değil yerel doğrulama çalıştırma ortamı sınırlaması olarak raporlanmalı; ilgili VM/runtime kanıtı ayrı kapılarla alınmalıdır.

`R/helpers_db_connection.R` için güncel sözleşme, `odbc` ve `pool` paketlerinin top-level `library()` ile zorunlu yüklenmemesidir. Bu sayede `cloud-quick` ağır DB runtime paketlerine takılmadan test bootstrap yolunu source edebilir. Gerçek DB bağlantısı açan fonksiyonlar kendi içinde `requireNamespace()` ile net hata vermeye devam eder; VM/SSO ve SQL Server güvencesi ayrıca VM preflight scriptleriyle alınmalıdır.

Kurum içi sunucu/VM testleri başarıyla geçtiyse ve Codex bulut çıktısı checkout, remote veya bootstrap kısıtları nedeniyle çelişkili görünüyorsa, çalışan kurum içi kod yalnızca Codex çıktısı yüzünden değiştirilmemelidir. Önce Codex'in hangi commit'i ve hangi artifact'i kullandığı kanıtlanmalıdır.


### Tarayıcı UX smoke kapsamı

En kırılgan istemci tarafı akışları için hafif gerçek tarayıcı smoke yolu korunur. `www/smoke/ux-smoke.html`, aynı origin üzerinde çalışan uygulamayı iframe içinde açar ve smoke-only `www/smoke/ux-smoke-probes.js` yardımcısını yükler. Başarılı koşumun son işareti `UX_SMOKE_DONE:PASS` olmalıdır.

Bu smoke yolu; streaming init/delta/stale requestId/finalize yaşam döngüsünü, tehlikeli HTML benzeri içeriğin etkin HTML'e dönüşmemesini, action button geri dönüşünü, follow-up pending temizliğini ve yinelenen asistan mesajı oluşmamasını doğrular. Ayrıca TTS/STT müzik duck sahipliği, tek arka plan müzik kaynağı, kayıtlı sohbet yüklenirken eski TTS'in otomatik başlamaması, Bilge Yolaç ↔ Ana Söyleşi geçişinde aktif panel sızıntısı, URL hash sızıntısı, modal/backdrop kalıntısı ve audio/TTS sahipliği dahil stale tool/page state kalmaması, welcome video'nun gereksiz destroy/reinit edilmemesi ve `Türkçe_çalışma_özeti_İstanbul.pdf` gibi Dosya Yönetimi görünen adlarının sentetik yenilemede okunabilir kalması kapsanır.

Son güçlendirme: UX smoke kapsamı yalnızca çalıştırılmakla kalmaz; `tests/testthat/test-ux-smoke-browser-contract.R` ve `tests/testthat/test-browser-smoke-harness-contract.R` ile açık belirteçler üzerinden kilitlenir. Bu sözleşmeler parçalı streaming içinde `<script>`, `<img onerror>` ve `javascript:` benzeri tehlikeli içeriklerin etkin HTML'e dönüşmeden görünür metin olarak kalmasını; finalize sonrası state, eylem düğmeleri ve takip sorusu temizliğini; TTS/STT duck sahipliğini; Bilge Yolaç ↔ Ana Söyleşi geçiş temizliğini; welcome video destroy/reinit sayaçlarını ve sentetik Dosya Yönetimi Türkçe görünen ad yenilemesini korur.

Tarayıcı UX smoke doğrulaması iki katmanlıdır: `bash tools/ai_validate.sh full --boot-smoke` önce normal Shiny boot smoke adımını çalıştırır, ardından yerelde Chrome/Chromium/Edge ikilisi bulunursa `tests/scripts/ai_browser_ux_smoke.R` ile sunulan `/smoke/ux-smoke.html` rotasını headless tarayıcıda koşar. Gerçek tarayıcı koşumunda beklenen son işaret `UX_SMOKE_DONE:PASS` değeridir.

Normal `--boot-smoke` profilinde tarayıcı ikilisi bulunamazsa browser UX adımı bloklayıcı olmayan SKIP (exit 0) olarak geçebilir. Tarayıcının zorunlu olduğu VM/yerel senaryolarda bloklayıcı mod kullanılmalıdır: `MERGEN_REQUIRE_BROWSER_UX_SMOKE=true bash tools/ai_validate.sh full --boot-smoke` veya `Rscript tests/scripts/ai_browser_ux_smoke.R --require-browser`. Varsayılan keşif yolları dışında kurulumlarda açık tarayıcı yolu `MERGEN_BROWSER_BIN="/path/to/chrome-or-msedge"` ile verilebilir.

Bu yol üretim kullanıcı deneyimini değiştirmemelidir. Smoke arayüzleri yalnızca test amaçlı ve isim alanlıdır: `window.MergenStreamingSmoke`, `window.MergenAudioLifecycleSmoke`, `window.MergenWelcomeVideoSmoke`, `window.MergenUxSmokeProbes`. `www/smoke/ux-smoke-probes.js` üretim varlık manifestine (`R/config_ui_assets.R`) eklenmemelidir. Runner yalnızca yerel tarayıcı ikililerini kullanır; CDN, runtime download, npm, Playwright, Selenium, chromote veya RSelenium gibi ağır/harici otomasyon bağımlılıkları eklenmemelidir.

Doğrulamada yerel/VM sonucu esas alınır: `bash tools/ai_validate.sh quick`, `bash tools/ai_validate.sh full --boot-smoke` ve aynı-origin `/smoke/ux-smoke.html` koşumu `UX_SMOKE_DONE:PASS` ile tamamlanmalıdır. Linux/RSPM paket bootstrap yolunda varsayılan paket türü güvenli source-style kurulumdur; `MERGEN_AI_R_PKG_TYPE` yalnızca açık override olarak kullanılmalıdır. Codex/Claude bulut ortamlarında R paket bootstrap aşaması testler başlamadan önce `arrow`, `duckdb`, `odbc`, `pool`, `shinyWidgets` gibi paketlerde başarısız olursa bu durum kod/test hatası değil, ortam/bootstrap kısıtı olarak raporlanmalıdır.

Son kabul notu: bu güncelleme sonrasında gerçek tarayıcı smoke koşumu `UX_SMOKE_DONE:PASS` işaretiyle tamamlanmış ve tüm `testthat` testleri başarıyla geçmiştir. Gelecek riskli/runtime etkili değişikliklerde aynı güven düzeyi için `bash tools/ai_validate.sh full --boot-smoke`; normal hızlı doğrulamada ise `bash tools/ai_validate.sh quick` kullanılmalıdır.

---
---

## Yapay Zekâ Söyleşi Deneyimi

- Ana Söyleşi, hızlı eylem kartları, model bağlamı, canlı düşünce akışı, reasoning model davranışı ve kaydedilmiş sohbet geri yükleme notları bu değişiklik notları ile [`technical-reference.md`](technical-reference.md) içinde izlenir.
- Araç bazlı model çözümleme, düşünme modelleri ve LLM işçi çıktısı önizleme kararlılığı korunması gereken davranışsal sınırlar olarak [`../CLAUDE.md`](../CLAUDE.md) içinde otoritatif kalır.

## Görsel Yükleme, Görsel Anlama ve Dosya Akışları

- Görsel yükleme/önizleme, desteklenen görsel türleri, model bağlamına görsel ekleme ve `MERGEN_VISION_MODELS` ile sürülen model yetenekleri bu değişiklik notlarında izlenir.
- Görsel anlama ayrı bir dar kurulum dosyasına ayrılmadı; mimari bağlamı [`architecture-map.md`](architecture-map.md), operasyonel yapılandırma/troubleshooting bağlamı [`../RUNBOOK.md`](../RUNBOOK.md) ve ayrıntılı teknik referans [`technical-reference.md`](technical-reference.md) içinde tutulur.

## Dosya Yönetimi ve Önizleme

- Dosya Yönetimi, önizleme, kullanıcı izolasyonu, geçici dosya yaşam döngüsü, güvenli yol çözümleme, DOCX önizleme yarış koşulu ve dosya listesi yenileme notları korunmuştur.
- Dosya deposu sağlık kontrolleri ve üretim yolu yapılandırması için [`../RUNBOOK.md`](../RUNBOOK.md) okunmalıdır.

## API Anahtarı, Güvenlik ve SSO

- API anahtarı seçim modalı, kişisel/kurumsal anahtar önceliği, TTS/AI Uzman anahtar çözümleme davranışı ve servis bağımlı test caveat'leri burada özetlenir.
- Gerçek API anahtarları, token'lar, parolalar, DSN'ler veya özel uç noktalar bu belgede tutulmaz. Yapılandırma örneği için [`../.Renviron.example`](../.Renviron.example) yalnızca şablon olarak kullanılmalıdır.

## Türkçe Karakter, Kodlama ve Windows VM Kararlılığı

- Türkçe karakter bütünlüğü, mojibake önleme, DB read/write normalizasyonu, mailto kodlama, Windows-1254/UTF-8 sınırı, UNC yol ve SSO profil davranışları güvenlik-kritik kabul edilir.
- Kodlama sınırlarının otoritatif sözleşmesi [`../CLAUDE.md`](../CLAUDE.md), operasyonel bakım yönergeleri [`../RUNBOOK.md`](../RUNBOOK.md), mimari özet ise [`architecture-map.md`](architecture-map.md) içindedir.

## UI, Tema ve Erişilebilirlik İyileştirmeleri

- Açık tema karşılama ekranı, neural pointer sınırı, Destek/Yenilikler açık tema kontrastı, NPS düğmeleri, rozetler, yardım sohbeti balonları, toast davranışı ve tarayıcı konsol hijyeni notları bu değişiklik notlarında izlenir.
- Frontend asset sırası ve UX smoke sınırları için [`../CLAUDE.md`](../CLAUDE.md) ve [`architecture-map.md`](architecture-map.md) birlikte okunmalıdır.

## TTS, STT ve Ses Akışları

- TTS/STT, AI Uzman konuşma üretimi, chunking, audio ducking ve kaydedilmiş sohbet TTS autoplay sınırları değişiklik notlarında korunur.
- Anahtar çözümleme ve secret safety kuralları runtime sözleşmesi olarak [`../CLAUDE.md`](../CLAUDE.md) içinde kalır.

## Bilge Yolaç / Claude Code Alanı

- Bilge Yolaç web oturumları, güvenli CLI çalıştırma, çalışma dizini seçimi, plugin sistemi, doküman çıkarımı/indirme ve stream-poll davranışı derin dokümanlarda izlenir.
- Mimari harita, eklenti dizinlerini ve çalışma zamanı sınırlarını özetler; sıkı güvenlik sözleşmeleri için [`../CLAUDE.md`](../CLAUDE.md) esas alınır.

## Test, Doğrulama ve Maintainability

- `bash tools/ai_validate.sh quick`, `cloud-quick`, validation doctor, browser UX smoke, maintainability ratchet, frontend complexity doctor ve kanıt dürüstlüğü notları README yerine bu belge, [`../RUNBOOK.md`](../RUNBOOK.md) ve [`../CLAUDE.md`](../CLAUDE.md) altında izlenir.
- `cloud-quick` çıktısı, ağır runtime package bootstrap ve app source smoke kapsamı çalışmadan elde edilmiş olabilir; bu nedenle tam VM/üretim doğrulaması gibi sunulamaz.

## Dependency Locking / renv

- `R/config_packages.R` insan-okunur paket manifestidir; kesin sürüm kilidi Windows VM/on-prem kuralına bağlı `renv.lock` ile yönetilir.
- Bulut checkout'unda `renv.lock` bulunmaması bilinçli olabilir; ayrıntı [`../RENV_LOCK_STATUS.md`](../RENV_LOCK_STATUS.md) ve [`dependency-locking.md`](dependency-locking.md) içindedir.

## Bilinen Sınırlar ve Kanıt Dürüstlüğü

- README'deki eski PR tarzı doğrulama günlükleri, kullanıcıyı ilk girişte yormamak için buraya taşındı.
- Yalnızca gerçekten çalıştırılan komutların sonucu “geçti” olarak ifade edilir.
- Codex/Claude cloud kanıtı ile Windows VM/on-prem kanıtı aynı şey değildir; özellikle DB, SSO, encoding, UNC path, paket kilidi ve tarayıcı smoke alanlarında sınırlar açıkça belirtilmelidir.