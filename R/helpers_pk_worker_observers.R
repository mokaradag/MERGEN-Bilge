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
