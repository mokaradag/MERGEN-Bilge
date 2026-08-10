# ==============================================================================
# Dosya Yolu: R/helpers_pk_worker_observers.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ-GÜVENLİ PK gözlemci sarmalayıcıları.
#
# NEDEN AYRI DOSYA: bu iki sarmalayıcı ANA SÜREÇTE `server_*` katmanında
# kuruluyordu. Temiz bir PSOCK işçisi o katmanı HİÇ yüklemez (Shiny wiring
# işçiye girmemelidir), dolayısıyla asenkron istekler yalnızca
# `MERGEN_PK_ASYNC` açık olduğu için:
#
#   * doğrudan-çıkış telemetrisini/köken alt bilgisini (kimlik/yetki hatası,
#     eşleşme yok, SQL/yapılandırma hatası) kaybediyordu;
#   * `MERGEN_PK_ENGINE=v2` derin isteklerini v1 olarak kaydediyordu.
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
if (exists("pk_deep_observation_helpers", mode = "function", inherits = TRUE) &&
    !exists(".pk_deep_observation_helpers_core", inherits = TRUE)) {

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
}

# ------------------------------------------------------------------------------
# 2) Standart PK doğrudan-çıkış gözlemcisi
# ------------------------------------------------------------------------------
# Ana motor yalnızca filtre aşamasına ULAŞAN sonuçları gözlemler. Doğrudan
# dönen çıkışlar (başlangıç durdurma, kimlik/yetki, eşleşme yok, SQL/config
# hatası, beklenmeyen istisna) `server_init_chat_runtime.R` sarmalayıcısıyla
# tamamlanıyordu. İşçide o dosya yoktur; sarmalayıcı burada kurulur.
#
# YALNIZCA İŞÇİ KİPİNDE kurulur. Ana süreçte `server_init_chat_runtime.R`
# zaten (daha zengin) sarmalayıcıyı kuruyor; ikisini üst üste bindirmek aynı
# doğrudan çıkış için İKİ telemetri satırı yazma riski taşırdı.
.pk_worker_observer_mode <- isTRUE(tolower(trimws(
  Sys.getenv("MERGEN_PK_WORKER_BOOTSTRAP", unset = "")
)) %in% c("1", "true", "t", "yes", "on"))

if (isTRUE(.pk_worker_observer_mode) &&
    exists("pk_analiz_process_request", mode = "function", inherits = TRUE) &&
    !exists(".pk_worker_analiz_core", inherits = TRUE)) {

  .pk_worker_analiz_core <- get(
    "pk_analiz_process_request", mode = "function", inherits = TRUE
  )

  pk_analiz_process_request <- function(user_prompt, chat_history, session,
                                        stop_check = NULL) {
    basladi <- Sys.time()
    yakalanan <- NULL
    sonuc <- tryCatch(
      .pk_worker_analiz_core(
        user_prompt = user_prompt, chat_history = chat_history,
        session = session, stop_check = stop_check
      ),
      error = function(e) {
        yakalanan <<- e
        e
      }
    )

    istisna <- inherits(sonuc, "condition")
    dogrudan <- istisna || is.character(sonuc) ||
      (is.list(sonuc) && identical(sonuc$type, "error_message"))
    if (!isTRUE(dogrudan)) return(sonuc)

    # Motorun zaten gözlediği yollarda bekleyen bir alt bilgi vardır; ikinci
    # kez yazma.
    bekleyen <- tryCatch(!is.null(session$userData$pk_provenance_pending),
                         error = function(e) FALSE)
    if (isTRUE(bekleyen)) {
      if (istisna) stop(yakalanan)
      return(sonuc)
    }

    if (exists("pk_analysis_observe", mode = "function", inherits = TRUE)) {
      try(pk_analysis_observe(session, NULL, list(
        request_id = tryCatch(
          if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
            pk_provenance_current_request_id(session)
          } else NULL,
          error = function(e) NULL
        ),
        question = user_prompt,
        username = tryCatch(as.character(session$userData$system_username %||% "Unknown")[1],
                            error = function(e) "Unknown"),
        engine = tryCatch(
          if (exists("pk_engine_mode", mode = "function", inherits = TRUE)) pk_engine_mode() else "v1",
          error = function(e) "v1"
        ),
        outcome = if (istisna) "Hata" else "DogrudanYanit",
        duration_ms = as.numeric(difftime(Sys.time(), basladi, units = "secs")) * 1000
      )), silent = TRUE)
    }

    if (istisna) stop(yakalanan)
    sonuc
  }
}

rm(.pk_worker_observer_mode)
