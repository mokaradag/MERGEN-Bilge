# ==============================================================================
# Dosya Yolu: tests/testthat/test-jwt-decode-behavior.R
# Açıklama: decode_jwt_payload() davranışsal testleri. Geçersiz/eksik token
#           reddini ve geçerli base64url JWT payload'ının JSON claim'lerine
#           çözümlenmesini doğrular. Bu güvenlik-duyarlı bir ayrıştırma
#           sınırıdır. DB/LLM/tarayıcı gerekmez; sentetik token kullanılır.
# ==============================================================================

.jwt_decode_source_once <- function() {
  if (exists("decode_jwt_payload", envir = globalenv(),
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

testthat::test_that("decode_jwt_payload geçersiz/eksik token'ı reddeder", {
  .jwt_decode_source_once()

  testthat::expect_null(decode_jwt_payload(NULL))
  testthat::expect_null(decode_jwt_payload(""))
  # Üç parçalı olmayan token reddedilmeli.
  testthat::expect_null(decode_jwt_payload("yalnizca.iki"))
  testthat::expect_null(decode_jwt_payload("a.b.c.d"))
})

testthat::test_that("decode_jwt_payload geçerli token'ın payload claim'lerini çözer", {
  .jwt_decode_source_once()
  testthat::skip_if_not_installed("base64enc")
  testthat::skip_if_not_installed("jsonlite")

  # debug_mode kontrolü için SSO_CONFIG gereklidir; geçici olarak atanır.
  had_cfg <- exists("SSO_CONFIG", envir = globalenv(), inherits = FALSE)
  old_cfg <- if (had_cfg) get("SSO_CONFIG", envir = globalenv()) else NULL
  assign("SSO_CONFIG", list(debug_mode = FALSE), envir = globalenv())
  on.exit({
    if (had_cfg) {
      assign("SSO_CONFIG", old_cfg, envir = globalenv())
    } else if (exists("SSO_CONFIG", envir = globalenv(), inherits = FALSE)) {
      rm("SSO_CONFIG", envir = globalenv())
    }
  }, add = TRUE)

  json <- '{"preferred_username":"mehmet","sub":"abc123"}'
  payload_b64 <- base64enc::base64encode(charToRaw(json))
  token <- paste0("header.", payload_b64, ".signature")

  payload <- decode_jwt_payload(token)

  testthat::expect_false(is.null(payload))
  testthat::expect_identical(payload$preferred_username, "mehmet")
  testthat::expect_identical(payload$sub, "abc123")
})
