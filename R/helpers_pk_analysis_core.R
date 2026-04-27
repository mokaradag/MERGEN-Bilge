# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_core.R
# Açıklama: Proje ve Kaynak Analizi modülünün saf / düşük yan etkili yardımcıları.
#           Bu dosya bilinçli olarak Shiny observer, LLM çağrısı veya canlı DB
#           bağlantısı başlatmaz. module_proje_kaynak_analizi.R dosyasını küçültmek
#           ve bakım skorunu iyileştirmek için çıkarılmıştır.
# ==============================================================================

# SQL analizi için maksimum prompt boyutu (karakter)
MAX_ANALYSIS_PROMPT_CHARS <- 150000  # ~37K token, güvenli sınır

# AI için sütun özetleri oluşturan yardımcı fonksiyon
summarize_columns_for_ai <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("")

  summary_list <- lapply(names(df), function(col) {
    vals <- df[[col]]
    if (all(is.na(vals))) return(sprintf("- %s: (Hepsi NULL)", col))

    if (is.numeric(vals)) {
      valid_vals <- vals[!is.na(vals)]
      if (length(valid_vals) == 0) {
        return(sprintf("- %s: (Sayısal, veri yok)", col))
      }

      return(sprintf(
        "- %s: (Sayısal, Min: %s, Maks: %s, Ort: %.2f, Kayıt: %d)",
        col,
        min(valid_vals),
        max(valid_vals),
        mean(valid_vals),
        length(valid_vals)
      ))
    } else if (inherits(vals, "Date") || inherits(vals, "POSIXt")) {
      return(sprintf(
        "- %s: (Tarih, Aralık: %s - %s)",
        col,
        min(vals, na.rm = TRUE),
        max(vals, na.rm = TRUE)
      ))
    } else {
      u_vals <- unique(na.omit(as.character(vals)))
      u_vals <- sort(u_vals)

      if (length(u_vals) <= 20) {
        return(sprintf("- %s: [%s]", col, paste(u_vals, collapse = ", ")))
      } else {
        return(sprintf(
          "- %s: [%s, ... (+%d deger daha)]",
          col,
          paste(head(u_vals, 15), collapse = ", "),
          length(u_vals) - 15
        ))
      }
    }
  })

  paste(unlist(summary_list), collapse = "\n")
}

convert_date_columns <- function(data, date_col_names) {
  if (is.null(date_col_names) || length(date_col_names) == 0) return(data)
  if (is.null(data) || nrow(data) == 0) return(data)

  for (col in date_col_names) {
    if (col %in% names(data)) {
      vals <- data[[col]]

      if (inherits(vals, "Date") || inherits(vals, "POSIXt")) {
        next
      }

      if (is.character(vals) || is.factor(vals)) {
        vals_char <- as.character(vals)

        converted <- as.Date(vals_char, format = "%d.%m.%Y")

        if (all(is.na(converted[!is.na(vals_char) & nzchar(vals_char)]))) {
          converted <- as.Date(vals_char, format = "%Y-%m-%d")
        }

        if (all(is.na(converted[!is.na(vals_char) & nzchar(vals_char)]))) {
          converted <- as.Date(vals_char, format = "%d/%m/%Y")
        }

        success_count <- sum(!is.na(converted) & !is.na(vals_char) & nzchar(vals_char))
        total_count <- sum(!is.na(vals_char) & nzchar(vals_char))

        if (total_count > 0 && (success_count / total_count) >= 0.5) {
          data[[col]] <- converted
          cat(sprintf(
            "[PK_ANALIZ] Tarih donusumu: '%s' sutunu Date tipine cevrildi (%d/%d basarili)\n",
            col,
            success_count,
            total_count
          ))
        } else {
          cat(sprintf(
            "[PK_ANALIZ] UYARI: '%s' sutunu Date'e cevrilemedi (basari orani dusuk)\n",
            col
          ))
        }
      }
    }
  }

  data
}

normalize_pk_text_utf8 <- function(x) {
  if (is.null(x)) return(x)
  if (is.factor(x)) x <- as.character(x)
  if (!is.character(x)) return(x)

  denenecek_kodlamalar <- unique(c(
    "UTF-8",
    getOption("mergen.db.name_encoding", "UTF-8"),
    getOption("mergen.db.client_encoding", "UTF-8"),
    "",
    "WINDOWS-1254",
    "latin1"
  ))

  donustur_tek <- function(s) {
    if (is.na(s) || !nzchar(s)) return(s)

    for (kodlama in denenecek_kodlamalar) {
      y <- tryCatch(
        iconv(s, from = kodlama, to = "UTF-8", sub = NA),
        error = function(e) NA_character_
      )

      if (!is.na(y)) {
        Encoding(y) <- "UTF-8"
        return(y)
      }
    }

    y <- tryCatch(
      iconv(s, from = "", to = "UTF-8", sub = "?"),
      error = function(e) enc2utf8(s)
    )

    if (is.na(y)) {
      y <- enc2utf8(s)
    }

    Encoding(y) <- "UTF-8"
    y
  }

  out <- vapply(x, donustur_tek, character(1), USE.NAMES = FALSE)
  out[is.na(x)] <- NA_character_
  Encoding(out) <- "UTF-8"
  out
}

normalize_pk_dataframe_utf8 <- function(df) {
  if (is.null(df) || !is.data.frame(df)) return(df)

  eski_isimler <- names(df)
  if (!is.null(eski_isimler)) {
    names(df) <- normalize_pk_text_utf8(eski_isimler)
  }

  for (j in seq_along(df)) {
    if (is.character(df[[j]]) || is.factor(df[[j]])) {
      df[[j]] <- normalize_pk_text_utf8(df[[j]])
    }
  }

  df
}

execute_pk_sql_unicode <- function(conn, sql_text) {
  if (is.null(sql_text) || !nzchar(trimws(sql_text))) {
    stop("Bos SQL metni gonderilemez.")
  }

  # SQL metnini ham batch olarak değil, Unicode parametre olarak SQL Server'a gönder.
  # Bu yöntem, köşeli parantezli + Türkçe karakterli + boşluklu sütun adlarında
  # ODBC tarafında yaşanan parse/encoding sorunlarını azaltmak için kullanılır.
  wrapper_sql <- paste(
    "DECLARE @sql NVARCHAR(MAX);",
    "SET @sql = ?;",
    "EXEC sp_executesql @sql;",
    sep = "\n"
  )

  DBI::dbGetQuery(
    conn,
    wrapper_sql,
    params = normalize_db_params(list(sql_text))
  )
}

normalize_sql_server_identifiers <- function(sql_text) {
  if (is.null(sql_text) || !nzchar(sql_text)) return(sql_text)

  sql_text_fixed <- gsub(
    "\\[([^\\]\\r\\n]*[ ÇĞİÖŞÜçğıöşü][^\\]\\r\\n]*)\\]",
    "\"\\1\"",
    sql_text,
    perl = TRUE
  )

  paste0("SET QUOTED_IDENTIFIER ON;\n", sql_text_fixed)
}