# ==============================================================================
# Dosya Yolu: tests/testthat/test-file-manager-table-runtime-behavior.R
# Açıklama: R/helpers_file_manager_table_runtime.R içindeki DT tablo runtime ve
#           ek-durum ayarlayıcı yardımcılarının davranışsal testleri.
#           Gerçek DB/tarayıcı yoktur; sahte session, mock ve testServer kullanılır.
# ==============================================================================

testthat::local_edition(3)

.fm_table_env <- new.env(parent = globalenv())
# Bu dosya fm_register_attach_state_client_handler'a ihtiyaç duyar.
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_attach_client.R"),
  encoding = "UTF-8",
  local = .fm_table_env
)
source(
  file.path(resolve_repo_root_for_tests(), "R", "helpers_file_manager_table_runtime.R"),
  encoding = "UTF-8",
  local = .fm_table_env
)

# Altı sütunlu örnek dosya tablosu üretir (gerçek kolon sırasıyla aynı).
.ornek_dosya_df <- function(n = 1) {
  if (n == 0) {
    return(data.frame(
      name = character(0), size = character(0), type = character(0),
      uploaded = character(0), actions = character(0), context = character(0),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    name = paste0("rapor_", seq_len(n), ".pdf"),
    size = rep("12 KB", n),
    type = rep("PDF", n),
    uploaded = rep("2026-01-01 10:00", n),
    actions = rep("<a href='#'>Sil</a>", n),
    context = rep("<input type='checkbox'/>", n),
    stringsAsFactors = FALSE
  )
}

# -----------------------------------------------------------------------------
# fm_create_file_manager_attachment_setter (saf kapanış - Shiny gerektirmez)
# -----------------------------------------------------------------------------

test_that("ek ayarlayıcı: işaretlenince üst bağlama ekler ve ns önekli setAttachState gönderir", {
  kayit <- new.env()
  kayit$attached <- list()
  kayit$detached <- character(0)
  kayit$msgs <- list()

  sahte_session <- list(
    sendCustomMessage = function(type, message) {
      kayit$msgs[[length(kayit$msgs) + 1]] <- list(type = type, message = message)
    }
  )
  ns <- function(x = "") paste0("fm-", x)

  mv <- new.env()
  mv$file_contents <- list("id1" = list(name = "rapor.pdf", path = "/x/rapor.pdf"))
  mv$files_in_context <- list()
  provider <- function() mv

  ekle <- function(content) kayit$attached[[length(kayit$attached) + 1]] <- content
  cikar <- function(filename) kayit$detached <- c(kayit$detached, filename)

  setter <- .fm_table_env$fm_create_file_manager_attachment_setter(
    sahte_session, ns, provider, ekle, cikar
  )

  sonuc <- setter("rapor.pdf", TRUE)

  expect_true(isTRUE(sonuc))
  expect_length(kayit$attached, 1)
  expect_equal(kayit$attached[[1]]$name, "rapor.pdf")
  expect_length(kayit$detached, 0)
  # Bağlam durumu güncellenmeli.
  expect_true(isTRUE(mv$files_in_context[["id1"]]))
  # İstemciye ns önekli setAttachState mesajı gitmeli.
  expect_length(kayit$msgs, 1)
  expect_equal(kayit$msgs[[1]]$type, "fm-setAttachState")
  expect_equal(kayit$msgs[[1]]$message$ids, "id1")
  expect_true(isTRUE(kayit$msgs[[1]]$message$checked))
})

test_that("ek ayarlayıcı: işaret kaldırılınca üst bağlamdan çıkarır ve durumu temizler", {
  kayit <- new.env()
  kayit$detached <- character(0)
  kayit$msgs <- list()

  sahte_session <- list(
    sendCustomMessage = function(type, message) {
      kayit$msgs[[length(kayit$msgs) + 1]] <- list(type = type, message = message)
    }
  )
  ns <- function(x = "") paste0("fm-", x)

  mv <- new.env()
  mv$file_contents <- list("id9" = list(name = "veri.xlsx"))
  mv$files_in_context <- list("id9" = TRUE)  # önceden ekli
  provider <- function() mv

  setter <- .fm_table_env$fm_create_file_manager_attachment_setter(
    sahte_session, ns, provider,
    attach_in_parent = function(content) stop("ekleme çağrılmamalı"),
    detach_in_parent = function(filename) kayit$detached <- c(kayit$detached, filename)
  )

  sonuc <- setter("veri.xlsx", FALSE)

  expect_true(isTRUE(sonuc))
  expect_equal(kayit$detached, "veri.xlsx")
  # Bağlam durumundan kaldırılmalı (NULL).
  expect_null(mv$files_in_context[["id9"]])
  expect_equal(kayit$msgs[[1]]$message$ids, "id9")
  expect_false(isTRUE(kayit$msgs[[1]]$message$checked))
})

test_that("ek ayarlayıcı: bilinmeyen dosya adı için FALSE döner ve yan etki üretmez", {
  kayit <- new.env()
  kayit$attached <- 0L
  kayit$msgs <- 0L

  sahte_session <- list(
    sendCustomMessage = function(type, message) kayit$msgs <- kayit$msgs + 1L
  )
  ns <- function(x = "") paste0("fm-", x)

  mv <- new.env()
  mv$file_contents <- list("id1" = list(name = "var.pdf"))
  mv$files_in_context <- list()
  provider <- function() mv

  setter <- .fm_table_env$fm_create_file_manager_attachment_setter(
    sahte_session, ns, provider,
    attach_in_parent = function(content) kayit$attached <- kayit$attached + 1L,
    detach_in_parent = function(filename) kayit$attached <- kayit$attached + 1L
  )

  sonuc <- setter("yok.pdf", TRUE)

  expect_false(isTRUE(sonuc))
  expect_identical(kayit$attached, 0L)
  expect_identical(kayit$msgs, 0L)
})

# -----------------------------------------------------------------------------
# fm_register_file_manager_table_runtime (testServer ile)
# -----------------------------------------------------------------------------

test_that("tablo runtime: initAttachHandlerOnce mesajı ns_prefix ile gönderilir ve TRUE döner", {
  skip_if_not_installed("DT")
  skip_if_not_installed("shiny")

  kayit <- new.env()
  kayit$msgs <- list()
  kayit$ret <- NULL

  provider <- function() list(files = .ornek_dosya_df(2), file_contents = list())

  # onFlushed içindeki shinyjs::runjs'i etkisiz kıl (kayıt davranışını ölçmüyoruz).
  testthat::local_mocked_bindings(
    runjs = function(code, ...) invisible(NULL),
    .package = "shinyjs"
  )

  shiny::testServer(
    function(input, output, session) {
      # Kök session'da sendCustomMessage'ı yakala (gözlemci flush'ta tetiklenir).
      session$sendCustomMessage <- function(type, message) {
        kayit$msgs[[type]] <- message
      }
      ns <- function(x = "") paste0("fm-", x)
      kayit$ret <- .fm_table_env$fm_register_file_manager_table_runtime(
        session, output, ns, provider
      )
    },
    {
      session$flushReact()
      expect_true(isTRUE(kayit$ret))
      expect_true("initAttachHandlerOnce" %in% names(kayit$msgs))
      expect_equal(kayit$msgs[["initAttachHandlerOnce"]]$ns_prefix, "fm-")
    }
  )
})

test_that("tablo runtime: files_table çıktısı dolu ve boş veri için hatasız render edilir", {
  skip_if_not_installed("DT")
  skip_if_not_installed("shiny")

  testthat::local_mocked_bindings(
    runjs = function(code, ...) invisible(NULL),
    .package = "shinyjs"
  )

  # Dolu tablo
  shiny::testServer(
    function(input, output, session) {
      session$sendCustomMessage <- function(type, message) invisible(NULL)
      ns <- function(x = "") paste0("fm-", x)
      .fm_table_env$fm_register_file_manager_table_runtime(
        session, output, ns,
        function() list(files = .ornek_dosya_df(3), file_contents = list())
      )
    },
    {
      session$flushReact()
      expect_error(force(output$files_table), NA)
    }
  )

  # Boş tablo (nrow == 0 dalı)
  shiny::testServer(
    function(input, output, session) {
      session$sendCustomMessage <- function(type, message) invisible(NULL)
      ns <- function(x = "") paste0("fm-", x)
      .fm_table_env$fm_register_file_manager_table_runtime(
        session, output, ns,
        function() list(files = .ornek_dosya_df(0), file_contents = list())
      )
    },
    {
      session$flushReact()
      expect_error(force(output$files_table), NA)
    }
  )
})
