# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-meta-descriptor-name-recovery.R
# Açıklama: Faz 3b metadata üreticisi -- statik tanımlayıcı ad kurtarma
#           regresyon testleri. Tamamen çevrimdışıdır; SQL Server/ODBC
#           gerektirmez.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }
  source(
    file.path(repo_root, "tools", "pk", "helpers_meta_generator_db.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
})

.pk_descriptor_fixture <- function() {
  data.frame(
    column_ordinal = 1:6,
    name = c(NA, NA, NA, NA, "EPPosta", "Telefon"),
    system_type_name = c(
      "nvarchar(50)", "nvarchar(100)", "int", "nvarchar(100)",
      "nvarchar(200)", "nvarchar(50)"
    ),
    max_length = c(100, 200, 4, 200, 400, 100),
    error_number = rep(NA_integer_, 6),
    error_type = rep(NA_integer_, 6),
    error_type_desc = rep(NA_character_, 6),
    error_message = rep(NA_character_, 6),
    stringsAsFactors = FALSE
  )
}

test_that("runtime metadata yalnızca statik tanımlayıcının eksik adlarını tamamlar", {
  descriptor <- .pk_descriptor_fixture()
  # RUNTIME ADLARI STATİK ADLARDAN FARKLI SEÇİLİR.
  #
  # Son iki ad eskiden fixture'daki statik adlarla AYNIYDI; "eksik adı tamamla"
  # ile "HER adı runtime adıyla EZ" davranışları o zaman ayırt EDİLEMİYORDU ve
  # ezen bir regresyon da bu testten geçerdi.
  runtime_names <- c(
    "MasrafYeriKodu", "MasrafYeri", "SicilNo", "KaynakAdi",
    "RuntimeEPosta", "RuntimeTelefon"
  )

  sonuc <- .pkgd_repair_descriptor_names(descriptor, runtime_names)

  # STATİK AD KAZANIR: dolu bir ad runtime adıyla EZİLMEZ.
  expect_identical(
    as.character(sonuc$name),
    c(runtime_names[1:4], "EPPosta", "Telefon")
  )
  # Tip/genişlik kanıtı runtime sonucundan UYDURULMAZ; statik SQL Server
  # tanımlayıcısının değerleri aynen korunur.
  expect_identical(sonuc$system_type_name, descriptor$system_type_name)
  expect_identical(sonuc$max_length, descriptor$max_length)
})

test_that("kolon sayısı uyuşmazsa ad kurtarma fail-closed kalır", {
  descriptor <- .pk_descriptor_fixture()

  expect_error(
    .pkgd_repair_descriptor_names(descriptor, c("A", "B")),
    "AYNI sayida sutun",
    fixed = TRUE
  )
})

test_that("runtime sonucu da adsızsa şema uydurulmaz", {
  descriptor <- .pk_descriptor_fixture()
  runtime_names <- c("", "MasrafYeri", "SicilNo", "KaynakAdi", "EPPosta", "Telefon")

  expect_error(
    .pkgd_repair_descriptor_names(descriptor, runtime_names),
    "runtime sonuc metadata'sinda da ADSIZ",
    fixed = TRUE
  )
})

test_that("tam statik şema runtime adlarına dokunmadan korunur", {
  descriptor <- .pk_descriptor_fixture()
  descriptor$name <- c("A", "B", "C", "D", "E", "F")

  expect_identical(
    .pkgd_repair_descriptor_names(descriptor, character(0)),
    descriptor
  )
})

test_that("SQL Server tanımlayıcı hata alanları kaybedilmez", {
  descriptor <- .pk_descriptor_fixture()
  descriptor$error_number[1] <- 11526L
  descriptor$error_type_desc[1] <- "DYNAMIC_SQL"
  descriptor$error_message[1] <- "The metadata could not be determined."

  ayrinti <- .pkgd_descriptor_error_detail(descriptor)

  expect_match(ayrinti, "hata_no=11526", fixed = TRUE)
  expect_match(ayrinti, "DYNAMIC_SQL", fixed = TRUE)
  expect_match(ayrinti, "metadata could not be determined", fixed = TRUE)
})
