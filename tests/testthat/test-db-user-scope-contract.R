# ==============================================================================
# Dosya Yolu: tests/testthat/test-db-user-scope-contract.R
# Açıklama: Sohbet geçmişi/veri görünürlüğü sorgularında UserID ve IsDeleted
# filtrelerinin korunmasını statik sözleşme olarak doğrular. Gerçek veritabanına
# bağlanmaz.
# ==============================================================================

.read_repo_file <- function(path) {
  repo_root <- resolve_repo_root_for_tests()
  paste(
    readLines(file.path(repo_root, path), warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
}

test_that("sohbet önizleme sorgusu kullanıcı ve soft-delete filtresini korur", {
  txt <- .read_repo_file("R/helpers_database.R")

  expect_true(
    grepl(
      "(?is)load_chats_preview_from_db\\s*<-\\s*function.*?WHERE\\s+c\\.UserID\\s*=\\s*\\?\\s+AND\\s+c\\.IsDeleted\\s*=\\s*0",
      txt,
      perl = TRUE
    ),
    info = "load_chats_preview_from_db içinde c.UserID = ? AND c.IsDeleted = 0 filtresi korunmalı."
  )
})

test_that("sohbet yükleme sorguları kullanıcı ve soft-delete filtresini korur", {
  txt <- .read_repo_file("R/helpers_database.R")

  expect_true(
    grepl(
      "(?is)load_chats_from_db\\s*<-\\s*function.*?WHERE\\s+c\\.UserID\\s*=\\s*\\?\\s+AND\\s+c\\.IsDeleted\\s*=\\s*0",
      txt,
      perl = TRUE
    ),
    info = "load_chats_from_db içinde kullanıcı ve IsDeleted filtresi korunmalı."
  )

  # Fonksiyonun hem özet hem mesajlı yükleme dallarında aynı güvenlik filtresi olmalı.
  matches <- gregexpr(
    "WHERE\\s+c\\.UserID\\s*=\\s*\\?\\s+AND\\s+c\\.IsDeleted\\s*=\\s*0",
    txt,
    perl = TRUE,
    ignore.case = TRUE
  )[[1]]

  expect_gte(
    length(matches[matches > 0]),
    3L,
    info = "helpers_database.R içinde chat sorguları için beklenen UserID/IsDeleted filtre sayısı az görünüyor."
  )
})