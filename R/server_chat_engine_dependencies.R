# ==============================================================================
# Dosya Yolu: R/server_chat_engine_dependencies.R
# Açıklama: Sohbet motoru için server.R ile server_module_wiring.R arasında
#           taşınan dış bağımlılıkları küçük ve doğrulanabilir bir bundle altında
#           toplar. Runtime state/cache/file/chat bağlamı runtime_ctx içinde kalır.
# ==============================================================================

.server_wiring_require_chat_engine_deps <- function(chat_engine_deps) {
  if (!is.list(chat_engine_deps)) {
    .server_wiring_stop(
      "chat_engine_deps liste olmalıdır."
    )
  }

  .server_runtime_require_values(
    chat_engine_deps,
    c(
      "settings_data",
      "api_key",
      "user_config_rv",
      "perf_tracker",
      "ai_processor",
      "tts_processor",
      "tts_visualizer",
      "stt_data",
      "saved_chats_data",
      "send_message_fns",
      "send_message_proxy",
      "api_config"
    ),
    "chat_engine_deps"
  )

  .server_wiring_require_environment(
    chat_engine_deps$send_message_fns,
    "chat_engine_deps$send_message_fns"
  )

  .server_wiring_require_functions(list(
    send_message_proxy = chat_engine_deps$send_message_proxy,
    perf_tracker_track_error = chat_engine_deps$perf_tracker$track_error,
    perf_tracker_track_request = chat_engine_deps$perf_tracker$track_request,
    ai_processor_call_llm_non_streaming = chat_engine_deps$ai_processor$call_llm_non_streaming
  ))

  invisible(TRUE)
}

serverBuildChatEngineDependencyBundle <- function(settings_data,
                                                  api_key,
                                                  user_config_rv,
                                                  perf_tracker,
                                                  saved_chats_data,
                                                  send_message_fns,
                                                  send_message_proxy,
                                                  api_config,
                                                  media_modules = NULL,
                                                  ai_processor = NULL,
                                                  tts_processor = NULL,
                                                  tts_visualizer = NULL,
                                                  stt_data = NULL,
                                                  admin_pool = NULL,
                                                  feedback_modal = NULL) {
  if (!is.null(media_modules)) {
    if (is.null(ai_processor)) {
      ai_processor <- media_modules$ai_processor
    }

    if (is.null(tts_processor)) {
      tts_processor <- media_modules$tts_processor
    }

    if (is.null(tts_visualizer)) {
      tts_visualizer <- media_modules$tts_visualizer
    }

    if (is.null(stt_data)) {
      stt_data <- media_modules$stt_data
    }

    if (is.null(feedback_modal)) {
      feedback_modal <- media_modules$feedback_modal
    }
  }

  chat_engine_deps <- list(
    settings_data = settings_data,
    api_key = api_key,
    user_config_rv = user_config_rv,
    perf_tracker = perf_tracker,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    tts_visualizer = tts_visualizer,
    stt_data = stt_data,
    saved_chats_data = saved_chats_data,
    send_message_fns = send_message_fns,
    send_message_proxy = send_message_proxy,
    api_config = api_config,
    admin_pool = admin_pool,
    feedback_modal = feedback_modal
  )

  .server_wiring_require_chat_engine_deps(chat_engine_deps)

  class(chat_engine_deps) <- c(
    "mergen_chat_engine_dependency_bundle",
    "list"
  )

  chat_engine_deps
}

.server_wiring_resolve_chat_engine_deps <- function(chat_engine_deps,
                                                    settings_data,
                                                    api_key,
                                                    user_config_rv,
                                                    perf_tracker,
                                                    saved_chats_data,
                                                    send_message_fns,
                                                    send_message_proxy,
                                                    api_config,
                                                    media_modules = NULL,
                                                    ai_processor = NULL,
                                                    tts_processor = NULL,
                                                    tts_visualizer = NULL,
                                                    stt_data = NULL,
                                                    admin_pool = NULL,
                                                    feedback_modal = NULL) {
  if (!is.null(chat_engine_deps)) {
    .server_wiring_require_chat_engine_deps(chat_engine_deps)
    return(chat_engine_deps)
  }

  serverBuildChatEngineDependencyBundle(
    settings_data = settings_data,
    api_key = api_key,
    user_config_rv = user_config_rv,
    perf_tracker = perf_tracker,
    saved_chats_data = saved_chats_data,
    send_message_fns = send_message_fns,
    send_message_proxy = send_message_proxy,
    api_config = api_config,
    media_modules = media_modules,
    ai_processor = ai_processor,
    tts_processor = tts_processor,
    tts_visualizer = tts_visualizer,
    stt_data = stt_data,
    admin_pool = admin_pool,
    feedback_modal = feedback_modal
  )
}

# =============================================================================
# PR #695 — Derin analiz ve Ortak Oturum Codex çalışma zamanı düzeltmeleri
# =============================================================================
# CHECKOUT KİMLİĞİ `conn` NESNESİNDEN GELMEZ.
#
# Havuz bir sonraki checkout'ta genellikle AYNI `conn` nesnesini geri verir;
# `identical(left$conn, right$conn)` iki AYRI checkout'u aynı sayıyordu. Sonuç:
# RLS okumasından sonra iade edilen birincil bağlantı için `primary_released`
# TRUE kalıyor, bir sonraki sorgunun checkout'u izlenmiyor ve onun
# `on.exit(release_connection(...))` çağrısı GERÇEK iadeyi ATLIYORDU — yaklaşık
# her ikinci derin sorgu bir havuz yuvası sızdırıyordu. Kimlik artık
# sarmalayıcının kendi ürettiği JETONDUR ve döndürülen nesneye iliştirilir.
.PK_HOOK_TOKEN_ATTR <- "pk_hook_checkout_token"

.pk_hook_checkout_token <- function(x) {
  if (is.null(x)) return(NULL)
  attr(x, .PK_HOOK_TOKEN_ATTR, exact = TRUE)
}

# BIRAKILMIŞ (stale) BAGLANTI KAYDI.
#
# Çekirdek, birincil bağlantıyı RLS okumasindan sonra havuza iade eder; elindeki
# `conn` referansi bu noktadan sonra ARTIK CHECKOUT DEGILDIR. Ayni referansla
# telemetri sorgusu çalıştırmak "use-after-release" olur. Kayit, YALNIZCA bu
# sarmalayıcının gercekten iade ettigi baglantilari izler; conn_provider gibi
# izlenmeyen yollardan gelen CANLI baglantilar bilinmez kalır ve olduğu gibi
# kullanılır (gereksiz ikinci checkout acilmaz).
.PK_HOOK_RELEASED_CAP <- 8L

.pk_hook_conn_is_released <- function(conn, state) {
  kayit <- state$released
  if (is.null(conn) || !is.list(kayit) || length(kayit) == 0L) return(FALSE)
  for (eski in kayit) if (identical(eski, conn)) return(TRUE)
  FALSE
}

.pk_hook_mark_released <- function(conn, state) {
  if (is.null(conn)) return(invisible(NULL))
  kayit <- if (is.list(state$released)) state$released else list()
  kayit <- Filter(function(eski) !identical(eski, conn), kayit)
  kayit <- c(kayit, list(conn))
  if (length(kayit) > .PK_HOOK_RELEASED_CAP) {
    kayit <- kayit[seq(length(kayit) - .PK_HOOK_RELEASED_CAP + 1L, length(kayit))]
  }
  state$released <- kayit
  invisible(NULL)
}

.pk_hook_mark_acquired <- function(conn, state) {
  if (is.null(conn) || !is.list(state$released)) return(invisible(NULL))
  state$released <- Filter(function(eski) !identical(eski, conn), state$released)
  invisible(NULL)
}

# Derin analiz henüz server_init_chat_runtime.R giriş-iptal sarmalayıcısını
# almadan önce çekirdeği sarılır. İlk bağlantı yalnızca RLS kimlik okumasına
# kadar yaşar; gözlem çağrıları kısa ömürlü telemetri bağlantıları kullanır.
if (exists("pk_deep_analysis_process", mode = "function", inherits = TRUE) &&
    !exists(".pk_hook_deep_core", inherits = FALSE)) {

  .pk_hook_deep_core <- get(
    "pk_deep_analysis_process", mode = "function", inherits = TRUE
  )
  .pk_hook_deep_core_env <- environment(.pk_hook_deep_core)
  .pk_hook_real_get_connection <- get(
    "get_connection", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )
  .pk_hook_real_release_connection <- get(
    "release_connection", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )
  .pk_hook_real_get_user_rls_info <- get(
    "get_user_rls_info", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )
  .pk_hook_real_pk_analysis_observe <- get(
    "pk_analysis_observe", mode = "function", envir = .pk_hook_deep_core_env, inherits = TRUE
  )

  pk_deep_analysis_process <- function(user_prompt, chat_history, session,
                                       detail_level = "standart",
                                       stop_check = NULL) {
    request_id <- .pk_hook_current_request_id(session)
    on.exit(
      try(pk_filter_observation_clear(request_id, user_prompt), silent = TRUE),
      add = TRUE
    )

    state <- new.env(parent = emptyenv())
    state$primary <- NULL
    state$primary_released <- FALSE
    state$released <- list()
    state$token_seq <- 0L
    state$released_tokens <- character(0)

    call_env <- new.env(parent = .pk_hook_deep_core_env)

    # `target` SARMALAYICIDA DA KABUL EDİLİR VE İLETİLİR.
    #
    # Gerçek `get_connection(target = "primary")` imzasını taşımayan bir
    # sarmalayıcı, hedef belirten her çağrıda "unused argument" ile düşerdi.
    # Yalnızca BİRİNCİL bağlantı yaşam döngüsü izlenir; ikincil/üçüncül hedefler
    # çağıranın kendi `release_connection()` sözleşmesine tabidir.
    call_env$get_connection <- function(target = "primary") {
      conn_list <- .pk_hook_real_get_connection(target)
      if (is.list(conn_list)) .pk_hook_mark_acquired(conn_list$conn %||% NULL, state)
      if (identical(target, "primary") && is.list(conn_list)) {
        # HER birincil checkout AYRI bir jeton alır; jeton çağırana verilen
        # nesnede taşınır ve bırakma sırasında geri okunur.
        state$token_seq <- state$token_seq + 1L
        attr(conn_list, .PK_HOOK_TOKEN_ATTR) <- paste0("pk", state$token_seq)
        if (is.null(state$primary)) {
          state$primary <- conn_list
          state$primary_released <- FALSE
        }
      }
      conn_list
    }

    call_env$release_connection <- function(conn_list) {
      # ÇİFT BIRAKMA yalnızca AYNI checkout jetonu için bastırılır; geri
      # dönüştürülmüş bir `conn` nesnesi taşıyan YENİ checkout GERÇEKTEN iade
      # edilir. `state$primary` gerçek bırakma ANINDA temizlenir; böylece
      # sonraki edinim yeniden izlenir.
      jeton <- .pk_hook_checkout_token(conn_list)
      if (!is.null(jeton)) {
        if (jeton %in% state$released_tokens) return(invisible(NULL))
        state$released_tokens <- c(state$released_tokens, jeton)
        if (identical(jeton, .pk_hook_checkout_token(state$primary))) {
          state$primary <- NULL
          state$primary_released <- TRUE
        }
      }
      if (is.list(conn_list)) .pk_hook_mark_released(conn_list$conn %||% NULL, state)
      .pk_hook_real_release_connection(conn_list)
    }

    call_env$get_user_rls_info <- function(username, conn) {
      on.exit({
        # `state$primary` gerçek bırakmada temizlendiği için ek bayrak denetimi
        # gerekmez; dolu olması "henüz iade edilmedi" demektir.
        if (!is.null(state$primary)) {
          try(call_env$release_connection(state$primary), silent = TRUE)
        }
      }, add = TRUE)
      .pk_hook_real_get_user_rls_info(username, conn)
    }

    call_env$pk_analysis_observe <- function(session, conn, info) {
      # ÇAĞIRANIN AÇTIĞI BAĞLANTI YENİDEN AÇILMAZ.
      #
      # `helpers_deep_analysis.R` gözlem katmanına `conn_provider =
      # pk_deep_short_lived_conn_provider()` verir; yani `conn` ZATEN açılmış
      # kısa ömürlü bağlantıdır. Bu sarmalayıcı onu yok sayıp ikinci bir
      # bağlantı açıyordu: her gözlem (çalıştırılan sorgu başına bir tane, artı
      # terminal gözlemler) havuzdan İKİ checkout tüketiyor, sağlayıcının
      # bağlantısı ise hiç kullanılmadan açılıp bırakılıyordu.
      #
      # ANCAK BIRAKILMIŞ BİR REFERANS YENİDEN KULLANILMAZ: çekirdek, birincil
      # bağlantıyı RLS okumasından sonra havuza iade eder ve elindeki `conn`
      # değişkenini gözleme yine de geçirir. Bu referansla sorgu çalıştırmak
      # "use-after-release" olurdu; bu durumda kısa ömürlü YENİ bir bağlantı
      # açılır. İzlenmeyen (conn_provider) canlı bağlantılar etkilenmez.
      if (!is.null(conn) && !.pk_hook_conn_is_released(conn, state)) {
        return(.pk_hook_real_pk_analysis_observe(session, conn, info))
      }
      telemetry_list <- tryCatch(
        .pk_hook_real_get_connection(),
        error = function(e) NULL
      )
      telemetry_conn <- if (is.list(telemetry_list)) {
        telemetry_list$conn %||% NULL
      } else {
        NULL
      }
      # YENİDEN EDİNİLEN NESNE ARTIK CANLIDIR. Havuz bir sonraki checkout'ta
      # AYNI `conn` nesnesini geri verir; kayıt temizlenmezse o CANLI bağlantı
      # da `.pk_hook_conn_is_released()` tarafından "bırakılmış" sanılır ve
      # kalan HER gözlem için ikinci bir checkout açılırdı -- bu sarmalayıcının
      # tam da kaldırdığı çift-checkout davranışı.
      .pk_hook_mark_acquired(telemetry_conn, state)
      if (!is.null(telemetry_list)) {
        on.exit(
          {
            # KAYIT İADE ANINDA GÜNCELLENİR: doğrudan `.pk_hook_real_release_connection()` çağrısı kaydı GÜNCELLEMEZ (yalnızca `call_env$release_connection()` günceller); aynı `conn` nesnesi bir sonraki gözlemde CANLI sanılıyor ve iade edilmiş bir havuz bağlantısı üzerinde telemetri çalıştırılıyordu.
            .pk_hook_mark_released(telemetry_conn, state)
            try(.pk_hook_real_release_connection(telemetry_list), silent = TRUE)
          },
          add = TRUE
        )
      }
      .pk_hook_real_pk_analysis_observe(session, telemetry_conn, info)
    }

    core <- .pk_hook_deep_core
    environment(core) <- call_env
    core(
      user_prompt = user_prompt,
      chat_history = chat_history,
      session = session,
      detail_level = detail_level,
      stop_check = stop_check
    )
  }
}

# YETKİLİ ALT BİLGİ MODEL METNİNE GÖRE BASTIRILMAZ.
#
# Eski metin tabanlı idempotentlik denetimi (`grepl("**Analiz Kaynağı", ...)`)
# modelin KENDİ yazdığı ya da istem enjeksiyonuyla ürettiği bir başlığı
# "footer zaten var" sanıp R'ye ait YETKİLİ alt bilgiyi DÜŞÜRÜYORDU. Kayıt bu
# noktada ZATEN tüketilmiştir, yani daha sonra teslim edilme şansı da yoktur:
# kullanıcıya yalnızca MODEL DENETİMİNDEKİ kaynak bölümü kalırdı.
#
# İdempotentlik BANT DIŞI sağlanır: `provenance_store` girdisi `istek_id`
# anahtarıyla tutulur ve okunduğu anda SİLİNİR (bkz. `motor$tamamla`
# sarmalayıcısı) — `pk_provenance_decorate()` ile aynı sözleşme.
# ORTAK OTURUM YANITI DA SAYISAL KÖKENE KARŞI DOĞRULANIR.
#
# Alt bilgi eklemek YETKİ vermez: model uydurma bir sayı üretirse, yanıt
# yine "Analiz Kaynağı" alt bilgisiyle YAYINLANIYORDU. Tek kullanıcılı yol
# (`pk_provenance_decorate()`) doğrulamayı `pk_numeric_provenance_apply()`
# ile yapar; Ortak Oturum yolu da AYNI sözleşmeye bağlanır. Bu yüzden depoya
# yalnızca alt bilgi METNİ değil, KAYDIN TAMAMI (olgular + kip + deterministik
# yedek) yayınlanır ve doğrulama `motor$tamamla` sınırında çalışır.
.pk_hook_room_record <- function(value) {
  if (is.list(value)) {
    return(list(
      footer = .pk_hook_scalar_text(value$footer),
      facts = value$facts,
      fallback_text = value$fallback_text,
      query_id = value$query_id,
      mode = value$mode
    ))
  }
  list(footer = .pk_hook_scalar_text(value), facts = NULL,
       fallback_text = NULL, query_id = NULL, mode = NULL)
}

.pk_hook_room_footer_append <- function(text, footer) {
  kayit <- .pk_hook_room_record(footer)

  # KİP TEK BİR NORMALLEŞTİRME İLE OKUNUR: aşağıdaki hata yakalayıcısı
  # `as.character(...)[1]` kullanırken bu kapı ÇIPLAK `identical()` yapıyordu;
  # adlandırılmış/öznitelikli bir `mode` değeri kapıyı geçersiz kılıyor, olgu
  # kaydı da olmadığı için doğrulama ATLANIYOR ve ham model metni otoriter alt
  # bilgiyle YAYIMLANIYORDU. Normalleştirme ERKEN DÖNÜŞTEN ÖNCE yapılır çünkü
  # boş alt bilgi kapısı da bu değere bakar.
  kip <- as.character(kayit$mode %||% "")[1]
  if (length(kip) != 1L || is.na(kip)) kip <- ""

  # ALT BİLGİ BOŞ OLSA BİLE DOĞRULAMA ÇALIŞIR. `pk_build_provenance_footer()`
  # başarısız olduğunda "" döndürür, ancak telemetri üreticisi olguları ve kipi
  # yine de saklar; amaç tam olarak §5.11 doğrulamasının çalışmaya devam
  # etmesidir. Koşulsuz erken dönüş, `block` kipinde DOĞRULANMAMIŞ model
  # düzyazısını Ortak Oturum yolundan teslim ediyordu. Bu yüzden yalnızca
  # yapılacak iş kalmadığında (alt bilgi yok + olgu yok + kip `block` değil)
  # erken dönülür; aksi hâlde doğrulama koşar ve yalnızca alt bilgi birleştirme
  # adımı boş kalır.
  if (!nzchar(kayit$footer) && is.null(kayit$facts) && !identical(kip, "block")) {
    return(text)
  }

  govde <- .pk_hook_scalar_text(text)

  # DOĞRULAMA ALT BİLGİDEN ÖNCE. Olgu saklanmamışsa (v1 yolu) adım atlanır ve
  # davranış değişmez. Doğrulayıcı kendi içinde KAPALI başarısız olur:
  # `block` kipinde deterministik yedek metni döndürür, ham düzyazıyı DEĞİL.
  # BLOCK KİPİNDE OLGU YOKSA DOĞRULANMAMIŞ METİN YAYIMLANMAZ.
  #
  # Telemetri üreticisi kipi ve alt bilgiyi olgulardan BAĞIMSIZ saklar; olgu
  # kaydı yoksa (v2 üretimi başarısız, paket kurulamadı) aşağıdaki doğrulama
  # ATLANIYOR ve otoriter alt bilgi ham model metnine EKLENİYORDU. `block`
  # kipinin tüm amacı budur: deterministik yedek (yoksa sabit reddetme metni)
  # kullanılır.
  .blok_yedegi <- function() {
    y <- .pk_hook_scalar_text(kayit$fallback_text)
    if (!nzchar(y) && exists("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE)) {
      y <- .pk_hook_scalar_text(get("PK_PROVENANCE_BLOCK_REFUSAL_TR", inherits = TRUE))
    }
    y
  }

  if (is.null(kayit$facts) && identical(kip, "block")) {
    yedek <- .blok_yedegi()
    if (nzchar(yedek)) govde <- yedek
  }

  # DOĞRULAYICI YÜKLENMEMİŞSE `block` KİPİ KAPALI BAŞARISIZ OLUR: olgu VARKEN doğrulayıcı çözülemezse aşağıdaki dal atlanıyor ve otoriter alt bilgi DOĞRULANMAMIŞ düzyazıya ekleniyordu.
  if (!is.null(kayit$facts) && identical(kip, "block") &&
      !exists("pk_numeric_provenance_apply", mode = "function", inherits = TRUE)) {
    yedek <- .blok_yedegi()
    if (nzchar(yedek)) govde <- yedek
  }

  if (!is.null(kayit$facts) &&
      exists("pk_numeric_provenance_apply", mode = "function", inherits = TRUE)) {
    govde <- tryCatch({
      # DOĞRULAYICIYA NORMALLEŞTİRİLMİŞ KİP GEÇİLİR: yukarıdaki kapılar `kip`
      # üzerinden karar verirken buraya ham `kayit$mode` geçiliyordu; adlandırılmış
      # veya öznitelikli bir değer iki kararın AYRIŞMASINA ve doğrulayıcının
      # bloklamayan bir kip seçmesine yol açabiliyordu.
      sonuc <- pk_numeric_provenance_apply(
        govde, kayit$facts, mode = kip,
        fallback_text = kayit$fallback_text
      )
      if (exists("pk_numeric_provenance_report", mode = "function", inherits = TRUE)) {
        try(pk_numeric_provenance_report(sonuc, kayit$query_id), silent = TRUE)
      }
      .pk_hook_scalar_text(sonuc$text)
    }, error = function(e) {
      # `block` kipi AÇIK başarısız olamaz: doğrulanmamış düzyazı teslim
      # edilmektense deterministik reddetme metni gösterilir. TEK SÖZLEŞME:
      # `.blok_yedegi()` önce `kayit$fallback_text` değerini kullanır; bu dal
      # yalnızca `PK_PROVENANCE_BLOCK_REFUSAL_TR` sabitine bakınca, sabit
      # çözülemeyen worker/izole çalışma zamanlarında deterministik yedek
      # metin VARKEN bile ham düzyazı yayımlanıyordu.
      if (identical(kip, "block")) {
        yedek <- .blok_yedegi()
        if (nzchar(yedek)) return(yedek)
      }
      govde
    })
  }

  paste0(govde, kayit$footer)
}

.pk_hook_room_footer_publish <- function(footer) {
  kayit <- .pk_hook_room_record(footer)
  # BOŞ ALT BİLGİ "YAPILACAK İŞ YOK" DEMEK DEĞİLDİR (PR #705 inceleme, P2):
  # `.pk_hook_room_footer_append()` (bkz. yukarıdaki kapı) alt bilgi boş olsa da
  # olgu ya da `block` kipi varsa DOĞRULAMAYI çalıştırır. Bu erken dönüş, tam
  # olarak o kayıtları düşürüyordu: `pk_provenance_take()` kaydı zaten TÜKETMİŞ
  # olduğu için `motor$tamamla()` sınırına `footer = NULL` gidiyor, doğrulama
  # hiç koşmuyor ve `block` kipinde DOĞRULANMAMIŞ model düzyazısı teslim
  # ediliyordu. Yayın artık kayıt olgu ya da `block` taşıdığında da yapılır.
  kip <- as.character(kayit$mode %||% "")[1]
  if (length(kip) != 1L || is.na(kip)) kip <- ""
  if (!nzchar(kayit$footer) && is.null(kayit$facts) && !identical(kip, "block")) {
    return(invisible(FALSE))
  }

  for (frame in rev(sys.frames())) {
    has_store <- exists(".pk_room_provenance_store", envir = frame, inherits = FALSE)
    has_key <- exists(".pk_room_provenance_key", envir = frame, inherits = FALSE)
    if (!has_store || !has_key) next

    store <- get(".pk_room_provenance_store", envir = frame, inherits = FALSE)
    key <- .pk_hook_scalar_text(get(
      ".pk_room_provenance_key", envir = frame, inherits = FALSE
    ))
    if (is.environment(store) && nzchar(key)) {
      assign(key, kayit, envir = store)
      return(invisible(TRUE))
    }
  }

  invisible(FALSE)
}

# Sentetik oda session'ındaki köken alt bilgisi açıkça köprü dönüşüne eklenir
# ve aynı istek için Ortak Oturum üretim deposuna yayınlanır.
if (exists("oo_arac_sql_baglami_kur", mode = "function", inherits = TRUE) &&
    !exists(".pk_hook_room_sql_core", inherits = FALSE)) {

  .pk_hook_room_sql_core <- get(
    "oo_arac_sql_baglami_kur", mode = "function", inherits = TRUE
  )

  oo_arac_sql_baglami_kur <- function(soru, gecmis, oda_session, arac_meta) {
    result <- .pk_hook_room_sql_core(soru, gecmis, oda_session, arac_meta)
    # TAM KAYIT alınır: yalnız alt bilgi metni değil, sayısal köken olguları,
    # kip ve deterministik yedek de taşınır (bkz. `.pk_hook_room_footer_append`).
    kayit <- if (exists("pk_provenance_take", mode = "function", inherits = TRUE)) {
      tryCatch(pk_provenance_take(oda_session, full = TRUE), error = function(e) NULL)
    } else {
      NULL
    }

    kayit <- .pk_hook_room_record(kayit)
    footer <- kayit$footer
    # ÇAĞIRAN KAPISI DA GEVŞETİLİR (PR #705 inceleme, P2): olgu taşıyan ya da
    # `block` kipindeki bir kayıt alt bilgisiz de olsa YAYINLANMALIDIR; aksi
    # hâlde tüketilmiş kayıt burada sessizce ATILIR ve doğrulama hiç koşmaz.
    kip_kaydi <- as.character(kayit$mode %||% "")[1]
    if (length(kip_kaydi) != 1L || is.na(kip_kaydi)) kip_kaydi <- ""
    if (nzchar(footer) || !is.null(kayit$facts) || identical(kip_kaydi, "block")) {
      # KAYIT ZATEN TÜKETİLDİ: teslim edilemese bile YAYINLANIR.
      #
      # `pk_provenance_take()` yuvayı yukarıda boşaltır. Yayın yalnızca
      # `is.list(result)` dalında yapılıyordu; çekirdek bir hata/ret yolundan
      # düz METİN döndürdüğünde yetkili alt bilgi alınıp ATILIYOR ve (kayıt
      # tüketildiği için) bir daha teslim edilemiyordu. Depoya yayınlamak,
      # `motor$tamamla` sınırında eklenmesine izin verir.
      .pk_hook_room_footer_publish(kayit)
      if (is.list(result)) result$provenance_footer <- footer
    }
    result
  }
}

# Her Ortak Oturum isteği için küçük bir alt-bilgi deposu kurulur. Doğrudan
# yanıt ve asenkron model yanıtı aynı motor$tamamla sınırında tek kez süslenir.
if (exists("ortakOturumYzBind", mode = "function", inherits = TRUE) &&
    !exists(".pk_hook_room_bind_core", inherits = FALSE)) {

  .pk_hook_room_bind_core <- get(
    "ortakOturumYzBind", mode = "function", inherits = TRUE
  )

  ortakOturumYzBind <- function(input, output, session, ctx, motor) {
    result <- .pk_hook_room_bind_core(input, output, session, ctx, motor)

    provenance_store <- new.env(parent = emptyenv())
    original_llm <- motor$llm_uret
    original_finish <- motor$tamamla

    if (is.function(original_llm)) {
      motor$llm_uret <- function(oturum_id, soru_id, soran_id, istek_id,
                                 kuyruk_id = NULL, persona_kimligi = NULL) {
        .pk_room_provenance_store <- provenance_store
        .pk_room_provenance_key <- .pk_hook_scalar_text(istek_id)
        original_llm(
          oturum_id = oturum_id,
          soru_id = soru_id,
          soran_id = soran_id,
          istek_id = istek_id,
          kuyruk_id = kuyruk_id,
          persona_kimligi = persona_kimligi
        )
      }
    }

    if (is.function(original_finish)) {
      motor$tamamla <- function(oturum_id, soru_id, istek_id,
                                yanit_metni = NULL, hata_metni = NULL,
                                kuyruk_id = NULL, soran_id = NULL,
                                persona_id = NULL) {
        key <- .pk_hook_scalar_text(istek_id)
        # KAYIT YALNIZCA ALT BİLGİ İLİŞTİRİLDİKTEN SONRA SİLİNİR.
        #
        # Eskiden kayıt KOŞULSUZ siliniyordu; `original_finish()` her iki metin
        # de `NULL` iken çağrıldığında otoriter alt bilgi tüketilip ATILIYOR ve
        # sonraki hiçbir çağrı onu kurtaramıyordu.
        footer <- if (nzchar(key) &&
                      exists(key, envir = provenance_store, inherits = FALSE)) {
          get(key, envir = provenance_store, inherits = FALSE)
        } else {
          NULL
        }

        # Alt bilgi TEK terminal metne eklenir; yanıt varsa ona, yoksa hataya.
        eklendi <- FALSE
        if (!is.null(yanit_metni)) {
          yanit_metni <- .pk_hook_room_footer_append(yanit_metni, footer)
          eklendi <- TRUE
        } else if (!is.null(hata_metni)) {
          hata_metni <- .pk_hook_room_footer_append(hata_metni, footer)
          eklendi <- TRUE
        }
        if (isTRUE(eklendi) && nzchar(key) &&
            exists(key, envir = provenance_store, inherits = FALSE)) {
          rm(list = key, envir = provenance_store)
        }

        original_finish(
          oturum_id = oturum_id,
          soru_id = soru_id,
          istek_id = istek_id,
          yanit_metni = yanit_metni,
          hata_metni = hata_metni,
          kuyruk_id = kuyruk_id,
          soran_id = soran_id,
          persona_id = persona_id
        )
      }
    }

    result
  }
}
