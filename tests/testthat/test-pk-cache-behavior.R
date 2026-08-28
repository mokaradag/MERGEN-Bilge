# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-cache-behavior.R
# Açıklama: Faz 6 (§5.10) — BOYUT SINIRLI LRU sonuç önbelleğinin davranış
#           testleri. Tamamen çevrimdışı: DB, LLM, ağ, tarayıcı GEREKMEZ.
#
# Kanıtlanan sözleşmeler:
#   - Anahtar YETKİ KAPSAMINI içerir; farklı RLS kapsamları önbelleği PAYLAŞMAZ.
#   - LRU sırası gerçek erişime göredir; giriş sayısı VE bayt bütçesi birlikte
#     tahliye tetikler.
#   - Tek giriş tavanını aşan sonuç HİÇ alınmaz; diğer her şeyi tahliye ederek
#     kendine yer AÇMAZ.
#   - Aynı anahtarın güncellenmesi bayt muhasebesini SÜRÜKLEMEZ.
#   - TTL dolan giriş ıska sayılır ve baytı muhasebeden düşülür.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  # SIZINTI TEMİZLENİR: `local = globalenv()` bu yardımcıları süit boyunca
  # KALICI olarak global ortama kurar; sonraki dosyalar
  # `exists(..., inherits = TRUE)` ile yoklayıp kendi fail-closed dallarını
  # ATLAYABİLİR ve dosya tek başına geçerken paket koşumunda FARKLI davranır.
  # Kardeş dosya `test-pk-result-size-behavior.R` aynı korumayı uygular.
  onceki_adlar <- ls(globalenv(), all.names = TRUE)

  source(file.path(repo_root, "R", "helpers_pk_config.R"),
         encoding = "UTF-8", local = globalenv())
  # Anahtar üretimi (yetki kapsamı imzası) AYRI dosyadadır ve depodan ÖNCE gelir.
  source(file.path(repo_root, "R", "helpers_pk_cache_key.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_pk_cache.R"),
         encoding = "UTF-8", local = globalenv())

  eklenen <- setdiff(ls(globalenv(), all.names = TRUE), onceki_adlar)
  if (length(eklenen) && requireNamespace("withr", quietly = TRUE)) {
    withr::defer(
      suppressWarnings(try(rm(list = eklenen, envir = globalenv()), silent = TRUE)),
      envir = testthat::teardown_env()
    )
  }
})

# Önbellek limitlerini AYARLAYAN yardımcı.
#
# ORTAM DEĞİŞKENİ DE İZOLE EDİLİR. `pk_config_resolve()` önceliği bilinçli
# olarak `query_meta -> ORTAM -> options() -> varsayılan` şeklindedir: ortam,
# operatörün kanalıdır ve `options()`'ı EZER. `.Renviron.example` bu dört
# anahtarı (`MERGEN_PK_CACHE_MAX_ENTRIES/MAX_MB/MAX_ENTRY_MB/TTL_SEC`) ayarlar;
# üretim `.Renviron`'ı kurulu bir Windows VM'de yalnızca `options()` yazan bir
# test SESSİZCE ortamın değerlerini ölçerdi. Sınırlar o zaman hiç uygulanmaz
# görünür (TTL dolmaz, tahliye olmaz, tek giriş tavanı aşılır) ve sözleşme
# üretim kodu doğru olduğu hâlde başarısız olur.
#
# Bu yüzden her iki kanal da testin değerine sabitlenir ve çıkışta ÖNCEKİ
# durumlarına geri alınır (bkz. `pk_select_with_env()` aynı desendir).
.PK_CACHE_ENV_KEYS <- c(
  "MERGEN_PK_CACHE_MAX_ENTRIES", "MERGEN_PK_CACHE_MAX_MB",
  "MERGEN_PK_CACHE_MAX_ENTRY_MB", "MERGEN_PK_CACHE_TTL_SEC"
)

.pk_cache_with_limits <- function(entries = 50L, mb = 512L, entry_mb = 128L,
                                  ttl = 300L, code) {
  eski <- list(
    mergen.pk.cache_max_entries = getOption("mergen.pk.cache_max_entries", NULL),
    mergen.pk.cache_max_mb = getOption("mergen.pk.cache_max_mb", NULL),
    mergen.pk.cache_max_entry_mb = getOption("mergen.pk.cache_max_entry_mb", NULL),
    mergen.pk.cache_ttl_sec = getOption("mergen.pk.cache_ttl_sec", NULL)
  )
  eski_env <- Sys.getenv(.PK_CACHE_ENV_KEYS, unset = NA_character_, names = TRUE)

  on.exit({
    for (nm in names(eski)) {
      do.call(options, stats::setNames(list(eski[[nm]]), nm))
    }
    for (ad in names(eski_env)) {
      if (is.na(eski_env[[ad]])) {
        Sys.unsetenv(ad)
      } else {
        do.call(Sys.setenv, stats::setNames(list(eski_env[[ad]]), ad))
      }
    }
    pk_cache_reset()
  }, add = TRUE)

  do.call(Sys.setenv, stats::setNames(
    as.list(as.character(c(entries, mb, entry_mb, ttl))),
    .PK_CACHE_ENV_KEYS
  ))
  options(
    mergen.pk.cache_max_entries = entries,
    mergen.pk.cache_max_mb = mb,
    mergen.pk.cache_max_entry_mb = entry_mb,
    mergen.pk.cache_ttl_sec = ttl
  )
  pk_cache_reset()
  force(code)
}

test_that("anahtar sonucu etkileyen HER boyutu içerir", {
  a <- pk_cache_key("q001", "rls_a", "f1")
  b <- pk_cache_key("q001", "rls_b", "f1")
  c <- pk_cache_key("q001", "rls_a", "f2")
  d <- pk_cache_key("q002", "rls_a", "f1")
  e <- pk_cache_key("q001", "rls_a", "f1", query_version = "v2")

  expect_false(identical(a, b))  # yetki kapsamı
  expect_false(identical(a, c))  # filtre imzası
  expect_false(identical(a, d))  # sorgu kimliği
  expect_false(identical(a, e))  # sorgu sürümü (deterministik geçersizleştirme)

  # Yetki imzası olmayan çağrı bile ANONİM bir kapsam ayrımı taşır; sessizce
  # "kapsamsız" bir ortak kovaya düşmez.
  expect_true(grepl("__no_scope__", pk_cache_key("q001", NULL, "f1"), fixed = TRUE))
})

test_that("extra alanları sıradan BAĞIMSIZ anahtar üretir", {
  a <- pk_cache_key("q", "r", "f", extra = list(z = 1, a = 2))
  b <- pk_cache_key("q", "r", "f", extra = list(a = 2, z = 1))
  expect_identical(a, b)
})

test_that("farklı YETKİ KAPSAMLARI önbelleği paylaşmaz", {
  .pk_cache_with_limits(code = {
    rls_1 <- list(authorized = TRUE, username = "ali", projects = c("P1", "P2"))
    rls_2 <- list(authorized = TRUE, username = "ali", projects = c("P1"))
    rls_3 <- list(authorized = TRUE, username = "veli", projects = c("P1", "P2"))

    s1 <- pk_cache_rls_signature(rls_1)
    s2 <- pk_cache_rls_signature(rls_2)
    s3 <- pk_cache_rls_signature(rls_3)

    # Aynı kullanıcının yetkisi DEĞİŞİRSE imza da değişir.
    expect_false(identical(s1, s2))
    expect_false(identical(s1, s3))
    expect_identical(s1, pk_cache_rls_signature(rls_1))

    k1 <- pk_cache_key("q001", s1, "f1")
    k3 <- pk_cache_key("q001", s3, "f1")

    pk_cache_put(k1, data.frame(x = 1:3))
    expect_true(pk_cache_get(k1)$hit)
    # Başka kullanıcının kapsamı ISKA olmalıdır: sızıntı KABUL EDİLEMEZ.
    expect_false(pk_cache_get(k3)$hit)
  })
})

test_that("yetkisiz kapsam ayrı bir imza taşır", {
  expect_equal(pk_cache_rls_signature(list(authorized = FALSE)), "__unauthorized__")
  expect_equal(pk_cache_rls_signature(NULL), "__no_scope__")
})

test_that("hit/miss ve TTL dolması doğru raporlanır", {
  .pk_cache_with_limits(ttl = 60L, code = {
    simdi <- as.POSIXct("2026-08-09 10:00:00", tz = "UTC")
    pk_cache_put("k", data.frame(x = 1), now = simdi)

    expect_true(pk_cache_get("k", now = simdi + 30)$hit)

    dolan <- pk_cache_get("k", now = simdi + 61)
    expect_false(dolan$hit)
    expect_equal(dolan$reason, "expired")

    # Dolan girişin baytı muhasebeden DÜŞÜLMÜŞ olmalıdır.
    expect_equal(pk_cache_stats()$entries, 0L)
    expect_equal(pk_cache_stats()$total_bytes, 0)
    expect_equal(pk_cache_stats()$expired, 1L)
  })
})

test_that("LRU sırası gerçek erişime göredir", {
  .pk_cache_with_limits(entries = 3L, code = {
    pk_cache_put("a", 1L)
    pk_cache_put("b", 2L)
    pk_cache_put("c", 3L)
    expect_equal(pk_cache_lru_order(), c("a", "b", "c"))

    # "a" okunursa en yeni hâle gelir.
    pk_cache_get("a")
    expect_equal(pk_cache_lru_order(), c("b", "c", "a"))
  })
})

test_that("giriş sayısı tavanı en ESKİ girişi tahliye eder", {
  .pk_cache_with_limits(entries = 3L, code = {
    pk_cache_put("a", 1L); pk_cache_put("b", 2L); pk_cache_put("c", 3L)
    pk_cache_get("a")  # "b" artık en eski

    pk_cache_put("d", 4L)

    expect_equal(pk_cache_stats()$entries, 3L)
    expect_false(pk_cache_get("b")$hit)
    expect_true(pk_cache_get("a")$hit)
    expect_true(pk_cache_get("c")$hit)
    expect_true(pk_cache_get("d")$hit)
  })
})

test_that("bayt bütçesi de tahliye tetikler ve muhasebe SÜRÜKLENMEZ", {
  # 1 MB toplam bütçe, 1 MB tek giriş tavanı: birkaç yüz KB'lik girişler
  # bütçeyi zorlar.
  .pk_cache_with_limits(entries = 100L, mb = 1L, entry_mb = 1L, code = {
    buyuk <- function() as.numeric(seq_len(40000))  # ~320 KB

    pk_cache_put("a", buyuk())
    pk_cache_put("b", buyuk())
    pk_cache_put("c", buyuk())
    onceki <- pk_cache_stats()

    pk_cache_put("d", buyuk())
    sonraki <- pk_cache_stats()

    expect_true(sonraki$evicted >= 1L)
    expect_lte(sonraki$total_bytes, 1 * 1024 * 1024)
    expect_true(onceki$entries >= 1L)

    # DEĞİŞMEZ GERÇEKTEN ÖLÇÜLÜR: toplam bayt, KALAN girişlerin baytlarının
    # TOPLAMINA eşit olmalıdır. Eski iddialar yalnızca "pozitif ve tavanın
    # altında" diyordu; yanlış bayt düşen bir tahliye yolu de geçerdi.
    kalan_bayt <- sum(vapply(
      .pk_cache_store$entries,
      function(g) suppressWarnings(as.numeric(g$bytes %||% 0)[1]),
      numeric(1)
    ))
    expect_equal(sonraki$total_bytes, kalan_bayt)
    expect_true(kalan_bayt > 0)
  })
})

test_that("TEK giriş tavanını aşan sonuç HİÇ önbelleğe alınmaz", {
  .pk_cache_with_limits(entries = 10L, mb = 512L, entry_mb = 1L, code = {
    pk_cache_put("kucuk_1", as.numeric(seq_len(1000)))
    pk_cache_put("kucuk_2", as.numeric(seq_len(1000)))
    onceki <- pk_cache_stats()

    kocaman <- as.numeric(seq_len(400000))  # ~3.2 MB > 1 MB tavan
    sonuc <- pk_cache_put("kocaman", kocaman)

    expect_false(sonuc$stored)
    expect_equal(sonuc$reason, "entry_too_large")
    expect_false(pk_cache_get("kocaman")$hit)

    # KRİTİK: diğer her şeyi tahliye ederek kendine yer AÇMAMIŞ olmalıdır.
    expect_equal(pk_cache_stats()$entries, onceki$entries)
    expect_true(pk_cache_get("kucuk_1")$hit)
    expect_true(pk_cache_get("kucuk_2")$hit)
    expect_equal(pk_cache_stats()$rejected_oversize, 1L)
  })
})

test_that("aynı anahtarın güncellenmesi bayt muhasebesini sürüklemez", {
  .pk_cache_with_limits(code = {
    pk_cache_put("k", as.numeric(seq_len(20000)))
    ilk <- pk_cache_stats()$total_bytes

    pk_cache_put("k", as.numeric(seq_len(20000)))
    ikinci <- pk_cache_stats()$total_bytes

    expect_equal(pk_cache_stats()$entries, 1L)
    expect_equal(ikinci, ilk)

    pk_cache_put("k", 1L)
    expect_true(pk_cache_stats()$total_bytes < ilk)
    expect_equal(pk_cache_stats()$entries, 1L)
  })
})

test_that("önbellek kapatıldığında yazma yapılmaz", {
  .pk_cache_with_limits(entries = 0L, code = {
    sonuc <- pk_cache_put("k", 1L)
    expect_false(sonuc$stored)
    expect_equal(sonuc$reason, "cache_disabled")
    expect_equal(pk_cache_stats()$entries, 0L)
  })

  .pk_cache_with_limits(mb = 0L, code = {
    sonuc <- pk_cache_put("k", 1L)
    expect_false(sonuc$stored)
    expect_equal(sonuc$reason, "cache_disabled")
  })
})

test_that("geçersizleştirme baytı düşürür", {
  .pk_cache_with_limits(code = {
    pk_cache_put("k", as.numeric(seq_len(5000)))
    expect_true(pk_cache_stats()$total_bytes > 0)

    expect_true(pk_cache_invalidate("k"))
    expect_equal(pk_cache_stats()$entries, 0L)
    expect_equal(pk_cache_stats()$total_bytes, 0)
    expect_false(pk_cache_invalidate("yok"))
  })
})

test_that("durum özeti SIR veya anahtar METNİ dışa vermez", {
  .pk_cache_with_limits(code = {
    pk_cache_put(pk_cache_key("q", "gizli_kapsam_imzasi", "f"), 1L)
    ozet <- pk_cache_stats()

    duz <- paste(unlist(lapply(ozet, as.character)), collapse = " ")
    expect_false(grepl("gizli_kapsam_imzasi", duz, fixed = TRUE))
    expect_true(all(c("entries", "total_bytes", "hit", "miss") %in% names(ozet)))
  })
})


# HAM SQL SONUCU ANALİZ KİPİNE BAĞLI DEĞİLDİR: derin analiz ile normal analiz
# aynı sorgu/RLS/SQL üçlüsünde AYNI ham çerçeveyi paylaşabilmelidir. `engine`
# anahtara girdiğinde iki yol birbirinin girdisine ASLA çarpmıyordu.
test_that("ham SQL önbellek anahtarı analiz kipinden BAĞIMSIZDIR", {
  skip_if_not(requireNamespace("digest", quietly = TRUE) ||
              requireNamespace("openssl", quietly = TRUE))

  sorgu <- list(id = "q001", db_target = "primary")
  rls <- list(authorized = TRUE, username = "tester", role = "USER",
              allowed_projects = c("P-1"), allowed_depts = NULL)
  sql <- "SELECT 1 AS a"

  derin <- pk_query_result_cache_key(sorgu, rls, sql, engine = "deep")
  v1 <- pk_query_result_cache_key(sorgu, rls, sql, engine = "v1")
  v2 <- pk_query_result_cache_key(sorgu, rls, sql, engine = "v2")

  expect_true(nzchar(derin))
  expect_identical(derin, v1)
  expect_identical(derin, v2)
})

# ---------------------------------------------------------------------------
# SAYISAL OLMAYAN LİMİT: bütçeyi kapatmak yerine KAPALI BAŞARISIZ olur
# ---------------------------------------------------------------------------

test_that("sayisal olmayan limit TUM butceleri devre disi birakmaz", {
  # GERİLEME: `coz()` yalnızca çözümleyici HATA fırlattığında yedeğe düşüyordu.
  # `MERGEN_PK_CACHE_MAX_MB=abc` gibi bir değer `as.numeric()` ile sessizce `NA`
  # üretiyor; `NA` `is.finite()` denetimlerini geçemediği için sayı, bayt ve
  # giriş-başına tavanların HEPSİ atlanıyor ve depo SINIRSIZ büyüyordu.
  .pk_cache_with_limits(entries = "abc", mb = "abc", entry_mb = "abc", ttl = "abc", code = {
    limitler <- .pk_cache_limits()
    for (alan in c("max_entries", "max_bytes", "max_entry_bytes", "ttl_sec")) {
      expect_true(is.finite(limitler[[alan]]), info = alan)
      expect_gt(limitler[[alan]], 0)
    }
  })
})

test_that("DSN parmak izi yalnizca `digest` kuruluyken de CARPISMAZ", {
  skip_if_not_installed("digest")
  # `withr` bu depoda OPSİYONEL bir test bağımlılığıdır; koruma olmadan
  # `withr::with_envvar()` hata veriyor ve `stop_on_failure = TRUE` ile TÜM
  # paket düşüyordu (atlanması gereken tek DSN testi yerine).
  skip_if_not_installed("withr")

  # GERİLEME: yalnızca `openssl` kabul ediliyordu. `digest` kurulu bir
  # dağıtımda parmak izi `len<n>`e düşüyor; AYNI KARAKTER SAYISINA sahip bir
  # DSN'e failover sonrası parmak izi DEĞİŞMİYOR ve sıcak giriş ÖNCEKİ
  # veritabanının satırlarını sunuyordu.
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  env$requireNamespace <- function(package, ..., quietly = FALSE) {
    if (identical(package, "openssl")) return(FALSE)
    base::requireNamespace(package, ..., quietly = quietly)
  }
  source(file.path(kok, "R", "helpers_pk_cache_key.R"), encoding = "UTF-8", local = env)
  source(file.path(kok, "R", "helpers_pk_cache.R"), encoding = "UTF-8", local = env)

  imza <- function(dsn) {
    withr::with_envvar(list(DB_DSN = dsn), env$.pk_cache_db_fingerprint("primary"))
  }

  a <- imza("SUNUCU_A")
  b <- imza("SUNUCU_B")   # AYNI karakter sayisi, FARKLI hedef

  expect_true(nzchar(a) && nzchar(b))
  expect_false(identical(a, b))
  expect_false(grepl("^len", a))
})
