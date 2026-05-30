# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-authorization-failclosed.R
# Açıklama: check_user_authorization() güvenlik davranışının DAVRANIŞSAL testleri.
#           Bu fonksiyon SSO ile giren kullanıcının uygulamaya erişim hakkını
#           DC01_user_base tablosundan doğrular ve güvenlik-kritik bir sınırdır.
#           Gerçek üretim kodu çağrılır; DB bağımlılıkları (get_connection,
#           dbGetQuery, ...) global stub'larla taklit edilir. Gerçek DB/LLM/
#           tarayıcı GEREKMEZ.
#
#           Özellikle YENİ fail-closed davranışı doğrulanır: DB hatası durumunda
#           yetki AÇILMAMALIDIR (önceki davranış "USER" veriyordu = fail-open).
# ==============================================================================

.authz_source_once <- function() {
  if (exists("check_user_authorization", envir = globalenv(),
             mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  source(
    file.path(resolve_repo_root_for_tests(), "R", "helpers_sso.R"),
    encoding = "UTF-8",
    local = globalenv()
  )
  invisible(TRUE)
}

# Belirtilen global isimleri geçici olarak stub'larla değiştirir, kod bloğunu
# çalıştırır ve sonra orijinalleri geri yükler (save/restore).
.authz_with_stubs <- function(stubs, code) {
  nm <- names(stubs)
  had <- vapply(nm, exists, logical(1), envir = globalenv(), inherits = FALSE)
  old <- stats::setNames(
    lapply(nm, function(n) {
      if (exists(n, envir = globalenv(), inherits = FALSE)) get(n, envir = globalenv()) else NULL
    }),
    nm
  )
  for (n in nm) assign(n, stubs[[n]], envir = globalenv())
  on.exit({
    for (n in nm) {
      if (isTRUE(had[[n]])) {
        assign(n, old[[n]], envir = globalenv())
      } else if (exists(n, envir = globalenv(), inherits = FALSE)) {
        rm(list = n, envir = globalenv())
      }
    }
  }, add = TRUE)
  force(code)
}

testthat::test_that("check_user_authorization boş/NULL kullanıcıda yetki vermez", {
  .authz_source_once()
  testthat::expect_false(isTRUE(check_user_authorization(NULL)$authorized))
  testthat::expect_false(isTRUE(check_user_authorization("")$authorized))
})

testthat::test_that("check_user_authorization DB hatasında fail-closed davranır (yetki vermez)", {
  .authz_source_once()

  .authz_with_stubs(
    list(get_connection = function() stop("DB erişilemiyor")),
    {
      res <- check_user_authorization("gercek_kullanici", sicil = "12345")
      # YENİ güvenli davranış: hata durumunda yetkilendirme REDDEDİLİR.
      testthat::expect_false(isTRUE(res$authorized))
      testthat::expect_null(res$yetki)
    }
  )
})

testthat::test_that("check_user_authorization kullanıcı bulunduğunda yetki döndürür", {
  .authz_source_once()

  .authz_with_stubs(
    list(
      get_connection = function() list(conn = "fake-conn"),
      release_connection = function(info) invisible(NULL),
      dbGetQuery = function(conn, query, params = NULL) {
        data.frame(
          KaynakAdi      = "Mehmet Karadağ",
          Yetki          = "ADMIN",
          MasrafYeriKodu = "MK01",
          KullaniciAdi   = "mkaradag",
          stringsAsFactors = FALSE
        )
      },
      normalize_db_visible_value   = function(x, ...) x,
      normalize_db_technical_value = function(x, ...) x
    ),
    {
      res <- check_user_authorization("mkaradag")
      testthat::expect_true(isTRUE(res$authorized))
      testthat::expect_identical(res$yetki, "ADMIN")
      testthat::expect_identical(res$kaynak_adi, "Mehmet Karadağ")
    }
  )
})

testthat::test_that("check_user_authorization kullanıcı bulunamazsa yetki vermez", {
  .authz_source_once()

  .authz_with_stubs(
    list(
      get_connection = function() list(conn = "fake-conn"),
      release_connection = function(info) invisible(NULL),
      dbGetQuery = function(conn, query, params = NULL) {
        data.frame(
          KaynakAdi = character(0), Yetki = character(0),
          MasrafYeriKodu = character(0), KullaniciAdi = character(0),
          stringsAsFactors = FALSE
        )
      },
      normalize_db_visible_value   = function(x, ...) x,
      normalize_db_technical_value = function(x, ...) x
    ),
    {
      res <- check_user_authorization("olmayan_kullanici")
      testthat::expect_false(isTRUE(res$authorized))
    }
  )
})

testthat::test_that("check_user_authorization KullaniciAdi bulunamazsa sicil ile dener", {
  .authz_source_once()

  call_state <- new.env(parent = emptyenv())
  call_state$n <- 0L

  .authz_with_stubs(
    list(
      get_connection = function() list(conn = "fake-conn"),
      release_connection = function(info) invisible(NULL),
      dbGetQuery = function(conn, query, params = NULL) {
        call_state$n <- call_state$n + 1L
        if (call_state$n == 1L) {
          # İlk sorgu (KullaniciAdi) boş döner.
          data.frame(KaynakAdi = character(0), Yetki = character(0),
                     MasrafYeriKodu = character(0), KullaniciAdi = character(0),
                     stringsAsFactors = FALSE)
        } else {
          # İkinci sorgu (sicil) eşleşir.
          data.frame(KaynakAdi = "Sicil Kullanıcı", Yetki = "USER",
                     MasrafYeriKodu = "SK99", KullaniciAdi = "12345",
                     stringsAsFactors = FALSE)
        }
      },
      normalize_db_visible_value   = function(x, ...) x,
      normalize_db_technical_value = function(x, ...) x
    ),
    {
      res <- check_user_authorization("eslesmeyen_ad", sicil = "12345")
      testthat::expect_true(isTRUE(res$authorized))
      testthat::expect_identical(res$yetki, "USER")
      testthat::expect_identical(call_state$n, 2L)
    }
  )
})
