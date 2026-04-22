# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-pool-healthy.R
# Açıklama: db_pool_healthy() fonksiyonunun get_pool_info() dönüşlerine göre
# TRUE/FALSE davranışını ve zamanaşımı kısa kesme yolunu doğrulayan birim
# testleri. Gerçek ODBC bağlantısı kurulmaz; get_pool_info() fonksiyonu test
# kapsamında stub'lanır.
# ==============================================================================

local({
  # helpers_database.R helper_bootstrap.R tarafından zaten source ediliyor.
  # db_pool_healthy fonksiyonu bu dosyada bulunmalıdır.
  if (!exists("db_pool_healthy", envir = globalenv(), inherits = FALSE)) {
    source(
      file.path(repo_root_for_tests, "R", "helpers_database.R"),
      encoding = "UTF-8",
      local = globalenv()
    )
  }
})

# get_pool_info'yu geçici olarak stub'la; on.exit ile orijinali geri yükler.
.with_pool_info_stub <- function(stub_fn, code) {
  eski <- get("get_pool_info", envir = globalenv(), inherits = FALSE)
  assign("get_pool_info", stub_fn, envir = globalenv())
  on.exit(assign("get_pool_info", eski, envir = globalenv()), add = TRUE)
  code()
}

test_that("db_pool_healthy valid=TRUE döndüğünde TRUE olur", {
  .with_pool_info_stub(
    function() list(valid = TRUE, mode = "Doğrudan", note = "ok"),
    function() {
      expect_true(db_pool_healthy(timeout_sec = 5))
    }
  )
})

test_that("db_pool_healthy valid=FALSE döndüğünde FALSE olur", {
  .with_pool_info_stub(
    function() list(valid = FALSE, error = "ODBC error"),
    function() {
      expect_false(db_pool_healthy(timeout_sec = 5))
    }
  )
})

test_that("db_pool_healthy get_pool_info hata fırlatırsa FALSE döner", {
  .with_pool_info_stub(
    function() stop("pool yok"),
    function() {
      expect_false(db_pool_healthy(timeout_sec = 5))
    }
  )
})

test_that("db_pool_healthy zamanaşımını aşan çağrıda FALSE döner", {
  # Stub zamanaşımından daha uzun uyur. setTimeLimit Sys.sleep'i her zaman
  # kesemediği için db_pool_healthy wall-clock post-check'i FALSE'a düşürür.
  yavas_stub <- function() {
    Sys.sleep(2)
    list(valid = TRUE)
  }

  .with_pool_info_stub(
    yavas_stub,
    function() {
      basla <- Sys.time()
      sonuc <- db_pool_healthy(timeout_sec = 1)
      sure <- as.numeric(difftime(Sys.time(), basla, units = "secs"))

      expect_false(sonuc)
      expect_true(sure >= 1)
    }
  )
})

test_that("db_pool_healthy varsayılan timeout_sec = 5 ile çağrılabilir", {
  .with_pool_info_stub(
    function() list(valid = TRUE),
    function() {
      # timeout_sec argümanı verilmeden çağrılırsa hata oluşmamalı.
      expect_true(db_pool_healthy())
    }
  )
})