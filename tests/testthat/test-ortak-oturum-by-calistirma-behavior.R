# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-by-calistirma-behavior.R
# Açıklama: Ortak Bilge Yolaç CANLI çalıştırma köprüsü davranış/sözleşme
#           testleri. DB, LLM, CLI, tarayıcı veya ağ GEREKMEZ; saf yardımcılar
#           doğrudan çalıştırılır, akış/yürütme sözleşmeleri statik taranır.
#
# Kapsanan sözleşmeler:
#   - Çalıştırma yan dosyaları (durdurma bayrağı + ilerleme) oda-kapsamlı ve
#     yol-enjeksiyonuna kapalıdır.
#   - Akış parçaları (parse_streaming_chunk biçimi) ilerleme kayıtlarına,
#     kayıtlar tüm katılımcılara yayınlanan kısa canlı metne çevrilir.
#   - Proje dizini olarak web adresi (http/https) açık mesajla reddedilir.
#   - run_claude_code_streaming durdurma bayrak dosyasını ve çalışma anı API
#     anahtarı enjeksiyonunu destekler.
#   - BilgeYolaç odası normal sohbet LLM'ine SESSİZCE DÜŞMEZ: CLI yokken açık
#     engelleyici mesaj verilir; kilit bırakılır; komut sohbette kalır.
#   - Model/proje dizini değişimi CLI devam (resume) bağlamını sıfırlar.
#   - Kompozerde BY odası için genel model menüsü yerine model katmanları
#     (Hızlı/Dengeli/Güçlü) çizilir; persona seçici BY odasında çizilmez.
# ==============================================================================

testthat::skip_if_not_installed("shiny")
testthat::skip_if_not_installed("jsonlite")

suppressPackageStartupMessages(library(shiny))

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  source(file.path(repo_root, "R", "helpers_ortak_oturum_by_calisma_alani.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "helpers_ortak_oturum_by_akis.R"),
         encoding = "UTF-8", local = globalenv())
})

.oo_by_cal_oku <- function(rel_path) {
  yol <- file.path(resolve_repo_root_for_tests(), rel_path)
  baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
  iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
}

# ------------------------------------------------------------------------------
# Yan dosyalar (durdurma + ilerleme)
# ------------------------------------------------------------------------------

test_that("çalıştırma yan dosyaları oda köküne yazılır ve istek kimliği temizlenir", {
  oda_koku <- file.path(tempdir(), sprintf("oo_by_cal_kok_%d", sample.int(99999L, 1L)))
  dir.create(oda_koku, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(oda_koku, recursive = TRUE, force = TRUE), add = TRUE)

  onceki <- if (exists("ortak_oturum_dosya_koku", inherits = TRUE)) {
    get("ortak_oturum_dosya_koku", inherits = TRUE)
  } else {
    NULL
  }
  on.exit({
    if (is.null(onceki)) {
      suppressWarnings(rm("ortak_oturum_dosya_koku", envir = globalenv()))
    } else {
      assign("ortak_oturum_dosya_koku", onceki, envir = globalenv())
    }
  }, add = TRUE)
  assign("ortak_oturum_dosya_koku", function(oturum_id) oda_koku, envir = globalenv())

  durdur <- ortak_by_calistirma_yan_dosyasi(42L, "oo_42_20260711_9", "durdur")
  ilerleme <- ortak_by_calistirma_yan_dosyasi(42L, "oo_42_20260711_9", "ilerleme")

  expect_true(startsWith(durdur, oda_koku))
  expect_true(startsWith(ilerleme, oda_koku))
  expect_true(grepl("\\.oo_by_durdur_", durdur))
  expect_true(grepl("\\.oo_by_ilerleme_.*\\.jsonl$", ilerleme))

  # Yol enjeksiyonu: ayraç/İşletim sistemi karakterleri istek kimliğinden ayıklanır.
  saldiri <- ortak_by_calistirma_yan_dosyasi(42L, "../../etc/passwd", "durdur")
  expect_false(grepl("\\.\\.", saldiri))
  expect_true(startsWith(saldiri, oda_koku))

  # Boş/temizlenince boş kalan kimlik: yan dosya üretilmez.
  expect_identical(ortak_by_calistirma_yan_dosyasi(42L, "", "durdur"), "")
  expect_identical(ortak_by_calistirma_yan_dosyasi(42L, "!!!", "ilerleme"), "")
})

# ------------------------------------------------------------------------------
# İlerleme kayıtları ve canlı metin
# ------------------------------------------------------------------------------

test_that("akış parçaları ilerleme kayıtlarına çevrilir (metin + araç)", {
  # Metin deltası
  metin <- oo_by_ilerleme_kayitlari(list(tip = "text_delta", icerik = "Merhaba"))
  expect_length(metin, 1L)
  expect_identical(metin[[1]]$t, "metin")
  expect_identical(metin[[1]]$v, "Merhaba")

  # Araç kullanımı: tür başlığa, komut ayrıntıya gider.
  arac <- oo_by_ilerleme_kayitlari(list(
    tip = "tool_use", arac_adi = "Bash", arac_turu = "bash",
    komut = "npm test", dosya_yolu = "", girdi = list()
  ))
  expect_length(arac, 1L)
  expect_identical(arac[[1]]$t, "arac")
  expect_identical(arac[[1]]$v, "Kabuk Komutu")
  expect_identical(arac[[1]]$d, "npm test")

  # Dosya yazma: yol ayrıntıya düşer; girdi listesinden de çözülür.
  yaz <- oo_by_ilerleme_kayitlari(list(
    tip = "tool_use", arac_adi = "Write", arac_turu = "file_write",
    komut = "", dosya_yolu = "", girdi = list(file_path = "rapor.md")
  ))
  expect_identical(yaz[[1]]$v, "Dosya Yazma")
  expect_identical(yaz[[1]]$d, "rapor.md")

  # Asistan toplu bloğu: içindeki tool_use kayıtları yayınlanır.
  toplu <- oo_by_ilerleme_kayitlari(list(
    tip = "assistant",
    bloklar = list(
      list(tip = "tool_use", arac_adi = "Read", arac_turu = "file_read",
           komut = "", dosya_yolu = "app.R", girdi = list()),
      list(tip = "tool_result", arac_id = "x", icerik = "ok")
    )
  ))
  expect_length(toplu, 1L)
  expect_identical(toplu[[1]]$v, "Dosya Okuma")

  # Görüntülenmeyen parçalar boş döner.
  expect_length(oo_by_ilerleme_kayitlari(list(tip = "message_start", model = "m")), 0L)
  expect_length(oo_by_ilerleme_kayitlari(NULL), 0L)
})

test_that("stream-json araç girdisi deltaları tamamlanmış komut ayrıntısıyla yayınlanır", {
  durum <- new.env(parent = emptyenv())
  durum$araclar <- list()

  baslangic <- oo_by_ilerleme_kayitlari(list(
    tip = "tool_use", arac_adi = "Bash", arac_turu = "bash",
    komut = "", dosya_yolu = "", girdi = list(), blok_indeks = 2L
  ), durum = durum)
  expect_length(baslangic, 0L)

  expect_length(oo_by_ilerleme_kayitlari(list(
    tip = "tool_input_delta", parcali_json = '{"command":"npm ', blok_indeks = 2L
  ), durum = durum), 0L)
  expect_length(oo_by_ilerleme_kayitlari(list(
    tip = "tool_input_delta", parcali_json = 'test"}', blok_indeks = 2L
  ), durum = durum), 0L)

  bitis <- oo_by_ilerleme_kayitlari(list(
    tip = "content_block_stop", blok_indeks = 2L
  ), durum = durum)
  expect_length(bitis, 1L)
  expect_identical(bitis[[1]]$v, "Kabuk Komutu")
  expect_identical(bitis[[1]]$d, "npm test")
})

test_that("canlı ilerleme metni araç satırları + metin kuyruğunu sınırlı üretir", {
  kayit_json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))

  satirlar <- c(
    kayit_json(list(t = "arac", v = "Kabuk Komutu", d = "ls -la")),
    kayit_json(list(t = "metin", v = "Dosyaları inceliyorum. ")),
    kayit_json(list(t = "arac", v = "Dosya Yazma", d = "rapor.md")),
    kayit_json(list(t = "metin", v = "Rapor hazır."))
  )

  metin <- oo_by_kismi_ilerleme_metni(satirlar)
  expect_true(grepl("> Kabuk Komutu: ls -la", metin, fixed = TRUE))
  expect_true(grepl("> Dosya Yazma: rapor.md", metin, fixed = TRUE))
  expect_true(grepl("Rapor hazır.", metin, fixed = TRUE))

  # Araç satırları metinden önce gelir (terminal dili).
  expect_true(
    regexpr("> Kabuk Komutu", metin, fixed = TRUE) <
      regexpr("Rapor hazır", metin, fixed = TRUE)
  )

  # Uzun metin kuyruktan kırpılır (ön izleme sınırı) ve bozuk satırlar atlanır.
  uzun <- oo_by_kismi_ilerleme_metni(c(
    "bozuk json {",
    kayit_json(list(t = "metin", v = paste(rep("abcde ", 300L), collapse = "")))
  ), metin_limit = 100L)
  expect_true(nchar(uzun) <= 140L)
  expect_true(startsWith(uzun, "…"))

  expect_identical(oo_by_kismi_ilerleme_metni(character(0)), "")
})

# ------------------------------------------------------------------------------
# Proje dizini doğrulaması: web adresi reddi
# ------------------------------------------------------------------------------

test_that("web adresi proje dizini olarak açık mesajla reddedilir", {
  for (aday in c("https://mergen.aselsan.com.tr/bilge", "http://ornek.local/proje", "HTTPS://x")) {
    engel <- ortak_by_ozel_dizin_engeli(aday, 42L, yonetilen_kokler = character(0))
    expect_true(is.character(engel), info = aday)
    expect_true(grepl("web adresi", engel, fixed = TRUE), info = aday)
    expect_true(grepl("klasör yolu", engel, fixed = TRUE), info = aday)
  }
})

# ------------------------------------------------------------------------------
# Akış çalıştırıcısı: durdurma bayrağı + API anahtarı enjeksiyonu
# ------------------------------------------------------------------------------

test_that("run_claude_code_streaming durdurma bayrağı ve API anahtarı sözleşmesini taşır", {
  akis <- .oo_by_cal_oku("R/helpers_claude_code_streaming.R")

  expect_true(grepl("stop_file = NULL", akis, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("api_key = NULL", akis, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("stopped = TRUE", akis, fixed = TRUE, useBytes = TRUE))
  # Durdurma yalnızca GERÇEK dosyayla tetiklenir (dizin/boş yol durdurmaz).
  expect_true(grepl("file.exists(yol) && !dir.exists(yol)", akis, fixed = TRUE, useBytes = TRUE))
  # Anahtar alt süreç ortamına run_claude_code ile aynı sözleşmeyle enjekte edilir.
  expect_true(grepl("cc_apply_runtime_api_key_env(komut$env, api_key)", akis, fixed = TRUE, useBytes = TRUE))
})

# ------------------------------------------------------------------------------
# Köprü: gerçek ajan yürütmesi + sessiz düşüş yasağı + çok kullanıcılı yayın
# ------------------------------------------------------------------------------

test_that("BY köprüsü gerçek akış boru hattını kullanır ve ilerlemeyi odaya yayınlar", {
  kopru <- .oo_by_cal_oku("R/module_ortak_oturum_by_calistirma.R")

  # Gerçek kodlama-ajanı boru hattı: run_claude_code (blok, akışsız) DEĞİL,
  # stream-json akış çalıştırıcısı kullanılır.
  expect_true(grepl("run_claude_code_streaming(", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("stop_file = durdurma_dosyasi", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("on_chunk = function(parca)", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo_by_ilerleme_kayitlari(parca, durum = ilerleme_durumu)", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ilerleme_durumu", kopru, fixed = TRUE, useBytes = TRUE))

  # Canlı ilerleme KismiYanit üzerinden TÜM katılımcılara yayınlanır.
  expect_true(grepl("ortak_db_uretim_kismi_yanit_guncelle", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo_by_kismi_ilerleme_metni", kopru, fixed = TRUE, useBytes = TRUE))

  # Tamamlama kalıcılığı hata verirse üretim kilidi asılı kalmamalı; callback
  # açık hata mesajıyla motor$tamamla yoluna düşer.
  expect_true(grepl("Çalıştırma tamamlama hatası", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("sonuç kaydı güvenli biçimde işlenemedi; kilit bırakıldı", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("Başarısız çalıştırma kaydı yazılamadı", kopru, fixed = TRUE, useBytes = TRUE))

  # CLI yolu NA dönerse nzchar(NA) ile üretim callback'i kırılmamalı.
  expect_true(grepl("is.na(cli) || !nzchar(cli)", kopru, fixed = TRUE, useBytes = TRUE))

  # CLI yokken açık engelleyici mesaj + yeniden deneme yolu (sessiz düşüş yok).
  expect_true(grepl(enc2utf8("Claude Code CLI bu ortamda bağlı değil; Bilge Yolaç komutu çalıştırılamadı."),
                    kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("yeniden gönderebilirsiniz"), kopru, fixed = TRUE, useBytes = TRUE))

  # Durdurulan çalıştırma Durduruldu durumuyla kaydedilir ve odaya bildirilir.
  expect_true(grepl('"Durduruldu"', kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("çalıştırması durduruldu"), kopru, fixed = TRUE, useBytes = TRUE))

  # Durdurma yetkisi sunucu tarafında yeniden doğrulanır (fail-closed).
  expect_true(grepl("ortak_db_aktif_uretim_detay", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('ortak_yetki_var_mi(katilim$Rol[1], "katilimci_yonet")', kopru, fixed = TRUE, useBytes = TRUE))
})

test_that("BilgeYolaç odası normal sohbet LLM'ine sessizce düşmez", {
  yz <- .oo_by_cal_oku("R/module_ortak_oturum_yz.R")

  # BY dalı: köprü yoksa/başlatamadıysa motor$tamamla ile açık hata; llm_uret
  # BY dalının içinde ÇAĞRILMAZ. Konum + substr KARAKTER tabanlıdır (useBytes
  # bayt ofsetleri Türkçe metinle kayar; repo test kuralı).
  by_dal_baslangic <- regexpr("if (by_odasi) {", yz, fixed = TRUE)
  by_dal_bitis <- regexpr("motor$llm_uret(oturum_id, soru_id, soran_id, istek_id, kuyruk_id, persona_kimligi)",
                          yz, fixed = TRUE)
  expect_true(by_dal_baslangic > 0 && by_dal_bitis > by_dal_baslangic)
  by_dal <- substr(yz, by_dal_baslangic, by_dal_bitis - 1L)
  expect_false(grepl("llm_uret", by_dal, fixed = TRUE))
  expect_true(grepl("ortak_by_kopru_kullanilamiyor_mesaji()", by_dal, fixed = TRUE))
  expect_true(grepl("return(invisible(NULL))", by_dal, fixed = TRUE))

  # Engelleyici mesaj metni saf yardımcıdadır ve yeniden deneme yolunu anlatır.
  mesaj <- ortak_by_kopru_kullanilamiyor_mesaji()
  expect_true(grepl(enc2utf8("çalıştırma köprüsü bu oturumda kullanılamıyor"), mesaj, fixed = TRUE))
  expect_true(grepl(enc2utf8("yeniden gönderebilirsiniz"), mesaj, fixed = TRUE))

  # Üretim paneli BY odasında Durdur kancasını ve ajan yüzeyi sınıfını taşır.
  expect_true(grepl("motor$by_durdur_ui", yz, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo-kismi-yanit-by", yz, fixed = TRUE, useBytes = TRUE))
})

# ------------------------------------------------------------------------------
# Model katmanları + oturum bağlamı sıfırlama + kompozer kapıları
# ------------------------------------------------------------------------------

test_that("model/proje dizini değişimi CLI devam bağlamını sıfırlar ve odaya bildirilir", {
  modul <- .oo_by_cal_oku("R/module_ortak_oturum_bilge_yolac.R")

  # Model değişimi: model + cli_session_id birlikte güncellenir + sistem notu.
  expect_true(grepl('ortak_db_by_oturum_guncelle(oturum_id, model = deger, cli_session_id = "")',
                    modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Bilge Yolaç modeli değiştirildi"), modul, fixed = TRUE, useBytes = TRUE))

  # Dizin uygula/sıfırla: cli_session_id sıfırlanır.
  expect_true(grepl('cli_session_id = ""', modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("ajan konuşma bağlamı yeni dizinle yeniden başlar"),
                    modul, fixed = TRUE, useBytes = TRUE))

  # Dizin içeriği: erişilemeyen dizin ile boş dizin ayrı mesajlardır.
  expect_true(grepl(enc2utf8("Dizin içeriği okunamadı"), modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Çalışma alanı henüz boş"), modul, fixed = TRUE, useBytes = TRUE))
})

test_that("BY odasında kompozer genel model menüsü yerine katmanları, persona seçiciyi ise hiç çizmez", {
  arac <- .oo_by_cal_oku("R/module_ortak_oturum_arac.R")
  expect_true(grepl("motor$by_model_secici_ui", arac, fixed = TRUE, useBytes = TRUE))

  # Konum + substr KARAKTER tabanlıdır (useBytes ofsetleri Türkçe ile kayar).
  oda <- .oo_by_cal_oku("R/module_ortak_oturum_room.R")
  persona_baslangic <- regexpr("output$oda_persona_secim_alani <- renderUI({", oda, fixed = TRUE)
  expect_true(persona_baslangic > 0)
  persona_blok <- substr(oda, persona_baslangic, persona_baslangic + 700L)
  expect_true(grepl(enc2utf8('"BilgeYolaç"'), persona_blok, fixed = TRUE))
  expect_true(grepl("return(NULL)", persona_blok, fixed = TRUE))

  # Kompozer katman grubu tek kullanıcılı katman üreticisine delege eder.
  kopru <- .oo_by_cal_oku("R/module_ortak_oturum_by_calistirma.R")
  expect_true(grepl("oo_by_model_govde_html", kopru, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo-by-composer-model", kopru, fixed = TRUE, useBytes = TRUE))
})

test_that("çalıştırma geçmişi Durduruldu durumunu ayrı rozetle gösterir", {
  gecmis <- data.frame(
    CalistirmaSirasi = c(1L, 2L),
    Durum = c("Durduruldu", "Tamamlandı"),
    Komut = c("uzun bir görev", "kısa görev"),
    KomutuVerenAdi = c("Mehmet", "Ayşe"),
    SureSaniye = c(12.5, 3.2),
    stringsAsFactors = FALSE
  )

  html <- paste(format(oo_by_gecmis_listesi_html(gecmis)), collapse = "\n")
  expect_true(grepl("oo-by-durum-durduruldu", html, fixed = TRUE))
  expect_true(grepl("Durduruldu", html, fixed = TRUE))
})
