# ==============================================================================
# Dosya Yolu: tests/testthat/test-ortak-oturum-arac-behavior.R
# Açıklama: Ortak Oturum araç seçici katmanının davranış testleri. Sentetik
#           araç yapılandırmasıyla (gerçek üretim model adları KULLANILMAZ)
#           çalışır; DB, LLM, tarayıcı veya ağ GEREKMEZ.
#
# Kapsanan sözleşmeler:
#   - Katalog tool_mode_config'ten türetilir; Görsel Oluşturma ortak odalarda
#     desteklenmez olarak işaretlenir.
#   - Araç ayarları soru MetaJson'una yazılır ve kayıpsız geri okunur.
#   - Üretim planı: sql/langflow/normal yol ayrımı, Derin Düşünme model
#     çözümü (mcp_excel/coding), özetleme sistem notu, langflow'da belge
#     bağlamının kapatılması.
#   - Seçici/rozet HTML üreticileri: ayar blokları, devre dışı araç, model
#     kilidi işaretleri, XSS escape ve JS string literal (toJSON) kodlaması.
#   - Proje/Kaynak Analizi köprüsü: karakter dönüşü doğrudan yanıt, liste
#     dönüşü sistem/kullanıcı bağlamı, Derin Düşünme'nin derin boru hattına
#     yönlenmesi.
#   - Statik kablolama: oda UI/sunucu ve JS köprüsü yeni yüzeyleri taşır.
# ==============================================================================

testthat::skip_if_not_installed("shiny")
testthat::skip_if_not_installed("jsonlite")

suppressPackageStartupMessages(library(shiny))

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("%||%", mode = "function", inherits = TRUE)) {
    `%||%` <<- function(a, b) if (is.null(a)) b else a
  }

  if (!exists("get_tool_mode_config", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_api_model_tool_runtime.R"),
           encoding = "UTF-8", local = globalenv())
  }

  source(file.path(repo_root, "R", "helpers_ortak_oturum_arac.R"),
         encoding = "UTF-8", local = globalenv())
  source(file.path(repo_root, "R", "module_ortak_oturum_arac.R"),
         encoding = "UTF-8", local = globalenv())
})

# Sentetik araç yapılandırması: gerçek üretim model adları kullanılmaz.
.oo_arac_test_config <- function() {
  list(
    local_models = c("Model Bir" = "model-bir", "Model İki" = "model-iki"),
    tool_mode_config = list(
      sql_analysis = list(
        family = "sql_analysis", setting_flag = "enable_rdata_tools",
        quick_action_id = "resource-analysis", title = "Proje ve Kaynak Analizi",
        description = "Kaynak verilerini analiz edin.", icon_name = "chart-bar",
        themeColor = "#06b6d4", model_id = "model-sql", real_tool = TRUE
      ),
      mcp_excel = list(
        family = "mcp_excel", setting_flag = "enable_mcp_tools",
        quick_action_id = "excel-analysis", title = "Excel Analizi",
        description = "Excel veri setlerini analiz edin.", icon_name = "file-excel",
        themeColor = "#10b981", model_id = "model-excel", real_tool = TRUE
      ),
      coding = list(
        family = "coding", setting_flag = "enable_coding_tools",
        quick_action_id = "coding-support", title = "Kodlama Desteği",
        description = "Kod desteği alın.", icon_name = "code",
        themeColor = "#f59e0b", model_id = "model-kod", real_tool = FALSE
      ),
      image = list(
        family = "image", setting_flag = "enable_image_tools",
        quick_action_id = "image-creation", title = "Görsel Oluşturma",
        description = "Görsel üretin.", icon_name = "image",
        themeColor = "#ec4899", model_id = "model-gorsel", real_tool = TRUE
      ),
      process = list(
        family = "process", setting_flag = "enable_process_tools",
        quick_action_id = "project-process", title = "Süreç Yönetimi Sistemi",
        description = "Kurumsal süreç akışları.", icon_name = "briefcase",
        themeColor = "#3b82f6", runtime = "langflow", real_tool = TRUE
      ),
      summarization = list(
        family = "summarization", setting_flag = "enable_summarization_tools",
        quick_action_id = "summarization", title = "Özetleme Desteği",
        description = "Belgeleri özetleyin.", icon_name = "file-alt",
        themeColor = "#6366f1", model_id = "model-ozet", real_tool = TRUE
      )
    ),
    deep_thinking_models = list(
      mcp_excel = list(low = "excel-derin-dusuk", high = "excel-derin-yuksek"),
      coding = list(low = "kod-derin-dusuk", high = "kod-derin-yuksek")
    ),
    langflow = list(
      base_url = "http://langflow.example.internal",
      api_key = "",
      timeout_seconds = 60,
      process_flow_ids_raw = "akis-id-1;akis-id-2",
      process_flow_names_raw = "Satın Alma;İşe Alım",
      process_flow_legacy_id = "",
      flow_ids = list(app_expert = "uygulama-akisi")
    )
  )
}

test_that("katalog tool_mode_config'ten türetilir ve görsel aracı devre dışıdır", {
  katalog <- oo_arac_katalogu(.oo_arac_test_config())

  aileler <- vapply(katalog, function(g) g$family, character(1))
  expect_setequal(
    aileler,
    c("sql_analysis", "mcp_excel", "coding", "image", "process", "summarization")
  )

  gorsel <- katalog[[which(aileler == "image")]]
  expect_false(gorsel$destekleniyor)

  sql <- katalog[[which(aileler == "sql_analysis")]]
  expect_true(sql$derin_var)
  expect_true(sql$detay_var)
  expect_false(sql$seviye_var)

  excel <- katalog[[which(aileler == "mcp_excel")]]
  expect_true(excel$derin_var)
  expect_true(excel$seviye_var)
  expect_false(excel$detay_var)

  surec <- katalog[[which(aileler == "process")]]
  expect_true(surec$akis_var)
  expect_identical(surec$runtime, "langflow")
})

test_that("araç ayarları soru MetaJson'una yazılır ve kayıpsız geri okunur", {
  # Araç yokken metadata üretilmez.
  expect_null(oo_arac_meta_listesi(oo_arac_varsayilan_ayarlar()))

  ayarlar <- list(family = "sql_analysis", derin = TRUE, seviye = "low",
                  detay = "detayli", surec_akisi = "")
  meta <- oo_arac_meta_listesi(ayarlar)
  expect_true(is.list(meta$arac))

  # ortak_db_mesaj_ekle ile aynı serileştirme yolu (jsonlite).
  json <- as.character(jsonlite::toJSON(meta, auto_unbox = TRUE, null = "null"))
  geri <- oo_arac_meta_parse(json)
  expect_identical(geri$family, "sql_analysis")
  expect_true(geri$derin)
  expect_identical(geri$detay, "detayli")

  # Bozuk/boş JSON güvenli varsayılana düşer.
  expect_identical(oo_arac_meta_parse("")$family, "")
  expect_identical(oo_arac_meta_parse("{bozuk json")$family, "")
  expect_identical(oo_arac_meta_parse(NA_character_)$family, "")

  # Persona metadata'sı ile birlikte yaşayabilir (arac alanı ayrı anahtar).
  birlikte <- as.character(jsonlite::toJSON(
    c(list(persona_id = "emre"), meta), auto_unbox = TRUE, null = "null"
  ))
  expect_identical(oo_arac_meta_parse(birlikte)$family, "sql_analysis")
})

test_that("rozet ayar özeti Türkçe ve ayara duyarlıdır", {
  expect_identical(oo_arac_ayar_ozeti(oo_arac_varsayilan_ayarlar()), "")

  sql <- list(family = "sql_analysis", derin = TRUE, detay = "detayli", seviye = "low")
  expect_true(grepl("Derin Düşünme", oo_arac_ayar_ozeti(sql), fixed = TRUE))
  expect_true(grepl("Detay: Detaylı", oo_arac_ayar_ozeti(sql), fixed = TRUE))

  excel <- list(family = "mcp_excel", derin = TRUE, seviye = "high", detay = "standart")
  expect_true(grepl("Derin Düşünme: Yüksek", oo_arac_ayar_ozeti(excel), fixed = TRUE))

  excel_kapali <- list(family = "mcp_excel", derin = FALSE, seviye = "high", detay = "standart")
  expect_identical(oo_arac_ayar_ozeti(excel_kapali), "")
})

test_that("üretim planı yol/model/belge bağlamı kararlarını doğru verir", {
  cfg <- .oo_arac_test_config()

  # Araç yok: normal yol, oda modeli (boş model_id), belge bağlamı açık.
  plan_bos <- oo_arac_uretim_plani(oo_arac_varsayilan_ayarlar(), config = cfg)
  expect_identical(plan_bos$yol, "normal")
  expect_identical(plan_bos$model_id, "")
  expect_true(plan_bos$belge_baglami)

  # sql_analysis: sql yolu + araç modeli.
  plan_sql <- oo_arac_uretim_plani(
    list(family = "sql_analysis", derin = TRUE, detay = "ozet", seviye = "low"),
    config = cfg
  )
  expect_identical(plan_sql$yol, "sql")
  expect_identical(plan_sql$model_id, "model-sql")
  expect_true(plan_sql$derin)
  expect_identical(plan_sql$detay, "ozet")

  # Langflow aracı: langflow yolu; belge bağlamı akışa enjekte edilmez.
  plan_lf <- oo_arac_uretim_plani(list(family = "process", surec_akisi = "flow_2"), config = cfg)
  expect_identical(plan_lf$yol, "langflow")
  expect_false(plan_lf$belge_baglami)

  # mcp_excel: Derin Düşünme kapalıyken araç modeli, açıkken derin model.
  plan_excel <- oo_arac_uretim_plani(list(family = "mcp_excel", derin = FALSE), config = cfg)
  expect_identical(plan_excel$model_id, "model-excel")

  plan_excel_derin <- oo_arac_uretim_plani(
    list(family = "mcp_excel", derin = TRUE, seviye = "high"), config = cfg
  )
  expect_identical(plan_excel_derin$model_id, "excel-derin-yuksek")

  # coding: derin düşük seviye modeli.
  plan_kod <- oo_arac_uretim_plani(
    list(family = "coding", derin = TRUE, seviye = "low"), config = cfg
  )
  expect_identical(plan_kod$model_id, "kod-derin-dusuk")

  # summarization: özet sistem notu taşır.
  plan_ozet <- oo_arac_uretim_plani(list(family = "summarization"), config = cfg)
  expect_true(nzchar(plan_ozet$sistem_notu))
  expect_identical(plan_ozet$model_id, "model-ozet")

  # Desteklenmeyen (image) ve bilinmeyen aile araçsız plana düşer.
  expect_identical(oo_arac_uretim_plani(list(family = "image"), config = cfg)$family, "")
  expect_identical(oo_arac_uretim_plani(list(family = "olmayan"), config = cfg)$family, "")
})

test_that("araç seçici HTML: ayar blokları, devre dışı araç, escape ve toJSON kodlaması", {
  cfg <- .oo_arac_test_config()
  katalog <- oo_arac_katalogu(cfg)

  ayarlar <- list(family = "sql_analysis", derin = TRUE, seviye = "low",
                  detay = "detayli", surec_akisi = "")

  html <- as.character(oo_arac_secici_html(
    katalog, ayarlar,
    dropdown_id = "test_dd",
    secim_input_id = "mod-oda_arac_secimi",
    ayar_input_id = "mod-oda_arac_ayari"
  ))

  expect_true(grepl("Analiz Araçları", html, fixed = TRUE))
  expect_true(grepl("Proje ve Kaynak Analizi", html, fixed = TRUE))
  expect_true(grepl("Araç Kullanma", html, fixed = TRUE))

  # Aktif araç ayar blokları: Derin Düşünme + Detay Seviyesi (seçili değer işaretli).
  expect_true(grepl("Derin Düşünme", html, fixed = TRUE))
  expect_true(grepl("Detay Seviyesi", html, fixed = TRUE))
  expect_true(grepl('data-oo-alan="derin"', html, fixed = TRUE))
  expect_true(grepl('data-oo-alan="detay"', html, fixed = TRUE))
  expect_true(grepl('data-oo-hedef-input="mod-oda_arac_ayari"', html, fixed = TRUE))

  # Görsel aracı devre dışı satır olarak listelenir.
  expect_true(grepl("oo-arac-devredisi", html, fixed = TRUE))
  expect_true(grepl("ortak oturumlarda desteklenmez", html, fixed = TRUE))

  # Seçim onclick'i girdi adını/values'u JS string literaline kodlar (öznitelik
  # içinde çift tırnak &quot; olarak render edilir; ham enterpolasyon YOKTUR).
  expect_true(grepl(
    "Shiny.setInputValue(&quot;mod-oda_arac_secimi&quot;, &quot;sql_analysis&quot;",
    html, fixed = TRUE
  ))

  # XSS sınırı: kötü niyetli araç başlığı ham HTML olarak DOM'a giremez.
  kirli <- katalog
  kirli[[1]]$baslik <- "<script>alert(1)</script>"
  kirli_html <- as.character(oo_arac_secici_html(
    kirli, oo_arac_varsayilan_ayarlar(),
    dropdown_id = "test_dd2",
    secim_input_id = "a", ayar_input_id = "b"
  ))
  expect_false(grepl("<script>alert(1)</script>", kirli_html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", kirli_html, fixed = TRUE))
})

test_that("araç rozeti aktif aracı, ayar özetini ve temizleme düğmesini taşır", {
  katalog <- oo_arac_katalogu(.oo_arac_test_config())

  expect_null(oo_arac_rozet_html(katalog, oo_arac_varsayilan_ayarlar(), "mod-temizle"))

  ayarlar <- list(family = "mcp_excel", derin = TRUE, seviye = "high",
                  detay = "standart", surec_akisi = "")
  html <- as.character(oo_arac_rozet_html(katalog, ayarlar, "mod-oda_arac_temizle"))

  expect_true(grepl("Excel Analizi", html, fixed = TRUE))
  expect_true(grepl("Derin Düşünme: Yüksek", html, fixed = TRUE))
  expect_true(grepl('data-oo-hedef-input="mod-oda_arac_temizle"', html, fixed = TRUE))
  expect_true(grepl("data-oo-arac-temizle", html, fixed = TRUE))
})

test_that("Proje/Kaynak Analizi köprüsü tekil oturum sözleşmesini taşır", {
  onceki_tekil <- if (exists("pk_analiz_process_request", inherits = TRUE)) {
    get("pk_analiz_process_request", inherits = TRUE)
  } else {
    NULL
  }
  onceki_derin <- if (exists("pk_deep_analysis_process", inherits = TRUE)) {
    get("pk_deep_analysis_process", inherits = TRUE)
  } else {
    NULL
  }
  on.exit({
    if (is.null(onceki_tekil)) {
      suppressWarnings(rm("pk_analiz_process_request", envir = globalenv()))
    } else {
      assign("pk_analiz_process_request", onceki_tekil, envir = globalenv())
    }
    if (is.null(onceki_derin)) {
      suppressWarnings(rm("pk_deep_analysis_process", envir = globalenv()))
    } else {
      assign("pk_deep_analysis_process", onceki_derin, envir = globalenv())
    }
  }, add = TRUE)

  # Karakter dönüşü (hata/bilgi) doğrudan yanıt olur.
  assign("pk_analiz_process_request", function(user_prompt, chat_history, session, stop_check = NULL) {
    "Analiz kütüphanesinde eşleşme bulunamadı."
  }, envir = globalenv())

  tekil <- oo_arac_sql_baglami_kur(
    "kaynak analizi", list(), NULL,
    list(family = "sql_analysis", derin = FALSE, detay = "standart")
  )
  expect_identical(tekil$dogrudan_yanit, "Analiz kütüphanesinde eşleşme bulunamadı.")

  # Liste dönüşü sistem/kullanıcı bağlamı + max_tokens olur.
  assign("pk_analiz_process_request", function(user_prompt, chat_history, session, stop_check = NULL) {
    list(prompt_context = "VERİ BAĞLAMI", user_context = "Zenginleştirilmiş soru", max_tokens = 4096L)
  }, envir = globalenv())

  liste <- oo_arac_sql_baglami_kur(
    "kaynak analizi", list(), NULL,
    list(family = "sql_analysis", derin = FALSE, detay = "standart")
  )
  expect_identical(liste$sistem, "VERİ BAĞLAMI")
  expect_identical(liste$kullanici, "Zenginleştirilmiş soru")
  expect_identical(liste$max_tokens, 4096L)

  # Derin Düşünme derin boru hattına detay seviyesiyle yönlenir.
  yakalanan <- new.env(parent = emptyenv())
  assign("pk_deep_analysis_process", function(user_prompt, chat_history, session,
                                              detail_level = "standart", stop_check = NULL) {
    yakalanan$detay <- detail_level
    "Derin analiz tamam."
  }, envir = globalenv())

  derin <- oo_arac_sql_baglami_kur(
    "derin analiz", list(), NULL,
    list(family = "sql_analysis", derin = TRUE, detay = "detayli")
  )
  expect_identical(derin$dogrudan_yanit, "Derin analiz tamam.")
  expect_identical(yakalanan$detay, "detayli")

  # error_message tipi liste de doğrudan yanıt olur.
  assign("pk_analiz_process_request", function(user_prompt, chat_history, session, stop_check = NULL) {
    list(type = "error_message", content = "Yetki hatası.")
  }, envir = globalenv())
  hata <- oo_arac_sql_baglami_kur(
    "x", list(), NULL, list(family = "sql_analysis", derin = FALSE, detay = "standart")
  )
  expect_identical(hata$dogrudan_yanit, "Yetki hatası.")
})

test_that("Langflow çağrı hazırlığı akış seçimi ve eksik yapılandırma kurallarını taşır", {
  repo_root <- resolve_repo_root_for_tests()
  if (!exists("mergen_langflow_config", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_langflow_runtime.R"),
           encoding = "UTF-8", local = globalenv())
  }

  cfg <- .oo_arac_test_config()

  plan <- oo_arac_uretim_plani(list(family = "process", surec_akisi = "flow_2"), config = cfg)
  lf <- oo_arac_langflow_cagrisi_hazirla(plan, soran_id = 7L, oturum_id = 42L, config = cfg)

  expect_true(is.list(lf))
  expect_identical(lf$flow_id, "akis-id-2")
  expect_true(grepl("oo_42", lf$session_id, fixed = TRUE))
  expect_true(lf$timeout_seconds > 0)

  # Taban URL eksikse NULL döner (çağıran net Türkçe hata gösterir).
  cfg_bos <- cfg
  cfg_bos$langflow$base_url <- ""
  plan_bos <- oo_arac_uretim_plani(list(family = "process"), config = cfg_bos)
  expect_null(oo_arac_langflow_cagrisi_hazirla(plan_bos, 7L, 42L, config = cfg_bos))
})

test_that("statik kablolama: oda UI/sunucu, üretim motoru ve JS köprüsü yeni yüzeyleri taşır", {
  repo_root <- resolve_repo_root_for_tests()
  oku <- function(yol) {
    baytlar <- readBin(yol, what = "raw", n = file.info(yol)$size)
    iconv(rawToChar(baytlar), from = "UTF-8", to = "UTF-8", sub = "byte")
  }

  oda_ui <- oku(file.path(repo_root, "R", "module_ortak_oturum_room_ui.R"))
  expect_true(grepl("oda_arac_secim_alani", oda_ui, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oda_arac_rozet_alani", oda_ui, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oda_sohbet_temizle_alani", oda_ui, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("belge_yukleme_alani", oda_ui, fixed = TRUE, useBytes = TRUE))

  oda_sunucu <- oku(file.path(repo_root, "R", "module_ortak_oturum_room.R"))
  expect_true(grepl("ortakOturumAracBind", oda_sunucu, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ortakOturumBelgePaneliBind", oda_sunucu, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ortakOturumSohbetTemizleBind", oda_sunucu, fixed = TRUE, useBytes = TRUE))

  arac_modul <- oku(file.path(repo_root, "R", "module_ortak_oturum_arac.R"))
  # Model kilidi: araç etkinken model seçici kilitli görünüme döner.
  expect_true(grepl("oo-secici-kilitli", arac_modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oda_model_secim_alani", arac_modul, fixed = TRUE, useBytes = TRUE))

  temizle_modul <- oku(file.path(repo_root, "R", "module_ortak_oturum_belge_paneli.R"))
  # Sohbeti temizleme açık onay modalı olmadan çalışmaz.
  expect_true(grepl("oda_sohbet_temizle_onay", temizle_modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("showModal", temizle_modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(enc2utf8("Kalıcı Olarak Temizle"), temizle_modul, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ortak_db_sohbet_temizle", temizle_modul, fixed = TRUE, useBytes = TRUE))

  yz_motor <- oku(file.path(repo_root, "R", "module_ortak_oturum_yz.R"))
  expect_true(grepl("meta_ekstra = arac_meta_ekstra", yz_motor, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo_arac_uretim_plani", yz_motor, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("ortak_belge_baglam_sistem_mesaji", yz_motor, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("oo_arac_langflow_uret", yz_motor, fixed = TRUE, useBytes = TRUE))

  js <- oku(file.path(repo_root, "www", "js", "ortak_oturumlar.js"))
  expect_true(grepl("data-oo-arac-ayar", js, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl("data-oo-secim-input", js, fixed = TRUE, useBytes = TRUE))

  # Tema: yeni yüzeyler açık temada da kapsanır.
  css <- oku(file.path(repo_root, "www", "css", "ortak_oturumlar_room.css"))
  expect_true(grepl(".oo-arac-rozet", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(".oo-belge-secim", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl(".oo-secici-kilitli", css, fixed = TRUE, useBytes = TRUE))
  expect_true(grepl('html[data-theme="light"] .oo-arac-rozet', css, fixed = TRUE, useBytes = TRUE))
})
