# R/helpers_rdata_engine.R

`%||%` <- function(a,b) if (is.null(a)) b else a

RDATA_ENGINE <- new.env(parent = emptyenv())

rdata_engine_init <- function(paths = list(
  RdataDaily = normalizePath("RdataDaily", mustWork = FALSE),
  Rdata      = normalizePath("Rdata", mustWork = FALSE)
)) {
  # DuckDB DB dosyası ve çalışma klasörü
  db_dir <- normalizePath(file.path("data"), mustWork = FALSE)
  if (!dir.exists(db_dir)) dir.create(db_dir, recursive = TRUE)
  db_path <- file.path(db_dir, "mergen_rdata.duckdb")

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
  RDATA_ENGINE$con <- con
  RDATA_ENGINE$paths <- paths
  RDATA_ENGINE$catalog <- NULL

  # Arrow entegrasyonu (DuckDB <-> Parquet)
  DBI::dbExecute(con, "SET threads TO 4;")
  # Türkçe: Çevrimdışı/izinli ortamlar için eklenti yüklemesini güvene al
  try(DBI::dbExecute(con, "INSTALL 'json'"), silent = TRUE)
  try(DBI::dbExecute(con, "LOAD 'json'"),    silent = TRUE)
  DBI::dbExecute(con, "PRAGMA enable_object_cache")

  invisible(TRUE)
}

rdata_engine_disconnect <- function() {
  if (!is.null(RDATA_ENGINE$con)) DBI::dbDisconnect(RDATA_ENGINE$con, shutdown = TRUE)
  RDATA_ENGINE$con <- NULL
}

# .RData içinden veri.frame/listeyi çıkar
.extract_frames_from_rdata <- function(file) {
  e <- new.env(parent = emptyenv())
  load(file, envir = e)
  objs <- ls(e, all.names = TRUE)
  out <- list()
  for (nm in objs) {
    obj <- get(nm, envir = e)
    if (is.data.frame(obj)) {
      out[[nm]] <- tibble::as_tibble(obj)
    } else if (is.list(obj) && !is.null(obj$data) && is.data.frame(obj$data)) {
      out[[nm]] <- tibble::as_tibble(obj$data)
    }
  }
  out
}

# .RData -> DuckDB tablo adı üret
.mk_table_name <- function(folder_tag, file, object_name) {
  stem <- tools::file_path_sans_ext(basename(file))
  nm <- paste0(folder_tag, "__", stem, "__", object_name)
  # Türkçe yorum: Tablonun adındaki geçersiz karakterleri alt çizgi ile değiştir.
  gsub("[^A-Za-z0-9_]", "_", nm)
}

# Tiplere küçük düzeltmeler (tarih/sayı)
.normalize_types <- function(df) {
  df <- as.data.frame(df)
  for (cn in names(df)) {
    v <- df[[cn]]
    if (inherits(v, c("POSIXct","POSIXt","Date"))) next
    # Tarih karakterlerini yakala
    if (is.character(v) && any(grepl("^\\d{4}-\\d{2}-\\d{2}$", v[!is.na(v)]))) {
      vv <- as.Date(v, format = "%Y-%m-%d")
      if (sum(!is.na(vv)) > 0.5*length(v)) { df[[cn]] <- vv; next }
    }
    # Sayısal karakter kolonlarını sayıya çevir (virgüllü TR notasyonu da)
    if (is.character(v) && any(grepl("^[-+]?[0-9]+([\\.,][0-9]+)?$", v[!is.na(v)]))) {
      vv <- suppressWarnings(as.numeric(gsub(",", ".", v)))
      na_ratio <- mean(is.na(vv))
      if (na_ratio < 0.4) df[[cn]] <- vv
    }
  }
  df
}

# --- ŞEMA güdümlü ifade üretici: kanonik alanı tabloya özgü gerçeğe çevir ---
schema_sql_expr <- function(canon_name, available_cols) {
  # Türkçe yorum: SCHEMA$COLUMN_SYNONYMS / SCHEMA$VARIANTS / SCHEMA$TYPES kullanan çözümleyici.
  sc <- get0("SCHEMA", inherits = TRUE)
  syn  <- if (!is.null(sc) && !is.null(sc$COLUMN_SYNONYMS)) sc$COLUMN_SYNONYMS else list()
  vars <- if (!is.null(sc) && !is.null(sc$VARIANTS))        sc$VARIANTS        else list()
  typs <- if (!is.null(sc) && !is.null(sc$TYPES))           sc$TYPES           else list()

  # Türkçe yorum: normalize edici – diakritik-insensitive eşleşme
  normalize_ascii <- function(x) {
    x <- enc2utf8(as.character(x))
    x <- stringi::stri_trans_general(x, "Latin-ASCII")
    tolower(gsub("[^a-z0-9_]+", "", x))
  }

  avail <- as.character(available_cols %||% character(0))
  avail_norm <- setNames(avail, vapply(avail, normalize_ascii, character(1)))

  # 1) Doğrudan isim eşleşmesi
  if (canon_name %in% avail) {
    src <- canon_name
  } else {
    # 2) Varyant/sinonim
    cand <- unique(c(
      as.character(vars[[canon_name]] %||% character(0)),
      as.character(syn[[canon_name]]  %||% character(0)),
      canon_name
    ))
    # a) normalize eşleşme
    src <- NULL
    for (c in cand) {
      nc <- normalize_ascii(c)
      if (nc %in% names(avail_norm)) { src <- avail_norm[[nc]]; break }
      # b) case-insensitive düz eşleşme
      if (is.null(src)) {
        hit <- avail[tolower(avail) == tolower(c)]
        if (length(hit)) { src <- hit[[1]]; break }
      }
    }
  }

  # Türkçe yorum: Tip hedefini bul (varsayılan TEXT)
  duck_type <- "TEXT"
  if (!is.null(typs[[canon_name]])) {
    duck_type <- toupper(as.character(typs[[canon_name]]))
  }

  # Türkçe: Bağlantı yoksa da güvenli tırnaklama yap
  qid <- function(x) {
    con <- RDATA_ENGINE$con %||% NULL
    if (!is.null(con)) DBI::dbQuoteIdentifier(con, x) else DBI::SQL(paste0('"', gsub('"','""', x), '"'))
  }

  if (is.null(src)) {
    # Kolon yoksa NULL AS "Canon" (tip ipucu ile)
    return(glue::glue("TRY_CAST(NULL AS {duck_type}) AS {qid(canon_name)}"))
  }

  # Türkçe: Bulunan kaynak kolonu tipine dök
  qsrc <- qid(src)
  qdst <- qid(canon_name)
  glue::glue("TRY_CAST({qsrc} AS {duck_type}) AS {qdst}")
}

# Klasörleri tara, Parquet yaz, DuckDB’ye bağla
rdata_build_lake <- function() {
  con <- RDATA_ENGINE$con; stopifnot(!is.null(con))
  base_out <- normalizePath(file.path("data","rdata_parquet"), mustWork = FALSE)
  dir.create(base_out, recursive = TRUE, showWarnings = FALSE)

  folders <- RDATA_ENGINE$paths
  all_tables <- c()

  for (tag in names(folders)) {
    p <- folders[[tag]]
    if (!dir.exists(p)) next
    files <- list.files(p, pattern = "\\.RData$", full.names = TRUE)
    for (f in files) {
      frames <- .extract_frames_from_rdata(f)
      if (!length(frames)) next
      for (nm in names(frames)) {
        df <- .normalize_types(frames[[nm]])
        if (!nrow(df) || !ncol(df)) next

        tbl_name <- .mk_table_name(tag, f, nm)
        out_dir  <- file.path(base_out, tbl_name)
        dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
        pq_path  <- file.path(out_dir, sprintf("%s.parquet", tbl_name))

        # Parquet yaz (overwrite)
        arrow::write_parquet(arrow::as_arrow_table(df), pq_path)
        # DuckDB’ye sanal tablo olarak bağla (external)
        DBI::dbExecute(con, sprintf(
          "CREATE OR REPLACE VIEW %s AS SELECT * FROM read_parquet('%s')",
          DBI::dbQuoteIdentifier(con, tbl_name), normalizePath(pq_path, winslash = "/", mustWork = TRUE)
        ))
        all_tables <- c(all_tables, tbl_name)
      }
    }
  }
  RDATA_ENGINE$tables <- unique(all_tables)
  invisible(RDATA_ENGINE$tables)
}

# Katalog çıkar: sütunlar, tipler, örnekler, join anahtarları
rdata_build_catalog <- function(sample_n = 2000) {
  con <- RDATA_ENGINE$con; stopifnot(!is.null(con))
  tables <- RDATA_ENGINE$tables %||% character(0)
  cols <- list()
  for (t in tables) {
    # Sütun adları & tipleri
    info <- DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", DBI::dbQuoteIdentifier(con, t)))
    if (!nrow(info)) next
		# Türkçe: DuckDB örnekleme sözdizimini TABLESAMPLE RESERVOIR olarak düzelt
		smp <- try(DBI::dbGetQuery(
		  con,
		  sprintf("SELECT * FROM %s TABLESAMPLE RESERVOIR(%d ROWS)",
				  DBI::dbQuoteIdentifier(con, t), as.integer(sample_n))
		), silent = TRUE)
    if (inherits(smp, "try-error")) smp <- NULL

    for (i in seq_len(nrow(info))) {
      cn <- info$name[i]
      vals <- if (!is.null(smp) && cn %in% names(smp)) smp[[cn]] else NULL
      top_vals <- if (length(vals)) as.character(head(sort(table(as.character(vals)), decreasing = TRUE), 5) |> names()) else character(0)
      cols[[length(cols)+1]] <- list(
        table = t,
        column = cn,
        type = info$type[i] %||% "",
        top = I(list(top_vals))
      )
    }
  }
  cat_df <- dplyr::bind_rows(lapply(cols, as_tibble))
  # join adayları: aynı isimli sütunlar (özellikle GOLDEN_COLUMNS)
	# SCHEMA güvenli okuma
	golden_cols <- {
	  sc <- get0("SCHEMA", inherits = TRUE)
	  if (!is.null(sc) && !is.null(sc$GOLDEN_COLUMNS)) sc$GOLDEN_COLUMNS else character(0)
	}

	join_edges <- cat_df |>
	  dplyr::filter(column %in% golden_cols) |>
	  dplyr::group_by(column) |>
	  dplyr::summarise(tables = list(unique(table)), .groups = "drop")

  RDATA_ENGINE$catalog <- list(columns = cat_df, joins = join_edges)
  invisible(RDATA_ENGINE$catalog)
}

# --- fact_universe görünümünü kanonik kolonlara göre oluştur ---
build_fact_universe_view <- function() {
  con <- RDATA_ENGINE$con; stopifnot(!is.null(con))
  sc  <- get0("SCHEMA", inherits = TRUE)

  canon_cols <- if (!is.null(sc) && !is.null(sc$FACT_UNIVERSE_CANON)) {
    as.character(sc$FACT_UNIVERSE_CANON)
  } else {
    # Türkçe yorum: Güvenli çekirdek – gerçek dosyadaki kanona devredecek.
    c("ProjeAdi","ProjeKodu","Yil","Ay")
  }

  tabs <- RDATA_ENGINE$tables %||% character(0)
  if (!length(tabs)) return(invisible(FALSE))

  selects <- vapply(tabs, function(t) {
    info <- try(DBI::dbGetQuery(con, sprintf(
      "PRAGMA table_info(%s)", DBI::dbQuoteIdentifier(con, t)
    )), silent = TRUE)
    avail <- if (!inherits(info, "try-error") && nrow(info)) info$name else character(0)

    exprs <- vapply(canon_cols, function(cn) schema_sql_expr(cn, avail), character(1))
    glue::glue("SELECT {paste(exprs, collapse = ', ')} FROM {DBI::dbQuoteIdentifier(con, t)}")
  }, character(1))

  sql <- paste(selects, collapse = "\nUNION ALL\n")

  DBI::dbExecute(con, "DROP VIEW IF EXISTS fact_universe")
  DBI::dbExecute(con, sprintf("CREATE VIEW fact_universe AS %s", sql))
  invisible(TRUE)
}

# Proje KPI’ları (günlük/precompute). Basit bir örnek: işçilik + gecikme + kritik.
rdata_build_views <- function() {
  con <- RDATA_ENGINE$con; stopifnot(!is.null(con))

  # 0) Kanonik görünüm: fact_universe (her oturumda bir kez oluştur)
  try(build_fact_universe_view(), silent = TRUE)

	# 1) Gerçekleşen/Kalan işçilik agregeleri (proje, ay, yıl)
	# Türkçe: v_union_core varsa onu kullan, yoksa fact_universe üzerinden topla
	has_union_core <- try(DBI::dbExistsTable(con, "v_union_core"), silent = TRUE)
	src_view <- if (isTRUE(has_union_core)) "v_union_core" else "fact_universe"

	DBI::dbExecute(con, sprintf("
	  CREATE OR REPLACE VIEW v_project_labor AS
	  SELECT
		COALESCE(ProjeKodu, ProjeAdi) AS proje_key,
		ANY_VALUE(ProjeAdi)  AS ProjeAdi,
		ANY_VALUE(ProjeKodu) AS ProjeKodu,
		Yil,
		Ay,
		SUM(COALESCE(GerceklesenIscilik_sa, 0)) AS gerceklesen_sa,
		SUM(COALESCE(KalanIscilik_sa, 0))       AS kalan_sa,
		SUM(COALESCE(ToplamIscilik_sa, 0))      AS toplam_sa
	  FROM %s
	  GROUP BY proje_key, Yil, Ay
	", src_view))

	# Şema bilgisi ile tabloya özgü seçme listesi üret (varyant seçimi)
	.mk_union_sql <- function(cols_need) {
	  con <- RDATA_ENGINE$con
	  # Bu kolonları içeren tablolar
	  tabs <- RDATA_ENGINE$catalog$columns |>
		dplyr::filter(column %in% cols_need) |>
		dplyr::pull(table) |> unique()
	  if (!length(tabs)) return(NULL)

	  selects <- vapply(tabs, function(t) {
		# Tablodaki gerçek kolonlar
		info <- try(DBI::dbGetQuery(con, sprintf(
		  "PRAGMA table_info(%s)", DBI::dbQuoteIdentifier(con, t)
		)), silent = TRUE)
		avail <- if (!inherits(info, "try-error") && nrow(info)) info$name else character(0)

		# İstenen her kanonik alan için TRY_CAST(...) AS "Kanonik"
		want <- cols_need
		exprs <- vapply(want, function(nm) schema_sql_expr(nm, avail), character(1))
		glue::glue("SELECT {paste(exprs, collapse = ', ')} FROM {DBI::dbQuoteIdentifier(con, t)}")
	  }, character(1))

	  paste(selects, collapse = "\nUNION ALL\n")
	}

	# SCHEMA yoksa güvenli çekirdek kolon listesi kullan
	sc <- get0("SCHEMA", inherits = TRUE)
	cols_core <- if (!is.null(sc) && !is.null(sc$UNION_CORE)) sc$UNION_CORE else c(
	  "ProjeAdi","ProjeKodu","Yil","Ay",
	  "GerceklesenIscilik_sa","KalanIscilik_sa","ToplamIscilik_sa",
	  "AktiviteBitis","TemelHatAktiviteBitis","KritikYolAktivitesi"
	)

	sql_union <- .mk_union_sql(cols_core)

  if (!is.null(sql_union)) {
    DBI::dbExecute(con, "DROP VIEW IF EXISTS v_union_core")
    DBI::dbExecute(con, sprintf("CREATE VIEW v_union_core AS %s", sql_union))

    DBI::dbExecute(con, "
      CREATE OR REPLACE VIEW v_project_health AS
      SELECT
        COALESCE(ProjeKodu, ProjeAdi) AS proje_key,
        MAX(ProjeAdi) AS ProjeAdi,
        MAX(ProjeKodu) AS ProjeKodu,
        SUM(COALESCE(GerceklesenIscilik_sa,0)) AS Gerceklesen_sa,
        SUM(COALESCE(KalanIscilik_sa,0)) AS Kalan_sa,
        SUM(COALESCE(ToplamIscilik_sa,0)) AS Toplam_sa,
        SUM(CASE WHEN AktiviteBitis > TemelHatAktiviteBitis THEN 1 ELSE 0 END) AS GecikenAktiviteSayisi,
        SUM(CASE WHEN COALESCE(KritikYolAktivitesi,'') IN ('Evet','evet','Yes','TRUE','1') THEN 1 ELSE 0 END) AS KritikAktiviteSayisi
      FROM v_union_core
      GROUP BY proje_key
    ")
  }
  invisible(TRUE)
}

# Tam index/yenileme (startup veya buton)
rdata_refresh_all <- function() {
  rdata_build_lake()
  rdata_build_catalog()
  rdata_build_views()
  invisible(TRUE)
}

# Türkçe yorum: Yenilemeden sonra fact_universe'i garanti altına al
try(build_fact_universe_view(), silent = TRUE)

# Basit filtreleme yordamı (WHERE koşulu üret)
.build_where <- function(filters) {
  if (is.null(filters) || !length(filters)) return("")
  parts <- c()
  for (nm in names(filters)) {
    v <- filters[[nm]]
    if (is.null(v)) next
    if (is.numeric(v)) {
      parts <- c(parts, glue::glue("{DBI::dbQuoteIdentifier(RDATA_ENGINE$con, nm)} = {v}"))
    } else if (inherits(v, "Date")) {
      parts <- c(parts, glue::glue("{DBI::dbQuoteIdentifier(RDATA_ENGINE$con, nm)} = DATE '{format(v, \"%Y-%m-%d\")}'"))
    } else {
      parts <- c(parts, glue::glue("{DBI::dbQuoteIdentifier(RDATA_ENGINE$con, nm)} ILIKE {DBI::dbQuoteString(RDATA_ENGINE$con, paste0('%', v, '%'))}"))
    }
  }
  paste("WHERE", paste(parts, collapse = " AND "))
}

rdata_answer_question <- function(question, limit = 100, want_chart = FALSE) {
  # Türkçe yorum: Eski motor devre dışı — doğrudan kullanımı engelle.
  stop("Bu fonksiyon devre dışıdır. helpers_rdata_lake üzerinden çağrı yapın.")
}

# Ham SQL çalıştır (güvenli alan: sadece SELECT)
rdata_sql_query <- function(sql, limit = 1000) {
  con <- RDATA_ENGINE$con; stopifnot(!is.null(con))
  s <- trimws(sql)
  if (!grepl("^select\\b", tolower(s))) stop("Sadece SELECT sorgularına izin veriliyor.")
  if (!grepl("limit\\b", tolower(s))) s <- paste0(s, " LIMIT ", as.integer(limit))
  DBI::dbGetQuery(con, s)
}
