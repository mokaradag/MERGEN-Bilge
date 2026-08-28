# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-phase-status-contract.R
# Açıklama: tools/pk_phase_status.sh operasyonel betiği sözleşme testleri.
#           Tamamen çevrimdışı ve belirlenimcidir: ağ, uzak depo veya gizli
#           değer GEREKMEZ. Betik SALT OKUNURDUR; metni ve kabuk sözdizimi
#           denetlenir, AYRICA GEÇERSİZ seçeneklerle çağrılıp reddi doğrulanır
#           (bu çağrılar git/ağ işine hiç ulaşmadan erken çıkar).
#
# Kapsanan sözleşmeler:
#   - Dosya WINDOWS-1254'e ÇEVRİLEBİLİR ve GEÇERLİ UTF-8'dir (Windows/Türkçe
#     yerelde mojibake riski); ASCII-ONLY kuralı BİLEREK KALDIRILDI, çünkü
#     Türkçeyi Latinleştirmeye zorluyordu (CLAUDE.md kural 1).
#   - Seçenek biçimli `<ref>` argümanı REDDEDİLİR.
#   - Sig (shallow) klon ve bayat uzak referans KAPALI BAŞARISIZ olur.
#   - Tarama BİRİNCİ EBEVEYN geçmişiyle sınırlıdır.
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

test_that("betik WINDOWS-1254'e ÇEVRİLEBİLİR", {
  yol <- .pk_phase_script_path()
  expect_true(file.exists(yol))

  # ASCII-ONLY DENETİMİ TÜRKÇEYİ LATİNLEŞTİRMEYE ZORLUYORDU (CLAUDE.md kural 1
  # ile çelişir). Gerçek sınır CP1254 TEMSİL EDİLEBİLİRLİĞİDİR: Türkçe harfler
  # CP1254'te vardır ve Türkçe Windows konsolunda doğru görünür; uzun tire /
  # paragraf işareti / emoji gibi KARŞILIĞI OLMAYAN karakterler mojibake üretir.
  satirlar <- readLines(yol, encoding = "UTF-8", warn = FALSE)
  cevrilen <- suppressWarnings(iconv(satirlar, from = "UTF-8", to = "WINDOWS-1254"))
  bozuk <- which(is.na(cevrilen))

  expect_equal(
    length(bozuk), 0L,
    info = sprintf("WINDOWS-1254'e çevrilemeyen satırlar: %s",
                   paste(utils::head(bozuk, 10L), collapse = ", "))
  )

  # Dosya UTF-8 olarak GEÇERLİ kalmalıdır (bozuk bayt dizisi girmemeli).
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- suppressWarnings(iconv(list(ham), from = "UTF-8", to = "UTF-8"))[[1]]
  expect_false(is.na(metin), info = "Betik geçerli UTF-8 değil.")
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

  # `--all` geçirmek `git log ... --all` etkisi yaratır ve YALNIZCA özellik
  # dalında kalan birleşmeler entegre olmuş gibi raporlanır.
  sonuc <- suppressWarnings(system2(
    bash_bin, c(shQuote(.pk_phase_script_path()), "--all"),
    stdout = TRUE, stderr = TRUE
  ))
  durum <- attr(sonuc, "status")

  expect_true(!is.null(durum) && durum != 0L)

  # YAKALANAN ÇIKTI YEREL KODLAMADADIR (Türkçe Windows konsolunda CP1254),
  # R literali ise UTF-8'dir; `fixed = TRUE` karşılaştırması farklı bayt
  # dizilerini kıyaslar ve betik seçeneği DOĞRU reddetse bile test düşerdi.
  # Bu dosyanın geri kalanı gibi burada da metin açıkça çevrilir ve ek olarak
  # ASCII bir çapa aranır.
  cevrili <- suppressWarnings(iconv(sonuc, from = "", to = "UTF-8"))
  cevrili[is.na(cevrili)] <- ""
  expect_true(any(grepl("HATA:", sonuc, fixed = TRUE, useBytes = TRUE)))

  # ZORUNLU EŞLEŞME ASCII'DİR.
  #
  # Türkçe Windows konsolu OEM kod sayfası 857 baytları yazar; `iconv(from = "")`
  # ise ANSI 1254'ten çevirir. `ç` baytı o zaman BAŞKA bir karaktere dönüşür ve
  # Türkçe eşleşmelerin HİÇBİRİ tutmaz -- betik `--all` seçeneğini DOĞRU
  # reddettiği hâlde test düşerdi. Türkçe biçim ek KANIT olarak kabul edilir.
  expect_true(
    any(grepl("olamaz", cevrili, fixed = TRUE)) ||
      any(grepl("olamaz", sonuc, fixed = TRUE, useBytes = TRUE)) ||
      any(grepl("<ref>", sonuc, fixed = TRUE, useBytes = TRUE))
  )
})

test_that("kapalı başarısızlık ve doğruluk sınırı metinde AÇIKÇA vardır", {
  metin <- .pk_phase_script_text()

  zorunlu <- c(
    # Bayat uzak referans / sığ klon / bozuk geçmiş kapalı başarısız olur.
    "is-shallow-repository",
    "git ls-remote",
    "PK_PHASE_SKIP_REMOTE_CHECK",
    # Tarama birinci ebeveyn geçmişiyle sınırlıdır (özellik dalı içindeki
    # birleşmeler entegrasyon sayılmaz).
    "--first-parent",
    # Squash birleşme ve geri alma (revert) tanınır.
    "squash",
    "Revert",
    # PK ad alanı doğrulaması: `ui/phase-2-redesign` gibi ilgisiz dallar
    # faz sayılmaz.
    "claude/pk-phase-",
    # Yokluk KANIT DEĞİLDİR.
    "SONUCU CIKARILAMAZ"
  )

  for (token in zorunlu) {
    expect_true(grepl(token, metin, fixed = TRUE, useBytes = TRUE),
                info = sprintf("Betikte beklenen sözleşme izi yok: %s", token))
  }
})

test_that("faz numarası İLK işaretten okunur (açgözlü kalıp yok)", {
  metin <- .pk_phase_script_text()

  # `claude/pk-phase-4-fix-phase-5-prep` dalı Faz 4'tür. Açgözlü `.*phase-`
  # kalıbı son işareti alır ve Faz 5'i yanlışlıkla entegre gösterir.
  expect_true(grepl('${dal#*phase-}', metin, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl('s/.*phase-\\(', metin, fixed = TRUE, useBytes = TRUE))

  # AYNI KURAL SQUASH KONUSUNDAKI `Faz ` ISARETI ICIN DE GECERLIDIR.
  # `Faz 4 duzeltme, Faz 5 hazirligi (#123)` konusu acgozlu kalipla Faz 5
  # okunuyor, BIRLESMEMIS bir faz entegre gibi raporlaniyordu.
  expect_true(grepl('${subject#*[Ff]az }', metin, fixed = TRUE, useBytes = TRUE))
  expect_false(grepl('s/.*[Ff]az \\(', metin, fixed = TRUE, useBytes = TRUE))
})
