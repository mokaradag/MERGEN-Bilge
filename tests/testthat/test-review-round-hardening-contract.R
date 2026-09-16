# ==============================================================================
# Dosya Yolu: tests/testthat/test-review-round-hardening-contract.R
# Açıklama: Son inceleme turunda kapatılan bulguların SÖZLEŞME testleri.
#           Davranış testi pratik olmayan (Shiny gözlemcisi, kilit sahipliği
#           yarışı, worker gönderim dalı) boundary'ler için kararın koddaki
#           yerinde kaldığı doğrulanır; kilit/rezervasyon ve karar yardımcıları
#           ise gerçek dosya sistemiyle DAVRANIŞ olarak sınanır.
#
#           Çevrimdışı ve deterministiktir: DB, LLM, ağ, tarayıcı veya gerçek
#           Shiny oturumu GEREKMEZ.
# ==============================================================================

# Windows VM'de bazı dosyalar geçersiz UTF-8 bayt dizisi taşıyabilir; tarama
# BAYT GÜVENLİ okuyucuyla yapılır (CLAUDE.md Windows tarama kuralı).
.reviewContractText <- function(goreli_yol) {
  yol <- file.path(resolve_repo_root_for_tests(), goreli_yol)
  ham <- readBin(yol, what = "raw", n = file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  # `.gitattributes` eol=lf yalnızca TAZE checkout'u normalleştirir; çalışma
  # kopyasındaki CRLF çok satırlı `fixed = TRUE` eşleşmesini düşürür.
  metin <- gsub("\r\n", "\n", metin, fixed = TRUE)
  gsub("\r", "\n", metin, fixed = TRUE)
}

# Yorum satırları taramadan ÖNCE ayıklanır: açıklayıcı bir yorum, kodda
# BULUNMAMASI gereken bir kalıbı içerdiğinde yanlış pozitif üretiyordu.
.reviewContractCode <- function(goreli_yol) {
  satirlar <- strsplit(.reviewContractText(goreli_yol), "\n", fixed = TRUE)[[1]]
  paste(satirlar[!grepl("^\\s*#", satirlar)], collapse = "\n")
}

.reviewContractEnv <- function(dosyalar, stub_fn = NULL) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a
  if (is.function(stub_fn)) stub_fn(env)
  kok <- resolve_repo_root_for_tests()
  for (dosya in dosyalar) {
    source(file.path(kok, dosya), encoding = "UTF-8", local = env)
  }
  env
}

# ------------------------------------------------------------------------------
# İndeks kilidi heartbeat'i SAHİPLİK KANITI döndürür ve kova temizliği DENETLER
# ------------------------------------------------------------------------------
test_that("indeks kilidi heartbeat'i sahiplik sonucunu döndürür", {
  env <- .reviewContractEnv(
    "R/config_file_store_index_lock.R",
    stub_fn = function(e) {
      e$MERGEN_INDEX_PATH <- file.path(tempdir(), "review-lock-index.json")
      e$log_warn <- function(...) invisible(NULL)
    }
  )

  # Kilit TUTULMUYORSA kaybedilecek sahiplik de yoktur.
  expect_true(env$file_store_index_lock_heartbeat())

  # Kayıtlı tazeleyici FALSE döndürdüğünde sonuç FALSE olur (sahiplik kaybı).
  env$.FILE_STORE_LOCK_STATE$heartbeat <- function() FALSE
  expect_false(env$file_store_index_lock_heartbeat())

  # Tazeleyici HATA fırlatırsa da sahiplik kanıtlanamaz.
  env$.FILE_STORE_LOCK_STATE$heartbeat <- function() stop("kilit yok")
  expect_false(env$file_store_index_lock_heartbeat())

  env$.FILE_STORE_LOCK_STATE$heartbeat <- function() TRUE
  expect_true(env$file_store_index_lock_heartbeat())
})

test_that("kova temizliği heartbeat sonucunu denetler ve silmeyi durdurur", {
  metin <- .reviewContractText("R/config_file_store_bucket_clear.R")

  expect_true(
    grepl("if (!isTRUE(file_store_index_lock_heartbeat())) {", metin, fixed = TRUE),
    info = "Heartbeat sonucu DENETLENMELİDİR (lost update koruması)."
  )
  # Silme döngüsü `temizle()` GÖVDESİNDEDİR: `<<-` yerel çerçeveyi atlar ve
  # `break`/başarısızlık dalını ölü koda çevirirdi.
  expect_true(
    grepl("sahiplik_kaybi <- TRUE", metin, fixed = TRUE),
    info = "Sahiplik kaybı silme döngüsünü durdurmalıdır."
  )
  expect_false(
    grepl("sahiplik_kaybi <<- TRUE", .reviewContractCode("R/config_file_store_bucket_clear.R"),
          fixed = TRUE),
    info = "Yerel bayrak `<<-` ile yazılmamalıdır (ölü kod riski)."
  )
  # Uzlaştırma DIŞ KİLİT BIRAKILDIKTAN sonra yapılır: dizin tabanlı kilit
  # yeniden girişli değildir ve iç içe edinim her zaman zaman aşımıyla
  # düşüyordu (uzlaştırma ölü koddu).
  expect_true(
    grepl(".kova_silinenleri_kilitle_ayikla(uid, sonuc$silinen, .kova_yol_anahtari)",
          metin, fixed = TRUE),
    info = "Silinenler DIŞ KİLİT SONRASI, yeniden alınan kilit altında uzlaştırılmalıdır."
  )
  expect_true(
    grepl("if (is.list(sonuc) && isTRUE(sonuc$sahiplik_kaybi)) {", metin, fixed = TRUE),
    info = "`temizle()` sahiplik kaybını çağırana YAPISAL olarak bildirmelidir."
  )
  # ÜÇ DURUMLU varlık kararı: "yok" varsayımı indeks kaydını düşürüyordu.
  expect_true(
    grepl("durum <- .kova_dizin_durumu(dir)", metin, fixed = TRUE) &&
      grepl("identical(durum, \"belirsiz\")", metin, fixed = TRUE),
    info = "Dizin varlığı üç durumlu değerlendirilmelidir."
  )
  # Başarıyla SİLİNEN kaydın indekste kalmaması.
  expect_true(
    grepl("anahtar %in% silinemeyen || !(anahtar %in% silinen)", metin, fixed = TRUE),
    info = "Silinen dosyaların kaydı indeksten düşmelidir."
  )
})

.reviewBucketDirDurum <- function() {
  env <- .reviewContractEnv(
    c(
      "R/utils_path_helpers.R", "R/helpers_files_path.R",
      "R/config_file_store_bucket_clear.R"
    ),
    stub_fn = function(e) {
      e$MERGEN_UPLOADS_DIR <- tempdir()
      e$MERGEN_MCP_BASE_DIR <- tempdir()
      e$log_warn <- function(...) invisible(NULL)
      e$mergen_user_upload_dir <- function(uid) ""
      e$.load_index <- function() list()
      e$.save_index <- function(idx) invisible(TRUE)
    }
  )
  # Karar yardımcısı DOSYA KAPSAMINDADIR (saf; test edilebilir olması için
  # `mergen_clear_user_bucket()` gövdesinden çıkarıldı).
  env$.kova_dizin_durumu
}

test_that("kova dizin durumu var/yok kararlarını doğru verir", {
  durum_fn <- .reviewBucketDirDurum()

  ust <- withr::local_tempdir()
  hedef <- file.path(ust, "kova")
  dir.create(hedef)

  expect_identical(durum_fn(hedef), "var")
  # Üst dizin LİSTELENEBİLİYOR ve ad orada YOK: kesin karar verilebilir.
  expect_identical(durum_fn(file.path(ust, "yok-boyle-bir-dizin")), "yok")
  # ÜST dizin de yoksa aday da KESİN yoktur; yokluk ata zincirinde kanıtlanır.
  # Eski "belirsiz" davranışı, henüz oluşturulmamış bir kökte (yeni kurulum)
  # her temizlik çağrısını başarısız yapıyordu.
  expect_identical(
    durum_fn(file.path(ust, "olmayan-ust", "kova")),
    "yok"
  )
})

test_that("kova temizliği bağlantıyla kova DIŞINA çıkan yolu silmez", {
  # Sembolik bağlantı POSIX'te izinsiz oluşturulabilir; Windows'ta ayrıcalık
  # gerektirir, bu yüzden davranış orada atlanır (üretim koruması aynıdır).
  skip_on_os("windows")

  kova_kok <- withr::local_tempdir()
  kova <- file.path(kova_kok, "user_9100")
  disari <- withr::local_tempdir()
  dir.create(kova, recursive = TRUE)
  dis_dosya <- file.path(disari, "gizli.txt")
  writeLines("kova disi", dis_dosya)
  ic_dosya <- file.path(kova, "ic.txt")
  writeLines("kova ici", ic_dosya)
  expect_true(file.symlink(disari, file.path(kova, "baglanti")))

  indeks <- new.env(parent = emptyenv())
  indeks$veri <- list(`9100` = list(list(path = ic_dosya)))

  env <- .reviewContractEnv(
    c(
      "R/utils_path_helpers.R", "R/helpers_files_path.R",
      "R/config_file_store_bucket_clear.R"
    ),
    stub_fn = function(e) {
      e$MERGEN_UPLOADS_DIR <- kova_kok
      e$MERGEN_MCP_BASE_DIR <- kova_kok
      e$log_warn <- function(...) invisible(NULL)
      e$mergen_user_upload_dir <- function(uid) kova
      e$.load_index <- function() indeks$veri
      e$.save_index <- function(idx) {
        indeks$veri <- idx
        invisible(TRUE)
      }
      e$file_store_index_lock_heartbeat <- function() TRUE
      e$.file_store_with_index_lock <- function(expr, ...) expr
    }
  )

  # Bağlantı üzerinden görünen dosya SİLİNEMEYEN sayılır; çağrı başarısızdır.
  expect_warning(sonuc <- env$mergen_clear_user_bucket(9100), "silinemedi")
  expect_false(isTRUE(sonuc))

  # Kova DIŞINDAKİ dosya DOKUNULMADAN durur; kova içindeki dosya silinir.
  expect_true(file.exists(dis_dosya))
  expect_false(file.exists(ic_dosya))
})

test_that("kova dizin durumu okunamayan üst dizinde BELİRSİZ döner", {
  # POSIX izin bitleri gerekir; root izin denetimini atlar.
  skip_on_os("windows")
  skip_if(identical(Sys.info()[["effective_user"]], "root"),
          "root izin denetimini atlar")

  durum_fn <- .reviewBucketDirDurum()
  ust <- withr::local_tempdir()

  Sys.chmod(ust, "000")
  on.exit(Sys.chmod(ust, "700"), add = TRUE)
  expect_identical(durum_fn(file.path(ust, "yok-boyle-bir-dizin")), "belirsiz")
})

test_that("kova temizliği sahiplik kaybında silmeyi DURDURUR", {
  kova_kok <- withr::local_tempdir()
  kova <- file.path(kova_kok, "user_9001")
  dir.create(kova)
  dosyalar <- file.path(kova, c("a.txt", "b.txt", "c.txt"))
  for (d in dosyalar) writeLines("veri", d)

  durum <- new.env(parent = emptyenv())
  durum$heartbeat_cagri <- 0L
  durum$kilit_cagri <- 0L
  durum$indeks <- list(
    `9001` = lapply(dosyalar, function(p) list(path = p))
  )

  env <- .reviewContractEnv(
    c(
      "R/utils_path_helpers.R", "R/helpers_files_path.R",
      "R/config_file_store_bucket_clear.R"
    ),
    stub_fn = function(e) {
      e$MERGEN_UPLOADS_DIR <- kova_kok
      e$MERGEN_MCP_BASE_DIR <- kova_kok
      e$log_warn <- function(...) invisible(NULL)
      e$mergen_user_upload_dir <- function(uid) kova
      e$.load_index <- function() durum$indeks
      e$.save_index <- function(idx) {
        durum$indeks <- idx
        invisible(TRUE)
      }
      # Heartbeat İLK dosyadan SONRA çağrılır; orada sahiplik KAYBEDİLİR.
      e$file_store_index_lock_heartbeat <- function() {
        durum$heartbeat_cagri <- durum$heartbeat_cagri + 1L
        FALSE
      }
      e$.file_store_with_index_lock <- function(expr, ...) {
        durum$kilit_cagri <- durum$kilit_cagri + 1L
        expr
      }
    }
  )

  expect_warning(
    sonuc <- env$mergen_clear_user_bucket(9001),
    "sahipliği kaybedildi"
  )
  expect_false(isTRUE(sonuc))

  # Döngü GERÇEKTEN durdu: ilk dosya silindi, kalanlar diskte DURUYOR.
  expect_identical(durum$heartbeat_cagri, 1L)
  expect_false(file.exists(dosyalar[1]))
  expect_true(all(file.exists(dosyalar[-1])))

  # İndeks uzlaştırması YENİDEN alınan kilit altında yapıldı (dış + iç çağrı).
  expect_gte(durum$kilit_cagri, 2L)
  # Yalnızca SİLİNEN dosyanın kaydı düştü; kalanlar korundu.
  kalan_yollar <- vapply(durum$indeks[["9001"]], function(e) e$path, character(1))
  expect_setequal(kalan_yollar, dosyalar[-1])
})

# ------------------------------------------------------------------------------
# Aşamalı kopya terfisi: sahiplik kanıtlı, hedefi EZMEYEN terfi
# ------------------------------------------------------------------------------
test_that("terfi var olan hedefi EZMEZ ve yabancı hedefi işaretler", {
  env <- .reviewContractEnv(
    c(
      "R/utils_path_reservation.R", "R/helpers_files_promote_probe.R",
      "R/helpers_files_promote_target.R"
    )
  )

  dizin <- withr::local_tempdir()
  staging <- file.path(dizin, "veri.txt.mergen-part")
  hedef <- file.path(dizin, "veri.txt")
  writeLines("yeni", staging)
  writeLines("mevcut", hedef)

  var_mi <- function(p) isTRUE(file.exists(p))
  sonuc <- env$mergen_promote_staged_file(staging, hedef, var_mi)

  expect_false(isTRUE(sonuc$ok))
  expect_true(isTRUE(sonuc$yabanci))
  # EŞZAMANLI yüklemenin dosyası KORUNUR.
  expect_identical(readLines(hedef), "mevcut")
})

test_that("terfi boş hedefe atomik olarak yerleşir", {
  env <- .reviewContractEnv(
    c(
      "R/utils_path_reservation.R", "R/helpers_files_promote_probe.R",
      "R/helpers_files_promote_target.R"
    )
  )

  dizin <- withr::local_tempdir()
  staging <- file.path(dizin, "veri.txt.mergen-part")
  hedef <- file.path(dizin, "veri.txt")
  writeLines("icerik", staging)

  sonuc <- env$mergen_promote_staged_file(
    staging, hedef, function(p) isTRUE(file.exists(p))
  )

  expect_true(isTRUE(sonuc$ok))
  expect_false(isTRUE(sonuc$yabanci))
  expect_identical(readLines(hedef), "icerik")
  expect_false(file.exists(staging))
})

test_that("görünürlük deneme sayısı geçersiz girdide güvenli varsayılana düşer", {
  env <- .reviewContractEnv(
    c(
      "R/utils_path_reservation.R", "R/helpers_files_promote_probe.R",
      "R/helpers_files_promote_target.R"
    )
  )

  # `as.integer(NA)` sonrası `seq_len()` HATA fırlatıyordu (terfi SONRASINDA).
  expect_identical(env$mergen_promote_attempt_count(NA), 10L)
  expect_identical(env$mergen_promote_attempt_count(Inf), 10L)
  expect_identical(env$mergen_promote_attempt_count("uc"), 10L)
  expect_identical(env$mergen_promote_attempt_count(0L), 10L)
  expect_identical(env$mergen_promote_attempt_count(3L), 3L)

  # Var olmayan yol için yoklama HATA FIRLATMADAN FALSE döner.
  expect_false(env$mergen_promote_wait_visible(
    file.path(tempdir(), "yok-boyle-bir-dosya"),
    function(p) isTRUE(file.exists(p)),
    denemeler = NA
  ))
})

test_that("aşamalı kopya staging görünürlüğünü sınırlı yoklamayla bekler", {
  metin <- .reviewContractText("R/helpers_files_copy_promote.R")

  expect_true(
    grepl("gorunur_mu <- function(p) {", metin, fixed = TRUE),
    info = "Staging görünürlüğü sınırlı yoklamayla denetlenmelidir."
  )
  expect_true(
    grepl("mergen_promote_staged_file(", metin, fixed = TRUE),
    info = "Terfi sahiplik kanıtlı yardımcıya devredilmelidir."
  )
  expect_false(
    grepl("file.rename(staging, hedef)", metin, fixed = TRUE),
    info = "Ham `file.rename()` terfisi bu dosyada kalmamalıdır."
  )
})

test_that("atomik yazma kısmi hedefi sahiplik kanıtıyla temizler", {
  metin <- .reviewContractText("R/utils_atomic_write.R")

  expect_true(
    grepl("mergen_reservation_acquire(rezerv_yolu, rezerv_jetonu)", metin, fixed = TRUE),
    info = "Hedef adı sahiplik kanıtı için rezerve edilmelidir."
  )
  expect_true(
    grepl("(isTRUE(copied) || isTRUE(sahiplik))", metin, fixed = TRUE),
    info = "Kısmi hedef, rezervasyon kanıtıyla da temizlenebilmelidir."
  )
})

# ------------------------------------------------------------------------------
# Dosya Yönetimi silme kararı: fiziksel silme başarılıysa yerel durum TEMİZLENİR
# ------------------------------------------------------------------------------
test_that("silme kararı kısmi temizliği yerel durumu koruma nedeni saymaz", {
  env <- .reviewContractEnv("R/helpers_file_manager_artifact_recovery.R")
  plan <- env$fm_delete_local_state_plan

  # Fiziksel silme YOK: yerel durum korunur.
  d <- plan(list(delete_failed = TRUE, deleted_physical = FALSE))
  expect_true(d$abort); expect_false(d$partial)

  # Silindi ama indeks temizliği kısmi: yerel durum TEMİZLENİR, ayrı bildirilir.
  d <- plan(list(delete_failed = TRUE, deleted_physical = TRUE))
  expect_false(d$abort); expect_true(d$partial)

  # Tam başarı.
  d <- plan(list(delete_failed = FALSE, deleted_physical = TRUE))
  expect_false(d$abort); expect_false(d$partial)
})

test_that("artefakt silme kilidi Shiny olay döngüsünü kısa tutar", {
  metin <- .reviewContractText("R/helpers_file_manager_artifact_recovery.R")
  expect_true(
    grepl(".file_store_with_index_lock(sil(), timeout_sec = 0.5, require_lock = FALSE)",
          metin, fixed = TRUE),
    info = "Kilit beklemesi kısa zaman aşımıyla sınırlanmalıdır."
  )
})

# ------------------------------------------------------------------------------
# Bilge Yolaç: aşama bildirimi çıktı işlemeyi İPTAL ETMEZ
# ------------------------------------------------------------------------------
test_that("aşama bildirimi hatası çıktı işlemeyi iptal etmez", {
  for (dosya in c("R/helpers_claude_code_codex_output_fixes.R",
                  "R/helpers_claude_code_run_output_dispatch.R")) {
    metin <- .reviewContractText(dosya)
    expect_true(
      grepl("çıktı işleme devam ediyor", metin, fixed = TRUE),
      info = sprintf("%s: aşama hatası yalnızca loglanmalıdır.", dosya)
    )
    expect_false(
      grepl("cc_report_output_processing_failure(\n      ctx,\n      attr(stage_sonuc",
            metin, fixed = TRUE),
      info = sprintf("%s: aşama hatası başarısızlık olarak raporlanmamalıdır.", dosya)
    )
  }
})

test_that("runtime terfi hatası sahiplik doğrulanmadan geri yükleme yapmaz", {
  metin <- .reviewContractText("R/helpers_claude_code_codex_runtime_fixes.R")

  expect_true(
    grepl("sahiplik_var <- identical(.cc_codex_lock_owner_token(lock_dir), kilit_jetonu)",
          metin, fixed = TRUE),
    info = "Geri yüklemeden ÖNCE sahiplik doğrulanmalıdır."
  )
  # Yükleme denetimi kullanılan TÜM kilit yardımcılarını kapsar.
  for (yardimci in c(".cc_codex_acquire_dir_lock", ".cc_codex_reap_dir_lock",
                     ".cc_codex_touch_dir_lock")) {
    expect_true(
      grepl(yardimci, metin, fixed = TRUE),
      info = sprintf("Yükleme denetimi %s yardımcısını kapsamalıdır.", yardimci)
    )
  }
})

test_that("yetim runtime geri kazanımı adım adım siler ve kirayı tazeler", {
  metin <- .reviewContractText("R/helpers_claude_code_runtime_lease.R")

  expect_true(
    grepl("cc_runtime_unlink_stepwise(aday)", metin, fixed = TRUE),
    info = "Uzun silme adımlara bölünmelidir (kilit bayatlamamalı)."
  )
  expect_true(
    grepl("cc_runtime_cleanup_lock_heartbeat()", metin, fixed = TRUE),
    info = "Her adımda kira tazelenmeli ve sahiplik doğrulanmalıdır."
  )
})

test_that("adım adım silme sahiplik kaybında DURUR", {
  env <- .reviewContractEnv(
    "R/helpers_claude_code_runtime_lease.R",
    stub_fn = function(e) {
      e$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
      e$log_warn <- function(...) invisible(NULL)
      e$cc_runtime_limit <- function(...) 0
      e$cc_runtime_user_dir <- function(...) ""
      e$.cc_scan_key <- function(x) x
      e$.cc_scan_norm <- function(x) x
    }
  )

  kok <- withr::local_tempdir()
  dir.create(file.path(kok, "alt"), recursive = TRUE)
  writeLines("x", file.path(kok, "alt", "a.txt"))
  writeLines("y", file.path(kok, "b.txt"))

  # Sahiplik KAYIP: hiçbir şey silinmez.
  env$.CC_RUNTIME_LOCK_STATE$heartbeat <- function() FALSE
  expect_false(env$cc_runtime_unlink_stepwise(kok))
  expect_true(dir.exists(kok))
  expect_true(file.exists(file.path(kok, "b.txt")))

  # Sahiplik SÜRÜYOR: tüm ağaç silinir.
  env$.CC_RUNTIME_LOCK_STATE$heartbeat <- function() TRUE
  expect_true(env$cc_runtime_unlink_stepwise(kok))
  expect_false(dir.exists(kok))
})

test_that("bağlantı testi kökü kullanıcı çalışma alanlarının ÜSTÜ değildir", {
  env <- .reviewContractEnv(
    "R/helpers_claude_code_path_policy.R",
    stub_fn = function(e) {
      e$claude_code_config <- list(allowed_workdir_roots = "")
      e$log_warn <- function(...) invisible(NULL)
      e$CLAUDE_CODE_LOG_PREFIX <- "[TEST]"
    }
  )

  kok <- env$cc_policy_temp_workspace_root()
  # Kök, `user_<id>` alt ağaçlarını İÇERMEZ: paylaşılan üst dizinin ALTINDA
  # ayrı bir klasördür.
  expect_true(grepl("claude_code_workspaces", kok, fixed = TRUE))
  expect_false(identical(
    normalizePath(kok, winslash = "/", mustWork = FALSE),
    normalizePath(file.path(tempdir(), "claude_code_workspaces"),
                  winslash = "/", mustWork = FALSE)
  ))

  # Kimlik YOKKEN izinli kökler ÜST dizinleri içermez.
  kokler <- env$cc_policy_allowed_workdir_roots(allow_system_temp = TRUE)
  ust_kokler <- normalizePath(
    c(file.path(tempdir(), "claude_code_runtime"),
      file.path(tempdir(), "claude_code_workspaces")),
    winslash = "/", mustWork = FALSE
  )
  expect_false(any(normalizePath(kokler, winslash = "/", mustWork = FALSE) %in% ust_kokler))
})

# ------------------------------------------------------------------------------
# SSO: skaler olmayan `kid` fail-closed reddedilir
# ------------------------------------------------------------------------------
test_that("skaler olmayan kid imza anahtarı çözümlemesinde reddedilir", {
  env <- .reviewContractEnv(
    c("R/helpers_sso_jwks_cache.R"),
    stub_fn = function(e) {
      e$log_warn <- function(...) invisible(NULL)
    }
  )
  env$sso_decode_jwt_header <- function(token) list(kid = c("a", "b"), alg = "RS256")

  cagrildi <- FALSE
  sonuc <- env$sso_resolve_signing_key(
    token = "sahte.token.imza",
    config = list(jwks_endpoint = "https://kc/realms/x/protocol/openid-connect/certs",
                  jwks_cache_ttl_secs = 3600L),
    fetch_fn = function(url) { cagrildi <<- TRUE; list(list(kid = "a")) }
  )

  # İstisna FIRLATMAZ, NULL döner ve JWKS getirme HİÇ denenmez.
  expect_null(sonuc)
  expect_false(cagrildi)
})

test_that("doğrulanmış skaler kid arama çağrılarına geçirilir", {
  metin <- .reviewContractText("R/helpers_sso_jwks_cache.R")
  expect_true(
    grepl("arama_kid <- if (nzchar(kid_metin)) kid_metin else NULL", metin, fixed = TRUE),
    info = "Aramaya doğrulanmış skaler geçilmelidir."
  )
  expect_false(
    grepl("sso_find_jwk_by_kid(keys, kid)", metin, fixed = TRUE),
    info = "HAM `kid` değeri arama çağrısına geçirilmemelidir."
  )
})

# ------------------------------------------------------------------------------
# Geri bildirim senkronizasyonu CLAIM değişimini de izler
# ------------------------------------------------------------------------------
test_that("geri bildirim gözlemcisi claim değişimini de izler", {
  kod <- .reviewContractCode("R/server_init_session_state.R")

  expect_true(
    grepl("list(sso_state$authenticated, sso_state$user_claims)", kod, fixed = TRUE),
    info = "Kullanıcı A -> B geçişinde senkronizasyon çalışmalıdır."
  )
  expect_false(
    grepl("once = TRUE", kod, fixed = TRUE),
    info = "`once = TRUE` yeniden kimlik doğrulamada senkronizasyonu öldürüyordu."
  )
})

# ------------------------------------------------------------------------------
# Dosya tıklama gözlemcisi kök çözümleme hatasını SESSİZCE yutmaz
# ------------------------------------------------------------------------------
test_that("dosya tıklama gözlemcisi kök çözümleme hatasını ayrıştırır", {
  metin <- .reviewContractText("R/server_observers_file_clicks.R")

  expect_true(
    grepl("kok_hatasi <<- TRUE", metin, fixed = TRUE),
    info = "Kök çözümleme hatası ayrı bir durum olarak izlenmelidir."
  )
  expect_true(
    grepl("Kullanıcı yükleme kökü çözülemedi", metin, fixed = TRUE),
    info = "Kök çözümleme hatası loglanmalıdır."
  )
  expect_true(
    grepl("Dosya klasörünüz şu anda çözümlenemedi", metin, fixed = TRUE),
    info = "Kullanıcıya geçici hata bildirilmelidir (sessiz ret değil)."
  )
})

# ------------------------------------------------------------------------------
# Ortak Oturum rezervasyonu SAHİPLİK kanıtıyla devralınır
# ------------------------------------------------------------------------------
test_that("ortak çalışma alanı rezervasyonu sahiplik jetonu kullanır", {
  metin <- .reviewContractText("R/helpers_ortak_oturum_ws_kopyalama.R")

  expect_true(
    grepl(".oo_rezerv_al(rezerv, jeton)", metin, fixed = TRUE),
    info = "Rezervasyon jetonla alınmalıdır."
  )
  expect_true(
    grepl(".oo_rezerv_devral(rezerv, jeton)", metin, fixed = TRUE),
    info = "Devralma sahiplik kanıtlı yardımcıdan geçmelidir."
  )
  expect_true(
    grepl("finally = .oo_rezerv_birak(rezerv, jeton)", metin, fixed = TRUE),
    info = "Bırakma YALNIZCA kendi jetonuyla yapılmalıdır."
  )
  expect_false(
    grepl("if (is.finite(yas) && yas > 60) {", metin, fixed = TRUE),
    info = "Yalnızca YAŞA dayalı devralma kaldırılmıştır."
  )
})

# ------------------------------------------------------------------------------
# AI Uzman hattı: teslim hatasında parça DÜŞÜRÜLMEZ
# ------------------------------------------------------------------------------
test_that("AI uzman hattı teslim hatasında parçayı kuyrukta tutar", {
  env <- .reviewContractEnv(
    "R/helpers_ai_expert_chunk_pipeline.R",
    stub_fn = function(e) {
      e$cat <- function(...) invisible(NULL)
    }
  )

  parcalar <- as.list(paste0("p", 1:3))
  cozucu <- list()
  teslim_edilen <- character(0)
  hata_verildi <- FALSE

  durum <- env$ai_expert_chunk_pipeline_baslat(
    parcalar = parcalar,
    baslangic = 2L,
    synth_fn = function(metin) {
      promises::promise(function(resolve, reject) {
        cozucu[[length(cozucu) + 1L]] <<- function() {
          resolve(list(success = TRUE, audio_src = paste0("ses-", metin), duration = 1))
        }
      })
    },
    is_current_fn = function() TRUE,
    queue_fn = function(index0, text, audio_src, duration) {
      # İLK teslim denemesi hata verir; parça DÜŞMEMELİ.
      if (!hata_verildi) {
        hata_verildi <<- TRUE
        stop("teslim hatasi (test)")
      }
      teslim_edilen <<- c(teslim_edilen, text)
    },
    policy = modifyList(env$ai_expert_chunk_pipeline_policy(),
                        list(eszamanli_sinir = 2L, tampon_deadline_sn = 0))
  )

  for (f in cozucu) f()
  for (i in 1:40) later::run_now(0.01)

  # Hata veren teslim yeniden denenir: parça istemciye ULAŞIR.
  expect_true("p2" %in% teslim_edilen)
  expect_true(hata_verildi)
})

test_that("NA ses kaynağı geçerli sayılmaz", {
  metin <- .reviewContractText("R/helpers_ai_expert_chunk_pipeline.R")
  expect_true(
    grepl("!is.na(ses_kaynagi) &&", metin, fixed = TRUE),
    info = "`nzchar(NA)` TRUE döndüğü için NA ses kaynağı açıkça reddedilmelidir."
  )
})

# ------------------------------------------------------------------------------
# Shiny boot smoke gövde taraması bayt güvenli kalmalıdır
# ------------------------------------------------------------------------------
test_that("ai_boot_smoke gövdeyi bayt güvenli tarar", {
  metin <- .reviewContractText("tests/scripts/ai_boot_smoke.R")

  expect_true(
    grepl('iconv(txt, from = "UTF-8", to = "UTF-8", sub = "?")', metin, fixed = TRUE),
    info = "Gövde bayt güvenli okuyucuyla normalleştirilmelidir."
  )
  expect_true(
    grepl("ignore.case = TRUE, useBytes = TRUE", metin, fixed = TRUE),
    info = "ASCII çapalar BAYT düzeyinde taranmalıdır."
  )
  # `enc2utf8()` kesilmiş baytları GEÇERLİ kılmaz; sağlıklı uygulama başarısız
  # raporlanıyordu.
  expect_false(
    grepl("enc2utf8(txt)", .reviewContractCode("tests/scripts/ai_boot_smoke.R"),
          fixed = TRUE),
    info = "Gövde normalleştirmesi enc2utf8() ile yapılmamalıdır."
  )
})
