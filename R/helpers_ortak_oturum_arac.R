# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_arac.R
# Açıklama: Ortak Oturum araç seçici SAF karar yardımcıları: Yapılandırma >
#           Analiz Araçları kataloğu (api_config$tool_mode_config tek kaynak),
#           araç ayar durumu / soru MetaJson gidiş-dönüşü, rozet ayar özeti,
#           üretim planı (model + yürütme yolu çözümü), Proje/Kaynak Analizi
#           boru hattı köprüsü ve Langflow worker üretimi. UI üreticileri ve
#           sunucu bağlayıcısı R/module_ortak_oturum_arac.R içindedir.
#
# Sözleşmeler:
#   * Araç kataloğu TEK kaynaktan okunur (api_config$tool_mode_config);
#     burada araç tanımı ÇOĞALTILMAZ.
#   * Derin Düşünme ayarları resolve_runtime_model_for_request üzerinden
#     modele yansır (mcp_excel/coding); sql_analysis derin modu pk boru
#     hattında çözülür. Görsel Oluşturma ortak odalarda desteklenmez.
#   * Araç seçimi soru mesajının MetaJson'una yazılır; kalıcı kuyruk bir
#     soruyu sonra devraldığında da aynı araç bağlamı uygulanır.
# ==============================================================================

# Ortak odalarda çalıştırılabilir araç aileleri. Görsel üretimi metin-dışı
# çıktı ürettiği için bilinçli olarak devre dışıdır.
.oo_arac_desteklenmeyenler <- c("image")

# Yapılandırma > Analiz Araçları kataloğu (SAF). Her giriş: family, baslik,
# aciklama, ikon, renk, runtime, destekleniyor, ayar şeması bayrakları.
oo_arac_katalogu <- function(config = NULL) {
  if (is.null(config) && exists("api_config", inherits = TRUE)) {
    config <- get("api_config", inherits = TRUE)
  }
  cfgs <- if (is.list(config)) config$tool_mode_config %||% list() else list()

  girisler <- lapply(cfgs, function(cfg) {
    family <- as.character(cfg$family %||% "")[1]
    if (!nzchar(family)) {
      return(NULL)
    }

    list(
      family = family,
      baslik = as.character(cfg$title %||% family)[1],
      aciklama = as.character(cfg$description %||% "")[1],
      ikon = as.character(cfg$icon_name %||% "bolt")[1],
      renk = as.character(cfg$themeColor %||% "#6366f1")[1],
      runtime = as.character(cfg$runtime %||% "local")[1],
      model_id = as.character(cfg$model_id %||% "")[1],
      destekleniyor = !(family %in% .oo_arac_desteklenmeyenler),
      derin_var = family %in% c("sql_analysis", "mcp_excel", "coding"),
      detay_var = identical(family, "sql_analysis"),
      seviye_var = family %in% c("mcp_excel", "coding"),
      akis_var = identical(family, "process")
    )
  })

  Filter(Negate(is.null), girisler)
}

# Varsayılan araç durumu: araç yok, ayarlar tekil oturum varsayılanlarıyla.
oo_arac_varsayilan_ayarlar <- function() {
  list(family = "", derin = FALSE, seviye = "low", detay = "standart", surec_akisi = "")
}

# Soru mesajı MetaJson'una yazılacak ek metadata listesi (SAF). Araç yoksa NULL.
oo_arac_meta_listesi <- function(ayarlar) {
  family <- as.character(ayarlar$family %||% "")[1]
  if (!nzchar(family)) {
    return(NULL)
  }

  list(arac = list(
    family = family,
    derin = isTRUE(ayarlar$derin),
    seviye = as.character(ayarlar$seviye %||% "low")[1],
    detay = as.character(ayarlar$detay %||% "standart")[1],
    surec_akisi = as.character(ayarlar$surec_akisi %||% "")[1]
  ))
}

# Soru mesajı MetaJson'undan araç seçimini geri okur (SAF). Bozuk/boş JSON
# güvenli "araç yok" varsayılanına düşer.
oo_arac_meta_parse <- function(meta_json) {
  varsayilan <- oo_arac_varsayilan_ayarlar()

  ham <- as.character(meta_json %||% "")[1]
  if (is.na(ham) || !nzchar(ham) || !requireNamespace("jsonlite", quietly = TRUE)) {
    return(varsayilan)
  }

  parsed <- tryCatch(jsonlite::fromJSON(ham, simplifyVector = TRUE), error = function(e) NULL)
  arac <- if (is.list(parsed)) parsed$arac else NULL
  if (!is.list(arac)) {
    return(varsayilan)
  }

  list(
    family = as.character(arac$family %||% "")[1],
    derin = isTRUE(as.logical(arac$derin %||% FALSE)[1]),
    seviye = as.character(arac$seviye %||% "low")[1],
    detay = as.character(arac$detay %||% "standart")[1],
    surec_akisi = as.character(arac$surec_akisi %||% "")[1]
  )
}

# Aktif araç rozeti için kısa Türkçe ayar özeti (SAF).
oo_arac_ayar_ozeti <- function(ayarlar) {
  family <- as.character(ayarlar$family %||% "")[1]
  parcalar <- character(0)

  if (identical(family, "sql_analysis")) {
    if (isTRUE(ayarlar$derin)) {
      parcalar <- c(parcalar, "Derin Düşünme")
    }
    detay_ad <- c(ozet = "Özet", standart = "Standart", detayli = "Detaylı")[
      as.character(ayarlar$detay %||% "standart")[1]
    ]
    if (!is.na(detay_ad)) {
      parcalar <- c(parcalar, paste("Detay:", unname(detay_ad)))
    }
  } else if (family %in% c("mcp_excel", "coding")) {
    if (isTRUE(ayarlar$derin)) {
      seviye_ad <- if (identical(as.character(ayarlar$seviye %||% "low")[1], "high")) "Yüksek" else "Düşük"
      parcalar <- c(parcalar, paste("Derin Düşünme:", seviye_ad))
    }
  }

  paste(parcalar, collapse = " · ")
}

# Üretim motoru için SAF yürütme planı. Soru mesajının MetaJson'undan gelen
# araç seçimini modele/yola çevirir:
#   * yol "sql"      -> Proje/Kaynak Analizi boru hattı (bağlam kurulumu)
#   * yol "langflow" -> kurumsal Langflow akışı (process / app_expert)
#   * yol "normal"   -> normal LLM (araç modeli veya oda modeli)
# Derin Düşünme ayarları resolve_runtime_model_for_request üzerinden modele
# yansır (mcp_excel/coding); sql_analysis derin modu boru hattı içinde çözülür.
oo_arac_uretim_plani <- function(arac_meta, config = NULL) {
  if (is.null(config) && exists("api_config", inherits = TRUE)) {
    config <- get("api_config", inherits = TRUE)
  }

  ayarlar <- if (is.list(arac_meta)) arac_meta else oo_arac_varsayilan_ayarlar()
  family <- as.character(ayarlar$family %||% "")[1]

  plan <- list(
    family = family,
    yol = "normal",
    model_id = "",
    belge_baglami = TRUE,
    sistem_notu = "",
    derin = isTRUE(ayarlar$derin),
    seviye = as.character(ayarlar$seviye %||% "low")[1],
    detay = as.character(ayarlar$detay %||% "standart")[1],
    surec_akisi = as.character(ayarlar$surec_akisi %||% "")[1]
  )

  if (!nzchar(family) || family %in% .oo_arac_desteklenmeyenler) {
    plan$family <- ""
    return(plan)
  }

  cfg <- if (exists("get_tool_mode_config", mode = "function", inherits = TRUE)) {
    get_tool_mode_config(family, by = "family", config = config)
  } else {
    NULL
  }
  if (is.null(cfg)) {
    plan$family <- ""
    return(plan)
  }

  if (identical(as.character(cfg$runtime %||% "")[1], "langflow")) {
    plan$yol <- "langflow"
    # Langflow akışı kendi bilgi tabanını taşır; ortak belge bağlamı akış
    # girdisine enjekte edilmez (tekil oturum davranışıyla tutarlı).
    plan$belge_baglami <- FALSE
    return(plan)
  }

  if (identical(family, "sql_analysis")) {
    plan$yol <- "sql"
    plan$model_id <- if (exists("resolve_tool_model_for_family", mode = "function", inherits = TRUE)) {
      resolve_tool_model_for_family("sql_analysis", config = config)
    } else {
      as.character(cfg$model_id %||% "")[1]
    }
    return(plan)
  }

  # mcp_excel / coding: Derin Düşünme model çözümü; diğerleri araç modeli.
  plan$model_id <- if (exists("resolve_runtime_model_for_request", mode = "function", inherits = TRUE)) {
    resolve_runtime_model_for_request(
      tool_family = family,
      fallback_model = as.character(cfg$model_id %||% "")[1],
      excel_deep_on = identical(family, "mcp_excel") && isTRUE(ayarlar$derin),
      excel_deep_level = plan$seviye,
      coding_deep_on = identical(family, "coding") && isTRUE(ayarlar$derin),
      coding_deep_level = plan$seviye,
      config = config
    )
  } else {
    as.character(cfg$model_id %||% "")[1]
  }

  if (identical(family, "summarization")) {
    plan$sistem_notu <- paste(
      "Kullanıcı özetleme aracını seçti: bağlama dahil edilen ortak belgeleri",
      "kapsamlı biçimde Türkçe özetle; tüm önemli başlıkları, alt konuları ve",
      "sayısal verileri koru."
    )
  }

  plan
}

# Proje/Kaynak Analizi boru hattı köprüsü. Tekil oturumdaki send_message
# yolunun aynısını kullanır: pk_deep_analysis_process (Derin Düşünme) veya
# pk_analiz_process_request. Karakter dönüşleri doğrudan yanıt olarak, liste
# dönüşleri sistem/kullanıcı bağlamı olarak aktarılır.
#
# @return list(dogrudan_yanit=, sistem=, kullanici=, max_tokens=)
oo_arac_sql_baglami_kur <- function(soru, gecmis, oda_session, arac_meta) {
  if (!exists("pk_analiz_process_request", mode = "function", inherits = TRUE)) {
    return(list(dogrudan_yanit = paste(
      "\U000026A0\U0000FE0F Proje ve Kaynak Analizi aracı bu ortamda yapılandırılmamış."
    )))
  }

  derin <- isTRUE(arac_meta$derin) &&
    exists("pk_deep_analysis_process", mode = "function", inherits = TRUE)

  sonuc <- tryCatch({
    if (derin) {
      pk_deep_analysis_process(
        soru, gecmis, oda_session,
        detail_level = as.character(arac_meta$detay %||% "standart")[1],
        stop_check = NULL
      )
    } else {
      pk_analiz_process_request(soru, gecmis, oda_session, stop_check = NULL)
    }
  }, error = function(e) {
    paste0("\U000026A0\U0000FE0F Analiz modülü hatası: ", conditionMessage(e))
  })

  if (is.character(sonuc)) {
    return(list(dogrudan_yanit = as.character(sonuc)[1]))
  }

  if (is.list(sonuc) && identical(sonuc$type, "error_message")) {
    return(list(dogrudan_yanit = as.character(sonuc$content %||% "Analiz tamamlanamadı.")[1]))
  }

  if (is.list(sonuc) && !is.null(sonuc$prompt_context)) {
    return(list(
      sistem = as.character(sonuc$prompt_context)[1],
      kullanici = as.character(sonuc$user_context %||% soru)[1],
      max_tokens = sonuc$max_tokens
    ))
  }

  list(dogrudan_yanit = "\U000026A0\U0000FE0F Analiz beklenmeyen bir sonuç döndürdü.")
}

# Langflow çağrısı için worker argümanlarını hazırlar (SAF-ish; config okur).
# Yapılandırma eksikse NULL döner; çağıran net Türkçe hata gösterir.
oo_arac_langflow_cagrisi_hazirla <- function(plan, soran_id, oturum_id, config = NULL) {
  if (is.null(config) && exists("api_config", inherits = TRUE)) {
    config <- get("api_config", inherits = TRUE)
  }
  if (!exists("mergen_langflow_config", mode = "function", inherits = TRUE) ||
      !exists("call_langflow_chat", mode = "function", inherits = TRUE)) {
    return(NULL)
  }

  lf_cfg <- mergen_langflow_config(config)
  base_url <- normalize_langflow_base_url(lf_cfg$base_url)
  flow_id <- mergen_langflow_flow_id_for_family(
    plan$family, config,
    selected_flow = plan$surec_akisi
  )

  if (!nzchar(base_url) || !nzchar(flow_id)) {
    return(NULL)
  }

  timeout_saniye <- suppressWarnings(as.numeric(lf_cfg$timeout_seconds %||% 300))
  if (length(timeout_saniye) == 0L || is.na(timeout_saniye) || timeout_saniye <= 0) {
    timeout_saniye <- 300
  }

  list(
    base_url = base_url,
    flow_id = flow_id,
    api_key = as.character(lf_cfg$api_key %||% "")[1],
    session_id = mergen_build_langflow_session_id(
      soran_id, paste0("oo_", oturum_id), flow_id = flow_id
    ),
    timeout_seconds = timeout_saniye
  )
}

# Langflow üretimini worker'da koşturur ve sonucu bitir_fn'e teslim eder.
# Üretim motoru (module_ortak_oturum_yz.R) tarafından çağrılır; motorun bakım
# bütçesini korumak için asenkron zincir burada tutulur. bitir_fn(yanit_metni=,
# hata_metni=) sözleşmesi motorun tamamlama yoludur.
oo_arac_langflow_uret <- function(lf, soru_metni, session_token, bitir_fn) {
  soru_local <- as.character(soru_metni %||% "")[1]
  lf_local <- lf

  if (!exists("tracked_future_promise", mode = "function", inherits = TRUE)) {
    yanit <- tryCatch(
      call_langflow_chat(
        input_value = soru_local,
        base_url = lf_local$base_url,
        flow_id = lf_local$flow_id,
        api_key = lf_local$api_key,
        session_id = lf_local$session_id,
        timeout_seconds = lf_local$timeout_seconds
      ),
      error = function(e) NULL
    )
    if (is.list(yanit) && isTRUE(yanit$success) &&
        nzchar(as.character(yanit$text %||% "")[1])) {
      bitir_fn(yanit_metni = as.character(yanit$text)[1])
    } else {
      bitir_fn(hata_metni = "Langflow yanıtı üretilemedi; lütfen tekrar deneyin.")
    }
    return(invisible(NULL))
  }

  prom <- tracked_future_promise(
    task_fn = function() {
      call_langflow_chat(
        input_value = soru_local,
        base_url = lf_local$base_url,
        flow_id = lf_local$flow_id,
        api_key = lf_local$api_key,
        session_id = lf_local$session_id,
        timeout_seconds = lf_local$timeout_seconds
      )
    },
    task_type = "ortak_oturum_langflow",
    session_token = session_token
  )

  promises::then(
    prom,
    function(yanit) {
      if (is.list(yanit) && isTRUE(yanit$success) &&
          nzchar(as.character(yanit$text %||% "")[1])) {
        bitir_fn(yanit_metni = as.character(yanit$text)[1])
      } else {
        hata <- as.character(yanit$error %||% "Langflow yanıtı alınamadı.")[1]
        # Üst-akış hatası API anahtarını yansıtsa bile odaya sızmasın.
        if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
          hata <- redact_sensitive_text(hata)
        }
        bitir_fn(hata_metni = paste0("\U000026A0\U0000FE0F ", hata))
      }
    },
    function(e) {
      bitir_fn(hata_metni = "Langflow yanıtı üretilemedi; lütfen tekrar deneyin.")
    }
  )

  invisible(NULL)
}

