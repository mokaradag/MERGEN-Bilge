# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-query-meta-review-hardening.R
# Açıklama: PR #696 bağımsız incelemesinde bulunan P1/P2 sözleşme açıkları.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()
  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  for (dosya in c(
    "helpers_pk_config.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_query_meta_schema.R",
    "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

.review_registry <- function() {
  list(
    "labor.remaining_hours" = list(role = "measure", unit = "saat"),
    "dimension.resource" = list(role = "dimension", unit = NULL),
    "date.project_start" = list(role = "date", unit = NULL)
  )
}

.review_meta <- function() {
  list(
    grain = "project_resource",
    grain_columns = c("ProjeKodu", "KaynakKodu"),
    primary_entity = "ProjeAdi",
    default_group_by = "ProjeKodu",
    default_measures = "KalanIscilik_sa",
    row_cap = 1000L,
    column_meta = list(
      ProjeKodu = list(label = "Proje Kodu", role = "id", entity = "project", match = "exact"),
      ProjeAdi = list(label = "Proje Adi", role = "dimension", entity = "project", match = "resolve", filterable = TRUE),
      KaynakKodu = list(
        label = "Kaynak Kodu", role = "dimension",
        capability = "dimension.resource", match = "exact", filterable = TRUE
      ),
      BaslangicTarihi = list(
        label = "Baslangic", role = "date", capability = "date.project_start"
      ),
      KalanIscilik_sa = list(
        label = "Kalan Iscilik", role = "measure",
        capability = "labor.remaining_hours", unit = "saat", additive = TRUE
      )
    )
  )
}

.review_library <- function(id = "q001") {
  list(list(
    id = id,
    name = "Sentetik sorgu",
    sql = "SELECT 1",
    rls_columns = list(proje_kodu_col = "ProjeKodu", masraf_yeri_col = NULL)
  ))
}

test_that("capability kapısı gereksinim rolünü de doğrular", {
  query <- list(meta = .review_meta())

  yanlis_rol <- pk_meta_capability_check(
    query,
    list(measures = "dimension.resource")
  )
  expect_equal(yanlis_rol$status, PK_META_STATUS_NO_SEMANTICS)
  expect_true("dimension.resource" %in% yanlis_rol$missing)
  expect_equal(yanlis_rol$role_mismatches[["dimension.resource"]]$expected, "measure")
  expect_equal(yanlis_rol$role_mismatches[["dimension.resource"]]$actual, "dimension")

  dogru_rol <- pk_meta_capability_check(
    query,
    list(dimensions = "dimension.resource")
  )
  expect_equal(dogru_rol$status, PK_META_STATUS_OK)
  expect_equal(dogru_rol$columns[["dimension.resource"]], "KaynakKodu")
})

test_that("bozuk RLS beyanı başlangıçta ve getirme sonrasında fail-closed olur", {
  kutuphane <- .review_library()
  kutuphane[[1]]$rls_columns$proje_kodu_col <- c("ProjeKodu", "BaskaSutun")

  expect_error(
    pk_query_meta_attach(
      kutuphane,
      auto = list(), local = list(), curated = list(q001 = .review_meta()),
      aliases = list(), registry = .review_registry()
    ),
    "rls_columns"
  )

  query <- .review_library()[[1]]
  query$meta <- .review_meta()
  query$rls_columns <- c(proje_kodu_col = "ProjeKodu")
  sonuc <- pk_meta_validate_actual_columns(
    query,
    c("ProjeKodu", "ProjeAdi", "KaynakKodu", "BaslangicTarihi", "KalanIscilik_sa")
  )
  expect_false(sonuc$ok)
  expect_true(sonuc$fail_closed)
  expect_true(length(sonuc$invalid_rls) > 0L)
})

test_that("toplama sözleşmesi non-additive ve ölçü olmayan sütunları korur", {
  meta <- .review_meta()
  meta$column_meta$KalanIscilik_sa$additive <- FALSE
  meta$column_meta$KalanIscilik_sa$aggregate <- "sum"
  expect_true(any(grepl(
    "additive=TRUE",
    pk_meta_validate_query("q001", meta, .review_registry()),
    fixed = TRUE
  )))

  meta2 <- .review_meta()
  meta2$column_meta$ProjeAdi$additive <- TRUE
  expect_true(any(grepl(
    "yalnizca role='measure'",
    pk_meta_validate_query("q001", meta2, .review_registry()),
    fixed = TRUE
  )))

  # Doğrulanmamış bir nesne tüketiciye ulaşsa bile accessor yanlış SUM açmaz.
  expect_equal(
    pk_meta_aggregate_for(list(meta = meta), "KalanIscilik_sa"),
    "none"
  )
})

test_that("weighted_mean ve latest sütun atıfları tekil ve boş olmayan sözleşmedir", {
  agirlik <- .review_meta()
  agirlik$column_meta$KalanIscilik_sa$aggregate <- "weighted_mean"
  agirlik$column_meta$KalanIscilik_sa$weight_by <- c("KalanIscilik_sa", "KalanIscilik_sa")
  expect_true(any(grepl(
    "weight_by tek olcu sutunu",
    pk_meta_validate_query("q001", agirlik, .review_registry()),
    fixed = TRUE
  )))

  son <- .review_meta()
  son$column_meta$KalanIscilik_sa$aggregate <- "latest"
  son$column_meta$KalanIscilik_sa$latest_by <- "BaslangicTarihi"
  son$column_meta$KalanIscilik_sa$latest_tie_by <- ""
  expect_true(any(grepl(
    "latest_by ve latest_tie_by zorunludur",
    pk_meta_validate_query("q001", son, .review_registry()),
    fixed = TRUE
  )))
})

test_that("izlenen ve yerel alias haritaları birlikte katlanır ve çakışma reddedilir", {
  testthat::skip_if_not_installed("stringi")

  meta <- .review_meta()
  meta$column_meta$ProjeAdi$aliases <- c("İSTANBUL" = "SENTETIK A")
  meta$column_meta$ProjeAdi$alias_provenance <- "synthetic"

  sonuc <- pk_query_meta_attach(
    .review_library(),
    auto = list(), local = list(), curated = list(q001 = meta),
    aliases = list(q001 = list(ProjeAdi = c("ANKARA" = "SENTETIK B"))),
    registry = .review_registry()
  )

  aliases <- sonuc[[1]]$meta$column_meta$ProjeAdi$aliases
  expect_equal(unname(aliases[["istanbul"]]), "SENTETIK A")
  expect_equal(unname(aliases[["ankara"]]), "SENTETIK B")

  expect_error(
    pk_query_meta_attach(
      .review_library(),
      auto = list(), local = list(), curated = list(q001 = meta),
      aliases = list(q001 = list(ProjeAdi = c("istanbul" = "SENTETIK C"))),
      registry = .review_registry()
    ),
    "birden fazla kanonik degere"
  )

  expect_error(
    pk_query_meta_attach(
      .review_library(),
      auto = list(), local = list(), curated = list(q001 = meta),
      aliases = list(list(ProjeAdi = c("ankara" = "SENTETIK B"))),
      registry = .review_registry()
    ),
    "adlandirilmis liste"
  )
})

test_that("tam sayı alanları kesir, taşma ve vektörü kabul etmez", {
  for (deger in list(1.5, Inf, c(100L, 200L), .Machine$integer.max + 1)) {
    meta <- .review_meta()
    meta$row_cap <- deger
    expect_true(any(grepl(
      "row_cap pozitif tam sayi",
      pk_meta_validate_query("q001", meta, .review_registry()),
      fixed = TRUE
    )))
  }

  expect_null(.pk_config_as_integer("1.5", pk_config_spec$MERGEN_PK_ROW_CAP))
  expect_null(.pk_config_as_integer("999999999999", pk_config_spec$MERGEN_PK_ROW_CAP))

  eski <- Sys.getenv("MERGEN_PK_ROW_CAP", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_PK_ROW_CAP") else Sys.setenv(MERGEN_PK_ROW_CAP = eski)
  }, add = TRUE)
  Sys.setenv(MERGEN_PK_ROW_CAP = "999999999999")
  expect_equal(
    pk_config_resolve("MERGEN_PK_ROW_CAP"),
    pk_config_spec$MERGEN_PK_ROW_CAP$default
  )
})

test_that("kararlı sorgu kimliği ve metadata katman şekli zorunludur", {
  iki_ayni <- c(.review_library(), .review_library())
  expect_error(
    pk_query_meta_attach(
      iki_ayni,
      auto = list(), local = list(), curated = list(q001 = .review_meta()),
      aliases = list(), registry = .review_registry()
    ),
    "tekrar eden sorgu id"
  )

  kimliksiz <- .review_library()
  kimliksiz[[1]]$id <- NULL
  expect_error(
    pk_query_meta_attach(
      kimliksiz,
      auto = list(), local = list(), curated = list(),
      aliases = list(), registry = .review_registry()
    ),
    "bos olmayan tek id"
  )

  expect_error(
    pk_query_meta_attach(
      .review_library(),
      auto = list(), local = list(), curated = list(q999 = .review_meta()),
      aliases = list(), registry = .review_registry()
    ),
    "bulunmayan sorgu id"
  )

  expect_error(
    pk_query_meta_attach(
      .review_library(),
      auto = list(), local = "bozuk", curated = list(q001 = .review_meta()),
      aliases = list(), registry = .review_registry()
    ),
    "pk_query_meta_local adlandirilmis liste"
  )
})


test_that("entity ve group_by gereksinimleri kapıda göz ardı edilmez", {
  query <- list(meta = .review_meta())

  expect_equal(
    pk_meta_capability_check(query, list(entity = "project"))$status,
    PK_META_STATUS_OK
  )

  yanlis_entity <- pk_meta_capability_check(query, list(entity = "resource"))
  expect_equal(yanlis_entity$status, PK_META_STATUS_NO_SEMANTICS)
  expect_equal(yanlis_entity$missing_entity, "resource")

  expect_equal(
    pk_meta_capability_check(query, list(group_by = "dimension.resource"))$status,
    PK_META_STATUS_OK
  )
  expect_equal(
    pk_meta_capability_check(query, list(group_by = "dimension.unknown"))$status,
    PK_META_STATUS_NO_SEMANTICS
  )

  typo <- pk_meta_capability_check(query, list(measure = "labor.remaining_hours"))
  expect_equal(typo$status, PK_META_STATUS_NO_SEMANTICS)
  expect_true(any(grepl("bilinmeyen alan", typo$invalid_requirements, fixed = TRUE)))

  bos <- pk_meta_capability_check(query, list(measures = ""))
  expect_equal(bos$status, PK_META_STATUS_NO_SEMANTICS)
  expect_true(length(bos$invalid_requirements) > 0L)
})

test_that("RLS alan adı yazım hataları ve tekrar eden gerçek sütunlar reddedilir", {
  kutuphane <- .review_library()
  kutuphane[[1]]$rls_columns$proje_kodu_clo <- "ProjeKodu"
  kutuphane[[1]]$rls_columns$proje_kodu_col <- NULL

  expect_error(
    pk_query_meta_attach(
      kutuphane,
      auto = list(), local = list(), curated = list(q001 = .review_meta()),
      aliases = list(), registry = .review_registry()
    ),
    "bilinmeyen alan"
  )

  query <- .review_library()[[1]]
  query$meta <- .review_meta()
  sonuc <- pk_meta_validate_actual_columns(
    query,
    c("ProjeKodu", "ProjeKodu", "ProjeAdi", "KaynakKodu", "BaslangicTarihi", "KalanIscilik_sa")
  )
  expect_false(sonuc$ok)
  expect_true(sonuc$fail_closed)
  expect_true(any(grepl("tekrar eden sutun", sonuc$errors, fixed = TRUE)))
})

test_that("curated alias kod ve exact sütunlara açık izin olmadan bağlanamaz", {
  testthat::skip_if_not_installed("stringi")

  meta <- .review_meta()
  meta$column_meta$ProjeKodu$aliases <- c("p1" = "P1")
  meta$column_meta$ProjeKodu$alias_provenance <- "synthetic"
  expect_true(any(grepl(
    "allow_aliases=TRUE",
    pk_meta_validate_query("q001", meta, .review_registry()),
    fixed = TRUE
  )))

  meta$column_meta$ProjeKodu$allow_aliases <- TRUE
  expect_equal(pk_meta_validate_query("q001", meta, .review_registry()), character(0))
})

test_that("grain, primary entity, latest_by ve SQL sözleşmeleri yapısal olarak doğrulanır", {
  grain <- .review_meta()
  grain$grain_columns <- character(0)
  expect_true(any(grepl(
    "grain_columns zorunludur",
    pk_meta_validate_query("q001", grain, .review_registry()),
    fixed = TRUE
  )))

  primary <- .review_meta()
  primary$primary_entity <- "KalanIscilik_sa"
  expect_true(any(grepl(
    "id veya dimension",
    pk_meta_validate_query("q001", primary, .review_registry()),
    fixed = TRUE
  )))

  no_sql <- .review_library()
  no_sql[[1]]$sql <- ""
  expect_error(
    pk_query_meta_attach(
      no_sql,
      auto = list(), local = list(), curated = list(q001 = .review_meta()),
      aliases = list(), registry = .review_registry()
    ),
    "bos olmayan SQL"
  )
})

test_that("bozuk capability_variants nesnesi çökmek yerine sözleşme hatası verir", {
  meta <- .review_meta()
  meta$column_meta$KalanIscilik2 <- meta$column_meta$KalanIscilik_sa
  meta$capability_variants <- list("labor.remaining_hours" = "KalanIscilik_sa")

  hatalar <- pk_meta_validate_query("q001", meta, .review_registry())
  expect_true(any(grepl("capability_variants", hatalar, fixed = TRUE)))
})
