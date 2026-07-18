# ==============================================================================
# Dosya Yolu: tests/testthat/test-speech-playback-policy-behavior.R
# Açıklama: Oynatma politikası davranışları: rehberlik politikası, öncelik
#           matrisi, oturum konuşma durumu (token sahipliği + bayat bitiş
#           koruması), karışık torba (tekrar önleme + peek) ve deterministik
#           kişisel karşılama öneki. Shiny gerekmez; sahte oturum kullanılır.
# ==============================================================================

testthat::test_that("rehberlik politikası rehberli/sessiz/bilinmeyen ayrımı yapar", {
  speech_tests_source_chain()

  for (page in names(mergen_speech_guided_pages())) {
    testthat::expect_identical(mergen_speech_guidance_policy(page), "guided",
                               info = page)
  }
  for (page in mergen_speech_silent_pages()) {
    testthat::expect_identical(mergen_speech_guidance_policy(page), "silent",
                               info = page)
  }
  testthat::expect_identical(mergen_speech_guidance_policy("olmayan_sayfa"), "unknown")
  testthat::expect_identical(mergen_speech_guidance_policy(NULL), "unknown")
  testthat::expect_identical(mergen_speech_guidance_policy(""), "unknown")
})

testthat::test_that("öncelik matrisi belgelenen sırayı uygular", {
  speech_tests_source_chain()

  # Boşken her tür başlayabilir
  for (kind in c("response_tts", "welcome", "page_guidance", "idle")) {
    testthat::expect_true(mergen_speech_priority_decision(NULL, kind)$allow)
  }

  # Kullanıcı istekli yanıt seslendirmesi her şeyi keser
  for (active in c("welcome", "page_guidance", "idle", "response_tts")) {
    d <- mergen_speech_priority_decision(active, "response_tts")
    testthat::expect_true(d$allow); testthat::expect_true(d$stop_active)
  }

  # Otomatik konuşmalar yanıt seslendirmesini KESEMEZ (kullanıcı niyeti korunur)
  for (new in c("welcome", "page_guidance", "idle")) {
    testthat::expect_false(mergen_speech_priority_decision("response_tts", new)$allow)
  }

  # Boşta konuşma hiçbir aktif konuşmayı kesemez
  for (active in c("welcome", "page_guidance", "idle")) {
    testthat::expect_false(mergen_speech_priority_decision(active, "idle")$allow)
  }

  # Gezinme (rehberlik) karşılamayı ve eski rehberliği keser
  testthat::expect_true(mergen_speech_priority_decision("welcome", "page_guidance")$allow)
  testthat::expect_true(mergen_speech_priority_decision("page_guidance", "page_guidance")$allow)
  testthat::expect_true(mergen_speech_priority_decision("idle", "page_guidance")$allow)

  # Karşılama rehberlik/boşta üzerine başlayabilir; ikinci karşılama başlayamaz
  testthat::expect_true(mergen_speech_priority_decision("idle", "welcome")$allow)
  testthat::expect_true(mergen_speech_priority_decision("page_guidance", "welcome")$allow)
  testthat::expect_false(mergen_speech_priority_decision("welcome", "welcome")$allow)
})

testthat::test_that("oturum konuşma durumu tekdüze artan token üretir ve bayat bitişi yok sayar", {
  speech_tests_source_chain()
  session <- speech_tests_fake_session()

  d1 <- mergen_speech_begin(session, "welcome")
  testthat::expect_true(d1$allow)
  testthat::expect_identical(d1$token, 1L)
  testthat::expect_identical(mergen_speech_active_kind(session), "welcome")

  # Boşta istek reddedilir; token artmaz
  d2 <- mergen_speech_begin(session, "idle")
  testthat::expect_false(d2$allow)

  # Rehberlik karşılamayı devralır; token artar
  d3 <- mergen_speech_begin(session, "page_guidance")
  testthat::expect_true(d3$allow)
  testthat::expect_identical(d3$token, 2L)

  # BAYAT bitiş (eski token) yeni konuşmanın durumunu TEMİZLEYEMEZ
  testthat::expect_false(mergen_speech_end(session, token = 1L))
  testthat::expect_identical(mergen_speech_active_kind(session), "page_guidance")

  # Güncel token temizler
  testthat::expect_true(mergen_speech_end(session, token = 2L))
  testthat::expect_null(mergen_speech_active_kind(session))

  # Token'sız bitiş koşulsuz temizler (stop yolu)
  mergen_speech_begin(session, "idle")
  mergen_speech_end(session)
  testthat::expect_null(mergen_speech_active_kind(session))
})

testthat::test_that("sonraki TTS parçaları başlangıç mesajından önce gönderilmez", {
  speech_tests_source_chain()
  session <- speech_tests_fake_session()
  sent <- list()
  session$sendCustomMessage <- function(type, payload) {
    sent[[length(sent) + 1L]] <<- list(type = type, payload = payload)
  }

  decision <- mergen_speech_begin(session, "idle")
  speaking <- TRUE
  dispatcher <- mergen_speech_chunk_dispatcher(
    session, decision$token, function() speaking
  )

  testthat::expect_true(dispatcher$claim_synthesis())
  testthat::expect_false(dispatcher$claim_synthesis())
  dispatcher$queue(list(index = 2L, speechToken = decision$token))
  dispatcher$queue(list(index = 1L, speechToken = decision$token))
  testthat::expect_length(sent, 0L)

  testthat::expect_true(dispatcher$start())
  testthat::expect_identical(vapply(sent, function(x) x$payload$index, integer(1)), 1:2)

  dispatcher$queue(list(index = 3L, speechToken = decision$token))
  testthat::expect_identical(sent[[3]]$payload$index, 3L)
  speaking <- FALSE
  testthat::expect_false(dispatcher$queue(list(index = 4L)))
  testthat::expect_length(sent, 3L)
})

testthat::test_that("karışık torba 10 çeşidi tüketmeden tekrar etmez", {
  speech_tests_source_chain()

  bags <- mergen_speech_shuffle_bag_env()
  for (trial in 1:5) {
    draws <- vapply(1:10, function(i) mergen_speech_shuffle_bag_draw(bags, "welcome"),
                    integer(1))
    testthat::expect_setequal(draws, 1:10)
  }
})

testthat::test_that("karışık torba yeniden dolumda hemen tekrarı engeller", {
  speech_tests_source_chain()

  # Çok sayıda tam turda sınır geçişinde ardışık tekrar hiç olmamalı
  for (trial in 1:50) {
    bags <- mergen_speech_shuffle_bag_env()
    draws <- vapply(1:20, function(i) mergen_speech_shuffle_bag_draw(bags, "p"),
                    integer(1))
    testthat::expect_false(any(diff(draws) == 0L),
                           info = paste(draws, collapse = ","))
    testthat::expect_false(draws[11] == draws[10])
  }
})

testthat::test_that("sayfa başına ve karşılama için torbalar bağımsızdır", {
  speech_tests_source_chain()

  bags <- mergen_speech_shuffle_bag_env()
  w1 <- mergen_speech_shuffle_bag_draw(bags, "welcome")
  f1 <- mergen_speech_shuffle_bag_draw(bags, "page:files")
  h1 <- mergen_speech_shuffle_bag_draw(bags, "page:history")

  # files torbasını tüketmek welcome/history torbasını etkilemez
  remaining_f <- vapply(2:10, function(i) mergen_speech_shuffle_bag_draw(bags, "page:files"),
                        integer(1))
  testthat::expect_setequal(c(f1, remaining_f), 1:10)

  w_slot <- get("welcome", envir = bags)
  testthat::expect_identical(length(w_slot$remaining), 9L)
  h_slot <- get("page:history", envir = bags)
  testthat::expect_identical(length(h_slot$remaining), 9L)
})

testthat::test_that("peek tüketmez ve sonraki draw peek ile aynıdır", {
  speech_tests_source_chain()

  bags <- mergen_speech_shuffle_bag_env()
  peeked <- mergen_speech_shuffle_bag_peek(bags, "page:files")
  peeked2 <- mergen_speech_shuffle_bag_peek(bags, "page:files")
  testthat::expect_identical(peeked, peeked2)

  drawn <- mergen_speech_shuffle_bag_draw(bags, "page:files")
  testthat::expect_identical(drawn, peeked)
})

testthat::test_that("kişisel önek deterministiktir, kısadır ve LLM içermez", {
  speech_tests_source_chain()

  p1 <- mergen_speech_build_welcome_prefix("Deniz", list("Excel raporu hazırlama"))
  p2 <- mergen_speech_build_welcome_prefix("Deniz", list("Excel raporu hazırlama"))
  testthat::expect_identical(p1, p2)
  testthat::expect_match(p1, "^Merhaba Deniz")
  testthat::expect_match(p1, "Excel raporu")

  # Ad var, konu yok
  p3 <- mergen_speech_build_welcome_prefix("Ayşe", NULL)
  testthat::expect_match(p3, "^Merhaba Ayşe")

  # Ad yoksa önek boş: statik karşılama tek başına yeterlidir
  testthat::expect_identical(mergen_speech_build_welcome_prefix("", list("konu")), "")
  testthat::expect_identical(mergen_speech_build_welcome_prefix(NULL, NULL), "")
})

testthat::test_that("önek konusu satır sonlarından arındırılır ve kelime sınırında kısalır", {
  speech_tests_source_chain()

  long_topic <- paste(rep("uzunkelime", 20), collapse = " ")
  cleaned <- mergen_speech_prefix_topic_clean(sprintf("ilk\nsatır\t%s", long_topic))
  testthat::expect_false(grepl("[\n\t]", cleaned))
  testthat::expect_lte(nchar(cleaned), 48L)
  # Kelime ortasından kesilmez
  testthat::expect_false(grepl("uzunkelim$", cleaned))

  testthat::expect_identical(mergen_speech_prefix_topic_clean(""), "")
  testthat::expect_identical(mergen_speech_prefix_topic_clean(NULL), "")
})
