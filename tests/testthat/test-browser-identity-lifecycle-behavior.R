# ==============================================================================
# Dosya Yolu: tests/testthat/test-browser-identity-lifecycle-behavior.R
# Açıklama: Tarayıcı kimlik yaşam döngüsü güvenlik sözleşmesi.
#           - SSO giriş durumu (state): istenmemiş/eşleşmeyen/tekrar oynatılan
#             dönüş reddedilir, eşleşen dönüş ve geri dönen kullanıcı çalışır.
#           - Tüm çıkış yolları tarayıcıdaki token'ı ve hesaba bağlı sohbeti siler.
#           - localStorage sohbeti doğrulanmış sahibe bağlıdır; başka hesabın
#             kaydı geri yüklenmez, geri yüklenen içerik sunucuda güvenle
#             yeniden üretilir (tarayıcı HTML'ine/kimliklerine güvenilmez).
#           Node yoksa yalnızca Node katmanı atlanır; sunucu sözleşmesi koşar.
# ==============================================================================

.kimlik_root <- function() resolve_repo_root_for_tests()

.kimlik_sso_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$SSO_ENABLED <- TRUE
  env$SSO_CONFIG <- list(
    auth_endpoint = "https://kc.test/auth", client_id = "mergen-bilge",
    response_type = "token", scope = "openid", logout_endpoint = ""
  )
  sys.source(file.path(.kimlik_root(), "R", "module_sso.R"), envir = env, keep.source = FALSE)
  env
}

test_that("SSO state, çıkış temizliği ve hesaba bağlı sohbet kaydı tarayıcıda doğrulanır", {
  node <- Sys.which("node")
  skip_if(!nzchar(node), "Node kullanılamıyor")
  suppressMessages(library(shiny))

  sso_env <- .kimlik_sso_env()
  betik <- as.character(sso_env$ssoPreflightScriptUI())
  betik <- sub("^<script>", "", sub("</script>$", "", betik))
  expect_match(betik, "__mergenSsoPreflight", fixed = TRUE)

  ui_env <- new.env(parent = globalenv())
  sys.source(file.path(.kimlik_root(), "R", "helpers_sidebar_user_display.R"),
             envir = ui_env, keep.source = FALSE)
  satir <- ui_env$mb_sidebar_controls_row(show_logout = TRUE, logout_url = "https://portal.test/cikis")
  dugme <- htmltools::tagQuery(satir)$find("button.mb-sidebar-logout-btn")$selectedTags()
  expect_length(dugme, 1L)
  onclick <- dugme[[1]]$attribs$onclick

  dizin <- withr::local_tempdir()
  on_kapi <- file.path(dizin, "preflight.js")
  cikis <- file.path(dizin, "logout_onclick.js")
  writeLines(enc2utf8(betik), on_kapi, useBytes = TRUE)
  writeLines(enc2utf8(onclick), cikis, useBytes = TRUE)

  script <- file.path(.kimlik_root(), "tests", "scripts", "browser_identity_regressions.js")
  sonuc <- system2(node, c(shQuote(script), shQuote(on_kapi), shQuote(cikis)), stdout = TRUE, stderr = TRUE)
  expect_null(attr(sonuc, "status"), info = paste(sonuc, collapse = "\n"))
  expect_match(paste(sonuc, collapse = "\n"), "browser identity regressions passed")
})

# ------------------------------------------------------------------------------
# Sunucu: sahip etiketi, geri yükleme kararı ve güvenli yeniden render
# ------------------------------------------------------------------------------
.kimlik_storage_env <- local({
  env <- NULL
  function() {
    if (!is.null(env)) return(env)
    env <<- new.env(parent = globalenv())
    for (dosya in c("helpers_markdown_safety.R", "helpers_messaging.R",
                    "helpers_chat_message_formatting.R", "helpers_user_session_identity.R",
                    "server_observers_storage.R")) {
      sys.source(file.path(.kimlik_root(), "R", dosya), envir = env, keep.source = FALSE)
    }
    env$showToast <- function(...) invisible(TRUE)
    env$get_characters_data <- function() NULL
    env$normalize_character_id <- function(x) as.character(x %||% "")
    env$insertUI <- function(selector, where, ui, ...) {
      env$eklenen <- c(env$eklenen, as.character(ui))
      invisible(NULL)
    }
    env$removeUI <- function(...) invisible(NULL)
    env
  }
})

.kimlik_oturum_kur <- function(session, uid) {
  session$userData$auth_initialized <- uid > 0L
  session$userData$user_id <- as.integer(uid)
}

.kimlik_sunucu <- function(env, mesajlar_gonderilen) {
  function(input, output, session) {
    values <- shiny::reactiveValues(messages = list(), liked_messages = character(0),
                                    disliked_messages = character(0), show_welcome = TRUE)
    settings_data <- shiny::reactiveValues(selected_character = "emre", enable_timestamps = TRUE,
                                           user_config = list(name = "Test", userId = 1L))
    session$sendCustomMessage <- function(type, message) {
      mesajlar_gonderilen$liste[[length(mesajlar_gonderilen$liste) + 1L]] <- list(type = type, message = message)
    }
    env$storageObserversInit(input, session, output, values, settings_data,
                             chat_rebind_all_charts = function(...) invisible(TRUE))
    session$userData$.values <- values
  }
}

test_that("sahip etiketi doğrulanmış kimliğe bağlıdır ve sunucu sırrı olmadan üretilmez", {
  env <- .kimlik_storage_env()
  oturum <- list(userData = new.env())
  expect_null(env$mergen_chat_storage_owner(oturum, master = "sir"))
  .kimlik_oturum_kur(oturum, 7L)
  a <- env$mergen_chat_storage_owner(oturum, master = "sir")
  expect_match(a, "^[0-9a-f]{64}$")
  expect_false(grepl("7", a, fixed = TRUE) && identical(a, "7"))
  expect_null(env$mergen_chat_storage_owner(oturum, master = ""))
  .kimlik_oturum_kur(oturum, 8L)
  expect_false(identical(env$mergen_chat_storage_owner(oturum, master = "sir"), a))
  expect_false(identical(env$mergen_chat_storage_owner(oturum, master = "baska"), a))
  oturum$userData$auth_initialized <- FALSE
  expect_null(env$mergen_chat_storage_owner(oturum, master = "sir"))
})

test_that("tarayıcıya yalnızca düz alanlar yazılır ve yalnız doğrulanmış sahibe", {
  env <- .kimlik_storage_env()
  withr::local_envvar(AI_KEYS_MASTER = "test-sir-kimlik")
  gonderilen <- new.env()
  gonderilen$liste <- list()

  shiny::testServer(.kimlik_sunucu(env, gonderilen), {
    session$flushReact()
    v <- session$userData$.values
    v$messages <- list(list(id = "m1", db_id = 99L, type = "ai", content = "yanıt",
                            html_content = "<b>x</b>", reasoning_content = "gizli düşünce",
                            timestamp = "10:00"))
    session$flushReact()
    expect_false(any(vapply(gonderilen$liste, function(x) identical(x$type, "saveCurrentChat"), logical(1))),
                 info = "kimliksiz oturum tarayıcıya sohbet yazmamalı")

    .kimlik_oturum_kur(session, 7L)
    v$messages <- c(v$messages, list(list(id = "m2", type = "user", content = "soru", timestamp = "10:01")))
    session$flushReact()
    kayit <- Filter(function(x) identical(x$type, "saveCurrentChat"), gonderilen$liste)
    expect_length(kayit, 1L)
    yuk <- kayit[[1]]$message
    expect_identical(yuk$owner, env$mergen_chat_storage_owner(session))
    expect_identical(names(yuk$messages[[1]]), c("type", "content", "timestamp", "include_in_context"))
    expect_false(grepl("gizli düşünce|<b>x</b>|99", jsonlite::toJSON(yuk$messages, auto_unbox = TRUE)))
  })
})

test_that("A'nın kaydı B'nin oturumuna geri yüklenmez ve tarayıcıdan silinir", {
  env <- .kimlik_storage_env()
  withr::local_envvar(AI_KEYS_MASTER = "test-sir-kimlik")
  a_oturum <- list(userData = new.env())
  .kimlik_oturum_kur(a_oturum, 7L)
  a_etiketi <- env$mergen_chat_storage_owner(a_oturum)

  gonderilen <- new.env()
  gonderilen$liste <- list()
  shiny::testServer(.kimlik_sunucu(env, gonderilen), {
    .kimlik_oturum_kur(session, 8L)
    session$flushReact()
    session$setInputs(load_chat_from_storage = list(
      owner = a_etiketi,
      messages = list(list(type = "user", content = "A'nın gizli sorusu"))
    ))
    session$flushReact()
    expect_length(session$userData$.values$messages, 0L)
    turler <- vapply(gonderilen$liste, `[[`, character(1), "type")
    expect_true("clearCurrentChat" %in% turler)
  })
})

test_that("eski biçim ve kimlik hazır değilken gelen kayıt güvenli işlenir", {
  env <- .kimlik_storage_env()
  withr::local_envvar(AI_KEYS_MASTER = "test-sir-kimlik")
  gonderilen <- new.env()
  gonderilen$liste <- list()
  shiny::testServer(.kimlik_sunucu(env, gonderilen), {
    session$flushReact()
    oturum_a <- list(userData = new.env())
    .kimlik_oturum_kur(oturum_a, 7L)
    etiket <- env$mergen_chat_storage_owner(oturum_a)

    # Kimlik henüz yok: kayıt bekletilir, ne yüklenir ne silinir.
    session$setInputs(load_chat_from_storage = list(owner = etiket,
      messages = list(list(type = "ai", content = "**önceki** yanıt"))))
    session$flushReact()
    expect_length(session$userData$.values$messages, 0L)
    expect_false("clearCurrentChat" %in% vapply(gonderilen$liste, `[[`, character(1), "type"))

    # Kimlik aynı hesap olarak hazırlanınca bekleyen kayıt geri yüklenir.
    .kimlik_oturum_kur(session, 7L)
    env$mergen_session_owner_transition(session$userData, 0L, 7L)
    session$flushReact()
    msgs <- session$userData$.values$messages
    expect_length(msgs, 1L)
    expect_match(msgs[[1]]$html_content, "<strong>önceki</strong>", fixed = TRUE)
  })

  # Sahipsiz eski dizi biçimi: kimlik hazır olsa da reddedilir.
  gonderilen$liste <- list()
  shiny::testServer(.kimlik_sunucu(env, gonderilen), {
    .kimlik_oturum_kur(session, 7L)
    session$flushReact()
    session$setInputs(load_chat_from_storage = list(
      list(id = "x\"');alert(1);//", type = "ai", content = "eski", html_content = "<img src=x onerror=alert(1)>")
    ))
    session$flushReact()
    expect_length(session$userData$.values$messages, 0L)
    expect_true("clearCurrentChat" %in% vapply(gonderilen$liste, `[[`, character(1), "type"))
  })
})

test_that("geri yüklenen içerik sunucuda yeniden üretilir; istemci HTML'i ve kimlikleri yok sayılır", {
  env <- .kimlik_storage_env()
  withr::local_envvar(AI_KEYS_MASTER = "test-sir-kimlik")
  env$eklenen <- character(0)
  gonderilen <- new.env()
  gonderilen$liste <- list()
  shiny::testServer(.kimlik_sunucu(env, gonderilen), {
    .kimlik_oturum_kur(session, 7L)
    session$flushReact()
    session$setInputs(load_chat_from_storage = list(
      owner = env$mergen_chat_storage_owner(session),
      messages = list(
        list(id = "x');alert(1);//", type = "ai", content = "Yanıt <img src=x onerror=alert(1)> **kalın**",
             html_content = "<img src=x onerror=alert(1)>", reasoning_content = "<script>alert(1)</script>",
             db_id = 5L, timestamp = "<b>t</b>"),
        list(type = "user", content = "Soru <script>alert(1)</script>"),
        list(type = "arac", content = "yetkisiz tür"),
        list(type = "user", content = list("dizi")),
        list(type = "ai", content = c("iki", "öğe"))
      )
    ))
    session$flushReact()
    msgs <- session$userData$.values$messages
    expect_length(msgs, 2L)
    expect_true(all(grepl("^msg_restore_[0-9]+_[0-9]+$", vapply(msgs, `[[`, character(1), "id"))))
    expect_null(msgs[[1]]$db_id)
    expect_null(msgs[[1]]$reasoning_content)
    expect_identical(msgs[[1]]$timestamp, "<b>t</b>")

    # Mesaj içeriği HTML'i sunucuda üretilmiştir; yalnızca güvenli markdown alt kümesi.
    icerik_html <- paste(vapply(msgs, `[[`, character(1), "html_content"), collapse = "\n")
    etiketler <- regmatches(icerik_html, gregexpr("<[A-Za-z][^>]*>", icerik_html, perl = TRUE))[[1]]
    adlar <- unique(tolower(sub("^<([A-Za-z0-9]+).*$", "\\1", etiketler)))
    expect_true(all(adlar %in% c("p", "strong", "em", "br")), info = icerik_html)
    expect_false(any(grepl("\\son[a-z]+\\s*=", etiketler, perl = TRUE)), info = icerik_html)

    # Sayfaya eklenen balonda istemcinin HTML'i, kimliği veya zaman damgası
    # işaretleme olarak yer almaz (uygulamanın sabit avatar şablonu hariç).
    html <- paste(env$eklenen, collapse = "\n")
    expect_false(grepl("<img src=x", html, fixed = TRUE), info = html)
    expect_false(grepl("<script>alert", html, fixed = TRUE), info = html)
    expect_false(grepl("alert(1);//", html, fixed = TRUE), info = html)
    expect_false(grepl("<b>t</b>", html, fixed = TRUE), info = html)
    expect_match(html, "<strong>kalın</strong>", fixed = TRUE)
    expect_match(html, "&lt;img", fixed = TRUE)
  })
})

test_that("geri yükleme toplam boyut bütçesi render'dan önce uygulanır", {
  env <- .kimlik_storage_env()
  cagri <- 0L
  gercek <- env$db_message_process_text_content
  env$db_message_process_text_content <- function(...) {
    cagri <<- cagri + 1L
    list(html = "<p>x</p>", has_code = FALSE)
  }
  withr::defer(env$db_message_process_text_content <- gercek)
  # Tek tek geçerli (200 x 199.999) ama toplamda bütçeyi aşan doğrudan girdi.
  parca <- strrep("a", 199999L)
  buyuk <- rep(list(list(type = "user", content = parca)), 200L)
  expect_length(env$mergen_chat_storage_restore_messages(buyuk), 0L)
  expect_identical(cagri, 0L)
  # Bütçe içindeki kayıt normal geri yüklenir.
  expect_length(env$mergen_chat_storage_restore_messages(buyuk[1:5]), 5L)
  expect_identical(cagri, 5L)
})

test_that("geri yüklenen görsel mesajı kayıtlı-sohbet yolundan sahip köküyle karta çevrilir", {
  env <- .kimlik_storage_env()
  kok <- withr::local_tempdir()
  withr::local_dir(kok)
  dir.create(file.path("user_images", "7", "c1"), recursive = TRUE)
  dir.create(file.path("user_images", "8", "c1"), recursive = TRUE)
  png <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
  writeBin(png, file.path("user_images", "7", "c1", "kendi.png"))
  writeBin(png, file.path("user_images", "8", "c1", "baskasi.png"))

  kayit <- list(
    list(type = "ai", content = "[GÖRSEL:user_images/7/c1/kendi.png] Çiçekli bahçe"),
    list(type = "ai", content = "[GÖRSEL:user_images/8/c1/baskasi.png] Başkasının görseli")
  )
  sonuc <- env$mergen_chat_storage_restore_messages(kayit, user_id = 7L)
  expect_length(sonuc, 2L)

  # Kendi görseli kart olarak çizilir; işaretçi düz metin olarak görünmez.
  expect_match(sonuc[[1]]$html_content, "generated-image-container", fixed = TRUE)
  expect_match(sonuc[[1]]$html_content, "Çiçekli bahçe", fixed = TRUE)
  expect_no_match(sonuc[[1]]$html_content, "Görsel dosyası bulunamadı", fixed = TRUE)
  expect_no_match(sonuc[[1]]$html_content, "[GÖRSEL", fixed = TRUE)
  expect_identical(sonuc[[1]]$content, kayit[[1]]$content)

  # Başka kullanıcının yolu sahip kökü dışında kalır: dosya sunulmaz.
  expect_match(sonuc[[2]]$html_content, "Görsel dosyası bulunamadı", fixed = TRUE)
  expect_no_match(sonuc[[2]]$html_content, "data:image", fixed = TRUE)

  # Kimlik verilmezse hiçbir görsel dosyası çözülmez (fail-closed).
  kimliksiz <- env$mergen_chat_storage_restore_messages(kayit[1])
  expect_match(kimliksiz[[1]]$html_content, "Görsel dosyası bulunamadı", fixed = TRUE)
})

test_that("kayıt geri yüklemenin kabul ettiği bütçeye sığan en yeni mesajlarla sınırlanır", {
  env <- .kimlik_storage_env()
  mesajlar <- lapply(seq_len(205), function(i) list(type = if (i %% 2) "user" else "ai",
                                                     content = paste("mesaj", i), timestamp = ""))
  yuk <- env$mergen_chat_storage_payload(mesajlar)
  expect_length(yuk, 200L)
  expect_identical(yuk[[200]]$content, "mesaj 205")
  expect_identical(yuk[[1]]$content, "mesaj 6")
  expect_length(env$mergen_chat_storage_restore_messages(yuk), 200L)

  # Bayt bütçesi: en yeni mesajlar tutulur, toplam sınırı aşan eskiler düşer.
  buyuk <- lapply(1:3, function(i) list(type = "user", content = strrep(letters[i], 900), timestamp = ""))
  kirpilmis <- env$mergen_chat_storage_payload(buyuk, max_total_chars = 2000L)
  expect_identical(vapply(kirpilmis, function(m) substr(m$content, 1, 1), character(1)), c("b", "c"))
})

test_that("sistem bildirimi ve bağlam dışı mesaj bayrağı kayıttan geri yüklemeye korunur", {
  env <- .kimlik_storage_env()
  yuk <- env$mergen_chat_storage_payload(list(
    list(type = "system", content = "rapor.xlsx yüklendi.", html_content = "<b>x</b>", timestamp = "10:00"),
    list(type = "ai", content = "Hızlı eylem tanıtımı", include_in_context = FALSE, timestamp = "10:01"),
    list(type = "user", content = "soru", timestamp = "10:02")
  ))
  expect_identical(vapply(yuk, `[[`, character(1), "type"), c("system", "ai", "user"))
  expect_identical(vapply(yuk, `[[`, logical(1), "include_in_context"), c(TRUE, FALSE, TRUE))

  geri <- env$mergen_chat_storage_restore_messages(yuk)
  expect_identical(vapply(geri, `[[`, character(1), "type"), c("system", "ai", "user"))
  expect_identical(vapply(geri, `[[`, logical(1), "include_in_context"), c(TRUE, FALSE, TRUE))
  expect_false(grepl("<b>x</b>", geri[[1]]$html_content, fixed = TRUE))

  # İstemci bayrağı yalnız mantıksal tekil FALSE ise bağlam dışı sayılır.
  for (bayrak in list("FALSE", 0L, c(FALSE, FALSE), NA, NULL)) {
    tek <- env$mergen_chat_storage_restore_messages(list(list(type = "user", content = "x",
                                                              include_in_context = bayrak)))
    expect_true(tek[[1]]$include_in_context)
  }
})

test_that("doğrulanmış kullanıcı sohbeti boşaltınca tarayıcı kaydı silinir; kimlik kaybında korunur", {
  env <- .kimlik_storage_env()
  withr::local_envvar(AI_KEYS_MASTER = "test-sir-kimlik")
  gonderilen <- new.env()
  gonderilen$liste <- list()
  turler <- function() vapply(gonderilen$liste, `[[`, character(1), "type")
  shiny::testServer(.kimlik_sunucu(env, gonderilen), {
    .kimlik_oturum_kur(session, 7L)
    session$flushReact()
    v <- session$userData$.values
    v$messages <- list(list(id = "m1", type = "user", content = "soru", timestamp = ""))
    session$flushReact()
    expect_identical(turler(), "saveCurrentChat")

    # Yeni sohbet: kayıt silinir, eski sohbet sonraki açılışta geri gelmez.
    v$messages <- list()
    session$flushReact()
    expect_identical(turler(), c("saveCurrentChat", "clearCurrentChat"))

    # Token süresi doldu: sohbet bellekten boşalsa da aynı kullanıcının kaydı silinmez.
    v$messages <- list(list(id = "m2", type = "user", content = "ikinci", timestamp = ""))
    session$flushReact()
    gonderilen$liste <- list()
    session$userData$auth_initialized <- FALSE
    v$messages <- list()
    session$flushReact()
    expect_false("clearCurrentChat" %in% turler())
  })
})
