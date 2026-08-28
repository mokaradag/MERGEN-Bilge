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
                  "helpers_pk_numeric_provenance.R",
                  "helpers_pk_numeric_provenance_claims.R")) {
    source(file.path(kok, "R", dosya), encoding = "UTF-8", local = env)
  }

  # Oda kancaları `R/server_chat_engine_dependencies.R` içindeki bir `local()`
  # bloğunda tanımlıdır ve dosyanın tamamı Shiny/DB bağımlılığı taşır. Bu yüzden
  # YALNIZCA ilgili yardımcı bloğu metinden ayıklanıp aynı ortama yüklenir;
  # üretim gövdesi BİREBİR aynıdır (kopyalanmış ikinci bir uygulama YOKTUR).
  # `.pk_hook_scalar_text()` ARTIK KOPYALANMAZ: üretim tanımı kendi
  # dosyasından (`R/server_init_session_state.R`) aynı çapa tekniğiyle
  # çıkarılır. Yerel bir ikinci uygulama, üretim sözleşmesi değiştiğinde
  # (örneğin boşluk kırpma ya da çok elemanlı girdiyi reddetme) bu muhafızın
  # farkı GÖRMESİNİ engelliyordu.
  .pk_oda_blok_yukle(env, kok, "server_init_session_state.R",
                     "^\\.pk_hook_scalar_text <- function",
                     "^pk_filter_observation_clear <- function",
                     ".pk_hook_scalar_text")

  .pk_oda_blok_yukle(env, kok, "server_chat_engine_dependencies.R",
                     "^\\.pk_hook_room_record <- function",
                     "^\\.pk_hook_room_footer_publish <- function",
                     c(".pk_hook_room_record", ".pk_hook_room_footer_append"))
  env
}

# İki çapa arasındaki ÜRETİM bloğunu ayıklayıp verilen ortama yükler.
#
# `beklenen` adları, ayıklanan bloğun test edilen fonksiyonları GERÇEKTEN
# tanımladığını kanıtlar. Yalnızca çapaların bulunduğunu doğrulamak yetmez:
# bir yeniden düzenleme fonksiyonu aralığın DIŞINA taşırsa ayıklama yine
# başarılı olur, ortamdaki ad `NULL` kalır ve her test sözleşmeyi
# adlandırmak yerine "attempt to apply non-function" ile düşerdi.
#
# Çapa desenleri REGEX'tir; baştaki nokta AÇIKÇA kaçırılır, aksi hâlde `.`
# herhangi bir karakteri (örneğin yorum satırındaki bir karakteri) eşlerdi.
.pk_oda_blok_yukle <- function(env, kok, dosya, bas_capa, son_capa, beklenen) {
  yol <- file.path(kok, "R", dosya)
  ham <- readBin(yol, "raw", file.info(yol)$size)
  metin <- iconv(rawToChar(ham), from = "UTF-8", to = "UTF-8", sub = "byte")
  # CRLF NORMALLEŞTİRİLİR: `.gitattributes` yalnızca TAZE checkout'u düzeltir,
  # çalışma kopyasındaki bir dosyayı yeniden yazmaz.
  satirlar <- strsplit(gsub("\r\n?", "\n", metin), "\n", fixed = TRUE)[[1]]

  bas <- grep(bas_capa, satirlar)[1]
  son_capa_satiri <- grep(son_capa, satirlar)[1]
  son <- son_capa_satiri - 1L

  # ÇIKARIM `eval()`'DEN ÖNCE DURUR. `grep(...)[1]` bulunamayınca `NA` döner;
  # testthat 3e'de başarısız bir beklenti gövdeyi DURDURMADIĞI için
  # `satirlar[bas:son]` OPAK bir indeks hatasıyla düşerdi.
  if (!isTRUE(is.finite(bas) && is.finite(son) && son > bas)) {
    stop(sprintf("Blok cikarimi basarisiz (%s): capalar bulunamadi.", dosya),
         call. = FALSE)
  }

  eval(parse(text = paste(satirlar[bas:son], collapse = "\n")), envir = env)

  eksik <- beklenen[!vapply(
    beklenen,
    function(ad) exists(ad, envir = env, mode = "function", inherits = FALSE),
    logical(1)
  )]
  if (length(eksik)) {
    stop(sprintf("Ayiklanan blok (%s) su fonksiyonlari TANIMLAMIYOR: %s",
                 dosya, paste(eksik, collapse = ", ")),
         call. = FALSE)
  }
  invisible(TRUE)
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
