# ==============================================================================
# Dosya Yolu: R/server_init_chat_runtime.R
# Açıklama: server.R içinde kullanılan sohbet çalışma zamanı yardımcılarını
#           kurar. Mesaj ekleme, durum sıfırlama, başlık üretme ve simüle
#           streaming sarmalayıcılarını tek yerde toplar.
# ==============================================================================

serverInitChatRuntime <- function(session, values, settings_data, output,
                                  resolve_current_user_id, stop_generation) {

  # ---------------------------------------------------------------------------
  # Sohbet durumunu sıfırlayan yardımcı
  # ---------------------------------------------------------------------------
  reset_chat_state <- function() {
    chat_reset_state(session, values)
  }

  # ---------------------------------------------------------------------------
  # Oturumun etkin kullanıcı kimliği ile mesaj ekleyen yardımcı
  # ---------------------------------------------------------------------------
  add_message <- function(content, type = "user", html = NULL, followups = NULL,
                          audio_src = NULL, audio_voice = NULL,
                          reasoning_content = NULL) {

    # SQL analizinin doğrudan dönen karakter/hata yanıtları normal LLM
    # sonlandırıcılarına uğramaz. Mesaj ekleme sınırı, bekleyen köken alt
    # bilgisini bütün AI yanıtlarında son bir kez ve idempotent biçimde tüketir.
    #
    # Bu sınırda çağıranın yakalanmış bir istek kimliği YOKTUR; kimlik oturumun
    # ETKİN PK isteğinden okunur. Kimliksiz çağrı artık kabul edilmiyor: aksi
    # hâlde geç biten bir yanıt, daha yeni bir isteğin bekleyen kaydını tüketir.
    if ((identical(type, "ai") || identical(type, "assistant")) &&
        exists("pk_provenance_decorate", mode = "function", inherits = TRUE)) {
      etkin_pk_id <- if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
        tryCatch(pk_provenance_current_request_id(session), error = function(e) NULL)
      } else {
        NULL
      }
      # DEKORASYON HATASI TERMİNAL MESAJI DÜŞÜREMEZ.
      #
      # Bozuk bir bekleyen kayıt burada hata fırlattığında `chat_add_message()`
      # hiç çalışmıyor, kullanıcı yanıtı TAMAMEN kaybediyor ve gönderim durumu
      # takılı kalıyordu. Aynı çağrı `R/server_handler_true_streaming.R` içinde
      # zaten korumalıdır; sözleşme burada da aynıdır: alt bilgi eklenemezse
      # SÜSLENMEMİŞ içerik teslim edilir.
      content <- tryCatch(
        pk_provenance_decorate(content, session, request_id = etkin_pk_id),
        error = function(e) {
          cat(sprintf("[PK] Köken alt bilgisi eklenemedi: %s\n", conditionMessage(e)[1]))
          content
        }
      )
    }

    effective_user_id <- resolve_current_user_id()

    chat_add_message(
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      content = content,
      type = type,
      html = html,
      current_user_id = effective_user_id,
      followups = followups,
      audio_src = audio_src,
      audio_voice = audio_voice,
      reasoning_content = reasoning_content
    )
  }

  # ---------------------------------------------------------------------------
  # Sohbet başlığı üreten yardımcı
  # ---------------------------------------------------------------------------
  generate_title_from_prompt <- function(prompt, max_len = 60) {
    chat_generate_title_from_prompt(prompt, max_len)
  }

  # ---------------------------------------------------------------------------
  # Simüle streaming sarmalayıcısı
  # ---------------------------------------------------------------------------
  simulate_streaming_stoppable <- function(full_response, followups = NULL,
                                           on_complete = NULL, on_start = NULL,
                                           tts_engine = NULL, tts_voice = NULL,
                                           request_id = NULL) {
    chat_simulate_streaming(
      request_id = request_id,
      full_response = full_response,
      session = session,
      values = values,
      settings_data = settings_data,
      output = output,
      stop_generation = stop_generation,
      followups = followups,
      on_complete = on_complete,
      on_start = on_start,
      tts_engine = tts_engine,
      tts_voice = tts_voice
    )
  }

  list(
    reset_chat_state = reset_chat_state,
    add_message = add_message,
    generate_title_from_prompt = generate_title_from_prompt,
    simulate_streaming_stoppable = simulate_streaming_stoppable
  )
}

# ==============================================================================
# Proje/Kaynak Analizi — doğrudan çıkış gözlem güvenlik ağı
# ==============================================================================
# module_proje_kaynak_analizi.R bu dosyadan önce yüklenir. Ana analiz motoru,
# filtre aşamasına ulaşan sonuçları kendi bağlamında gözlemler. Aşağıdaki ince
# sarmalayıcı yalnızca motorun doğrudan döndüğü ve henüz köken alt bilgisi
# bırakmadığı çıkışları (başlangıç durdurma, kimlik/yetki, eşleşme yok, SQL ve
# yapılandırma hataları ile beklenmeyen istisnalar) tamamlar. Böylece başarılı
# yolların telemetrisi yinelenmez.
# SENTINEL YÜRÜRLÜKTEKİ FONKSİYONA GÖRE DE TAZELENİR: yalnızca sentinel varlığına bakmak, `R/module_proje_kaynak_analizi.R` bu dosyadan SONRA yeniden source edildiğinde (bootstrap parmak izi tazelemesi, `global.R` yeniden yüklemesi) BAYAT çekirdeği kalıcı hâle getiriyordu; `pk_hook_single_exit_fix_install()` o eski çekirdeği sarmalayıp public sembole atadığı için boru hattı ÖNCEKİ revizyonu çalıştırıyordu. Sarmalanmış bir fonksiyon ASLA çekirdek olarak yakalanmaz (işaret çözülemiyorsa da yakalanmaz: çift sarmalama riski).
if (exists("pk_analiz_process_request", mode = "function", inherits = TRUE) &&
    (!exists(".pk_analiz_process_request_without_exit_observer", inherits = FALSE) ||
     (exists(".pk_hook_single_exit_is_wrapped", mode = "function", inherits = TRUE) &&
      !isTRUE(.pk_hook_single_exit_is_wrapped(
        get("pk_analiz_process_request", mode = "function", inherits = TRUE)
      ))))) {
  .pk_analiz_process_request_without_exit_observer <- get(
    "pk_analiz_process_request", mode = "function", inherits = TRUE
  )
}

# YEDEK SARMALAYICI YALNIZCA KURULUM YARDIMCISI YOKKEN KURULUR.
#
# `pk_hook_single_exit_fix_install()` (R/server_init_session_state.R) HAM
# çekirdeği sarmalar ve `pk_analiz_process_request`'i AYNI çalışma ortamında
# yeniden atar. Aşağıdaki sarmalayıcı bu yüzden varsayılan yapılandırmada çağrı
# zincirinden ÇIKARILIYOR ve gövdesi ULAŞILMAZ kalıyordu: iki kopya zamanla
# ayrışmış, birinde yapılan düzeltme diğerinde etkisiz kalmıştı. Tek sahip artık
# kurulum yardımcısıdır; burası yalnızca o yardımcı yoksa devreye giren yedektir.
# Kontrol ARAMA YOLUNA değil HEDEF ORTAMA bakar (`inherits = FALSE`): üretimde
# her iki dosya da `globalenv()` içine kaynaklandığı için davranış aynıdır, ama
# izole bir test/işçi ortamında arama yolunda kalan bir kurulum yardımcısı bu
# yedeği SESSİZCE devre dışı bırakıp telemetriyi tümden düşürüyordu.
if (!exists("pk_hook_single_exit_fix_install", mode = "function",
            envir = environment(), inherits = FALSE) &&
    exists(".pk_analiz_process_request_without_exit_observer",
           mode = "function", inherits = FALSE)) {

  pk_analiz_process_request <- function(user_prompt, chat_history, session,
                                        stop_check = NULL) {
    started_at <- Sys.time()
    caught_error <- NULL
    result <- tryCatch(
      .pk_analiz_process_request_without_exit_observer(
        user_prompt = user_prompt,
        chat_history = chat_history,
        session = session,
        stop_check = stop_check
      ),
      error = function(e) {
        caught_error <<- e
        e
      }
    )

    is_exception <- inherits(result, "condition")
    is_direct_exit <- is_exception || is.character(result) ||
      (is.list(result) && identical(result$type, "error_message"))
    if (!isTRUE(is_direct_exit)) return(result)

    # Motorun RLS-sıfır/filtre-sıfır gibi zaten gözlediği doğrudan yanıtlarında
    # bekleyen bir alt bilgi vardır. Onları ikinci kez yazma.
    has_pending_footer <- tryCatch(
      !is.null(session$userData$pk_provenance_pending),
      error = function(e) FALSE
    )
    if (isTRUE(has_pending_footer)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    # Windows SSO başlangıcında kimlik henüz kesinleşmemişken ana motor bilinçli
    # olarak DB bağlantısı açmadan "kimlik hazırlanıyor" yanıtı döndürür. Bu
    # güvenlik ağı o sınırı telemetri uğruna delmemelidir.
    auth_pending <- tryCatch(
      identical(session$userData$auth_initialized, FALSE),
      error = function(e) FALSE
    )
    if (isTRUE(auth_pending)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    if (!exists("pk_analysis_observe", mode = "function", inherits = TRUE)) {
      if (is_exception) stop(caught_error)
      return(result)
    }

    # `conditionMessage()` SKALER OLMAYABİLİR: çok elemanlı bir koşul mesajı
    # `is.na()`/`if()` çağrılarını hata işleyicinin İÇİNDE düşürür, özgün
    # başarısızlığı gizler ve telemetriyi bastırırdı.
    .skaler <- function(x) {
      if (is.null(x) || length(x) == 0L) return("")
      out <- as.character(x)[1]
      if (is.na(out)) "" else out
    }
    response_text <- if (is_exception) {
      .skaler(conditionMessage(result))
    } else if (is.character(result)) {
      .skaler(result)
    } else {
      .skaler(result$content)
    }

    stopped <- grepl("İşlem Durduruldu", response_text, fixed = TRUE)
    no_match <- grepl("mevcut analiz kütüphanesinde bulunamadı", response_text, fixed = TRUE)

    # YETKİ REDDİ DÜZYAZIDAN SINIFLANDIRILMAZ. `pk_rls_denied_message()` üç
    # farklı metin üretir (`db_error` / `ambiguous` / `not_found`) ve yalnızca
    # `not_found` metni "Yetki Hatası" içerir; diğer ikisi `"Hata"` olarak
    # kaydediliyor ve yetki reddi metrikleri EKSİK sayıyordu. Tüm RLS reddi
    # metinleri tek yerden tanınır.
    unauthorized <- grepl("Yetki Hatası", response_text, fixed = TRUE) ||
      (exists("pk_rls_denied_message", mode = "function", inherits = TRUE) &&
         isTRUE(tryCatch(
           any(vapply(c("db_error", "ambiguous", "not_found"), function(durum) {
             mesaj <- as.character(pk_rls_denied_message(durum))[1]
             is.character(mesaj) && nzchar(mesaj) &&
               identical(trimws(response_text), trimws(mesaj))
           }, logical(1))),
           error = function(e) FALSE
         )))

    outcome <- if (stopped) {
      "Durduruldu"
    } else if (unauthorized) {
      "Yetkisiz"
    } else if (no_match) {
      "EslesmeYok"
    } else {
      "Hata"
    }

    request_id <- if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
      tryCatch(pk_provenance_current_request_id(session), error = function(e) NULL)
    } else {
      NULL
    }

    username <- tryCatch(
      session$userData$system_username %||%
        session$userData$username %||%
        session$userData$user_name %||%
        "Unknown",
      error = function(e) "Unknown"
    )
    user_id <- tryCatch(session$userData$user_id %||% NULL, error = function(e) NULL)

    # DURDURULMUŞ ÇIKIŞ YENİ BİR VERİTABANI BAĞLANTISI AÇMAZ.
    #
    # Kullanıcı Durdur'a bastığında `pk_analiz_process_request()` veritabanına
    # HİÇ dokunmadan durdurma mesajıyla döner. Buradaki koşulsuz
    # `get_connection()` ise yalnızca telemetri yazmak için PAYLAŞILAN Shiny
    # olay döngüsünde bloklayıcı bir ODBC oturum açma denemesi başlatıyordu;
    # havuz tükendiğinde veya DSN girişi yavaş olduğunda iptal edilmiş bir
    # istek yüzünden tüm oturumlar bekliyordu. Aynı dosyadaki derin analiz yolu
    # ve `R/server_init_session_state.R` bu atlamayı zaten yapar; telemetri
    # `conn = NULL` ile fail-soft çalışır.
    conn_list <- if (isTRUE(stopped)) {
      NULL
    } else {
      tryCatch(get_connection(), error = function(e) NULL)
    }
    conn <- if (is.list(conn_list)) conn_list$conn %||% NULL else NULL
    if (!is.null(conn_list)) {
      on.exit(try(release_connection(conn_list), silent = TRUE), add = TRUE)
    }

    try(
      pk_analysis_observe(session, conn, list(
        request_id = request_id,
        question = user_prompt,
        username = username,
        user_id = user_id,
        deep_thinking = FALSE,
        query_name = "Tekil analiz",
        filter_status = if (stopped) "stopped" else "not_reached",
        filters = list(),
        outcome = outcome,
        duration_ms = as.numeric(difftime(Sys.time(), started_at, units = "secs")) * 1000
      )),
      silent = TRUE
    )

    if (is_exception) stop(caught_error)
    result
  }

  # YEDEK SARMALAYICI DA "SARMALANMIŞ" DİYE İŞARETLENİR.
  #
  # Yukarıdaki çekirdek yakalama kapısı bir fonksiyonu yalnızca
  # `.pk_hook_single_exit_is_wrapped()` FALSE dediğinde ham çekirdek sayar. Bu
  # yedek sarmalayıcı işareti taşımadığı için, dosya yeniden source edildiğinde
  # (bootstrap parmak izi tazelemesi, `global.R` yeniden yüklemesi) kapı ONU
  # çekirdek olarak yakalıyor ve üzerine ikinci bir sarmalayıcı kuruyordu.
  # Zincir her tazelemede bir halka uzuyor, aynı doğrudan çıkış için
  # `MB_Analiz_Log` tablosuna YİNELENEN satırlar yazılıyordu. İşaret,
  # `R/server_init_session_state.R` ile AYNI özniteliktir; o dosya manifestte
  # bundan ÖNCE yüklendiği için sembol burada görünür, yine de yokluğuna karşı
  # savunmalı davranılır (işaretlenemezse davranış eski hâline döner).
  if (exists(".PK_HOOK_SINGLE_EXIT_MARK", inherits = TRUE)) {
    attr(pk_analiz_process_request, get(".PK_HOOK_SINGLE_EXIT_MARK", inherits = TRUE)) <- TRUE
  }
}

# ==============================================================================
# Derin analiz — giriş anındaki iptali gözlemle
# ==============================================================================
# Derin analiz motorunun kendi gözlemcisi ilk stop_check() dönüşünden sonra
# kuruluyordu. Bu ince sarmalayıcı yalnızca çağrı girişinde zaten iptal edilmiş
# istekleri yakalar; diğer bütün yolları değiştirmeden asıl motora devreder.
# MUHAFIZ SARMALAYICININ KENDİSİNE BAKAR, SAKLANAN ÖZGÜN KOPYAYA DEĞİL.
#
# Eski koşul `.pk_deep_analysis_process_without_entry_observer` nesnesinin
# VARLIĞINA bakıyordu. `R/module_proje_kaynak_analizi.R` bu dosyadan SONRA
# yeniden source edilirse (ör. bootstrap parmak izi tazelemesi)
# `pk_deep_analysis_process` sarmalanmamış hâline döner ama sentinel nesne
# YERİNDE KALIR; muhafız `FALSE` olur, sarmalayıcı YENİDEN KURULMAZ ve derin
# istekler için giriş anı iptal telemetrisi sessizce yazılmaz olur.
# `R/helpers_pk_worker_observers.R` ile AYNI desen: sarmalayıcı işaretlenir.
.PK_DEEP_ENTRY_WRAP_MARK <- "pk_deep_entry_observer_wrapped"

.pk_deep_entry_is_wrapped <- function(fn) {
  is.function(fn) && isTRUE(attr(fn, .PK_DEEP_ENTRY_WRAP_MARK, exact = TRUE))
}

if (exists("pk_deep_analysis_process", mode = "function", inherits = TRUE) &&
    !.pk_deep_entry_is_wrapped(get("pk_deep_analysis_process", mode = "function",
                                   inherits = TRUE))) {

  .pk_deep_analysis_process_without_entry_observer <- get(
    "pk_deep_analysis_process", mode = "function", inherits = TRUE
  )

  pk_deep_analysis_process <- function(user_prompt, chat_history, session,
                                       detail_level = "standart",
                                       stop_check = NULL) {
    # HATALI `stop_check` İSTEĞİ DÜŞÜRMEZ: bu hattaki diğer çağrı yerleriyle
    # AYNI fail-soft kapı uygulanır (örneğin reaktif değer okuyan bir geri
    # çağrı, reaktif bağlam dışında hata fırlatır ve derin istek motor hiç
    # çağrılmadan düşerdi).
    entry_stopped <- is.function(stop_check) &&
      isTRUE(tryCatch(stop_check(), error = function(e) FALSE))
    if (!isTRUE(entry_stopped)) {
      return(.pk_deep_analysis_process_without_entry_observer(
        user_prompt = user_prompt,
        chat_history = chat_history,
        session = session,
        detail_level = detail_level,
        stop_check = stop_check
      ))
    }

    # SSO kimliği bekleniyorsa iptal yanıtı DB erişimi başlatmamalıdır. Kimlik
    # hazır olduğunda ise iptal hem telemetriye hem köken alt bilgisine yazılır.
    auth_pending <- tryCatch(
      identical(session$userData$auth_initialized, FALSE),
      error = function(e) FALSE
    )
    if (!isTRUE(auth_pending) &&
        exists("pk_analysis_observe", mode = "function", inherits = TRUE)) {
      started_at <- Sys.time()
      request_id <- if (exists("pk_provenance_current_request_id", mode = "function", inherits = TRUE)) {
        tryCatch(pk_provenance_current_request_id(session), error = function(e) NULL)
      } else {
        NULL
      }
      username <- tryCatch(
        session$userData$system_username %||%
          session$userData$username %||%
          session$userData$user_name %||%
          "Unknown",
        error = function(e) "Unknown"
      )
      user_id <- tryCatch(session$userData$user_id %||% NULL, error = function(e) NULL)

      # DURDURULMUŞ GİRİŞ YENİ BİR BAĞLANTI AÇMAZ.
      #
      # Bu dala YALNIZCA `entry_stopped` doğruyken girilir; iptal ZATEN
      # onaylanmıştır. Havuz tükenmişse ya da DSN login'i yavaşsa
      # `get_connection()` yalnızca telemetri yazmak için ANA Shiny olay
      # döngüsünü bloklardı. Tek analiz yolu (`R/server_init_session_state.R`)
      # `stopped` için aynı atlamayı yapar; telemetri `conn = NULL` ile
      # fail-soft çalışır.
      try(
        pk_analysis_observe(session, NULL, list(
          request_id = request_id,
          question = user_prompt,
          username = username,
          user_id = user_id,
          deep_thinking = TRUE,
          query_name = "Derin analiz",
          filter_status = "stopped",
          filters = list(),
          outcome = "Durduruldu",
          duration_ms = as.numeric(difftime(Sys.time(), started_at, units = "secs")) * 1000
        )),
        silent = TRUE
      )
    }

    "\U000026A0\U0000FE0F **İşlem Durduruldu:** Analiz kullanıcı tarafından iptal edildi."
  }

  # SARMALAYICI İŞARETLENİR: kurulum idempotenttir ve modül yeniden source
  # edildiğinde muhafız sarmalayıcının GERÇEKTEN yerinde olup olmadığını görür.
  attr(pk_deep_analysis_process, .PK_DEEP_ENTRY_WRAP_MARK) <- TRUE
}

# PR #695 Codex düzeltmesi: Yukarıdaki temel doğrudan-çıkış sarmalayıcısı
# kurulduktan sonra DB-hata tekrar bağlantısı ve filtre temizliği sertleştirmesini
# etkinleştir.
# Aynı ortam kuralı: yardımcı YALNIZCA bu ortamda tanımlıysa çağrılır. Arama
# yolundaki bir kopya `pk_analiz_process_request`'i KENDİ ortamında yeniden
# atardı ve bu ortam sarmalanmamış kalırdı.
if (exists("pk_hook_single_exit_fix_install", mode = "function",
           envir = environment(), inherits = FALSE)) {
  pk_hook_single_exit_fix_install()
}
