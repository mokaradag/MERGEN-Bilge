# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-phase-status-contract.R
# Açıklama: tools/pk_phase_status.sh operasyonel betiği sözleşme testleri.
#           Tamamen çevrimdışı ve belirlenimcidir: ağ, uzak depo veya gizli
#           değer GEREKMEZ. Betik SALT OKUNURDUR ve burada ÇALIŞTIRILMAZ;
#           yalnızca metni ve kabuk sözdizimi denetlenir.
#
# Kapsanan sözleşmeler:
#   - Dosya BAYT DÜZEYİNDE ASCII'dir (Windows/Türkçe yerelde mojibake riski).
#   - Seçenek biçimli `<ref>` argümanı REDDEDİLİR.
#   - Sig (shallow) klon ve bayat uzak referans KAPALI BAŞARISIZ olur.
#   - Tarama BİRİNCİ EBEVEYN gecmisiyle sınırlıdır.
#   - Yokluk KANIT SAYILMAZ; kapanış notu bunu açıkça söyler.
# ==============================================================================

.pk_phase_script_path <- function() {
  file.path(resolve_repo_root_for_tests(), "tools", "pk_phase_status.sh")
}

.pk_phase_script_text <- function() {
  yol <- .pk_phase_script_path()
  ham <- readBin(yol, "raw", file.info(yol)$size)
  rawToChar(ham)
}

# Windows CI çalıştırıcılarında C:/Windows/System32/bash.exe (WSL başlatıcısı)
# PATH üzerinde Git for Windows'un gerçek POSIX kabuğunun önüne geçebilir.
# Dağıtım kurulu değilse bu ikili sessizce hata verir; System32 eşleşmesi
# reddedilir ve Git'in kendi bash'i açıkça aranır.
.pk_phase_locate_bash <- function() {
  aday <- Sys.which("bash")
  aday <- if (length(aday)) unname(aday)[1] else ""

  system32_mi <- FALSE
  if (nzchar(aday)) {
    aday_norm <- tolower(normalizePath(aday, winslash = "/", mustWork = FALSE))
    system32_mi <- grepl("/system32/", aday_norm, fixed = TRUE)
  }
  if (nzchar(aday) && !system32_mi) return(aday)

  git_adaylari <- c(
    file.path(Sys.getenv("ProgramFiles"), "Git", "bin", "bash.exe"),
    file.path(Sys.getenv("ProgramFiles"), "Git", "usr", "bin", "bash.exe"),
    file.path(Sys.getenv("ProgramFiles(x86)"), "Git", "bin", "bash.exe")
  )
  for (y in git_adaylari) {
    if (nzchar(y) && file.exists(y)) return(y)
  }

  ""
}

test_that("betik BAYT DÜZEYİNDE ASCII'dir", {
  yol <- .pk_phase_script_path()
  expect_true(file.exists(yol))

  ham <- readBin(yol, "raw", file.info(yol)$size)
  ascii_disi <- which(as.integer(ham) > 127L)

  # Dosya başlığı ASCII-only olduğunu İDDİA EDER; iddia denetlenmezse bir
  # uzun tire veya paragraf işareti sessizce geri gelir ve UTF-8 olmayan bir
  # VM konsolunda mojibake üretir.
  expect_equal(
    length(ascii_disi), 0L,
    info = sprintf("ASCII disi bayt konumlari: %s",
                   paste(utils::head(ascii_disi, 10L), collapse = ", "))
  )
})

test_that("kabuk sözdizimi geçerlidir", {
  bash_bin <- .pk_phase_locate_bash()
  testthat::skip_if_not(nzchar(bash_bin))

  sonuc <- suppressWarnings(system2(
    bash_bin, c("-n", shQuote(.pk_phase_script_path())),
    stdout = TRUE, stderr = TRUE
  ))
  durum <- attr(sonuc, "status")

  expect_true(is.null(durum) || identical(durum, 0L),
              info = paste(sonuc, collapse = "\n"))
})

test_that("seçenek biçimli ref argümanı REDDEDİLİR", {
  bash_bin <- .pk_phase_locate_bash()
  testthat::skip_if_not(nzchar(bash_bin))

  # `--all` gecirmek `git log ... --all` etkisi yaratir ve YALNIZCA ozellik
  # dalinda kalan birlesmeler entegre olmus gibi raporlanir.
  sonuc <- suppressWarnings(system2(
    bash_bin, c(shQuote(.pk_phase_script_path()), "--all"),
    stdout = TRUE, stderr = TRUE
  ))
  durum <- attr(sonuc, "status")

  expect_true(!is.null(durum) && durum != 0L)
  expect_true(any(grepl("secenek olamaz", sonuc, fixed = TRUE)))
})

test_that("kapalı başarısızlık ve doğruluk sınırı metinde AÇIKÇA vardır", {
  metin <- .pk_phase_script_text()

  zorunlu <- c(
    # Bayat uzak referans / sig klon / bozuk gecmis kapali basarisiz olur.
    "is-shallow-repository",
    "git ls-remote",
    "PK_PHASE_SKIP_REMOTE_CHECK",
    # Tarama birinci ebeveyn gecmisiyle sinirlidir (ozellik dali icindeki
    # birlesmeler entegrasyon sayilmaz).
    "--first-parent",
    # Squash birlesme ve geri alma (revert) taninir.
    "squash",
    "Revert",
    # PK ad alani dogrulamasi: `ui/phase-2-redesign` gibi ilgisiz dallar
    # faz sayilmaz.
    "claude/pk-phase-",
    # Yokluk KANIT DEGILDIR.
    "SONUCU CIKARILAMAZ"
  )

  for (token in zorunlu) {
    expect_true(grepl(token, metin, fixed = TRUE, useBytes = TRUE),
                info = sprintf("Betikte beklenen sozlesme izi yok: %s", token))
  }
})

test_that("faz numarası İLK işaretten okunur (açgözlü kalıp yok)", {
  metin <- .pk_phase_script_text()

  # `claude/pk-phase-4-fix-phase-5-prep` dali Faz 4'tur. Acgozlu `.*phase-`
  # kalibi son isareti alir ve Faz 5'i yanlislikla entegre gosterir.
  expect_true(grepl('${dal#*phase-}', metin, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl('s/.*phase-\\(', metin, fixed = TRUE, useBytes = TRUE))
})
