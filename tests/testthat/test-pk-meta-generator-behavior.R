# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-meta-generator-behavior.R
# Açıklama: Faz 3b — VM'e özgü metadata üreticisinin ÇEVRİMDIŞI davranış
#           sözleşmesi. Tamamen belirlenimcidir: DB, SQL Server, LLM, tarayıcı,
#           SSO, ağ veya gizli değer GEREKMEZ. Uygulamayı BAŞLATMAZ.
#
# DÜRÜSTLÜK SINIRI: Bu dosya SQL Server'ın `describe` davranışını, gerçek
# ~169 sorguluk üretim kütüphanesini, ODBC tip kodlarını ya da Windows VM
# çalışmasını KANITLAMAZ. Yalnızca üreticinin saf karar mantığını kanıtlar.
#
# Kapsanan kabul kriterleri (master plan §5.1, §8 "Phase 3b"):
#   - kip ayrıştırma ve geçersiz kip reddi
#   - kararlı id kullanımı (liste konumu DEĞİL)
#   - üretilen R kaynağının saf ASCII olması ve geri source edilebilmesi
#   - küre edilmiş (curated) metadata'nın üretilen katmanı YENMESİ
#   - alias dosyasının ASLA yazılmaması (çalışma zamanı kapısı)
#   - RLS uyuşmazlığının GÜVENLİK bulgusu olarak yakalanması
#   - metadata atıf / rol-tip uyuşmazlığının bloklayıcı sayılması
#   - anlamsal yeteneğin ASLA çıkarılmaması (fail-closed korunur)
#   - önek (prefix) örneğinin tek yönlü kanıt sınırına uyması
#   - atomik yazma ve tek bozuk sorgunun koşuyu düşürmemesi
#   - gizli değerlerin rapora sızmaması
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  # Çalışma zamanı sözleşmesi (üretici bunları YENİDEN YAZMAZ, TÜKETİR).
  for (dosya in c(
    "helpers_pk_ascii_tokens.R",
    "helpers_pk_text_turkish.R",
    "helpers_pk_config.R",
    "helpers_pk_query_meta_schema.R",
    "helpers_pk_query_meta_access.R",
    "helpers_pk_query_meta.R",
    "helpers_pk_sql_readonly.R"
  )) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }

  # VM aracı (kaynak manifestinde DEĞİLDİR; elle source edilir).
  for (dosya in c(
    "helpers_meta_generator_config.R",
    "helpers_meta_generator_schema.R",
    "helpers_meta_generator_render.R",
    "helpers_meta_generator_health.R",
    "helpers_meta_generator_run.R"
  )) {
    source(file.path(repo_root, "tools", "pk", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# ------------------------------------------------------------------------------
# Ortak sahte (fake) kurulum
# ------------------------------------------------------------------------------

.gen_test_config <- function(mode = "describe", ...) {
  withr::with_envvar(c(MERGEN_PK_META_MODE = mode), {
    cfg <- pkg_meta_resolve_config(repo_root = tempdir())
    ekler <- list(...)
    for (ad in names(ekler)) cfg[[ad]] <- ekler[[ad]]
    cfg
  })
}

.gen_desc <- function(...) {
  sutunlar <- list(...)
  lapply(names(sutunlar), function(ad) {
    list(name = ad, system_type_name = sutunlar[[ad]], max_length = 50)
  })
}

.gen_fake_conn <- function() structure(list(), class = "fake_conn")

.gen_run <- function(lib, cfg, describe_fn = NULL, sample_fn = NULL,
                     curated = list(), registry = NULL) {
  pkg_meta_run_inventory(
    query_library = lib,
    config = cfg,
    connect_fn = function(target) list(conn = .gen_fake_conn()),
    release_fn = function(handle) invisible(NULL),
    describe_fn = describe_fn %||% function(conn, sql) NULL,
    sample_fn = sample_fn %||% function(conn, sql, n) stop("ornekleme beklenmiyordu"),
    curated_layer = curated,
    registry = registry
  )
}

# ------------------------------------------------------------------------------
# 1) Kip ayrıştırma
# ------------------------------------------------------------------------------

test_that("kip cozumleme belgelenmis varsayilani kullanir ve buyuk harfi kabul eder", {
  withr::with_envvar(c(MERGEN_PK_META_MODE = ""), {
    sonuc <- pkg_meta_resolve_mode()
    expect_identical(sonuc$mode, PKG_META_DEFAULT_MODE)
    expect_true(sonuc$defaulted)
  })

  withr::with_envvar(c(MERGEN_PK_META_MODE = "DESCRIBE"), {
    sonuc <- pkg_meta_resolve_mode()
    expect_identical(sonuc$mode, "describe")
    expect_false(sonuc$defaulted)
  })

  # Kip bir PROTOKOL BELIRTECIDIR: Türkçe yerelde bile aynı çözülmelidir.
  expect_identical(pkg_meta_resolve_mode("SAMPLE")$mode, "sample")
})

test_that("gecersiz kip SESSIZCE varsayilana dusmez, acikca reddedilir", {
  expect_error(pkg_meta_resolve_mode("describ"), "Gecersiz MERGEN_PK_META_MODE")
  expect_error(pkg_meta_resolve_mode("full"), "Gecersiz MERGEN_PK_META_MODE")
  # Yanlış yazılmış bir kipin `sample`'a düşmesi üretim DB'sinde gereksiz yük
  # demektir; hata mesajı izinli kipleri söylemelidir.
  expect_error(pkg_meta_resolve_mode("x"), "describe")
})

test_that("gecersiz sayisal yapilandirma reddedilir", {
  withr::with_envvar(c(MERGEN_PK_META_SAMPLE_ROWS = "abc"), {
    expect_error(pkg_meta_resolve_config(repo_root = tempdir()), "tam sayi olmalidir")
  })
  withr::with_envvar(c(MERGEN_PK_META_SAMPLE_ROWS = "0"), {
    expect_error(pkg_meta_resolve_config(repo_root = tempdir()), "araliginda olmalidir")
  })
})

# ------------------------------------------------------------------------------
# 2) Şema çıkarımı — YAPI çıkarılır, ANLAM çıkarılmaz
# ------------------------------------------------------------------------------

test_that("SQL Server tipleri R sinifina cevrilir ve rol yapidan turetilir", {
  sema <- pkgs_schema_from_descriptor(.gen_desc(
    Kod = "nvarchar(50)", Saat = "decimal(18,2)", Tarih = "datetime2(7)",
    Sayi = "bigint", Bayrak = "bit", Gun = "date"
  ))

  expect_identical(unname(sema$schema[["Kod"]]), "character")
  expect_identical(unname(sema$schema[["Saat"]]), "numeric")
  # `datetime2` ve `bigint` HAM SQL tip adiyla birakilsaydi sessizce
  # "dimension" olurdu: tarih kapsami ve olcu KAYBI.
  expect_identical(unname(sema$schema[["Tarih"]]), "POSIXct")
  expect_identical(unname(sema$schema[["Sayi"]]), "numeric")
  expect_identical(unname(sema$schema[["Gun"]]), "Date")

  cmeta <- pkgs_build_column_meta(sema$schema, sema$source_types, "describe")
  expect_identical(cmeta[["Tarih"]]$role, "date")
  expect_identical(cmeta[["Saat"]]$role, "measure")
  expect_identical(cmeta[["Sayi"]]$role, "measure")
  expect_identical(cmeta[["Kod"]]$role, "dimension")
})

test_that("bilinmeyen SQL tipi EN MUHAFAZAKAR yapiya duser ve bildirilir", {
  sema <- pkgs_schema_from_descriptor(.gen_desc(Konum = "geography"))

  # Bir ölçü sanıp toplamak SESSİZ YANLIŞ SAYI üretir; boyut saymak yalnızca
  # yeteneği kısıtlar. Muhafazakâr yön budur.
  expect_identical(unname(sema$schema[["Konum"]]), "character")
  expect_identical(sema$unmapped, "Konum")
})

test_that("uretici ANLAMSAL alanlari ASLA uretmez", {
  sema <- pkgs_schema_from_descriptor(.gen_desc(
    KalanIscilik_sa = "decimal(18,2)", BaslangicTarihi = "date",
    ProjeAdi = "nvarchar(200)", TamamlanmaYuzdesi = "decimal(5,2)"
  ))
  girdi <- pkgn_build_local_entry(sema$schema, sema$source_types, "describe")

  # Sütun ADINDAN anlam çıkarmak master planın açıkça yasakladığı şeydir:
  # "KalanIscilik_sa" adı, o sütunun KALAN mı PLANLANAN mı işçilik olduğunu
  # KANITLAMAZ; "BaslangicTarihi" adı proje başlangıcı olduğunu kanıtlamaz.
  for (sutun in names(girdi$column_meta)) {
    expect_null(girdi$column_meta[[sutun]]$capability)
    expect_null(girdi$column_meta[[sutun]]$additive)
    expect_null(girdi$column_meta[[sutun]]$unit)
    expect_null(girdi$column_meta[[sutun]]$aggregate)
    expect_null(girdi$column_meta[[sutun]]$entity)
  }

  expect_null(girdi$grain)
  expect_null(girdi$primary_entity)
  expect_null(girdi$default_measures)
  expect_null(girdi$default_group_by)
  expect_null(girdi$intents)

  # Fail-closed: yetenek yoksa anlamsal istek SQL'den ÖNCE durur.
  kontrol <- pk_meta_capability_check(
    list(meta = girdi), list(measures = "labor.remaining_hours")
  )
  expect_identical(kontrol$status, PK_META_STATUS_NO_SEMANTICS)
})

test_that("Tier-0 varsayilanlari fail-closed kalir", {
  sema <- pkgs_schema_from_descriptor(.gen_desc(Kod = "nvarchar(50)"))
  girdi <- pkgn_build_local_entry(sema$schema, sema$source_types, "describe")

  expect_false(girdi$column_meta[["Kod"]]$filterable)
  expect_identical(girdi$column_meta[["Kod"]]$match, "none")
  expect_true(is.na(girdi$column_meta[["Kod"]]$high_cardinality))
})

# ------------------------------------------------------------------------------
# 3) Örnekleme kanıt sınırı — TEK YÖNLÜ
# ------------------------------------------------------------------------------

test_that("onek ornegi benzersizlik/null-yok/dusuk-kardinalite KANITLAMAZ", {
  df <- data.frame(
    Benzersiz = c("a", "b", "c"),
    AzDeger = c("x", "x", "y"),
    stringsAsFactors = FALSE
  )
  gozlem <- pkgs_sample_observations(df, high_cardinality_threshold = 50L,
                                     method = "prefix")

  expect_identical(gozlem$Benzersiz$evidence, "prefix_one_sided")

  # Mükerrer GÖRMEMEK benzersizliği KANITLAMAZ.
  expect_false(isTRUE(gozlem$Benzersiz$unique_disproved))
  # Ama gözlenen bir mükerrer benzersizliği ÇÜRÜTÜR (tek yönlü, güvenli).
  expect_true(gozlem$AzDeger$unique_disproved)

  # 3 farklı değer görmek DÜŞÜK kardinaliteyi kanıtlamaz; alan NA kalmalıdır.
  cmeta <- pkgs_apply_observations(
    pkgs_build_column_meta(c(Benzersiz = "character", AzDeger = "character"),
                           NULL, "sample"),
    gozlem
  )
  expect_true(is.na(cmeta$Benzersiz$high_cardinality))
  expect_true(is.na(cmeta$AzDeger$high_cardinality))
})

test_that("esik ustu farkli deger YUKSEK kardinaliteyi kanitlar (tek yonlu TRUE)", {
  df <- data.frame(Kod = as.character(seq_len(12)), stringsAsFactors = FALSE)
  gozlem <- pkgs_sample_observations(df, high_cardinality_threshold = 5L)

  expect_true(gozlem$Kod$high_cardinality_proved)

  cmeta <- pkgs_apply_observations(
    pkgs_build_column_meta(c(Kod = "character"), NULL, "sample"), gozlem
  )
  expect_true(cmeta$Kod$high_cardinality)
})

test_that("gozlenen NULL kaydedilir; NULL gormemek 'null yok' KANITLAMAZ", {
  df <- data.frame(A = c(1, NA), B = c(1, 2))
  gozlem <- pkgs_sample_observations(df)

  expect_true(gozlem$A$null_observed)
  expect_false(gozlem$B$null_observed)
  # `null_observed = FALSE` "bu sütunda NULL yok" DEMEK DEĞİLDİR; sözleşme
  # alanlarına (örn. bir NOT NULL iddiası) terfi ettirilmemelidir.
  cmeta <- pkgs_apply_observations(
    pkgs_build_column_meta(c(A = "numeric", B = "numeric"), NULL, "sample"), gozlem
  )
  expect_null(cmeta$B$not_null)
})

test_that("ornek satir sayisi tavana degdiginde yalnizca ALT SINIR bildirilir", {
  cfg <- .gen_test_config("sample")
  cfg$sample_rows <- 3L
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  sonuc <- .gen_run(lib, cfg, sample_fn = function(conn, sql, n) {
    data.frame(A = seq_len(3), stringsAsFactors = FALSE)
  })

  ornek <- sonuc$records[[1]]$sample
  expect_true(ornek$row_count_is_lower_bound)
  # 3 satırlık örnek 4 satırlık sonucu 5 milyondan AYIRT EDEMEZ: row_cap
  # geçti/kaldı iddiası ÜRETİLMEZ.
  expect_identical(ornek$cardinality_claim, "unknown")
  expect_identical(ornek$method, "prefix")
})

# ------------------------------------------------------------------------------
# 4) Kararlı id
# ------------------------------------------------------------------------------

test_that("metadata liste konumuna degil KARARLI id'ye baglanir", {
  cfg <- .gen_test_config("describe")
  desc <- function(conn, sql) .gen_desc(A = "int")

  lib1 <- list(
    list(id = "q_alpha", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    list(id = "q_beta", name = "B", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list())
  )
  lib2 <- rev(lib1)

  s1 <- .gen_run(lib1, cfg, describe_fn = desc)
  s2 <- .gen_run(lib2, cfg, describe_fn = desc)

  # Kütüphaneyi yeniden sıralamak metadata anahtarlarını DEĞİŞTİRMEMELİDİR.
  expect_setequal(names(s1$local_meta), names(s2$local_meta))
  expect_identical(s1$local_meta$q_alpha$result_schema,
                   s2$local_meta$q_alpha$result_schema)
})

test_that("kararli id tasimayan sorgu basarisiz sayilir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(name = "Idsiz", db_target = "primary", sql = "SELECT A FROM T"))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(A = "int"))
  expect_identical(sonuc$records[[1]]$status, "failed")
  expect_true(any(vapply(sonuc$records[[1]]$findings,
                         function(f) identical(f$code, "missing_query_id"), logical(1))))
})

# ------------------------------------------------------------------------------
# 5) Katman birleşmesi — KÜRE EDİLMİŞ KAZANIR
# ------------------------------------------------------------------------------

test_that("kure edilmis metadata uretilen katmani YENER", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT Saat FROM T", rls_columns = list()))

  # Üretici yapıdan `measure` çıkarır; küre edilmiş katman ANLAMI ekler.
  kure <- list(q1 = list(
    column_meta = list(Saat = list(
      role = "measure", capability = "labor.remaining_hours",
      unit = "saat", additive = TRUE, aggregate = "sum"
    )),
    primary_entity = NULL
  ))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(Saat = "decimal(18,2)"),
                    curated = kure,
                    registry = list("labor.remaining_hours" = list(role = "measure", unit = "saat")))

  expect_identical(sonuc$records[[1]]$status, "ok")

  birlesik <- pk_meta_merge_layers(
    auto = list(), local = sonuc$local_meta, curated = kure
  )$q1

  expect_identical(birlesik$column_meta$Saat$capability, "labor.remaining_hours")
  expect_true(birlesik$column_meta$Saat$additive)
  # Üretilen yapısal alanlar KAYBOLMAZ; küre edilmiş alanların yanında durur.
  expect_identical(unname(birlesik$result_schema[["Saat"]]), "numeric")
})

test_that("uretilen katman kuresyonu EZMEZ (alan bazli birlesme)", {
  sema <- c(Kod = "character")
  uretilen <- pkgn_build_local_entry(sema, NULL, "describe")
  kure <- list(column_meta = list(Kod = list(role = "dimension", match = "resolve",
                                             filterable = TRUE)))

  birlesik <- pk_meta_merge_layers(
    local = list(q = uretilen), curated = list(q = kure)
  )$q

  # Üretici `match="none"` / `filterable=FALSE` yazar; küre edilmiş değer kazanır.
  expect_identical(birlesik$column_meta$Kod$match, "resolve")
  expect_true(birlesik$column_meta$Kod$filterable)
  # Üreticinin köken alanı korunur.
  expect_identical(birlesik$column_meta$Kod$inferred_from, "generator_describe")
})

# ------------------------------------------------------------------------------
# 6) RLS — GÜVENLİK KRİTİK
# ------------------------------------------------------------------------------

test_that("beyan edilen RLS sutunu semada yoksa GUVENLIK bulgusu uretilir", {
  cfg <- .gen_test_config("describe")
  # Operatörün VM'de gördüğü gerçek durum.
  lib <- list(list(
    id = "gen_pro_per_01", name = "Kisi bazli", db_target = "primary",
    sql = "SELECT SicilNo, Saat FROM T",
    rls_columns = list(proje_kodu_col = "ProjeKodu", eps_kodu_col = "ProgMd1Kodu")
  ))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    .gen_desc(SicilNo = "int", Saat = "decimal(18,2)")
  })

  kayit <- sonuc$records[[1]]
  expect_identical(kayit$status, "withheld")
  expect_gt(kayit$security_finding_count, 0L)

  rls_bulgu <- Filter(function(f) identical(f$code, "rls_column_missing"), kayit$findings)
  expect_length(rls_bulgu, 1L)
  expect_true(rls_bulgu[[1]]$security_relevant)
  expect_setequal(rls_bulgu[[1]]$columns, c("ProjeKodu", "ProgMd1Kodu"))
  expect_identical(sonuc$summary$rls_mismatches, 1L)
})

test_that("uretici RLS beyanini KALDIRMAZ, devre disi BIRAKMAZ, SQL'i ONARMAZ", {
  cfg <- .gen_test_config("describe")
  rls <- list(proje_kodu_col = "ProjeKodu")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT SicilNo FROM T", rls_columns = rls))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(SicilNo = "int"))

  # Girdi kütüphanesi DEĞİŞMEMİŞTİR ve üretilen katman bir RLS alanı taşımaz.
  expect_identical(lib[[1]]$rls_columns, rls)
  expect_identical(lib[[1]]$sql, "SELECT SicilNo FROM T")
  expect_null(sonuc$local_meta$q1)

  # Geri çekilen sorgu BUGÜNKÜ davranışında kalır: şeması olmadığı için
  # `pending_no_schema` ve istek zamanı RLS kapısı DEĞİŞMEZ (fail-closed).
  gercek <- pk_meta_validate_actual_columns(lib[[1]], c("SicilNo"))
  expect_true(gercek$fail_closed)
  expect_identical(gercek$missing_rls, "ProjeKodu")
})

test_that("RLS beyani semada VARSA bulgu uretilmez", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT ProjeKodu FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(ProjeKodu = "nvarchar(50)"))

  expect_identical(sonuc$records[[1]]$status, "ok")
  expect_identical(sonuc$records[[1]]$security_finding_count, 0L)
})

# ------------------------------------------------------------------------------
# 7) Metadata atıf ve rol/tip uyuşmazlıkları
# ------------------------------------------------------------------------------

test_that("kuresyonun atif ettigi eksik sutun bloklayici bulgudur", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))
  kure <- list(q1 = list(column_meta = list(Yok = list(role = "dimension"))))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(A = "int"),
                    curated = kure)

  kayit <- sonuc$records[[1]]
  expect_identical(kayit$status, "withheld")
  expect_true(any(vapply(kayit$findings, function(f) {
    identical(f$code, "column_meta_missing_in_schema")
  }, logical(1))))
})

test_that("role='measure' iken semadaki tip metinse bloklayici uyusmazlik uretilir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT Tutar FROM T", rls_columns = list()))
  kure <- list(q1 = list(column_meta = list(Tutar = list(role = "measure"))))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(Tutar = "nvarchar(50)"),
                    curated = kure)

  kayit <- sonuc$records[[1]]
  expect_identical(kayit$status, "withheld")
  # Sessiz yanlış toplam üretilmeden ÖNCE yakalanmalıdır.
  expect_true(any(vapply(kayit$findings, function(f) {
    identical(f$code, "role_type_mismatch")
  }, logical(1))))
})

test_that("Tier-0 ve kuresyon bekleyen sorgular raporlanir", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q_ok", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    list(id = "q_tier0", name = "B", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list())
  )

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    if (identical(sql, "SELECT A FROM T")) return(.gen_desc(A = "int"))
    NULL
  })

  expect_identical(sonuc$summary$queries_needing_curation, 2L)
  expect_true(all(vapply(sonuc$records, function(r) {
    any(vapply(r$findings, function(f) identical(f$code, "no_semantic_capability"),
               logical(1)))
  }, logical(1))))
})

test_that("sema alinamayan sorgu Tier-0 olarak raporlanir ve kosuyu dusurmez", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) NULL)

  kayit <- sonuc$records[[1]]
  expect_identical(kayit$status, "failed")
  expect_true(kayit$tier0)
  expect_identical(kayit$schema_validation, "pending_no_schema")
  expect_identical(sonuc$summary$tier0_queries, 1L)
})

# ------------------------------------------------------------------------------
# 8) Salt-okunur kapısı ve dayanıklılık
# ------------------------------------------------------------------------------

test_that("salt-okunur olmayan SQL CALISTIRILMAZ", {
  cfg <- .gen_test_config("sample")
  lib <- list(
    list(id = "q_update", name = "U", db_target = "primary",
         sql = "UPDATE T SET x = 1", rls_columns = list()),
    list(id = "q_drop", name = "D", db_target = "primary",
         sql = "DROP TABLE T", rls_columns = list()),
    list(id = "q_multi", name = "M", db_target = "primary",
         sql = "SELECT 1; DELETE FROM T", rls_columns = list())
  )

  calistirildi <- FALSE
  sonuc <- .gen_run(lib, cfg, sample_fn = function(conn, sql, n) {
    calistirildi <<- TRUE
    data.frame(A = 1)
  })

  # Üretici ASLA veri değiştiren bir ifade çalıştırmaz.
  expect_false(calistirildi)
  expect_true(all(vapply(sonuc$records, function(r) identical(r$status, "skipped"),
                         logical(1))))
  expect_identical(sonuc$summary$skipped, 3L)
  expect_length(sonuc$local_meta, 0L)
})

test_that("bir bozuk sorgu raporun geri kalanini bozmaz", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q_ok1", name = "A", db_target = "primary", sql = "SELECT A FROM T1",
         rls_columns = list()),
    list(id = "q_bad", name = "B", db_target = "primary", sql = "SELECT A FROM T2",
         rls_columns = list()),
    list(id = "q_ok2", name = "C", db_target = "primary", sql = "SELECT A FROM T3",
         rls_columns = list())
  )

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    if (grepl("T2", sql, fixed = TRUE)) stop("beklenmeyen surucu hatasi")
    .gen_desc(A = "int")
  })

  expect_length(sonuc$records, 3L)
  expect_identical(sonuc$records[[1]]$status, "ok")
  expect_identical(sonuc$records[[2]]$status, "failed")
  expect_identical(sonuc$records[[3]]$status, "ok")
  expect_setequal(names(sonuc$local_meta), c("q_ok1", "q_ok2"))
})

test_that("baglanti kurulamadiginda sorgular Tier-0 kalir ve baglanti birakilir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  birakildi <- 0L
  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) stop("DSN acilmadi"),
    release_fn = function(handle) birakildi <<- birakildi + 1L,
    describe_fn = function(conn, sql) .gen_desc(A = "int"),
    sample_fn = function(conn, sql, n) data.frame(A = 1)
  )

  expect_identical(sonuc$records[[1]]$status, "failed")
  expect_true(sonuc$records[[1]]$tier0)
  expect_length(sonuc$local_meta, 0L)
})

test_that("basarili kosuda baglanti HER DURUMDA birakilir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  birakildi <- 0L
  pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) list(conn = .gen_fake_conn()),
    release_fn = function(handle) birakildi <<- birakildi + 1L,
    describe_fn = function(conn, sql) .gen_desc(A = "int"),
    sample_fn = function(conn, sql, n) data.frame(A = 1)
  )

  expect_identical(birakildi, 1L)
})

# ------------------------------------------------------------------------------
# 9) Gizli değer sızıntısı
# ------------------------------------------------------------------------------

test_that("surucu hatasindaki DSN/parola rapora GIRMEZ", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  gizli <- paste0("hun", "ter2")
  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    stop(sprintf("Login failed. DSN=UretimDSN;UID=svc_mergen;PWD=%s", gizli))
  })

  kayit <- sonuc$records[[1]]
  tum_metin <- paste(
    as.character(kayit$error),
    paste(vapply(kayit$findings, function(f) f$detail, character(1)), collapse = " ")
  )

  expect_false(grepl(gizli, tum_metin, fixed = TRUE))
  expect_false(grepl("UretimDSN", tum_metin, fixed = TRUE))
  expect_true(grepl("gizli", tum_metin, fixed = TRUE))
})

test_that("reddedilen SQL'in HAM METNI rapora girmez", {
  cfg <- .gen_test_config("describe")
  gizli_sql <- "UPDATE GizliTablo SET Maas = 1"
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = gizli_sql, rls_columns = list()))

  sonuc <- .gen_run(lib, cfg)
  detaylar <- paste(vapply(sonuc$records[[1]]$findings, function(f) f$detail,
                           character(1)), collapse = " ")
  expect_false(grepl("GizliTablo", detaylar, fixed = TRUE))
})

# ------------------------------------------------------------------------------
# 10) Çıktı dosyası — hedef kapısı, ASCII, atomiklik, geri source
# ------------------------------------------------------------------------------

test_that("uretici OPERATOR ALIAS dosyasina ASLA yazmaz", {
  gecici <- withr::local_tempdir()

  for (yasak in PKG_META_FORBIDDEN_TARGETS) {
    expect_error(
      pkgr_write_local_meta_file("x <- 1", file.path(gecici, basename(yasak))),
      "YASAKLI HEDEF|Beklenmeyen cikti hedefi"
    )
  }

  # Alias dosyası özellikle adıyla korunur.
  expect_error(
    pkgr_write_local_meta_file("x <- 1", file.path(gecici, "library_query_aliases_local.R")),
    "YASAKLI HEDEF"
  )
  expect_false(file.exists(file.path(gecici, "library_query_aliases_local.R")))
})

test_that("uretilen kaynak SAF ASCII'dir ve Turkce sutun adlari bozulmadan geri okunur", {
  gecici <- withr::local_tempdir()
  hedef <- file.path(gecici, "library_query_meta_local.R")

  sema <- c("ProjeAdı" = "character", "Tamamlanma_Yüzdesi" = "numeric",
            "Şube" = "character")
  girdi <- pkgn_build_local_entry(sema, NULL, "describe")
  metin <- pkgr_render_local_meta_file(list(q_türkçe = girdi),
                                       list(mode = "describe", timestamp = "T",
                                            artifact_rel = "A"))
  pkgr_write_local_meta_file(metin, hedef)

  # Windows VM'de yerel kod sayfası WINDOWS-1254'tür; saf ASCII çıktı
  # `source(..., encoding="UTF-8")` kesilme sınıfını tamamen kapatır.
  ham <- readBin(hedef, what = "raw", n = file.info(hedef)$size)
  expect_false(any(as.integer(ham) > 127L))

  ortam <- new.env()
  source(hedef, local = ortam, encoding = "UTF-8")
  geri <- ortam$pk_query_meta_local[["q_türkçe"]]$result_schema

  expect_identical(geri, sema)
  expect_identical(names(geri)[1], "ProjeAdı")
})

test_that("uretilen dosya parse edilemezse ONCEKI dosya korunur", {
  gecici <- withr::local_tempdir()
  hedef <- file.path(gecici, "library_query_meta_local.R")

  onceki <- "pk_query_meta_local <- list(saglam = TRUE)\n"
  writeLines(onceki, hedef)

  expect_error(
    pkgr_write_local_meta_file("pk_query_meta_local <- list(", hedef),
    "parse edilemedi"
  )

  # Yarım/bozuk dosya ASLA yerine geçmez.
  expect_identical(trimws(paste(readLines(hedef), collapse = "\n")), trimws(onceki))
  expect_length(list.files(gecici, pattern = "\\.tmp-"), 0L)
})

test_that("uretilen dosya pk_query_meta_attach kapisindan gecer", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT ProjeKodu, Saat FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    .gen_desc(ProjeKodu = "nvarchar(50)", Saat = "decimal(18,2)")
  })

  # Üreticinin "dahil edilebilir" kararı, uygulamanın açılışta vereceği
  # kararla BİREBİR aynı olmalıdır; aksi halde üretici uygulamayı kırardı.
  expect_silent(
    baglanmis <- pk_query_meta_attach(lib, auto = list(), local = sonuc$local_meta,
                                      curated = list(), aliases = list(),
                                      registry = list())
  )
  expect_identical(baglanmis[[1]]$meta$schema_validation, PK_META_SCHEMA_VALIDATED)
})

test_that("geri cekilen sorgu attach kapisini DUSURMEZ", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "gen_pro_per_01", name = "K", db_target = "primary",
                   sql = "SELECT SicilNo FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(SicilNo = "int"))
  expect_length(sonuc$local_meta, 0L)

  # Geri çekildiği için şema yoktur: sorgu bugünkü Tier-0 yolundan boot eder.
  baglanmis <- pk_query_meta_attach(lib, auto = list(), local = sonuc$local_meta,
                                    curated = list(), aliases = list(), registry = list())
  expect_identical(baglanmis[[1]]$meta$schema_validation, PK_META_SCHEMA_PENDING)
})

test_that("render fonksiyon/ortam degerini reddeder (cikti salt VERIDIR)", {
  expect_error(pkgr_encode_value(list(f = function(x) x)), "yalnizca veri")
  expect_error(pkgr_encode_value(list(e = new.env())), "yalnizca veri")
})

test_that("render NA/logical/integer/numeric degerleri tam olarak geri okur", {
  gecici <- withr::local_tempdir()
  hedef <- file.path(gecici, "library_query_meta_local.R")

  girdi <- list(q = list(
    column_meta = list(A = list(high_cardinality = NA, tier = 0L, filterable = FALSE)),
    oran = 0.1234567890123456,
    bos = list()
  ))
  pkgr_write_local_meta_file(
    pkgr_render_local_meta_file(girdi, list(mode = "describe")), hedef
  )

  ortam <- new.env()
  source(hedef, local = ortam, encoding = "UTF-8")
  geri <- ortam$pk_query_meta_local$q

  expect_true(is.na(geri$column_meta$A$high_cardinality))
  expect_true(is.logical(geri$column_meta$A$high_cardinality))
  expect_identical(geri$column_meta$A$tier, 0L)
  expect_false(geri$column_meta$A$filterable)
  expect_equal(geri$oran, 0.1234567890123456)
  expect_identical(geri$bos, list())
})

# ------------------------------------------------------------------------------
# 11) Sağlık raporu biçimi
# ------------------------------------------------------------------------------

test_that("saglik ozeti ve metin raporu tutarlidir", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q_ok", name = "Saglikli", db_target = "primary",
         sql = "SELECT ProjeKodu FROM T",
         rls_columns = list(proje_kodu_col = "ProjeKodu")),
    list(id = "q_rls", name = "RLS eksik", db_target = "primary",
         sql = "SELECT SicilNo FROM T",
         rls_columns = list(proje_kodu_col = "ProjeKodu"))
  )

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    if (grepl("SicilNo", sql, fixed = TRUE)) return(.gen_desc(SicilNo = "int"))
    .gen_desc(ProjeKodu = "nvarchar(50)")
  })

  ozet <- sonuc$summary
  expect_identical(ozet$total_queries, 2L)
  expect_identical(ozet$included, 1L)
  expect_identical(ozet$withheld, 1L)
  expect_identical(ozet$rls_mismatches, 1L)

  metin <- pkgh_render_text(ozet, sonuc$records, pkg_meta_config_summary(cfg))
  expect_true(grepl("q_rls", metin, fixed = TRUE))
  expect_true(grepl("GERI CEKILDI", metin, fixed = TRUE))
  expect_true(grepl("YENIDEN BASLATILIR", metin, fixed = TRUE))

  konsol <- pkgh_render_console(ozet, sonuc$records)
  expect_true(grepl("GUVENLIK", konsol, fixed = TRUE))
})

test_that("saglik artefaktlari yazilir ve gizli deger tasimaz", {
  skip_if_not_installed("jsonlite")

  gecici <- withr::local_tempdir()
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q_rls", name = "RLS eksik", db_target = "primary",
                   sql = "SELECT SicilNo FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(SicilNo = "int"))

  rapor <- list(
    phase = "3b", timestamp = "T",
    config = pkg_meta_config_summary(cfg),
    summary = sonuc$summary, queries = sonuc$records
  )
  yollar <- pkgh_write_artifacts(rapor, gecici, sonuc$records, sonuc$summary,
                                 pkg_meta_config_summary(cfg))

  expect_true(file.exists(yollar$json))
  expect_true(file.exists(yollar$text))

  geri <- jsonlite::fromJSON(yollar$json, simplifyVector = FALSE)
  expect_identical(geri$summary$rls_mismatches, 1L)
  expect_identical(geri$queries[[1]]$status, "withheld")

  # Yapilandirma ozeti gizli deger TASIMAZ (DSN/kimlik/uc nokta yok).
  expect_null(geri$config$dsn)
  expect_setequal(
    names(geri$config),
    c("mode", "mode_defaulted", "sample_rows", "high_cardinality_threshold",
      "sql_timeout_sec", "max_result_mb", "resume", "output_rel", "artifact_rel")
  )

  metin <- paste(readLines(yollar$text, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_true(grepl("q_rls", metin, fixed = TRUE))
})

test_that("devam onbellegi yazilip geri okunur ve kip degisince YOK SAYILIR", {
  skip_if_not_installed("jsonlite")

  gecici <- withr::local_tempdir()
  durum_yolu <- file.path(gecici, "generator-state.json")

  onbellek <- list(q1 = list(
    mode = "describe",
    columns = c("ProjeAdı" = "character", "Saat" = "numeric"),
    source_types = c("ProjeAdı" = "nvarchar(200)", "Saat" = "decimal(18,2)")
  ))

  pkgh_write_state(onbellek, durum_yolu, "describe", "T")
  expect_true(file.exists(durum_yolu))

  geri <- pkgh_read_state(durum_yolu, "describe")
  expect_named(geri, "q1")
  expect_identical(geri$q1$schema, c("ProjeAdı" = "character", "Saat" = "numeric"))
  expect_identical(unname(geri$q1$source_types[["Saat"]]), "decimal(18,2)")
  expect_true(geri$q1$ok)

  # `describe` ile alinmis sema `sample` gozlemlerini TASIMAZ; kip degisince
  # onbellek yok sayilmalidir, aksi halde ornekleme kanitlari uydurulmus olur.
  expect_length(pkgh_read_state(durum_yolu, "sample"), 0L)

  # Bozuk/eksik durum dosyasi kosuyu DUSURMEZ.
  expect_length(pkgh_read_state(file.path(gecici, "yok.json"), "describe"), 0L)
  writeLines("{ bozuk", durum_yolu)
  expect_length(pkgh_read_state(durum_yolu, "describe"), 0L)
})

test_that("onbellekten gelen sema DB'ye HIC gitmeden kullanilir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT ProjeKodu FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  onbellek <- list(q1 = list(
    ok = TRUE,
    schema = c(ProjeKodu = "character"),
    source_types = c(ProjeKodu = "nvarchar(50)"),
    unmapped = character(0), unbounded = character(0), observations = list(),
    sample_info = list(mode = "describe", from_cache = TRUE),
    cache = list(mode = "describe", columns = c(ProjeKodu = "character"))
  ))

  db_dokunuldu <- FALSE
  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) {
      db_dokunuldu <<- TRUE
      list(conn = .gen_fake_conn())
    },
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) {
      db_dokunuldu <<- TRUE
      NULL
    },
    sample_fn = function(conn, sql, n) stop("beklenmiyordu"),
    cache = onbellek
  )

  # Kesintiye ugrayan bir kosu kaldigi yerden devam eder: onbellekli sorgu
  # icin DB'ye HIC gidilmez.
  expect_false(db_dokunuldu)
  expect_identical(sonuc$records[[1]]$status, "ok")
  expect_named(sonuc$local_meta, "q1")
})

test_that("resume kapaliyken onbellek KULLANILMAZ", {
  cfg <- .gen_test_config("describe")
  cfg$resume <- FALSE
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  onbellek <- list(q1 = list(ok = TRUE, schema = c(Eski = "character"),
                             source_types = NULL, observations = list()))

  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) list(conn = .gen_fake_conn()),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) .gen_desc(Yeni = "int"),
    sample_fn = function(conn, sql, n) stop("beklenmiyordu"),
    cache = onbellek
  )

  expect_identical(names(sonuc$local_meta$q1$result_schema), "Yeni")
})

test_that("saglik kaydi JSON'a serilestirilebilir", {
  skip_if_not_installed("jsonlite")

  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))
  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(A = "int"))

  json <- jsonlite::toJSON(
    list(summary = sonuc$summary, queries = sonuc$records),
    auto_unbox = TRUE, null = "null"
  )
  geri <- jsonlite::fromJSON(as.character(json), simplifyVector = FALSE)

  expect_identical(geri$summary$total_queries, 1L)
  expect_identical(geri$queries[[1]]$query_id, "q1")
  expect_identical(geri$queries[[1]]$status, "ok")
})
