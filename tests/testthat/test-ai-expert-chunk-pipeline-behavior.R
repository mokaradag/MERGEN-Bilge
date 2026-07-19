# ==============================================================================
# Dosya Yolu: tests/testthat/test-ai-expert-chunk-pipeline-behavior.R
# Açıklama: AI Uzman TTS parça hattının davranış testleri: sınırlı
#           eşzamanlılık, sıralı (kablo indeksli) teslim, başarısız parçanın
#           atlanıp dizinin kısalması, başlangıç tamponu kapısı ve iptal
#           koruması. Tamamen çevrimdışı ve deterministiktir; gerçek TTS,
#           Shiny oturumu veya ağ gerekmez.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  if (!exists("ai_expert_chunk_pipeline_baslat", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_ai_expert_chunk_pipeline.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

# later kuyruğunu sınırlı biçimde boşaltır (promise callback'leri için).
.aiexp_drain <- function(n = 50L) {
  for (i in seq_len(n)) later::run_now(timeoutSecs = 0)
  invisible(NULL)
}

# Elle çözülen sentez sahtesi: her çağrı bir "resolver" kaydeder.
.aiexp_fake_synth <- function() {
  kayit <- new.env(parent = emptyenv())
  kayit$resolvers <- list()
  kayit$istekler <- character(0)

  synth_fn <- function(text) {
    kayit$istekler <- c(kayit$istekler, text)
    promises::promise(function(resolve, reject) {
      kayit$resolvers[[length(kayit$resolvers) + 1L]] <-
        list(resolve = resolve, reject = reject, text = text)
    })
  }

  list(
    synth_fn = synth_fn,
    kayit = kayit,
    coz = function(i, basari = TRUE, src = paste0("wav-", i)) {
      r <- kayit$resolvers[[i]]
      if (isTRUE(basari)) {
        r$resolve(list(success = TRUE, audio_src = src, duration = 1.5))
      } else {
        r$resolve(list(success = FALSE, audio_src = ""))
      }
      .aiexp_drain()
    }
  )
}

test_that("parça hattı eşzamanlılığı sınırlar ve parçaları sırayla teslim eder", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  sahte <- .aiexp_fake_synth()
  teslimler <- list()
  bosaldi <- NULL

  ai_expert_chunk_pipeline_baslat(
    parcalar = list("p1", "p2", "p3", "p4", "p5"),
    baslangic = 2L,
    synth_fn = sahte$synth_fn,
    is_current_fn = function() TRUE,
    queue_fn = function(index0, text, audio_src, duration) {
      teslimler[[length(teslimler) + 1L]] <<- list(index0 = index0, text = text)
    },
    on_drained = function(teslim) bosaldi <<- teslim,
    policy = list(eszamanli_sinir = 2L, baslangic_tampon_suresi_sn = 0)
  )

  # Sınır 2: yalnızca p2 ve p3 sentezde; p4 henüz başlamadı.
  expect_identical(sahte$kayit$istekler, c("p2", "p3"))

  # p3 ÖNCE tamamlanır: sıralı teslim korunur, p3 bekletilir; p4 sentezi başlar.
  sahte$coz(2, basari = TRUE, src = "wav-p3")
  expect_length(teslimler, 0L)
  expect_identical(sahte$kayit$istekler, c("p2", "p3", "p4"))

  # p2 tamamlanınca p2 ve bekleyen p3 SIRAYLA teslim edilir.
  sahte$coz(1, basari = TRUE, src = "wav-p2")
  expect_identical(vapply(teslimler, function(x) x$text, character(1)), c("p2", "p3"))
  expect_identical(vapply(teslimler, function(x) x$index0, numeric(1)), c(1, 2))

  # Kalanlar tamamlanır; hat boşaldığında teslim sayısı bildirilir.
  sahte$coz(3)
  sahte$coz(4)
  expect_identical(vapply(teslimler, function(x) x$text, character(1)),
                   c("p2", "p3", "p4", "p5"))
  expect_identical(bosaldi, 5L)
})

test_that("başarısız parça atlanır, kablo indeksleri boşluksuz kalır ve gerçek teslim bildirilir", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  sahte <- .aiexp_fake_synth()
  teslimler <- list()
  bosaldi <- NULL

  ai_expert_chunk_pipeline_baslat(
    parcalar = list("p1", "p2", "p3", "p4"),
    baslangic = 2L,
    synth_fn = sahte$synth_fn,
    is_current_fn = function() TRUE,
    queue_fn = function(index0, text, audio_src, duration) {
      teslimler[[length(teslimler) + 1L]] <<- list(index0 = index0, text = text)
    },
    on_drained = function(teslim) bosaldi <<- teslim,
    policy = list(eszamanli_sinir = 2L, baslangic_tampon_suresi_sn = 0)
  )

  sahte$coz(1, basari = FALSE)   # p2 başarısız -> atlanır
  sahte$coz(2, basari = TRUE)    # p3 başarılı -> kablo indeksi 1 (p2'nin yeri)
  sahte$coz(3, basari = TRUE)    # p4 -> kablo indeksi 2

  expect_identical(vapply(teslimler, function(x) x$text, character(1)), c("p3", "p4"))
  expect_identical(vapply(teslimler, function(x) x$index0, numeric(1)), c(1, 2))
  # 4 parçalık dizide 1 parça düştü: gerçek teslim 3 (ilk parça dahil).
  expect_identical(bosaldi, 3L)
})

test_that("başlangıç tamponu kapısı ilk parçayı tampon sonuçlanana kadar bekletir", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  baslatilan <- NULL
  kapi <- ai_expert_baslangic_kapisi(
    dispatch_fn = function(text, chunks, audio_src, duration) {
      baslatilan <<- list(text = text, src = audio_src)
    },
    deadline_secs = 0  # süre sınırı devre dışı: yalnızca tampon sinyali açar
  )

  kapi$ilk_hazir(list(text = "ilk", chunks = list("ilk", "ikinci"),
                      audio_src = "wav-ilk", duration = 1))
  expect_null(baslatilan)
  expect_false(kapi$acik_mi())

  kapi$tampon_hazir()
  expect_false(is.null(baslatilan))
  expect_identical(baslatilan$text, "ilk")
  expect_true(kapi$acik_mi())

  # Yinelenen sinyaller ikinci kez başlatmaz (idempotent).
  baslatilan <- NULL
  kapi$tampon_hazir()
  kapi$ilk_hazir(list(text = "baska", chunks = list(), audio_src = "x", duration = 1))
  expect_null(baslatilan)
})

test_that("başlangıç kapısı süre sınırı dolunca tamponsuz da açılır", {
  skip_if_not_installed("later")

  baslatilan <- NULL
  kapi <- ai_expert_baslangic_kapisi(
    dispatch_fn = function(text, chunks, audio_src, duration) {
      baslatilan <<- text
    },
    deadline_secs = 0.01
  )
  kapi$ilk_hazir(list(text = "ilk", chunks = list("a", "b"),
                      audio_src = "wav", duration = 1))
  expect_null(baslatilan)

  # Süre sınırı geri çağrısı later kuyruğundan gelir.
  deadline <- Sys.time() + 2
  while (is.null(baslatilan) && Sys.time() < deadline) {
    later::run_now(timeoutSecs = 0.05)
  }
  expect_identical(baslatilan, "ilk")
})

test_that("iptal edilen konuşmada kuyruktaki sentez işi başlatılmaz ve teslim yapılmaz", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  sahte <- .aiexp_fake_synth()
  aktif <- TRUE
  teslimler <- 0L

  ai_expert_chunk_pipeline_baslat(
    parcalar = list("p1", "p2", "p3", "p4", "p5"),
    baslangic = 2L,
    synth_fn = sahte$synth_fn,
    is_current_fn = function() aktif,
    queue_fn = function(index0, text, audio_src, duration) {
      teslimler <<- teslimler + 1L
    },
    policy = list(eszamanli_sinir = 1L, baslangic_tampon_suresi_sn = 0)
  )

  expect_identical(sahte$kayit$istekler, "p2")

  # Konuşma iptal edildi: p2 tamamlansa bile teslim edilmez, p3+ hiç başlamaz.
  aktif <- FALSE
  sahte$coz(1, basari = TRUE)
  expect_identical(teslimler, 0L)
  expect_identical(sahte$kayit$istekler, "p2")
})

test_that("tek parçalı yanıt tamponu beklemez ve politika ortamdan ayarlanabilir", {
  tampon <- FALSE
  ai_expert_chunk_pipeline_baslat(
    parcalar = list("tek"),
    baslangic = 2L,
    synth_fn = function(text) stop("çağrılmamalı"),
    is_current_fn = function() TRUE,
    queue_fn = function(...) stop("teslim olmamalı"),
    on_buffer_settled = function() tampon <<- TRUE,
    policy = list(eszamanli_sinir = 2L, baslangic_tampon_suresi_sn = 0)
  )
  expect_true(tampon)

  withr::with_envvar(c(MERGEN_AI_EXPERT_TTS_CONCURRENCY = "3",
                       MERGEN_AI_EXPERT_TTS_START_BUFFER_SECS = "9"), {
    politika <- ai_expert_chunk_pipeline_policy()
    expect_identical(politika$eszamanli_sinir, 3L)
    expect_identical(politika$baslangic_tampon_suresi_sn, 9)
  })
})
