# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-async-request-behavior.R
# Açıklama: Faz 6 (§5.10) — işçi anlık görüntüsü, oturum vekili, bootstrap
#           sözleşmesi ve İSTEK-KİMLİĞİ KORUMASI davranış testleri.
#           Tamamen çevrimdışı: gerçek future işçisi, DB, LLM, ağ GEREKMEZ.
#
# Kanıtlanan sözleşmeler:
#   - Anlık görüntü hiçbir oturum/reaktif/bağlantı/fonksiyon/ortam TAŞIMAZ ve
#     bunu savunmacı doğrulayıcı GÖRÜR.
#   - Vekil oturumun `userData`'sı bir ORTAMDIR; işçi yazımları GERİ TOPLANIR.
#   - Kişisel anahtar YALNIZCA gerçekten kişisel çözüldüyse taşınır ve sahiplik
#     işaretiyle birlikte gider (kurum varsayılanı işçide çözülür).
#   - Bayat/durdurulmuş/kimliksiz geri çağrı durumu MUTASYONA UĞRATAMAZ.
#   - İşçi bootstrap SÜREÇ BAŞINA BİR KEZ çalışır (memoize) ve globals paketi
#     KÜÇÜK kalır (yüzlerce fonksiyon serileştirilmez).
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  for (dosya in c("helpers_pk_config.R", "helpers_pk_async_cancel.R",
                  "helpers_pk_async_worker_env.R", "helpers_pk_async_worker_pool.R", "helpers_pk_async_bootstrap.R", "helpers_pk_async_snapshot_validate.R", "helpers_pk_async_snapshot.R",
                  "helpers_pk_async_plan.R", "helpers_pk_async_request.R")) {
    source(file.path(repo_root, "R", dosya), encoding = "UTF-8", local = globalenv())
  }
})

# --- Anlık görüntü işçi güvenliği ---------------------------------------------

test_that("temiz düz liste işçi-güvenli sayılır", {
  dogrulama <- pk_async_validate_request(list(
    a = "metin", b = 42L, c = list(d = TRUE, e = c(1, 2, 3))
  ))
  expect_true(dogrulama$safe)
  expect_equal(dogrulama$violations, character(0))
})

test_that("fonksiyon, ortam ve reaktif/bağlantı sınıfları REDDEDİLİR", {
  expect_false(pk_async_validate_request(list(f = function() 1))$safe)
  expect_false(pk_async_validate_request(list(e = new.env()))$safe)

  sahte_oturum <- structure(list(userData = list()), class = "ShinySession")
  expect_false(pk_async_validate_request(list(session = sahte_oturum))$safe)

  sahte_rv <- structure(list(), class = "reactivevalues")
  expect_false(pk_async_validate_request(list(values = sahte_rv))$safe)

  sahte_conn <- structure(list(), class = c("SQLiteConnection", "DBIConnection"))
  expect_false(pk_async_validate_request(list(conn = sahte_conn))$safe)
})

test_that("ihlal DERİN iç içe listede de bulunur ve YOLU raporlanır", {
  dogrulama <- pk_async_validate_request(list(
    ust = list(orta = list(alt = new.env()))
  ))
  expect_false(dogrulama$safe)
  expect_true(any(grepl("ust\\$orta\\$alt", dogrulama$violations)))
})

test_that("gerçek anlık görüntü işçi-güvenlidir", {
  istek <- pk_async_build_request(
    user_prompt = "İstanbul projesinin kalan işçiliği nedir?",
    chat_history = list(list(role = "user", content = "merhaba")),
    username = "ali.veli",
    request_id = "req_1",
    deep_thinking = TRUE,
    detail_level = "detayli",
    api_key_plan = list(key = "sk-fake-personal", source = "personal"),
    user_session_snapshot = list(system_username = "ali.veli", user_id = 7L),
    select_state = list(sohbet_1 = list(query_id = "q009")),
    repo_root = tempdir(),
    cancel_token = "/tmp/x.flag",
    deadline_sec = 300,
    engine = "v2",
    bootstrap_files = c("R/utils_common.R")
  )

  expect_true(pk_async_validate_request(istek)$safe)
  expect_equal(istek$username, "ali.veli")
  expect_true(istek$deep_thinking)
  expect_equal(istek$engine, "v2")
  expect_equal(istek$bootstrap_files, "R/utils_common.R")
})

test_that("KURUM varsayılan anahtarı işçiye TAŞINMAZ", {
  # Kaynak `default` ise anahtar hiç taşınmaz; işçi kendi ortamından çözer.
  # Böylece kişisel/kurum ayrımı birebir korunur ve gereksiz sır taşınmaz.
  istek <- pk_async_build_request(
    user_prompt = "x", chat_history = list(), username = "u", request_id = "r",
    api_key_plan = list(key = "sk-institution", source = "default")
  )
  expect_equal(istek$api_key, "")
  expect_equal(istek$api_key_source, "default")

  eksik <- pk_async_build_request(
    user_prompt = "x", chat_history = list(), username = "u", request_id = "r",
    api_key_plan = list(key = "", source = "missing")
  )
  expect_equal(eksik$api_key, "")
})

test_that("sohbet geçmişi yalnızca role/content/type taşır", {
  istek <- pk_async_build_request(
    user_prompt = "x",
    chat_history = list(
      list(role = "user", content = "a", extra = new.env(), include_in_context = TRUE)
    ),
    username = "u", request_id = "r"
  )
  expect_true(pk_async_validate_request(istek)$safe)
  expect_equal(names(istek$chat_history[[1]]), c("role", "content", "type"))
})

test_that("userData anlık görüntüsü yalnızca ATOMİK alanları alır", {
  ud <- new.env(parent = emptyenv())
  ud$system_username <- "ali"
  ud$user_id <- 7L
  ud$auth_initialized <- TRUE
  ud$ai_api_key <- "gizli-anahtar-kopyalanmamali"
  ud$user_config <- list(a = 1)          # liste -> atlanır
  ud$some_fn <- function() 1             # fonksiyon -> atlanır
  oturum <- list(userData = ud)

  anlik <- pk_async_capture_user_data(oturum)
  expect_true(all(names(anlik) %in% c(
    "system_username", "user_id", "auth_source", "auth_initialized",
    "sso_active", "current_chat_id"
  )))
  expect_false("user_config" %in% names(anlik))
  expect_false("some_fn" %in% names(anlik))
  # Anahtar bu yoldan KOPYALANMAZ; yalnızca çözülmüş plan üzerinden taşınır.
  expect_false("ai_api_key" %in% names(anlik))
})

# --- Oturum vekili -----------------------------------------------------------

test_that("vekil userData bir ORTAMDIR ve yazımlar kalıcıdır", {
  istek <- pk_async_build_request(
    user_prompt = "x", chat_history = list(), username = "ali",
    request_id = "req_9",
    api_key_plan = list(key = "sk-personal", source = "personal"),
    select_state = list(s1 = list(query_id = "q001"))
  )

  vekil <- pk_async_worker_session(istek)
  expect_true(is.environment(vekil$userData))
  expect_equal(vekil$userData$system_username, "ali")
  expect_true(isTRUE(vekil$userData$auth_initialized))
  expect_equal(vekil$userData$ai_api_key, "sk-personal")
  expect_equal(vekil$userData$ai_api_key_owner, "ali")
  expect_equal(vekil$userData[["pk_provenance_request_id"]], "req_9")
  expect_equal(vekil$userData[["pk_select_state"]]$s1$query_id, "q001")

  # Liste olsaydı bu yazım sessizce kaybolurdu.
  vekil$userData[["pk_select_state"]] <- list(s1 = list(query_id = "q777"))
  expect_equal(vekil$userData[["pk_select_state"]]$s1$query_id, "q777")
})

test_that("kişisel anahtar yoksa vekilde sahiplik işareti de olmaz", {
  istek <- pk_async_build_request(
    user_prompt = "x", chat_history = list(), username = "ali", request_id = "r",
    api_key_plan = list(key = "sk-inst", source = "default")
  )
  vekil <- pk_async_worker_session(istek)
  expect_null(vekil$userData$ai_api_key)
  expect_null(vekil$userData$ai_api_key_owner)
})

test_that("işçi yazımları toplanır ve YALNIZCA izinli yuvalar uygulanır", {
  vekil <- list(userData = new.env(parent = emptyenv()))
  vekil$userData[["pk_select_state"]] <- list(s = list(query_id = "q1"))
  vekil$userData[["pk_provenance_pending"]] <- list(footer = "alt bilgi")
  vekil$userData[["rastgele_yuva"]] <- "taşınmamalı"

  yazimlar <- pk_async_harvest_session(vekil)
  expect_true(all(names(yazimlar) %in% c("pk_select_state", "pk_provenance_pending")))
  expect_false("rastgele_yuva" %in% names(yazimlar))

  hedef <- list(userData = new.env(parent = emptyenv()))
  uygulanan <- pk_async_apply_session_writes(hedef, yazimlar)
  expect_setequal(uygulanan, c("pk_select_state", "pk_provenance_pending"))
  expect_equal(hedef$userData[["pk_select_state"]]$s$query_id, "q1")

  # İzinli olmayan yuva enjekte edilse bile UYGULANMAZ.
  kotucu <- pk_async_apply_session_writes(hedef, list(rastgele_yuva = "x"))
  expect_equal(kotucu, character(0))
  expect_null(hedef$userData[["rastgele_yuva"]])
})

# --- İstek-kimliği koruması ---------------------------------------------------

test_that("aktif istek uygulanır; bayat/durdurulmuş/kimliksiz UYGULANMAZ", {
  expect_true(pk_async_should_apply("req_1", "req_1")$apply)

  bayat <- pk_async_should_apply("req_2", "req_1")
  expect_false(bayat$apply)
  expect_equal(bayat$reason, "stale")

  durduruldu <- pk_async_should_apply("req_1", "req_1", stopped = TRUE)
  expect_false(durduruldu$apply)
  expect_equal(durduruldu$reason, "stopped")

  # Durdurma, kimlik eşleşmesinden ÖNCE değerlendirilir.
  expect_equal(pk_async_should_apply("req_9", "req_1", stopped = TRUE)$reason, "stopped")

  for (bos in list(NULL, "", NA_character_)) {
    expect_false(pk_async_should_apply("req_1", bos)$apply)
    expect_equal(pk_async_should_apply("req_1", bos)$reason, "unknown")
    expect_false(pk_async_should_apply(bos, "req_1")$apply)
  }
})

test_that("durdurma sonrası cancelled_* aktif kimliği bayatlık üretir", {
  # Gerçek durdur gözlemcisi active_request_id'yi `cancelled_<ts>` yapar.
  karar <- pk_async_should_apply("cancelled_123.45", "req_1")
  expect_false(karar$apply)
  expect_equal(karar$reason, "stale")
})

# --- Bootstrap sözleşmesi -----------------------------------------------------

test_that("bootstrap dosya listesi manifest BÖLÜMLERİNDEN türetilir ve sıra korunur", {
  manifest <- list(
    foundation = c("R/a.R", "R/b.R"),
    module_ui = c("R/ui.R"),
    analysis_helpers = c("R/c.R", "R/b.R")
  )
  yollar <- pk_async_worker_bootstrap_files(
    sections = c("foundation", "analysis_helpers"), manifest = manifest
  )
  expect_equal(yollar, c("R/a.R", "R/b.R", "R/c.R"))
  # UI/modül bölümleri BİLİNÇLİ olarak dışarıdadır.
  expect_false("R/ui.R" %in% yollar)
})

test_that("donmuş bölüm listesi UI/modül/gözlemci bölümleri İÇERMEZ", {
  bolumler <- pk_async_worker_manifest_sections()
  expect_true(all(c("foundation", "database", "analysis_helpers", "llm_pipeline") %in% bolumler))
  expect_false(any(grepl("^module_", bolumler)))
  expect_false(any(grepl("^server_", bolumler)))
  expect_false("config_ui_assets" %in% bolumler)
  expect_false("ortak_oturumlar" %in% bolumler)
})

test_that("gerçek manifest ile bootstrap listesi üretilir ve PK giriş noktasını içerir", {
  repo_root <- resolve_repo_root_for_tests()
  manifest_env <- new.env(parent = globalenv())
  source(file.path(repo_root, "R", "config_source_manifest.R"),
         encoding = "UTF-8", local = manifest_env)

  yollar <- pk_async_worker_bootstrap_files(manifest = manifest_env$source_manifest_sections)
  expect_true(length(yollar) > 50L)
  expect_true("R/module_proje_kaynak_analizi.R" %in% yollar ||
                "R/helpers_pk_analysis_filters.R" %in% yollar)
  expect_true("R/helpers_db_connection.R" %in% yollar)
  expect_true("R/helpers_llm_api.R" %in% yollar)
  expect_equal(anyDuplicated(yollar), 0L)
})

test_that("bootstrap SÜREÇ BAŞINA BİR KEZ çalışır (memoize) ve tekrar okumaz", {
  kok <- file.path(tempdir(), paste0("pk_boot_", as.integer(runif(1, 1, 1e9))))
  dir.create(file.path(kok, "R"), recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(kok, recursive = TRUE), add = TRUE)

  # Sayaç: dosya her yüklendiğinde artar.
  writeLines(
    'if (!exists(".pk_boot_test_counter", envir = globalenv())) assign(".pk_boot_test_counter", 0L, envir = globalenv())
     assign(".pk_boot_test_counter", get(".pk_boot_test_counter", envir = globalenv()) + 1L, envir = globalenv())',
    file.path(kok, "R", "sayac.R")
  )

  eski_flag <- get0(.PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv(), ifnotfound = NULL)
  on.exit({
    if (is.null(eski_flag)) {
      suppressWarnings(rm(list = .PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv()))
    } else {
      assign(.PK_ASYNC_BOOTSTRAP_FLAG, eski_flag, envir = globalenv())
    }
    suppressWarnings(rm(list = ".pk_boot_test_counter", envir = globalenv()))
  }, add = TRUE)

  suppressWarnings(rm(list = .PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv()))

  # Sentetik dosya listesi: ZORUNLU giriş dosyası sözleşmesi burada
  # kapsam dışıdır (test bootstrap MEKANİĞİNİ ölçer, üretim yüzeyini değil).
  ilk <- pk_async_worker_bootstrap(kok, "R/sayac.R", required_files = character(0))
  expect_true(ilk$ok)
  expect_false(ilk$cached)
  expect_equal(ilk$loaded, 1L)
  expect_equal(get(".pk_boot_test_counter", envir = globalenv()), 1L)

  ikinci <- pk_async_worker_bootstrap(kok, "R/sayac.R", required_files = character(0))
  expect_true(ikinci$ok)
  expect_true(ikinci$cached)
  # KRİTİK: dosya İKİNCİ KEZ yüklenmedi.
  expect_equal(get(".pk_boot_test_counter", envir = globalenv()), 1L)
})

test_that("bootstrap geçersiz kök ve boş liste için TİPLİ hata döner", {
  eski_flag <- get0(.PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv(), ifnotfound = NULL)
  on.exit({
    if (is.null(eski_flag)) {
      suppressWarnings(rm(list = .PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv()))
    } else {
      assign(.PK_ASYNC_BOOTSTRAP_FLAG, eski_flag, envir = globalenv())
    }
  }, add = TRUE)
  suppressWarnings(rm(list = .PK_ASYNC_BOOTSTRAP_FLAG, envir = globalenv()))

  expect_equal(pk_async_worker_bootstrap("/olmayan/kok", "R/a.R")$failed, "repo_root")
  expect_equal(pk_async_worker_bootstrap(tempdir(), character(0))$failed, "empty_file_list")
})

test_that("hazırlık kontrolü eksik giriş noktalarını ADLANDIRIR", {
  hazir <- pk_async_worker_ready(c("pk_async_worker_ready", "kesinlikle_olmayan_fn"))
  expect_false(hazir$ready)
  expect_equal(hazir$missing, "kesinlikle_olmayan_fn")

  expect_true(pk_async_worker_ready("pk_async_worker_ready")$ready)
})

test_that("globals paketi KÜÇÜK kalır ve memoize edilir", {
  pk_async_worker_globals_reset()
  ilk <- pk_async_worker_globals()
  ikinci <- pk_async_worker_globals()

  expect_identical(ilk, ikinci)  # aynı nesne: memoize
  # Yüzlerce boru hattı fonksiyonu SERİLEŞTİRİLMEZ; işçide bootstrap ile yüklenir.
  #
  # Tavan `explicit` kip yüzünden bilinçli olarak yükseltildi: özyinelemeli
  # global genişletme YOKTUR, bu yüzden bootstrap ÖNCESİ kullanılan HER sembol
  # (parmak izi, sahneleme ortamı, havuz admisyonu, artifact kaydı, sır kurulumu)
  # AÇIKÇA taşınmalıdır. Eksik biri offline hiçbir testi kırmaz — temiz bir PSOCK
  # işçisi ham "could not find function" ile ölür. Sınır yine de KÜÇÜKTÜR:
  # boru hattının kendisi taşınmaz.
  # PR #703: sınır 45 -> 56. İnceleme, bootstrap ÖNCESİ çalışan yeni güvenlik
  # yardımcılarını gerektirdi (sınırlı dosya sistemi sarmalayıcısı, havuz
  # yapılandırma parmak izi, agregat admisyon planı, artefakt KAPSAMI, kurulan
  # globals kaydı). Explicit-mode özyinelemeli genişletme YAPMADIĞI için bunlar
  # açıkça taşınmalıdır; eksik biri offline hiçbir testi kırmaz ama TEMİZ bir
  # PSOCK işçisi ham "could not find function" ile ölür.
  # PAKET KAPALILIĞI ayrıca `test-pk-async-hardening-behavior.R` içinde
  # çağrı grafiği gezilerek kanıtlanır; buradaki sınır yalnızca "boru hattının
  # tamamı taşınmasın" korumasıdır.
  expect_true(length(ilk) < 56L)
  expect_true("pk_async_worker_bootstrap" %in% names(ilk))
  expect_true("bootstrap_files" %in% names(ilk))
  expect_false("pk_analiz_process_request" %in% names(ilk))
  expect_false("select_smart_query" %in% names(ilk))
})

# --- Asenkron uygunluk --------------------------------------------------------

test_that("MERGEN_PK_ASYNC varsayılan KAPALI ve motor bayrağından BAĞIMSIZDIR", {
  eski_async <- Sys.getenv("MERGEN_PK_ASYNC", unset = NA_character_)
  eski_engine <- Sys.getenv("MERGEN_PK_ENGINE", unset = NA_character_)
  on.exit({
    if (is.na(eski_async)) Sys.unsetenv("MERGEN_PK_ASYNC") else Sys.setenv(MERGEN_PK_ASYNC = eski_async)
    if (is.na(eski_engine)) Sys.unsetenv("MERGEN_PK_ENGINE") else Sys.setenv(MERGEN_PK_ENGINE = eski_engine)
  }, add = TRUE)

  Sys.unsetenv("MERGEN_PK_ASYNC")
  expect_false(pk_async_enabled())

  # Motoru v2 yapmak asenkronu AÇMAZ (ayrı kill switch).
  Sys.setenv(MERGEN_PK_ENGINE = "v2")
  expect_false(pk_async_enabled())

  Sys.setenv(MERGEN_PK_ASYNC = "true")
  expect_true(pk_async_enabled())

  # ...ve asenkronu açmak motoru v2 YAPMAZ.
  Sys.setenv(MERGEN_PK_ENGINE = "v1")
  expect_true(pk_async_enabled())
  expect_equal(pk_config_resolve("MERGEN_PK_ENGINE"), "v1")
})

test_that("sequential future planında asenkron gönderim UYGUN DEĞİLDİR", {
  skip_if_not_installed("future")

  eski <- Sys.getenv("MERGEN_PK_ASYNC", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_PK_ASYNC") else Sys.setenv(MERGEN_PK_ASYNC = eski)
  }, add = TRUE)

  Sys.setenv(MERGEN_PK_ASYNC = "true")
  future::plan(future::sequential)

  # "Asenkron" çalıştırmak sequential planda işi ANA olay döngüsünde yapmakla
  # AYNI ŞEYDİR; Faz 6'nın tek faydasını yok eder. Senkron yola dönmek DÜRÜSTTÜR.
  expect_false(pk_async_plan_is_async())
  uygun <- pk_async_available()
  expect_false(uygun$available)
  # Faz 6 inceleme düzeltmesi: plan reddi ARTIK NEDENİYLE raporlanır
  # (sequential / tek-işçi / multicore-fork / uzak cluster ayrı ayrı görünür).
  expect_true(grepl("^(plan_|single_worker|remote_cluster|future_plan_not_async)",
                    uygun$reason))
})

test_that("bayrak kapalıyken sebep flag_off olur", {
  eski <- Sys.getenv("MERGEN_PK_ASYNC", unset = NA_character_)
  on.exit({
    if (is.na(eski)) Sys.unsetenv("MERGEN_PK_ASYNC") else Sys.setenv(MERGEN_PK_ASYNC = eski)
  }, add = TRUE)

  Sys.setenv(MERGEN_PK_ASYNC = "false")
  uygun <- pk_async_available()
  expect_false(uygun$available)
  expect_equal(uygun$reason, "flag_off")
})
