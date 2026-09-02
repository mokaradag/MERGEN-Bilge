# ==============================================================================
# Dosya Yolu: R/helpers_pk_worker_observers.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ-GÜVENLİ PK gözlemci sarmalayıcıları.
#
# NEDEN AYRI DOSYA: bu sarmalayıcı ANA SÜREÇTE `server_*` katmanında
# kuruluyordu. Temiz bir PSOCK işçisi o katmanı HİÇ yüklemez (Shiny wiring
# işçiye girmemelidir), dolayısıyla asenkron istekler yalnızca
# `MERGEN_PK_ASYNC` açık olduğu için:
#
#   * `MERGEN_PK_ENGINE=v2` derin isteklerini v1 olarak kaydediyordu.
#
# Standart PK DOĞRUDAN-ÇIKIŞ sarmalayıcısı ayrı bir sorumluluktur ve
# `R/helpers_pk_worker_direct_exit.R` içindedir (bu dosyadan HEMEN SONRA
# yüklenir; oradaki kurulum buradaki `.pk_worker_is_wrapped()` yardımcısını
# kullanır).
#
# Dosya SAFTIR: Shiny/reaktif/DB/ağ bağımlılığı YOKTUR. Yalnızca zaten yüklü
# fonksiyonları sarmalar ve HER İKİ tarafta (ana süreç + işçi) aynı davranışı
# üretir. Yeniden source edilmeye karşı IDEMPOTENT'tir: sarmalayıcı zincirinin
# büyümemesi için sarmalanmamış çekirdek kararlı bir sentinel altında saklanır.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1) Derin gözlemci FABRİKA KAPSAMI
# ------------------------------------------------------------------------------
# `pk_deep_observation_helpers()` temel fabrikası gözlemciyi GLOBAL aramayla
# çözer ve `engine = "v1"` sabitler. v2 derin köprüsü ise çağrı-yerel bir
# `pk_analysis_observe` override'ı kurar. Sarmalayıcı, çağıranın kapsamındaki
# override'ı fabrikaya taşır.
#
# IDEMPOTENT: sentinel yoksa MEVCUT sembol çekirdek olarak saklanır; varsa
# yeniden sarmalanmaz. Aksi hâlde her `global.R` yeniden yüklemesinde
# sarmalayıcı zinciri büyür ve iç sarmalayıcı `parent.frame()`'i DIŞ
# sarmalayıcının çerçevesinden okuyup yanlış gözlemciyi seçerdi.
#
# SENTINEL TEK BAŞINA YETMEZ: bir parmak izi yenilemesinde üst katman dosyası
# `pk_deep_observation_helpers` sembolünü TAZE bir çekirdeğe yeniden tanımlar,
# ama `.pk_deep_observation_helpers_core` HÂLÂ var olduğu için kurulum
# ATLANIYOR ve PUBLIC fonksiyon SARMALANMAMIŞ kalıyordu (v2 derin köken/
# doğrudan-çıkış telemetrisi sessizce kayboluyordu). Bu yüzden karar,
# "sentinel var mı" değil "MEVCUT public fonksiyon ZATEN sarmalayıcı mı"
# sorusuna dayanır.
.pk_worker_is_wrapped <- function(fn, mark) {
  is.function(fn) && isTRUE(attr(fn, mark, exact = TRUE))
}

if (exists("pk_deep_observation_helpers", mode = "function", inherits = TRUE) &&
    !.pk_worker_is_wrapped(
      get("pk_deep_observation_helpers", mode = "function", inherits = TRUE),
      "pk_worker_deep_wrapper"
    )) {

  .pk_deep_observation_helpers_core <- get(
    "pk_deep_observation_helpers", mode = "function", inherits = TRUE
  )

  pk_deep_observation_helpers <- function(...) {
    gozlemci <- try(
      get("pk_analysis_observe", envir = parent.frame(), mode = "function", inherits = TRUE),
      silent = TRUE
    )
    fabrika <- .pk_deep_observation_helpers_core
    if (is.function(gozlemci)) {
      e <- new.env(parent = environment(fabrika))
      e$pk_analysis_observe <- gozlemci
      environment(fabrika) <- e
    }
    fabrika(...)
  }
  attr(pk_deep_observation_helpers, "pk_worker_deep_wrapper") <- TRUE
}

# ==============================================================================
# DOĞRUDAN ÇIKIŞ SONUÇ SINIFLANDIRMASI — ANA SÜREÇ İLE İŞÇİ AYNI EŞLEMEYİ
# KULLANIR
#
# İşçi sarmalayıcısı her istisna/durdurma DIŞI karakter çıkışını
# `DogrudanYanit` olarak kaydediyordu; ana süreçteki karşılığı ise aynı
# yanıtları `Yetkisiz` ve `EslesmeYok` olarak sınıflandırıyor. Telemetri bu
# yüzden YALNIZCA asenkron yönlendirme kullanıldığı için anlam değiştiriyor ve
# denetim/rollout ölçümleri bozuluyordu. Eşleme TEK yerdedir.
# ==============================================================================
# `error_message` SONUCUNDAN KULLANICIYA GÖRÜNEN METNİ ÇIKAR.
#
# Sonuç `list(type = "error_message", message = ...)` ya da bir koşul nesnesi
# olabilir. `as.character(x)[1]` listede İLK ÖGEYİ (`type`) döndürür; desen
# taramaları bu yüzden YANLIŞ dizede çalışıyordu. İki sınıflandırıcı da bunu
# kullanır.
pk_direct_exit_text <- function(x) {
  if (is.null(x)) return("")
  ham <- if (inherits(x, "condition")) {
    tryCatch(conditionMessage(x), error = function(e) "")
  } else if (is.list(x)) {
    # BOŞ / `NA` ALAN KULLANILABİLİR DEĞİLDİR (PR #705 inceleme, P3).
    #
    # `Negate(is.null)` `character(0)` ve `NA_character_` değerlerini de KABUL
    # ediyor, bu yüzden boş bir `message` alanı DOLU `answer`/`text`/`content`
    # alanlarını MASKELİYORDU. Sonuç: `pk_direct_exit_is_db_failure()` boş metin
    # okuyup `FALSE` döndürüyor, doğrudan-çıkış sarmalayıcısı DSN erişilemezken
    # yeni bir telemetri bağlantısı açıyordu -- tam olarak bu sınıflandırıcının
    # engellemek için var olduğu bloklayan yeniden bağlanma. `Yetkisiz` /
    # `EslesmeYok` sınıflandırmaları da aynı nedenle kayboluyordu.
    .kullanilir <- function(v) {
      if (is.null(v)) return(FALSE)
      s <- tryCatch(as.character(v)[1], error = function(e) NA_character_)
      length(s) == 1L && !is.na(s) && nzchar(s)
    }
    Find(.kullanilir, x[c("message", "answer", "text", "content")]) %||% ""
  } else x
  metin <- tryCatch(as.character(ham)[1], error = function(e) "")
  if (length(metin) != 1L || is.na(metin)) return("")

  # METİN UTF-8'E NORMALLEŞTİRİLİR: aşağıdaki Türkçe desenler `\uXXXX` kaçışlarıyla yazıldığı için UTF-8'dir, `fixed = TRUE` ise KODLAMA ÇEVİRİSİNDEN SONRA bayt bayt eşler. Windows VM'de işçiden gelen mesaj WINDOWS-1254 baytları taşıyıp UTF-8 işaretini TAŞIMADIĞINDA hiçbir desen eşleşmiyor; sonuç "DogrudanYanit"e, DB arıza saptaması FALSE'a düşüyordu (işçi bloklayan yeniden bağlanmayı tekrar deniyordu).
  tryCatch(enc2utf8(metin), error = function(e) metin)
}

pk_direct_exit_outcome <- function(response_text, stopped = FALSE, error = FALSE) {
  if (isTRUE(error)) return("Hata")
  if (isTRUE(stopped)) return("Durduruldu")

  metin <- pk_direct_exit_text(response_text)

  if (grepl("\u0130\u015flem Durduruldu", metin, fixed = TRUE)) return("Durduruldu")
  if (grepl("Yetki Hatas\u0131", metin, fixed = TRUE)) return("Yetkisiz")
  if (grepl("mevcut analiz k\u00fct\u00fcphanesinde bulunamad\u0131", metin, fixed = TRUE)) {
    return("EslesmeYok")
  }

  # `type == "error_message"` DESEN TARAMASINDAN SONRA hata sonucuna eşlenir.
  #
  # Eşleme desenlerden ÖNCE yapıldığında AYNI yanıt, hangi yolun
  # sınıflandırdığına göre FARKLI bir `MB_Analiz_Log` sonucu alıyordu: ana
  # süreçteki sarmalayıcı (`R/server_init_chat_runtime.R`) önce `result$content`
  # metnini çıkarıp bu sınıflandırıcıya verdiği için "Yetkisiz"/"EslesmeYok"
  # üretiyor, işçi yolu (`R/helpers_pk_worker_direct_exit.R`) HAM listeyi
  # verdiği için aynı yanıtı "Hata" sayıyordu; telemetri sonucu ASENKRON
  # YÖNLENDİRMEYE bağlıydı. Daha ÖZGÜL desenler önce denenir; hiçbiri tutmazsa
  # `error_message` yine "Hata"dır, yani genel hata listeleri "DogrudanYanit"a
  # DÜŞMEZ.
  if (is.list(response_text) &&
      identical(as.character(response_text$type %||% "")[1], "error_message")) return("Hata")

  "DogrudanYanit"
}

# DB ARIZASI DESENLERİ TEK KAYNAKTADIR: ana süreçteki `.pk_hook_database_failure_text()` ile işçi sınıflandırıcısı AYRI listeler taşıyordu; işçi listesinde `Login failed`, `Data source name not found`, `08001`, `HYT00`, `IM002` gibi bağlantı katmanı imzaları YOKTU ve böyle bir arızada sarmalayıcı telemetri için YENİ bağlantı açıp aynı bloklayan `dbConnect` denemesini tekrarlıyordu. `R/server_init_session_state.R` manifeste göre sonra yüklendiği için sabitleri buradan okur.
PK_DB_FAILURE_PATTERNS <- c(
  "Veritaban\u0131 Hatas\u0131", "SQLSTATE", "ODBC", "nanodbc",
  "Login timeout", "Login failed", "could not connect",
  "Connection refused", "DSN=", "Driver="
)

# İstisna mesajlarında bağlantı katmanı hataları DBI/ODBC biçiminde görünür.
PK_DB_FAILURE_EXCEPTION_PATTERNS <- c(
  "dbConnect", "dbGetQuery", "dbSendQuery", "dbExecute",
  "Data source name not found",
  "08001", "08S01", "HYT00", "IM002"
)

# İşçi çıkışı bir VERİTABANI/ODBC hatası mı? Öyleyse telemetri için YENİ bir
# bağlantı açılmaz: DSN/oturum açma erişilemezken aynı bloklayan denemeyi
# tekrarlamak, işçiyi kullanıcıya dönen hatanın ve son tarihin ötesinde meşgul
# tutardı.
#
# İşçi HER İKİ listeyi de kullanır: doğrudan çıkış sonucu hem kullanıcıya dönen metin hem de yakalanmış bir istisna biçiminde gelebilir, ayrım yapmak yalnızca yanlış negatif üretirdi. Yanlış pozitifin maliyeti OPSİYONEL telemetrinin atlanması, yanlış negatifinki bloklayan bir yeniden bağlanma denemesidir.
pk_direct_exit_is_db_failure <- function(response_text) {
  # LİSTE ŞEKLİ DE DESTEKLENİR: `as.character(list(...))[1]` İLK ÖGEYİ (`type`) döndürürdü, yani `error_message` listesi içinde taşınan DB arızası saptanmıyordu; metin çıkarımı ortak yardımcıdan geçer.
  metin <- pk_direct_exit_text(response_text)
  if (!nzchar(metin)) return(FALSE)

  desenler <- c(PK_DB_FAILURE_PATTERNS, PK_DB_FAILURE_EXCEPTION_PATTERNS)
  any(vapply(desenler, function(d) grepl(d, metin, fixed = TRUE), logical(1)))
}
