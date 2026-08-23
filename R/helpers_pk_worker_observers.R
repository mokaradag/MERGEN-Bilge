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
    Find(Negate(is.null), x[c("message", "answer", "text", "content")]) %||% ""
  } else x
  metin <- tryCatch(as.character(ham)[1], error = function(e) "")
  if (length(metin) != 1L || is.na(metin)) "" else metin
}

pk_direct_exit_outcome <- function(response_text, stopped = FALSE, error = FALSE) {
  if (isTRUE(error)) return("Hata")
  if (isTRUE(stopped)) return("Durduruldu")

  # `type == "error_message"` desen taramasından ÖNCE hata sonucuna eşlenir.
  if (is.list(response_text) &&
      identical(as.character(response_text$type %||% "")[1], "error_message")) return("Hata")

  metin <- pk_direct_exit_text(response_text)

  if (grepl("\u0130\u015flem Durduruldu", metin, fixed = TRUE)) return("Durduruldu")
  if (grepl("Yetki Hatas\u0131", metin, fixed = TRUE)) return("Yetkisiz")
  if (grepl("mevcut analiz k\u00fct\u00fcphanesinde bulunamad\u0131", metin, fixed = TRUE)) {
    return("EslesmeYok")
  }

  "DogrudanYanit"
}

# İşçi çıkışı bir VERİTABANI/ODBC hatası mı? Öyleyse telemetri için YENİ bir
# bağlantı açılmaz: DSN/oturum açma erişilemezken aynı bloklayan denemeyi
# tekrarlamak, işçiyi kullanıcıya dönen hatanın ve son tarihin ötesinde meşgul
# tutardı.
pk_direct_exit_is_db_failure <- function(response_text) {
  metin <- tryCatch(as.character(response_text %||% "")[1], error = function(e) "")
  if (is.na(metin) || !nzchar(metin)) return(FALSE)

  desenler <- c("nanodbc", "SQLSTATE", "ODBC", "Veritaban", "DSN", "Login timeout",
                "Connection", "dbConnect")
  any(vapply(desenler, function(d) grepl(d, metin, fixed = TRUE), logical(1)))
}
