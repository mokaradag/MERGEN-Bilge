# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-config-resolver-behavior.R
# Açıklama: Proje ve Kaynak Analizi yapılandırma çözümleyicisinin davranış
#           testleri. Tamamen çevrimdışı ve belirlenimcidir: DB, LLM, tarayıcı,
#           ağ veya gizli değer GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Öncelik sırası: sorgu metadata > ortam değişkeni > options() > varsayılan.
#   - Worker güvenliği: değer future worker içinde Sys.getenv ile okunabilir,
#     kapanış serileştirilmesine gerek yoktur.
#   - Geçersiz/çözümlenemeyen değer sessizce bir alt önceliğe düşer.
#   - Gizli anahtarlar tanılama çıktısında ham olarak görünmez.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  source(file.path(repo_root, "R", "helpers_pk_config.R"),
         encoding = "UTF-8", local = globalenv())
})

# Ortam değişkeni ve options() değerlerini test kapsamında güvenle değiştirip
# geri yükleyen yardımcı (withr bağımlılığı eklemeden).
.pk_cfg_with_settings <- function(envs = list(), opts = list(), code) {
  old_env <- Sys.getenv(names(envs), unset = NA_character_, names = TRUE)

  # DİKKAT: options(eski_liste) yalnızca verilen adları geri yazar; testte YENİ
  # eklenen bir seçenek kaldırılmaz ve sonraki teste sızar. Bu yüzden yalnızca
  # dokunulan adlar hedefli biçimde geri alınır (yoktu ise NULL'a çekilir).
  old_opts <- if (length(opts) > 0) {
    stats::setNames(lapply(names(opts), function(nm) getOption(nm, default = NULL)), names(opts))
  } else {
    list()
  }

  set_env <- function(nm, val) {
    if (is.null(val) || is.na(val)) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(as.character(val)), nm))
    }
  }

  on.exit({
    for (nm in names(envs)) set_env(nm, old_env[[nm]])
    if (length(old_opts) > 0) options(old_opts)
  }, add = TRUE)

  for (nm in names(envs)) set_env(nm, envs[[nm]])
  if (length(opts) > 0) options(opts)

  force(code)
}

test_that("çözümleyici yerleşik varsayılanları döndürür", {
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_TELEMETRY = NULL, MERGEN_PK_ENGINE = NULL,
                MERGEN_PK_LOG_QUESTION_TEXT = NULL),
    code = {
      expect_true(pk_config_resolve("MERGEN_PK_TELEMETRY"))
      expect_false(pk_config_resolve("MERGEN_PK_LOG_QUESTION_TEXT"))
      expect_identical(pk_config_resolve("MERGEN_PK_ENGINE"), "v1")
    }
  )
})

test_that("options() yerleşik varsayılanı ezer", {
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_TELEMETRY = NULL),
    opts = list(mergen.pk.telemetry = FALSE),
    code = expect_false(pk_config_resolve("MERGEN_PK_TELEMETRY"))
  )
})

test_that("ortam değişkeni options() değerini ezer", {
  # CLAUDE.md'deki DB_CLIENT_ENCODING sözleşmesiyle aynı yön: ortam, R
  # options() değerinden ÖNCE gelir.
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_TELEMETRY = "false"),
    opts = list(mergen.pk.telemetry = TRUE),
    code = expect_false(pk_config_resolve("MERGEN_PK_TELEMETRY"))
  )
})

test_that("sorgu bazlı metadata ortam değişkenini de ezer", {
  # §9: ağır bir sorgu kendi sınırını taşıyabilsin diye metadata en yüksek
  # önceliktedir.
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_TELEMETRY = "true"),
    opts = list(mergen.pk.telemetry = TRUE),
    code = expect_false(
      pk_config_resolve("MERGEN_PK_TELEMETRY", query_meta = list(telemetry = FALSE))
    )
  )
})

test_that("öncelik zinciri tam sırayla uygulanır", {
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_ENGINE = "v2"),
    opts = list(mergen.pk.engine = "v1"),
    code = {
      # metadata > env
      expect_identical(
        pk_config_resolve("MERGEN_PK_ENGINE", query_meta = list(engine = "v1")),
        "v1"
      )
      # env > options
      expect_identical(pk_config_resolve("MERGEN_PK_ENGINE"), "v2")
    }
  )
})

test_that("geçersiz değerler sessizce bir alt önceliğe düşer", {
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_TELEMETRY = "belki"),
    code = expect_true(pk_config_resolve("MERGEN_PK_TELEMETRY"))
  )

  # İzin verilmeyen enum değeri kabul edilmez.
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_ENGINE = "v9"),
    code = expect_identical(pk_config_resolve("MERGEN_PK_ENGINE"), "v1")
  )

  # Geçersiz metadata da atlanır; env değeri devreye girer.
  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_TELEMETRY = "false"),
    code = expect_false(
      pk_config_resolve("MERGEN_PK_TELEMETRY", query_meta = list(telemetry = "sacma"))
    )
  )
})

test_that("Türkçe mantıksal yazımlar desteklenir", {
  for (dogru in c("evet", "acik", "açık", "1", "on", "TRUE")) {
    .pk_cfg_with_settings(
      envs = list(MERGEN_PK_LOG_QUESTION_TEXT = dogru),
      code = expect_true(
        pk_config_resolve("MERGEN_PK_LOG_QUESTION_TEXT"),
        info = sprintf("'%s' TRUE olarak çözülmeli", dogru)
      )
    )
  }

  for (yanlis in c("hayır", "kapali", "0", "off", "FALSE")) {
    .pk_cfg_with_settings(
      envs = list(MERGEN_PK_TELEMETRY = yanlis),
      code = expect_false(
        pk_config_resolve("MERGEN_PK_TELEMETRY"),
        info = sprintf("'%s' FALSE olarak çözülmeli", yanlis)
      )
    )
  }
})

test_that("tanımsız anahtar sessizce varsayılan uydurmaz, hata verir", {
  expect_error(pk_config_resolve("MERGEN_PK_OLMAYAN_ANAHTAR"), "tanimsiz")
})

test_that("anahtar adı eşlemesi metadata ve options adlarını üretir", {
  expect_identical(pk_config_meta_key("MERGEN_PK_TELEMETRY"), "telemetry")
  expect_identical(pk_config_option_key("MERGEN_PK_TELEMETRY"), "mergen.pk.telemetry")
})

test_that("çözümleyici worker güvenlidir: yalnızca Sys.getenv okur", {
  # Kapanış serileştirmesi gerekmediğini kanıtlamak için fonksiyon gövdesinde
  # kaynak seviyesinde Sys.getenv kullanımı aranır (CLAUDE.md worker kuralı:
  # MERGEN_LLM_TIMEOUT_SEC ile aynı desen).
  body_txt <- paste(deparse(body(pk_config_resolve)), collapse = "\n")
  expect_true(grepl("Sys.getenv", body_txt, fixed = TRUE))

  # Temiz bir ortamda (worker benzeri) yalnızca dosyayı source ederek çalışır.
  worker_env <- new.env(parent = globalenv())
  source(file.path(resolve_repo_root_for_tests(), "R", "helpers_pk_config.R"),
         encoding = "UTF-8", local = worker_env)

  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_ENGINE = "v2"),
    code = expect_identical(worker_env$pk_config_resolve("MERGEN_PK_ENGINE"), "v2")
  )
})

test_that("tanılama özeti gizli anahtarın ham değerini sızdırmaz", {
  fake_key <- paste0("sahte-", paste(rep("x", 24), collapse = ""))

  .pk_cfg_with_settings(
    envs = list(MERGEN_PK_TELEMETRY_HMAC_KEY = fake_key),
    code = {
      snapshot <- pk_config_safe_snapshot()
      flat <- paste(unlist(snapshot), collapse = " ")

      expect_false(grepl(fake_key, flat, fixed = TRUE))
      expect_true(snapshot$MERGEN_PK_TELEMETRY_HMAC_KEY$present)
      expect_identical(snapshot$MERGEN_PK_TELEMETRY_HMAC_KEY$nchar, nchar(fake_key))
      expect_identical(snapshot$MERGEN_PK_TELEMETRY_HMAC_KEY$value, "<hidden>")
    }
  )
})

# BEYAN EDİLMİŞ AMA BOZUK DEĞER "YOK" DEĞİLDİR.
#
# Çok elemanlı ya da açıkça NA bir eşik beyanı sessizce ATLANIYOR,
# `invalid_sources` boş kalıyor ve `pk_resolve_thresholds()` yapılandırmayı
# GEÇERLİ rapor ediyordu: operatör eşiği değiştirdiğini sanırken varlık
# çözümlemesi başka bir eşikle çalışıyordu (kapalı-başarısız ihlali).
test_that("bozuk eşik beyanı YOK değil GEÇERSİZ raporlanır", {
  eski <- getOption("mergen.pk.resolve_auto_score", default = NULL)
  on.exit(options(mergen.pk.resolve_auto_score = eski), add = TRUE)

  options(mergen.pk.resolve_auto_score = c(90L, 95L))
  sonda <- pk_config_probe("MERGEN_PK_RESOLVE_AUTO_SCORE")
  expect_true("options" %in% sonda$invalid_sources)

  options(mergen.pk.resolve_auto_score = NA)
  expect_true("options" %in% pk_config_probe("MERGEN_PK_RESOLVE_AUTO_SCORE")$invalid_sources)

  # AYARLANMAMIS ortam degiskeni GECERSIZ SAYILMAZ: `Sys.getenv()` sentinel'i
  # "beyan edilmis ama bozuk" ile karistirilmamalidir.
  options(mergen.pk.resolve_auto_score = NULL)
  expect_equal(pk_config_probe("MERGEN_PK_RESOLVE_AUTO_SCORE")$invalid_sources,
               character(0))
})
