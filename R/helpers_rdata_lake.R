# R/helpers_rdata_lake.R
# -------------------------------------------------------------
# RData Lake: DuckDB tabanlı hızlı arama/sorgu katmanı
# -------------------------------------------------------------

suppressWarnings({
  library(DBI)
  library(duckdb)
  library(data.table)
  library(jsonlite)
  library(stringi)
  library(stringdist)
})

# Güvenli vektör erişimi - NULL veya geçersiz indeks durumlarını ele alır
safe_vector_access <- function(vec, index, default = NULL) {
  tryCatch({
    if (is.null(vec) || !is.atomic(vec) && !is.list(vec)) return(default)
    if (is.null(index) || !is.numeric(index) && !is.character(index)) return(default)
    if (length(vec) == 0) return(default)
    
    result <- vec[[index]]
    if (is.null(result)) return(default)
    return(result)
  }, error = function(e) {
    return(default)
  })
}

helpers_rdata_lake <- new.env(parent = globalenv())

# Metinsel tool çağrılarını yakala (rdata_sql(...), rdata_metrics(...))
# Türkçe: Eski (regex tabanlı) ayrıştırıcı — korunuyor
helpers_rdata_lake$parse_tool_calls_from_text_legacy <- function(text) {
  out <- list()
  if (!is.character(text) || length(text) == 0 || !nzchar(text[1])) return(out)
  s <- text[1]

  # rdata_sql(sql="...") veya rdata_sql("...")
  # Çok satırlı SQL'i de kapsayacak şekilde en temizi: önce kod bloğunu dene
  m_all <- gregexpr("rdata_sql\\s*\\(([^)]*)\\)", s, perl = TRUE)
  if (!is.na(m_all[[1]][1]) && m_all[[1]][1] > 0) {
    parts <- regmatches(s, m_all)[[1]]
    for (p in parts) {
      # sql="..."/'...' veya çıplak string
      mm <- regexpr("(?:sql\\s*=\\s*)?([\"'])([\\s\\S]*?)\\1", p, perl = TRUE)
      if (mm[1] > 0) {
        seg <- regmatches(p, mm)
        sql <- sub("^(?:sql\\s*=\\s*)?([\"'])([\\s\\S]*?)\\1$", "\\2", seg)
        out[[length(out)+1]] <- list(function_name = "rdata_sql", arguments = list(sql = sql))
      }
    }
  }

  # rdata_metrics(proje_adi="...") / rdata_metrics(proje_kodu="...")
  m2 <- gregexpr("rdata_metrics\\s*\\(([^)]*)\\)", s, perl = TRUE)
  if (!is.na(m2[[1]][1]) && m2[[1]][1] > 0) {
    parts <- regmatches(s, m2)[[1]]
    for (p in parts) {
      pa <- NULL; pk <- NULL
      mm_pa <- regexpr("proje_adi\\s*=\\s*([\"'])(.*?)\\1", p, perl = TRUE)
      if (mm_pa[1] > 0) {
        seg <- regmatches(p, mm_pa)
        pa  <- sub("^proje_adi\\s*=\\s*([\"'])(.*?)\\1$", "\\2", seg)
      }
      mm_pk <- regexpr("proje_kodu\\s*=\\s*([\"'])(.*?)\\1", p, perl = TRUE)
      if (mm_pk[1] > 0) {
        seg <- regmatches(p, mm_pk)
        pk  <- sub("^proje_kodu\\s*=\\s*([\"'])(.*?)\\1$", "\\2", seg)
      }
      out[[length(out)+1]] <- list(function_name = "rdata_metrics", arguments = list(proje_adi = pa, proje_kodu = pk))
    }
  }
  
    # rdata_column_search(query="...", limit=10)
  m3 <- gregexpr("rdata_column_search\\s*\\(([^)]*)\\)", s, perl = TRUE)
  if (!is.na(m3[[1]][1]) && m3[[1]][1] > 0) {
    parts <- regmatches(s, m3)[[1]]
    for (p in parts) {
      qx <- regexpr("query\\s*=\\s*([\"'])([\\s\\S]*?)\\1", p, perl = TRUE)
      qv <- if (qx[1] > 0) sub("^query\\s*=\\s*([\"'])([\\s\\S]*?)\\1$", "\\2", regmatches(p, qx)) else ""
      lx <- regexpr("limit\\s*=\\s*([0-9]+)", p, perl = TRUE)
      lv <- if (lx[1] > 0) as.integer(sub("^limit\\s*=\\s*([0-9]+)$", "\\1", regmatches(p, lx))) else 10L
      out[[length(out)+1]] <- list(function_name = "rdata_column_search", arguments = list(query = qv, limit = lv))
    }
  }

  # rdata_ask(question="...", limit=100)
  m4 <- gregexpr("rdata_ask\\s*\\(([^)]*)\\)", s, perl = TRUE)
  if (!is.na(m4[[1]][1]) && m4[[1]][1] > 0) {
    parts <- regmatches(s, m4)[[1]]
    for (p in parts) {
      qx <- regexpr("question\\s*=\\s*([\"'])([\\s\\S]*?)\\1", p, perl = TRUE)
      qv <- if (qx[1] > 0) sub("^question\\s*=\\s*([\"'])([\\s\\S]*?)\\1$", "\\2", regmatches(p, qx)) else ""
      lx <- regexpr("limit\\s*=\\s*([0-9]+)", p, perl = TRUE)
      lv <- if (lx[1] > 0) as.integer(sub("^limit\\s*=\\s*([0-9]+)$", "\\1", regmatches(p, lx))) else 100L
      out[[length(out)+1]] <- list(function_name = "rdata_ask", arguments = list(question = qv))
    }
  }
  
  out
}

# Türkçe yorum: rdata aracı çalıştırıcı (tek giriş noktası).
helpers_rdata_lake$execute_tool <- function(name, args) {
  # Türkçe yorum: Harici yürütücü varsa onu kullan (tekrar yazmamak için).
  if (exists("execute_mcp_rdata_tool", inherits = TRUE) &&
      is.function(execute_mcp_rdata_tool)) {
    tc <- list(name = name, args = args)
    return(execute_mcp_rdata_tool(tc, session = NULL))
  }

  # Türkçe yorum: Basit yerleşik dağıtım (yedek).
  nm <- tolower(as.character(name %||% ""))
  if (identical(nm, "rdata_sql")) {
    sql   <- as.character(args$sql %||% "")
    raw_limit <- args$limit
    preview_rows <- NULL
    if (!is.null(raw_limit)) {
      suppressWarnings({
        candidate <- try(as.integer(raw_limit), silent = TRUE)
        if (!inherits(candidate, "try-error")) {
          cand_val <- candidate[1]
          if (is.finite(cand_val) && cand_val > 0) preview_rows <- cand_val
        }
      })
    }
    return(helpers_rdata_lake$rdata_sql(sql, preview_rows = preview_rows))
  } else if (identical(nm, "rdata_metrics")) {
    cat("[EXECUTE_TOOL] rdata_metrics called\n")
    cat("[EXECUTE_TOOL] args class: ", class(args), " names: ", paste(names(args), collapse=", "), "\n")
    
    # Argümanları güvenli şekilde normalize et (vektör/liste olabilir)
    pa <- args$proje_adi %||% NULL
    cat("[EXECUTE_TOOL] proje_adi RAW: class=", class(pa), " length=", length(pa), "\n")
    
    if (!is.null(pa)) {
      tryCatch({
        pa <- unlist(pa, use.names = FALSE)
        pa <- if (length(pa) > 0) as.character(pa)[1] else NULL
        cat("[EXECUTE_TOOL] proje_adi NORMALIZED: ", pa %||% "NULL", "\n")
      }, error = function(e) {
        cat("[EXECUTE_TOOL] ERROR normalizing proje_adi: ", conditionMessage(e), "\n")
        pa <<- NULL
      })
    }
    
    pk <- args$proje_kodu %||% NULL
    cat("[EXECUTE_TOOL] proje_kodu RAW: class=", class(pk), " length=", length(pk), "\n")
    
    if (!is.null(pk)) {
      tryCatch({
        pk <- unlist(pk, use.names = FALSE)
        pk <- if (length(pk) > 0) as.character(pk)[1] else NULL
        cat("[EXECUTE_TOOL] proje_kodu NORMALIZED: ", pk %||% "NULL", "\n")
      }, error = function(e) {
        cat("[EXECUTE_TOOL] ERROR normalizing proje_kodu: ", conditionMessage(e), "\n")
        pk <<- NULL
      })
    }
    
    cat("[EXECUTE_TOOL] Calling rdata_metrics with proje_adi='", pa %||% "", "' proje_kodu='", pk %||% "", "'\n")
    result <- helpers_rdata_lake$rdata_metrics(proje_adi = pa, proje_kodu = pk)
    cat("[EXECUTE_TOOL] rdata_metrics returned: ", if(is.list(result) && !is.null(result$error)) "ERROR" else "SUCCESS", "\n")
    return(result)
  } else if (identical(nm, "rdata_ask")) {
          q   <- as.character(args$question %||% "")
          raw_limit <- args$limit
          lim <- NULL
          if (!is.null(raw_limit)) {
            suppressWarnings({
              lim_try <- try(as.integer(raw_limit), silent = TRUE)
              if (!inherits(lim_try, "try-error")) {
                lim_val <- lim_try[1]
                if (is.finite(lim_val) && lim_val > 0) lim <- lim_val
              }
            })
          }
          # Türkçe: Soruyu derleyip ortaya çıkan SQL'i çalıştır
          plan <- try(helpers_rdata_lake$rdata_compile_sql(q, limit = lim), silent = TRUE)
          if (inherits(plan, "try-error") || is.null(plan$sql)) {
                # Türkçe: Derleme başarısızsa güvenli fallback kullan
                con <- helpers_rdata_lake$db_connect(readonly = TRUE)
                on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
                sql <- helpers_rdata_lake$compose_dynamic_fallback_sql(con, limit = lim)
          } else {
                sql <- plan$sql
          }
          res <- helpers_rdata_lake$rdata_sql(sql, preview_rows = lim)
          return(res)

  } else if (identical(nm, "rdata_column_search")) {
    # Türkçe yorum: Sütun arama aracı — model ilk keşifte bunu çağırmalı
    q   <- as.character(args$query %||% "")
    lim <- as.integer(args$limit %||% 10L)
    if (!is.finite(lim) || lim <= 0) lim <- 10L
    return(helpers_rdata_lake$rdata_column_search(query = q, limit = lim))
	
  } else if (identical(nm, "rdata_search")) {
    # Türkçe: Metin tabanlı arama aracını çalıştır
    txt <- as.character(args$text %||% args$query %||% "")
    lim <- as.integer(args$limit %||% 10L)
    return(helpers_rdata_lake$rdata_search(text = txt, limit = lim))

  } else if (identical(nm, "rdata_smart_query")) {
    # Türkçe: Akıllı sorguyu çalıştır
    dims <- args$dimensions %||% list()
    mets <- args$metrics    %||% list()
    fil  <- args$filters    %||% list()
    raw_lim <- args$limit
    lim <- NULL
    if (!is.null(raw_lim)) {
      suppressWarnings({
        lim_try <- try(as.integer(raw_lim), silent = TRUE)
        if (!inherits(lim_try, "try-error")) {
          lim_val <- lim_try[1]
          if (is.finite(lim_val) && lim_val > 0) lim <- lim_val
        }
      })
    }
    return(helpers_rdata_lake$rdata_smart_query(dimensions = dims, metrics = mets, filters = fil, limit = lim))
	
  }

  list(error = sprintf("Bilinmeyen rdata aracı: %s", name))
}

# Türkçe yorum: Kolon arama aracı — metadata kapalı olsa bile çalışır
helpers_rdata_lake$rdata_column_search <- function(query, limit = 10L, sample_each = 3L) {
  # Türkçe: Girdi normalizasyonu
  q <- as.character(query %||% "")
  lim <- as.integer(limit %||% 10L); if (!is.finite(lim) || lim <= 0) lim <- 10L
  samp <- as.integer(sample_each %||% 3L); if (!is.finite(samp) || samp <= 0) samp <- 3L

  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  # Türkçe: fact_universe yoksa hafif yenilemeyi tetikle
  exists_fu <- FALSE
  try({
    exists_fu <- DBI::dbExistsTable(con, "fact_universe")
  }, silent = TRUE)
  if (!isTRUE(exists_fu)) {
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
    try(helpers_rdata_lake$rdata_refresh_all(), silent = TRUE)
    con <- helpers_rdata_lake$db_connect(readonly = TRUE)
    on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
  }

  # Türkçe: Mevcut sütunları ve tiplerini çek
  info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  if (inherits(info, "try-error") || !nrow(info)) {
    return(list(error = "fact_universe görünümü bulunamadı veya sütun listesi alınamadı."))
  }
  avail_cols  <- as.character(info$name)
  avail_types <- as.character(info$type %||% rep("", nrow(info)))

  # Türkçe: Şema rolleri ile metrik/boyut/zaman sınıflaması
  roles <- helpers_rdata_lake$infer_schema_roles(avail_cols)
  is_metric <- function(cn) cn %in% (roles$metrics %||% character(0))
  is_time   <- function(cn) cn %in% (roles$time_dims %||% character(0))
  role_of   <- function(cn) {
    if (is_metric(cn)) "metric"
    else if (is_time(cn)) "time"
    else "dimension"
  }

  # Türkçe: Basit benzerlik skoru (alt dize + Jaro-Winkler benzerliği)
  make_score <- function(col, qtxt) {
    if (!nzchar(qtxt)) return(0)
    cl <- tolower(enc2utf8(col))
    qt <- tolower(enc2utf8(qtxt))
    has_sub <- as.integer(grepl(qt, cl, fixed = TRUE))
    jw <- tryCatch({
      # stringdist::stringsim(JW) 0..1 arası, hata olursa 0
      stringdist::stringsim(qt, cl, method = "jw")
    }, error = function(e) 0)
    # Türkçe: alt dize eşleşmesine ekstra ağırlık ver
    (2 * has_sub) + jw
  }

  scores <- vapply(avail_cols, make_score, numeric(1), qtxt = q)
  ord <- order(scores, decreasing = TRUE, na.last = NA)
  if (length(ord) == 0) {
    return(list(error = "Sorgu ile eşleşen sütun bulunamadı."))
  }

  pick_idx <- utils::head(ord, lim)
  picked   <- avail_cols[pick_idx]

  # Türkçe: Örnek değerleri küçük LIMIT ile al (tek tek; güvenli CAST ile)
  sample_for <- function(cn) {
    id <- DBI::dbQuoteIdentifier(con, cn)
    sql <- sprintf(
      'SELECT DISTINCT CAST(%s AS VARCHAR) AS v FROM fact_universe WHERE %s IS NOT NULL LIMIT %d',
      id, id, as.integer(samp)
    )
    vv <- try(DBI::dbGetQuery(con, sql), silent = TRUE)
    if (inherits(vv, "try-error") || !nrow(vv)) return(character(0))
    as.character(vv$v)
  }

  examples <- vapply(picked, function(cn) {
    vals <- sample_for(cn)
    if (!length(vals)) "" else paste(utils::head(vals, samp), collapse = " | ")
  }, character(1))

  types <- avail_types[match(picked, avail_cols)]
  roles_chr <- vapply(picked, role_of, character(1))

  # Türkçe: Önizleme tablosu — formatlayıcılar bunu markdown’a çevirir
  df <- data.frame(
    column_name   = picked,
    role          = roles_chr,
    data_type     = types %||% "",
    sample_values = examples,
    stringsAsFactors = FALSE
  )

  # Türkçe: Hem 'preview' hem de geriye dönük 'sonuç_önizleme' döndür
  list(
    preview = df,
    `sonuç_önizleme` = df,
    matched_columns = picked
  )
}

# ---- Akıllı sorgu: boyut/metrik adlarından SQL üret ve çalıştır ----
helpers_rdata_lake$rdata_smart_query <- function(dimensions = NULL, metrics = NULL, filters = NULL, limit = NULL) {
  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  # Türkçe: Mevcut kolonları al
  info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  avail <- if (!inherits(info, "try-error") && nrow(info)) as.character(info$name) else character(0)

  # Türkçe: Metadata varsa yaklaşık eşleştirme ile kesin kolon bul
  resolve_cols <- function(xs) {
    if (!length(xs)) return(character(0))
    out <- character(0)
    for (x in xs) {
      exact <- try(helpers_rdata_metadata$find_exact_column(con, x), silent = TRUE)
      if (!inherits(exact, "try-error") && nzchar(exact %||% "")) {
        out <- c(out, exact)
      } else if (x %in% avail) {
        out <- c(out, x)
      }
    }
    unique(intersect(out, avail))
  }

  dims <- resolve_cols(dimensions %||% character(0))
  mets <- resolve_cols(metrics    %||% character(0))
  if (!length(mets)) stop("En az bir metrik gerek.")

  # Türkçe: SUM(TRY_CAST(...)) ile güvenli toplama
  met_sel <- paste(sprintf('SUM(TRY_CAST("%s" AS DOUBLE)) AS "%s"', mets, mets), collapse = ", ")
  dim_sel <- if (length(dims)) paste(sprintf('"%s"', dims), collapse = ", ") else ""
  sel_list <- paste(c(dim_sel, met_sel), collapse = ", ")

  # Türkçe: Basit filtre derleme (eşitlik/ILIKE)
  where_parts <- c()
  if (is.list(filters) && length(filters)) {
    for (nm in names(filters)) {
      if (!(nm %in% avail)) next
      v <- filters[[nm]]
      qid <- DBI::dbQuoteIdentifier(con, nm)
      if (is.numeric(v)) {
        where_parts <- c(where_parts, sprintf("%s = %s", qid, as.numeric(v)[1]))
      } else if (inherits(v, "Date")) {
        where_parts <- c(where_parts, sprintf("%s = DATE '%s'", qid, format(as.Date(v[1]), "%Y-%m-%d")))
      } else {
        where_parts <- c(where_parts, sprintf("%s ILIKE %s", qid, DBI::dbQuoteString(con, paste0("%", as.character(v)[1], "%"))))
      }
    }
  }
  wc <- if (length(where_parts)) paste("WHERE", paste(where_parts, collapse = " AND ")) else ""

  grp <- if (length(dims)) paste("GROUP BY", paste(sprintf('"%s"', dims), collapse = ", ")) else ""
  ord <- sprintf('ORDER BY "%s" DESC', mets[1])
  lim_txt <- ""
  lim_val <- NULL
  if (!is.null(limit)) {
    suppressWarnings({
      lim_try <- try(as.integer(limit), silent = TRUE)
      if (!inherits(lim_try, "try-error")) {
        cand <- lim_try[1]
        if (is.finite(cand) && cand > 0) {
          lim_val <- cand
          lim_txt <- sprintf("LIMIT %d", cand)
        }
      }
    })
  }

  sql <- sprintf("SELECT %s FROM fact_universe %s %s %s %s", sel_list, wc, grp, ord, lim_txt)

  # Türkçe: Otomatik source_table filtresi eklensin
  helpers_rdata_lake$rdata_sql(sql, preview_rows = lim_val)
}

# Türkçe yorum: Geçici durum temizleme - her çağrı öncesi ve sonrası
helpers_rdata_lake$rdata_reset_state <- function(reason = "") {
  # Türkçe yorum: Birleşmeleri önlemek için geçici yapıları sıfırla.
  if (exists(".chart_store_env", envir = helpers_rdata_lake, inherits = FALSE)) {
    env <- get(".chart_store_env", envir = helpers_rdata_lake)
    if (is.environment(env)) rm(list = ls(env, all.names = TRUE), envir = env)
  }
  helpers_rdata_lake$.chart_store_env <- new.env(parent = emptyenv())
  
  # Türkçe yorum: Request ID'yi sıfırla (her soru yeni bir ID almalı)
  helpers_rdata_lake$.current_request_id <- NULL
  
  if (nzchar(reason)) cat("[RDATA_LAKE] reset_state reason=", reason, "\n")
  invisible(TRUE)
}

# ---- Kalıcı DuckDB dosyası (uygulama veri dizininde) ----
# Türkçe: DuckDB dosyasını kalıcı bir dizinde tut (varsayılan: ./data)
helpers_rdata_lake$db_path <- {
  root <- getOption("mergen.files_root", NULL)
  if (is.null(root) || !nzchar(root)) root <- "data"
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  file.path(root, "rdata_lake.duckdb")
}

helpers_rdata_lake$catalog  <- data.table::data.table()   # bellek içi katalog önbellek

# Altın sütunlar şemadan
helpers_rdata_lake$GOLDEN <- {
  # SCHEMA tanımlı değilse güvenli varsayılanı kullan
  schema <- get0("SCHEMA", inherits = TRUE)
  if (!is.null(schema) && !is.null(schema$GOLDEN_COLUMNS)) schema$GOLDEN_COLUMNS else character(0)
}

# ---- Yardımcı: güvenli tablo adı üretimi ----
helpers_rdata_lake$sanitize_name <- function(x) {
  # Türkçe yorum: Önce UTF-8'e çevir, sonra ASCII'ye indir ve güvenli ada dönüştür.
  x <- enc2utf8(x)
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- tolower(gsub("[^a-z0-9_]+", "_", x))
  x <- gsub("^_+|_+$", "", x)
  x <- substr(x, 1, 63)
  # Türkçe yorum: Boş kalırsa varsayılan bir ad ver.
  if (!nzchar(x)) x <- "t"
  x
}

# ---- SCHEMA tabanlı metrik isimleri (mevcut kolona göre) ----
helpers_rdata_lake$metric_names_from_schema <- function(avail_cols) {
  # Türkçe yorum: METRICS anahtarlarını ve sayısal TYPE'ları birleştir, mevcut kolonlarla kesiştir.
  schema <- get0("SCHEMA", inherits = TRUE)
  mets_l <- if (!is.null(schema) && !is.null(schema$METRICS)) schema$METRICS else list()
  types  <- if (!is.null(schema) && !is.null(schema$TYPES))   schema$TYPES   else list()

  # METRICS anahtarları
  from_metrics <- names(mets_l)

  # Sayısal TYPES: DOUBLE/DECIMAL/REAL/NUMERIC/INTEGER/BIGINT
  numeric_types <- c("DOUBLE","DECIMAL","INTEGER","BIGINT","REAL","NUMERIC")
  from_types <- names(types)[toupper(unlist(types)) %in% numeric_types]

  cand <- unique(c(from_metrics, from_types))
  intersect(cand, avail_cols)
}

# ---- Dinamik fallback SELECT derleyici (sütunlar tam dinamik) ----
helpers_rdata_lake$compose_dynamic_fallback_sql <- function(con, limit = NULL, desired_dims = NULL) {
  # Türkçe yorum: fact_universe mevcut kolonları çek.
  info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  avail_cols <- if (!inherits(info, "try-error") && nrow(info)) as.character(info$name) else character(0)

  # Türkçe yorum: Şemadan roller (zaman/varlık/metrik)
  roles <- helpers_rdata_lake$infer_schema_roles(avail_cols)
  mets  <- helpers_rdata_lake$metric_names_from_schema(avail_cols)

  # Türkçe yorum: Gösterilecek metrikleri sınırla (ilk 3 genelde yeter)
  if (!length(mets)) stop("Uygun metrik bulunamadı.")
  mets_show <- head(mets, as.integer(getOption("mergen.rdata.preview_metrics", 3L)))

  # Türkçe yorum: Varlık boyutu seçimi — Şema önceliği: UNION_CORE -> GOLDEN_COLUMNS -> VARIANTS
  schema <- get0("SCHEMA", inherits = TRUE)
  prio <- unique(c(
    if (!is.null(schema$UNION_CORE)) schema$UNION_CORE else character(0),
    if (!is.null(schema$GOLDEN_COLUMNS)) schema$GOLDEN_COLUMNS else character(0),
    names(schema$VARIANTS %||% list())
  ))

  dims <- if (!is.null(desired_dims) && length(intersect(desired_dims, avail_cols))) {
    intersect(desired_dims, avail_cols)
  } else {
    cand <- intersect(prio, roles$entity_dims %||% character(0))
    if (length(cand)) cand[1] else head(roles$entity_dims %||% character(0), 1)
  }
  
  dims <- unique(dims)
  dim_sel <- if (length(dims)) paste(sprintf('"%s"', dims), collapse = ", ") else ""

	# Türkçe yorum: Hem sayısal hem metin-sayısal sütunları güvenle topla
	met_sel <- paste(sprintf('SUM(TRY_CAST("%s" AS DOUBLE)) AS "%s"', mets_show, mets_show), collapse = ", ")
  sel_list <- paste(c(dim_sel, met_sel), collapse = ", ")
  grp_list <- if (length(dims)) paste(sprintf('"%s"', dims), collapse = ", ") else ""
  ord_col  <- sprintf('"%s"', mets_show[1])

  sprintf("
    SELECT %s
    FROM fact_universe
    %s
    %s
	ORDER BY %s DESC
	%s
	",
	  sel_list,
	  "",  # WHERE yok
	  if (nzchar(grp_list)) paste("GROUP BY", grp_list) else "",
          ord_col,
          {
            lim_txt <- ""
            if (!is.null(limit)) {
              suppressWarnings({
                lim_try <- try(as.integer(limit), silent = TRUE)
                if (!inherits(lim_try, "try-error")) {
                  lim_val <- lim_try[1]
                  if (is.finite(lim_val) && lim_val > 0) lim_txt <- sprintf("LIMIT %d", lim_val)
                }
              })
            }
            lim_txt
          }
        )
}

# ---- DuckDB bağlantısı (her çağrıda aç-kapat) ----
helpers_rdata_lake$db_connect <- function(readonly = FALSE) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = helpers_rdata_lake$db_path, read_only = readonly)

  # Sistem kaynaklarına göre DuckDB ayarları
  # threads: kullanılacak CPU çekirdek sayısı
  # memory_limit: işlemler için kullanılacak RAM sınırı (örn: '8GB', '16GB')
  thr <- tryCatch(getOption("mergen.duckdb.threads", parallel::detectCores()), error = function(e) 4L)
  mem <- getOption("mergen.duckdb.memory_limit", "8GB")

  try(DBI::dbExecute(con, sprintf("PRAGMA threads=%d", as.integer(thr)[1])), silent = TRUE)
  try(DBI::dbExecute(con, sprintf("PRAGMA memory_limit='%s'", mem)), silent = TRUE)
  try(DBI::dbExecute(con, "PRAGMA preserve_insertion_order=false"), silent = TRUE)
  # Türkçe yorum: Büyük işlemlerde belleği taşırmamak için geçici dosya dizini kullan
  tmpdir <- getOption("mergen.duckdb.temp_directory", "")
  if (is.character(tmpdir) && nzchar(tmpdir)) {
    dir.create(tmpdir, recursive = TRUE, showWarnings = FALSE)
    try(DBI::dbExecute(con, sprintf("PRAGMA temp_directory='%s'", 
        normalizePath(tmpdir, winslash = "/", mustWork = FALSE))), silent = TRUE)
  }
  # Ağ bağlantısız ortamlarda eklenti indirme denemesini kapat
  try(DBI::dbExecute(con, "SET autoinstall=false"), silent = TRUE)

  con
}

# ---- Motoru başlat ----
helpers_rdata_lake$rdata_engine_init <- function(paths_opt = NULL) {
  # Uygulama seçeneklerinden yolları oku; DuckDB dosyasını ve katalog tablosunu hazırla
  # Yolları options()'tan çek
  if (is.null(paths_opt)) paths_opt <- getOption("mergen.rdata.paths", list())
  # Ortam değişkeniyle override (isteğe bağlı)
  env_daily  <- Sys.getenv("MERGEN_RDATA_DAILY_PATH", "")
  env_weekly <- Sys.getenv("MERGEN_RDATA_WEEKLY_PATH", "")
  if (nzchar(env_daily))  paths_opt$RdataDaily <- env_daily
  if (nzchar(env_weekly)) paths_opt$Rdata      <- env_weekly

  helpers_rdata_lake$paths <- paths_opt
  if (length(paths_opt) == 0) {
    message("RDataLake: no paths configured; set options(mergen.rdata.paths=...)")
  }

  # DuckDB dosyasını oluştur
  con <- helpers_rdata_lake$db_connect(readonly = FALSE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))
  # Katalog tablosu (kaynak, tablo, sütunlar, zaman)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS rd_catalog (
      source_file TEXT,
      object_name TEXT,
      table_name  TEXT,
      n_rows      BIGINT,
      n_cols      INTEGER,
      columns_json TEXT,
      loaded_at    TIMESTAMP
    );
  ")

  # Araç girişlerini küresel alana sabitle (MCP 'family:rdata' bunları çağırır)
  # Not: Bu atamalar başka bir eski tanımı ezerek her zaman lake sürümünü kullanır.
  assign("rdata_sql",     function(...) { cat("[RDATA_LAKE] shim rdata_sql(global) -> lake\n");     helpers_rdata_lake$rdata_sql(...)     }, envir = globalenv())
  assign("rdata_search",  function(...) { cat("[RDATA_LAKE] shim rdata_search(global) -> lake\n");  helpers_rdata_lake$rdata_search(...)  }, envir = globalenv())
  assign("rdata_metrics", function(...) { cat("[RDATA_LAKE] shim rdata_metrics(global) -> lake\n"); helpers_rdata_lake$rdata_metrics(...) }, envir = globalenv())
  assign("rdata_column_search", function(...) { cat("[RDATA_LAKE] shim rdata_column_search(global) -> lake\n"); helpers_rdata_lake$rdata_column_search(...) }, envir = globalenv())
  cat("[RDATA_LAKE] tool shims installed in globalenv: rdata_sql/search/metrics/column_search -> helpers_rdata_lake\n")

  # Trigger an initial refresh so aggregates & metric profiles exist when the app starts.
  # Skips work if the lake is already built. Respect heavy toggles.
  if (isTRUE(getOption("mergen.rdata.refresh_on_boot", TRUE))) {
    con_chk <- helpers_rdata_lake$db_connect(readonly = TRUE)
    need_refresh <- FALSE
    try({
      if (!DBI::dbExistsTable(con_chk, "fact_universe")) {
        need_refresh <- TRUE
      } else {
        # Only require profiles if profiles are enabled
        if (isTRUE(getOption("mergen.rdata.enable_profiles", TRUE))) {
          if (!DBI::dbExistsTable(con_chk, "rd_metric_profiles")) {
            need_refresh <- TRUE
          } else {
            n_profiles <- DBI::dbGetQuery(con_chk, "SELECT COUNT(*) AS n FROM rd_metric_profiles")$n
            if (is.na(n_profiles) || n_profiles == 0) need_refresh <- TRUE
          }
        }
        # Only require aggregate catalog if aggregates are enabled
        if (isTRUE(getOption("mergen.rdata.enable_aggregates", TRUE))) {
          if (!DBI::dbExistsTable(con_chk, "rd_agg_catalog")) {
            need_refresh <- TRUE
          }
        }
      }
    }, silent = TRUE)
    try(DBI::dbDisconnect(con_chk, shutdown = TRUE), silent = TRUE)
    if (need_refresh) {
      cat("[RDATA_LAKE] initial refresh_on_boot triggered\n")
      helpers_rdata_lake$rdata_refresh_all()
    }
  }

  invisible(TRUE)
}

# ---- .RData içinden data.frame/data.table objelerini çıkar ----
helpers_rdata_lake$load_rdata_frames <- function(file_path) {
  e <- new.env(parent = emptyenv())
  nm <- load(file_path, envir = e)
  out <- list()
  for (obj in nm) {
    val <- e[[obj]]
    if (inherits(val, c("data.frame","data.table","tbl_df"))) {
      dt <- data.table::as.data.table(val)
      # Sütun isimleri boş/NA olmasın
      nms <- names(dt)
      nms[is.na(nms) | nms == ""] <- paste0("X", which(is.na(nms) | nms == ""))
      names(dt) <- make.names(nms, unique = TRUE, allow_ = TRUE)
      out[[obj]] <- dt
    }
  }
  out
}

# ---- DuckDB uyumlu tip temizleyici ----
helpers_rdata_lake$sanitize_df_for_duckdb <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  rownames(df) <- NULL
  # Türkçe yorum: Boş/NA adları düzelt ve benzersiz isim üret.
  nms <- names(df)
  nms[is.na(nms) | nms == ""] <- paste0("X", which(is.na(nms) | nms == ""))
  names(df) <- make.names(nms, unique = TRUE, allow_ = TRUE)

  for (cn in names(df)) {
    x <- df[[cn]]

    # Türkçe yorum: DuckDB'nin sevmediği sınıfları dönüştür.
    if (inherits(x, "AsIs"))      x <- as.vector(x)
    if (inherits(x, "factor"))    x <- as.character(x)
    if (inherits(x, "ordered"))   x <- as.character(x)
    if (inherits(x, "POSIXlt"))   x <- as.POSIXct(x, tz = "UTC")
    if (inherits(x, "IDate"))     x <- as.Date(x)
    if (inherits(x, "ITime"))     x <- as.integer(x)            # saniye
    if (inherits(x, "hms"))       x <- as.numeric(x)            # saniye
    if (inherits(x, "difftime"))  x <- as.numeric(x, units = "secs")
    if (inherits(x, "integer64")) x <- as.numeric(x)            # hassasiyet kaybı kabul
    if (is.raw(x))                x <- base64enc::base64encode(x)

    # Türkçe yorum: Karakter sütunları UTF-8'e zorla; geçersiz baytları güvenli şekilde dönüştür.
    if (is.character(x)) {
      # Yerel kodlamadan UTF-8'e dönüşüm; hatalı baytları 'byte' gösterimi ile korur.
      x <- suppressWarnings(iconv(x, from = "", to = "UTF-8", sub = "byte"))
      # NUL karakterlerini PCRE ile temizle (kaynakta literal NUL kullanma).
      x <- gsub("\\x00", "", x, perl = TRUE)
    }

    # Türkçe yorum: Liste sütunlarını güvenli biçime çevir (JSON veya tekil atomik değer).
    if (is.list(x) && !is.data.frame(x)) {
      x <- vapply(x, function(el) {
        if (is.null(el)) return(NA_character_)
        if (is.atomic(el) && length(el) == 1L) return(as.character(el))
        # JSON'u ASCII'ye zorlarsak sorunlu baytlar kaçışlı gelir; DuckDB ile güvenli.
        jsonlite::toJSON(el, auto_unbox = TRUE, null = "null", ensure_ascii = TRUE)
      }, character(1))
      # JSON dizelerine de NUL temizliği uygula (literal NUL kullanma)
      x <- gsub("\\x00", "", x, perl = TRUE)
    }

    df[[cn]] <- x
  }
  df
}

# ---- Tek tabloyu DuckDB'ye yaz ----
helpers_rdata_lake$write_table <- function(con, dt, table_name) {
  # Türkçe yorum: rapi_register_df hatalarını önlemek için tiplere ön-temizlik uygula.
  df <- helpers_rdata_lake$sanitize_df_for_duckdb(dt)
  tryCatch(
    DBI::dbWriteTable(con, table_name, df, overwrite = TRUE, temporary = FALSE),
    error = function(e) {
      # Türkçe yorum: Hata mesajını tablo adı ile birlikte yüzeye çıkar.
      stop(sprintf("DuckDB yazma hatası (tablo='%s'): %s", table_name, conditionMessage(e)))
    }
  )
}

# Soru → DuckDB SQL derleyici (SCHEMA ve fact_universe üstünden)
helpers_rdata_lake$rdata_compile_sql <- function(question, limit = NULL) {
  lim_txt <- ""
  if (!is.null(limit)) {
    suppressWarnings({
      lim_try <- try(as.integer(limit), silent = TRUE)
      if (!inherits(lim_try, "try-error")) {
        lim_val <- lim_try[1]
        if (is.finite(lim_val) && lim_val > 0) {
          lim_txt <- sprintf("LIMIT %d", lim_val)
        }
      }
    })
  }

  # Bağlantı ve fact_universe kontrolü
  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))

  exists_now <- try(DBI::dbExistsTable(con, "fact_universe"), silent = TRUE)
  if (inherits(exists_now, "try-error") || !isTRUE(exists_now)) {
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
    try(helpers_rdata_lake$rdata_refresh_all(), silent = TRUE)
    con <- helpers_rdata_lake$db_connect(readonly = TRUE)
    on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = FALSE)
  }

  # Gerçek mevcut sütunlar
  avail <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  avail_cols <- if (!inherits(avail, "try-error") && nrow(avail)) as.character(avail$name) else character(0)

  # --- Basit kişi adı bulma kısa yolu (SicilNo + ad/isim) ---
  # Türkçe yorum: Bu soru tipinde doğrudan dim_person üzerinden yanıt ver.
  # Latinize/capitalize ETME; saf metin eşlemesi ile ilerle.
  q_txt <- tolower(enc2utf8(question))
  has_sicil <- grepl("\\b(sicil\\s*no|sicilno)\\b", q_txt, perl = TRUE)
  asks_name <- grepl("\\b(ad[ıi]|ad\\s*soyad|isim|adı)\\b", q_txt, perl = TRUE)
  dim_person_exists <- try(DBI::dbExistsTable(con, "dim_person"), silent = TRUE)
  if (isTRUE(dim_person_exists) && has_sicil && asks_name) {
    # Türkçe yorum: Sorudan sayısal bir kimlik yakala (yoksa geniş ILIKE)
    id_hit <- regmatches(q_txt, regexpr("\\b[0-9]{3,}\\b", q_txt, perl = TRUE))
    where_clause <- if (length(id_hit) && nzchar(id_hit[1])) {
      paste0('WHERE CAST("SicilNo" AS VARCHAR) ILIKE ', DBI::dbQuoteString(con, paste0("%", id_hit[1], "%")))
    } else {
      ""  # Türkçe yorum: id bulunamazsa ilk satırdan bir örnek döner
    }

    sql <- sprintf('
      SELECT ANY_VALUE("AdSoyad") AS "AdSoyad"
      FROM dim_person
      %s
      LIMIT 1
    ', where_clause)

    return(list(sql = sql, dims = character(0), metrics = character(0), from = "dim_person"))
  }

  # Soru çözümlemesi
  pr <- try(parse_tr_question(question), silent = TRUE)
  pr <- if (inherits(pr, "try-error")) list(text = "", tokens = character(0), project_hint = NULL) else pr

	# Türkçe yorum: SCHEMA rollerine göre boyut adaylarını çıkar.
	roles <- helpers_rdata_lake$infer_schema_roles(avail_cols)
	dim_pool <- unique(c(roles$entity_dims %||% character(0)))

	  # Türkçe yorum: Soruya göre sütun sıralaması yoksa şema önceliğini uygula.
	  schema <- get0("SCHEMA", inherits = TRUE)
	  prio <- unique(c(
		if (!is.null(schema$UNION_CORE)) schema$UNION_CORE else character(0),
		if (!is.null(schema$GOLDEN_COLUMNS)) schema$GOLDEN_COLUMNS else character(0),
		names(schema$VARIANTS %||% list())
	  ))

	  dims <- character(0)
	  try({
		rk <- rank_columns_for_question(question, unique(c(dim_pool, roles$time_dims %||% character(0))))
		if (is.data.frame(rk) && nrow(rk)) dims <- rk$column[rk$score >= 0.55]
	  }, silent = TRUE)

	  if (!length(dims)) {
		cand <- intersect(prio, dim_pool)
		dims <- if (length(cand)) cand[1] else head(dim_pool, 1)
	  }

	dims <- unique(head(dims, 2))

	# Türkçe yorum: Metri̇kler — önce soru sinyali, olmadı SCHEMA/TYPES'tan mevcut metrikler
	mets <- try(infer_metrics(question), silent = TRUE)
	mets <- if (!inherits(mets, "try-error") && length(mets)) mets else helpers_rdata_lake$metric_names_from_schema(avail_cols)
	mets <- intersect(mets, avail_cols)
	if (!length(mets)) stop("Uygun metrik bulunamadı.")

  # WHERE filtresi
  where_parts <- c()
  # Türkçe yorum: Proje ipucu → tüm varlık boyutlarında ILIKE uygula (SCHEMA'ya tam dinamik)
	if (!is.null(pr$project_hint) && length(avail_cols)) {
	  ph <- as.character(pr$project_hint)[1]
	  if (nzchar(ph)) {
		ent_dims <- intersect(roles$entity_dims %||% character(0), avail_cols)
		if (length(ent_dims)) {
		  pattern <- paste0("%", ph, "%")
		  ors <- glue::glue_sql('{`col`} ILIKE {pattern}', col = ent_dims, pattern = pattern, .con = con)
		  any_ilike <- glue::glue_collapse(ors, " OR ")
		  where_parts <- c(where_parts, glue::glue("({any_ilike})"))
		}
	  }
	}
  # Zaman penceresi
  tw <- try(infer_time_window(question), silent = TRUE)
  if (!inherits(tw, "try-error") && is.list(tw)) {
    if (!is.null(tw$Yil) && "Yil" %in% avail_cols) where_parts <- c(where_parts, sprintf("Yil = %d", as.integer(tw$Yil[1])))
    if (!is.null(tw$Ay)  && "Ay"  %in% avail_cols) where_parts <- c(where_parts, sprintf("Ay = %d",  as.integer(tw$Ay[1])))
  }
  wc <- if (length(where_parts)) paste("WHERE", paste(where_parts, collapse = " AND ")) else ""

	# FROM seçimi: rd_agg_catalog'tan en uygun özet tabloyu seç; yoksa fact_universe
	from_tbl <- "fact_universe"
	desired_grain <- {
	  # Zaman filtresine göre tercih edilen tane
	  if (!is.null(tw) && (is.list(tw) || is.environment(tw))) {
		if (!is.null(tw$Yil) || !is.null(tw$Ay)) "yil_ay" else NA_character_
	  } else NA_character_
	}

	cand <- try(DBI::dbGetQuery(con, "SELECT table_name,dims_json,metrics_json,time_grain FROM rd_agg_catalog"), silent = TRUE)
	best <- NULL; best_pen <- Inf

	if (!inherits(cand, "try-error") && nrow(cand)) {
	  for (i in seq_len(nrow(cand))) {
		dims_tbl <- try(jsonlite::fromJSON(cand$dims_json[i]), silent = TRUE); if (inherits(dims_tbl,"try-error")) next
		mets_tbl <- try(jsonlite::fromJSON(cand$metrics_json[i]), silent = TRUE); if (inherits(mets_tbl,"try-error")) next
		tg_tbl   <- cand$time_grain[i] %||% "none"

		# İstek boyutları ve metrikleri tablo tarafından kapsanmalı
		if (!all(dims %in% dims_tbl)) next
		if (!all(mets %in% mets_tbl)) next

		# Ceza: fazla boyut sayısı + zaman tane uyuşmazlığı
		pen <- (length(dims_tbl) - length(dims))
		if (!is.na(desired_grain)) {
		  if (!identical(desired_grain, tg_tbl)) pen <- pen + 1
		}
		if (pen < best_pen) {
		  best_pen <- pen
		  best <- cand$table_name[i]
		}
	  }
	}

	if (!is.null(best) && nzchar(best)) {
	  from_tbl <- best
	}

  # SELECT listesi
  dim_sel <- if (length(dims)) paste(sprintf('"%s"', dims), collapse = ", ") else ""
	# Türkçe yorum: TRY_CAST ile güvenli toplama
	met_sel <- paste(sprintf('SUM(TRY_CAST("%s" AS DOUBLE)) AS "%s"', mets, mets), collapse = ", ")

  sel_list <- paste(c(dim_sel, met_sel), collapse = ", ")
  grp_list <- if (length(dims)) paste(sprintf('"%s"', dims), collapse = ", ") else ""
  ord_col  <- sprintf('"%s"', mets[1])

  sql <- sprintf("
    SELECT %s
    FROM %s
    %s
    %s
    ORDER BY %s DESC
    %s
  ",
    sel_list,
    from_tbl,
    wc,
    if (nzchar(grp_list)) paste("GROUP BY", grp_list) else "",
    ord_col,
    lim_txt
  )

  list(sql = sql, dims = dims, metrics = mets, from = from_tbl)
}

# ---- Tüm Rdata klasörlerini tara ve yükle ----
# GÜNCELLENMIŞ VERSİYON - Metadata entegrasyonu ile
helpers_rdata_lake$rdata_refresh_all <- function() {
  # Türkçe yorum: Eşzamanlı/arka arkaya çağrıları yutmak için kilit ve zaman damgası kullan.
  if (isTRUE(helpers_rdata_lake$.__refresh_in_progress)) {
    cat("[RDATA LAKE] Refresh skipped (already in progress)\n")
    return(invisible(FALSE))
  }
  helpers_rdata_lake$.__refresh_in_progress <- TRUE
  on.exit({
    helpers_rdata_lake$.__refresh_in_progress <- FALSE
    helpers_rdata_lake$.__last_refresh_at     <- Sys.time()
  }, add = TRUE)

  # Klasörleri tara, staging tabloları yaz, fact_universe görünümünü oluştur ve katalogu güncelle
  paths <- helpers_rdata_lake$paths %||% list()
  if (!length(paths)) return(invisible(FALSE))

  con <- helpers_rdata_lake$db_connect(readonly = FALSE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))

  cat("[RDATA LAKE] Refresh started\n")

  new_catalog <- data.table::data.table()
  stg_tables <- character()

  for (folder in unique(unlist(paths))) {
    if (!nzchar(folder) || !dir.exists(folder)) next
    files <- list.files(folder, pattern = "\\.(RData|rda)$", full.names = TRUE, ignore.case = TRUE)
    for (f in files) {
      cat("  - Loading:", f, "\n")
      frames <- helpers_rdata_lake$load_rdata_frames(f)
      if (!length(frames)) next
      for (obj in names(frames)) {
        dt <- frames[[obj]]

        # Türkçe yorum: Dosya ve obje adını UTF-8'e çevir, uzantıyı at, sonra sanitize et.
        base_file <- basename(f)
        base_file <- sub("\\.(RData|rda)$", "", base_file, ignore.case = TRUE)
        base_file <- enc2utf8(base_file)
        obj_name  <- enc2utf8(obj)

        stg_name <- paste0(
          "stg_",
          helpers_rdata_lake$sanitize_name(base_file),
          "_",
          helpers_rdata_lake$sanitize_name(obj_name)
        )

        # Türkçe yorum: Tanı kolaylığı için oluşturulan tablo adını logla.
        cat("      -> staging table:", stg_name, "(obj=", obj, ")\n")

        helpers_rdata_lake$write_table(con, dt, stg_name)
        stg_tables <- c(stg_tables, stg_name)

        cols <- names(dt)
        rec <- data.table::data.table(  # data.table fonksiyonunu paket adıyla çağır
          source_file = normalizePath(f, winslash = "/", mustWork = FALSE),
          object_name = obj,
          table_name  = stg_name,
          n_rows      = nrow(dt),
          n_cols      = ncol(dt),
          # Türkçe yorum: JSON'u ASCII'ye zorla; potansiyel problemli baytları kaçışla.
          columns_json = jsonlite::toJSON(cols, auto_unbox = TRUE, ensure_ascii = TRUE),
          loaded_at    = Sys.time()
        )
        new_catalog <- rbind(new_catalog, rec)  # base rbind burada yeterli
      }
    }
  }

  # Katalogu güncelle
	if (nrow(new_catalog)) {
	  # Türkçe: Tablonun tamamını yeniden yaz – ek DELETE gereksiz
	  DBI::dbWriteTable(con, "rd_catalog", as.data.frame(new_catalog), overwrite = TRUE)
	}

  schema <- get0("SCHEMA", inherits = TRUE)
  canon <- if (!is.null(schema) && !is.null(schema$FACT_UNIVERSE_CANON)) {
    schema$FACT_UNIVERSE_CANON
  } else c(
    # SCHEMA yoksa güvenli kanonik alan listesi
    "ProjeKodu","ProjeAdi","SicilNo","KaynakAdi","Yil","Ay","Donem",
    "KalanIscilik_sa","GerceklesenIscilik_sa","Iscilik_sa","ToplamIscilik_sa",
    "AktiviteBaslangic","AktiviteBitis","ProjeDurumu","Direktorluk",
    "MasrafYeri","MasrafYeriKodu","RolAdi","ProjeYoneticisi"
  )

  # Her stg tablo için kesit üret (eksik alanları NULL olarak dök)
  parts <- list()
  for (tb in unique(stg_tables)) {
    # Sütunları öğren
    cols <- try(DBI::dbGetQuery(con, paste0("PRAGMA table_info(", tb, ")"))$name, silent = TRUE)
    if (inherits(cols, "try-error") || is.null(cols)) next
    # Türkçe yorum: Şema varyantlarını ve tiplerini kullanarak kanonik seçme listesi üret.
    sel <- vapply(canon, function(cn) {
      # not: schema_sql_expr, R/schema_registry.R içinde tanımlı yardımcıdır
      schema_sql_expr(cn, available_cols = cols)
    }, character(1))

    parts[[length(parts)+1]] <- sprintf(
      "SELECT %s AS source_table, %s FROM %s",
      DBI::dbQuoteString(con, tb),                         # kaynak tablo adı sabit sütun olarak
      paste(sel, collapse = ", "),                         # kanonik alanlar (TRY_CAST ile)
      DBI::dbQuoteIdentifier(con, tb)                      # gerçek tablo adı güvenli biçimde
    )
  }

  if (length(parts)) {
    # Görünümü güvenle güncelle
    sql_view <- paste0("CREATE OR REPLACE VIEW fact_universe AS \n", paste(parts, collapse = "\nUNION ALL\n"))
    DBI::dbExecute(con, sql_view)
    cat("[RDATA LAKE] fact_universe built with", length(parts), "parts\n")

    # Mevcut kanonik kolonları öğren + veri hacmini logla
    info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
    avail_cols <- if (!inherits(info, "try-error") && nrow(info)) as.character(info$name) else character(0)
    nrow_df <- as.numeric(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM fact_universe")$n %||% 0)
    cat("[RDATA LAKE] fact_universe size: rows=", nrow_df, " cols=", length(avail_cols), "\n")

    # Türkçe yorum: Otomatik boyut tablolarını üret (kişiler & projeler).
    try(helpers_rdata_lake$build_auto_dimensions(con, avail_cols), silent = TRUE)

    # Özet katalog tablosu
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS rd_agg_catalog (
        table_name   TEXT PRIMARY KEY,
        dims_json    TEXT,
        metrics_json TEXT,
        time_grain   TEXT,
        created_at   TIMESTAMP
      );
    ")

    roles <- helpers_rdata_lake$infer_schema_roles(avail_cols)

    # 1) Metric profiles (ağır) — seçenek kapalıysa atla
    if (isTRUE(getOption("mergen.rdata.enable_profiles", TRUE))) {
      # Türkçe: Özet/istatistik profilleri açıkken üret
      try(helpers_rdata_lake$build_metric_profiles(con, roles), silent = FALSE)
    } else {
      cat("[RDATA LAKE] [PROFILE] seçenek kapalı (mergen.rdata.enable_profiles=FALSE) — atlandı\n")
    }

    # 2) Dinamik özetler (ağır) — seçenek kapalıysa atla
    if (isTRUE(getOption("mergen.rdata.enable_aggregates", TRUE))) {
      agg_meta <- helpers_rdata_lake$build_dynamic_aggregates(con, roles)
      if (nrow(agg_meta)) {
        agg_meta$created_at <- Sys.time()
        DBI::dbExecute(con, "DELETE FROM rd_agg_catalog")
        DBI::dbWriteTable(con, "rd_agg_catalog", agg_meta, append = TRUE)
        cat("[RDATA LAKE] dynamic aggregates built: ", nrow(agg_meta), " entries\n")
      } else {
        cat("[RDATA LAKE] no dynamic aggregates created (roles/metrics missing)\n")
      }
    } else {
      cat("[RDATA LAKE] [AGG] seçenek kapalı (mergen.rdata.enable_aggregates=FALSE) — atlandı\n")
    }
    
    # ============================================================================
    # ===== METADATA SİSTEMİ (ağır) — profiller kapalıysa metadata da atla =====
    # ============================================================================
    if (isTRUE(getOption("mergen.rdata.enable_profiles", TRUE))) {
      cat("[RDATA LAKE] =====================================\n")
      cat("[RDATA LAKE] Metadata sistemi başlatılıyor...\n")
      cat("[RDATA LAKE] =====================================\n")
    
    # Metadata helper'ı kontrol et
    if (exists("helpers_rdata_metadata", inherits = TRUE)) {
      
      metadata_start_time <- Sys.time()
      metadata_success <- FALSE
      
      tryCatch({
        # 1. Metadata tablosunu oluştur
        cat("[RDATA LAKE] 1/2: Metadata tablosu oluşturuluyor...\n")
        helpers_rdata_metadata$create_metadata_table(con)
        
        # 2. fact_universe'den metadata topla
        cat("[RDATA LAKE] 2/2: fact_universe analiz ediliyor...\n")
        cat("[RDATA LAKE] (Bu işlem ", nrow_df, " satır için 5-10 dakika sürebilir)\n")
        helpers_rdata_metadata$refresh_metadata(con)
        
        metadata_success <- TRUE
        
        # Metadata istatistikleri
        meta_stats <- try(DBI::dbGetQuery(con, "
          SELECT 
            COUNT(*) AS total_columns,
            SUM(CASE WHEN is_metric THEN 1 ELSE 0 END) AS metrics,
            SUM(CASE WHEN is_dimension THEN 1 ELSE 0 END) AS dimensions
          FROM rd_column_metadata
        "), silent = TRUE)
        
        if (!inherits(meta_stats, "try-error") && nrow(meta_stats)) {
          cat("[RDATA LAKE] =====================================\n")
          cat("[RDATA LAKE] METADATA BAŞARIYLA OLUŞTURULDU! ✓\n")
          cat("[RDATA LAKE] =====================================\n")
          cat("[RDATA LAKE] Toplam sütun   :", meta_stats$total_columns[1], "\n")
          cat("[RDATA LAKE] Metrik sütunlar:", meta_stats$metrics[1], "\n")
          cat("[RDATA LAKE] Boyut sütunları:", meta_stats$dimensions[1], "\n")
          
          elapsed <- as.numeric(difftime(Sys.time(), metadata_start_time, units = "secs"))
          cat("[RDATA LAKE] Süre           :", round(elapsed, 1), "saniye\n")
          cat("[RDATA LAKE] =====================================\n")
        }
        
        # Örnek sütunları göster (debugging için)
        sample_cols <- try(DBI::dbGetQuery(con, "
          SELECT column_name, data_type, is_metric, non_null_count 
          FROM rd_column_metadata 
          ORDER BY non_null_count DESC 
          LIMIT 5
        "), silent = TRUE)
        
        if (!inherits(sample_cols, "try-error") && nrow(sample_cols)) {
          cat("[RDATA LAKE] En çok dolu sütunlar:\n")
          for (i in seq_len(nrow(sample_cols))) {
            r <- sample_cols[i, ]
            cat(sprintf("[RDATA LAKE]   %d. %s (%s) - %s satır\n",
                       i, r$column_name, r$data_type, 
                       format(r$non_null_count, big.mark = ",")))
          }
        }
        
      }, error = function(e) {
        cat("[RDATA LAKE] =====================================\n")
        cat("[RDATA LAKE] METADATA HATASI! ✗\n")
        cat("[RDATA LAKE] =====================================\n")
        cat("[RDATA LAKE] Hata:", conditionMessage(e), "\n")
        cat("[RDATA LAKE] Metadata olmadan devam ediliyor...\n")
        cat("[RDATA LAKE] =====================================\n")
      })
      
      if (metadata_success) {
        # Metadata kalitesini kontrol et
        quality_check <- try({
          null_stats <- DBI::dbGetQuery(con, "
            SELECT 
              COUNT(*) AS high_null_count
            FROM rd_column_metadata
            WHERE (CAST(null_count AS DOUBLE) / NULLIF(null_count + non_null_count, 0)) > 0.8
          ")
          
          if (!inherits(null_stats, "try-error") && null_stats$high_null_count[1] > 0) {
            cat("[RDATA LAKE] UYARI: ", null_stats$high_null_count[1], 
                " sütunda %80'den fazla NULL var\n")
          }
        }, silent = TRUE)
      }
      
		} else {
		  cat("[RDATA LAKE] Metadata helper bulunamadı — atlandı\n")
		}
	}
    # ============================================================================
    # ===== YENİ KOD BİTTİ =====
    # ============================================================================
    
  } else {
    cat("[RDATA LAKE] No staging tables found; fact_universe not created.\n")
  }

  helpers_rdata_lake$catalog <- new_catalog
  
  cat("[RDATA LAKE] =====================================\n")
  cat("[RDATA LAKE] REFRESH TAMAMLANDI! ✓\n")
  cat("[RDATA LAKE] =====================================\n")
  cat("[RDATA LAKE] Staging tabloları :", length(stg_tables), "\n")
  cat("[RDATA LAKE] fact_universe     : OLUŞTURULDU\n")
  if (exists("helpers_rdata_metadata", inherits = TRUE)) {
    cat("[RDATA LAKE] Metadata sistemi  : HAZIR\n")
  } else {
    cat("[RDATA LAKE] Metadata sistemi  : YOK (ekleyin!)\n")
  }
  cat("[RDATA LAKE] =====================================\n")
  
  invisible(TRUE)
}

# Geriye dönük uyumluluk (global isimleri her zaman lake'e yönlendir)
# Türkçe: Eski motoru kesin olarak devre dışı bırak – tek giriş noktası lake olsun.
rdata_engine_init <- function(...) helpers_rdata_lake$rdata_engine_init(...)
rdata_refresh_all <- function(...) helpers_rdata_lake$rdata_refresh_all(...)

.helpers_rewrite_sql_idents <- function(sql, idmap) {
  # Türkçe yorum: Hem tırnaklı hem tırnaksız kimlikleri değiştir.
  s <- sql
  for (k in idmap$keys) {
    v <- idmap$map[[k]]
    # "ProjeNo" → "ProjeKodu"
    pat_q <- paste0('\"', gsub('([\\W])','\\\\\\1', k), '\"')
    rep_q <- paste0('"', v, '"')
    s <- gsub(pat_q, rep_q, s, perl = TRUE)

    # [ProjeNo] → "ProjeKodu"
    pat_b <- paste0('\\[', gsub('([\\W])','\\\\\\1', k), '\\]')
    s <- gsub(pat_b, rep_q, s, perl = TRUE)

    # ProjeNo → ProjeKodu (Unicode kimlik; latinize etmeden, Unicode sınırları)
    pat_u <- paste0('(?<![[:alnum:]_])', gsub('([\\W])','\\\\\\1', k), '(?![[:alnum:]_])')
    s <- gsub(pat_u, v, s, perl = TRUE)
  }
  # Türkçe yorum: Yaygın hata: kapanmayan çift tırnaklı kimlikleri kapat.
  s <- gsub('\"([A-Za-z0-9_]+)(?=\\s|,|\\)|$)', '"\\1"', s, perl = TRUE)
  s
}

# Expose the identifier rewriter under the name the later rdata_sql() expects
helpers_rdata_lake$rewrite_sql_idents <- .helpers_rewrite_sql_idents

# Provide a no-op ident map builder (extend with SCHEMA aliases if you like)
helpers_rdata_lake$build_ident_map <- function(avail_names) {
  # Return an empty map (no rewrites) by default
  list(keys = character(0), map = list())
}

# ---- Şema rollerini çıkar (zaman/varlık/metrik) ----
helpers_rdata_lake$infer_schema_roles <- function(avail_cols) {
  schema <- get0("SCHEMA", inherits = TRUE)
  types  <- if (!is.null(schema) && !is.null(schema$TYPES)) schema$TYPES else list()
  gold   <- if (!is.null(schema) && !is.null(schema$GOLDEN_COLUMNS)) schema$GOLDEN_COLUMNS else character(0)
  ucore  <- if (!is.null(schema) && !is.null(schema$UNION_CORE)) schema$UNION_CORE else character(0)
  mets_l <- if (!is.null(schema) && !is.null(schema$METRICS)) schema$METRICS else list()
  vars   <- if (!is.null(schema) && !is.null(schema$VARIANTS)) schema$VARIANTS else list()

  # Türkçe yorum: Zaman boyutlarını TYPES'tan dinamik seç (DATE/TIMESTAMP vb.); ayrıca yaygın adları da kapsa.
  up_types <- toupper(unlist(types))
  is_time  <- grepl("DATE|TIMESTAMP|DATETIME|TIME", up_types %||% character(0))
  time_from_types <- names(types)[is_time]
  common_time_names <- intersect(c("Yil","Ay","Donem","Tarih","DataDate"), avail_cols)
  time_dims <- unique(intersect(c(time_from_types, common_time_names), avail_cols))

  # Türkçe yorum: Metrikler = METRICS anahtarları ∪ sayısal tipli sütunlar (DOUBLE/DECIMAL/REAL/NUMERIC/INTEGER/BIGINT)
  is_numeric <- grepl("DOUBLE|DECIMAL|REAL|NUMERIC|INTEGER|BIGINT", up_types %||% character(0))
  metric_from_types  <- names(types)[is_numeric]
  metric_from_schema <- names(mets_l)
  metrics0 <- unique(c(metric_from_types, metric_from_schema))
  metrics  <- intersect(metrics0, avail_cols)

  # Türkçe yorum: Aday varlık boyutları = GOLDEN/UNION_CORE/VARIANTS anahtarları
  all_dim_candidates <- unique(c(gold, ucore, names(vars)))
  # TYPES yoksa bile güvenli şekilde mevcut sütunlarla kesiştir
  entity_dims <- setdiff(intersect(all_dim_candidates, avail_cols), unique(c(metrics, time_dims)))

  # Türkçe yorum: Öncelik sırası: UNION_CORE -> GOLDEN -> VARIANTS anahtarları
  prio <- unique(c(ucore, gold, names(vars)))
  entity_dims <- unique(c(intersect(prio, entity_dims), setdiff(entity_dims, prio)))

  list(
    time_dims   = time_dims,
    metrics     = metrics,
    entity_dims = entity_dims
  )
}

# ---- Dinamik özet tabloları üret ve katalogla (Sınırsız + Batch) ----
helpers_rdata_lake$build_dynamic_aggregates <- function(con, roles) {
  # Limits (Inf or <=0 means "no limit")
  max_entity_aggs_opt <- getOption("mergen.rdata.max_entity_aggs", Inf)
  max_metrics_opt     <- getOption("mergen.rdata.max_metrics", Inf)

  dims_ent_all <- roles$entity_dims %||% character(0)
  mets_all     <- roles$metrics %||% character(0)
  t_dims_all   <- roles$time_dims %||% character(0)

  if (!length(dims_ent_all) || !length(mets_all)) return(data.frame())

  n_dims_all <- length(dims_ent_all)
  n_mets_all <- length(mets_all)

  dim_pick_n <- if (!is.finite(max_entity_aggs_opt) || max_entity_aggs_opt <= 0) n_dims_all else min(n_dims_all, as.integer(max_entity_aggs_opt))
  met_pick_n <- if (!is.finite(max_metrics_opt)     || max_metrics_opt     <= 0) n_mets_all else min(n_mets_all, as.integer(max_metrics_opt))

  dim_pick <- dims_ent_all[seq_len(dim_pick_n)]
  mets     <- mets_all[seq_len(met_pick_n)]

  # Keep only time dims that actually exist in the view
  fu_cols <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)")$name, silent = TRUE)
  fu_cols <- if (inherits(fu_cols, "try-error")) character(0) else as.character(fu_cols)
  t_dims  <- intersect(t_dims_all, fu_cols)

  qid <- function(x) DBI::dbQuoteIdentifier(con, x)
  sanitize <- helpers_rdata_lake$sanitize_name

  sum_exprs <- paste(sprintf('SUM(TRY_CAST(%s AS DOUBLE)) AS %s', qid(mets), qid(mets)), collapse = ", ")

  meta_rows <- list()
  created_ct <- 0L

  for (dim in dim_pick) {
    dim_q <- qid(dim)

    # (1) No time grain
    tbl1 <- paste0("agg_", sanitize(dim))
    sql1 <- sprintf("
      CREATE OR REPLACE TABLE %s AS
      SELECT %s, %s
      FROM fact_universe
      GROUP BY %s
    ", qid(tbl1), dim_q, sum_exprs, dim_q)
    try(DBI::dbExecute(con, sql1), silent = TRUE); created_ct <- created_ct + 1L
    meta_rows[[length(meta_rows)+1]] <- data.frame(
      table_name   = tbl1,
      dims_json    = jsonlite::toJSON(list(dim), auto_unbox = TRUE),
      metrics_json = jsonlite::toJSON(unname(mets), auto_unbox = TRUE),
      time_grain   = "none",
      stringsAsFactors = FALSE
    )

    # (2) Single time dimension
    if (length(t_dims)) {
      for (td in t_dims) {
        td_q <- qid(td); tg <- tolower(td)
        tblt <- paste0("agg_", sanitize(dim), "_", sanitize(tg))
        sqlt <- sprintf("
          CREATE OR REPLACE TABLE %s AS
          SELECT %s, %s, %s
          FROM fact_universe
          GROUP BY %s, %s
        ", qid(tblt), dim_q, td_q, sum_exprs, dim_q, td_q)
        try(DBI::dbExecute(con, sqlt), silent = TRUE); created_ct <- created_ct + 1L
        meta_rows[[length(meta_rows)+1]] <- data.frame(
          table_name   = tblt,
          dims_json    = jsonlite::toJSON(list(dim, td), auto_unbox = TRUE),
          metrics_json = jsonlite::toJSON(unname(mets), auto_unbox = TRUE),
          time_grain   = tg,
          stringsAsFactors = FALSE
        )
      }
    }

    # (3) Pair of first two time dimensions (e.g., Yil+Ay)
    if (length(t_dims) >= 2) {
      td1 <- t_dims[1]; td2 <- t_dims[2]
      td1_q <- qid(td1); td2_q <- qid(td2)
      tg <- paste0(tolower(td1), "_", tolower(td2))
      tblp <- paste0("agg_", sanitize(dim), "_", sanitize(tg))
      sqlp <- sprintf("
        CREATE OR REPLACE TABLE %s AS
        SELECT %s, %s, %s, %s
        FROM fact_universe
        GROUP BY %s, %s, %s
      ", qid(tblp), dim_q, td1_q, td2_q, sum_exprs, dim_q, td1_q, td2_q)
      try(DBI::dbExecute(con, sqlp), silent = TRUE); created_ct <- created_ct + 1L
      meta_rows[[length(meta_rows)+1]] <- data.frame(
        table_name   = tblp,
        dims_json    = jsonlite::toJSON(list(dim, td1, td2), auto_unbox = TRUE),
        metrics_json = jsonlite::toJSON(unname(mets), auto_unbox = TRUE),
        time_grain   = tg,
        stringsAsFactors = FALSE
      )
    }
  }

  cat("[RDATA LAKE] [AGG] created tables: ", created_ct, "\n")
  if (!length(meta_rows)) return(data.frame())
  do.call(rbind, meta_rows)
}

# ---- Metrik profil tablolarını oluştur (tam kapsam + batch + log) ----
helpers_rdata_lake$build_metric_profiles <- function(con, roles) {
  # Türkçe yorum: Metrik profillerini güvenle oluştur; eksik değişken ve tablo hatalarını gider.
  max_prof_opt <- getOption("mergen.rdata.max_metrics_profile", Inf)
  batch_size   <- as.integer(getOption("mergen.rdata.profile_batch_size", 50L))
  sample_frac  <- as.numeric(getOption("mergen.rdata.profile_sample_frac", 1.0))
  if (!is.finite(sample_frac) || sample_frac <= 0 || sample_frac > 1) sample_frac <- 1.0

  # Tablo var mı? Yoksa profil üretmeye çalışma.
  if (!DBI::dbExistsTable(con, "fact_universe")) {
    cat("[RDATA LAKE] [PROFILE] fact_universe yok; atlanıyor\n")
    return(invisible(FALSE))
  }

  # Hedef tabloyu oluştur (yoksa)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS rd_metric_profiles (
      metric_name TEXT,
      row_count   BIGINT,
      non_null    BIGINT,
      distinct_non_null BIGINT,
      sum         DOUBLE,
      avg         DOUBLE,
      min         DOUBLE,
      max         DOUBLE,
      p50         DOUBLE,
      p90         DOUBLE,
      p99         DOUBLE,
      zero_count  BIGINT,
      neg_count   BIGINT,
      created_at  TIMESTAMP
    )
  ")

  # Türkçe yorum: Kullanılacak metrik listesi (rollerden; boşsa sayısal tipli mevcut kolonlardan türet)
  avail <- DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)")
  avail_cols <- as.character(avail$name %||% character(0))
  mets_from_roles <- roles$metrics %||% character(0)
  mets <- intersect(unique(mets_from_roles), avail_cols)

  if (!length(mets)) {
    # TYPES üzerinden sayısal seç (varsa)
    schema <- get0("SCHEMA", inherits = TRUE)
    types  <- if (!is.null(schema) && !is.null(schema$TYPES)) schema$TYPES else list()
    up_types <- toupper(unlist(types %||% list()))
    numeric_types <- c("DOUBLE","DECIMAL","INTEGER","BIGINT","REAL","NUMERIC")
    numeric_from_types <- names(types)[up_types %in% numeric_types]
    mets <- intersect(unique(numeric_from_types), avail_cols)
  }

  # Sınır uygula (Inf veya <=0 ise tümü)
  if (is.finite(max_prof_opt) && max_prof_opt > 0) {
    mets <- head(mets, as.integer(max_prof_opt))
  }

  if (!length(mets)) {
    cat("[RDATA LAKE] [PROFILE] uygun metrik yok; atlanıyor\n")
    return(invisible(FALSE))
  }

  total_rows <- as.numeric(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM fact_universe")$n %||% 0)
  cat("[RDATA LAKE] [PROFILE] start; metrics=", length(mets), " rows=", total_rows,
      " sample_frac=", sample_frac, "\n")

  # Türkçe yorum: Örnekleme kaynağı
  src_from <- if (sample_frac < 1 && is.finite(total_rows) && total_rows > 0) {
    sample_rows <- max(1L, as.integer(ceiling(total_rows * sample_frac)))
    sprintf("fact_universe TABLESAMPLE RESERVOIR(%d ROWS)", sample_rows)
  } else {
    "fact_universe"
  }

  # Türkçe yorum: Her metrik için profil sorgusu üret (TRY_CAST ile güvenli)
  make_q <- function(m) sprintf("
    SELECT
      %s AS metric_name,
      %d AS row_count,
      COUNT(x) AS non_null,
      COUNT(DISTINCT x) AS distinct_non_null,
      SUM(x) AS sum,
      AVG(x) AS avg,
      MIN(x) AS min,
      MAX(x) AS max,
      QUANTILE(x, 0.5)  AS p50,
      QUANTILE(x, 0.9)  AS p90,
      QUANTILE(x, 0.99) AS p99,
      SUM(CASE WHEN x = 0 THEN 1 ELSE 0 END) AS zero_count,
      SUM(CASE WHEN x < 0 THEN 1 ELSE 0 END) AS neg_count,
      CURRENT_TIMESTAMP AS created_at
    FROM (
      SELECT TRY_CAST(%s AS DOUBLE) AS x
      FROM %s
    ) t
  ",
    DBI::dbQuoteString(con, m),
    total_rows,
    DBI::dbQuoteIdentifier(con, m),
    src_from
  )

  # Türkçe yorum: Batch'lere böl ve tabloyu temizleyip yeniden doldur
  DBI::dbExecute(con, "DELETE FROM rd_metric_profiles")
  chunks <- split(mets, ceiling(seq_along(mets) / max(1L, batch_size)))
  t0 <- Sys.time(); done <- 0L

  for (idx in seq_along(chunks)) {
    tb  <- Sys.time()
    grp <- chunks[[idx]]
    qry <- paste(vapply(grp, make_q, character(1)), collapse = "\nUNION ALL\n")

    ok <- TRUE
    tryCatch(
      DBI::dbExecute(con, sprintf("INSERT INTO rd_metric_profiles %s", qry)),
      error = function(e) { ok <<- FALSE; cat("[RDATA LAKE] [PROFILE] error: ", conditionMessage(e), "\n") }
    )

    if (!ok && identical(src_from, "fact_universe") == FALSE) {
      # Türkçe yorum: Örnekleme hatasında tam veriyle tekrar dene
      backup_src <- "fact_universe"
      make_q_full <- function(m) sub(sprintf("\\bFROM\\s+%s\\b", src_from), paste("FROM", backup_src), make_q(m))
      qry2 <- paste(vapply(grp, make_q_full, character(1)), collapse = "\nUNION ALL\n")
      DBI::dbExecute(con, sprintf("INSERT INTO rd_metric_profiles %s", qry2))
    }

    done <- done + length(grp)
    cat(sprintf("[RDATA LAKE] [PROFILE] batch %d/%d (metrics %d/%d) duration_s=%.1f\n",
                idx, length(chunks), done, length(mets),
                as.numeric(difftime(Sys.time(), tb, units = "secs"))))
  }

  dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat("[RDATA LAKE] [PROFILE] finished; metrics=", done, " duration_s=", round(dur, 1), "\n")
  invisible(TRUE)
}

# ---- Otomatik boyut tablolarını üret (kişiler / projeler) ----
helpers_rdata_lake$build_auto_dimensions <- function(con, avail_cols) {
  qid <- function(x) DBI::dbQuoteIdentifier(con, x)

  # Türkçe yorum: Boş/whitespace kabul etmeyen VARCHAR dönüşümü
  nn_sql <- function(col) sprintf("NULLIF(TRIM(CAST(%s AS VARCHAR)), '')", qid(col))

  # Türkçe yorum: Label adaylarını mevcut kolonlara göre filtrele
  pick_coalesce <- function(cands) {
    cands <- intersect(cands, avail_cols)
    if (!length(cands)) return(NULL)
    paste(vapply(cands, nn_sql, character(1)), collapse = ", ")
  }

  # ----- dim_person -----
  if ("SicilNo" %in% avail_cols) {
    # Türkçe yorum: Kişi adı için yaygın kolon isimleri; mevcut olanlar kullanılır.
    person_name_candidates <- c("KaynakAdi","AdSoyad","Kaynak","Kaynak_Adi","PersonelAdi","PersonelAdSoyad","Ad")
    coalesce_expr <- pick_coalesce(person_name_candidates)

    if (!is.null(coalesce_expr)) {
      sql_person <- sprintf("
        CREATE OR REPLACE TABLE dim_person AS
        WITH candidates AS (
          SELECT
            %s AS SicilNo,
            COALESCE(%s) AS AdSoyad
          FROM fact_universe
        )
        SELECT SicilNo, ANY_VALUE(AdSoyad) AS AdSoyad
        FROM candidates
        WHERE SicilNo IS NOT NULL AND AdSoyad IS NOT NULL
        GROUP BY SicilNo
      ", qid("SicilNo"), coalesce_expr)

      # Türkçe yorum: Oluştur (hata çıkarsa es geç)
      try(DBI::dbExecute(con, sql_person), silent = TRUE)
    }
  }

  # ----- dim_project -----
  if ("ProjeKodu" %in% avail_cols) {
    # Türkçe yorum: Proje adı için yaygın kolon isimleri; mevcut olanlar kullanılır.
    project_name_candidates <- c("ProjeAdi","Proje_Adi","Proje Adi","ProjeIsmi","ProjeIsmiFull")
    coalesce_expr <- pick_coalesce(project_name_candidates)

    if (is.null(coalesce_expr)) {
      # Türkçe yorum: Label kolon yoksa kodu label olarak kullan (VARCHAR'a döndür).
      coalesce_expr <- nn_sql("ProjeKodu")
    }

    sql_project <- sprintf("
      CREATE OR REPLACE TABLE dim_project AS
      WITH candidates AS (
        SELECT
          %s AS ProjeKodu,
          COALESCE(%s) AS ProjeAdi
        FROM fact_universe
      )
      SELECT ProjeKodu, ANY_VALUE(ProjeAdi) AS ProjeAdi
      FROM candidates
      WHERE ProjeKodu IS NOT NULL AND ProjeAdi IS NOT NULL
      GROUP BY ProjeKodu
    ", qid("ProjeKodu"), coalesce_expr)

    # Türkçe yorum: Oluştur (hata çıkarsa es geç)
    try(DBI::dbExecute(con, sql_project), silent = TRUE)
  }

  invisible(TRUE)
}

# ---- İstenen sütunlar için kaynak tablo öner (smart query desteği) ----
helpers_rdata_lake$suggest_source_tables_for_columns <- function(required_cols,
                                                                 top_n = 5,
                                                                 sample_frac = getOption("mergen.rdata.source_suggest_sample_frac", 1.0)) {
  # Türkçe: Girdi kontrolü
  if (is.null(required_cols)) required_cols <- character(0)
  required_cols <- unique(as.character(required_cols))
  if (!length(required_cols)) return(data.frame())

  # Türkçe: Bağlantıyı aç ve fact_universe görünümünü doğrula
  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  exists_fu <- FALSE
  try({
    q <- DBI::dbGetQuery(con, "SELECT 1 FROM information_schema.tables WHERE table_name ILIKE 'fact_universe' LIMIT 1")
    exists_fu <- nrow(q) > 0
  }, silent = TRUE)

  if (!exists_fu) {
    # Türkçe: Görünüm yoksa yenilemeyi tetikle ve tekrar dene
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
    try(helpers_rdata_lake$rdata_refresh_all(), silent = TRUE)
    con <- helpers_rdata_lake$db_connect(readonly = TRUE)
    on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
  }

  # Türkçe: Mevcut kanonik sütunları al
  info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  avail_cols <- if (!inherits(info, "try-error") && nrow(info)) as.character(info$name) else character(0)

  # Türkçe: Sadece fact_universe'de gerçekten bulunan sütunlarla ilerle
  req <- intersect(required_cols, avail_cols)
  if (!length(req)) return(data.frame())

  # Türkçe: Örnekleme (ağır veri için sistem yüzdesi ile yaklaşık örnek)
  src_from <- "fact_universe"
  if (is.numeric(sample_frac) && is.finite(sample_frac) && sample_frac > 0 && sample_frac < 1) {
    # DuckDB: SYSTEM(PERCENT) örnekleme
    src_from <- sprintf("fact_universe TABLESAMPLE SYSTEM(%.4f PERCENT)", sample_frac * 100)
  }

  # Türkçe: Her istenen sütun için NOT NULL sayacı üret
  nn_exprs <- paste(
    vapply(req, function(cn) {
      sprintf('SUM(CASE WHEN %s IS NOT NULL THEN 1 ELSE 0 END) AS %s',
              DBI::dbQuoteIdentifier(con, cn),
              DBI::dbQuoteIdentifier(con, paste0(cn, "__nn")))
    }, character(1)),
    collapse = ", "
  )

  # Türkçe: Kaynak tablo bazında kapsama istatistiği hesapla
  sql <- sprintf("
    SELECT source_table, %s, COUNT(*) AS __rows__
    FROM %s
    GROUP BY source_table
  ", nn_exprs, src_from)

  df <- try(DBI::dbGetQuery(con, sql), silent = TRUE)
  if (inherits(df, "try-error") || !nrow(df)) return(data.frame())

	# Türkçe: Kapsanan sütun sayısı / toplam istenen sütun sayısı
	nn_cols <- paste0(req, "__nn")
	df[["__covered__"]]    <- rowSums(df[, nn_cols, drop = FALSE] > 0)
	df[["__need__"]]       <- length(req)
	df[["coverage_ratio"]] <- ifelse(df[["__need__"]] > 0, df[["__covered__"]] / df[["__need__"]], 0)

	# Türkçe: Sıralama — önce kapsama oranı, sonra toplam NOT NULL, sonra satır
	df[["__nn_sum__"]] <- rowSums(df[, nn_cols, drop = FALSE])
	ord <- order(-df[["coverage_ratio"]], -df[["__nn_sum__"]], -df[["__rows__"]])
	df  <- df[ord, , drop = FALSE]

  # Türkçe: Eksik sütun listesini üret
  df$missing_cols <- vapply(seq_len(nrow(df)), function(i) {
    miss <- req[ df[i, nn_cols, drop = FALSE] == 0 ]
    paste(miss, collapse = ",")
  }, character(1))

  # Türkçe: Sonuç sütunlarını sadeleştir
  out <- df[, c("source_table", "coverage_ratio", "__covered__", "__need__", "__rows__", "missing_cols"), drop = FALSE]
  names(out) <- c("source_table", "coverage_ratio", "covered_cols", "required_cols", "row_count", "missing_cols")

  # Türkçe: İlk N öneriyi döndür
  utils::head(out, as.integer(top_n)[1])
}

# ---- Yardımcı: kaynak tablo önerisini vector olarak döndür (wrapper) ----
helpers_rdata_lake$suggest_source_tables_for <- function(required_cols, top_n = 5) {
  # Türkçe: suggest_source_tables_for_columns çağır ve sadece source_table vector'ünü döndür
  df <- helpers_rdata_lake$suggest_source_tables_for_columns(required_cols, top_n = top_n)
  if (!is.data.frame(df) || !nrow(df)) return(character(0))
  
  # Türkçe: Sadece tam kapsama (coverage_ratio >= 0.8) olanları al
  good <- df[df$coverage_ratio >= 0.8, , drop = FALSE]
  if (!nrow(good)) {
    # Türkçe: Tam kapsama yoksa en iyi 2 tanesini al
    good <- utils::head(df, min(2, nrow(df)))
  }
  
  as.character(good$source_table)
}

# ---- Metin tabanlı arama (tablo/sütun) ----
helpers_rdata_lake$rdata_search <- function(text, limit = 10) {  # metin tabanlı arama
  # Katalog üzerinde kopya ile çalış; yerinde (by reference) değişiklik yapma
  catv <- data.table::copy(helpers_rdata_lake$catalog)
  if (!nrow(catv)) {
    try(rdata_refresh_all(), silent = TRUE)
    catv <- data.table::copy(helpers_rdata_lake$catalog)
    if (!nrow(catv)) return(list(error = "Katalog boş; önce yenileyin."))
  }
  if (!nzchar(text)) return(list(error = "Arama ifadesi boş"))

  q <- tolower(stringi::stri_trans_general(text, "Latin-ASCII"))
  # Aday skor: tablo adı ve kaynak dosya adına fuzzy skor (kopya tabloya yaz)
  catv[, simple := tolower(paste(table_name, basename(source_file)))]
  catv[, score := 1 - stringdist::stringdist(q, simple, method = "jw")]
  top <- head(catv[order(-score)][, .(table_name, object_name, source_file, score, n_rows, n_cols)], limit)
  cat("[RDATA_LAKE] search text=", encodeString(text), " hit_n=", nrow(top), "\n")

  list(
    eşleşmeler = as.data.frame(top)
  )
}

# ---- Proje metrikleri (örnek) ----
helpers_rdata_lake$rdata_metrics <- function(proje_adi = NULL, proje_kodu = NULL) {
  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))

  cat("[RDATA_METRICS] begin; filters: proje_adi=", encodeString(proje_adi %||% ""),
      " proje_kodu=", encodeString(proje_kodu %||% ""), "\n")

  # Türkçe: fact_universe yoksa yenile
  exists_now <- try(DBI::dbExistsTable(con, "fact_universe"), silent = TRUE)
  if (inherits(exists_now, "try-error") || !isTRUE(exists_now)) {
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
    try(helpers_rdata_lake$rdata_refresh_all(), silent = TRUE)
    con <- helpers_rdata_lake$db_connect(readonly = TRUE)
    on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = FALSE)
    try(DBI::dbExecute(con, "PRAGMA invalidate"), silent = TRUE)
  }

  info <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"), silent = TRUE)
  avail_cols <- if (!inherits(info, "try-error") && nrow(info)) as.character(info$name) else character(0)
  roles <- helpers_rdata_lake$infer_schema_roles(avail_cols)
  mets  <- roles$metrics %||% character(0)

  pref_ids <- intersect(c("ProjeKodu","ProjeAdi"), avail_cols)
  fallback_ids <- roles$entity_dims %||% character(0)
  id_dims <- unique(c(pref_ids, head(fallback_ids, 2)))

  where_parts <- c()
  if (is.character(proje_kodu) && nzchar(proje_kodu[1]) && "ProjeKodu" %in% avail_cols) {
    where_parts <- c(where_parts,
      sprintf('"ProjeKodu" ILIKE %s', DBI::dbQuoteString(con, paste0("%", proje_kodu[1], "%"))))
  }
  if (is.character(proje_adi) && nzchar(proje_adi[1]) && "ProjeAdi" %in% avail_cols) {
    where_parts <- c(where_parts,
      sprintf('"ProjeAdi" ILIKE %s', DBI::dbQuoteString(con, paste0("%", proje_adi[1], "%"))))
  }

  wc <- if (length(where_parts)) paste("WHERE", paste(where_parts, collapse = " AND ")) else ""

  met_sql <- if (length(mets)) paste(sprintf('SUM(TRY_CAST("%s" AS DOUBLE)) AS "%s"', mets, mets), collapse = ", ") else ""

  if (length(where_parts)) {
    # Türkçe: Filtre varsa tek satır özet döndür (eski davranış)
    id_sql  <- if (length(id_dims)) paste(sprintf('ANY_VALUE("%s") AS "%s"', id_dims, id_dims), collapse = ", ") else "COUNT(*) AS KayitSayisi"
    sql <- sprintf('
      WITH base AS (SELECT * FROM fact_universe %s)
      SELECT %s%s%s
      FROM base
    ', wc, id_sql, if (nzchar(met_sql)) paste0(", ", met_sql) else "", "")
  } else {
    # Türkçe: Filtre yoksa en büyük projeyi seç; ProjeKodu yoksa ilk varlık boyutunu kullan
    key <- if ("ToplamIscilik_sa" %in% mets) '"ToplamIscilik_sa"' else sprintf('"%s"', mets[1])
    dim_fallback <- if ("ProjeKodu" %in% avail_cols) "ProjeKodu" else {
      fk <- roles$entity_dims %||% character(0)
      if (length(fk)) fk[1] else NA_character_
    }
    grp_expr <- if (!is.na(dim_fallback)) sprintf('"%s"', dim_fallback) else NULL

    id_sql <- paste(c(
      if ("ProjeAdi"  %in% avail_cols) 'ANY_VALUE("ProjeAdi")  AS "ProjeAdi"'  else NULL,
      if ("ProjeKodu" %in% avail_cols) 'ANY_VALUE("ProjeKodu") AS "ProjeKodu"' else NULL,
      if (!("ProjeKodu" %in% avail_cols) && !is.na(dim_fallback))
        sprintf('ANY_VALUE("%s") AS "%s"', dim_fallback, dim_fallback) else NULL
    ), collapse = ", ")

    sql <- sprintf('
      SELECT %s%s
      FROM fact_universe
      %s
      ORDER BY %s DESC
      LIMIT 1
    ',
      if (nzchar(id_sql)) id_sql else 'COUNT(*) AS "KayitSayisi"',
      if (nzchar(met_sql)) paste0(", ", met_sql) else "",
      if (!is.null(grp_expr)) paste("GROUP BY", grp_expr) else "",
      key
    )
  }

  cat("[RDATA_METRICS] SQL=", gsub("\\s+"," ", sql), "\n")
  ans <- tryCatch(DBI::dbGetQuery(con, sql), error = function(e) e)
  if (inherits(ans, "error")) return(list(error = ans$message))
  cat("[RDATA_METRICS] ok rows=", nrow(ans), "\n")

  row <- if (nrow(ans)) ans[1, , drop = FALSE] else data.frame()
  out <- list()
  for (d in c("ProjeAdi","ProjeKodu")) if (d %in% names(row)) out[[d]] <- row[[d]] %||% ""
  for (m in mets) out[[m]] <- suppressWarnings(as.numeric(row[[m]] %||% NA))

  # Türkçe: Basit ilerleme yüzdesi (varsa)
  had_progress <- FALSE
  try({
    ger_idx <- grep("GERCEKLESEN|REAL|ACTUAL", toupper(names(out)), perl = TRUE)
    top_idx <- grep("TOPLAM|PLAN|TOTAL",        toupper(names(out)), perl = TRUE)
    if (length(ger_idx) && length(top_idx)) {
      gv <- as.numeric(out[[names(out)[ger_idx[1]]]] %||% NA)
      tv <- as.numeric(out[[names(out)[top_idx[1]]]] %||% NA)
      if (is.finite(gv) && is.finite(tv) && tv > 0) {
        out$ilerleme_yuzde <- round(100 * gv/tv, 1)
        had_progress <- TRUE
      }
    }
  }, silent = TRUE)
  if (!had_progress) out$ilerleme_yuzde <- NULL

  out
}

# Türkçe: OpenAI uyumlu araç şeması — rdata ailesi için tek doğru sürüm
helpers_rdata_lake$get_openai_tools_extra <- function() {
  list(
    tools = list(
      list(
        type = "function",
        `function` = list(
          name = "rdata_column_search",
          description = "Sütun adlarında arama yap. Hangi sütunların olduğunu öğrenmek için MUTLAKA kullan!",
          parameters = list(
            type = "object",
            properties = list(
              query = list(type = "string", description = "Aranacak kelime (örn: 'iscilik', 'proje', 'yil')")
            ),
            required = list("query")
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "rdata_smart_query",
          description = "Akıllı sorgu: boyut ve metrik adlarını (yaklaşık) ver, SQL otomatik oluşturulur (LIMIT kullanma, source_table alanını dahil et)",
          parameters = list(
            type = "object",
            properties = list(
              dimensions = list(type = "array", items = list(type = "string"),
                                description = "Boyut sütunları (örn: ['proje', 'yil'])"),
              metrics    = list(type = "array", items = list(type = "string"),
                                description = "Metrik sütunları (örn: ['iscilik', 'kalan'])"),
              filters    = list(type = "object", description = "Filtreler (örn: {yil: 2024})")
            ),
            required = list()  # Türkçe: zorunlu alan yok; model içeriğe göre doldurur
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "rdata_sql",
          description = "DuckDB SQL sorgusu çalıştır (fact_universe). LIMIT/TOP yok, source_table sütununu da seç.",
          parameters = list(
            type = "object",
            properties = list(
              sql          = list(type = "string",  description = "SELECT sorgusu")
            ),
            required = list("sql")
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "rdata_metrics",
          description = "Projeye özel temel metrikler",
          parameters = list(
            type = "object",
            properties = list(
              proje_adi  = list(type = "string", description = "Proje adı"),
              proje_kodu = list(type = "string", description = "Proje kodu")
            ),
            required = list()  # Türkçe: ikisinden biri yeterli; bu yüzden zorunlu alan belirtmiyoruz
          )
        )
      ),
      list(
        type = "function",
        `function` = list(
          name = "rdata_ask",
          description = "Serbest soru: anlam çıkar ve uygun SQL ile yanıtla",
          parameters = list(
            type = "object",
            properties = list(
              question = list(type = "string",  description = "Doğal dilde soru")
            ),
            required = list("question")
          )
        )
      )
    )
  )
}

# Türkçe: Ollama vb. modeller için metinsel araç çağrısı ayrıştırıcı (JSON/SQL)
helpers_rdata_lake$parse_tool_calls_from_text_json <- function(txt) {
  out <- list()
  if (!is.character(txt) || !nzchar(txt[1])) return(out)
  s <- txt[1]

  # 1) JSON tarzı { "tool":"rdata_sql", "arguments":{...} } yakalamaya çalış
  jre <- gregexpr("\\{\\s*\"(tool|name)\"\\s*:\\s*\"rdata_[a-z_]+\"[\\s\\S]*?\\}", s, perl = TRUE)
  if (jre[[1]][1] > 0) {
    for (i in seq_along(jre[[1]])) {
      frag <- substr(s, jre[[1]][i], jre[[1]][i] + attr(jre[[1]], "match.length")[i] - 1)
      obj <- try(jsonlite::fromJSON(frag, simplifyVector = FALSE), silent = TRUE)
      if (!inherits(obj, "try-error") && is.list(obj)) {
        fn <- obj$tool %||% obj$name
        args <- obj$arguments %||% obj$args %||% list()
        if (is.character(fn) && grepl("^rdata_", fn)) {
          out[[length(out) + 1]] <- list(function_name = fn, arguments = args)
        }
      }
    }
  }

  # 2) ```sql ... ``` bloğu → rdata_sql
  m <- regexpr("```(?:sql)?\\s*(SELECT[\\s\\S]*?)```", s, perl = TRUE, ignore.case = TRUE)
  if (m > 0) {
    sql <- regmatches(s, m)
    sql <- sub("^```(?:sql)?\\s*", "", sql, perl = TRUE)
    sql <- sub("```\\s*$", "", sql, perl = TRUE)
    out[[length(out) + 1]] <- list(function_name = "rdata_sql", arguments = list(sql = sql, limit = 200))
  }

  out
}

# Türkçe: Tek giriş — her iki ayrıştırıcıyı birleştir
helpers_rdata_lake$parse_tool_calls_from_text <- function(txt) {
  c(
    helpers_rdata_lake$parse_tool_calls_from_text_legacy(txt),
    helpers_rdata_lake$parse_tool_calls_from_text_json(txt)
  )
}

# rData araçları için metinsel JSON çağrı yönergesi
helpers_rdata_lake$get_rdata_tools_prompt <- function() {
  paste(
    "Sadece aşağıdaki rData araçlarını kullan. Tek bir JSON araç çağrısı üret ve aracın döndürdüğü TÜM satırları Türkçe açıkla.",
    "",
    "Kırmızı çizgiler:",
    "- fact_universe üzerindeki sorgularda LIMIT/TOP/SAMPLE benzeri kısıtlar kullanma; tüm veriyi işle.",
    "- Her sorguda source_table sütununu da getir ve yanıtta hangi tablolardan geldiğini belirt.",
    "- Sorunun gerektirdiği tüm filtreleme, grupla, sıralama veya toplulaştırmaları SQL içinde uygula.",
    "- Tamamen NA olan sütunları sonuçta gösterme.",
    "- Yalnızca veritabanından gelen gerçek değerleri raporla; uydurma bilgi ekleme.",
    "",
    "Araçlar:",
    "1) rdata_search(text) — RData Lake kataloğunda tablo/sütun ara (SQL üretmez).",
    "2) rdata_sql(sql) — DuckDB uyumlu SELECT çalıştırır (varsayılan tablo: fact_universe).",
    "3) rdata_metrics(proje_adi, proje_kodu) — belirli proje metriklerini getirir.",
    "",
    "JSON örneği:",
    "{\"name\":\"rdata_sql\",\"arguments\":{\"sql\":\"SELECT source_table, ... FROM fact_universe WHERE ...\"}}",
    "",
    "Dosya (Excel/CSV) araçlarını KULLANMA; sadece rdata_* araçlarını kullan.",
    sep = "\n"
  )
}

# geriye dönük uyumluluk (araç isimlerini kesin olarak lake'e yönlendir)
rdata_sql     <- function(...) { cat("[RDATA_LAKE] shim rdata_sql(file) -> lake\n");     helpers_rdata_lake$rdata_sql(...) }
rdata_search  <- function(...) { cat("[RDATA_LAKE] shim rdata_search(file) -> lake\n");  helpers_rdata_lake$rdata_search(...) }
rdata_metrics <- function(...) { cat("[RDATA_LAKE] shim rdata_metrics(file) -> lake\n"); helpers_rdata_lake$rdata_metrics(...) }

# --- Uyumluluk: eski rdata_sql_query API'sini destekle ---
if (!exists("rdata_sql_query", inherits = FALSE)) {
  rdata_sql_query <- function(sql, limit = NULL) {
    # Türkçe yorum: Lake'in rdata_sql çıktısını data.frame'e çevirip döndür.
    res <- helpers_rdata_lake$rdata_sql(sql, preview_rows = limit)
    if (is.list(res) && !is.null(res$error)) stop(res$error)
    if (is.list(res) && is.data.frame(res$sonuç_önizleme)) return(res$sonuç_önizleme)
    data.frame()
  }
}

# Kolay konsol önizleme yardımcıları
helpers_rdata_lake$peek_fact_universe <- function(n = 5) {
  # Türkçe yorum: fact_universe'den ilk n satırı getir.
  q <- sprintf("SELECT * FROM fact_universe LIMIT %d", as.integer(n))
  res <- helpers_rdata_lake$rdata_sql(q, preview_rows = n)
  if (is.list(res) && is.data.frame(res$`sonuç_önizleme`)) print(res$`sonuç_önizleme`) else print(res)
  invisible(res)
}

# --- Hızlı durum denetimi: fact_universe var mı, satır/sütun kaç? ---
helpers_rdata_lake$fact_universe_status <- function(n = 5, do_log = TRUE) {
  # Türkçe: Bağlantı aç
  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))

  # Türkçe: Varlık kontrolü
  exists <- FALSE
  try({
    q <- DBI::dbGetQuery(con, "SELECT 1 FROM information_schema.tables WHERE table_name ILIKE 'fact_universe' LIMIT 1")
    exists <- nrow(q) > 0
  }, silent = TRUE)

  if (!exists) {
    if (isTRUE(do_log)) cat("[RDATA LAKE] fact_universe: YOK\n")
    return(list(exists = FALSE, rows = 0L, cols = 0L, sample = data.frame()))
  }

  # Türkçe: Satır/sütun bilgisi
  rows <- NA_real_
  cols <- 0L
  sample <- data.frame()

  try(rows <- as.numeric(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM fact_universe")$n %||% 0), silent = TRUE)
  try(cols <- as.integer(nrow(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)"))), silent = TRUE)
  if (is.finite(n) && n > 0) {
    sample <- try(DBI::dbGetQuery(con, sprintf("SELECT * FROM fact_universe LIMIT %d", as.integer(n))), silent = TRUE)
    if (inherits(sample, "try-error")) sample <- data.frame()
  }

  if (isTRUE(do_log)) {
    cat(sprintf("[RDATA LAKE] fact_universe durum: satır=%s sütun=%s\n",
                format(rows, big.mark = ","), cols))
  }

  list(exists = TRUE, rows = rows, cols = cols, sample = sample)
}

# --- Yardımcı: fact_universe var mı? yoksa oluştur ---
helpers_rdata_lake$ensure_fact_universe <- function() {
  con <- helpers_rdata_lake$db_connect(readonly = FALSE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE))
  exists <- FALSE
  # Türkçe: VIEW var mı?
  try({
    q <- DBI::dbGetQuery(con, "SELECT 1 FROM information_schema.tables WHERE table_name ILIKE 'fact_universe' LIMIT 1")
    exists <- nrow(q) > 0
  }, silent = TRUE)

  if (!exists) {
    # Türkçe: Görünüm yoksa hafif yenile çalıştır (ağır işler seçeneklerle zaten kapalı olabilir)
    cat("[RDATA LAKE] ensure_fact_universe(): görünüm yok — hafif yenile çalıştırılıyor\n")
    try(helpers_rdata_lake$rdata_refresh_all(), silent = TRUE)
  }
  invisible(TRUE)
}

# ---- SQL'e otomatik source_table filtresi enjekte et ----
helpers_rdata_lake$inject_source_table_filter <- function(sql_txt) {
  # Türkçe: fact_universe geçen sorgularda, JOIN/alias bozulmadan source_table filtresi ekle
  cat("\n========== [INJECT_FILTER] BAŞLANGIÇ ==========\n")
  cat("[INJECT_FILTER] Gelen SQL:\n", sql_txt, "\n")

	# 1) fact_universe yoksa çık
	if (!grepl("\\bfact_universe\\b", sql_txt, ignore.case = TRUE, perl = TRUE)) {
	  cat("[INJECT_FILTER] fact_universe yok, atlanıyor\n")
	  return(sql_txt)
	}

  # 2) Kullanıcı zaten source_table ile filtreliyorsa dokunma
  if (grepl("\\bsource_table\\b", sql_txt, ignore.case = TRUE, perl = TRUE)) {
    cat("[INJECT_FILTER] source_table ifadesi mevcut, atlanıyor\n")
    return(sql_txt)
  }

  # 3) Hangi kolonlar kullanılıyor? — tüm SQL içinde tırnaklı kimlikleri ve bilinen kolonları tara
  used_cols <- character(0)
  # 3a) Tırnak içindeki kimlikler
  q_hits <- regmatches(sql_txt, gregexpr('"([^"]+)"', sql_txt, perl = TRUE))[[1]]
  if (length(q_hits)) used_cols <- unique(c(used_cols, gsub('"', '', q_hits, fixed = TRUE)))

  # 3b) fact_universe kolon listesinden metin içinde geçenleri de ekle
	con <- helpers_rdata_lake$db_connect(readonly = TRUE)
	on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
  fu_cols <- try(DBI::dbGetQuery(con, "PRAGMA table_info(fact_universe)")$name, silent = TRUE)
  fu_cols <- if (inherits(fu_cols, "try-error")) character(0) else as.character(fu_cols)
  if (length(fu_cols)) {
    hits <- vapply(
      fu_cols,
      function(cn) grepl(paste0("\\b", gsub("([\\W])","\\\\\\1", cn), "\\b"),
                         sql_txt, ignore.case = TRUE, perl = TRUE),
      logical(1)
    )
    used_cols <- unique(c(used_cols, fu_cols[which(hits)]))
  }

  # 4) Önerilecek source_table listesini al
  cat("[INJECT_FILTER] Çıkarılan kolon sayısı: ", length(used_cols), "\n")
  st_candidates <- try(helpers_rdata_lake$suggest_source_tables_for(used_cols, top_n = 3), silent = TRUE)
  if (inherits(st_candidates, "try-error") || !length(st_candidates)) {
    cat("[INJECT_FILTER] Öneri yok, atlanıyor\n")
    return(sql_txt)
  }

  st_filter <- sprintf(
    "source_table IN (%s)",
    paste(sprintf("'%s'", gsub("'", "''", st_candidates)), collapse = ", ")
  )
  cat("[INJECT_FILTER] Filtre: ", st_filter, "\n")

  # 5) FROM fact_universe [AS] alias? → subquery ile sar
  # Ör: FROM fact_universe fu  ->  FROM (SELECT * FROM fact_universe WHERE ...) fu
  pat <- "(?i)\\bFROM\\s+fact_universe(?:\\s+(AS\\s+)?([A-Za-z_][A-Za-z0-9_]*))?"
  repl <- paste0("FROM (SELECT * FROM fact_universe WHERE ", st_filter, ") \\1\\2")

  new_sql <- sub(pat, repl, sql_txt, perl = TRUE)
  if (identical(new_sql, sql_txt)) {
    cat("[INJECT_FILTER] Değişiklik uygulanamadı, özgün SQL korunuyor\n")
    return(sql_txt)
  }

  cat("[INJECT_FILTER] Final SQL:\n", new_sql, "\n")
  cat("========== [INJECT_FILTER] BİTİŞ ==========\n\n")
  new_sql
}

# --- Ana: SQL çalıştır + kimlikleri şemaya göre yeniden yaz + standart çıktı ---
helpers_rdata_lake$rdata_sql <- function(sql, preview_rows = NULL) {
  # Türkçe: Gerçek DuckDB sorgusu çalıştır ve 'preview' olarak döndür.
  if (!is.character(sql) || !nzchar(sql[1])) {
    return(list(error = "SQL boş."))
  }
  sql_txt <- as.character(sql[1])

  # Türkçe: fact_universe sorgularında otomatik source_table filtresi ekle
  sql_txt <- helpers_rdata_lake$inject_source_table_filter(sql_txt)

  # Savunmacı: LIMIT yoksa, sadece önizleme amaçıyla üst limite zorla (force_preview_limit TRUE ise)
  if (isTRUE(getOption("mergen.rdata.force_preview_limit", FALSE))) {
    if (!is.null(preview_rows)) {
      suppressWarnings({
        forced_limit <- try(as.integer(preview_rows), silent = TRUE)
        if (!inherits(forced_limit, "try-error")) {
          forced_val <- forced_limit[1]
          if (is.finite(forced_val) && forced_val > 0 && !grepl("(?i)\\bLIMIT\\b", sql_txt, perl = TRUE)) {
            sql_txt <- paste(sql_txt, sprintf("LIMIT %d", forced_val))
          }
        }
      })
    }
  }

  con <- helpers_rdata_lake$db_connect(readonly = TRUE)
  on.exit(try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  start <- proc.time()[3]
df <- try(DBI::dbGetQuery(con, sql_txt), silent = FALSE)  # Türkçe: silent=FALSE ile hataları gör

# Türkçe: Sonucu detaylı logla
if (!inherits(df, "try-error")) {
  cat("\n========== [RDATA_SQL] SORGU SONUCU ==========\n")
  cat("[RDATA_SQL] Dönen satır sayısı: ", nrow(df), "\n")
  cat("[RDATA_SQL] Dönen sütun sayısı: ", ncol(df), "\n")
  if (nrow(df) > 0) {
    cat("[RDATA_SQL] İlk 3 satır:\n")
    print(utils::head(df, 3))
    
    # Türkçe: NA kontrolü yap
    na_counts <- colSums(is.na(df))
    na_pct <- (na_counts / nrow(df)) * 100
    cat("\n[RDATA_SQL] NA Yüzdeleri:\n")
    for (i in seq_along(na_pct)) {
      cat(sprintf("  %s: %.1f%%\n", names(na_pct)[i], na_pct[i]))
    }
    
    # Türkçe: UYARI: Eğer çoğu sütun %90+ NA ise
    high_na_cols <- names(na_pct)[na_pct > 90]
    if (length(high_na_cols) > length(na_pct) * 0.5) {
      cat("\n*** UYARI: Sonuçların çoğu NA! ***\n")
      cat("Yüksek NA'lı sütunlar: ", paste(high_na_cols, collapse = ", "), "\n")
    }
  }
  cat("========================================\n\n")
}

  elapsed <- round((proc.time()[3] - start) * 1000)

  if (inherits(df, "try-error")) {
    return(list(
      error = as.character(attr(df, "condition")$message %||% df),
      sql_effective = sql_txt
    ))
  }

  # Türkçe: Tüm veriyi döndür (artık limit yok) ve tamamen NA olan sütunları atla
  source_tables <- character(0)
  removed_all_na <- character(0)
  if ("source_table" %in% names(df)) {
    source_tables <- unique(df$source_table)
    source_tables <- source_tables[!is.na(source_tables)]
    source_tables <- sort(as.character(source_tables))
  }

  if (is.data.frame(df) && nrow(df) > 0) {
    na_mask <- vapply(df, function(col) all(is.na(col)), logical(1L))
    removed_all_na <- names(na_mask)[na_mask]
    if (any(na_mask)) {
      df <- df[, !na_mask, drop = FALSE]
    }
  }
  
  n_all <- nrow(df)
  prev <- df  # Türkçe: Artık kesme yapmıyoruz, tüm sonucu döndür

  list(
    ok = TRUE,  # Türkçe: Başarı durumu eklendi (geriye dönük uyumluluk için)
    sql_effective = sql_txt,
    elapsed_ms = elapsed,
    row_count = n_all,
    column_count = ncol(df),
    preview = as.data.frame(prev, stringsAsFactors = FALSE),
    `sonuç_önizleme` = as.data.frame(prev, stringsAsFactors = FALSE),  # Türkçe: Gerçek veriyi içeren alan eklendi
    source_table_values = source_tables,
    dropped_all_na_columns = removed_all_na
  )
}