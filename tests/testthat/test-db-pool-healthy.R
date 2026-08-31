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
# ---------------------------------------------------------------------------
# DIŞ GEÇEN-SÜRE SINIRI: silinmez, KALAN süresi geri yüklenir
# ---------------------------------------------------------------------------

test_that(".db_with_elapsed_budget dis sinirin KALANINI geri yukler", {
  # GERİLEME: çıkış işleyicisi `elapsed = Inf` yazarak DIŞ çağıranın sınırını
  # SİLİYORDU. `db_pool_healthy(timeout_sec = 5)` -> `get_pool_info()` ->
  # `get_connection()` zincirinden sonra sonda sorgusu HİÇBİR geçen-süre
  # sınırı olmadan çalışıyor ve asılı bir sorgu kesilemiyordu.
  env <- new.env(parent = globalenv())
  source(file.path(repo_root_for_tests, "R", "helpers_db_connection.R"),
         encoding = "UTF-8", local = env)

  cagrilar <- list()
  env$setTimeLimit <- function(cpu = Inf, elapsed = Inf, transient = FALSE) {
    cagrilar[[length(cagrilar) + 1L]] <<- elapsed
    invisible(NULL)
  }

  # DIŞ bütçe 30 sn; İÇ bütçe 2 sn. İÇ blok ÖLÇÜLEBİLİR zaman tüketir: hemen
  # dönen bir blokta kalan bütçe ~30 sn olur ve `expect_lte(..., 30)`, çıkışta
  # TAM bütçeyi geri yükleyen (geçen süreyi yok sayan) hatalı bir uygulama için
  # de geçerdi; test yalnızca "Inf geri yüklenmedi"yi kanıtlardı.
  env$.db_with_elapsed_budget(30, function() {
    env$.db_with_elapsed_budget(2, function() {
      Sys.sleep(1.2)
      "ic"
    })
  })

  expect_gte(length(cagrilar), 3L)
  # 1) dış sınır kurulur, 2) iç sınır DARALTIR, 3) çıkışta dışın KALANI geri gelir.
  expect_equal(cagrilar[[1]], 30, tolerance = 0.5)
  expect_equal(cagrilar[[2]], 2, tolerance = 0.5)
  son_ic_cikis <- cagrilar[[3]]
  expect_true(is.finite(son_ic_cikis))
  # KALAN geri yüklenir: TAM bütçe geri yüklenirse bu iddia DÜŞER.
  expect_lt(son_ic_cikis, 29.5)
  expect_gt(son_ic_cikis, 1)
})

test_that("ic butce DIS butceyi GENISLETEMEZ (yalnizca daraltir)", {
  # YALNIZCA 30 -> 2 yonu sinanirsa, ic butcenin KOSULSUZ kazandigi bir
  # gerileme fark edilmezdi: dis 1 sn / ic 30 sn kombinasyonunda hatali
  # uygulama 30 sn kurar ve dis son tarih ASILIRDI.
  env <- new.env(parent = globalenv())
  source(file.path(repo_root_for_tests, "R", "helpers_db_connection.R"),
         encoding = "UTF-8", local = env)

  cagrilar <- list()
  env$setTimeLimit <- function(cpu = Inf, elapsed = Inf, transient = FALSE) {
    cagrilar[[length(cagrilar) + 1L]] <<- elapsed
    invisible(NULL)
  }

  # DIŞ bütçe 1 sn; İÇ bütçe 30 sn.
  env$.db_with_elapsed_budget(1, function() {
    env$.db_with_elapsed_budget(30, function() "ic")
  })

  expect_gte(length(cagrilar), 2L)
  expect_equal(cagrilar[[1]], 1, tolerance = 0.5)
  # İÇ sınır DIŞ kalanı AŞMAZ.
  expect_lte(cagrilar[[2]], 1 + 0.5)
})

test_that("dis sinir yokken cikis Inf'e doner (davranis korunur)", {
  env <- new.env(parent = globalenv())
  source(file.path(repo_root_for_tests, "R", "helpers_db_connection.R"),
         encoding = "UTF-8", local = env)

  cagrilar <- list()
  env$setTimeLimit <- function(cpu = Inf, elapsed = Inf, transient = FALSE) {
    cagrilar[[length(cagrilar) + 1L]] <<- elapsed
    invisible(NULL)
  }

  env$.db_with_elapsed_budget(3, function() "tek")

  expect_equal(cagrilar[[1]], 3, tolerance = 0.5)
  expect_true(is.infinite(cagrilar[[length(cagrilar)]]))
})
