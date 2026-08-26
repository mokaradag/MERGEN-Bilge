# ==============================================================================
# Dosya Yolu: tests/testthat/test-pk-room-provenance-guard-behavior.R
# Açıklama: Ortak Oturum (oda) yanıt yolunun SAYISAL KÖKENE karşı doğrulanması.
#
#           Bulgu: oda yolunda `yanit_metni` doğrudan "Analiz Kaynağı" alt
#           bilgisiyle BİRLEŞTİRİLİYOR, `pk_numeric_provenance_apply()`
#           ÇAĞRILMIYORDU. Model uydurma bir sayı ürettiğinde yanıt yine
#           YETKİLİ görünen alt bilgiyle yayımlanıyordu. Tek kullanıcılı yol
#           (`pk_provenance_decorate()`) ile AYNI sözleşme burada da geçerlidir.
#
#           Tamamen ÇEVRİMDIŞI ve DETERMİNİSTİKtir: gerçek DB, LLM, Shiny
#           oturumu, tarayıcı, SSO, ağ veya gizli değer GEREKMEZ.
# ==============================================================================

.pk_oda_env <- function() {
  kok <- resolve_repo_root_for_tests()
  env <- new.env(parent = globalenv())
  env$`%||%` <- function(a, b) if (is.null(a)) b else a

  for (dosya in c("helpers_pk_config.R", "helpers_pk_precision.R",
                  "helpers_pk_packet_stats.R", "helpers_pk_packet_context_facts.R",
                  "helpers_pk_numeric_provenance.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  # Oda kancaları `R/server_chat_engine_dependencies.R` içindeki bir `local()`
  # bloğunda tanımlıdır ve dosyanın tamamı Shiny/DB bağımlılığı taşır. Bu yüzden
  # YALNIZCA ilgili yardımcı bloğu metinden ayıklanıp aynı ortama yüklenir;
  # üretim gövdesi BİREBİR aynıdır (kopyalanmış ikinci bir uygulama YOKTUR).
  ham <- readBin(file.path(kok, "R", "server_chat_engine_dependencies.R"), "raw",
                 file.info(file.path(kok, "R", "server_chat_engine_dependencies.R"))$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  satirlar <- strsplit(gsub("\r\n", "\n", metin, fixed = TRUE), "\n", fixed = TRUE)[[1]]

  bas <- grep("^.pk_hook_room_record <- function", satirlar)[1]
  son <- grep("^.pk_hook_room_footer_publish <- function", satirlar)[1] - 1L
  testthat::expect_true(is.finite(bas) && is.finite(son) && son > bas)

  # `.pk_hook_scalar_text()` aynı dosyanın başka bir yerinde tanımlıdır; sözleşme
  # "skaler metne indirge"dir ve burada aynı davranışla sağlanır.
  env$.pk_hook_scalar_text <- function(x) {
    v <- tryCatch(as.character(x), error = function(e) character(0))
    if (!length(v) || is.na(v[1])) return("")
    v[1]
  }
  eval(parse(text = paste(satirlar[bas:son], collapse = "\n")), envir = env)
  env
}

.pk_oda_olgular <- function(env) {
  list(
    env$pk_fact_record("measure", "KalanIscilik_sa", "sum", 18420.5,
                       list(label = "Kalan İşçilik", unit = "saat", decimals = 1L,
                            capability = "labor.remaining_hours"))
  )
}

.pk_oda_kimlik <- function(olgular) olgular[[1]]$fact_id

test_that("oda alt bilgisi eklenmeden ÖNCE sayısal köken doğrulanır", {
  env <- .pk_oda_env()
  olgular <- .pk_oda_olgular(env)
  kimlik <- .pk_oda_kimlik(olgular)

  # UYDURMA SAYI: olgu 18.420,5 saat; model 99.999,9 saat iddia ediyor.
  yanit <- sprintf("Toplam 99.999,9 saat [fact:%s].", kimlik)
  alt_bilgi <- "\n\n---\nAnaliz Kaynağı: sentetik"

  sonuc <- env$.pk_hook_room_footer_append(
    yanit,
    list(footer = alt_bilgi, facts = olgular, mode = "block",
         fallback_text = "SENTETIK DETERMINISTIK OZET", query_id = "q-oda")
  )

  # `block` kipinde ham düzyazı TESLİM EDİLMEZ.
  expect_false(grepl("99.999,9", sonuc, fixed = TRUE))
  expect_true(grepl("SENTETIK DETERMINISTIK OZET", sonuc, fixed = TRUE))
  # Alt bilgi yine eklenir (kaynak şeffaflığı korunur).
  expect_true(grepl("Analiz Kaynağı", sonuc, fixed = TRUE))
  # Referans işareti kullanıcıya SIZMAZ.
  expect_false(grepl("[fact:", sonuc, fixed = TRUE))
})

test_that("DOĞRU sayı taşıyan oda yanıtı olduğu gibi teslim edilir", {
  env <- .pk_oda_env()
  olgular <- .pk_oda_olgular(env)
  kimlik <- .pk_oda_kimlik(olgular)

  yanit <- sprintf("Toplam 18.420,5 saat [fact:%s].", kimlik)
  alt_bilgi <- "\n\n---\nAnaliz Kaynağı: sentetik"

  sonuc <- env$.pk_hook_room_footer_append(
    yanit,
    list(footer = alt_bilgi, facts = olgular, mode = "block",
         fallback_text = "SENTETIK DETERMINISTIK OZET", query_id = "q-oda")
  )

  expect_true(grepl("18.420,5 saat", sonuc, fixed = TRUE))
  expect_false(grepl("SENTETIK DETERMINISTIK OZET", sonuc, fixed = TRUE))
  expect_true(grepl("Analiz Kaynağı", sonuc, fixed = TRUE))
  expect_false(grepl("[fact:", sonuc, fixed = TRUE))
})

test_that("olgu YOKSA (v1 yolu) davranış DEĞİŞMEZ", {
  env <- .pk_oda_env()
  alt_bilgi <- "\n\n---\nAnaliz Kaynağı: sentetik"

  sonuc <- env$.pk_hook_room_footer_append(
    "Serbest metin yanıt.",
    list(footer = alt_bilgi, facts = NULL, mode = NULL, fallback_text = NULL)
  )
  expect_identical(sonuc, paste0("Serbest metin yanıt.", alt_bilgi))

  # Alt bilgi BOŞSA gövde hiç değiştirilmez.
  expect_identical(
    env$.pk_hook_room_footer_append("Serbest metin yanıt.", list(footer = "")),
    "Serbest metin yanıt."
  )
})

test_that("doğrulayıcı HATA verirse block kipi ham düzyazıyı TESLİM ETMEZ", {
  env <- .pk_oda_env()
  olgular <- .pk_oda_olgular(env)

  # Doğrulayıcı yerel olarak patlatılır: `block` kipi AÇIK başarısız olamaz.
  env$pk_numeric_provenance_apply <- function(...) stop("sentetik doğrulayıcı hatası")
  env$PK_PROVENANCE_BLOCK_REFUSAL_TR <- "SENTETIK RED METNI"

  sonuc <- env$.pk_hook_room_footer_append(
    "Toplam 99.999,9 saat.",
    list(footer = "\n\n---\nAnaliz Kaynağı: sentetik", facts = olgular,
         mode = "block", fallback_text = NULL, query_id = "q-oda")
  )

  expect_false(grepl("99.999,9", sonuc, fixed = TRUE))
  expect_true(grepl("SENTETIK RED METNI", sonuc, fixed = TRUE))
})

test_that("kayıt normalleştirme liste OLMAYAN alt bilgiyi de kabul eder", {
  env <- .pk_oda_env()

  kayit <- env$.pk_hook_room_record("\n\n---\nAnaliz Kaynağı: sentetik")
  expect_identical(kayit$footer, "\n\n---\nAnaliz Kaynağı: sentetik")
  expect_null(kayit$facts)
  expect_null(kayit$mode)

  bos <- env$.pk_hook_room_record(NULL)
  expect_identical(bos$footer, "")
})
