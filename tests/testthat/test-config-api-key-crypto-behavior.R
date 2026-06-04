# ==============================================================================
# Dosya Yolu: tests/testthat/test-config-api-key-crypto-behavior.R
# Açıklama: R/config_api.R kullanıcı API anahtarı kripto/dosya yardımcılarının
#           davranışsal testleri. .hash_key_hex determinizmi, .enc_key/.dec_key
#           gidiş-dönüşü, save/load/verify dosya akışı ve hatalı anahtar reddi
#           doğrulanır. Gerçek anahtar/secret kullanılmaz; sahte değerler verilir.
# ==============================================================================

testthat::local_edition(3)

# config_api.R kaynak anında getwd()/api_keys oluşturur; repoyu kirletmemek için
# geçici dizinde source edilir ve sonra API_KEYS_DIR test klasörüne yönlendirilir.
.api_env <- new.env(parent = globalenv())
.api_master <- "test-master-key-0123456789"
.api_keys_tmp <- file.path(tempdir(), paste0("apikeys_test_", as.integer(stats::runif(1, 1, 1e7))))
dir.create(.api_keys_tmp, showWarnings = FALSE, recursive = TRUE)

local({
  Sys.setenv(AI_KEYS_MASTER = .api_master)
  # Repo kökü mutlak yol olarak with_dir öncesinde çözülür (with_dir içinde
  # göreli arama başarısız olur).
  kok <- normalizePath(resolve_repo_root_for_tests(), winslash = "/", mustWork = TRUE)
  source(file.path(kok, "R", "utils_atomic_write.R"), encoding = "UTF-8", local = .api_env)
  src_tmp <- file.path(tempdir(), paste0("apisrc_", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(src_tmp, showWarnings = FALSE, recursive = TRUE)
  withr::with_dir(src_tmp, {
    source(file.path(kok, "R", "config_api.R"), encoding = "UTF-8", local = .api_env)
  })
})

# Tüm dosya işlemleri izole geçici klasöre yönlendirilir.
.api_env$API_KEYS_DIR <- .api_keys_tmp

# -----------------------------------------------------------------------------
# .api_user_file
# -----------------------------------------------------------------------------

test_that(".api_user_file kullanıcı adına göre <kullanıcı>_api_key yolu üretir", {
  yol <- .api_env$.api_user_file("aliveli")
  expect_true(grepl("aliveli_api_key$", yol))
  expect_identical(dirname(yol), .api_keys_tmp)
})

# -----------------------------------------------------------------------------
# .hash_key_hex
# -----------------------------------------------------------------------------

test_that(".hash_key_hex aynı tuz+anahtar için deterministik, farklı anahtar için farklı üretir", {
  salt <- as.raw(1:16)
  h1 <- .api_env$.hash_key_hex("fake-key-abc", salt)
  h2 <- .api_env$.hash_key_hex("fake-key-abc", salt)
  h3 <- .api_env$.hash_key_hex("fake-key-xyz", salt)

  expect_identical(h1, h2)               # determinizm
  expect_false(identical(h1, h3))        # farklı anahtar -> farklı hash
  expect_match(h1, "^[0-9a-f]+$")        # hex string
  expect_equal(nchar(h1), 64L)           # SHA256 -> 64 hex karakter
})

test_that(".hash_key_hex farklı tuz için farklı hash üretir", {
  h_salt1 <- .api_env$.hash_key_hex("fake-key", as.raw(rep(1, 16)))
  h_salt2 <- .api_env$.hash_key_hex("fake-key", as.raw(rep(2, 16)))
  expect_false(identical(h_salt1, h_salt2))
})

# -----------------------------------------------------------------------------
# .enc_key / .dec_key gidiş-dönüş
# -----------------------------------------------------------------------------

test_that(".enc_key/.dec_key düz metni gidiş-dönüşte korur ve desteklenen alg kullanır", {
  duz <- "super-secret-fake-value-42"
  enc <- .api_env$.enc_key(duz, .api_master)

  expect_true(enc$alg %in% c("aes-256-gcm", "aes-256-cbc"))
  expect_true(nzchar(enc$iv_b64) && nzchar(enc$cipher_b64))
  # Şifreli metin düz metni içermez (base64 sızıntısı yok).
  expect_false(grepl(duz, enc$cipher_b64, fixed = TRUE))

  dec <- .api_env$.dec_key(enc, .api_master)
  expect_identical(dec, duz)
})

test_that(".enc_key her çağrıda farklı şifreli metin üretir ama aynı düz metne çözülür", {
  duz <- "tekrar-eden-anahtar"
  e1 <- .api_env$.enc_key(duz, .api_master)
  e2 <- .api_env$.enc_key(duz, .api_master)

  # Rastgele IV nedeniyle ciphertext farklı olmalı.
  expect_false(identical(e1$cipher_b64, e2$cipher_b64))
  # Ancak ikisi de aynı düz metne çözülmeli.
  expect_identical(.api_env$.dec_key(e1, .api_master), duz)
  expect_identical(.api_env$.dec_key(e2, .api_master), duz)
})

test_that(".enc_key/.dec_key Türkçe karakter içeren değeri korur", {
  duz <- "şğüöçİ-anahtar-ÇĞ"
  enc <- .api_env$.enc_key(duz, .api_master)
  expect_identical(.api_env$.dec_key(enc, .api_master), duz)
})

test_that(".dec_key zorunlu alanlar eksikse hata verir", {
  expect_error(.api_env$.dec_key(list(cipher_b64 = "x"), .api_master))
  expect_error(.api_env$.dec_key(list(iv_b64 = "x"), .api_master))
})

# -----------------------------------------------------------------------------
# save/load/verify/exists dosya akışı
# -----------------------------------------------------------------------------

test_that("save_user_api_key sonra load_user_api_key aynı düz anahtarı döndürür", {
  yol <- .api_env$save_user_api_key("kayit_kullanici", "fake-personal-key-001")
  expect_true(file.exists(yol))
  expect_identical(.api_env$load_user_api_key("kayit_kullanici"), "fake-personal-key-001")
})

test_that("kaydedilen dosya düz anahtarı açık metin olarak içermez", {
  .api_env$save_user_api_key("gizli_kullanici", "DUZ_ANAHTAR_TOKEN")
  ham <- paste(readLines(.api_env$.api_user_file("gizli_kullanici"), warn = FALSE), collapse = "\n")
  expect_false(grepl("DUZ_ANAHTAR_TOKEN", ham, fixed = TRUE))
})

test_that("user_api_key_exists kayıtlı kullanıcı için TRUE, olmayan için FALSE döner", {
  .api_env$save_user_api_key("var_olan", "fake-key")
  expect_true(.api_env$user_api_key_exists("var_olan"))
  expect_false(.api_env$user_api_key_exists("hic_olmayan_kullanici"))
})

test_that("load_user_api_key kayıtsız kullanıcı için NULL döner", {
  expect_null(.api_env$load_user_api_key("kayitsiz_kullanici_xyz"))
})

test_that("verify_user_api_key doğru anahtarı kabul, yanlışı ve eksik kaydı reddeder", {
  .api_env$save_user_api_key("dogrulama_kullanici", "fake-correct-key")
  expect_true(.api_env$verify_user_api_key("dogrulama_kullanici", "fake-correct-key"))
  expect_false(.api_env$verify_user_api_key("dogrulama_kullanici", "fake-wrong-key"))
  # Kaydı olmayan kullanıcı için doğrulama her zaman FALSE.
  expect_false(.api_env$verify_user_api_key("hic_yok_kullanici", "herhangi"))
})

test_that("Türkçe karakter içeren anahtar kaydedilip yüklenip doğrulanabilir", {
  .api_env$save_user_api_key("turkce_kullanici", "anahtar-ş-ğ-İ-ç")
  expect_identical(.api_env$load_user_api_key("turkce_kullanici"), "anahtar-ş-ğ-İ-ç")
  expect_true(.api_env$verify_user_api_key("turkce_kullanici", "anahtar-ş-ğ-İ-ç"))
})

# -----------------------------------------------------------------------------
# Regresyon: NUL içeren rastgele tuz kaydı çökertmemeli
# (rand_bytes 0x00 bayt üretebilir; .hash_key_hex rawToChar ile gömülü NUL
#  hatası verirdi. save_user_api_key tuzdaki NUL baytlarını 0x01'e eşler.)
# -----------------------------------------------------------------------------

test_that("save_user_api_key tuz 0x00 bayt içerse de çökmeden kaydeder ve doğrular", {
  skip_if_not_installed("openssl")

  # rand_bytes'i NUL içeren bir tuz/IV döndürecek şekilde mock'la.
  testthat::local_mocked_bindings(
    rand_bytes = function(n) as.raw(c(0L, rep(2L, n - 1L))),
    .package = "openssl"
  )

  expect_error(.api_env$save_user_api_key("nul_tuz_kullanici", "fake-nul-key"), NA)
  expect_identical(.api_env$load_user_api_key("nul_tuz_kullanici"), "fake-nul-key")
  expect_true(.api_env$verify_user_api_key("nul_tuz_kullanici", "fake-nul-key"))
  expect_false(.api_env$verify_user_api_key("nul_tuz_kullanici", "fake-yanlis-key"))
})
