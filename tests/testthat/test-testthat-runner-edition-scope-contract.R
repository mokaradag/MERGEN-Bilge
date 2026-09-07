# ==============================================================================
# Dosya Yolu: tests/testthat/test-testthat-runner-edition-scope-contract.R
# Açıklama: Test koşucuları (`tests/testthat.R`, izole çocuk koşucu üreticileri
#           ve ai_repo_check odaklı koşum) `testthat::local_edition()` çağrısını
#           ÜST DÜZEYDE yapmamalıdır. Küresel ortamdaki çağrı testthat/rlang'ın
#           küresel ertelenmiş işleyicisini kaydeder; Rscript çıkışında bu
#           işleyici `deferred_run(env)` çağırır ve "deferred_run fonksiyonu
#           bulunamadı" hatasıyla biter (Windows vm-evidence tam paket koşumunda
#           görüldü; Linux'ta test başarısı/başarısızlığından BAĞIMSIZ olarak
#           birebir yeniden üretildi). Çağrı zaten etkisizdi: test_file() ve
#           test_dir() sürümü DESCRIPTION/TESTTHAT_EDITION üzerinden kendisi
#           çözer (bu depoda 2. sürüm).
# ==============================================================================

# Parse tabanlı tarama: yorumlar düşürülür. `local_edition()` YALNIZCA küresel
# ortamda çalışan ifadelerde aranır; yürüyüş `function` sınırında durduğu için
# bir yardımcı fonksiyonun gövdesindeki çağrı bulgu üretmez. Denetim akışı
# (`{`, `(`, `if`, `for`, `while`, `repeat`) da küresel ortamda çalıştığı için
# içine girilir; aksi hâlde `if (TRUE) testthat::local_edition(2)` kaçıyordu.
# Çocuk betik satırlarına yazılan dize sabitleri ayrı ve özyinelemeli taranır.
# `try`/`tryCatch`/`suppressWarnings` gibi sarmalayıcılar da ARGÜMANLARINI
# küresel ortamda çalıştırır; listede olmasalar yürüyüş orada duruyor ve
# `try(testthat::local_edition(2), silent = TRUE)` kaçıyordu.
# Atama biçimleri (`<-`, `<<-`, `=`) de sağ tarafı küresel ortamda çalıştırır;
# listede olmadıkları için `edition <- testthat::local_edition(2)` kaçıyordu.
.RUNNER_EDITION_AKIS <- c(
  "{", "(", "if", "for", "while", "repeat",
  "<-", "<<-", "=",
  "try", "tryCatch", "suppressWarnings", "suppressMessages", "withCallingHandlers"
)

.runner_edition_ust_duzey_cagri <- function(ifade) {
  if (!is.call(ifade)) return(FALSE)
  ad <- paste(deparse(ifade[[1]]), collapse = "")
  if (ad %in% c("local_edition", "testthat::local_edition")) return(TRUE)
  if (!(ad %in% .RUNNER_EDITION_AKIS)) return(FALSE)
  if (length(ifade) < 2L) return(FALSE)
  for (idx in seq.int(2L, length(ifade))) {
    # Boş argüman (ör. `for` başlığı) boş sembol olarak gelir; CLAUDE.md AST
    # kuralı gereği doğrudan indeksleyip quote(expr = ) ile karşılaştırılır.
    if (identical(ifade[[idx]], quote(expr = ))) next
    if (isTRUE(.runner_edition_ust_duzey_cagri(ifade[[idx]]))) return(TRUE)
  }
  FALSE
}

.runner_edition_dize_bulgusu <- function(x) {
  bulundu <- FALSE
  gez <- function(dugum) {
    if (isTRUE(bulundu)) return(invisible(NULL))
    if (is.character(dugum)) {
      # `testthat::local_edition (2)` geçerli R'dir; boşluklu biçim de yakalanır.
      if (any(grepl("local_edition\\s*\\(", dugum, perl = TRUE))) bulundu <<- TRUE
      return(invisible(NULL))
    }
    # Boş argüman (ör. `df[i, ]`) boş sembol olarak gelir. Boş sembolü bir YEREL
    # DEĞİŞKENE bağlamak forcing sırasında hata fırlatır; `missing()` de yerel
    # bağlama üzerinde güvenilir değildir (CLAUDE.md AST yürüyücü kuralı). Bu
    # yüzden doğrudan indeksleyip quote(expr = ) ile karşılaştırırız.
    if (is.call(dugum) || is.expression(dugum) || is.list(dugum)) {
      basla <- if (is.call(dugum)) 2L else 1L
      if (length(dugum) >= basla) {
        for (idx in seq.int(basla, length(dugum))) {
          if (identical(dugum[[idx]], quote(expr = ))) next
          gez(dugum[[idx]])
        }
      }
    }
    invisible(NULL)
  }
  gez(x)
  bulundu
}

.runner_edition_bulgulari <- function(path) {
  ifadeler <- parse(path, keep.source = FALSE, encoding = "UTF-8")
  bulgular <- character(0)
  for (idx in seq_along(ifadeler)) {
    ifade <- ifadeler[[idx]]
    if (.runner_edition_ust_duzey_cagri(ifade)) {
      bulgular <- c(bulgular, paste("çağrı:", paste(deparse(ifade[[1]]), collapse = "")))
    }
    if (.runner_edition_dize_bulgusu(ifade)) {
      bulgular <- c(bulgular, "dize sabiti: local_edition(")
    }
  }
  unique(bulgular)
}

# Dedektör regresyonu: küresel ortamda çalışan denetim akışı içindeki çağrı da
# testthat/rlang ertelenmiş işleyicisini kaydeder ve bulgu üretmelidir.
test_that("dedektör denetim akışı içindeki üst düzey local_edition() çağrısını yakalar", {
  yol <- withr::local_tempfile(fileext = ".R")
  writeLines(c(
    "if (TRUE) testthat::local_edition(2)"
  ), yol, useBytes = TRUE)
  expect_gt(length(.runner_edition_bulgulari(yol)), 0L)

  yol2 <- withr::local_tempfile(fileext = ".R")
  writeLines(c(
    "{",
    "  local_edition(3)",
    "}"
  ), yol2, useBytes = TRUE)
  expect_gt(length(.runner_edition_bulgulari(yol2)), 0L)

  # Fonksiyon gövdesindeki çağrı bulgu ÜRETMEZ (küresel kayıt yoktur).
  yol3 <- withr::local_tempfile(fileext = ".R")
  writeLines(c(
    "f <- function() {",
    "  testthat::local_edition(2)",
    "}"
  ), yol3, useBytes = TRUE)
  expect_identical(.runner_edition_bulgulari(yol3), character(0))
})

# Üst düzey ATAMA sağ tarafı da küresel ortamda çalışır ve ertelenmiş işleyiciyi
# kaydeder; üç atama biçimi de bulgu üretmelidir.
test_that("dedektör üst düzey atama sağ tarafındaki local_edition() çağrısını yakalar", {
  for (atama in c("edition <- testthat::local_edition(2)",
                  "edition <<- testthat::local_edition(2)",
                  "edition = testthat::local_edition(2)")) {
    yol <- withr::local_tempfile(fileext = ".R")
    writeLines(atama, yol, useBytes = TRUE)
    expect_gt(length(.runner_edition_bulgulari(yol)), 0L, label = atama)
  }
})

# Boşluklu çağrı biçimi (`local_edition (2)`) da geçerli R'dir; çocuk betik
# dizelerinde bu biçim de bulgu üretmelidir.
test_that("dedektör çocuk betik dizesinde boşluklu local_edition çağrısını yakalar", {
  yol <- withr::local_tempfile(fileext = ".R")
  writeLines(c(
    "kosucu <- c(",
    "  \"testthat::local_edition (2)\"",
    ")"
  ), yol, useBytes = TRUE)
  expect_gt(length(.runner_edition_bulgulari(yol)), 0L)
})

test_that("test koşucuları local_edition() çağrısını üst düzeyde yapmaz", {
  repo_root <- resolve_repo_root_for_tests()
  dosyalar <- c(
    "tests/testthat.R",
    "tests/scripts/run_full_testthat_isolated.R",
    "tools/run_full_testthat_isolated.R",
    "tests/scripts/ai_repo_check.R"
  )
  for (dosya in dosyalar) {
    yol <- file.path(repo_root, dosya)
    expect_true(file.exists(yol), info = dosya)
    bulgular <- .runner_edition_bulgulari(yol)
    expect_identical(bulgular, character(0), info = dosya)
  }
})

# Sürümün ÇALIŞTIĞI kanıtlanmalıdır: depoda DESCRIPTION / Config/testthat/edition
# yok, bu yüzden bildirim olmadan `find_edition()` sessizce 2. sürüme düşer ve CI
# hangi sürümü koştuğunu bilmeden yeşile döner.
test_that("koşucular testthat sürümünü açıkça bildirir", {
  repo_root <- resolve_repo_root_for_tests()
  for (dosya in c(
    "tests/testthat.R",
    "tests/scripts/run_full_testthat_isolated.R",
    "tools/run_full_testthat_isolated.R",
    "tests/scripts/ai_repo_check.R"
  )) {
    yol <- file.path(repo_root, dosya)
    expect_true(file.exists(yol), info = dosya)
    metin <- paste(readLines(yol, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    expect_true(
      grepl("TESTTHAT_EDITION", metin, fixed = TRUE),
      info = paste0(dosya, " testthat sürümünü TESTTHAT_EDITION ile bildirmelidir.")
    )
  }
})

test_that("tests/testthat.R sürüm bildirimini test_dir çağrısına sınırlar", {
  repo_root <- resolve_repo_root_for_tests()
  metin <- paste(
    readLines(file.path(repo_root, "tests", "testthat.R"), warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )

  # Bildirim geri alınabilir olmalıdır: koşum sonrası süreç ortamı kirlenmemeli.
  expect_true(grepl("Sys.setenv(TESTTHAT_EDITION", metin, fixed = TRUE))
  expect_true(grepl("Sys.unsetenv(\"TESTTHAT_EDITION\")", metin, fixed = TRUE))
  expect_true(grepl("on.exit(", metin, fixed = TRUE))
})

test_that("çocuk koşucu şablonu test_file() ile çalışır ve çıkışta deferred_run hatası üretmez", {
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  skip_if(!file.exists(rscript), "Rscript ikilisi bulunamadı")

  dizin <- withr::local_tempdir()
  # Yol KESME İŞARETİ içerir: güvensiz tek tırnak enterpolasyonu bu girdide
  # geçersiz R sözdizimi üretir (Windows kullanıcı klasörü adı kesme işareti
  # taşıyabilir).
  apostrof_dizin <- file.path(dizin, "O'Brien")
  dir.create(apostrof_dizin, recursive = TRUE, showWarnings = FALSE)
  skip_if_not(dir.exists(apostrof_dizin), "Kesme işaretli dizin oluşturulamadı")
  test_dosyasi <- file.path(apostrof_dizin, "test-gecer.R")
  writeLines("test_that('gecer', { expect_true(TRUE) })", test_dosyasi)

  # tests/scripts/run_full_testthat_isolated.R çocuk şablonuyla aynı şekil.
  kosucu <- file.path(dizin, "runner.R")
  writeLines(c(
    "Sys.setenv(MERGEN_RUN_APP = 'false', MERGEN_DISABLE_FUTURES = 'true', TZ = 'UTC')",
    "options(warn = 1)",
    "library(testthat)",
    # Yol R DİZE SABİTİ olarak serileştirilir: tek tırnak içeren bir yol
    # (kesme işareti içeren kullanıcı klasörü) geçersiz R sözdizimi üretiyordu.
    sprintf("res <- testthat::test_file(%s, reporter = 'summary', stop_on_failure = TRUE, stop_on_warning = TRUE)",
            deparse(gsub("\\", "/", test_dosyasi, fixed = TRUE))),
    "invisible(res)"
  ), kosucu)

  cikti <- suppressWarnings(system2(rscript, c("--vanilla", shQuote(kosucu)),
                                    stdout = TRUE, stderr = TRUE))
  durum <- attr(cikti, "status")
  expect_true(is.null(durum) || identical(as.integer(durum), 0L),
              info = paste(cikti, collapse = "\n"))
  expect_false(any(grepl("deferred_run", cikti, fixed = TRUE)),
               info = paste(cikti, collapse = "\n"))
})
