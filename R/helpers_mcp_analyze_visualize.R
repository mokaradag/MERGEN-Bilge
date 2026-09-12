# ==============================================================================
# Dosya Yolu: R/helpers_mcp_analyze_visualize.R
# Açıklama: MCP R-first analiz ve görselleştirme aracını tanımlar.
# ==============================================================================

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE))) {
  stop(
    "MCP helper ortamı bulunamadı; helpers_mcp_analyze_visualize.R yüklenemiyor.",
    call. = FALSE
  )
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

.mcp_analyze_visualize_required <- c(
  "auto_file_name",
  "resolve_file_argument",
  "safe_read_table_generic",
  "find_matching_column",
  "create_md_table",
  "normalize_chart_type",
  "prepare_chart_data",
  "mcp_debug_log"
)

.mcp_analyze_visualize_missing <- .mcp_analyze_visualize_required[
  !vapply(.mcp_analyze_visualize_required, function(fn) {
    exists(fn, envir = helpers_mcp_tools, inherits = FALSE) &&
      is.function(get(fn, envir = helpers_mcp_tools, inherits = FALSE))
  }, logical(1))
]

if (length(.mcp_analyze_visualize_missing) > 0L) {
  stop(
    sprintf(
      "MCP analyze_and_visualize bağımlılıkları eksik: %s",
      paste(.mcp_analyze_visualize_missing, collapse = ", ")
    ),
    call. = FALSE
  )
}

rm(.mcp_analyze_visualize_required, .mcp_analyze_visualize_missing)

# ==================================
# Tool 5: analyze_and_visualize
# ==================================
# Türkçe: Bu araç, filtrelenmiş/gruplandırılmış sorguları GERÇEK veriyle yanıtlar.
# AI değer uyduramaz çünkü R hesaplama yapar, AI sadece sonucu gösterir.
helpers_mcp_tools$analyze_and_visualize <- function(
  file_name,
  analysis_type = "summary",  # summary, filtered_stats, grouped_stats, chart
  filter_column = NULL,
  filter_value = NULL,
  group_column = NULL,
  stat_column = NULL,
  stat_function = "mean",  # mean, sum, count, median, min, max
  chart_type = NULL,  # Türkçe: Grafik istenirse: bar, pie, line, hist, scatter
  session = NULL
) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error, ok = FALSE))

  # Türkçe: Dosyayı oku
  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(res$path)
  }, error = function(e) e)

  if (inherits(dt, "error")) {
    return(list(error = sprintf("Dosya okunamadı: %s", dt$message), ok = FALSE))
  }

  display_name <- res$display %||% basename(res$path)
  result_text <- ""
  chart_data <- NULL

  # Türkçe: Sütun doğrulama
  available_cols <- names(dt)

  # --- AKILLI SÜTUN EŞLEŞTİRME ---
  # Türkçe: AI yanlış/eksik sütun adı verdiyse, akıllı eşleştirme ile düzelt
  smart_resolve_column <- function(col_name, col_type_hint = "any") {
    if (is.null(col_name) || !nzchar(col_name)) return(NULL)

    # Direkt eşleşme varsa kullan
    if (col_name %in% available_cols) return(col_name)

    # Akıllı eşleştirme dene
    matched <- helpers_mcp_tools$find_matching_column(col_name, available_cols)
    if (!is.null(matched)) {
      helpers_mcp_tools$mcp_debug_log(
        sprintf("[SMART_MATCH] '%s' -> '%s'", col_name, matched)
      )
      return(matched)
    }

    # Tip ipucu ile eşleştirme
    if (col_type_hint == "numeric") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        for (nc in num_cols) {
          if (grepl(tolower(col_name), tolower(nc), fixed = TRUE) ||
              grepl(tolower(nc), tolower(col_name), fixed = TRUE)) {
            helpers_mcp_tools$mcp_debug_log(
              sprintf("[SMART_MATCH] Sayısal tip eşleşmesi: '%s' -> '%s'", col_name, nc)
            )
            return(nc)
          }
        }
      }
    } else if (col_type_hint == "categorical") {
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      if (length(cat_cols) > 0) {
        for (cc in cat_cols) {
          if (grepl(tolower(col_name), tolower(cc), fixed = TRUE) ||
              grepl(tolower(cc), tolower(col_name), fixed = TRUE)) {
            helpers_mcp_tools$mcp_debug_log(
              sprintf("[SMART_MATCH] Kategorik tip eşleşmesi: '%s' -> '%s'", col_name, cc)
            )
            return(cc)
          }
        }
      }
    }

    NULL
  }

  # --- 1. FİLTRELEME ---
  if (!is.null(filter_column) && nzchar(filter_column) &&
      !is.null(filter_value) && nzchar(filter_value)) {

    resolved_filter_column <- smart_resolve_column(filter_column, "categorical")

    if (is.null(resolved_filter_column)) {
      col_info <- vapply(available_cols, function(cn) {
        if (is.character(dt[[cn]]) || is.factor(dt[[cn]])) {
          unique_vals <- head(unique(as.character(dt[[cn]])), 5)
          sprintf("'%s' (değerler: %s)", cn, paste(unique_vals, collapse = ", "))
        } else {
          sprintf("'%s' (sayısal)", cn)
        }
      }, character(1))

      return(list(
        error = sprintf(
          "Filtre sütunu '%s' bulunamadı.\n\nMevcut sütunlar ve örnek değerler:\n%s\n\nLütfen yukarıdaki GERÇEK sütun isimlerinden birini kullanın.",
          filter_column,
          paste(col_info, collapse = "\n")
        ),
        ok = FALSE
      ))
    }

    filter_column <- resolved_filter_column

    col_vals <- dt[[filter_column]]
    if (is.character(col_vals) || is.factor(col_vals)) {
      # fixed = TRUE: filtre değeri REGEX olarak yorumlanıyordu ("." her şeyi
      # eşliyor, "(" hata veriyordu). Kullanıcı değeri düz metindir; harf
      # duyarsızlık iki tarafı da küçülterek sağlanır.
      filter_mask <- grepl(
        tolower(as.character(filter_value)[1]),
        tolower(as.character(col_vals)),
        fixed = TRUE
      )
    } else {
      filter_val_num <- suppressWarnings(as.numeric(filter_value))
      if (!is.na(filter_val_num)) {
        filter_mask <- col_vals == filter_val_num
      } else {
        filter_mask <- rep(FALSE, nrow(dt))
      }
    }

    # NA maskesi data.table'da satır ENJEKTE eder (NA satırı döner).
    filter_mask[is.na(filter_mask)] <- FALSE

    dt <- dt[filter_mask, ]

    if (nrow(dt) == 0) {
      return(list(
        result = sprintf(
          "### Sonuç Yok\n'%s' sütununda '%s' değeri bulunamadı.",
          filter_column,
          filter_value
        ),
        ok = TRUE
      ))
    }

    result_text <- sprintf(
      "**Filtre:** %s = '%s' (%d kayıt)\n\n",
      filter_column,
      filter_value,
      nrow(dt)
    )
  }

  # --- 2. İSTATİSTİK HESAPLAMA ---
  stat_fun <- switch(tolower(stat_function %||% "mean"),
    "mean" = function(x) mean(x, na.rm = TRUE),
    "sum" = function(x) sum(x, na.rm = TRUE),
    "count" = function(x) sum(!is.na(x)),
    "median" = function(x) median(x, na.rm = TRUE),
    "min" = function(x) min(x, na.rm = TRUE),
    "max" = function(x) max(x, na.rm = TRUE),
    function(x) mean(x, na.rm = TRUE)
  )

  stat_label <- switch(tolower(stat_function %||% "mean"),
    "mean" = "Ortalama",
    "sum" = "Toplam",
    "count" = "Adet",
    "median" = "Medyan",
    "min" = "Minimum",
    "max" = "Maksimum",
    "Ortalama"
  )

  # --- 3. ANALİZ TİPİNE GÖRE İŞLEM ---
  analysis_type <- tolower(analysis_type %||% "summary")

  if (analysis_type == "summary") {
    num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]

    if (length(num_cols) > 0) {
      summary_rows <- lapply(num_cols, function(cn) {
        vals <- dt[[cn]]
        data.frame(
          Sutun = cn,
          Ortalama = round(mean(vals, na.rm = TRUE), 2),
          Medyan = round(median(vals, na.rm = TRUE), 2),
          Min = round(min(vals, na.rm = TRUE), 2),
          Max = round(max(vals, na.rm = TRUE), 2),
          Toplam = round(sum(vals, na.rm = TRUE), 2),
          stringsAsFactors = FALSE
        )
      })

      summary_df <- do.call(rbind, summary_rows)
      names(summary_df)[1] <- "S\u00fctun"

      result_text <- paste0(
        result_text,
        sprintf("### Dosya Özeti: %s\n", display_name),
        sprintf("- **Toplam Satır:** %d\n", nrow(dt)),
        sprintf("- **Toplam Sütun:** %d\n\n", ncol(dt)),
        "#### Sayısal Sütun İstatistikleri (R tarafından hesaplandı)\n",
        helpers_mcp_tools$create_md_table(summary_df)
      )

      chart_data <- summary_df
    } else {
      result_text <- paste0(
        result_text,
        sprintf("### Dosya Özeti: %s\n", display_name),
        sprintf("- **Toplam Satır:** %d\n", nrow(dt)),
        sprintf("- **Toplam Sütun:** %d\n", ncol(dt)),
        sprintf("- **Sütunlar:** %s\n", paste(available_cols, collapse = ", "))
      )
    }
  } else if (analysis_type == "filtered_stats") {
    if (is.null(stat_column) || !nzchar(stat_column)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        stat_column <- num_cols[1]
      } else {
        return(list(error = "Sayısal sütun bulunamadı.", ok = FALSE))
      }
    } else {
      resolved_stat_column <- smart_resolve_column(stat_column, "numeric")
      if (!is.null(resolved_stat_column)) {
        stat_column <- resolved_stat_column
      }
    }

    if (!(stat_column %in% available_cols)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      return(list(
        error = sprintf(
          "İstatistik sütunu '%s' bulunamadı.\nMevcut sayısal sütunlar: %s",
          stat_column,
          paste(num_cols, collapse = ", ")
        ),
        ok = FALSE
      ))
    }

    vals <- dt[[stat_column]]
    if (!is.numeric(vals)) {
      return(list(error = sprintf("'%s' sütunu sayısal değil.", stat_column), ok = FALSE))
    }

    stat_value <- stat_fun(vals)

    result_text <- paste0(
      result_text,
      sprintf("### %s: %s\n\n", stat_label, stat_column),
      sprintf("**Sonuç:** %.2f\n\n", stat_value),
      sprintf("_(Bu değer R tarafından %d kayıt üzerinden hesaplandı)_", nrow(dt))
    )

    chart_data <- data.frame(
      Metrik = stat_label,
      Deger = stat_value,
      stringsAsFactors = FALSE
    )
    names(chart_data)[2] <- "De\u011fer"
  } else if (analysis_type == "grouped_stats") {
    if (is.null(group_column) || !nzchar(group_column)) {
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      if (length(cat_cols) > 0) {
        return(list(
          error = sprintf(
            "group_column parametresi gerekli.\nMevcut kategorik sütunlar: %s",
            paste(cat_cols, collapse = ", ")
          ),
          ok = FALSE
        ))
      } else {
        return(list(error = "group_column parametresi gerekli ve kategorik sütun bulunamadı.", ok = FALSE))
      }
    }

    resolved_group_column <- smart_resolve_column(group_column, "categorical")
    if (!is.null(resolved_group_column)) {
      group_column <- resolved_group_column
    }

    if (!(group_column %in% available_cols)) {
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      return(list(
        error = sprintf(
          "Gruplama sütunu '%s' bulunamadı.\nMevcut kategorik sütunlar: %s",
          group_column,
          paste(cat_cols, collapse = ", ")
        ),
        ok = FALSE
      ))
    }

    if (is.null(stat_column) || !nzchar(stat_column)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        stat_column <- num_cols[1]
      } else {
        return(list(error = "Sayısal sütun bulunamadı.", ok = FALSE))
      }
    } else {
      resolved_stat_column <- smart_resolve_column(stat_column, "numeric")
      if (!is.null(resolved_stat_column)) {
        stat_column <- resolved_stat_column
      }
    }

    if (!(stat_column %in% available_cols)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      return(list(
        error = sprintf(
          "İstatistik sütunu '%s' bulunamadı.\nMevcut sayısal sütunlar: %s",
          stat_column,
          paste(num_cols, collapse = ", ")
        ),
        ok = FALSE
      ))
    }

    grouped_result <- aggregate(
      dt[[stat_column]],
      by = list(Grup = dt[[group_column]]),
      FUN = stat_fun
    )
    names(grouped_result) <- c(group_column, paste0(stat_label, "_", stat_column))

    grouped_result <- grouped_result[order(grouped_result[[2]], decreasing = TRUE), ]

    result_text <- paste0(
      result_text,
      sprintf("### %s Bazında %s: %s\n\n", group_column, stat_label, stat_column),
      helpers_mcp_tools$create_md_table(grouped_result),
      sprintf("\n\n_(Bu değerler R tarafından %d kayıt üzerinden hesaplandı)_", nrow(dt))
    )

    chart_data <- grouped_result
  } else if (analysis_type == "chart") {
    return(helpers_mcp_tools$prepare_chart_data(
      file_name = file_name,
      chart_type = chart_type %||% "bar",
      x = group_column,
      y = stat_column,
      # Değerler doğrudan SQL metnine gömülüyordu; tek tırnak içeren bir değer
      # (ör. "O'Brien") sorguyu bozuyor/enjeksiyona açıyordu. Tanımlayıcı ve
      # değer SQL kurallarına göre kaçırılır.
      # Boş değerlerde filtre SQL'i üretilmez: satır 132'deki akıllı sütun
      # çözümlemesi de atlandığı için ham `filter_column` DuckDB hatasına yol
      # açıyor, hata yutulup grafik FİLTRESİZ üretiliyordu.
      #
      # ANLAM BİRLİĞİ: karakter sütununda özet/gruplu istatistik harf DUYARSIZ
      # ALT DİZE eşleşmesi yapar (`grepl(..., fixed = TRUE)`); grafik dalı TAM
      # EŞİTLİK kurunca `filter_value = "Ank"` istatistikte "Ankara" ile
      # eşleşirken grafik BOŞ dönüyordu. SAYISAL sütunda ise istatistik SAYISAL
      # EŞİTLİK kullanır; metne çevirip LIKE kurmak `1` değerinde `10` ve `21`
      # satırlarını da kapsıyordu. Bu yüzden SQL sütun TÜRÜNE göre üretilir.
      filter_sql = if (!is.null(filter_column) && nzchar(filter_column) &&
                       !is.null(filter_value) && nzchar(filter_value)) {
        sutun <- gsub('"', '""', as.character(filter_column)[1], fixed = TRUE)
        sayisal_sutun <- !is.null(dt[[filter_column]]) &&
          !is.character(dt[[filter_column]]) && !is.factor(dt[[filter_column]])
        filtre_sayi <- suppressWarnings(as.numeric(as.character(filter_value)[1]))

        # TAM DEĞER KORUNUR: `format(..., scientific = FALSE)` yapılandırılmış
        # GÖSTERİM hassasiyetini kullanır (varsayılan `digits = 7`), yani
        # `0.123456789` değeri `0.1234568` olarak SQL'e giriyordu. Bellekteki
        # filtre orijinal double ile karşılaştırdığı için istatistik eşleşen
        # satır bulurken grafik boş kalıyor ya da FARKLI satırlar dönüyordu.
        # Sonlu olmayan değer (NaN/Inf) filtre olarak kullanılamaz.
        if (isTRUE(sayisal_sutun) && is.finite(filtre_sayi)) {
          sayi_sql <- format(
            filtre_sayi,
            digits = 17,
            scientific = FALSE,
            trim = TRUE,
            decimal.mark = "."
          )
          sprintf("\"%s\" = %s", sutun, sayi_sql)
        } else {
          deger <- tolower(as.character(filter_value)[1])
          deger <- gsub("\\", "\\\\", deger, fixed = TRUE)
          deger <- gsub("%", "\\%", deger, fixed = TRUE)
          deger <- gsub("_", "\\_", deger, fixed = TRUE)
          deger <- gsub("'", "''", deger, fixed = TRUE)
          sprintf(
            "LOWER(CAST(\"%s\" AS VARCHAR)) LIKE '%%%s%%' ESCAPE '\\'",
            sutun, deger
          )
        }
      } else {
        NULL
      },
      agg = stat_function,
      session = session
    ))
  }

  # --- 4. GRAFİK EKLENSİN Mİ? ---
  chart_spec <- NULL
  if (!is.null(chart_type) && nzchar(chart_type) && !is.null(chart_data) && nrow(chart_data) > 0) {
    chart_spec <- list(
      type = helpers_mcp_tools$normalize_chart_type(chart_type),
      mapping = list(
        x = names(chart_data)[1],
        y = names(chart_data)[2]
      ),
      params = list(agg = NULL),
      data = as.data.frame(chart_data),
      schema = as.list(vapply(chart_data, function(z) class(z)[1], character(1))),
      n = nrow(chart_data)
    )
  }

  # --- 5. SONUÇ ---
  if (!is.null(chart_spec)) {
    return(list(
      ok = TRUE,
      `__mcp_plot` = TRUE,
      result = result_text,
      chart = chart_spec,
      message = "Analiz ve grafik hazırlandı."
    ))
  }

  list(
    ok = TRUE,
    result = result_text
  )
}