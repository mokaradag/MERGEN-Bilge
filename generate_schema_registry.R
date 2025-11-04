# tools/generate_schema_registry.R
# -------------------------------------------------------------
# Auto-build R/schema_registry.R from real data in Rdata* folders
# (Simplified: emit ONLY SCHEMA$TYPES)
# -------------------------------------------------------------

## ========== CONFIG — set your folders ==========
DAILY_DIR <- "path/to/RdataDaily"   # <<<< EDIT THIS
MAIN_DIR  <- "path/to/Rdata"        # <<<< EDIT THIS
OUT_FILE  <- file.path("R", "schema_registry.R")

## ========== Dependencies (base R only) ==========
suppressWarnings({
  # no external packages required
})

## ========== Helpers: filesystem & loading ==========
is_dir <- function(p) isTRUE(file.info(p)$isdir)
all_files <- function(root) {
  if (!is_dir(root)) return(character(0))
  list.files(root, pattern = "(?i)\\.(rdata|rda|rds)$", recursive = TRUE, full.names = TRUE)
}

load_any <- function(path) {
  # Returns a named list of data.frame-like objects contained in file
  out <- list()
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("rdata","rda")) {
    e <- new.env(parent = emptyenv())
    nm <- tryCatch(load(path, envir = e), error = function(e) character(0))
    for (n in nm) {
      obj <- get(n, envir = e)
      if (inherits(obj, c("data.frame","tbl_df","tbl","data.table"))) {
        out[[paste0(basename(path), "::", n)]] <- as.data.frame(obj, stringsAsFactors = FALSE)
      }
    }
  } else if (ext == "rds") {
    obj <- tryCatch(readRDS(path), error = function(e) NULL)
    if (inherits(obj, c("data.frame","tbl_df","tbl","data.table"))) {
      out[[basename(path)]] <- as.data.frame(obj, stringsAsFactors = FALSE)
    }
  }
  out
}

## ========== Helpers: string canonicalization ==========
strip_tr <- function(x) {
  # Basic transliteration for Turkish chars + general accent strip
  x <- chartr("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU", x)
  y <- iconv(x, to = "ASCII//TRANSLIT")
  ifelse(is.na(y), x, y)
}

split_tokens <- function(x) {
  # Split camelCase, snake_case, spaces, dots
  x <- gsub("([a-z])([A-Z])", "\\1_\\2", x)
  x <- gsub("[\\.\\s]+", "_", x)
  unlist(strsplit(x, "[^A-Za-z0-9]+"))
}

# Vector-safe token map
token_map <- local({
  m <- c(
    proje="project", project="project", prj="project",
    adi="name", ad="name", name="name",
    kod="code", kodu="code", code="code",
    yonetici="manager", yoneticisi="manager", manager="manager", pm="manager",
    kaynak="resource", personel="resource", calisan="resource", ekip="resource", resource="resource",
    sicil="employeeid", "sicilno"="employeeid", employee="employeeid", id="employeeid",
    wbs="wbs",
    direktorluk="directorate", mudurluk="directorate", directorate="directorate",
    masraf="cost", masrafyeri="costcenter", cost="cost", costcenter="costcenter", cc="costcenter",
    rol="role", role="role",
    yil="year", year="year", ay="month", month="month", donem="period", period="period",
    tarih="date", date="date",
    aktivite="activity", activity="activity",
    baslangic="start", start="start",
    bitis="finish", finish="finish",
    temelhat="baseline", bl="baseline", baseline="baseline",
    kritik="critical", critical="critical",
    iscilik="laborhours", labor="laborhours", hours="laborhours", saat="laborhours",
    gerceklesen="actual", actual="actual",
    kalan="remaining", remaining="remaining",
    toplam="total", total="total",
    asof="asof", data="data", datadate="datadate"
  )
  function(tok) {
    tks <- tolower(tok)
    mm  <- m[tks]
    mm[is.na(mm)] <- tks[is.na(mm)]
    unname(mm)
  }
})

norm_key <- function(colname) {
  base <- strip_tr(colname)
  toks <- split_tokens(base)
  toks <- toks[nzchar(toks)]
  toks <- token_map(toks)
  paste(toks, collapse = "_")
}

is_df_like <- function(x) inherits(x, c("data.frame","tbl_df","tbl","data.table"))
`%||%` <- function(a,b) if (is.null(a)) b else a

## ========== Type inference & unification ==========
rclass_to_duck <- function(cls) {
  # Map most common R classes to DuckDB types
  if (any(cls %in% c("POSIXct","POSIXt"))) return("TIMESTAMP")
  if ("Date" %in% cls) return("DATE")
  if ("integer" %in% cls) return("INTEGER")
  if ("numeric" %in% cls || "double" %in% cls) return("DOUBLE")
  if ("logical" %in% cls) return("BOOLEAN")
  "VARCHAR"
}

unify_types <- function(types) {
  types <- unique(types)
  if (length(types) == 1) return(types[[1]])
  if ("VARCHAR" %in% types) return("VARCHAR")
  if (all(types %in% c("TIMESTAMP","DATE"))) return("TIMESTAMP")
  if (all(types %in% c("INTEGER","DOUBLE"))) return("DOUBLE")
  if ("BOOLEAN" %in% types && any(types %in% c("INTEGER","DOUBLE"))) return("DOUBLE")
  "VARCHAR"
}

## ========== Scan all tables and collect stats ==========
files <- unique(c(all_files(DAILY_DIR), all_files(MAIN_DIR)))
if (!length(files)) {
  stop("No .RData/.rda/.RDS files found under the configured folders. Please check DAILY_DIR and MAIN_DIR.")
}

message(sprintf("Found %d data files. Scanning…", length(files)))

# Minimal structures needed to infer TYPES with canonicalized names
groups <- new.env(parent = emptyenv())  # group_key -> list(variants=env, type_counts=env, total_hits=int)
raw_counts <- new.env(parent = emptyenv())
table_count <- 0L

ensure_group <- function(gk) {
  if (is.null(groups[[gk]])) {
    groups[[gk]] <- list(
      variants = new.env(parent = emptyenv()),
      type_counts = new.env(parent = emptyenv()),
      total_hits = 0L
    )
  }
  groups[[gk]]
}
add_env_count <- function(env, key, inc = 1L) {
  assign(key, get0(key, env, ifnotfound = 0L) + inc, envir = env)
}

for (f in files) {
  objs <- load_any(f)
  if (!length(objs)) next
  for (nm in names(objs)) {
    df <- objs[[nm]]
    if (!is_df_like(df)) next
    table_count <- table_count + 1L
    cols <- names(df)
    if (!length(cols)) next

    classes <- lapply(df, function(x) class(x)[1])
    duck_types <- vapply(classes, rclass_to_duck, character(1))

    for (i in seq_along(cols)) {
      raw <- cols[[i]]
      gk  <- norm_key(raw)
      tp  <- duck_types[[i]]

      add_env_count(raw_counts, raw, 1L)

      g <- ensure_group(gk)
      assign(raw, TRUE, envir = g$variants)
      add_env_count(g$type_counts, tp, 1L)
      g$total_hits <- g$total_hits + 1L
    }
  }
}

env_to_vec <- function(e) sort(names(as.list(e)))
env_to_table_counts <- function(e) {
  xs <- as.list(e)
  data.frame(type = names(xs), n = as.integer(unlist(xs)), row.names = NULL)
}

raw_count_vector <- {
  xs <- as.list(raw_counts)
  if (!length(xs)) integer(0) else {
    setNames(as.integer(unlist(xs, use.names = FALSE)), names(xs))
  }
}

choose_canonical <- function(g) {
  # pick the raw variant with the highest GLOBAL raw count; tiebreak by shortest, then alphabetical
  vars <- env_to_vec(g$variants)
  if (!length(vars)) return(NA_character_)
  vfreq <- vapply(vars, function(v) as.integer(raw_count_vector[[v]] %||% 0L), integer(1))
  vars[order(-vfreq, nchar(vars), vars)][1]
}

## ========== Build TYPES (canonical name -> unified DuckDB type) ==========
group_list <- as.list(groups)
types_map <- list()

for (gk in sort(names(group_list))) {
  g <- group_list[[gk]]
  can <- choose_canonical(g)
  if (is.na(can)) next
  tt <- env_to_table_counts(g$type_counts)
  types_map[[can]] <- unify_types(tt$type)
}

## ========== Emit ONLY SCHEMA$TYPES to R/schema_registry.R ==========
dir.create(dirname(OUT_FILE), showWarnings = FALSE, recursive = TRUE)

is_syntactic <- function(x) identical(x, make.names(x))
fmt_name <- function(x) if (is_syntactic(x)) x else paste0("`", gsub("`","\\`", x, fixed = TRUE), "`")
fmt_named_scalar <- function(nm, val) sprintf("  %s = \"%s\"", fmt_name(nm), gsub("\"","\\\"", val, fixed = TRUE))
fmt_named_types <- function(lst) {
  if (!length(lst)) return("list()")
  items <- vapply(names(lst), function(nm) fmt_named_scalar(nm, lst[[nm]]), character(1))
  paste0("list(\n", paste0(items, collapse = ",\n"), "\n)")
}

# Order by descending frequency of chosen canonical, then alphabetically
canon_freq <- vapply(names(types_map), function(k) as.integer(raw_count_vector[[k]] %||% 0L), integer(1))
ord <- order(-canon_freq, tolower(names(types_map)))
types_map <- types_map[ord]

header <- c(
  "# R/schema_registry.R",
  "# -------------------------------------------------------------",
  "# Basitleştirilmiş Şema: Sadece Veri Tipleri",
  "# -------------------------------------------------------------",
  "",
  "SCHEMA <- new.env(parent = emptyenv())",
  "",
  "# Sadece veri tiplerini tanımla (diğer her şey metadata'dan gelecek)",
  paste0("SCHEMA$TYPES <- ", fmt_named_types(types_map)),
  ""
)

writeLines(header, con = OUT_FILE, useBytes = TRUE)

message(sprintf("✅ Wrote %s", normalizePath(OUT_FILE, winslash = "/")))
message(sprintf("  • Tables scanned: %d", table_count))
message(sprintf("  • Canonical fields inferred (TYPES): %d", length(types_map)))
