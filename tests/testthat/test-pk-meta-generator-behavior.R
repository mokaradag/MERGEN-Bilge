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
  #
  # SIRA, GİRİŞ NOKTASININ SIRASIYLA AYNIDIR (tools/pk/generate_query_meta.R):
  # maskeleme bulgu üretiminden, şema getirme envanter döngüsünden ÖNCE gelir.
  # Bir yardımcı buraya EKLENMEZSE testler VM'de görülmeyen bir "fonksiyon
  # bulunamadi" hatasıyla düşer.
  for (dosya in c(
    "helpers_meta_generator_config.R",
    "helpers_meta_generator_schema.R",
    "helpers_meta_generator_render.R",
    "helpers_meta_generator_redact.R",
    "helpers_meta_generator_findings.R",
    "helpers_meta_generator_health.R",
    "helpers_meta_generator_state.R",
    "helpers_meta_generator_db.R",
    "helpers_meta_generator_fetch.R",
    "helpers_meta_generator_run.R",
    "helpers_meta_generator_lock.R",
    "helpers_meta_generator_commit.R"
  )) {
    source(file.path(repo_root, "tools", "pk", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# ------------------------------------------------------------------------------
# Ortak sahte (fake) kurulum
# ------------------------------------------------------------------------------

# Üreticinin OKUDUĞU HER ortam değişkeni burada AÇIKÇA temizlenir. Aksi hâlde,
# geliştirici/operatör kabuğunda ayarlı tek bir değer (örneğin
# MERGEN_PK_META_RESUME=false) "sabit" sanılan test yapılandırmasını sessizce
# değiştirir ve devam testleri varsayılan yolu HİÇ sınamaz.
.GEN_ENV_KEYS <- c(
  "MERGEN_PK_META_MODE", "MERGEN_PK_META_SAMPLE_ROWS",
  "MERGEN_PK_META_HIGH_CARD_MIN", "MERGEN_PK_META_SQL_TIMEOUT_SEC",
  "MERGEN_PK_META_MAX_RESULT_MB", "MERGEN_PK_META_RESUME",
  "MERGEN_PK_META_SAMPLE_UNICODE"
)

.gen_test_config <- function(mode = "describe", ...) {
  temiz <- stats::setNames(rep(NA_character_, length(.GEN_ENV_KEYS)), .GEN_ENV_KEYS)
  temiz[["MERGEN_PK_META_MODE"]] <- mode

  withr::with_envvar(temiz, {
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

# Üretilen katman hedefi SÖZLEŞME GEREĞİ `R/` dizinindedir; kapı yalnızca temel
# ada değil, dizin yapısına da bakar.
.gen_out_path <- function(dir) {
  hedef <- file.path(dir, "R")
  dir.create(hedef, recursive = TRUE, showWarnings = FALSE)
  file.path(hedef, "library_query_meta_local.R")
}

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
  # `odbc` bigint'i VARSAYILAN olarak bit64::integer64 dondurur; describe kipi
  # "numeric" yazsaydi ayni sutun sample kipinde "integer64" gorunur ve yalnizca
  # kip degistirmek metadata'yi calkalardi.
  expect_identical(unname(sema$schema[["Sayi"]]), "integer64")
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
  # Bulgu, hangi NATIF tipin eslenemedigini de tasir: yalnizca sutun adi
  # operatore hangi eslemenin eklenecegini SOYLEMEZ.
  expect_length(sema$unmapped, 1L)
  expect_identical(sema$unmapped[[1]]$column, "Konum")
  expect_identical(sema$unmapped[[1]]$source_type, "geography")
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
  # TEK YÖNLÜ KANIT: gözlenmemek KAYDEDİLMEZ. `null_observed = FALSE` yazmak,
  # "bu önekte görülmedi" ile "gerçekten yok" arasındaki farkı SİLER; alan
  # `observed` altında kalıcılaştığı için sonraki okuyucu ikisini AYIRT EDEMEZ.
  # Bu yüzden karşı örnek yoksa alan TANIMSIZ kalır.
  expect_null(gozlem$B$null_observed)
  # Alan hiçbir durumda sözleşme alanlarına (örn. bir NOT NULL iddiası) terfi
  # ettirilmemelidir.
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
  expect_false(grepl("svc_mergen", tum_metin, fixed = TRUE))
  # Ham sürücü metni HİÇ yazılmaz: salt-okunur bir sorgu bile hata metninde
  # ÜRETİM SATIR DEĞERİ taşıyabilir. Yerine kararlı bir sınıflandırma yazılır.
  expect_true(grepl("Ham surucu metni", tum_metin, fixed = TRUE))
  expect_true(grepl("sinif=", tum_metin, fixed = TRUE))
})

test_that("surucu hata ozeti satir degeri TASIMAZ ama SQLSTATE'i korur", {
  ad <- paste0("Ahmet ", "Yilmaz")
  ozet <- pkgh_db_error_summary(sprintf(
    "[Microsoft][ODBC Driver 17][SQL Server]Conversion failed when converting the nvarchar value '%s' to data type int. [22018]",
    ad
  ))

  # Bir dönüşüm hatası ÜRETİM SATIR DEĞERİNİ metne gömer; rapor bunu ASLA
  # kalıcılaştırmamalıdır.
  expect_false(grepl(ad, ozet, fixed = TRUE))
  expect_true(grepl("conversion_failed", ozet, fixed = TRUE))

  # Bağlantı/izin sınıfları da ayrı ayrı tanınmalıdır.
  expect_true(grepl("connection_lost", pkgh_db_error_summary("08S01 communication link failure"),
                    fixed = TRUE))
  expect_true(grepl("permission_denied", pkgh_db_error_summary("Login failed for user"),
                    fixed = TRUE))
})

test_that("baglanti dizesi degerinin TAMAMI maskelenir", {
  metin <- .pkgh_redact("DSN={Prod SQL};UID={DOMAIN User};PWD=abc123;Deneme=1")

  # Boşluktan kesen bir maske `SQL}` / `User}` artıklarını raporda BIRAKIRDI.
  expect_false(grepl("Prod SQL", metin, fixed = TRUE))
  expect_false(grepl("DOMAIN User", metin, fixed = TRUE))
  expect_false(grepl("abc123", metin, fixed = TRUE))
  expect_true(grepl("<gizli>", metin, fixed = TRUE))
  # İlgisiz anahtar/değer çiftleri KORUNUR.
  expect_true(grepl("Deneme=1", metin, fixed = TRUE))
})

test_that("baslangic dogrulama hatasindaki alias ayrintisi rapora GIRMEZ", {
  ham <- paste(
    "[PK_META] Sorgu metadata sozlesmesi gecersiz (1 bulgu):",
    "  - [q1] alias bindirmesinde catisan kanonik hedef: Gercek Proje Adi",
    sep = "\n"
  )
  temiz <- pkgh_sanitize_validation_error(ham)

  # Alias bindirmesi ÜRETİMDEN TÜRETİLMİŞTİR; kanonik hedef değerleri gerçek
  # proje/program adları olabilir.
  expect_false(grepl("Gercek Proje Adi", temiz, fixed = TRUE))
  expect_true(grepl("[q1]", temiz, fixed = TRUE))
  # Alias ile ilgisiz satır KORUNUR.
  expect_true(grepl("Sorgu metadata sozlesmesi gecersiz", temiz, fixed = TRUE))
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
  hedef <- .gen_out_path(gecici)

  sema <- c("ProjeAdı" = "character", "Tamamlanma_Yüzdesi" = "numeric",
            "Şube" = "character")
  girdi <- pkgn_build_local_entry(sema, NULL, "describe")
  metin <- pkgr_render_local_meta_file(list(q_turkce = girdi),
                                       list(mode = "describe", timestamp = "T",
                                            artifact_rel = "A"))
  pkgr_write_local_meta_file(metin, hedef)

  # Windows VM'de yerel kod sayfası WINDOWS-1254'tür; saf ASCII çıktı
  # `source(..., encoding="UTF-8")` kesilme sınıfını tamamen kapatır.
  ham <- readBin(hedef, what = "raw", n = file.info(hedef)$size)
  expect_false(any(as.integer(ham) > 127L))

  ortam <- new.env()
  source(hedef, local = ortam, encoding = "UTF-8")
  geri <- ortam$pk_query_meta_local[["q_turkce"]]$result_schema

  expect_identical(geri, sema)
  expect_identical(names(geri)[1], "ProjeAdı")
})

test_that("uretilen dosya parse edilemezse ONCEKI dosya korunur", {
  gecici <- withr::local_tempdir()
  hedef <- .gen_out_path(gecici)

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
  hedef <- .gen_out_path(gecici)

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
      "sql_timeout_sec", "max_result_mb", "sample_unicode", "resume",
      "output_rel", "artifact_rel", "run_id")
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
    fingerprint = "fp-1",
    columns = c("ProjeAdı" = "character", "Saat" = "numeric"),
    source_types = c("ProjeAdı" = "nvarchar(200)", "Saat" = "decimal(18,2)")
  ))

  expect_true(pkgh_write_state(onbellek, durum_yolu, "describe", "T"))
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

# ------------------------------------------------------------------------------
# 12) Devam önbelleği: PARMAK İZİ ve KANIT ALANLARI
# ------------------------------------------------------------------------------

test_that("SQL degisince devam onbellegi girdisi KABUL EDILMEZ", {
  skip_if_not_installed("jsonlite")

  gecici <- withr::local_tempdir()
  durum_yolu <- file.path(gecici, "generator-state.json")

  eski_sorgu <- list(id = "q1", db_target = "primary", sql = "SELECT A FROM T")
  yeni_sorgu <- list(id = "q1", db_target = "primary", sql = "SELECT A, B FROM T")

  onbellek <- list(q1 = list(
    mode = "describe",
    fingerprint = pkgh_state_fingerprint(eski_sorgu),
    columns = c(A = "integer"),
    source_types = c(A = "int")
  ))
  pkgh_write_state(onbellek, durum_yolu, "describe", "T")

  # Aynı SQL: girdi kabul edilir.
  ayni <- pkgh_read_state(durum_yolu, "describe",
                          fingerprints = pkgh_state_fingerprints(list(eski_sorgu)))
  expect_named(ayni, "q1")

  # SELECT listesi değişmiş: eski şema o sorguyu ARTIK TEMSİL ETMEZ. Kabul
  # edilseydi, üreticiyi tekrar çalıştırmak bayat metadata'yı ONARAMAZDI.
  degismis <- pkgh_read_state(durum_yolu, "describe",
                              fingerprints = pkgh_state_fingerprints(list(yeni_sorgu)))
  expect_length(degismis, 0L)

  # Kütüphaneden kalkmış bir kimlik de kabul edilmez.
  expect_length(pkgh_read_state(durum_yolu, "describe", fingerprints = list()), 0L)
})

test_that("bicim surumu degisince devam onbellegi TAMAMEN yok sayilir", {
  skip_if_not_installed("jsonlite")

  gecici <- withr::local_tempdir()
  durum_yolu <- file.path(gecici, "generator-state.json")

  pkgh_write_state(list(q1 = list(columns = c(A = "integer"), fingerprint = "fp")),
                   durum_yolu, "describe", "T", state_version = 1L)

  expect_length(pkgh_read_state(durum_yolu, "describe", state_version = 2L), 0L)
  expect_named(pkgh_read_state(durum_yolu, "describe", state_version = 1L), "q1")
})

test_that("devam onbellegi KANIT alanlarini yuvarlak yolculukla korur", {
  skip_if_not_installed("jsonlite")

  gecici <- withr::local_tempdir()
  durum_yolu <- file.path(gecici, "generator-state.json")

  onbellek <- list(q1 = list(
    fingerprint = "fp",
    columns = c(Kod = "character"),
    source_types = c(Kod = "nvarchar(max)"),
    unmapped = list(list(column = "Kod", source_type = "geography")),
    unbounded = "Kod",
    observations = list(Kod = list(high_cardinality_proved = TRUE, distinct_observed = 99))
  ))
  pkgh_write_state(onbellek, durum_yolu, "sample", "T")

  geri <- pkgh_read_state(durum_yolu, "sample")
  # Bunları boş yeniden kurmak, ikinci koşuda yüksek kardinalite gözlemlerini ve
  # eşlenmeyen/sınırsız tip bulgularını SESSİZCE düşürürdü.
  expect_identical(geri$q1$unbounded, "Kod")
  expect_length(geri$q1$unmapped, 1L)
  expect_true(isTRUE(geri$q1$observations$Kod$high_cardinality_proved))
})

test_that("ara kayit her sorgudan SONRA yazilir", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q1", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    list(id = "q2", name = "B", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list())
  )

  anlik <- list()
  pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) list(conn = .gen_fake_conn()),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) .gen_desc(A = "int"),
    sample_fn = function(conn, sql, n) stop("beklenmiyordu"),
    checkpoint_fn = function(cache) anlik[[length(anlik) + 1L]] <<- names(cache)
  )

  # Yalnızca koşu SONUNDA yazmak, gerçek bir kesintide TÜM ilerlemeyi
  # kaybettirirdi; "kaldığı yerden devam" ilanı o hâlde işlevsiz olurdu.
  expect_length(anlik, 2L)
  expect_identical(anlik[[1]], "q1")
  expect_setequal(anlik[[2]], c("q1", "q2"))
})

# ------------------------------------------------------------------------------
# 13) Bağlantı yaşam döngüsü ve hedef doğrulaması
# ------------------------------------------------------------------------------

test_that("BILINMEYEN db_target icin baglanti ACILMAZ", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "secondaryy",
                   sql = "SELECT A FROM T", rls_columns = list()))

  baglandi <- FALSE
  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) {
      baglandi <<- TRUE
      list(conn = .gen_fake_conn())
    },
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) .gen_desc(A = "int"),
    sample_fn = function(conn, sql, n) data.frame(A = 1)
  )

  # `get_connection()` bilinmeyen bir hedefi BIRINCIL DSN'e düşürür: yazım
  # hatası sorguyu yanlış veritabanında çalıştırırdı.
  expect_false(baglandi)
  expect_identical(sonuc$records[[1]]$status, "failed")
  expect_true(any(vapply(sonuc$records[[1]]$findings,
                         function(f) identical(f$code, "invalid_db_target"), logical(1))))
})

test_that("BASARISIZ baglanti onbellege ALINMAZ; sonraki sorgu yeniden dener", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q1", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    list(id = "q2", name = "B", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list())
  )

  deneme <- 0L
  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) {
      deneme <<- deneme + 1L
      if (deneme == 1L) stop("gecici checkout hatasi")
      list(conn = .gen_fake_conn())
    },
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) .gen_desc(A = "int"),
    sample_fn = function(conn, sql, n) stop("beklenmiyordu")
  )

  # Tek bir geçici hata onbelleğe NULL yazsaydı, o hedefteki BÜTÜN sonraki
  # sorgular yeniden deneme şansı bulamadan düşerdi.
  expect_identical(deneme, 2L)
  expect_identical(sonuc$records[[1]]$status, "failed")
  expect_identical(sonuc$records[[2]]$status, "ok")
})

test_that("OLU baglanti birakilir ve sonraki sorgu icin yenisi acilir", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q1", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    list(id = "q2", name = "B", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list())
  )

  acilan <- 0L
  birakilan <- 0L
  cagri <- 0L
  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) {
      acilan <<- acilan + 1L
      list(conn = .gen_fake_conn())
    },
    release_fn = function(handle) birakilan <<- birakilan + 1L,
    describe_fn = function(conn, sql) {
      cagri <<- cagri + 1L
      if (cagri == 1L) stop("08S01 communication link failure")
      .gen_desc(A = "int")
    },
    sample_fn = function(conn, sql, n) stop("beklenmiyordu")
  )

  # Ölü tutamaç önbellekte kalsaydı, aynı hedefteki her sonraki sorgu da
  # düşerdi. Bu, ilk `connect_fn()` hatasından FARKLI bir durumdur.
  expect_identical(acilan, 2L)
  expect_gte(birakilan, 1L)
  expect_identical(sonuc$records[[2]]$status, "ok")
})

test_that("HAM DBIConnection donduren enjekte edilmis connect_fn desteklenir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  ham_conn <- structure(list(), class = c("fake_dbi", "DBIConnection"))
  gorulen <- NULL

  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) ham_conn,
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) {
      gorulen <<- conn
      .gen_desc(A = "int")
    },
    sample_fn = function(conn, sql, n) stop("beklenmiyordu")
  )

  # Belgelenen sözleşme "bağlantı nesnesi ya da NULL" der; `$conn` erişimini
  # koşulsuz yapmak ham bir bağlantıda TÜM envanteri düşürürdü.
  expect_identical(sonuc$records[[1]]$status, "ok")
  expect_true(inherits(gorulen, "DBIConnection"))
})

# ------------------------------------------------------------------------------
# 14) Rapor doğruluğu
# ------------------------------------------------------------------------------

test_that("GERI CEKILEN sorgu Tier-0 olarak raporlanir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT SicilNo FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(SicilNo = "int"))
  kayit <- sonuc$records[[1]]

  # Şema ELDE olsa da sorgu üretilen katmana GİRMEZ; çalışma zamanı onu
  # Tier-0/`pending_no_schema` görür. `validated` demek YANLIŞ bir hazırlık
  # tablosu sunardı.
  expect_identical(kayit$status, "withheld")
  expect_true(kayit$tier0)
  expect_identical(kayit$schema_validation, "pending_no_schema")
  expect_identical(sonuc$summary$tier0_queries, 1L)
})

test_that("basarisiz/atlanan sorgu anlamsal KAPSAMA sayilmaz", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q_fail", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    list(id = "q_skip", name = "B", db_target = "primary", sql = "DROP TABLE T",
         rls_columns = list())
  )

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) NULL)

  # Anlamsal kontrol bu kayıtlar için HİÇ çalışmadı; onları "anlamsal metadata
  # var" saymak, sorgular envanterlenemezken YÜKSEK kapsama raporlardı.
  expect_identical(sonuc$summary$queries_with_semantics, 0L)
  expect_identical(sonuc$summary$queries_needing_curation, 0L)
})

test_that("sema disi basarisizlik 'sema alinamadi' sayilmaz", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(name = "Idsiz", db_target = "primary", sql = "SELECT A FROM T"))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(A = "int"))

  expect_identical(sonuc$summary$failed_queries, 1L)
  # `missing_query_id` hiçbir describe/sample çağrısı yapılmadan üretilir.
  expect_identical(sonuc$summary$schema_failures, 0L)
})

test_that("devam onbelleginden gelen sorgu 'bu kosuda sema alinan' sayilmaz", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  onbellek <- list(q1 = list(
    ok = TRUE, schema = c(A = "integer"), source_types = c(A = "int"),
    unmapped = list(), unbounded = character(0), observations = list(),
    sample_info = list(mode = "describe", from_cache = TRUE),
    cache = list(mode = "describe", columns = c(A = "integer"))
  ))

  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) list(conn = .gen_fake_conn()),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) stop("beklenmiyordu"),
    sample_fn = function(conn, sql, n) stop("beklenmiyordu"),
    cache = onbellek
  )

  # Tamamen önbellekten çalışan bir koşu "hepsi describe/sample edildi" derse
  # BU KOŞUNUN ürettiği kanıtı abartır.
  expect_identical(sonuc$summary$described_or_sampled, 0L)
  expect_identical(sonuc$summary$from_cache, 1L)
})

test_that("yalnizca attention bulgusu olan sorgu insan raporunda GORUNUR", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q_geo", name = "Konum", db_target = "primary",
                   sql = "SELECT Konum FROM T", rls_columns = list()))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(Konum = "geography"))

  metin <- pkgh_render_text(sonuc$summary, sonuc$records, pkg_meta_config_summary(cfg))

  # `attention` tanımı gereği operatör eylemi gerektirir; yalnızca bloklayıcı
  # kayıtları listelemek bu sorguyu rapordan TAMAMEN gizlerdi.
  expect_true(grepl("q_geo", metin, fixed = TRUE))
  expect_true(grepl("unmapped_sql_type", metin, fixed = TRUE))
  expect_false(grepl("BULGU YOK", metin, fixed = TRUE))
})

test_that("bosluklu sorgu id raporda KANONIK bicimde tutulur", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = " q_bosluk ", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(A = "int"))

  # Rapor, denetlediği artefaktla AYNI kimliği göstermelidir.
  expect_identical(sonuc$records[[1]]$query_id, "q_bosluk")
  expect_named(sonuc$local_meta, "q_bosluk")
})

test_that("ayni kusur IKI KEZ bloklayici sayilmaz", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT SicilNo FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(SicilNo = "int"))
  kayit <- sonuc$records[[1]]

  # Eksik RLS sütunu hem `rls_column_missing` hem de doğrulayıcı yükü olarak
  # sayılsaydı, `blocking_count` tek kusuru İKİ gösterirdi.
  expect_identical(kayit$blocking_count, 1L)
  kodlar <- vapply(kayit$findings, function(f) f$code, character(1))
  expect_true("rls_column_missing" %in% kodlar)
  expect_true("startup_validation_detail" %in% kodlar)
  expect_false("startup_validation_would_fail" %in% kodlar)
})

test_that("ozel bulgu yokken dogrulayici yuku BLOKLAYICI kalir", {
  # Şema geçerli olsa da `pk_meta_validate_query()` bilinmeyen bir capability
  # kimliğini reddeder; buna karşılık gelen ÖZEL yapısal bulgu YOKTUR.
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT Saat FROM T", rls_columns = list()))
  kure <- list(q1 = list(column_meta = list(Saat = list(
    role = "measure", capability = "bilinmeyen.yetenek"
  ))))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(Saat = "decimal(18,2)"),
                    curated = kure, registry = list())

  kayit <- sonuc$records[[1]]
  expect_identical(kayit$status, "withheld")
  kodlar <- vapply(kayit$findings, function(f) f$code, character(1))
  expect_true("startup_validation_would_fail" %in% kodlar)
})

# ------------------------------------------------------------------------------
# 15) RLS bildirimi: bozuk biçim ve mükerrer sütun
# ------------------------------------------------------------------------------

test_that("BOZUK rls_columns beyani GUVENLIK bulgusudur", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT ProjeKodu FROM T", rls_columns = list(bilinmeyen_alan = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(ProjeKodu = "nvarchar(50)"))

  kayit <- sonuc$records[[1]]
  # Çalışma zamanı bu beyanı `fail_closed = TRUE` sayar; rapor GÜVENLİK
  # saymazsa `rls_mismatches` sıfır kalır ve DURDURUCU uyarı BASILMAZ.
  expect_identical(kayit$status, "withheld")
  expect_gt(kayit$security_finding_count, 0L)
  expect_identical(sonuc$summary$rls_mismatches, 1L)
})

test_that("MUKERRER RLS sutunu GUVENLIK bulgusudur", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT ProjeKodu, ProjeKodu FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    list(
      list(name = "ProjeKodu", system_type_name = "nvarchar(50)", max_length = 50),
      list(name = "ProjeKodu", system_type_name = "nvarchar(50)", max_length = 50)
    )
  })

  kayit <- sonuc$records[[1]]
  kodlar <- vapply(kayit$findings, function(f) f$code, character(1))
  expect_true("rls_column_duplicated" %in% kodlar)
  expect_gt(kayit$security_finding_count, 0L)
})

# ------------------------------------------------------------------------------
# 16) Tanımlayıcı sözleşmesi ve tip eşlemesi
# ------------------------------------------------------------------------------

test_that("ADSIZ sonuc sutunu sessizce DUSURULMEZ", {
  cikarim <- pkgs_schema_from_descriptor(list(
    list(name = "A", system_type_name = "int", max_length = 4),
    list(name = NULL, system_type_name = "int", max_length = 4)
  ))

  # Adsız bir sütunu düşürüp "kısmi" şema yazmak, başlangıç doğrulamasını GEÇEN
  # ama gerçek DBI sonucuyla UYUŞMAYAN metadata üretirdi.
  expect_false(isTRUE(cikarim$ok))
  expect_length(cikarim$invalid, 1L)
})

test_that("sutun adi KIRPILMAZ", {
  cikarim <- pkgs_schema_from_descriptor(list(
    list(name = " Kod ", system_type_name = "nvarchar(50)", max_length = 50)
  ))

  # Kırpılmış bir anahtar, bilinçli boşluklu bir takma adı İSKALAR.
  expect_identical(names(cikarim$schema), " Kod ")
})

test_that("adsiz sutun bildiren tanimlayici sorguyu GERI CEKER", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A, 1 FROM T", rls_columns = list()))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) {
    list(
      list(name = "A", system_type_name = "int", max_length = 4),
      list(name = "", system_type_name = "int", max_length = 4)
    )
  })

  expect_identical(sonuc$records[[1]]$status, "failed")
  expect_true(any(vapply(sonuc$records[[1]]$findings,
                         function(f) identical(f$code, "describe_invalid_schema"),
                         logical(1))))
  expect_length(sonuc$local_meta, 0L)
})

test_that("max_length = -1 sinirsiz sayilir; sql_variant sayilmaz", {
  cikarim <- pkgs_schema_from_descriptor(list(
    list(name = "Udt", system_type_name = "geometry", max_length = -1),
    list(name = "Karisik", system_type_name = "sql_variant", max_length = 8016),
    list(name = "Metin", system_type_name = "nvarchar", max_length = 100)
  ))

  # Uzamsal/CLR UDT tipleri adlarında `(max)` TAŞIMADAN `-1` bildirir.
  expect_true("Udt" %in% cikarim$unbounded)
  # `sql_variant` 8016 baytlık KANITLANMIŞ bir üst sınıra sahiptir.
  expect_false("Karisik" %in% cikarim$unbounded)
  expect_false("Metin" %in% cikarim$unbounded)
})

test_that("rowversion/timestamp IKILI eslenir, time hms olur", {
  cikarim <- pkgs_schema_from_descriptor(.gen_desc(
    Surum = "rowversion", Eski = "timestamp", Saat = "time"
  ))

  # `rowversion` (eski adı `timestamp`) 8 baytlık İKİLİ bir tiptir; TARİH DEĞİL.
  expect_identical(unname(cikarim$schema[["Surum"]]), "raw")
  expect_identical(unname(cikarim$schema[["Eski"]]), "raw")
  # `odbc` SQL TIME değerlerini `hms` döndürür; sample kipiyle eşlik şart.
  expect_identical(unname(cikarim$schema[["Saat"]]), "hms")
  expect_identical(.pk_meta_role_from_class("hms"), "dimension")
})

test_that("sinirsiz LOB bulgusu OPERATOR EYLEMI siddetindedir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT Aciklama FROM T", rls_columns = list()))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(Aciklama = "nvarchar(max)"))

  bulgu <- Filter(function(f) identical(f$code, "unbounded_lob_column"),
                  sonuc$records[[1]]$findings)
  expect_length(bulgu, 1L)
  # `info` bastırılır ve operatör kılavuzunun "eylem gerektirir" dediği bir
  # bulgu insan raporundan tamamen kaybolurdu.
  expect_identical(bulgu[[1]]$severity, "attention")
})

# ------------------------------------------------------------------------------
# 17) Örnekleme: yerli tipler, sıfır satır, row_cap
# ------------------------------------------------------------------------------

test_that("sample kipi NATIF tipleri korur ve yapisal bulgulari uretir", {
  cfg <- .gen_test_config("sample")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT Aciklama FROM T", rls_columns = list()))

  sonuc <- .gen_run(
    lib, cfg,
    describe_fn = function(conn, sql) .gen_desc(Aciklama = "nvarchar(max)"),
    sample_fn = function(conn, sql, n) data.frame(Aciklama = "x", stringsAsFactors = FALSE)
  )

  kodlar <- vapply(sonuc$records[[1]]$findings, function(f) f$code, character(1))
  # R sınıfı `nvarchar(max)` ile `nvarchar(200)` arasını AYIRT EDEMEZ; yapısal
  # bulgular yalnızca natif tanımlayıcıdan çıkar.
  expect_true("unbounded_lob_column" %in% kodlar)
  expect_true(isTRUE(sonuc$records[[1]]$sample$native_types_available))
})

test_that("SIFIR satirli ornek BILDIRILIR", {
  cfg <- .gen_test_config("sample")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))

  sonuc <- .gen_run(lib, cfg, sample_fn = function(conn, sql, n) {
    data.frame(A = integer(0))
  })

  kayit <- sonuc$records[[1]]
  expect_identical(kayit$status, "ok")
  expect_true(any(vapply(kayit$findings,
                         function(f) identical(f$code, "sample_zero_rows"), logical(1))))
})

test_that("onek row_cap asimini KANITLADIGINDA bildirilir", {
  cfg <- .gen_test_config("sample")
  cfg$sample_rows <- 10L
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list()))
  kure <- list(q1 = list(row_cap = 3L))

  sonuc <- .gen_run(lib, cfg, curated = kure,
                    sample_fn = function(conn, sql, n) data.frame(A = seq_len(5)))

  kayit <- sonuc$records[[1]]
  # 5 satır görmek, `row_cap = 3` için aşımı TEK BAŞINA kanıtlar; "bilinmiyor"
  # demek elde olan kanıtı gizlemek olurdu.
  expect_true(any(vapply(kayit$findings,
                         function(f) identical(f$code, "row_cap_exceeded"), logical(1))))
  expect_identical(kayit$sample$cardinality_claim, "row_cap_exceeded")
})

test_that("ornek satir siniri SUNUCU siniri DEGILDIR; guvenlik acik sample kapisidir", {
  cfg <- .gen_test_config("sample")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list(),
                   meta_sample_safe = TRUE))

  sonuc <- .gen_run(lib, cfg, sample_fn = function(conn, sql, n) data.frame(A = 1))

  # `dbSendQuery()` SELECT'i çalıştırır; `dbFetch(n=)` yalnızca aktarımı sınırlar.
  # Üretim sample yolundaki güvenlik iddiası, sorgunun açıkça incelenip
  # `meta_sample_safe = TRUE` kapısından geçirilmiş olmasıdır.
  expect_false(sonuc$records[[1]]$sample$server_bounded)
  expect_identical(sonuc$records[[1]]$sample$bound_kind, "explicit_safe_query_gate")
  expect_true(sonuc$records[[1]]$sample$explicitly_sample_safe)
})

test_that("blob NULL degerleri EKSIK sayilir", {
  df <- data.frame(id = 1:3)
  df$Veri <- list(as.raw(1), NULL, as.raw(1))

  gozlem <- pkgs_sample_observations(df)

  # `is.na(NULL)` liste ögesinde FALSE'tur: düz `is.na()` kullanan bir yol
  # "NULL görülmedi" der ve tekrar eden NULL'ları MÜKERRER DEĞER sayar.
  expect_true(gozlem$Veri$null_observed)
  expect_identical(gozlem$Veri$distinct_observed, 1L)
})

# ------------------------------------------------------------------------------
# 18) Yapılandırma çapraz doğrulaması ve varsayılan kip
# ------------------------------------------------------------------------------

test_that("belgelenen varsayilan kip 'describe'tir", {
  # Varsayılan `sample` olsaydı, ortam değişkenini ayarlamayı UNUTAN bir
  # `source(...)` çağrısı TÜM üretim sorgu kütüphanesini çalıştırırdı.
  expect_identical(PKG_META_DEFAULT_MODE, "describe")
})

test_that("ULASILAMAZ yuksek kardinalite esigi SAMPLE kipinde reddedilir", {
  withr::with_envvar(c(MERGEN_PK_META_MODE = "sample",
                       MERGEN_PK_META_SAMPLE_ROWS = "50",
                       MERGEN_PK_META_HIGH_CARD_MIN = "50"), {
    expect_error(pkg_meta_resolve_config(repo_root = tempdir()), "KUCUK olmalidir")
  })
})

test_that("DESCRIBE kipi ornekleme ayarlari yuzunden REDDEDILMEZ", {
  # `describe` kipi ne `sample_rows` ne de kardinalite esigini KULLANIR. Capraz
  # kontrol kosulsuz calistiginda, onceki bir ornekleme kosusundan kalan ayar
  # cifti, uretim sorgularini CALISTIRMAYAN guvenli envanteri de imkansiz
  # kilardi.
  withr::with_envvar(c(MERGEN_PK_META_MODE = "describe",
                       MERGEN_PK_META_SAMPLE_ROWS = "10",
                       MERGEN_PK_META_HIGH_CARD_MIN = "50"), {
    cfg <- pkg_meta_resolve_config(repo_root = tempdir())
    expect_identical(cfg$mode, "describe")
    expect_identical(cfg$sample_rows, 10L)
    expect_identical(cfg$high_cardinality_threshold, 50L)
  })
})

test_that("kosu kimligi ayni saniyede bile CARPISMAZ", {
  an <- as.POSIXct("2026-08-17 12:00:00", tz = "UTC")
  expect_false(identical(pkg_meta_run_id(an, pid = 111L),
                         pkg_meta_run_id(an, pid = 222L)))
  expect_true(grepl("^20260817-120000-", pkg_meta_run_id(an, pid = 111L)))
})

test_that("hedef dogrulamasi desteklenen kumeyi uygular", {
  expect_true(pkg_meta_validate_db_target("primary")$ok)
  expect_true(pkg_meta_validate_db_target("SECONDARY")$ok)
  expect_false(pkg_meta_validate_db_target("secondaryy")$ok)
  expect_false(pkg_meta_validate_db_target("")$ok)
  expect_identical(pkg_meta_validate_db_target("tertiary")$env_var, "DB_DSN_3")
})

# ------------------------------------------------------------------------------
# 19) Çıktı yazma: hedef kapısı, sayı biçimi, boş vektör, evreleme
# ------------------------------------------------------------------------------

test_that("cikti hedefi TEMEL ADA degil TAM YOLA gore dogrulanir", {
  gecici <- withr::local_tempdir()

  # Yalnızca `basename()` kontrol edilseydi, TAMAMEN başka bir dizindeki bir
  # hedef de kapıdan geçerdi.
  expect_error(
    pkgr_write_local_meta_file("x <- 1", file.path(gecici, "library_query_meta_local.R")),
    "dizininde degil"
  )

  hedef <- .gen_out_path(gecici)
  expect_silent(pkgr_write_local_meta_file("x <- 1\n", hedef))

  # Depo kökü verildiğinde tam yol BİREBİR karşılaştırılır.
  baska <- withr::local_tempdir()
  expect_error(
    pkgr_write_local_meta_file("x <- 1\n", hedef, repo_root = baska),
    "beklenen yol degil"
  )
})

test_that("ondalik ayraci YEREL AYARDAN bagimsizdir", {
  gecici <- withr::local_tempdir()
  hedef <- .gen_out_path(gecici)

  eski <- options(OutDec = ",")
  on.exit(options(eski), add = TRUE)

  pkgr_write_local_meta_file(
    pkgr_render_local_meta_file(list(q = list(oran = 0.125)), list(mode = "describe")),
    hedef
  )

  ortam <- new.env()
  source(hedef, local = ortam, encoding = "UTF-8")
  # `OutDec = ","` altında `0,125` yazılsaydı, virgül ARGÜMAN AYIRICI olarak
  # ayrışır ve dosya PARSE EDİLİR ama değer/yapı SESSİZCE değişirdi.
  expect_equal(ortam$pk_query_meta_local$q$oran, 0.125)
})

test_that("SIFIR uzunluklu atomik vektorler turuyle geri okunur", {
  gecici <- withr::local_tempdir()
  hedef <- .gen_out_path(gecici)

  girdi <- list(q = list(bos_metin = character(0), bos_tam = integer(0),
                         bos_mantik = logical(0)))
  pkgr_write_local_meta_file(
    pkgr_render_local_meta_file(girdi, list(mode = "describe")), hedef
  )

  ortam <- new.env()
  source(hedef, local = ortam, encoding = "UTF-8")
  geri <- ortam$pk_query_meta_local$q

  # `c()` R'de NULL'dur: alan TÜRÜNÜ ve VARLIĞINI kaybederdi.
  expect_identical(geri$bos_metin, character(0))
  expect_identical(geri$bos_tam, integer(0))
  expect_identical(geri$bos_mantik, logical(0))
})

test_that("HAZIRLAMA canli dosyaya DOKUNMAZ; YAYIMLAMA tasir", {
  gecici <- withr::local_tempdir()
  hedef <- .gen_out_path(gecici)
  writeLines("pk_query_meta_local <- list(eski = TRUE)", hedef)

  hazir <- pkgr_stage_local_meta_file(
    pkgr_render_local_meta_file(list(yeni = list(tier = 1L)), list(mode = "describe")),
    hedef
  )

  # Denetim artefaktları yazılmadan üretimden türetilmiş metadata devreye
  # ALINMAMALIDIR; bu yüzden hazırlama ve yayımlama AYRI adımlardır.
  expect_true(file.exists(hazir))
  expect_true(grepl("eski", paste(readLines(hedef), collapse = " "), fixed = TRUE))

  pkgr_publish_staged_file(hazir, hedef)
  expect_true(grepl("yeni", paste(readLines(hedef), collapse = " "), fixed = TRUE))
  expect_false(file.exists(hazir))
})

# ------------------------------------------------------------------------------
# 20) Katman birleştirme, koşu kilidi ve katalog teşhisi
# ------------------------------------------------------------------------------

test_that("KISMI envanter onceki gecerli metadata'yi SILMEZ", {
  onceki <- list(
    q_ok = list(result_schema = c(A = "integer")),
    q_fail = list(result_schema = c(B = "integer")),
    q_withheld = list(result_schema = c(C = "integer")),
    q_kalkti = list(result_schema = c(D = "integer"))
  )
  uretilen <- list(q_ok = list(result_schema = c(A = "numeric")))
  kayitlar <- list(
    list(query_id = "q_ok", status = "ok"),
    list(query_id = "q_fail", status = "failed"),
    list(query_id = "q_withheld", status = "withheld")
  )

  birlesme <- pkgc_merge_local_layers(onceki, uretilen, kayitlar)

  # Geçici bir sürücü hatası, sağlam metadata'yı Tier-0'a DÜŞÜRMEMELİDİR.
  expect_identical(unname(birlesme$meta$q_fail$result_schema[["B"]]), "integer")
  expect_identical(birlesme$kept, "q_fail")
  # `ok` girdisi YENİSİYLE değişir.
  expect_identical(unname(birlesme$meta$q_ok$result_schema[["A"]]), "numeric")
  # Bloklayıcı bulgusu olan sorgunun ESKİ şeması bayat bir sözleşme bırakırdı.
  expect_null(birlesme$meta$q_withheld)
  expect_identical(birlesme$withheld_removed, "q_withheld")
  # Kütüphaneden kalkmış kimlik düşürülür (başlangıç kapısı bunu HATA sayar).
  expect_null(birlesme$meta$q_kalkti)
  expect_identical(birlesme$dropped, "q_kalkti")
})

test_that("kosu kilidi es zamanli ikinci kosuyu REDDEDER", {
  gecici <- withr::local_tempdir()
  kilit_yolu <- file.path(gecici, "generator.lock")

  ilk <- pkgc_acquire_run_lock(kilit_yolu)
  expect_true(ilk$ok)

  # İki koşu aynı çıktı dosyasını SON YAZAN KAZANIR biçimde ezerdi.
  ikinci <- pkgc_acquire_run_lock(kilit_yolu)
  expect_false(ikinci$ok)
  expect_true(grepl("uretici kosusu", ikinci$detail, fixed = TRUE))

  pkgc_release_run_lock(ilk)
  ucuncu <- pkgc_acquire_run_lock(kilit_yolu)
  expect_true(ucuncu$ok)
  pkgc_release_run_lock(ucuncu)
})

test_that("BAYAT kilit kirilir", {
  gecici <- withr::local_tempdir()
  kilit_yolu <- file.path(gecici, "generator.lock")
  dir.create(kilit_yolu)

  sonuc <- pkgc_acquire_run_lock(kilit_yolu, stale_sec = -1)
  expect_true(sonuc$ok)
  pkgc_release_run_lock(sonuc)
})

test_that("katalog teshisi mukerrer/eksik kimligi SEMA OLMADAN bulur", {
  kutuphane <- list(
    list(id = "q1", name = "A", sql = "SELECT 1"),
    list(id = "q1", name = "B", sql = "SELECT 2"),
    list(id = "q3", name = "C"),
    list(name = "Idsiz", sql = "SELECT 4"),
    "bozuk"
  )

  kayitlar <- pkgc_catalog_findings(kutuphane)
  kodlar <- unlist(lapply(kayitlar, function(r) {
    vapply(r$findings, function(f) f$code, character(1))
  }))

  # Bootstrap bu kusurlarda DURDUĞU için, sağlık raporunun vaat ettiği
  # mükerrer/eksik kimlik kapsaması aksi hâlde ASLA üretilemezdi.
  expect_true("duplicate_query_id" %in% kodlar)
  expect_true("missing_sql" %in% kodlar)
  expect_true("missing_query_id" %in% kodlar)
  expect_true("malformed_library_entry" %in% kodlar)
})

test_that("BOZUK kutuphane ogesi envanterde sessizce DUSURULMEZ", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q1", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    "bozuk"
  )

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(A = "int"))

  # Sessizce düşürmek `total_queries` sayısını gerçek kütüphaneden KÜÇÜK
  # gösterir ve denetim bu kusur sınıfını göremez.
  expect_identical(sonuc$summary$total_queries, 2L)
  expect_identical(sonuc$records[[2]]$status, "failed")
})

# ------------------------------------------------------------------------------
# 21) query nesnesindeki ESKİ sütun beyanları
# ------------------------------------------------------------------------------

test_that("query$date_columns / pre_aggregated_columns semaya karsi denetlenir", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT A FROM T", rls_columns = list(),
                   date_columns = c("YokTarih"),
                   pre_aggregated_columns = c("YokToplam")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(A = "int"))

  kodlar <- vapply(sonuc$records[[1]]$findings, function(f) f$code, character(1))
  # Runtime bunları SESSİZCE atlar / bayat listeyi istatistik özetine geçirir;
  # rapor sorguyu DAHİL derken analiz sözleşmesi bozuk kalırdı.
  expect_true("query_date_columns_missing_in_schema" %in% kodlar)
  expect_true("query_pre_aggregated_columns_missing_in_schema" %in% kodlar)
  # Runtime düşmediği için bunlar BLOKLAYICI değildir.
  expect_identical(sonuc$records[[1]]$status, "ok")
})

test_that("date_columns beyani runtime-etkin semayi DATE yapar ve sorguyu geri CEKMEZ", {
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT Tarih FROM T", rls_columns = list(),
                   date_columns = c("Tarih")))
  kure <- list(q1 = list(column_meta = list(Tarih = list(role = "date"))))

  sonuc <- .gen_run(lib, cfg,
                    describe_fn = function(conn, sql) .gen_desc(Tarih = "nvarchar(20)"),
                    curated = kure)

  kayit <- sonuc$records[[1]]
  kodlar <- vapply(kayit$findings, function(f) f$code, character(1))

  # Runtime `convert_date_columns()` çağrısını metadata kapısından ÖNCE yapar.
  # Üretici de aynı etkin şemayı kullanmalı; aksi halde çalışan bir varchar tarih
  # sorgusunu yanlışlıkla geri çeker ve üretim metadata'sını yazamaz.
  expect_false("role_type_mismatch" %in% kodlar)
  expect_false("role_type_mismatch_declared_date" %in% kodlar)
  expect_identical(kayit$status, "ok")
  expect_identical(kayit$blocking_count, 0L)
  expect_false("startup_validation_would_fail" %in% kodlar)
  expect_identical(unname(sonuc$local_meta$q1$result_schema[["Tarih"]]), "Date")
})

# ------------------------------------------------------------------------------
# 22) Alias bindirmesi ve salt-okunur kapısı
# ------------------------------------------------------------------------------

test_that("alias bindirmesi SORGU BAZINDA dogrulanir", {
  cfg <- .gen_test_config("describe")
  lib <- list(
    list(id = "q_iyi", name = "A", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list()),
    list(id = "q_alias", name = "B", db_target = "primary", sql = "SELECT A FROM T",
         rls_columns = list())
  )
  # Beyan EDİLMEMİŞ bir sütuna alias bindirmesi.
  bindirme <- list(q_alias = list(Yok = list(deger = "hedef")))

  sonuc <- pkg_meta_run_inventory(
    query_library = lib, config = cfg,
    connect_fn = function(target) list(conn = .gen_fake_conn()),
    release_fn = function(handle) invisible(NULL),
    describe_fn = function(conn, sql) .gen_desc(A = "int"),
    sample_fn = function(conn, sql, n) stop("beklenmiyordu"),
    alias_overlay = bindirme
  )

  # Bindirme yalnızca BÜTÜN KÜTÜPHANE kapısında uygulansaydı, tek bir bozuk
  # alias TÜM üretilen katmanın yazılmamasına yol açardı.
  expect_identical(sonuc$records[[1]]$status, "ok")
  expect_identical(sonuc$records[[2]]$status, "withheld")
  expect_setequal(names(sonuc$local_meta), "q_iyi")
})

test_that("sequence ilerleten SELECT salt-okunur SAYILMAZ", {
  # `NEXT VALUE FOR` SQL Server'da sequence değerini AYIRIR/İLERLETİR: değer
  # hiçbir yere yazılmasa bile ÜRETİM DURUMU DEĞİŞİR.
  kapi <- pk_sql_classify_readonly("SELECT NEXT VALUE FOR dbo.SiparisNo AS N")
  expect_false(kapi$allowed)
  expect_identical(kapi$reason, "sequence_mutation")

  cfg <- .gen_test_config("sample")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT NEXT VALUE FOR dbo.SiparisNo AS N",
                   rls_columns = list()))

  calistirildi <- FALSE
  sonuc <- .gen_run(lib, cfg, sample_fn = function(conn, sql, n) {
    calistirildi <<- TRUE
    data.frame(N = 1)
  })

  expect_false(calistirildi)
  expect_identical(sonuc$records[[1]]$status, "skipped")
})

# ------------------------------------------------------------------------------
# 23) JSON tür kararlılığı
# ------------------------------------------------------------------------------

test_that("health.json koleksiyon alanlari KARDINALITEDEN bagimsiz dizidir", {
  skip_if_not_installed("jsonlite")

  gecici <- withr::local_tempdir()
  cfg <- .gen_test_config("describe")
  lib <- list(list(id = "q1", name = "S", db_target = "primary",
                   sql = "SELECT SicilNo FROM T",
                   rls_columns = list(proje_kodu_col = "ProjeKodu")))

  sonuc <- .gen_run(lib, cfg, describe_fn = function(conn, sql) .gen_desc(SicilNo = "int"))
  yollar <- pkgh_write_artifacts(
    list(summary = sonuc$summary, queries = sonuc$records),
    gecici, sonuc$records, sonuc$summary, pkg_meta_config_summary(cfg)
  )

  ham <- paste(readLines(yollar$json, warn = FALSE), collapse = "\n")
  geri <- jsonlite::fromJSON(ham, simplifyVector = FALSE)

  rls <- Filter(function(f) identical(f$code, "rls_column_missing"),
                geri$queries[[1]]$findings)
  # Tek ögeli `columns` bir DİZE olsaydı, makine okuyucusu her alan için
  # skaler-ya-da-dizi özel durumu yazmak zorunda kalır ve sorgu iki eksik
  # sütuna geçtiğinde KIRILIRDI.
  expect_true(is.list(rls[[1]]$columns))
  expect_length(rls[[1]]$columns, 1L)
})
