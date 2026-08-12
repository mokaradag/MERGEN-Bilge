# ==============================================================================
# Dosya Yolu: R/helpers_pk_worker_direct_exit.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ kipinde standart PK DOĞRUDAN-ÇIKIŞ gözlemci
#           sarmalayıcısı.
#
# NEDEN AYRI DOSYA: `R/helpers_pk_worker_observers.R` derin gözlemci fabrika
# kapsamına odaklanır ve bakım oranı bütçesindedir. Doğrudan-çıkış sarmalayıcısı
# ise ayrı bir sorumluluktur (telemetri + kısa ömürlü DB bağlantısı) ve
# YALNIZCA işçi kipinde kurulur. İkisini aynı dosyada tutmak, bütçeyi gizlice
# gevşetmeyi gerektirirdi.
#
# Bu dosya `R/helpers_pk_worker_observers.R` HEMEN ARDINDAN yüklenmelidir:
# `.pk_worker_is_wrapped()` yardımcısı orada tanımlıdır.
# ==============================================================================

# Ana motor yalnızca filtre aşamasına ULAŞAN sonuçları gözlemler. Doğrudan
# dönen çıkışlar (başlangıç durdurma, kimlik/yetki, eşleşme yok, SQL/config
# hatası, beklenmeyen istisna) `server_init_chat_runtime.R` sarmalayıcısıyla
# tamamlanıyordu. İşçide o dosya yoktur; sarmalayıcı burada kurulur.
#
# YALNIZCA İŞÇİ KİPİNDE kurulur. Ana süreçte `server_init_chat_runtime.R`
# zaten (daha zengin) sarmalayıcıyı kuruyor; ikisini üst üste bindirmek aynı
# doğrudan çıkış için İKİ telemetri satırı yazma riski taşırdı.
.pk_worker_direct_exit_mode <- isTRUE(tolower(trimws(
  Sys.getenv("MERGEN_PK_WORKER_BOOTSTRAP", unset = "")
)) %in% c("1", "true", "t", "yes", "on"))

# Doğrudan-çıkış telemetrisi için KISA ÖMÜRLÜ bağlantı. Bağlantı açılamazsa
# telemetri sessizce atlanır (kullanıcı yanıtı ETKİLENMEZ).
.pk_worker_observer_connection <- function() {
  if (!exists("get_connection", mode = "function", inherits = TRUE)) {
    return(list(conn = NULL, conn_info = NULL))
  }
  bilgi <- tryCatch(get_connection(), error = function(e) NULL)
  if (is.null(bilgi)) return(list(conn = NULL, conn_info = NULL))
  list(conn = tryCatch(bilgi$conn, error = function(e) NULL), conn_info = bilgi)
}

if (isTRUE(.pk_worker_direct_exit_mode) &&
    exists(".pk_worker_is_wrapped", mode = "function", inherits = TRUE) &&
    exists("pk_analiz_process_request", mode = "function", inherits = TRUE) &&
    !.pk_worker_is_wrapped(
      get("pk_analiz_process_request", mode = "function", inherits = TRUE),
      "pk_worker_direct_exit_wrapper"
    )) {

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

    durduruldu <- isTRUE(tryCatch(
      is.function(stop_check) && isTRUE(stop_check()), error = function(e) FALSE
    ))

    # DURDURMA GÖZLENDİKTEN SONRA YENİ DB İŞİ BAŞLATILMAZ (PR #703 incelemesi).
    #
    # Telemetri OPSİYONELDİR; iptal ise kullanıcının AÇIK talebidir. Burada bir
    # havuz checkout'u/login'i açmak, Durdur'u zaten gözlemiş bir isteği yavaş
    # bir DSN veya telemetri yazımı kadar daha bekletir ve işçi yuvası + DB
    # oturumu o süre boyunca meşgul kalır. İptal TEARDOWN'a doğru ilerlemelidir.
    if (isTRUE(durduruldu)) {
      if (istisna) stop(yakalanan)
      return(sonuc)
    }

    if (exists("pk_analysis_observe", mode = "function", inherits = TRUE)) {
      # CANLI BAĞLANTI ZORUNLUDUR: `pk_telemetry_log_analysis()` `conn = NULL`
      # iken HEMEN `FALSE` döner, yani bu sarmalayıcı geri getirmesi gereken
      # doğrudan çıkışların HİÇBİRİNİ `MB_Analiz_Log`'a yazmaz; yalnızca köken
      # kaydını bırakırdı. Ana süreçteki karşılığı da bağlantıyı açıp bırakır.
      baglanti <- .pk_worker_observer_connection()
      if (!is.null(baglanti$conn_info)) {
        on.exit(try(release_connection(baglanti$conn_info), silent = TRUE), add = TRUE)
      }

      try(pk_analysis_observe(session, baglanti$conn, list(
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
        # FİLTRE DURUMU AÇIKÇA VERİLİR. Alan eksik olduğunda
        # `pk_analysis_observe()` onu `"error"` olarak normalleştiriyor ve
        # "filtre çıkarımı başarısız; analiz TÜM yetkili küme üzerinde
        # çalıştı" alt bilgisini üretiyordu — oysa bu çıkışlarda filtre
        # aşamasına HİÇ ULAŞILMAMIŞTIR. Kullanıcıya YANLIŞ bir bozulma
        # bildirimi gitmesi kabul edilemez.
        filter_status = if (isTRUE(durduruldu)) "stopped" else "not_reached",
        filters = list(),
        outcome = if (istisna) "Hata" else if (isTRUE(durduruldu)) "Durduruldu" else "DogrudanYanit",
        duration_ms = as.numeric(difftime(Sys.time(), basladi, units = "secs")) * 1000
      )), silent = TRUE)
    }

    if (istisna) stop(yakalanan)
    sonuc
  }
  attr(pk_analiz_process_request, "pk_worker_direct_exit_wrapper") <- TRUE
}

rm(.pk_worker_direct_exit_mode)
