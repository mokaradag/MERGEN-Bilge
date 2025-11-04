# R/helpers_mcp_rdata_tools.R

get_mcp_rdata_tools <- function() {
  list(
    # Mevcut araçlar
    list(
      name = "rdata_search",
      description = "RData katalogunda tablo/nesne ara",
      parameters = list(
        text = list(type = "string", description = "Arama terimi"),
        limit = list(type = "integer", description = "Maksimum sonuç sayısı", default = 10)
      )
    ),
    
    list(
      name = "rdata_sql",
      description = "DuckDB SQL sorgusu çalıştır (fact_universe tablosu üzerinden). SÜTUN ADLARINI TAM OLARAK YAZIN!",
      parameters = list(
        sql = list(type = "string", description = "SELECT sorgusu"),
        preview_rows = list(type = "integer", description = "Önizleme satır sayısı", default = 1000)
      )
    ),
    
    # ===== YENİ ARAÇLAR =====
    list(
      name = "rdata_column_search",
      description = "Sütun adlarında arama yap. Hangi sütunların olduğunu öğrenmek için MUTLAKA kullan!",
      parameters = list(
        query = list(type = "string", description = "Aranacak kelime (örn: 'iscilik', 'proje', 'yil')"),
        limit = list(type = "integer", description = "Maksimum sonuç", default = 10)
      )
    ),
    
    list(
      name = "rdata_smart_query",
      description = "Akıllı sorgu: boyut ve metrik adlarını (yaklaşık) ver, SQL otomatik oluşturulur",
      parameters = list(
        dimensions = list(type = "array", items = list(type = "string"), 
                         description = "Boyut sütunları (örn: ['proje', 'yil'])"),
        metrics = list(type = "array", items = list(type = "string"),
                      description = "Metrik sütunları (örn: ['iscilik', 'kalan'])"),
        filters = list(type = "object", description = "Filtreler (örn: {yil: 2024})"),
        limit = list(type = "integer", default = 1000)
      )
    ),
	   
    list(
      name = "rdata_metrics",
      description = "Projeye özel temel metrikler",
      parameters = list(
        proje_adi = list(type = "string", description = "Proje adı"),
        proje_kodu = list(type = "string", description = "Proje kodu")
      )
    )
  )
}

execute_mcp_rdata_tool <- function(tc, session=NULL) {
  nm_raw <- tc$name
  args   <- tc$args %||% list()
  nm     <- gsub("\\.", "_", nm_raw)  # isim normalizasyonu

  # Çağrı kimliği ve kapsam temizliği
  # Türkçe yorum: Her çağrıyı ayırt etmek ve loglamak için benzersiz kimlik üret.
  req_id <- sprintf("req_%d_%05d", as.integer(Sys.time()), sample.int(1e5, 1))
  cat("[RDATA_TOOL]", req_id, " name=", nm, " raw_args=", paste(names(args), collapse=","), "\n")

  # Argüman yardımcıları — LLM'in dizi/tekil göndermesine dayanıklı
  scalar_chr <- function(x, default="") {
    if (is.null(x)) return(default)
    x <- unlist(x, recursive = TRUE, use.names = FALSE)
    if (!length(x)) return(default)
    as.character(x[[length(x)]])
  }
  scalar_int <- function(x, default=0L) {
    if (is.null(x)) return(default)
    x <- as.integer(unlist(x, recursive = TRUE, use.names = FALSE))
    if (!length(x)) return(default)
    as.integer(x[[length(x)]])
  }
  scalar_lgl <- function(x, default=FALSE) {
    if (is.null(x)) return(default)
    x <- as.logical(unlist(x, recursive = TRUE, use.names = FALSE))
    if (!length(x)) return(default)
    isTRUE(x[[length(x)]])
  }

  # Geçici durum sıfırla (potansiyel birleşmeleri engelle)
  if (exists(".chart_store_env", envir = helpers_rdata_lake, inherits = FALSE)) {
    env <- get(".chart_store_env", envir = helpers_rdata_lake)
    if (is.environment(env)) rm(list = ls(env, all.names = TRUE), envir = env)
  }
  helpers_rdata_lake$.chart_store_env <- new.env(parent = emptyenv())
  helpers_rdata_lake$.current_request_id <- req_id  # Türkçe: aktif çağrı id

  if (identical(nm, "rdata_ask")) {
    # Türkçe: Soru → (mümkünse) derlenmiş SQL → sonuç; daima standart yapı döndür
    q   <- scalar_chr(args$question, "")
    lim <- scalar_int(args$limit, 100)
    cat("[RDATA_TOOL]", req_id, " rdata_ask question=", encodeString(q), " limit=", lim, "\n")
    sql_to_run <- NULL
    comp <- try(helpers_rdata_lake$rdata_compile_sql(q, lim), silent = TRUE)
    if (!inherits(comp, "try-error") && is.list(comp) && nzchar(comp$sql %||% "")) {
      sql_to_run <- comp$sql
    } else {
      con <- helpers_rdata_lake$db_connect(readonly = TRUE)
      on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
      sql_to_run <- helpers_rdata_lake$compose_dynamic_fallback_sql(con, limit = lim)
    }
    return(helpers_rdata_lake$rdata_sql(sql_to_run, preview_rows = lim))

} else if (identical(nm, "rdata_sql")) {
    # Türkçe: Doğrudan SQL çalıştır
    sql_in <- scalar_chr(args$sql, "")
	# Türkçe: Varsayılanı büyüt, 'all' için büyük değer kullan
	lim_in <- scalar_int(args$preview_rows %||% args$limit, 100000)
    
    cat("\n========== [RDATA_TOOL] BAŞLANGIÇ ==========\n")
    cat("[RDATA_TOOL]", req_id, "rdata_sql çağrıldı\n")
    cat("[RDATA_TOOL] SQL uzunluğu:", nchar(sql_in), "karakter\n")
    cat("[RDATA_TOOL] Limit:", lim_in, "\n")
    cat("[RDATA_TOOL] SQL:\n", sql_in, "\n")
    
    # Türkçe: SQL'i çalıştır ve sonucu al
    result <- helpers_rdata_lake$rdata_sql(sql_in, preview_rows = lim_in)
	    
	# Türkçe: 'preview' varsa 'sonuç_önizleme' takma adını da ekle
    if (is.list(result) && is.data.frame(result$preview) && is.null(result$`sonuç_önizleme`)) {
      result$`sonuç_önizleme` <- result$preview
    }

    # Türkçe: Sonucu detaylı logla
    cat("\n[RDATA_TOOL] SONUÇ YAPISI:\n")
    cat("[RDATA_TOOL] Result class:", class(result), "\n")
    cat("[RDATA_TOOL] Result names:", paste(names(result), collapse=", "), "\n")
    
    if (is.list(result)) {
      if (!is.null(result$error)) {
        cat("[RDATA_TOOL] *** HATA VAR ***:", result$error, "\n")
      }
      
      df <- result$`sonuç_önizleme` %||% result$preview
      if (is.data.frame(df)) {
        cat("[RDATA_TOOL] DataFrame bulundu!\n")
        cat("[RDATA_TOOL] Satır sayısı:", nrow(df), "\n")
        cat("[RDATA_TOOL] Sütun sayısı:", ncol(df), "\n")
        cat("[RDATA_TOOL] Sütunlar:", paste(colnames(df), collapse=", "), "\n")
        
        if (nrow(df) > 0) {
          cat("\n[RDATA_TOOL] İLK 3 SATIR:\n")
          print(head(df, 3))
          
          # Türkçe: Veri gerçek mi yoksa NA'larla dolu mu?
          na_pct <- mean(is.na(df)) * 100
          cat("\n[RDATA_TOOL] NA Yüzdesi: %.1f%%\n", na_pct)
          
          if (na_pct > 50) {
            cat("[RDATA_TOOL] *** UYARI: Verinin yarısından fazlası NA! ***\n")
          }
        } else {
          cat("[RDATA_TOOL] *** UYARI: DataFrame BOŞ (0 satır) ***\n")
        }
      } else {
        cat("[RDATA_TOOL] *** UYARI: sonuç_önizleme veya preview DataFrame değil! ***\n")
        cat("[RDATA_TOOL] Class:", class(df), "\n")
      }
    }
    
    cat("========== [RDATA_TOOL] BİTİŞ ==========\n\n")
    
    return(result)

  } else if (identical(nm, "rdata_chart")) {
    # Türkçe: SQL → veri → ChartLab tanımı
    res <- helpers_rdata_lake$rdata_sql(args$sql %||% "", preview_rows = args$top_n %||% 25)
    df <- if (is.list(res) && is.data.frame(res$preview %||% res$`sonuç_önizleme`)) {
      res$preview %||% res$`sonuç_önizleme`
    } else data.frame()

    x_map <- if (!is.null(args$x)) as.character(unlist(args$x, use.names = FALSE))[1] else NULL
    y_map <- if (!is.null(args$y)) as.character(unlist(args$y, use.names = FALSE))[1] else NULL
    g_map <- if (!is.null(args$group)) as.character(unlist(args$group, use.names = FALSE))[1] else NULL

    spec <- list(
      type = as.character((args$type %||% "bar"))[1],
      data = df,
      mapping = list(x = x_map, y = y_map, group = g_map),
      params = list(top_n = as.integer(args$top_n %||% 25), orientation = as.character(args$orientation %||% "v")[1])
    )

    ref_id <- sprintf("sql_chart_%d_%05d", as.integer(Sys.time()), sample.int(1e5, 1))
    cat("[RDATA_TOOL]", req_id, " chart_ref=", ref_id, " x=", args$x, " y=", args$y, "\n")
    cs <- list(); cs[[ref_id]] <- spec
    return(list(
      content = paste0("```chartlab\n", jsonlite::toJSON(list(ref = ref_id), auto_unbox = TRUE), "\n```"),
      chart_store = cs
    ))

  } else if (identical(nm, "rdata_column_search")) {
    # Türkçe yorum: Sütun adında arama yap
    query <- scalar_chr(args$query, "")
    limit <- scalar_int(args$limit, 10)
    cat("[RDATA_TOOL]", req_id, " rdata_column_search query='", query, "' limit=", limit, "\n")

    con <- helpers_rdata_lake$db_connect(readonly = TRUE)
    on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

    if (exists("helpers_rdata_metadata", inherits = TRUE)) {
      results <- helpers_rdata_metadata$search_columns(con, query, limit)
      if (nrow(results) == 0) return(list(content = paste0("'", query, "' için sütun bulunamadı.")))

      lines <- c("Bulunan Sütunlar:\n")
      for (i in seq_len(nrow(results))) {
        r <- results[i, ]
        samples <- paste(head(unlist(r$sample_values), 3), collapse = ", ")
        lines <- c(lines, sprintf(
          "%d. **%s** (%s) - %s | Farklı değer: %d | Örnek: %s",
          i, r$column_name, r$data_type,
          if (r$is_metric) "METRİK" else "BOYUT",
          r$distinct_count,
          samples
        ))
      }
      return(list(content = paste(lines, collapse = "\n")))
    } else {
      return(list(content = "Metadata sistemi yüklenmemiş."))
    }

	} else if (identical(nm, "rdata_smart_query")) {
	  # Türkçe yorum: Boyut/metrik yaklaşık adlardan SQL üret
	  dimensions <- unlist(args$dimensions %||% list())
	  metrics    <- unlist(args$metrics %||% list())
	  filters    <- args$filters %||% list()
	  limit      <- scalar_int(args$limit, 100)
	  cat("[RDATA_TOOL]", req_id, " rdata_smart_query dims=", length(dimensions),
		  " mets=", length(metrics), " filters=", length(filters), "\n")

	  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
	  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

	  if (exists("helpers_rdata_metadata", inherits = TRUE)) {
		# Türkçe: Yaklaşık adları gerçek kolon adına çöz
		exact_dims <- character(0)
		for (d in dimensions) {
		  exact <- helpers_rdata_metadata$find_exact_column(con, d)
		  if (!is.null(exact)) {
			exact_dims <- c(exact_dims, exact)
			cat("[SMART_QUERY] '", d, "' -> '", exact, "'\n")
		  }
		}
		exact_mets <- character(0)
		for (m in metrics) {
		  exact <- helpers_rdata_metadata$find_exact_column(con, m)
		  if (!is.null(exact)) {
			exact_mets <- c(exact_mets, exact)
			cat("[SMART_QUERY] '", m, "' -> '", exact, "'\n")
		  }
		}
		if (!length(exact_dims) && !length(exact_mets)) {
		  return(list(content = "Belirtilen sütunlar bulunamadı. 'rdata_column_search' ile arama yapın."))
		}

		# SELECT
		select_parts <- c()
		if (length(exact_dims)) select_parts <- c(select_parts, paste0('"', exact_dims, '"', collapse = ", "))
		if (length(exact_mets)) {
		  # Türkçe: Tüm metrikleri DOUBLE'a zorlayıp SUM ile topla
		  agg_mets <- paste0('SUM(TRY_CAST("', exact_mets, '" AS DOUBLE)) AS "', exact_mets, '"', collapse = ", ")
		  select_parts <- c(select_parts, agg_mets)
		}
		select_clause <- paste(select_parts, collapse = ", ")

		# WHERE (kullanıcı filtreleri)
		where_parts <- character(0)
		if (length(filters)) {
		  for (fname in names(filters)) {
			fval <- filters[[fname]]
			exact_col <- helpers_rdata_metadata$find_exact_column(con, fname)
			if (!is.null(exact_col)) {
			  if (is.numeric(fval)) {
				where_parts <- c(where_parts, sprintf('"%s" = %s', exact_col, fval))
			  } else {
				where_parts <- c(where_parts, sprintf('"%s" = \'%s\'', exact_col, as.character(fval)[1]))
			  }
			}
		  }
		}

		# Türkçe: NA tuzağını engellemek için doğru kaynak tabloları öner ve uygula (kullanıcı 'source_table' vermediyse)
		has_user_source <- any(tolower(names(filters)) == "source_table")
		if (!has_user_source) {
		  st_candidates <- helpers_rdata_lake$suggest_source_tables_for(c(exact_dims, exact_mets))
		  if (length(st_candidates)) {
			q <- paste(sprintf("'%s'", gsub("'", "''", st_candidates)), collapse = ", ")
			where_parts <- c(where_parts, sprintf('"source_table" IN (%s)', q))
			cat("[SMART_QUERY] source_table filter injected: ", paste(st_candidates, collapse = ", "), "\n")
		  }
		}

		where_clause  <- if (length(where_parts)) paste("WHERE", paste(where_parts, collapse = " AND ")) else ""
		group_clause  <- if (length(exact_dims)) paste("GROUP BY", paste0('"', exact_dims, '"', collapse = ", ")) else ""
		order_clause  <- if (length(exact_mets)) paste0('ORDER BY "', exact_mets[1], '" DESC') else ""

		# Türkçe: Kullanıcı 'tümü/all' isterse LIMIT uygulama (limit <= 0 veya Inf kabul)
		limit_clause <- if (is.finite(limit) && limit > 0) sprintf("LIMIT %d", limit) else ""

		sql <- sprintf("
		  SELECT %s
		  FROM fact_universe
		  %s
		  %s
		  %s
		  %s
		", select_clause, where_clause, group_clause, order_clause, limit_clause)

		cat("[SMART_QUERY] SQL:\n", sql, "\n")
		res <- helpers_rdata_lake$rdata_sql(sql, preview_rows = limit)
		if (!is.null(res$error)) return(list(content = paste0("Sorgu hatası:\n", res$error)))

        # Türkçe: 'sonuç_önizleme' alanını da ekle (UI ve fallback'lar için)
        return(list(
          preview = res$preview,
          `sonuç_önizleme` = res$preview,
          sql_effective = res$sql_effective,
          row_count = res$row_count,
          column_count = res$column_count
        ))
	  } else {
		return(list(content = "Metadata sistemi yüklenmemiş."))
	  }
  }

  # Türkçe: Tanınmayan araç adı
  list(content = sprintf("Bilinmeyen RData aracı: %s", nm_raw))
}
