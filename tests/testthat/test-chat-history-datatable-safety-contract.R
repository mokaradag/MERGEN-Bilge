# ==============================================================================
# Dosya Yolu: tests/testthat/test-chat-history-datatable-safety-contract.R
# Açıklama: Söyleşi Geçmişi DataTable HTML kaçış güvenliği sözleşmesi.
# ==============================================================================

.find_repo_root_chat_history_dt_safety <- function() {
  candidates <- unique(normalizePath(
    c(
      getwd(),
      file.path(getwd(), ".."),
      file.path(getwd(), "..", "..")
    ),
    winslash = "/",
    mustWork = FALSE
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "app.R")) &&
        file.exists(file.path(candidate, "R/module_chat_history.R"))) {
      return(candidate)
    }
  }

  stop("Repo kökü bulunamadı.", call. = FALSE)
}

.read_repo_text_chat_history_dt_safety <- function(path) {
  full_path <- file.path(.find_repo_root_chat_history_dt_safety(), path)

  size <- suppressWarnings(file.info(full_path)$size[1])
  if (is.na(size) || size <= 0) {
    return("")
  }

  con <- file(full_path, open = "rb")
  on.exit(close(con), add = TRUE)

  raw_data <- readBin(con, what = "raw", n = size)

  txt <- suppressWarnings(
    iconv(list(raw_data), from = "UTF-8", to = "UTF-8", sub = "byte")[[1]]
  )

  if (is.na(txt)) {
    txt <- ""
  }

  txt <- gsub("\\r\\n?|\\r", "\n", txt, perl = TRUE)
  enc2utf8(txt)
}

test_that("Söyleşi Geçmişi DataTable kullanıcı/AI metnini raw HTML olarak işlemez", {
  history_text <- .read_repo_text_chat_history_dt_safety("R/module_chat_history.R")

  expect_true(grepl("output\\$history_table\\s*<-\\s*DT::renderDT", history_text, perl = TRUE))
  expect_true(grepl("DT::datatable\\s*\\(", history_text, perl = TRUE))
  expect_true(grepl("escape\\s*=\\s*TRUE", history_text, perl = TRUE))

  history_table_start <- regexpr("output\\$history_table\\s*<-\\s*DT::renderDT", history_text, perl = TRUE)[[1]]
  expect_gt(history_table_start, 0)

  history_table_block <- substring(history_text, history_table_start)
  next_download <- regexpr("output\\$export_history\\s*<-\\s*downloadHandler", history_table_block, perl = TRUE)[[1]]

  if (next_download > 0) {
    history_table_block <- substring(history_table_block, 1, next_download - 1)
  }

  expect_false(
    grepl("escape\\s*=\\s*FALSE", history_table_block, perl = TRUE),
    info = "Söyleşi Geçmişi tablosunda Soru/Cevap önizlemeleri raw HTML olarak render edilmemelidir."
  )
})
# ------------------------------------------------------------------------------
# Yönetici paneli escape = FALSE tabloları
# ------------------------------------------------------------------------------
# Bu tablolar rozet/ikon HTML'i render ettiği için escape = FALSE kullanır.
# Sözleşme: escape = FALSE kullanan her yönetici tablosunda, kullanıcı/LLM
# kontrollü serbest metin sütunları htmltools::htmlEscape() ile kaçırılmalıdır.
.admin_dt_escape_targets <- list(
  list(
    path = "R/module_admin_yanit_analizi_outputs.R",
    columns = c("ModelUsed", "kullanici", "etiketler", "yorum", "onizleme")
  ),
  list(
    path = "R/helpers_admin_geri_bildirim_output_tables.R",
    columns = c("kullanici", "etiketler_display", "sevilen_display", "gelistirme_display")
  )
)

test_that("yönetici escape = FALSE tabloları kullanıcı metnini htmlEscape ile kaçırır", {
  for (hedef in .admin_dt_escape_targets) {
    metin <- .read_repo_text_chat_history_dt_safety(hedef$path)
    expect_true(nzchar(metin), info = hedef$path)

    for (sutun in hedef$columns) {
      # Sütun adı TAM eşleşmelidir: önek eşleşmesi (kullanici vs kullanici_adi)
      # yalnızca daha uzun bir sütun kaçırıldığında da sözleşmeyi geçiriyordu.
      # Atama ETKİN bir kod satırını başlatmalıdır: yorum satırındaki
      # `# data$kullanici <- htmltools::htmlEscape(...)` da eşleşiyor ve etkin
      # atama silinmişken sözleşme geçiyordu.
      desen <- paste0(
        "(?m)^[ \\t]*data\\$", sutun,
        "(?![A-Za-z0-9._])\\s*<-\\s*htmltools::htmlEscape"
      )
      expect_true(
        grepl(desen, metin, perl = TRUE),
        info = paste0(hedef$path, " :: data$", sutun, " htmlEscape ile atanmalıdır.")
      )
    }
  }
})
