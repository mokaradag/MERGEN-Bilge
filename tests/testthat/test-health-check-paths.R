# ==============================================================================
# Dosya Yolu: tests/testthat/test-health-check-paths.R
# Açıklama: Sistem Durumu dosya yolu ve index JSON kontrollerini test eder.
# ==============================================================================

.bootstrap_health_path_tests <- function() {
  helper_candidates <- c("tests/testthat/helper_bootstrap.R", "testthat/helper_bootstrap.R", "helper_bootstrap.R")
  helper_path <- helper_candidates[file.exists(helper_candidates)][1]
  if (!is.na(helper_path) && nzchar(helper_path)) source(helper_path, encoding = "UTF-8", local = globalenv())
  if (!exists("resolve_repo_root_for_tests", mode = "function", inherits = TRUE)) {
    resolve_repo_root_for_tests <<- function() normalizePath(if (file.exists("app.R")) "." else "../..", winslash = "/", mustWork = TRUE)
  }
  repo_root <- resolve_repo_root_for_tests()
  source(file.path(repo_root, "R", "helpers_health_formatters.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_files_path.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_health_runtime_checks.R"), encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_health_checks.R"), encoding = "UTF-8", local = globalenv())
}

.bootstrap_health_path_tests()

test_that("geçici klasör yazılabilir olarak raporlanır", {
  tmp <- tempdir()
  res <- health_check_path_writable("tmp.write", "Temp Yazma", tmp)
  expect_identical(res$status[1], "ok")
  expect_true(all(c("id", "label", "status", "severity", "value", "detail", "duration_ms", "checked_at", "remediation") %in% names(res)))
})

test_that("eksik klasör kritik olarak raporlanır", {
  missing <- file.path(tempdir(), paste0("missing-", as.integer(Sys.time())))
  if (dir.exists(missing)) unlink(missing, recursive = TRUE, force = TRUE)
  expect_warning(
    res <- health_check_path_writable("missing.write", "Eksik Klasör", missing),
    regexp = NA
  )
  expect_identical(res$status[1], "critical")
})

test_that("index JSON üst klasöründe okuma yazma kontrolü güvenli çalışır", {
  tmp <- tempfile("index-root-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")
  writeLines("{}", idx, useBytes = TRUE)
  res <- health_check_index_json(idx)
  expect_identical(res$status[1], "ok")
  expect_false(file.exists(file.path(tmp, ".index-health-should-not-exist.json")))
})

test_that("henüz oluşmamış index JSON yazılabilir üst klasörde kritik değildir", {
  tmp <- tempfile("index-lazy-root-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")

  res <- health_check_index_json(idx)

  expect_identical(res$status[1], "ok")
  expect_match(res$detail[1], "henüz oluşturulmamış", fixed = TRUE)
  expect_false(file.exists(idx))
})

test_that("UNC varlık sorguları yanlış negatif olsa da gerçek yazma kanıttır", {
  tmp <- tempfile("unc-health-probe-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")

  had_dir_exists <- exists("dir.exists", envir = .GlobalEnv, inherits = FALSE)
  old_dir_exists <- if (had_dir_exists) get("dir.exists", envir = .GlobalEnv, inherits = FALSE) else NULL
  had_relaxed <- exists("path_exists_relaxed", envir = .GlobalEnv, inherits = FALSE)
  old_relaxed <- if (had_relaxed) get("path_exists_relaxed", envir = .GlobalEnv, inherits = FALSE) else NULL

  withr::defer({
    if (had_dir_exists) assign("dir.exists", old_dir_exists, envir = .GlobalEnv)
    else if (exists("dir.exists", envir = .GlobalEnv, inherits = FALSE)) rm(list = "dir.exists", envir = .GlobalEnv)

    if (had_relaxed) assign("path_exists_relaxed", old_relaxed, envir = .GlobalEnv)
    else if (exists("path_exists_relaxed", envir = .GlobalEnv, inherits = FALSE)) rm(list = "path_exists_relaxed", envir = .GlobalEnv)
  })

  assign("dir.exists", function(...) FALSE, envir = .GlobalEnv)
  assign("path_exists_relaxed", function(...) FALSE, envir = .GlobalEnv)

  root_res <- health_check_path_writable("unc.write", "UNC Yazma", tmp)
  index_res <- health_check_index_json(idx)

  expect_identical(root_res$status[1], "ok")
  expect_identical(index_res$status[1], "ok")
  expect_false(file.exists(idx))
})

test_that("index kontrolü ham ortam değeri yerine kanonik runtime yolunu kullanır", {
  tmp <- tempfile("index-runtime-root-")
  dir.create(tmp, recursive = TRUE)
  idx <- file.path(tmp, "index.json")
  invalid_idx <- file.path(tmp, "missing-parent", "index.json")

  old_option <- options(mergen.index_path = idx)
  old_env <- Sys.getenv("MERGEN_INDEX_PATH", unset = NA_character_)
  withr::defer({
    options(old_option)
    if (is.na(old_env)) Sys.unsetenv("MERGEN_INDEX_PATH") else Sys.setenv(MERGEN_INDEX_PATH = old_env)
  })
  Sys.setenv(MERGEN_INDEX_PATH = invalid_idx)

  res <- health_check_index_json()

  expect_identical(res$status[1], "ok")
  expect_identical(res$value[1], idx)
})

test_that("boş index yolu tanımlı değil olarak döner", {
  res <- health_check_index_json("")
  expect_identical(res$status[1], "not_configured")
})

test_that("mojibake Türkçe yol onarılıp gerçek klasör bulunur (files_root)", {
  # VM senaryosu: Sys.getenv Türkçe UNC yolunu mojibake döndürür
  # (ör. "Geliştirme" -> "GeliÅŸtirme"); repair_turkish_mojibake_path bunu onarır.
  # Kontrol onarılmış yolu kullanmalı, gerçek klasörü bulmalı ve temiz göstermeli.
  base <- tempfile("moji-root-")
  real <- file.path(base, "Gelistirme_REAL", "data")
  dir.create(real, recursive = TRUE)
  mojibake_in <- file.path(base, "Gelistirme_MOJI", "data")

  had <- exists("repair_turkish_mojibake_path", envir = .GlobalEnv, inherits = FALSE)
  old <- if (had) get("repair_turkish_mojibake_path", envir = .GlobalEnv) else NULL
  assign("repair_turkish_mojibake_path",
         function(p) gsub("Gelistirme_MOJI", "Gelistirme_REAL", p, fixed = TRUE),
         envir = .GlobalEnv)
  withr::defer({
    if (had) assign("repair_turkish_mojibake_path", old, envir = .GlobalEnv)
    else rm("repair_turkish_mojibake_path", envir = .GlobalEnv)
  })

  res <- health_check_path_writable("moji.files_root", "Kök", mojibake_in,
                                    create_if_missing = FALSE, require_write = FALSE)
  expect_identical(res$status[1], "ok")
  expect_true(grepl("Gelistirme_REAL", res$value[1], fixed = TRUE))
})

test_that("yol varyant üreteci slash/backslash biçimlerini kapsar", {
  variants <- .health_path_variants("//sunucu/pay/MERGEN Bilge/data")
  # forward-slash ve backslash UNC biçimleri denenecek adaylar arasında olmalı.
  expect_true("//sunucu/pay/MERGEN Bilge/data" %in% variants)
  expect_true("\\\\sunucu\\pay\\MERGEN Bilge\\data" %in% variants)
  # Boş yol boş vektör döndürür.
  expect_identical(.health_path_variants(""), character(0))
})

test_that("require_write=FALSE: var olan klasör yazma testi geçmese bile SAĞLIKLI (ok)", {
  # files_root senaryosu: kök gerçekten var (Explorer'da görünür) ama UNC/izin
  # nedeniyle yazma testi geçmiyor. KÖK yazması bu kontrol için zorunlu değil
  # (asıl yazma hedefi index.json ayrı kontrol edilir), o yüzden UYARI/KRİTİK
  # değil SAĞLIKLI (ok) olmalı.
  existing <- tempfile("kok-var-yazilmaz-")
  dir.create(existing, recursive = TRUE)

  old_probe <- .health_write_probe
  assign(".health_write_probe",
         function(...) list(ok = FALSE, error = "yazma reddedildi (test)"),
         envir = .GlobalEnv)
  withr::defer(assign(".health_write_probe", old_probe, envir = .GlobalEnv))

  res <- health_check_path_writable("files_root.test", "Kök", existing,
                                    create_if_missing = FALSE, require_write = FALSE)
  expect_identical(res$status[1], "ok")

  # Ama gerçekten olmayan klasör require_write=FALSE olsa da kritik kalır.
  missing <- file.path(tempdir(), paste0("kok-yok-", as.integer(Sys.time()), "-", sample(1e6, 1)))
  if (dir.exists(missing)) unlink(missing, recursive = TRUE, force = TRUE)
  res2 <- health_check_path_writable("files_root.missing", "Kök Yok", missing,
                                     create_if_missing = FALSE, require_write = FALSE)
  expect_identical(res2$status[1], "critical")
  expect_false(dir.exists(missing))
})

test_that("var olan ancak yazılamayan klasör KRİTİK değil UYARI olarak raporlanır", {
  # Kullanıcı senaryosu: UNC klasörü gerçekten var (Explorer'da görünüyor) ama
  # yol formu ya da izin nedeniyle yazma denemesi başarısız oluyor. Bu durumda
  # panel "Kritik / bulunamadı" değil, "Uyarı" göstermelidir.
  existing <- tempfile("var-ama-yazilamaz-")
  dir.create(existing, recursive = TRUE)

  # Tüm varyantlarda yazma başarısız gibi davran (izin reddi taklidi).
  old_probe <- .health_write_probe
  assign(".health_write_probe",
         function(...) list(ok = FALSE, error = "izin reddedildi (test)"),
         envir = .GlobalEnv)
  withr::defer(assign(".health_write_probe", old_probe, envir = .GlobalEnv))

  res <- health_check_path_writable("ro.test", "Salt Okunur", existing)
  expect_identical(res$status[1], "warning")
  expect_true(grepl("erişilebilir", res$detail[1], fixed = TRUE))
})

test_that("var olan klasör create_if_missing=FALSE olsa da dir.create ile canlandırılıp ok döner", {
  # UNC klasörleri Windows'ta yol dir.create ile canlandırılmadan yanlış
  # başarısız olabildiği için, var olan bir klasör create_if_missing=FALSE iken
  # de canlandırılıp yazma testi geçmelidir (mergen_uploads/logs ile aynı davranış).
  existing <- tempfile("var-olan-kok-")
  dir.create(existing, recursive = TRUE)
  res <- health_check_path_writable("prime.test", "Canlandırma", existing, create_if_missing = FALSE)
  expect_identical(res$status[1], "ok")
  expect_true(dir.exists(existing))
})

test_that("create_if_missing=FALSE eksik klasörü oluşturup MASKELEMEZ (geri alır)", {
  missing <- file.path(tempdir(), paste0("prime-geri-al-", as.integer(Sys.time()), "-", sample(1e6, 1)))
  if (dir.exists(missing)) unlink(missing, recursive = TRUE, force = TRUE)

  res <- health_check_path_writable("prime.rollback", "Geri Al", missing, create_if_missing = FALSE)

  expect_identical(res$status[1], "critical")
  # Canlandırma için oluşturulmuş olsa bile geri alınmalı; eksik klasör kalmamalı.
  expect_false(dir.exists(missing))
})

test_that("create_if_missing=TRUE eksik klasörü oluşturur ve korur", {
  missing <- file.path(tempdir(), paste0("prime-olustur-", as.integer(Sys.time()), "-", sample(1e6, 1)))
  if (dir.exists(missing)) unlink(missing, recursive = TRUE, force = TRUE)

  res <- health_check_path_writable("prime.create", "Oluştur", missing, create_if_missing = TRUE)

  expect_identical(res$status[1], "ok")
  expect_true(dir.exists(missing))
  unlink(missing, recursive = TRUE, force = TRUE)
})

test_that("gerçekten olmayan klasör yazma başarısızsa kritik kalır", {
  missing <- file.path(tempdir(), paste0("gercekten-yok-", as.integer(Sys.time())))
  if (dir.exists(missing)) unlink(missing, recursive = TRUE, force = TRUE)

  old_probe <- .health_write_probe
  assign(".health_write_probe",
         function(...) list(ok = FALSE, error = "yol yok (test)"),
         envir = .GlobalEnv)
  withr::defer(assign(".health_write_probe", old_probe, envir = .GlobalEnv))

  res <- health_check_path_writable("missing2.test", "Eksik", missing)
  expect_identical(res$status[1], "critical")
})
