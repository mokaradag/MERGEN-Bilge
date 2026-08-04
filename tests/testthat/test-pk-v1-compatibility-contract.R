# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-v1-compatibility-contract.R
# Açıklama: Motor sınırı sözleşmesi (master plan §10). `MERGEN_PK_ENGINE=v1`
#           iken D1–D5, D7–D9 ve D12 davranışları DEĞİŞMEMİŞ olmalıdır; yalnızca
#           dört çapraz-motor madde farklılaşabilir: koşulsuz RLS kapalı
#           başarısızlığı, salt-okunur SQL reddi, ODBC hata redaksiyonu ve
#           Faz 0 gözlem/durum tesisatı.
#
#           Tümü çevrimdışı ve deterministiktir: gerçek DB, LLM, tarayıcı, SSO,
#           ağ veya gerçek sır KULLANILMAZ.
# ==============================================================================

.pk_v1_env <- function() {
  repo_root <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
  for (f in c("helpers_pk_config.R", "helpers_pk_text_turkish.R",
              "helpers_pk_provenance.R", "helpers_pk_filter_compile.R",
              "helpers_pk_filter_policy.R", "helpers_pk_analysis_filters_v2.R")) {
    source(file.path(repo_root, "R", f), encoding = "UTF-8", local = env)
  }
  # apply_smart_filters ve v1 gövdesi; dispatch yüzeyi en sonda yüklenir.
  env$summarize_columns_for_ai <- function(...) ""
  source(file.path(repo_root, "R", "helpers_pk_analysis_filters_base.R"),
         encoding = "UTF-8", local = env)
  source(file.path(repo_root, "R", "helpers_pk_analysis_filters.R"),
         encoding = "UTF-8", local = env)
  env
}

.pk_v1_data <- function() {
  data.frame(
    ProjeAdi = c("SENTETIK RADAR", "SENTETIK ELEKTRONIK HARP", "SENTETIK LOJISTIK"),
    Durum = c("Aktif", "Aktif", "Pasif"),
    Butce = c(10, 20, 30),
    stringsAsFactors = FALSE
  )
}

# Ciktiyi bastirarak filtre uygular (v1 gövdesi bol miktarda cat() yazar).
.pk_v1_apply <- function(env, veri, talimat) {
  sonuc <- NULL
  utils::capture.output(
    sonuc <- env$apply_smart_filters(veri, talimat, "sentetik soru"),
    type = "output"
  )
  sonuc
}

test_that("v1 varsayilandir: bayrak verilmediginde motor v1'dir", {
  env <- .pk_v1_env()

  withr::with_envvar(list(MERGEN_PK_ENGINE = NA_character_), {
    withr::with_options(list(mergen.pk.engine = NULL), {
      expect_identical(env$pk_engine_mode(), "v1")
      expect_false(isTRUE(env$pk_engine_is_v2()))
    })
  })
})

test_that("D1: v1 AYNI sutundaki filtreleri HALA kesistirir (davranis degismedi)", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "ProjeAdi", value = "RADAR", operation = "contains"),
    list(column = "ProjeAdi", value = "ELEKTRONIK HARP", operation = "contains")
  ))

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v1"), {
    v1 <- .pk_v1_apply(env, veri, talimat)
    # v1'in bilinen kusuru KORUNUR: kesisim -> 0 satir.
    expect_equal(nrow(v1), 0L)
  })

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    v2 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v2), 2L)
  })
})

test_that("D2: v1 cok degerli filtreyi HALA kirpar (davranis degismedi)", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "ProjeAdi",
         value = c("SENTETIK RADAR", "SENTETIK LOJISTIK"),
         operation = "exact_match")
  ))

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v1"), {
    v1 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v1), 1L)   # yalnizca ILK deger uygulandi
  })

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    v2 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v2), 2L)
  })
})

test_that("D5: v1 filter_expression'i HALA calistirir, v2 ASLA calistirmaz", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(
    filters = list(),
    filter_expression = "{ .pk_v1_sayac <<- .pk_v1_sayac + 1L; Butce > 15 }"
  )

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v1"), {
    env$.pk_v1_sayac <- 0L
    v1 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v1), 2L)
    expect_true(env$.pk_v1_sayac > 0L)   # ifade GERCEKTEN calistirildi
  })

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    env$.pk_v1_sayac <- 0L
    v2 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v2), 3L)           # ifade yok sayildi
    expect_identical(env$.pk_v1_sayac, 0L)
  })
})

test_that("D4: v1'de sifir eslesme politikasi YOKTUR", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "ProjeAdi", value = "HIC OLMAYAN", operation = "exact_match")
  ))

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v1"), {
    v1 <- .pk_v1_apply(env, veri, talimat)
    expect_equal(nrow(v1), 0L)
    # v1 karar ozniteligi TASIMAZ.
    expect_null(attr(v1, env$PK_FILTER_V2_ATTR, exact = TRUE))
  })

  withr::with_envvar(list(MERGEN_PK_ENGINE = "v2"), {
    v2 <- .pk_v1_apply(env, veri, talimat)
    karar <- attr(v2, env$PK_FILTER_V2_ATTR, exact = TRUE)
    expect_identical(karar$action, "refuse")
  })
})

test_that("D9: filtre zaman asimi v1'de 8 saniyede sabit kalir", {
  metin_yolu <- file.path(resolve_repo_root_for_tests(),
                          "R", "helpers_pk_analysis_filters_base.R")
  size <- suppressWarnings(file.info(metin_yolu)$size[1])
  con <- file(metin_yolu, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  metin <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  # v1 varsayilani 8 saniye olarak KORUNUR; yapilandirilabilir deger yalnizca
  # v2 dalinda tuketilir.
  expect_true(grepl("filter_timeout <- 8", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("MERGEN_PK_FILTER_TIMEOUT_SEC", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_engine_is_v2()", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("v1 gozlem sozlesmesi (Faz 0) her iki motorda da korunur", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()

  talimat <- list(filters = list(
    list(column = "Durum", value = "Aktif", operation = "exact_match")
  ))

  for (motor in c("v1", "v2")) {
    withr::with_envvar(list(MERGEN_PK_ENGINE = motor), {
      sonuc <- .pk_v1_apply(env, veri, talimat)
      expect_equal(nrow(sonuc), 2L, info = motor)

      gozlem <- env$pk_filter_observation_take(list(question = "sentetik soru"))
      expect_true(is.list(gozlem), info = motor)
      expect_identical(as.integer(gozlem$matched_rows), 2L, info = motor)
      expect_true(length(gozlem$applied_filters) > 0L, info = motor)
    })
  }
})

test_that("dort capraz-motor madde v1'de de ETKINDIR", {
  repo_root <- resolve_repo_root_for_tests()

  oku <- function(rel) {
    full <- file.path(repo_root, rel)
    size <- suppressWarnings(file.info(full)$size[1])
    con <- file(full, open = "rb")
    on.exit(close(con), add = TRUE)
    raw_data <- readBin(con, what = "raw", n = size)
    txt <- suppressWarnings(iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]])
    satirlar <- strsplit(enc2utf8(txt), "\n", fixed = TRUE)[[1]]
    satirlar <- satirlar[!grepl("^\\s*#", satirlar, perl = TRUE, useBytes = TRUE)]
    paste(satirlar, collapse = "\n")
  }

  # 1) RLS kapali basarisizligi ve 2) salt-okunur SQL kapisi ve
  # 3) ODBC redaksiyonu: hicbiri motor bayragina bagli DEGILDIR.
  for (dosya in c("R/helpers_pk_rls.R", "R/helpers_pk_sql_readonly.R",
                  "R/helpers_pk_safe_errors.R")) {
    metin <- oku(dosya)
    expect_false(grepl("MERGEN_PK_ENGINE", metin, fixed = TRUE, useBytes = TRUE), info = dosya)
    expect_false(grepl("pk_engine_is_v2", metin, fixed = TRUE, useBytes = TRUE), info = dosya)
  }

  # 4) Faz 0 gozlem/durum tesisati da bayraktan bagimsizdir.
  gozlem <- oku("R/helpers_pk_analysis_filters.R")
  expect_true(grepl(".pk_filter_observation_store(", gozlem, fixed = TRUE, useBytes = TRUE))
})

test_that("v2'ye ozgu davranis dosyalari motor bayragina BAGLI kalir", {
  repo_root <- resolve_repo_root_for_tests()

  # Modul, v2 davranislarini yalnizca bayrak acikken devreye alir.
  full <- file.path(repo_root, "R", "module_proje_kaynak_analizi.R")
  size <- suppressWarnings(file.info(full)$size[1])
  con <- file(full, open = "rb")
  on.exit(close(con), add = TRUE)
  raw_data <- readBin(con, what = "raw", n = size)
  metin <- enc2utf8(suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  ))

  expect_true(grepl("pk_engine_is_v2(", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_filter_degraded_gate(", metin, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("pk_engine_v2 &&", metin, fixed = TRUE, useBytes = TRUE))
})

test_that("motor kipi sorgu metadatasindan (query$meta) cozulur", {
  env <- .pk_v1_env()
  veri <- .pk_v1_data()
  talimat <- list(filters = list(
    list(column = "Durum", operation = "exact_match", value = "Aktif")
  ))

  # `.pk_filter_observation_context()` cagri cercevesinden TAM sorgu nesnesini
  # toplar; motor kipi bu yuzden modulun okudugu alanla AYNI yerden
  # cozulmelidir. Aksi halde modul v2 sanip politika/butce uygularken filtreler
  # v1 govdesinde kalir ve D1-D5 sessizce devre disi kalirdi.
  cagir <- function(sorgu) {
    selected_query <- sorgu
    sonuc <- NULL
    utils::capture.output(
      sonuc <- env$apply_smart_filters(veri, talimat, "sentetik soru"),
      type = "output"
    )
    sonuc
  }

  withr::with_envvar(list(MERGEN_PK_ENGINE = NA_character_), {
    withr::with_options(list(mergen.pk.engine = NULL), {
      v2_sonuc <- cagir(list(id = "q", name = "Q", meta = list(engine = "v2")))
      expect_false(
        is.null(attr(v2_sonuc, env$PK_FILTER_V2_ATTR, exact = TRUE)),
        info = "meta$engine = v2 iken filtreler v2 govdesinde calismalidir."
      )

      # Ust duzey `engine` alani motor kipini DEGISTIRMEZ; modul onu okumaz.
      v1_sonuc <- cagir(list(id = "q", name = "Q", engine = "v2", meta = list()))
      expect_true(
        is.null(attr(v1_sonuc, env$PK_FILTER_V2_ATTR, exact = TRUE)),
        info = "Ust duzey engine alani v2'yi tetiklememelidir (modul meta okur)."
      )
    })
  })
})
