# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-attach-client-behavior.R
# Açıklama: R/helpers_file_manager_attach_client.R içindeki istemci tarafı
#           ek-durum (setAttachState) kayıt yardımcısının davranışsal testleri.
#           Gerçek Shiny/DB/tarayıcı gerektirmez; sahte session ve mock kullanır.
# ==============================================================================

testthat::local_edition(3)

# Test edilen dosyayı yalıtılmış bir ortama yükle.
.fm_attach_env <- new.env(parent = globalenv())
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_attach_client.R"),
  encoding = "UTF-8",
  local = .fm_attach_env
)

test_that("fm_register_attach_state_client_handler onFlushed'i bir kez kaydeder ve TRUE döner", {
  kayit <- new.env()
  kayit$flushed <- list()

  # Sahte session: onFlushed çağrılarını kaydeder.
  sahte_session <- list(
    onFlushed = function(fn, once = FALSE) {
      kayit$flushed[[length(kayit$flushed) + 1]] <- list(fn = fn, once = once)
      invisible(NULL)
    }
  )
  ns <- function(x = "") paste0("dosya_yon-", x)

  sonuc <- .fm_attach_env$fm_register_attach_state_client_handler(
    session = sahte_session, ns = ns
  )

  expect_true(isTRUE(sonuc))
  expect_length(kayit$flushed, 1)
  # Yardımcı, kaydı yalnızca bir kez yapmalı (once = TRUE).
  expect_true(isTRUE(kayit$flushed[[1]]$once))
  expect_true(is.function(kayit$flushed[[1]]$fn))
})

test_that("onFlushed tetiklendiğinde ns önekli setAttachState JS kaydı runjs ile gönderilir", {
  kayit <- new.env()
  kayit$flushed <- list()
  kayit$code <- NULL

  sahte_session <- list(
    onFlushed = function(fn, once = FALSE) {
      kayit$flushed[[length(kayit$flushed) + 1]] <- fn
    }
  )
  ns <- function(x = "") paste0("dosya_yon-", x)

  .fm_attach_env$fm_register_attach_state_client_handler(
    session = sahte_session, ns = ns
  )

  # shinyjs::runjs çağrısını yakala.
  testthat::local_mocked_bindings(
    runjs = function(code, ...) {
      kayit$code <- code
      invisible(NULL)
    },
    .package = "shinyjs"
  )

  # Kaydedilen onFlushed geri çağrısını çalıştır.
  kayit$flushed[[1]]()

  expect_true(is.character(kayit$code))
  # ns öneki JS şablonuna doğru yerleşmeli.
  expect_true(grepl("var nsPrefix = 'dosya_yon-'", kayit$code, fixed = TRUE))
  # Tek seferlik kapı ve gerçek mesaj işleyici kayıtları bulunmalı.
  expect_true(grepl("initAttachHandlerOnce", kayit$code, fixed = TRUE))
  expect_true(grepl("'setAttachState'", kayit$code, fixed = TRUE))
  # Checkbox id'si ns öneki + 'attach_' + dosya id ile çözümlenmeli.
  expect_true(grepl("nsPrefix + 'attach_' + fid", kayit$code, fixed = TRUE))
  # Tek seferlik global kapı bayrağı korunmalı.
  expect_true(grepl("__initAttachHandlerOnce", kayit$code, fixed = TRUE))
})
