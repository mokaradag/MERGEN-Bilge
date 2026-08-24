# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_core_impl.R
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

      # `integer64` HASSASİYETİ KORUNUR.
      #
      # `bit64::integer64` `is.numeric()` denetimini GEÇER, ama base `sprintf()`
      # bu sınıfa DİSPATCH ETMEZ: 2^53 üstündeki büyüklüklerde ham double bit
      # deseni ya da yuvarlanmış bir değer basılırdı. `as.character()` doğru
      # dizeyi üretir; ortalama da `as.numeric()` üzerinden AÇIKÇA hesaplanır.
      if (inherits(valid_vals, "integer64")) {
        return(sprintf(
          "- %s: (Sayısal, Min: %s, Maks: %s, Ort: %.2f, Kayıt: %d)",
          col,
          as.character(min(valid_vals)),
          as.character(max(valid_vals)),
          mean(as.numeric(valid_vals)),
          length(valid_vals)
        ))
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

        # YEDEK BİÇİMLER "HEPSİ BAŞARISIZ" KOŞULUNA BAĞLI DEĞİLDİR.
        # KARIŞIK biçimli bir sütunda ilk biçim bazı değerleri çevirdiğinde
        # `all(is.na(...))` FALSE olur, yedekler hiç denenmez ve KALAN gerçek
        # tarihler sessizce NA olarak düşürülürdü. Artık her yedek biçim
        # YALNIZCA hâlâ NA olan değerlere uygulanır; tek biçimli sütunlarda
        # sonuç birebir aynıdır.
        gecerli <- !is.na(vals_char) & nzchar(vals_char)
        converted <- as.Date(rep(NA_character_, length(vals_char)))

        for (bicim in c("%d.%m.%Y", "%Y-%m-%d", "%d/%m/%Y")) {
          eksik <- gecerli & is.na(converted)
          if (!any(eksik)) break
          deneme <- suppressWarnings(as.Date(vals_char[eksik], format = bicim))
          converted[eksik] <- deneme
        }

        success_count <- sum(!is.na(converted) & !is.na(vals_char) & nzchar(vals_char))
        total_count <- sum(!is.na(vals_char) & nzchar(vals_char))

        if (total_count > 0 && (success_count / total_count) >= 0.5) {
          data[[col]] <- converted
          cat(sprintf(
            "[PK_ANALIZ] Tarih dönüşümü: '%s' sütunu Date tipine çevrildi (%d/%d başarılı)\n",
            col,
            success_count,
            total_count
          ))
        } else {
          cat(sprintf(
            "[PK_ANALIZ] UYARI: '%s' sütunu Date'e çevrilemedi (başarı oranı düşük)\n",
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

  # `iconv()` VEKTÖRELDİR. Öge başına altı `iconv()` çağrısı yerine aday
  # kodlama başına TEK geçiş yapılır ve yalnızca hâlâ NA olan ögeler
  # doldurulur (yukarıdaki tarih dönüşümündeki desenin aynısı). Maliyet
  # satır x aday yerine yalnızca aday sayısıyla ölçeklenir; sonuç aynıdır.
  out <- rep(NA_character_, length(x))
  bos <- is.na(x) | !nzchar(x)
  out[bos] <- x[bos]

  for (kodlama in denenecek_kodlamalar) {
    eksik <- is.na(out) & !bos
    if (!any(eksik)) break
    deneme <- tryCatch(
      iconv(x[eksik], from = kodlama, to = "UTF-8", sub = NA),
      error = function(e) rep(NA_character_, sum(eksik))
    )
    out[eksik] <- deneme
  }

  eksik <- is.na(out) & !bos
  if (any(eksik)) {
    yedek <- tryCatch(
      iconv(x[eksik], from = "", to = "UTF-8", sub = "?"),
      error = function(e) enc2utf8(x[eksik])
    )
    hala_na <- is.na(yedek)
    if (any(hala_na)) yedek[hala_na] <- enc2utf8(x[eksik][hala_na])
    out[eksik] <- yedek
  }

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

  # TÜRKÇE DESEN UTF-8'E SABİTLENİR.
  #
  # `source(file, encoding = "UTF-8")` dize sabitlerini YERLİ (WINDOWS-1254)
  # işaretler; karşılaştırılan metin ise UTF-8 işaretli gelir ve `perl = TRUE`
  # eşleşmesi Türkçe Windows VM'de SESSİZCE durur. Köşeli parantezli Türkçe bir
  # tanımlayıcı o zaman `[...]` olarak kalır, `SET QUOTED_IDENTIFIER ON` yazımı
  # uygulanmaz ve bu yardımcının önlemek için var olduğu ODBC ayrıştırma sorunu
  # geri döner.
  sql_text_fixed <- gsub(
    enc2utf8("\\[([^\\]\\r\\n]*[ ÇĞİÖŞÜçğıöşü][^\\]\\r\\n]*)\\]"),
    "\"\\1\"",
    enc2utf8(sql_text),
    perl = TRUE
  )

  paste0("SET QUOTED_IDENTIFIER ON;\n", sql_text_fixed)
}
