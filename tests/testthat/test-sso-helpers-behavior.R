# ==============================================================================
# Dosya Yolu: tests/testthat/test-sso-helpers-behavior.R
# Açıklama: SSO yardımcılarının davranışsal testleri. build_sso_logout_url URL
#           kurulumu (client_id + kodlanmış post_logout_redirect_uri) ve
#           check_user_authorization boş kullanıcı koruması doğrulanır. Bu
#           güvenlik-duyarlı bir sınırdır. DB/LLM/tarayıcı gerekmez; geçerli
#           kullanıcı yetki sorgusu (DB) test edilmez.
# ==============================================================================

.sso_helpers_source_once <- function() {
  if (exists("build_sso_logout_url", envir = globalenv(),
             mode = "function", inherits = TRUE) &&
      exists("check_user_authorization", envir = globalenv(),
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

# build_sso_logout_url SSO_ENABLED ve SSO_CONFIG globallerine bağlıdır;
# test süresince geçici değerler atanır ve geri yüklenir.
.with_sso_globals <- function(enabled, config) {
  names <- c("SSO_ENABLED", "SSO_CONFIG")
  had <- vapply(names, exists, logical(1), envir = globalenv(), inherits = FALSE)
  old <- lapply(names, function(nm) {
    if (exists(nm, envir = globalenv(), inherits = FALSE)) get(nm, envir = globalenv()) else NULL
  })
  names(old) <- names

  assign("SSO_ENABLED", enabled, envir = globalenv())
  assign("SSO_CONFIG", config, envir = globalenv())

  list(restore = function() {
    for (nm in names) {
      if (isTRUE(had[[nm]])) {
        assign(nm, old[[nm]], envir = globalenv())
      } else if (exists(nm, envir = globalenv(), inherits = FALSE)) {
        rm(list = nm, envir = globalenv())
      }
    }
  })
}

testthat::test_that("build_sso_logout_url SSO kapalıyken NULL döner", {
  .sso_helpers_source_once()

  g <- .with_sso_globals(FALSE, list(logout_endpoint = "https://kc.local/logout", client_id = "mbilge"))
  on.exit(g$restore(), add = TRUE)

  testthat::expect_null(build_sso_logout_url())
})

testthat::test_that("build_sso_logout_url logout endpoint yoksa NULL döner", {
  .sso_helpers_source_once()

  g <- .with_sso_globals(TRUE, list(logout_endpoint = NULL, client_id = "mbilge"))
  on.exit(g$restore(), add = TRUE)

  testthat::expect_null(build_sso_logout_url())
})

testthat::test_that("build_sso_logout_url client_id ve kodlanmış redirect ile URL kurar", {
  .sso_helpers_source_once()

  g <- .with_sso_globals(TRUE, list(logout_endpoint = "https://kc.local/logout", client_id = "mbilge"))
  on.exit(g$restore(), add = TRUE)

  # Redirect olmadan: yalnızca client_id.
  url_basic <- build_sso_logout_url()
  testthat::expect_true(grepl("https://kc.local/logout?client_id=mbilge", url_basic, fixed = TRUE))

  # Redirect ile: post_logout_redirect_uri reserved-encode edilmeli.
  url_redirect <- build_sso_logout_url("https://app.local/return")
  testthat::expect_true(grepl("client_id=mbilge", url_redirect, fixed = TRUE))
  testthat::expect_true(grepl("post_logout_redirect_uri=https%3A%2F%2Fapp.local%2Freturn", url_redirect, fixed = TRUE))
})

testthat::test_that("check_user_authorization boş/NULL kullanıcıda yetki vermez", {
  .sso_helpers_source_once()

  res_null <- check_user_authorization(NULL)
  testthat::expect_false(isTRUE(res_null$authorized))

  res_empty <- check_user_authorization("")
  testthat::expect_false(isTRUE(res_empty$authorized))
})
