# ==============================================================================
# Dosya Yolu: R/helpers_mcp_table_readers.R
# Açıklama: MCP akışında kullanılan Excel/genel tablo okuyucuları ve Markdown
#           tablo üreticisi. helpers_mcp_tools ortamına fonksiyon ekler.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  .mcp_context_path <- file.path("R", "helpers_mcp_context.R")

  if (!file.exists(.mcp_context_path)) {
    stop(
      "R/helpers_mcp_context.R bulunamadı; helpers_mcp_table_readers.R yüklenemiyor.",
      call. = FALSE
    )
  }

  source(.mcp_context_path, encoding = "UTF-8", local = globalenv())
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

if (!exists("normalize_excel_path", envir = helpers_mcp_tools, inherits = FALSE)) {
  stop(
    "MCP tablo okuyucuları için helpers_mcp_tools$normalize_excel_path hazır olmalıdır. R/helpers_mcp_tools.R önce yüklenmelidir.",
    call. = FALSE
  )
}

# Global sağlam Excel okuyucu varsa MCP ortamına taşı; yoksa yerel fallback kullan.
# Önemli: utils_excel_reader.R içindeki safe_read_excel_table(), normalize_excel_path()
# gibi yardımcıları unqualified çağırır. MCP/tool/worker bağlamında bu fonksiyonun
# globalenv() yerine helpers_mcp_tools ortamında çalışması gerekir.
if (exists("safe_read_excel_table", envir = globalenv(), inherits = TRUE)) {
  .global_safe_read_excel_table <- get(
    "safe_read_excel_table",
    envir = globalenv(),
    inherits = TRUE
  )

  if (is.function(.global_safe_read_excel_table)) {
    environment(.global_safe_read_excel_table) <- helpers_mcp_tools

    assign(
      "safe_read_excel_table",
      .global_safe_read_excel_table,
      envir = helpers_mcp_tools
    )
  }

  rm(.global_safe_read_excel_table)
}

if (!exists("safe_read_excel_table", envir = helpers_mcp_tools, inherits = FALSE)) {
  helpers_mcp_tools$safe_read_excel_table <- function(path, sheet = 1, n_max = Inf, min_header_cols = 2) {
    path_prepared <- helpers_mcp_tools$normalize_excel_path(path)

    if (!file.exists(path_prepared) && !fs::file_exists(path_prepared)) {
      if (file.exists(path)) {
        path_prepared <- path
      } else {
        stop(sprintf("Dosya bulunamadı (Path: %s)", path_prepared))
      }
    }

    ext <- tolower(tools::file_ext(path_prepared))
    if (!ext %in% c("xlsx", "xls", "xlsm")) {
      stop(sprintf("Excel uzantısı bekleniyor, bulundu: .%s", ext))
    }

    df <- tryCatch({
      readxl::read_excel(path_prepared, sheet = sheet, col_names = TRUE)
    }, error = function(e) {
      if (grepl("libxls error", conditionMessage(e), ignore.case = TRUE)) {
        return(readxl::read_xlsx(path_prepared, sheet = sheet, col_names = TRUE))
      }

      if (.Platform$OS.type == "windows") {
        short_p <- tryCatch(
          utils::shortPathName(gsub("/", "\\\\", path_prepared)),
          error = function(x) NULL
        )
        if (!is.null(short_p) && nzchar(short_p)) {
          return(readxl::read_excel(short_p, sheet = sheet, col_names = TRUE))
        }
      }

      if (grepl("unable to translate", conditionMessage(e), fixed = TRUE)) {
        utf8_path <- tryCatch(enc2utf8(path_prepared), error = function(x) path_prepared)
        if (!identical(utf8_path, path_prepared) && file.exists(utf8_path)) {
          return(readxl::read_excel(utf8_path, sheet = sheet, col_names = TRUE))
        }
      }

      stop(e)
    })

    if (is.finite(n_max)) df <- head(df, n_max)
    df <- as.data.frame(df, stringsAsFactors = FALSE)
    if (anyNA(names(df)) || any(names(df) == "")) {
      names(df) <- paste0("X", seq_along(df))
    }
    names(df) <- make.unique(names(df), sep = "_")
    df
  }
}

helpers_mcp_tools$safe_read_table_generic <- function(path, sheet = 1, n_max = Inf) {
  path_fixed <- helpers_mcp_tools$normalize_excel_path(path)

  ext <- tolower(tools::file_ext(path_fixed))
  as_dt <- function(df) data.table::as.data.table(as.data.frame(df, stringsAsFactors = FALSE))

  sanitize_names <- function(df) {
    nms <- names(df)
    if (anyNA(nms) || any(nms == "")) nms <- paste0("X", seq_along(nms))
    names(df) <- make.unique(nms, sep = "_")
    df
  }

  if (ext %in% c("xlsx", "xls")) {
    df <- helpers_mcp_tools$safe_read_excel_table(path_fixed, sheet = sheet, n_max = n_max)
    return(as_dt(sanitize_names(df)))
  }

  if (ext %in% c("csv", "txt")) {
    df <- tryCatch(
      data.table::fread(path_fixed, nThread = 1),
      error = function(e) {
        read.csv(path_fixed, stringsAsFactors = FALSE, check.names = FALSE)
      }
    )
    if (is.finite(n_max)) df <- head(df, n_max)
    return(as_dt(sanitize_names(df)))
  }

  if (ext %in% c("rds")) {
    obj <- readRDS(path_fixed)
    if (inherits(obj, c("data.frame", "data.table", "tbl_df"))) {
      df <- obj
    } else if (is.list(obj) && length(obj)) {
      ix <- which(vapply(
        obj,
        function(x) inherits(x, c("data.frame", "data.table", "tbl_df")),
        logical(1)
      ))
      if (length(ix)) {
        df <- obj[[ix[1]]]
      } else {
        stop("RDS has no data.frame-like object")
      }
    } else {
      stop("RDS is not a data.frame-like object")
    }
    if (is.finite(n_max)) df <- head(df, n_max)
    return(as_dt(sanitize_names(df)))
  }

  if (ext %in% c("rdata", "rda")) {
    e <- new.env(parent = emptyenv())
    nm <- load(path_fixed, envir = e)
    picks <- nm[vapply(
      nm,
      function(n) inherits(e[[n]], c("data.frame", "data.table", "tbl_df")),
      logical(1)
    )]
    if (!length(picks)) stop("RData has no data.frame-like object")
    df <- e[[picks[1]]]
    if (is.finite(n_max)) df <- head(df, n_max)
    return(as_dt(sanitize_names(df)))
  }

  stop(sprintf("Unsupported file type: .%s", ext))
}

helpers_mcp_tools$create_md_table <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("_Veri yok_")

  safe_df <- as.data.frame(lapply(df, function(x) {
    if (is.numeric(x)) return(format(x, big.mark = ".", decimal.mark = ",", scientific = FALSE, trim = TRUE))
    if (is.logical(x)) return(ifelse(x, "TRUE", "FALSE"))
    if (inherits(x, "Date") || inherits(x, "POSIXt")) return(as.character(x))
    as.character(x)
  }), stringsAsFactors = FALSE)

  safe_df[] <- lapply(safe_df, function(col) tryCatch(enc2utf8(col), error = function(e) col))

  cols <- tryCatch(enc2utf8(names(safe_df)), error = function(e) names(safe_df))
  header <- paste0("| ", paste(cols, collapse = " | "), " |")
  sep    <- paste0("| ", paste(rep("---", length(cols)), collapse = " | "), " |")

  rows <- vapply(seq_len(nrow(safe_df)), function(i) {
    paste0("| ", paste(safe_df[i, ], collapse = " | "), " |")
  }, character(1))

  paste(c(header, sep, rows), collapse = "\n")
}

# Worker ve MCP araç bağlamlarında fonksiyonlar kendi helper ortamlarını taşımalıdır.
# Özellikle safe_read_excel_table(), normalize_excel_path() gibi yardımcıları
# unqualified çağırabildiği için environment helpers_mcp_tools olmalıdır.
assign("helpers_mcp_tools", helpers_mcp_tools, envir = helpers_mcp_tools)

for (.mcp_reader_fn in c("safe_read_excel_table", "safe_read_table_generic", "create_md_table")) {
  if (exists(.mcp_reader_fn, envir = helpers_mcp_tools, inherits = FALSE)) {
    .mcp_reader_fun <- get(.mcp_reader_fn, envir = helpers_mcp_tools, inherits = FALSE)

    if (is.function(.mcp_reader_fun)) {
      environment(.mcp_reader_fun) <- helpers_mcp_tools
      assign(.mcp_reader_fn, .mcp_reader_fun, envir = helpers_mcp_tools)
    }
  }
}

if (exists(".mcp_reader_fn", inherits = FALSE)) {
  rm(.mcp_reader_fn)
}

if (exists(".mcp_reader_fun", inherits = FALSE)) {
  rm(.mcp_reader_fun)
}