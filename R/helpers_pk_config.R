# ==============================================================================
# Dosya Yolu: R/helpers_pk_config.R
# Açıklama: Proje ve Kaynak Analizi yapılandırma çözümleyicisi. Bu araçtaki
#           hiçbir eşik/zaman aşımı/sınır sabit kodlanmaz; tümü tek bir
#           öncelik sırasıyla çözülür:
#
#             sorgu bazlı metadata -> .Renviron ortam değişkeni -> options()
#             -> yerleşik varsayılan
#
#           Dosya BİLEREK saf ve worker güvenlidir: Shiny/reactive/DB/ağ
#           bağımlılığı yoktur ve ortam değerleri future worker içinde
#           doğrudan Sys.getenv() ile okunur (kapanış serileştirilmez).
#
# Not: Bu dosya yalnızca gerçekten TÜKETİLEN anahtarları kaydeder. Örneğin
#      MERGEN_PK_FILTER_TIMEOUT_SEC burada YOKTUR; onu v1'de tüketmek motorun
#      filtre sonuçlarını değiştirirdi ve bu, master planın §10 motor sınırı
#      sözleşmesine aykırıdır.
# ==============================================================================

# Desteklenen anahtarların tek kaynağı. Yeni faz yeni anahtar eklerken bu
# listeye girdi ekler; çözümleyici kodu değişmez.

# Yerelden BAĞIMSIZ ASCII küçük harf (makine/protokol belirteçleri için).
# Ortak yardımcı `R/helpers_pk_text_turkish.R` içindedir; bu dosya izole
# testlerde tek başına source edilebildiği için yerel bir yedeği vardır.
.pk_config_ascii_lower <- function(x) {
  if (exists("pk_ascii_lower", mode = "function", inherits = TRUE)) return(pk_ascii_lower(x))
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", as.character(x))
}

pk_config_spec <- list(
  MERGEN_PK_ENGINE = list(
    type = "character",
    default = "v1",
    allowed = c("v1", "v2")
  ),
  MERGEN_PK_TELEMETRY = list(
    type = "logical",
    default = TRUE
  ),
  MERGEN_PK_LOG_QUESTION_TEXT = list(
    type = "logical",
    default = FALSE
  ),
  # Gizli değer: yalnızca varlığı/uzunluğu raporlanabilir, değeri asla loglanmaz.
  MERGEN_PK_TELEMETRY_HMAC_KEY = list(
    type = "character",
    default = "",
    secret = TRUE
  ),
  # Anahtar rotasyonu etiketi; parmak izinin yanında saklanır ki rotasyondan
  # sonra eski satırlar hangi anahtarla üretildiği bilinerek yorumlanabilsin.
  MERGEN_PK_TELEMETRY_HMAC_KEY_ID = list(
    type = "character",
    default = "k1"
  ),
  # Sorgu sonucu satır tavanı. Ağır bir sorgu kendi tavanını metadata ile
  # taşıyabilir; bu yüzden öncelik zincirinin ilk basamağı sorgu metadatasıdır.
  MERGEN_PK_ROW_CAP = list(
    type = "integer",
    default = 50000L,
    min = 1L
  ),
  # Faz 1 (D9): Filtre planı LLM zaman aşımı. v1'deki sabit 8 saniye fazla
  # agresifti ve zaman aşımı "filtre gerekmedi" ile ayırt edilemiyordu.
  # YALNIZCA v2 tüketir; v1 kendi sabit değerinde bırakılır ki motor sınırı
  # sözleşmesi (§10) bozulmasın.
  MERGEN_PK_FILTER_TIMEOUT_SEC = list(
    type = "integer",
    default = 20L,
    min = 1L
  ),
  # Faz 1 (D1/D2): Bu orandan fazla satır bırakan filtre "etkisiz" sayılır ve
  # köken kaydında böyle raporlanır.
  MERGEN_PK_NOOP_FILTER_RATIO = list(
    type = "double",
    default = 0.95,
    min = 0,
    max = 1
  ),
  # Faz 1 (D7): Modele giden TÜM yükün (özet + tablolar + örnek satır JSON'u)
  # karakter bütçesi. Eski kod yalnızca özet metnini ölçüyordu.
  MERGEN_PK_PROMPT_CHAR_BUDGET = list(
    type = "integer",
    default = 120000L,
    min = 1000L
  ),
  # --- Faz 2 (§5.7): analiz paketi ----------------------------------------
  # Kategorik sütun başına gösterilen ilk-K değer. Eski özet yalnızca ilk beş
  # kategorik sütunu ve her birinin YALNIZCA ilk değerini veriyordu (D17).
  MERGEN_PK_TOPK_CATEGORIES = list(
    type = "integer",
    default = 10L,
    min = 1L
  ),
  # "Diğer" toplamasından önce gösterilen grup sayısı.
  MERGEN_PK_GROUP_TOPN = list(
    type = "integer",
    default = 15L,
    min = 1L
  ),
  # Pakete giren temsilî örnek satır sayısı (ilk-N + son-N + uç değer +
  # tabakalı). Eski yol `head(data, 500)` ile KONUMSAL YANLI idi (D18).
  MERGEN_PK_SAMPLE_ROWS = list(
    type = "integer",
    default = 30L,
    min = 1L
  ),
  # Sabit tohum -> yeniden üretilebilir tabakalı örnek.
  MERGEN_PK_SAMPLE_SEED = list(
    type = "integer",
    default = 42L
  ),
  # --- Faz 2 (§5.8): yanıt kompozisyonu eşikleri --------------------------
  MERGEN_PK_INLINE_MAX_ROWS = list(
    type = "integer",
    default = 15L,
    min = 1L
  ),
  MERGEN_PK_INLINE_MAX_COLS = list(
    type = "integer",
    default = 8L,
    min = 1L
  ),
  MERGEN_PK_DT_MAX_ROWS = list(
    type = "integer",
    default = 200L,
    min = 1L
  ),
  MERGEN_PK_INLINE_MAX_COLS_DT = list(
    type = "integer",
    default = 12L,
    min = 1L
  ),
  # Ek yolunda baloncukta gösterilen önizleme satırı.
  MERGEN_PK_PREVIEW_ROWS = list(
    type = "integer",
    default = 10L,
    min = 1L
  ),
  # --- Faz 2 (§5.9): dışa aktarım ----------------------------------------
  # TEK bir sayfa/parçadaki azami satır. Daha büyük sonuç ya doğrulanmış
  # numaralı parçalara bölünür ya da AÇIKÇA reddedilir; sessizce kırpılmaz.
  MERGEN_PK_EXPORT_MAX_ROWS = list(
    type = "integer",
    default = 100000L,
    min = 1L
  ),
  # Parça tavanı. Aşılırsa dışa aktarım reddedilir ve kullanıcıdan sorusunu
  # daraltması istenir.
  MERGEN_PK_EXPORT_MAX_PARTS = list(
    type = "integer",
    default = 20L,
    min = 1L
  ),
  # XLSX bellek tavanı (hücre = satır x sütun). `writexl` tüm sayfaları AYNI
  # ANDA ister; tavan aşılırsa XLSX hiç denenmez ve parçaları teker teker yazan
  # akışlı CSV yoluna geçilir. Sessiz kırpma DEĞİLDİR: tüm satırlar aktarılır.
  MERGEN_PK_EXPORT_MAX_CELLS = list(
    type = "integer",
    default = 2000000L,
    min = 1L
  ),
  # --- Faz 4 (§5.4): varlık çözümleme -------------------------------------
  # Çözümleme hattının filtre yoluna bağlanması. YALNIZCA v2 yürütücüsünden
  # çağrılır; v1 davranışı bu anahtardan BAĞIMSIZ olarak bit bit korunur.
  # Operatörün geri dönüş anahtarı olarak açık tutulur: gerçek sözlük
  # davranışı VM'de ölçülene kadar kapatılabilir olmalıdır.
  MERGEN_PK_RESOLVE_ENABLED = list(
    type = "logical",
    default = TRUE
  ),
  # --- Faz 4 (§5.4): varlık çözümleme eşikleri ----------------------------
  # HEPSİ 0..100 aralığında tam sayıdır ve `pk_resolve_thresholds()` içinde
  # AYRICA ilişkileri doğrulanır: MIN <= MULTI <= AUTO. Tek anahtar
  # doğrulaması bu ilişkiyi yakalayamaz — örneğin MIN=90 ile AUTO=85 tek tek
  # geçerli, birlikte tutarsızdır ve kapalı başarısızlığa yol açmalıdır.
  #
  # Çözümleyicideki HİÇBİR dal bu değerleri sabit kodlamaz (§5.4 açık kuralı).
  #
  # Tek adayın otomatik kabul edildiği eşik.
  MERGEN_PK_RESOLVE_AUTO_SCORE = list(
    type = "integer",
    default = 85L,
    min = 0L,
    max = 100L
  ),
  # Çoğul isteklerde adayın "güçlü" sayıldığı eşik. Bu eşiği geçen adaylar
  # sessizce BİRLEŞTİRİLMEZ; kullanıcıya onaylatılır.
  MERGEN_PK_RESOLVE_MULTI_SCORE = list(
    type = "integer",
    default = 70L,
    min = 0L,
    max = 100L
  ),
  # Bu eşiğin altı "çözümlenemedi" sayılır (kural 6/7).
  MERGEN_PK_RESOLVE_MIN_SCORE = list(
    type = "integer",
    default = 40L,
    min = 0L,
    max = 100L
  ),
  # Tepe ile ikinci aday arasındaki fark bu değerin altındaysa tahmin
  # yürütülmez, kullanıcıya sorulur.
  MERGEN_PK_RESOLVE_AMBIGUITY_MARGIN = list(
    type = "integer",
    default = 10L,
    min = 0L,
    max = 100L
  ),
  # Tek bir OR grubunda TAMAMEN görünür/onaylanabilir azami kanonik değer.
  # Daha büyük kümeler daraltma/sayfalama gerektirir ve değerler "Tümü"
  # arkasına SAKLANAMAZ.
  MERGEN_PK_RESOLVE_MAX_CANDIDATES = list(
    type = "integer",
    default = 5L,
    min = 1L,
    max = 5L
  ),
  # Puanlamaya giren varlık ifadesinin azami karakter uzunluğu. Sınırsız
  # ifade, mütevazı bir sözlükte bile aday başına iki Levenshtein hesabıyla
  # PAYLAŞILAN Shiny sürecini meşgul edebilir (yapıştırılmış/kötü niyetli
  # metin). Aşan ifade kırpılır ve bu durum karara AÇIKÇA yazılır.
  MERGEN_PK_RESOLVE_MAX_PHRASE_CHARS = list(
    type = "integer",
    default = 160L,
    min = 8L,
    max = 4000L
  ),
  # Belirteç/mesafe katmanlarına giren azami aday sayısı. Kesin ve alias
  # katmanları bu sınırdan ETKİLENMEZ; onlar karma araması ile çözülür.
  # Tavan aşılırsa karar `scan_truncated` taşır; sessiz "eşleşme yok" olmaz.
  MERGEN_PK_RESOLVE_MAX_SCAN_CANDIDATES = list(
    type = "integer",
    default = 2000L,
    min = 1L,
    max = 200000L
  ),
  # --- Faz 5 (§5.2): iki geçişli sorgu seçimi -----------------------------
  # D14: v1'de seçim çağrısının HİÇ zaman aşımı yoktu ve asılı bir uç nokta
  # olay döngüsünü bloke ediyordu. Değer HER İKİ geçişte de ayrı ayrı uygulanır.
  #
  # ÜST SINIR bir güvenlik kontrolüdür, konfor değil: bu değer tam olarak
  # "asılı uç nokta olay döngüsünü bloke etmesin" diye vardır ve doğrudan
  # `request_timeout_sec` olarak iletilir. Sınırsız bırakıldığında bir yazım
  # hatası (`86400`) her geçişi bir güne kadar bloke ederek D14'ü geri getirir.
  MERGEN_PK_SELECT_TIMEOUT_SEC = list(
    type = "integer",
    default = 60L,
    min = 1L,
    max = 120L
  ),
  # Geçiş A'nın isteyeceği ve Geçiş B'ye DEĞİŞMEDEN taşınacak aday sayısı.
  #
  # ALT SINIR 2 GÜVENLİK SÖZLEŞMESİDİR (§5.2): tek adaylık bir getirim,
  # `MERGEN_PK_SELECT_MIN_MARGIN` için gereken ikinci-aday güvenini
  # üretemez; marj kapısı uygulanamaz hâle gelir. Bu yüzden `min = 2L`.
  #
  # ÜST SINIR keyfi değildir: Geçiş B her aday için TAM açıklama, örnek
  # sorular ve sütun etiketleri gönderir; sınırsız N, Geçiş B yükünü
  # bağlam penceresinin ötesine taşır ve kırpma sessiz aday kaybı olurdu.
  MERGEN_PK_SELECT_RECALL_N = list(
    type = "integer",
    default = 5L,
    min = 2L,
    max = 20L
  ),
  # Bu güvenin altında çalıştırma YAPILMAZ; netleştirme sorulur (D10).
  MERGEN_PK_SELECT_MIN_CONFIDENCE = list(
    type = "integer",
    default = 50L,
    min = 0L,
    max = 100L
  ),
  # Tepe aday ile ikinci aday arasındaki asgari fark. Altında kalırsa yakın
  # beraberlik sayılır ve kullanıcıya sorulur.
  MERGEN_PK_SELECT_MIN_MARGIN = list(
    type = "integer",
    default = 15L,
    min = 0L,
    max = 100L
  ),
  # Sözlüksel getirim UYUŞMAZLIĞININ güvenden düşürdüğü puan. Sözlüksel
  # katman KARAR VERMEZ (§5.2); yalnızca güveni zayıflatır. 0 verilirse sinyal
  # tamamen etkisizleşir (yalnızca raporlanır).
  MERGEN_PK_SELECT_DISAGREE_PENALTY = list(
    type = "integer",
    default = 15L,
    min = 0L,
    max = 100L
  ),
  # Geçiş A satırındaki açıklama karakter bütçesi. Alanlar KÜRESEL olarak
  # düşürülmez, tek tek ve DETERMİNİSTİK biçimde kırpılır (§5.2).
  #
  # TÜM Geçiş A bütçelerinin ÜST SINIRI vardır. Bunlar tam olarak tüm
  # kütüphanenin tek istemde sığmasını garanti etmek için vardır; sınırsız
  # bırakılan bir "bütçe" sağlaması gereken sınırı kaldırır ve recall
  # kütüphane SIRASINA bağımlı hâle gelir.
  MERGEN_PK_SELECT_DESC_CHARS = list(
    type = "integer",
    default = 220L,
    min = 40L,
    max = 600L
  ),
  # Geçiş A satırındaki örnek soru başına karakter bütçesi.
  MERGEN_PK_SELECT_SAMPLE_CHARS = list(
    type = "integer",
    default = 120L,
    min = 20L,
    max = 400L
  ),
  # Geçiş A satırındaki sorgu ADI karakter bütçesi. Ad da kırpılır: başlangıç
  # doğrulaması ada uzunluk sınırı koymaz ve tek bir devasa ad, diğer tüm
  # bütçeleri anlamsız kılabilirdi.
  MERGEN_PK_SELECT_NAME_CHARS = list(
    type = "integer",
    default = 120L,
    min = 20L,
    max = 400L
  ),
  # Geçiş A satırındaki anahtar kelime/niyet/uygun-değil alanlarının toplam
  # karakter bütçesi.
  MERGEN_PK_SELECT_KEYWORD_CHARS = list(
    type = "integer",
    default = 160L,
    min = 20L,
    max = 600L
  ),
  # Takip bağlamındaki konuşma turu başına karakter bütçesi. Örnek soru
  # bütçesinden AYRIDIR: kütüphane yükünü küçültmek için `SAMPLE_CHARS`
  # düşürüldüğünde eksiltili takip bağlamı sessizce yok olmamalıdır.
  MERGEN_PK_SELECT_HISTORY_CHARS = list(
    type = "integer",
    default = 240L,
    min = 40L,
    max = 800L
  ),
  # Geçiş B aday bloklarının TOPLAM karakter bütçesi. Aday SAYISI tek başına
  # bağlamı sınırlamaz: tek bir geniş sorgu tüm açıklama/örnek/sütun
  # metadata'sıyla pencereyi taşırabilir.
  MERGEN_PK_SELECT_PASS_B_CHARS = list(
    type = "integer",
    default = 24000L,
    min = 2000L,
    max = 120000L
  ),
  # XLSX yolunun TAHMİNİ BAYT tavanı (MB).
  #
  # Hücre SAYISI hücre GENİŞLİĞİ hakkında hiçbir şey söylemez: tek bir çok-KB
  # metin sütununun 100.000 satırı hücre tavanının çok altında kalırken kabul
  # edilen sonuç yüzlerce MB olabilir. XLSX yolu çerçeveyi normalleştirip
  # kopyalar ve çalışma kitabını onun YANINDA kurar; bu, `MERGEN_PK_MAX_RESULT_MB`
  # sınırını geçmiş bir sonuçta bile işçiyi tüketebilir. Tavan geçici kopya
  # payını da kapsar.
  MERGEN_PK_EXPORT_MAX_BYTES_MB = list(
    type = "integer",
    default = 128L,
    min = 1L,
    max = 4096L
  ),
  # Geçiş A kütüphane yükünün TOPLAM karakter bütçesi.
  #
  # Alan başına kırpma (DESC/NAME/KEYWORD/SAMPLE_CHARS) tek başına YETMEZ:
  # sorgu SAYISI sınırlı değildir ve gerçek kütüphane 169 sorguludur. Alanları
  # izin verilen üst sınırlara yakın, daha büyük bir kütüphane Geçiş A'yı
  # seçici modelin bağlamının ötesine itebilir. Geçiş B'nin `PASS_B_CHARS`
  # toplam kapısının Geçiş A karşılığıdır; aşıldığında sessiz kırpma değil,
  # AÇIK kapalı-başarısız rapor üretilir.
  MERGEN_PK_SELECT_PASS_A_CHARS = list(
    type = "integer",
    default = 200000L,
    min = 2000L,
    max = 400000L
  ),
  # Geçiş A satırına giren örnek soru sayısı (§5.2: `sample_questions[1:2]`).
  # ÜST SINIR sözleşmenin kendisidir: §5.2 iki örnek soru der ve 169 sorguluk
  # gerçek kütüphanede bu alan yükün en büyük bileşenidir.
  MERGEN_PK_SELECT_SAMPLE_N = list(
    type = "integer",
    default = 2L,
    min = 1L,
    max = 2L
  ),
  # Takip bağlamı zarfına giren konuşma turu sayısı (§5.2: son 2 tur).
  # Zarf bir GÜVENLİK sınırıdır, ayar değil: 10 tur seçim istemine ilgisiz
  # eski konuşmayı taşır, 0 ise eksiltili takip sorusunu yorumlamak için
  # gereken tek kanıtı siler.
  MERGEN_PK_SELECT_HISTORY_TURNS = list(
    type = "integer",
    default = 2L,
    min = 1L,
    max = 2L
  ),
  # --- Faz 2 (§5.11): sayısal köken doğrulaması ---------------------------
  # `log` ile başlanır: gerçek yanlış-pozitif oranı VM'de ölçülmeden `warn`
  # veya `block` kipine geçilmez.
  MERGEN_PK_NUMERIC_PROVENANCE_MODE = list(
    type = "character",
    default = "log",
    allowed = c("off", "log", "warn", "block")
  ),
  # --- Faz 6 (§5.10): bloklamayan yürütme ve performans -------------------
  # AYRI kill switch: MERGEN_PK_ENGINE'den BAĞIMSIZDIR. v2 motoru VM'de
  # benimsenirken yürütme senkron kalabilir; en riskli değişiklik böylece
  # tek başına doğrulanır (§10). Varsayılan KAPALI olmalıdır: bu bayrağın
  # ana faydası (olay döngüsü yanıt verebilirliği) OFFLINE KANITLANAMAZ.
  MERGEN_PK_ASYNC = list(
    type = "logical",
    default = FALSE
  ),
  # ODBC sorgu zaman aşımı: asılı kalan bir ifade bağlantıyı sonsuza kadar
  # tutmasın. Ağır bir sorgu metadata ile bu değeri YÜKSELTEBİLİR, ancak
  # asla kalan analiz bütçesinin ötesine geçemez (bkz. pk_sql_timeout_plan).
  MERGEN_PK_SQL_TIMEOUT_SEC = list(
    type = "integer",
    default = 120L,
    min = 1L
  ),
  # TÜM analizin duvar saati bütçesi. İşçi bu bütçe tükendiğinde durur ve
  # bağlantısını serbest bırakır. Ardışık geçerli zaman aşımlarının toplamı
  # bu bütçeyi AŞAMAZ.
  MERGEN_PK_ANALYSIS_DEADLINE_SEC = list(
    type = "integer",
    default = 300L,
    min = 1L
  ),
  # Sonuç önbelleği: giriş sayısı tavanı.
  MERGEN_PK_CACHE_MAX_ENTRIES = list(
    type = "integer",
    default = 50L,
    min = 0L
  ),
  # Sonuç önbelleği: toplam bayt bütçesi (MB). TTL TEK BAŞINA yeterli
  # değildir; pencere içinde üretilen her büyük sonuç aynı anda yerleşik
  # kalabilir.
  MERGEN_PK_CACHE_MAX_MB = list(
    type = "integer",
    default = 512L,
    min = 0L
  ),
  # Bu boyutun üzerindeki TEK bir giriş HİÇ önbelleğe alınmaz; diğer her şeyi
  # tahliye ederek kendine yer açması YASAKTIR.
  MERGEN_PK_CACHE_MAX_ENTRY_MB = list(
    type = "integer",
    default = 128L,
    min = 0L
  ),
  # (query_id, rls_signature, filter_signature) önbellek ömrü.
  MERGEN_PK_CACHE_TTL_SEC = list(
    type = "integer",
    default = 300L,
    min = 0L
  ),
  # Derin Düşünme sıralı-küme tavanı (§10). v2 seçimi bu değeri okur; kodda
  # sabit 5 kalmaz.
  MERGEN_PK_DEEP_MAX_QUERIES = list(
    type = "integer",
    default = 5L,
    min = 1L,
    max = 20L
  ),
  # TEK bir materyalize sonucun aktif bellek tavanı (MB). Karar frame
  # YÜKLENMEDEN ÖNCE verilir; önbellek bayt bütçesi yalnızca
  # materyalizasyondan SONRA geçerlidir, dolayısıyla bir işçiyi tek geniş
  # sorgudan koruyamaz.
  MERGEN_PK_MAX_RESULT_MB = list(
    type = "integer",
    default = 512L,
    min = 1L
  ),
  # SINIRSIZ LOB sütunlu sonuçlara (nvarchar(max)/XML/image/UDT) izin ver.
  #
  # VARSAYILAN KAPALI: satır granülaritesi bir LOB HÜCRESİNİ kesemez;
  # `dbFetch(n = 1)` bile hücrenin tamamını belleğe alır ve
  # `MERGEN_PK_MAX_RESULT_MB` kapısı ancak SONRASINDA çalışır. Gerçekten LOB
  # döndüren bir sorgusu olan operatör riski AÇIKÇA üstlenebilir.
  MERGEN_PK_ALLOW_UNBOUNDED_LOB = list(
    type = "logical",
    default = FALSE
  ),
  # Sonuç-boyutu ön kontrolünde R/sürücü nesne yükü için muhafazakâr çarpan.
  # Beyan edilmiş maksimum sütun genişliklerinin toplamı, R karakter
  # vektörlerinin gerçek bellek maliyetini OLDUĞU GİBİ vermez.
  MERGEN_PK_RESULT_OVERHEAD_FACTOR = list(
    type = "double",
    default = 2.5,
    min = 1
  ),
  # Kanıtlanmış üst sınır yokken zorunlu sınırlı-parça (chunk) getiriminde
  # parça başına satır sayısı.
  MERGEN_PK_FETCH_CHUNK_ROWS = list(
    type = "integer",
    default = 5000L,
    min = 1L
  )
)

# MERGEN_PK_TELEMETRY -> "telemetry" (sorgu metadata alan adı)
#
# Küçük harfe indirme yerelden BAĞIMSIZ olmalıdır: Türkçe Windows yerel ayarında
# `tolower("ID")` noktasız `ıd` üretir ve `..._HMAC_KEY_ID` anahtarı için hem
# metadata hem options() basamağı sessizce ıskalanır. Anahtar adları saf ASCII
# olduğundan A-Z ile sınırlı bir eşleme doğru ve yeterlidir.
pk_config_meta_key <- function(key) {
  chartr(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
    sub("^MERGEN_PK_", "", as.character(key)[1])
  )
}

# MERGEN_PK_TELEMETRY -> "mergen.pk.telemetry" (options() adı)
pk_config_option_key <- function(key) {
  paste0("mergen.pk.", pk_config_meta_key(key))
}

# Mantıksal değer ayrıştırma; Türkçe operatör alışkanlıkları da desteklenir.
.pk_config_as_logical <- function(value) {
  if (is.logical(value) && length(value) == 1L && !is.na(value)) return(value)
  if (length(value) != 1L) return(NULL)

  # Yapılandırma bayrağı ASCII protokol belirtecidir: Türkçe yerelde
  # `tolower("TRUE")` -> "trve" değil ama `tolower("I")` -> "ı" davranışı
  # "ON"/"OFF" gibi girdilerde sessiz uyumsuzluk üretir.
  txt <- .pk_config_ascii_lower(trimws(as.character(value)[1]))
  if (is.na(txt) || !nzchar(txt)) return(NULL)

  # PR #705: Türkçe BÜYÜK harfli operatör yazımları da desteklenir.
  #
  # ASCII katlama yerelden bağımsızdır ama `Ç`/`Ğ`/`İ`/`Ö`/`Ş`/`Ü` harflerine
  # DOKUNMAZ; `AÇIK` yazan bir operatör `aÇik` üretiyor, sözlükte bulunamıyor
  # ve değer SESSİZCE geçersiz sayılıp daha düşük öncelikli bir varsayılana
  # düşülüyordu. Eşleme SABİT ve yerelden bağımsızdır (`tolower()` kullanılmaz).
  txt <- chartr("ÇĞİÖŞÜ", "çğiöşü", txt)

  # Nokta(sız) i belirsizliği: ASCII katlamada `I` -> `i`, Türkçe yazımda
  # `ı` beklenir. Her iki yazım da AÇIKÇA kabul edilir; tahmin yapılmaz.
  if (txt %in% c("true", "t", "1", "yes", "y", "on", "evet",
                 "acik", "acık", "açik", "açık")) return(TRUE)
  if (txt %in% c("false", "f", "0", "no", "n", "off", "hayir", "hayır",
                 "kapali", "kapalı")) return(FALSE)

  NULL
}

# Tam sayılar yuvarlanmaz. Kesirli, taşan veya birden çok değer geçersizdir.
.pk_config_as_integer <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  num <- suppressWarnings(as.numeric(as.character(value)[1]))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return(NULL)
  if (!identical(num, trunc(num))) return(NULL)
  if (num < -.Machine$integer.max || num > .Machine$integer.max) return(NULL)

  out <- as.integer(num)
  if (is.na(out)) return(NULL)
  if (!is.null(spec$min) && out < spec$min) return(NULL)
  if (!is.null(spec$max) && out > spec$max) return(NULL)

  out
}

# Ondalık değerler. Tam sayıdan ayrı tutulur; NaN/Inf ve aralık dışı reddedilir.
.pk_config_as_double <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  num <- suppressWarnings(as.numeric(as.character(value)[1]))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return(NULL)
  if (!is.null(spec$min) && num < spec$min) return(NULL)
  if (!is.null(spec$max) && num > spec$max) return(NULL)

  num
}

.pk_config_as_character <- function(value, spec) {
  if (length(value) != 1L) return(NULL)

  txt <- as.character(value)[1]
  if (is.na(txt)) return(NULL)

  txt <- trimws(txt)
  if (!nzchar(txt) && nzchar(spec$default %||% "")) return(NULL)
  if (!is.null(spec$allowed) && !(txt %in% spec$allowed)) return(NULL)

  txt
}

# Ham bir adayı anahtarın tipine göre doğrular. Geçersizse NULL döner ki
# çözümleyici bir sonraki önceliğe geçebilsin (sessiz varsayılana düşme).
.pk_config_coerce <- function(value, spec) {
  if (is.null(value) || length(value) == 0L) return(NULL)

  switch(
    spec$type %||% "character",
    logical   = .pk_config_as_logical(value),
    integer   = .pk_config_as_integer(value, spec),
    double    = .pk_config_as_double(value, spec),
    character = .pk_config_as_character(value, spec),
    NULL
  )
}

#' Etkin motor kipi ("v1" / "v2")
#'
#' Master plan §10: `v1` varsayılandır ve operatör VM'de doğrulayana kadar
#' öyle kalır. D1-D5, D7-D9 ve D12 YALNIZCA `v2` altında etkinleşir; RLS
#' kapalı başarısızlığı, salt-okunur SQL kapısı, ODBC redaksiyonu ve Faz 0
#' gözlemi ise bayraktan BAĞIMSIZ çalışır.
pk_engine_mode <- function(query_meta = NULL) {
  tryCatch(
    pk_config_resolve("MERGEN_PK_ENGINE", query_meta = query_meta),
    error = function(e) "v1"
  )
}

pk_engine_is_v2 <- function(query_meta = NULL) {
  identical(pk_engine_mode(query_meta), "v2")
}

#' Yapılandırma değerini öncelik sırasıyla çöz
#'
#' @param key Anahtar adı (örn. "MERGEN_PK_TELEMETRY").
#' @param query_meta Seçilen sorgunun metadata listesi (opsiyonel). Sorgu bazlı
#'   değer global ayarı EZER; böylece ağır bir sorgu kendi sınırını taşıyabilir.
#' @return Anahtarın tipine uygun tek elemanlı değer.
pk_config_resolve <- function(key, query_meta = NULL) {
  key <- as.character(key)[1]
  spec <- pk_config_spec[[key]]

  if (is.null(spec)) {
    stop(sprintf("pk_config_resolve: tanimsiz yapilandirma anahtari '%s'.", key), call. = FALSE)
  }

  # 1) Sorgu bazlı metadata
  if (is.list(query_meta)) {
    candidate <- .pk_config_coerce(query_meta[[pk_config_meta_key(key)]], spec)
    if (!is.null(candidate)) return(candidate)
  }

  # 2) Ortam değişkeni (worker güvenli: doğrudan Sys.getenv)
  env_raw <- Sys.getenv(key, unset = NA_character_)
  if (!is.na(env_raw)) {
    candidate <- .pk_config_coerce(env_raw, spec)
    if (!is.null(candidate)) return(candidate)
  }

  # 3) options()
  candidate <- .pk_config_coerce(getOption(pk_config_option_key(key), default = NULL), spec)
  if (!is.null(candidate)) return(candidate)

  # 4) Yerleşik varsayılan
  spec$default
}

#' Bir anahtarı çöz VE geçersiz kaynakları RAPORLA
#'
#' `pk_config_resolve()` bilerek toleranslıdır: geçersiz bir öncelik basamağını
#' atlar ve bir sonrakine geçer. Bu, çoğu ayar için doğru davranıştır — ama
#' EŞİKLER için değildir. `MERGEN_PK_RESOLVE_AUTO_SCORE=bogus` sessizce
#' varsayılan 85'e düşerse operatör eşiği DEĞİŞTİRDİĞİNİ sanır, oysa otomatik
#' filtreleme hâlâ eski değerle çalışır. §5.4 sözleşmesi bunun tersini ister:
#' geçersiz/çözülemeyen eşik otomatik çözümlemeyi DEVRE DIŞI bırakmalı ve
#' operatöre açık hata göstermelidir.
#'
#' Bu yardımcı, ATLANMIŞ olan basamağı görünür kılar; kapalı başarısızlık
#' kararını çağıran taraf verir.
#'
#' @return `list(value, invalid_sources)`. `invalid_sources`, değer TAŞIYAN ama
#'   anahtarın tipine/aralığına UYMAYAN basamakların adlarıdır.
pk_config_probe <- function(key, query_meta = NULL) {
  key <- as.character(key)[1]
  spec <- pk_config_spec[[key]]

  if (is.null(spec)) {
    stop(sprintf("pk_config_probe: tanimsiz yapilandirma anahtari '%s'.", key), call. = FALSE)
  }

  gecersiz <- character(0)
  # BEYAN EDİLMİŞ AMA BOZUK DEĞER "YOK" DEĞİLDİR.
  #
  # Eski kapı yalnızca skaler, `NA` olmayan ve boş olmayan bir değeri "var"
  # sayıyordu; çok elemanlı (`c(90, 95)`) ya da açıkça `NA` bir beyan sessizce
  # ATLANIYOR, `invalid_sources` boş kalıyor ve `pk_resolve_thresholds()`
  # yapılandırmayı GEÇERLİ raporluyordu. Operatör eşiği değiştirdiğini sanırken
  # varlık çözümlemesi başka bir eşikle çalışıyordu (kapalı-başarısız ihlali).
  .ham_var <- function(x) {
    if (is.null(x) || length(x) == 0L) return(FALSE)
    if (length(x) != 1L) return(TRUE)
    if (is.na(x)) return(TRUE)
    nzchar(trimws(as.character(x)[1]))
  }

  # ÖNCELİK SIRASI: query_meta -> environment -> options.
  #
  # PR #705: KAZANAN basamaktan SONRAKİ basamaklar artık taranmaz. Eski
  # davranışta geçerli bir `meta$resolve_auto_score = 90` kazanmış olsa bile
  # bayat bir `MERGEN_PK_RESOLVE_AUTO_SCORE=bogus` "environment geçersiz" diye
  # raporlanıyor, `pk_resolve_thresholds()` bunu görüp çözümleyiciyi
  # `config_error` sayıyordu. Yani isteği ETKİLEYEMEYEN düşük öncelikli bir
  # değer, geçerli bir sorgu-özel ayarı zehirliyordu.
  #
  # Kapalı başarısızlık KORUNUR: kazanandan ÖNCEKİ (yani gerçekten
  # uygulanabilecekken bozuk olan) basamaklar hâlâ geçersiz raporlanır.
  basamaklar <- list(
    list(ad = "query_meta", ham = if (is.list(query_meta)) query_meta[[pk_config_meta_key(key)]] else NULL),
    # ORTAM DEĞİŞKENİNDE "AYARLANMAMIŞ" BOŞ DİZEDİR, `NA` DEĞİLDİR.
    #
    # `unset = NA_character_` sentinel'i, aşağıdaki "beyan edilmiş ama bozuk"
    # denetimiyle çakışırdı: AYARLANMAMIŞ her anahtar `NA` görülüp "environment
    # geçersiz" raporlanır ve `pk_resolve_thresholds()` tüm yapılandırmayı
    # geçersiz sayardı. Boş dize hem "yok" demektir hem de operatörün açıkça
    # boş bıraktığı bir değeri zaten geçersiz kılmaz.
    list(ad = "environment", ham = Sys.getenv(key, unset = "")),
    list(ad = "options", ham = getOption(pk_config_option_key(key), default = NULL))
  )

  for (basamak in basamaklar) {
    if (!.ham_var(basamak$ham)) next
    if (is.null(.pk_config_coerce(basamak$ham, spec))) {
      gecersiz <- c(gecersiz, basamak$ad)
      next
    }
    # Geçerli değer bulundu: bu basamak KAZANIR, alt basamaklar isteği
    # etkileyemez ve tanılama amacıyla bile geçersiz sayılmaz.
    break
  }

  list(
    value = pk_config_resolve(key, query_meta = query_meta),
    invalid_sources = gecersiz
  )
}

#' Gizli olmayan yapılandırma özeti (tanılama için)
#'
#' Gizli anahtarlar için yalnızca varlık/uzunluk bilgisi döner; ham değer
#' hiçbir koşulda çıktıya girmez.
pk_config_safe_snapshot <- function() {
  out <- list()

  for (key in names(pk_config_spec)) {
    spec <- pk_config_spec[[key]]
    value <- tryCatch(pk_config_resolve(key), error = function(e) NULL)

    if (isTRUE(spec$secret)) {
      out[[key]] <- list(
        present = !is.null(value) && nzchar(as.character(value)[1]),
        nchar = if (is.null(value)) 0L else nchar(as.character(value)[1]),
        value = "<hidden>"
      )
    } else {
      # `out[[key]] <- NULL` elemanı LISTEDEN SILER; çözülemeyen bir anahtar
      # bu yüzden raporda hiç görünmezdi. Tanılamada "yok" ile "çözülemedi"
      # ayrılabilsin diye açıkça NA yazılır.
      out[[key]] <- value %||% NA
    }
  }

  out
}
