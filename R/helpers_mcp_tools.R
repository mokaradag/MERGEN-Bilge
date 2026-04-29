# ==============================================================================
# Dosya Yolu: R/helpers_mcp_tools.R
# Açıklama: MCP araçları, dosya çözümleme, tablo okuma ve analiz yardımcıları.
#           Worker bağlamlarında çalışabilmesi için kendi helper ortamını kullanır.
# ==============================================================================

# MCP bootstrap/source-order yardımcıları ayrı dosyada tutulur.
# helpers_mcp_tools.R tek başına source edildiğinde de eski davranışı korumak için
# burada çalışma dizini bağımsız fallback source uygulanır.
.mcp_find_bootstrap_file <- function(relative_path) {
  relative_path <- gsub("\\\\", "/", relative_path, fixed = TRUE)

  candidate_roots <- c(
    getwd(),
    dirname(getwd()),
    dirname(dirname(getwd())),
    Sys.getenv("MERGEN_REPO_ROOT", unset = ""),
    if (exists("repo_root_for_tests", envir = globalenv(), inherits = TRUE)) {
      get("repo_root_for_tests", envir = globalenv(), inherits = TRUE)
    } else {
      ""
    }
  )

  candidate_roots <- unique(candidate_roots[nzchar(candidate_roots)])

  candidates <- unique(c(
    relative_path,
    file.path(candidate_roots, relative_path)
  ))

  for (candidate in candidates) {
    candidate <- tryCatch(
      normalizePath(candidate, winslash = "/", mustWork = FALSE),
      error = function(e) candidate
    )

    if (file.exists(candidate)) {
      return(candidate)
    }
  }

  ""
}

if (!exists("mcp_tools_bootstrap_ready", mode = "function", inherits = TRUE) ||
    !isTRUE(mcp_tools_bootstrap_ready())) {

  .mcp_bootstrap_path <- .mcp_find_bootstrap_file("R/helpers_mcp_bootstrap.R")

  if (!nzchar(.mcp_bootstrap_path)) {
    stop(
      sprintf(
        "R/helpers_mcp_bootstrap.R bulunamadı; helpers_mcp_tools.R yüklenemiyor. Çalışma dizini: %s",
        getwd()
      ),
      call. = FALSE
    )
  }

  source(.mcp_bootstrap_path, encoding = "UTF-8", local = globalenv())
}

if (exists(".mcp_bootstrap_path", inherits = FALSE)) {
  rm(.mcp_bootstrap_path)
}

rm(.mcp_find_bootstrap_file)

if (!exists("helpers_mcp_tools", envir = globalenv(), inherits = FALSE) ||
    !is.environment(get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)) ||
    !isTRUE(mcp_tools_bootstrap_ready())) {
  stop("MCP bootstrap helper sözleşmesi eksik.", call. = FALSE)
}

helpers_mcp_tools <- get("helpers_mcp_tools", envir = globalenv(), inherits = FALSE)

# Bu helper ailesi R/helpers_mcp_schema_helpers.R içinde tanımlıdır.
# Geriye dönük uyumluluk için dotted alias korunur.
.normalize_args <- helpers_mcp_tools$normalize_args

# ==================================
# Tool 4: prepare_chart_data  (NEW)
# ==================================
helpers_mcp_tools$prepare_chart_data <- function(
  file_name,
  chart_type,
  x = NULL,
  y = NULL,
  group = NULL,
  agg = NULL,
  bins = NULL,
  top_n = NULL,
  # --- new rendering options ---
  stack = NULL,
  donut = NULL,
  orientation = NULL,
  smooth = NULL,
  # ---------------------------------------------------
  filter_sql = NULL,
  limit = 5000,
  session = NULL
) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  chart_type <- helpers_mcp_tools$normalize_chart_type(chart_type)

  # 1) resolve file
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error, ok = FALSE))

  # 2) read
  dt <- tryCatch({
    helpers_mcp_tools$safe_read_table_generic(res$path)
  }, error = function(e) e)
  if (inherits(dt, "error")) {
    return(list(error = sprintf("Dosya okunamadı: %s \U2014 %s", basename(res$path), dt$message), ok = FALSE))
  }
  
  # --- Türkçe yorum: Sütun doğrulama ve akıllı eşleştirme ---
  # Model geçersiz sütun adı verdiyse, önce akıllı eşleştirme dene, bulamazsa otomatik seçime bırak
  available_cols <- names(dt)

  # Türkçe: Akıllı sütun eşleştirme fonksiyonu
  smart_match_column <- function(col_name, col_type = "any") {
    if (is.null(col_name) || !nzchar(col_name)) return(NULL)
    if (col_name %in% available_cols) return(col_name)

    # Akıllı eşleştirme dene
    matched <- helpers_mcp_tools$find_matching_column(col_name, available_cols)
    if (!is.null(matched)) {
      cat("[CHART_SMART_MATCH] '", col_name, "' -> '", matched, "'\n", sep = "")
      return(matched)
    }
    NULL
  }

  # Türkçe yorum: x parametresini akıllı eşleştir
  if (!is.null(x) && nzchar(x) && !(x %in% available_cols)) {
    matched_x <- smart_match_column(x)
    if (!is.null(matched_x)) {
      x <- matched_x
    } else {
      cat("[CHART] x='", x, "' sütunu bulunamadı, otomatik seçilecek\n", sep = "")
      x <- NULL
    }
  }

  # Türkçe yorum: y parametresini akıllı eşleştir (virgüllü çoklu y'yi de kontrol et)
  if (!is.null(y) && nzchar(y)) {
    y_parts <- trimws(strsplit(as.character(y), ",")[[1]])
    resolved_y <- vapply(y_parts, function(yp) {
      if (yp %in% available_cols) return(yp)
      matched <- smart_match_column(yp)
      if (!is.null(matched)) return(matched)
      return("")
    }, character(1))
    resolved_y <- resolved_y[nzchar(resolved_y)]

    if (length(resolved_y) > 0) {
      y <- paste(resolved_y, collapse = ", ")
    } else {
      cat("[CHART] y sütunları bulunamadı: ", paste(y_parts, collapse = ", "), ", otomatik seçilecek\n", sep = "")
      y <- NULL
    }
  }

  # Türkçe yorum: group parametresini akıllı eşleştir
  if (!is.null(group) && nzchar(group) && !(group %in% available_cols)) {
    matched_group <- smart_match_column(group)
    if (!is.null(matched_group)) {
      group <- matched_group
    } else {
      cat("[CHART] group='", group, "' sütunu bulunamadı, otomatik seçilecek\n", sep = "")
      group <- NULL
    }
  }

  # --- Türkçe yorum: Pie/Donut için zorunlu ayarlamalar ---
  # X ekseni, agg ve top_n parametreleri otomatik olarak ayarlanır
  if (tolower(chart_type) %in% c("pie","donut")) {
    # Türkçe yorum: X ekseni yoksa kategorik sütun seç
    if (is.null(x) || !nzchar(x)) {
      cat_cols <- names(dt)[vapply(dt, function(v) is.character(v) || is.factor(v), logical(1))]
      if (length(cat_cols)) {
        x <- cat_cols[1]
      } else {
        # Türkçe yorum: Kategorik sütun yoksa ilk sütunu kullan
        x <- names(dt)[1]
      }
    }
 
    # Türkçe yorum: Y ekseni yoksa ilk sayısal sütunu seç
    if (is.null(y) || !nzchar(y)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      num_cols <- setdiff(num_cols, x)  # X'den farklı olmalı
      if (length(num_cols)) {
        y <- num_cols[1]
      }
    }
 
    # Türkçe yorum: Pie/Donut için agg parametresi ZORUNLU - yoksa otomatik ekle
    if (is.null(agg) || !nzchar(agg)) {
      agg <- "sum"  # Varsayılan olarak toplam kullan
    }
 
    # Türkçe yorum: Pie/Donut için top_n parametresi ZORUNLU - yoksa otomatik ekle
    # Bu, sonsuz dilim oluşturulmasını engeller
    if (is.null(top_n) || is.na(top_n) || !is.numeric(top_n)) {
      top_n <- 10  # Maksimum 10 dilim göster
    } else if (top_n > 20) {
      top_n <- 20  # 20'den fazla dilim mantıksız, sınırla
    }
  }
  
  # --- Türkçe yorum: Diğer grafik türleri için akıllı eksen seçimi ---
  # Kullanıcı veya model x/y belirtmemişse, veri yapısına göre otomatik seç
 
  # Türkçe yorum: Yardımcı fonksiyonlar
  is_date_col <- function(v) inherits(v, c("Date", "POSIXct", "POSIXt"))
  is_numeric_col <- function(v) is.numeric(v)
  is_cat_col <- function(v) is.character(v) || is.factor(v)
 
  # Türkçe yorum: Sütun kategorilerini belirle
  date_cols <- names(dt)[vapply(dt, is_date_col, logical(1))]
  num_cols <- names(dt)[vapply(dt, is_numeric_col, logical(1))]
  cat_cols <- names(dt)[vapply(dt, is_cat_col, logical(1))]
 
  # Türkçe yorum: String formatındaki tarih sütunlarını yakala
  if (length(date_cols) == 0 && length(cat_cols) > 0) {
    date_pattern <- "date|tarih|zaman|time|yil|year|month|ay|period|donem"
    date_candidates <- grep(date_pattern, tolower(cat_cols), value = TRUE)
    if (length(date_candidates) > 0) {
      date_cols <- date_candidates
      cat_cols <- setdiff(cat_cols, date_candidates)
    }
  }
 
  first_or_null <- function(vec) if (length(vec)) vec[1] else NULL
 
  # Türkçe yorum: Line/Area grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) %in% c("line", "area")) {
    if (is.null(x) || !nzchar(x)) {
      # Türkçe yorum: Önce tarih sütunu, yoksa ilk sayısal sütun
      x <- first_or_null(date_cols)
      if (is.null(x)) x <- first_or_null(num_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      # Türkçe yorum: X'den farklı ilk sayısal sütun
      y <- first_or_null(setdiff(num_cols, x))
    }
    if (is.null(group) && length(cat_cols) > 0) {
      # Türkçe yorum: Kategorik sütun varsa gruplama için kullan
      group <- first_or_null(cat_cols)
    }
  }
 
  # Türkçe yorum: Bar/Column grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) %in% c("bar", "column")) {
    if (is.null(x) || !nzchar(x)) {
      # Türkçe yorum: Önce kategorik sütun, yoksa tarih sütunu
      x <- first_or_null(cat_cols)
      if (is.null(x)) x <- first_or_null(date_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      # Türkçe yorum: İlk sayısal sütun
      y <- first_or_null(num_cols)
    }
  }
 
  # Türkçe yorum: Scatter grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) == "scatter") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(num_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(setdiff(num_cols, x))
    }
    if (is.null(group) && length(cat_cols) > 0) {
      group <- first_or_null(cat_cols)
    }
  }
 
  # Türkçe yorum: Histogram için akıllı eksen seçimi
  if (tolower(chart_type) == "hist") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(num_cols)
    }
    # Türkçe yorum: Histogram için y ekseni her zaman NULL olmalı
    y <- NULL
  }
 
  # Türkçe yorum: Pareto grafikleri için akıllı eksen seçimi
  if (tolower(chart_type) == "pareto") {
    if (is.null(x) || !nzchar(x)) {
      x <- first_or_null(cat_cols)
    }
    if (is.null(y) || !nzchar(y)) {
      y <- first_or_null(num_cols)
    }
    # Türkçe yorum: Pareto için agregasyon gerekli
    if (is.null(agg) || !nzchar(agg)) {
      agg <- "sum"
    }
  }

  # 3) optional filter with DuckDB WHERE
  if (!is.null(filter_sql) && nzchar(filter_sql) && helpers_mcp_tools$safe_has_duckdb()) {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir=":memory:")
    on.exit(try(DBI::dbDisconnect(con, shutdown=TRUE), silent=TRUE), add=TRUE)
    DBI::dbWriteTable(con, "t", as.data.frame(dt), temporary = TRUE, overwrite = TRUE)

    q <- sprintf('SELECT * FROM t WHERE %s', filter_sql)
    q <- gsub("`", "\"", q, fixed = TRUE)
    q <- gsub("\\[", "\"", q); q <- gsub("\\]", "\"", q)

    filt <- tryCatch(DBI::dbGetQuery(con, q), error = function(e) e)
    if (!inherits(filt, "error")) dt <- data.table::as.data.table(filt)
  }

  # 4) thin to only needed columns & Handle Multi-Y (Wide-to-Long)
  # Çoklu Y sütunlarını güvenli şekilde ayıkla
  if (is.null(y)) {
    y_candidates <- NULL
  } else if (is.character(y) || is.list(y)) {
    # Liste veya vektör gelirse düzleştir
    raw_y <- unlist(y, use.names = FALSE)
    if (length(raw_y) > 1) {
      y_candidates <- trimws(raw_y)
    } else {
      # Virgülle ayrılmış string gelirse parçala
      y_candidates <- trimws(strsplit(as.character(raw_y), ",")[[1]])
    }
  } else {
    y_candidates <- NULL
  }
  
  # Pie ve Donut grafikleri için otomatik agregasyon kontrolü
  # Eğer kullanıcı agg belirtmemişse ve veri çoksa, sistemi korumak için otomatik topla.
  if (tolower(chart_type) %in% c("pie", "donut", "bar", "column") && is.null(agg)) {
    row_limit_for_raw <- 20
    if (nrow(dt) > row_limit_for_raw) {
      if (!is.null(y_candidates) && length(y_candidates) > 0) {
        agg <- "sum" # Sayısal sütun varsa topla
      } else {
        agg <- "count" # Sayısal sütun yoksa satırları say
      }
    }
  }
  
  if (length(y_candidates) > 1) {
    # Check if all exist
    missing <- setdiff(c(x, y_candidates, group), names(dt))
    if (length(missing)) {
      return(list(error = sprintf("Sütun(lar) bulunamadı: %s", paste(missing, collapse=", ")), ok=FALSE))
    }
    
    # Reshape (Melt)
    measure_vars <- y_candidates
    id_vars <- c(x, group) # keep existing group if any
    id_vars <- id_vars[!is.null(id_vars)]
    
    subset_dt <- data.table::melt(dt, id.vars = id_vars, measure.vars = measure_vars,
                                  variable.name = "Variable", value.name = "Value")
    
    # Update mapping
    y <- "Value"
    # If there was a group, we might need a composite group, but usually multi-Y implies the variable IS the group
    if (is.null(group)) {
      group <- "Variable"
    } else {
      # If both group and multi-Y exist, usually we prioritize the multi-Y as the legend group
      # or we'd need a faceted plot (not supported yet). Let's swap group to Variable.
      group <- "Variable" 
    }
    
  } else {
    # Standard single Y logic
    cols <- unique(na.omit(c(x, y, group)))
    if (!length(cols)) {
      subset_dt <- dt
    } else {
      missing <- setdiff(cols, names(dt))
      if (length(missing)) {
        return(list(
          error = sprintf("Sütun(lar) bulunamadı: %s. Mevcut: %s", paste(missing, collapse = ", "), paste(names(dt), collapse = ", ")),
          ok = FALSE
        ))
      }
      subset_dt <- dt[, ..cols]
    }
  }

  # 5) limit rows and coerce time cols (ChartLab will format)
  if (is.finite(limit) && nrow(subset_dt) > limit) subset_dt <- head(subset_dt, limit)
  for (nm in names(subset_dt)) {
    if (inherits(subset_dt[[nm]], "POSIXt")) next
    if (inherits(subset_dt[[nm]], "Date")) next
    # leave as-is; ChartLab will handle coercions cautiously
  }

  schema <- vapply(subset_dt, function(z) class(z)[1], character(1))

  # 6) build chart spec payload
  list(
    ok = TRUE,
    `__mcp_plot` = TRUE,        # <--- GLUE FLAG (server will route to ChartLab)
    file = basename(res$path),
    chart = list(
      type = tolower(chart_type),             # "hist"|"bar"|"line"|"scatter"|"box"|"area"
      mapping = list(x = x, y = y, group = group),
      params = list(
        agg = agg, bins = bins, top_n = top_n,
        stack = stack, donut = donut, orientation = orientation, smooth = smooth
      ),
      data = as.data.frame(subset_dt),
      schema = as.list(schema),
      n = nrow(subset_dt)
    ),
    message = "Grafik verileri hazırlandı; ChartLab'a iletildi."
  )
}

# ==================================
# Tool 5: analyze_and_visualize (YENİ - R-First Yaklaşımı)
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
      cat("[SMART_MATCH] '", col_name, "' -> '", matched, "'\n", sep = "")
      return(matched)
    }

    # Tip ipucu ile eşleştirme (örn: sayısal sütun gerekiyorsa)
    if (col_type_hint == "numeric") {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        # Sütun adında arama terimi var mı kontrol et
        for (nc in num_cols) {
          if (grepl(tolower(col_name), tolower(nc), fixed = TRUE) ||
              grepl(tolower(nc), tolower(col_name), fixed = TRUE)) {
            cat("[SMART_MATCH] Sayısal tip eşleşmesi: '", col_name, "' -> '", nc, "'\n", sep = "")
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
            cat("[SMART_MATCH] Kategorik tip eşleşmesi: '", col_name, "' -> '", cc, "'\n", sep = "")
            return(cc)
          }
        }
      }
    }

    NULL
  }

  # --- 1. FİLTRELEME (filter_column ve filter_value varsa) ---
  if (!is.null(filter_column) && nzchar(filter_column) &&
      !is.null(filter_value) && nzchar(filter_value)) {

    # Akıllı sütun eşleştirme
    resolved_filter_column <- smart_resolve_column(filter_column, "categorical")

    if (is.null(resolved_filter_column)) {
      # Sütun bulunamadı - mevcut sütunları ve değerlerini göster
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
          filter_column, paste(col_info, collapse = "\n")
        ),
        ok = FALSE
      ))
    }

    # Çözülen sütun adını kullan
    filter_column <- resolved_filter_column
 
    # Türkçe: Büyük/küçük harf duyarsız filtreleme
    col_vals <- dt[[filter_column]]
    if (is.character(col_vals) || is.factor(col_vals)) {
      filter_mask <- grepl(filter_value, as.character(col_vals), ignore.case = TRUE)
    } else {
      # Türkçe: Sayısal sütun için tam eşleşme
      filter_val_num <- suppressWarnings(as.numeric(filter_value))
      if (!is.na(filter_val_num)) {
        filter_mask <- col_vals == filter_val_num
      } else {
        filter_mask <- rep(FALSE, nrow(dt))
      }
    }
 
    dt <- dt[filter_mask, ]
 
    if (nrow(dt) == 0) {
      return(list(
        result = sprintf("### Sonuç Yok\n'%s' sütununda '%s' değeri bulunamadı.",
                         filter_column, filter_value),
        ok = TRUE
      ))
    }
 
    result_text <- sprintf("**Filtre:** %s = '%s' (%d kayıt)\n\n",
                           filter_column, filter_value, nrow(dt))
  }
 
  # --- 2. İSTATİSTİK HESAPLAMA (R yapıyor, AI değil!) ---
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
    # Türkçe: Genel özet
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
      result_text <- paste0(result_text,
        sprintf("### Dosya Özeti: %s\n", display_name),
        sprintf("- **Toplam Satır:** %d\n", nrow(dt)),
        sprintf("- **Toplam Sütun:** %d\n\n", ncol(dt)),
        "#### Sayısal Sütun İstatistikleri (R tarafından hesaplandı)\n",
        helpers_mcp_tools$create_md_table(summary_df)
      )
      chart_data <- summary_df
    } else {
      result_text <- paste0(result_text,
        sprintf("### Dosya Özeti: %s\n", display_name),
        sprintf("- **Toplam Satır:** %d\n", nrow(dt)),
        sprintf("- **Toplam Sütun:** %d\n", ncol(dt)),
        sprintf("- **Sütunlar:** %s\n", paste(available_cols, collapse = ", "))
      )
    }
 
  } else if (analysis_type == "filtered_stats") {
    # Türkçe: Filtrelenmiş veri üzerinde istatistik
    if (is.null(stat_column) || !nzchar(stat_column)) {
      # Türkçe: stat_column belirtilmemişse ilk sayısal sütunu kullan
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      if (length(num_cols) > 0) {
        stat_column <- num_cols[1]
      } else {
        return(list(error = "Sayısal sütun bulunamadı.", ok = FALSE))
      }
    } else {
      # Akıllı sütun eşleştirme
      resolved_stat_column <- smart_resolve_column(stat_column, "numeric")
      if (!is.null(resolved_stat_column)) {
        stat_column <- resolved_stat_column
      }
    }

    if (!(stat_column %in% available_cols)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      return(list(
        error = sprintf("İstatistik sütunu '%s' bulunamadı.\nMevcut sayısal sütunlar: %s",
                        stat_column, paste(num_cols, collapse = ", ")),
        ok = FALSE
      ))
    }

    vals <- dt[[stat_column]]
    if (!is.numeric(vals)) {
      return(list(error = sprintf("'%s' sütunu sayısal değil.", stat_column), ok = FALSE))
    }

    stat_value <- stat_fun(vals)

    result_text <- paste0(result_text,
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
    # Türkçe: Gruplandırılmış istatistik (örn: departman bazında ortalama)
    if (is.null(group_column) || !nzchar(group_column)) {
      # Kategorik sütun yoksa hata ver
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      if (length(cat_cols) > 0) {
        return(list(
          error = sprintf("group_column parametresi gerekli.\nMevcut kategorik sütunlar: %s", paste(cat_cols, collapse = ", ")),
          ok = FALSE
        ))
      } else {
        return(list(error = "group_column parametresi gerekli ve kategorik sütun bulunamadı.", ok = FALSE))
      }
    }

    # Akıllı sütun eşleştirme - group_column
    resolved_group_column <- smart_resolve_column(group_column, "categorical")
    if (!is.null(resolved_group_column)) {
      group_column <- resolved_group_column
    }

    if (!(group_column %in% available_cols)) {
      cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]
      return(list(
        error = sprintf("Gruplama sütunu '%s' bulunamadı.\nMevcut kategorik sütunlar: %s",
                        group_column, paste(cat_cols, collapse = ", ")),
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
      # Akıllı sütun eşleştirme - stat_column
      resolved_stat_column <- smart_resolve_column(stat_column, "numeric")
      if (!is.null(resolved_stat_column)) {
        stat_column <- resolved_stat_column
      }
    }

    if (!(stat_column %in% available_cols)) {
      num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
      return(list(
        error = sprintf("İstatistik sütunu '%s' bulunamadı.\nMevcut sayısal sütunlar: %s",
                        stat_column, paste(num_cols, collapse = ", ")),
        ok = FALSE
      ))
    }
 
    # Türkçe: R ile gruplandırılmış hesaplama
    grouped_result <- aggregate(
      dt[[stat_column]],
      by = list(Grup = dt[[group_column]]),
      FUN = stat_fun
    )
    names(grouped_result) <- c(group_column, paste0(stat_label, "_", stat_column))
 
    # Türkçe: Sırala (büyükten küçüğe)
    grouped_result <- grouped_result[order(grouped_result[[2]], decreasing = TRUE), ]
 
    result_text <- paste0(result_text,
      sprintf("### %s Bazında %s: %s\n\n", group_column, stat_label, stat_column),
      helpers_mcp_tools$create_md_table(grouped_result),
      sprintf("\n\n_(Bu değerler R tarafından %d kayıt üzerinden hesaplandı)_", nrow(dt))
    )
 
    chart_data <- grouped_result
 
  } else if (analysis_type == "chart") {
    # Türkçe: Sadece grafik isteniyor
    # prepare_chart_data'ya yönlendir
    return(helpers_mcp_tools$prepare_chart_data(
      file_name = file_name,
      chart_type = chart_type %||% "bar",
      x = group_column,
      y = stat_column,
      filter_sql = if (!is.null(filter_column) && !is.null(filter_value)) {
        sprintf("\"%s\" = '%s'", filter_column, filter_value)
      } else NULL,
      agg = stat_function,
      session = session
    ))
  }
 
  # --- 4. GRAFİK EKLENSİN Mİ? ---
  chart_spec <- NULL
  if (!is.null(chart_type) && nzchar(chart_type) && !is.null(chart_data) && nrow(chart_data) > 0) {
    # Türkçe: Grafik oluştur
    chart_spec <- list(
      type = helpers_mcp_tools$normalize_chart_type(chart_type),
      mapping = list(
        x = names(chart_data)[1],
        y = names(chart_data)[2]
      ),
      params = list(agg = NULL),  # Türkçe: Zaten agregasyon yapıldı
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
  } else {
    return(list(
      ok = TRUE,
      result = result_text
    ))
  }
}
 
# ==================================
# Tool 6: get_distinct_values
# ==================================
helpers_mcp_tools$get_distinct_values <- function(file_name, column, limit = 50, session = NULL) {
  file_name <- helpers_mcp_tools$auto_file_name(file_name, session)
  res <- helpers_mcp_tools$resolve_file_argument(file_name, session)
  if (!isTRUE(res$ok)) return(list(error = res$error))
  
  if (is.null(column) || !nzchar(column)) return(list(error = "column parametresi boş"))

  path <- res$path
  dt <- tryCatch({
    data.table::as.data.table(helpers_mcp_tools$safe_read_excel_table(path))
  }, error = function(e) e)
  
  if (inherits(dt, "error")) return(list(error = sprintf("Dosya okunamadı: %s", dt$message)))

  if (!(column %in% names(dt))) {
    return(list(error = sprintf("Sütun '%s' bulunamadı. Mevcut: %s", column, paste(names(dt), collapse=", "))))
  }

  vals <- unique(dt[[column]])
  vals <- vals[!is.na(vals)]
  count <- length(vals)
  
  # Return top N
  shown_vals <- head(sort(vals), limit)
  
  display_name <- res$display %||% basename(path)
  
  msg <- paste0(
    "### Benzersiz Değerler: ", column, " (", display_name, ")\n",
    "- **Toplam Benzersiz Sayı:** ", count, "\n",
    "- **Listelenen (İlk ", length(shown_vals), "):** ", paste(shown_vals, collapse = ", ")
  )
  
  if (count > limit) {
    msg <- paste0(msg, "\n\n_(Liste çok uzun olduğu için ilk ", limit, " kayıt gösterildi. Tam liste için SQL kullanabilirsiniz.)_")
  }
  
  list(result = msg)
}

# ============================
# Tool router
# ============================
helpers_mcp_tools$execute_parsed_tool <- function(tc, session = NULL) {
  fn   <- tc$function_name %||% tc$name %||% tc$tool %||% tc$action
  args <- helpers_mcp_tools$normalize_args(tc$arguments %||% tc$parameters %||% list())

  if (is.null(fn) || !nzchar(fn)) return(list(error = "Araç adı boş"))

	switch(tolower(fn),
	  "analyze_uploaded_file"   = helpers_mcp_tools$analyze_uploaded_file(args$file_name, session),
	  "get_column_statistics"   = helpers_mcp_tools$get_column_statistics(args$file_name, args$column, session),
	  "get_distinct_values"     = helpers_mcp_tools$get_distinct_values(args$file_name, args$column, args$limit %||% 50, session),
	  "get_column_stats"        = helpers_mcp_tools$get_column_statistics(args$file_name, args$column, session),
	  "sql_query_uploaded_file" = helpers_mcp_tools$sql_query_uploaded_file(args$file_name, args$sql, session),
	  "analyze_and_visualize"   = helpers_mcp_tools$analyze_and_visualize(
		file_name      = args$file_name,
		analysis_type  = args$analysis_type %||% "summary",
		filter_column  = args$filter_column,
		filter_value   = args$filter_value,
		group_column   = args$group_column,
		stat_column    = args$stat_column,
		stat_function  = args$stat_function %||% "mean",
		chart_type     = args$chart_type,
		session        = session
	  ),
	  "prepare_chart_data"      = helpers_mcp_tools$prepare_chart_data(
		file_name   = args$file_name,
		chart_type  = args$chart_type,
		x           = args$x %||% args$xlabel %||% args$x_col,
		y           = args$y %||% args$ylabel %||% args$y_col,
		group       = args$group %||% args$color %||% args$hue,
		agg         = args$agg,
		bins        = args$bins,
		top_n       = args$top_n,
		stack       = args$stack,        # Türkçe yorum: Yığınlama modu (normal/percent)
		donut       = args$donut,        # Türkçe yorum: Pasta grafiğini halka yap
		orientation = args$orientation,  # Türkçe yorum: Bar grafiği yönü (v/h)
		smooth      = args$smooth,       # Türkçe yorum: Çizgi yumuşatma
		filter_sql  = args$filter_sql,
		limit       = args$limit %||% 5000,
		session     = session
	  ),
	  {
		list(error = sprintf("Bilinmeyen araç: %s", fn))
	  }
	)
}

# ============================
# OpenAI tools schema
# ============================
helpers_mcp_tools$get_openai_tools <- function(session = NULL) {
  list(
    tools = list(
      list(
        type = "function",
        `function` = list(
          name = "analyze_uploaded_file",
          description = "Yüklü Excel dosyasının temel özetini çıkarır (satır, sütun, sütun adları, sayısal özet).",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string",
                               description = "Sohbetteki dosya jetonu (file_123...) veya gerçek dosya adı (dummy.xlsx).")
            ),
            required = list("file_name")
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "get_column_statistics",
          description = "Belirli bir sütunun istatistiklerini döndürür (numeric: ort, medyan, min, max; categorical: frekans).",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya jetonu veya adı."),
              column    = list(type = "string", description = "İstatistikleri istenen sütun adı.")
            ),
            required = list("file_name", "column")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "sql_query_uploaded_file",
          description = "SQL ile filtreleme, sıralama, gruplama ve 'Top N' listeleme yapar. Sıralama (ORDER BY) ve listeleme soruları için bunu kullan. Tablo adı: t.",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya jetonu veya adı."),
              sql       = list(type = "string", description = "DuckDB uyumlu SQL; tablo adı 't'. Örnek: SELECT * FROM t ORDER BY Age DESC LIMIT 10")
            ),
            required = list("file_name", "sql")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "get_distinct_values",
          description = "Bir sütundaki benzersiz (unique) değerleri listeler. Filtreleme yapmadan önce kategori isimlerini öğrenmek için kullan.",
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya adı."),
              column    = list(type = "string", description = "Benzersiz değerleri istenen sütun."),
              limit     = list(type = "integer", description = "Maksimum kaç değer dönsün (varsayılan 50).")
            ),
            required = list("file_name", "column")
          )
        )
      ),
      # Türkçe: YENİ - R-First yaklaşımı ile filtrelenmiş analiz ve grafik
      list(
        type = "function",
        `function` = list(
          name = "analyze_and_visualize",
          description = paste0(
            "FİLTRELENMİŞ İSTATİSTİK VE GRAFİK için bu aracı kullan! ",
            "Kullanıcı belirli bir gruba/kategoriye göre ortalama, toplam vb. istiyorsa bu araç ZORUNLU. ",
            "Örnek: 'IT departmanının ortalama maaşı', 'Erkeklerin çalışma saati toplamı'. ",
            "R tarafından GERÇEK hesaplama yapılır, AI değer UYDURAMAZ!"
          ),
          parameters = list(
            type = "object",
            properties = list(
              file_name = list(type = "string", description = "Dosya adı"),
              analysis_type = list(
                type = "string",
                description = paste0(
                  "Analiz tipi: ",
                  "'summary' (genel özet), ",
                  "'filtered_stats' (filtrelenmiş tek istatistik), ",
                  "'grouped_stats' (gruplandırılmış istatistik), ",
                  "'chart' (sadece grafik)"
                )
              ),
              filter_column = list(type = "string", description = "Filtreleme yapılacak sütun (örn: 'Departman', 'Cinsiyet')"),
              filter_value = list(type = "string", description = "Filtreleme değeri (örn: 'IT', 'Erkek')"),
              group_column = list(type = "string", description = "Gruplama sütunu (grouped_stats için). Örn: 'Departman'"),
              stat_column = list(type = "string", description = "İstatistik hesaplanacak sayısal sütun (örn: 'Maas', 'CalismaSaati')"),
              stat_function = list(type = "string", description = "İstatistik fonksiyonu: 'mean', 'sum', 'count', 'median', 'min', 'max'"),
              chart_type = list(type = "string", description = "Grafik eklensin mi? 'bar', 'pie', 'line', 'area', 'scatter', 'pareto', 'hist'. Boş bırakırsan grafik çizilmez.")
            ),
            required = list("file_name", "analysis_type")
          )
        )
      ),
	  list(
        type = "function",
        `function` = list(
          name = "prepare_chart_data",
          description = paste0(
            "GENEL GRAFİK ÇİZER (filtresiz). Dosyanın TAMAMINI görselleştirir. ",
            "Eksenleri OTOMATİK seçer. Sadece file_name ve chart_type ver. ",
            "NOT: Filtrelenmiş grafik istiyorsan analyze_and_visualize kullan!"
          ),
          parameters = list(
            type = "object",
            properties = list(
              file_name  = list(type = "string", description = "Dosya adı (örn: 'veri.xlsx')"),
              chart_type = list(type = "string", description = "Grafik türü: 'hist', 'bar', 'pie', 'donut', 'line', 'area', 'scatter', 'pareto'"),
              x          = list(type = "string", description = "X ekseni sütunu (OPSİYONEL - boş bırakırsan otomatik seçilir)"),
              y          = list(type = "string", description = "Y ekseni sütunu (OPSİYONEL). Çoklu seri için: 'Col1,Col2'"),
              group      = list(type = "string", description = "Gruplama sütunu (OPSİYONEL)"),
              agg        = list(type = "string", description = "Agregasyon: 'sum', 'mean', 'count' (OPSİYONEL - pie/bar için otomatik eklenir)"),
              bins       = list(type = "integer", description = "Histogram kutu sayısı (OPSİYONEL)"),
              top_n      = list(type = "integer", description = "En yüksek N kayıt (OPSİYONEL - pie için otomatik 10)"),
              stack      = list(type = "string", description = "Yığınlama: 'normal' veya 'percent' (OPSİYONEL)"),
              donut      = list(type = "boolean", description = "Pasta yerine halka (OPSİYONEL)"),
              orientation = list(type = "string", description = "Bar yönü: 'v' veya 'h' (OPSİYONEL)"),
              smooth     = list(type = "boolean", description = "Çizgi yumuşatma (OPSİYONEL)"),
              filter_sql = list(type = "string", description = "SQL WHERE filtresi (OPSİYONEL, tercih: analyze_and_visualize kullan)"),
              limit      = list(type = "integer", description = "Maksimum satır (OPSİYONEL)")
            ),
            required = list("file_name", "chart_type")
          )
        )
      )
    )
  )
}

# ============================
# Tool-use instruction prompt
# ============================
# Türkçe: Bu prompt TÜM modellere gönderilir. Açık ve model-agnostik olmalı.
# file_schema parametresi ile dosya şeması da eklenebilir.
helpers_mcp_tools$get_mcp_tools_prompt <- function(file_schema = NULL) {
  # Dosya şeması varsa başta ekle
  schema_section <- ""
  if (!is.null(file_schema) && nzchar(file_schema)) {
    schema_section <- paste0(
      "# \U0001F4CA YÜKLÜ DOSYA BİLGİSİ\n\n",
      file_schema, "\n\n",
      "---\n\n",
      "**ÖNEMLİ:** Yukarıdaki şemada gördüğün GERÇEK sütun isimlerini kullan!\n",
      "Kullanıcı Türkçe terim kullanırsa, şemadaki İngilizce karşılığını bul.\n",
      "Örnek: Kullanıcı 'departman' derse \U2192 şemada 'Department' sütununu kullan.\n\n",
      "---\n\n"
    )
  }

  paste0(
    schema_section,
    "# VERİ ANALİZİ VE GRAFİK ARAÇLARI KULLANIM KILAVUZU\n\n",

    "Sen bir Excel/CSV veri analisti asistanısın. Araçları ZORUNLU olarak kullanmalısın.\n",
    "ASLA kendi başına istatistik HESAPLAMA veya değer UYDURMA! Tüm hesaplamalar R tarafından yapılır.\n\n",

    "## \U000026A0\U0000FE0F SÜTUN İSİMLERİ İÇİN KRİTİK KURAL:\n",
    "1. Yukarıdaki dosya şemasında GERÇEK sütun isimlerini gör\n",
    "2. Kullanıcının Türkçe terimi ile şemadaki İngilizce sütunu eşleştir\n",
    "3. Araç çağrılarında SADECE şemadaki gerçek sütun isimlerini kullan\n",
    "4. Şemada olmayan sütun ismi KULLANMA - hata alırsın!\n\n",

    "## KRİTİK KURAL: HANGİ ARACI NE ZAMAN KULLAN?\n\n",

    "### \U00000031\U0000FE0F\U000020E3 FİLTRELENMİŞ İSTATİSTİK İSTENİYORSA \U2192 `analyze_and_visualize`\n",
    "Kullanıcı belirli bir kategoriye göre ortalama, toplam, sayı istiyorsa BU ARACI KULLAN!\n\n",

    "**Örnekler:**\n",
    "- 'IT departmanının ortalama maaşı' \U2192 analyze_and_visualize(filter_column='Department', filter_value='IT', stat_function='mean')\n",
    "- 'Erkeklerin toplam çalışma saati' \U2192 analyze_and_visualize(filter_column='Gender', filter_value='Male', stat_function='sum')\n",
    "- 'Departman bazında ortalama maaş' \U2192 analyze_and_visualize(analysis_type='grouped_stats', group_column='Departman', stat_function='mean')\n",
    "- 'Satış ekibinin performans grafiği' \U2192 analyze_and_visualize(filter_column='Departman', filter_value='Satış', chart_type='bar')\n\n",
 
    "### \U00000032\U0000FE0F\U000020E3 GENEL GRAFİK İSTENİYORSA (filtresiz) \U2192 `prepare_chart_data`\n",
    "Tüm veriyi görselleştirmek için bu aracı kullan. Eksenler OTOMATİK seçilir.\n\n",
 
    "**Örnekler:**\n",
    "- 'histogram çiz' \U2192 prepare_chart_data(chart_type='hist')\n",
    "- 'bar grafiği' \U2192 prepare_chart_data(chart_type='bar')\n",
    "- 'pasta grafiği' \U2192 prepare_chart_data(chart_type='pie')\n",
    "- 'çizgi grafiği' \U2192 prepare_chart_data(chart_type='line')\n",
    "- 'scatter plot' \U2192 prepare_chart_data(chart_type='scatter')\n\n",
 
    "### \U00000033\U0000FE0F\U000020E3 SQL SORGUSU GEREKİYORSA \U2192 `sql_query_uploaded_file`\n",
    "Karmaşık filtreleme, sıralama, gruplama için SQL kullan. Tablo adı: 't'\n\n",
 
    "**Örnekler:**\n",
    "- 'En yüksek maaşlı 10 kişi' \U2192 sql_query_uploaded_file(sql='SELECT * FROM t ORDER BY Maas DESC LIMIT 10')\n",
    "- '2023 yılı kayıtları' \U2192 sql_query_uploaded_file(sql=\"SELECT * FROM t WHERE Yil = 2023\")\n\n",
 
    "### \U00000034\U0000FE0F\U000020E3 SÜTUN DEĞERLERİNİ ÖĞRENMEK İÇİN \U2192 `get_distinct_values`\n",
    "Hangi kategoriler var bilmiyorsan önce bu aracı çağır.\n\n",
 
    "## GRAFİK TÜRLERİ SÖZLÜĞÜ:\n",
    "| Kullanıcı Terimi | chart_type |\n",
    "|------------------|------------|\n",
    "| histogram, dağılım | 'hist' |\n",
    "| bar, çubuk, sütun | 'bar' |\n",
    "| pasta, pie | 'pie' |\n",
    "| halka, donut | 'donut' |\n",
    "| çizgi, line, trend | 'line' |\n",
    "| alan, area | 'area' |\n",
    "| scatter, saçılım | 'scatter' |\n",
    "| pareto | 'pareto' |\n\n",

    "## GRAFİK TÜRÜ SEÇİMİ İÇİN EK KURALLAR:\n",
    "- Kullanıcı 'çizgi grafiği' diyorsa ASLA 'scatter' seçme; chart_type='line' kullan.\n",
    "- 'scatter' sadece iki sayısal sütun arasındaki ilişki/korelasyon için kullanılmalı.\n",
    "- Kullanıcı 'alan grafiği' diyorsa chart_type='area' kullan.\n",
    "- Kullanıcı 'pareto' diyorsa chart_type='pareto' kullan.\n\n",

    "## ZORUNLU KURALLAR:\n",
    "1. \U0000274C ASLA kendi başına değer UYDURMA! Araç kullan.\n",
    "2. \U0000274C ASLA sütun adı TAHMIN ETME! Araç otomatik seçer veya get_distinct_values ile öğren.\n",
    "3. \U00002705 Filtrelenmiş istatistik = analyze_and_visualize\n",
    "4. \U00002705 Genel grafik = prepare_chart_data\n",
    "5. \U00002705 Her grafik isteği için EN AZ BİR araç çağır\n",
    "6. \U00002705 Birden fazla grafik istenirse birden fazla araç çağır\n\n",
 
    "## ARAÇ ÇAĞIRMA FORMATI:\n",
    "Her araç çağrısı şu formatta olmalı:\n",
    "```json\n",
    "{\"name\": \"araç_adı\", \"arguments\": {\"param1\": \"değer1\", \"param2\": \"değer2\"}}\n",
    "```\n\n",
 
    "ŞİMDİ kullanıcının talebine göre UYGUN ARACI ÇAĞıR!"
  )
}

# Lightweight SQL extractor (so plain SELECT blocks are still executed)
helpers_mcp_tools$extract_sql_from_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return(NULL)

  # Prefer fenced sql blocks
  block_rgx <- "```sql\\s*([\\s\\S]*?)```"
  m <- regexpr(block_rgx, text, perl = TRUE)
  if (m[1] != -1) {
    sql <- regmatches(text, m)[1]
    sql <- gsub("^```sql", "", sql)
    sql <- gsub("```$", "", sql)
    return(trimws(sql))
  }

  # Fallback: first SELECT ... pattern
  plain_sel <- regexpr("(?is)select\\s+[\\s\\S]+?($|;)", text, perl = TRUE)
  if (plain_sel[1] != -1) {
    sql <- regmatches(text, plain_sel)[1]
    sql <- sub(";+$", "", sql)
    return(trimws(sql))
  }

  NULL
}

# ============================
# Parse textual tool calls
# ============================
helpers_mcp_tools$parse_tool_calls_from_text <- function(text) {
  if (is.null(text) || !nzchar(text)) return(list())
  out <- list()

  # 1) <tool_call> ... </tool_call>
  tc_blocks <- gregexpr("<tool_call>(.*?)</tool_call>", text, perl = TRUE)
  if (tc_blocks[[1]][1] != -1) {
    blocks <- regmatches(text, tc_blocks)[[1]]
    blocks <- gsub("^<tool_call>|</tool_call>$", "", blocks)
    for (blk in blocks) {
      try({
        obj  <- jsonlite::fromJSON(blk, simplifyVector = FALSE)
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }, silent = TRUE)
    }
  }

  # 2) Inline JSON {"name|tool|action": "...", "arguments|parameters": {...}}
  json_pat <- paste0(
    "\\{\\s*\"(tool|name|action)\"\\s*:\\s*\"[^\"]+\"[\\s\\S]*?",
    "\"(arguments|parameters)\"\\s*:\\s*\\{[\\s\\S]*?\\}\\s*\\}"
  )
  rgx <- gregexpr(json_pat, text, perl = TRUE)
  if (rgx[[1]][1] != -1) {
    objs <- regmatches(text, rgx)[[1]]
    for (o in objs) {
      try({
        obj  <- jsonlite::fromJSON(o, simplifyVector = FALSE)
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }, silent = TRUE)
    }
  }

  # 3) Whole message is JSON
  if (length(out) == 0) {
    try({
      obj <- jsonlite::fromJSON(text, simplifyVector = FALSE)
      if (is.list(obj) && (!is.null(obj$name) || !is.null(obj$tool) || !is.null(obj$action))) {
        fn   <- obj$name %||% obj$tool %||% obj$action
        args <- obj$arguments %||% obj$parameters %||% list()
        if (is.character(args)) {
          args <- tryCatch(jsonlite::fromJSON(args, simplifyVector = FALSE), error = function(e) list())
        }
        out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
      }
    }, silent = TRUE)
  }

  # 4) Plain SQL without explicit tool markup
  if (length(out) == 0) {
    sql_candidate <- helpers_mcp_tools$extract_sql_from_text(text)
    if (!is.null(sql_candidate) && nzchar(sql_candidate)) {
      out[[length(out) + 1]] <- list(
        function_name = "sql_query_uploaded_file",
        arguments = list(sql = sql_candidate)
      )
    }
  }
  
  out
}

# ============================
# Public wrappers (used by global.R)
# ============================
get_openai_tools              <- function(session = NULL) helpers_mcp_tools$get_openai_tools(session)
get_mcp_tools_prompt          <- function(file_schema = NULL) helpers_mcp_tools$get_mcp_tools_prompt(file_schema)
extract_mcp_file_schema       <- function(file_name, session = NULL) helpers_mcp_tools$extract_mcp_file_schema(file_name, session)
find_matching_column          <- function(search_term, available_columns, context = NULL) helpers_mcp_tools$find_matching_column(search_term, available_columns, context)
parse_tool_calls_from_text    <- function(x)              helpers_mcp_tools$parse_tool_calls_from_text(x)
execute_parsed_tool           <- function(tc, session=NULL) helpers_mcp_tools$execute_parsed_tool(tc, session)
register_session_file         <- function(session, token, path, nm=NULL) helpers_mcp_tools$register_uploaded_file(session, token, path, nm)
reset_session_file_registry   <- function(session = NULL) helpers_mcp_tools$reset_session_file_registry(session)
environment(helpers_mcp_tools$analyze_uploaded_file)   <- helpers_mcp_tools
environment(helpers_mcp_tools$get_column_statistics)   <- helpers_mcp_tools
environment(helpers_mcp_tools$sql_query_uploaded_file) <- helpers_mcp_tools
environment(helpers_mcp_tools$prepare_chart_data)      <- helpers_mcp_tools
environment(helpers_mcp_tools$analyze_and_visualize)   <- helpers_mcp_tools
environment(helpers_mcp_tools$resolve_file_argument)   <- helpers_mcp_tools
environment(helpers_mcp_tools$normalize_excel_path)    <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_excel_table)   <- helpers_mcp_tools
environment(helpers_mcp_tools$safe_read_table_generic) <- helpers_mcp_tools
environment(helpers_mcp_tools$get_default_file_name)   <- helpers_mcp_tools
environment(helpers_mcp_tools$auto_file_name)          <- helpers_mcp_tools
environment(helpers_mcp_tools$extract_mcp_file_schema) <- helpers_mcp_tools
environment(helpers_mcp_tools$find_matching_column)    <- helpers_mcp_tools