# ==============================================================================
# Dosya Yolu: tests/testthat/test-atomic-write-text-behavior.R
# Açıklama: R/utils_atomic_write.R içindeki atomic_write_text fonksiyonunun
#           DAVRANIŞSAL testleri (mevcut testlerde çağrılmıyordu). Atomik UTF-8
#           yazımı Windows VM'de native codepage bozulmasını önlemek için
#           baytları binary yazar; bu test gerçek yaz-oku döngüsünü ve girdi
#           doğrulama/erken-hata yollarını yalnızca yerel geçici dosyalarla
#           (sentetik fixture) doğrular. Ağ/DB/Shiny GEREKMEZ.
#           Not: atomic_write_json jsonlite gerektirdiği için burada kapsanmaz.
# ==============================================================================

.atomicwrite_source_once <- function() {
  if (!exists("%||%", inherits = TRUE)) {
    assign("%||%", function(a, b) if (is.null(a)) b else a, envir = globalenv())
  }
  if (!exists("atomic_write_text",
              envir = globalenv(), mode = "function", inherits = TRUE)) {
    source(
      file.path(resolve_repo_root_for_tests(), "R", "utils_atomic_write.R"),
      encoding = "UTF-8", local = globalenv()
    )
  }
  invisible(TRUE)
}

# UTF-8 dosyayı bayt-güvenli okuyan yardımcı (Windows/locale bağımsız).
.atomicwrite_read_utf8 <- function(path) {
  boyut <- file.info(path)$size[1]
  if (is.na(boyut) || boyut == 0) return("")
  raw_bytes <- readBin(path, what = "raw", n = boyut)
  txt <- rawToChar(raw_bytes)
  Encoding(txt) <- "UTF-8"
  txt
}

# ------------------------------------------------------------------------------
# Girdi doğrulama / erken hata
# ------------------------------------------------------------------------------
testthat::test_that("atomic_write_text geçersiz final_path / content için durur", {
  .atomicwrite_source_once()
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)

  testthat::expect_error(atomic_write_text("x", ""), "final_path")
  testthat::expect_error(atomic_write_text("x", c("a", "b")), "final_path")
  # content karakter olmalı.
  testthat::expect_error(atomic_write_text(123, tmp), "content")
  # NOT: final_path = NA_character_ açık doğrulama tarafından YAKALANMAZ çünkü
  # nzchar(NA) == TRUE'dur; bu durum erken-hata yerine aşağı akışta bir bağlantı
  # hatasına ve yan etkiye yol açar. Yan etkiden kaçınmak için burada test edilmez
  # (bkz. nihai rapor / küçük sınırlama notu).
})

# ------------------------------------------------------------------------------
# UTF-8 yaz-oku döngüsü
# ------------------------------------------------------------------------------
testthat::test_that("atomic_write_text Türkçe çok-satırlı içeriği UTF-8 olarak yazar", {
  .atomicwrite_source_once()
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)

  icerik <- c("Türkçe satır: çğıöşü", "İkinci satır: ÇĞİÖŞÜ")
  donen <- atomic_write_text(icerik, tmp)
  testthat::expect_true(isTRUE(donen))            # invisible(TRUE)
  testthat::expect_true(file.exists(tmp))

  okunan <- .atomicwrite_read_utf8(tmp)
  testthat::expect_identical(okunan, enc2utf8(paste(icerik, collapse = "\n")))
})

testthat::test_that("atomic_write_text tek dizeyi yazar ve overwrite eder", {
  .atomicwrite_source_once()
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)

  atomic_write_text("ilk içerik", tmp)
  testthat::expect_identical(.atomicwrite_read_utf8(tmp), enc2utf8("ilk içerik"))

  # Üzerine yazım.
  atomic_write_text("ikinci içerik", tmp)
  testthat::expect_identical(.atomicwrite_read_utf8(tmp), enc2utf8("ikinci içerik"))
})

# ------------------------------------------------------------------------------
# Eksik üst dizin oluşturma
# ------------------------------------------------------------------------------
testthat::test_that("atomic_write_text eksik üst dizini oluşturur", {
  .atomicwrite_source_once()
  alt_dir <- file.path(tempdir(), "atomicwrite_nested_dir")
  unlink(alt_dir, recursive = TRUE)
  on.exit(unlink(alt_dir, recursive = TRUE), add = TRUE)

  hedef <- file.path(alt_dir, "derin", "dosya.txt")
  atomic_write_text("merhaba", hedef)

  testthat::expect_true(dir.exists(dirname(hedef)))
  testthat::expect_true(file.exists(hedef))
  testthat::expect_identical(.atomicwrite_read_utf8(hedef), "merhaba")
})


# Regresyon: kopya doğrulanamadığında ve geçerli yedek yokken kısmi hedef
# yerinde kalıyordu; atomic_write_json() ile yazılan index bozuk JSON olurdu.
test_that("atomic_write_text yedeksiz basarisizlikta kismi hedefi birakmaz", {
  .atomicwrite_source_once()

  kok <- withr::local_tempdir()
  hedef <- file.path(kok, "index.json")

  # rename başarısız olur, ardından kopya EKSİK bir dosya bırakır.
  testthat::local_mocked_bindings(
    file.rename = function(from, to) FALSE,
    file.copy = function(from, to, ...) {
      writeBin(as.raw(c(0x7b)), to)  # yarım JSON: "{"
      TRUE
    },
    .package = "base"
  )

  # Hata mesajı SABİTLENİR: aksi hâlde erken bir hata (dizin/geçici dosya)
  # da testi geçirir ve kısmi-kopya temizliği hiç çalışmamış olur.
  expect_error(atomic_write_text('{"a":1}', hedef), "hedefe taşıma başarısız")
  expect_false(file.exists(hedef))
})

# Regresyon: mevcut hedefin dogrulanmis yedegi alinamadiginda uzerine YAZILMAZ.
test_that("atomic_write_text yedek alinamayan mevcut hedefi korur", {
  .atomicwrite_source_once()

  kok <- withr::local_tempdir()
  hedef <- file.path(kok, "index.json")
  writeBin(charToRaw('{"eski":true}'), hedef)

  testthat::local_mocked_bindings(
    file.rename = function(from, to) FALSE,
    file.copy = function(from, to, ...) FALSE,
    .package = "base"
  )

  expect_error(atomic_write_text('{"a":1}', hedef), "doğrulanmış yedek")
  expect_true(file.exists(hedef))
  expect_identical(.atomicwrite_read_utf8(hedef), '{"eski":true}')
})
