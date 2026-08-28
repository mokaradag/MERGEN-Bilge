# ==============================================================================
# Dosya Yolu: tests/testthat/test-bootstrap-source-manifest-behavior.R
# Açıklama: R/bootstrap_source_manifest.R saf manifest doğrulama yardımcılarının
#           DAVRANIŞSAL testleri. Bu dosya davranışsal olarak daha önce test
#           edilmiyordu (yalnızca yapısal sözleşme testlerinde adı geçiyordu).
#
#           Kapsananlar:
#           - source_manifest_validate_files(): boş/yinelenen/eksik dosya tespiti.
#           - source_manifest_validate_order(): kritik sıra kuralı ihlali tespiti.
#           - source_manifest_validate_order_rule_targets(): kural hedeflerinin
#             manifest/boot allowlist içinde olması.
#           - source_manifest_validate_parse(): UTF-8 parse doğrulaması.
#
#           Hatalar "Kaynak manifesti doğrulaması başarısız: ..." önekiyle gelir.
#           Yan etkisiz; gerçek uygulama yüklenmez. Geçici dosyalarla deterministik.
# ==============================================================================

.source_manifest_bootstrap_for_test <- function() {
  env <- new.env(parent = globalenv())
  source(
    file.path(resolve_repo_root_for_tests(), "R", "bootstrap_source_manifest.R"),
    encoding = "UTF-8",
    local = env
  )
  env
}

# Geçici repo kökü altında gerçek R dosyaları üretir.
.make_manifest_repo <- function(files) {
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  for (rel in names(files)) {
    full <- file.path(tmp, rel)
    dir.create(dirname(full), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[rel]], full, useBytes = TRUE)
  }
  tmp
}

# ------------------------------------------------------------------------------
# source_manifest_validate_files
# ------------------------------------------------------------------------------
testthat::test_that("validate_files karakter olmayan veya boş manifesti reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(env$source_manifest_validate_files(NULL),
                         regexp = "karakter vektörü değil")
  testthat::expect_error(env$source_manifest_validate_files(character(0)),
                         regexp = "karakter vektörü değil")
})

testthat::test_that("validate_files boş/yalnızca-boşluk dosya yolunu reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(
    env$source_manifest_validate_files(c("R/a.R", "   ")),
    regexp = "boş dosya yolu"
  )
})

testthat::test_that("validate_files yinelenen dosya yollarını reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/a.R" = "x <- 1", "R/b.R" = "y <- 2"))
  testthat::expect_error(
    env$source_manifest_validate_files(c("R/a.R", "R/b.R", "R/a.R"), repo_root = repo),
    regexp = "tekrar eden kaynak dosya"
  )
})

testthat::test_that("validate_files eksik dosyaları açık adla raporlar", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/a.R" = "x <- 1"))
  testthat::expect_error(
    env$source_manifest_validate_files(c("R/a.R", "R/yok.R"), repo_root = repo),
    regexp = "eksik kaynak dosya"
  )
})

testthat::test_that("validate_files tüm dosyalar mevcutsa TRUE döner", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/a.R" = "x <- 1", "R/b.R" = "y <- 2"))
  testthat::expect_true(env$source_manifest_validate_files(c("R/a.R", "R/b.R"), repo_root = repo))
})

# ------------------------------------------------------------------------------
# source_manifest_validate_order
# ------------------------------------------------------------------------------
testthat::test_that("validate_order boş kural listesinde TRUE döner", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_true(env$source_manifest_validate_order(c("R/a.R", "R/b.R"), list()))
})

testthat::test_that("validate_order doğru sırada TRUE, ihlalde hata verir", {
  env <- .source_manifest_bootstrap_for_test()
  paths <- c("R/a.R", "R/b.R", "R/c.R")
  # a, b'den önce -> doğru.
  testthat::expect_true(
    env$source_manifest_validate_order(paths, list(c("R/a.R", "R/b.R")))
  )
  # c, a'dan önce yüklenmeli kuralı ama c sonra geliyor -> ihlal.
  testthat::expect_error(
    env$source_manifest_validate_order(paths, list(c("R/c.R", "R/a.R"))),
    regexp = "yanlış kaynak sırası"
  )
})

testthat::test_that("validate_order manifestte olmayan kural hedeflerinde sıra kontrolünü atlar", {
  env <- .source_manifest_bootstrap_for_test()
  paths <- c("R/a.R", "R/b.R")
  # Kuraldaki R/x.R manifestte yok -> sıra karşılaştırması atlanır, TRUE.
  testthat::expect_true(
    env$source_manifest_validate_order(paths, list(c("R/a.R", "R/x.R")))
  )
})

testthat::test_that("validate_order geçersiz kural tanımını (uzunluk != 2) reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(
    env$source_manifest_validate_order(c("R/a.R"), list("R/a.R")),
    regexp = "geçersiz sıra kuralı"
  )
})

# ------------------------------------------------------------------------------
# source_manifest_validate_order_rule_targets
# ------------------------------------------------------------------------------
testthat::test_that("validate_order_rule_targets manifest dışı hedefi reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_error(
    env$source_manifest_validate_order_rule_targets(
      paths = c("R/a.R", "R/b.R"),
      order_rules = list(c("R/a.R", "R/dishedef.R"))
    ),
    regexp = "manifest/boot allowlist dışında"
  )
})

testthat::test_that("validate_order_rule_targets optional_paths ile karşılanan hedefi kabul eder", {
  env <- .source_manifest_bootstrap_for_test()
  testthat::expect_true(
    env$source_manifest_validate_order_rule_targets(
      paths = c("R/a.R"),
      order_rules = list(c("R/a.R", "R/boot.R")),
      optional_paths = c("R/boot.R")
    )
  )
})

# ------------------------------------------------------------------------------
# source_manifest_validate_parse
# ------------------------------------------------------------------------------
testthat::test_that("validate_parse geçerli R dosyalarında TRUE döner", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/ok.R" = c("f <- function(x) {", "  x + 1", "}")))
  testthat::expect_true(env$source_manifest_validate_parse("R/ok.R", repo_root = repo))
})

testthat::test_that("validate_parse CRLF satır sonlarını doğru işler", {
  env <- .source_manifest_bootstrap_for_test()

  repo <- withr::local_tempdir()
  dir.create(file.path(repo, "R"), recursive = TRUE, showWarnings = FALSE)

  con <- file(file.path(repo, "R", "crlf.R"), open = "wb")
  tryCatch(
    writeBin(charToRaw("f <- function(x) {\r\n  x + 1\r\n}"), con),
    finally = close(con)
  )

  testthat::expect_true(
    env$source_manifest_validate_parse("R/crlf.R", repo_root = repo)
  )
})

testthat::test_that("validate_parse söz dizimi hatalı dosyayı reddeder", {
  env <- .source_manifest_bootstrap_for_test()
  repo <- .make_manifest_repo(list("R/bozuk.R" = c("f <- function(x {", "  x + 1")))
  testthat::expect_error(
    env$source_manifest_validate_parse("R/bozuk.R", repo_root = repo),
    regexp = "parse edilemedi"
  )
})
# ------------------------------------------------------------------------------
# Faz 3a: "yokluğu BEKLENEN" opsiyonel gruplar
# ------------------------------------------------------------------------------
# Ayrım önemlidir: codex_hardening eksikse çalışma kopyası bozuktur ve bu
# GÜRÜLTÜLÜ bildirilmelidir. Gitignore'lu, VM'e özgü dosyalar ise her bulut/CI
# checkout'unda tasarım gereği yoktur; onlar için her boot'ta uyarı yazmak,
# gerçek sorunu gösteren uyarıyı gürültüye boğar.

# Verilen ortamı opsiyonel grup yapılandırmasıyla donatıp yolları ayıklar ve
# bu sırada üretilen mesajları toplar.
.manifest_present_with_groups <- function(groups, expected_absent, paths, repo_root) {
  env <- .source_manifest_bootstrap_for_test()
  assign("source_manifest_optional_source_groups", groups, envir = env)
  assign("source_manifest_optional_source_paths",
         unlist(groups, use.names = FALSE), envir = env)
  assign("source_manifest_expected_absent_source_groups", expected_absent, envir = env)

  # Süreç başına bir kez uyarma önbelleği testler arasında sızmasın.
  assign(".source_manifest_warned", new.env(parent = emptyenv()), envir = env)

  mesajlar <- character(0)
  sonuc <- withCallingHandlers(
    env$source_manifest_present_paths(paths, repo_root = repo_root),
    message = function(m) {
      mesajlar <<- c(mesajlar, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )

  list(paths = sonuc, messages = mesajlar)
}

testthat::test_that("yokluğu beklenen opsiyonel grup SESSİZCE atlanır", {
  repo <- .make_manifest_repo(list("R/var.R" = "x <- 1"))

  sonuc <- .manifest_present_with_groups(
    groups = list(pk_yerel = "R/yok.R"),
    expected_absent = "pk_yerel",
    paths = c("R/var.R", "R/yok.R"),
    repo_root = repo
  )

  # Dosya yine atlanır (opsiyonel sözleşmesi korunur)...
  testthat::expect_equal(sonuc$paths, "R/var.R")
  # ...ama hiçbir uyarı yazılmaz.
  testthat::expect_equal(sonuc$messages, character(0))
})

testthat::test_that("yokluğu beklenmeyen opsiyonel grup GÜRÜLTÜLÜ kalır", {
  repo <- .make_manifest_repo(list("R/var.R" = "x <- 1"))

  sonuc <- .manifest_present_with_groups(
    groups = list(sertlestirme = "R/yok.R"),
    expected_absent = character(0),
    paths = c("R/var.R", "R/yok.R"),
    repo_root = repo
  )

  testthat::expect_equal(sonuc$paths, "R/var.R")
  testthat::expect_true(any(grepl("DEVRE DISI", sonuc$messages, fixed = TRUE)))
  testthat::expect_true(any(grepl("R/yok.R", sonuc$messages, fixed = TRUE)))
})

testthat::test_that("beklenen-eksik listesi grubun ATOMİKLİĞİNİ değiştirmez", {
  # Bir üyesi eksik olan grubun TÜM üyeleri düşer; susturma yalnızca mesajı
  # etkiler, yükleme kararını değil.
  repo <- .make_manifest_repo(list("R/a.R" = "x <- 1", "R/var.R" = "y <- 2"))

  sonuc <- .manifest_present_with_groups(
    groups = list(ikili = c("R/a.R", "R/yok.R")),
    expected_absent = "ikili",
    paths = c("R/var.R", "R/a.R", "R/yok.R"),
    repo_root = repo
  )

  testthat::expect_equal(sonuc$paths, "R/var.R")
  testthat::expect_equal(sonuc$messages, character(0))
})
