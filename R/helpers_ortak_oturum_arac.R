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

    destekleniyor <- !(family %in% .oo_arac_desteklenmeyenler)

    list(
      family = family,
      baslik = as.character(cfg$title %||% family)[1],
      aciklama = as.character(cfg$description %||% "")[1],
      ikon = as.character(cfg$icon_name %||% "bolt")[1],
      renk = as.character(cfg$themeColor %||% "#6366f1")[1],
      runtime = as.character(cfg$runtime %||% "local")[1],
      model_id = as.character(cfg$model_id %||% "")[1],
      destekleniyor = destekleniyor,
      devre_disi_nedeni = if (destekleniyor) "" else oo_arac_devre_disi_nedeni(family),
      derin_var = family %in% c("sql_analysis", "mcp_excel", "coding"),
      detay_var = identical(family, "sql_analysis"),
      seviye_var = family %in% c("mcp_excel", "coding"),
      akis_var = identical(family, "process"),
      # Dosya Özetleme ayarları (tekil oturumla aynı seçenek uzayı):
      # Detay = Kısa Özet / Standart / Detaylı, Odak = Genel / Sayısal Veri /
      # Karar & Öneri / Karşılaştırma.
      ozet_detay_var = identical(family, "summarization"),
      odak_var = identical(family, "summarization")
    )
  })

  Filter(Negate(is.null), girisler)
}

# Varsayılan araç durumu: araç yok, ayarlar tekil oturum varsayılanlarıyla.
oo_arac_varsayilan_ayarlar <- function() {
  list(
    family = "", derin = FALSE, seviye = "low", detay = "standart",
    odak = "genel", surec_akisi = ""
  )
}

# Soru mesajı için araç planı + seçili belge anlık görüntüsü metadata'sını
# hazırlar. BilgeYolaç odasında araç planı yazılmaz ve belge kümesi BOŞ
# sabitlenir (sorular BY köprüsüne gider; CLI'sız normal LLM düşüşü de
# arayüzün vaat etmediği belge/araç bağlamını sessizce eklememelidir).
# Boş küme bile açıkça yazılır: kuyrukta bekleyen bir soru, üretim başlamadan
# önce sonradan yapılan seçimleri yanlışlıkla bağlama almasın.
oo_arac_soru_meta_hazirla <- function(oturum_id, uid, by_odasi = FALSE, arac_meta_fn = NULL) {
  arac_meta_ekstra <- NULL
  if (!isTRUE(by_odasi) && is.function(arac_meta_fn)) {
    arac_meta_ekstra <- arac_meta_fn()
  }

  belge_ids <- integer(0)
  if (!isTRUE(by_odasi) &&
      exists("ortak_db_secili_belge_idleri", mode = "function", inherits = TRUE)) {
    belge_ids <- ortak_db_secili_belge_idleri(oturum_id, uid)
  }

  utils::modifyList(
    if (is.list(arac_meta_ekstra)) arac_meta_ekstra else list(),
    list(belgeler = list(secili_ids = as.integer(belge_ids)))
  )
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
    odak = as.character(ayarlar$odak %||% "genel")[1],
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
    odak = as.character(arac$odak %||% "genel")[1],
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
  } else if (identical(family, "summarization")) {
    detay_ad <- c(kisa = "Kısa Özet", standart = "Standart", detayli = "Detaylı")[
      as.character(ayarlar$detay %||% "standart")[1]
    ]
    if (!is.na(detay_ad)) {
      parcalar <- c(parcalar, paste("Detay:", unname(detay_ad)))
    }
    odak_ad <- c(
      genel = "Genel", sayisal = "Sayısal Veri",
      karar = "Karar & Öneri", karsilastirma = "Karşılaştırma"
    )[as.character(ayarlar$odak %||% "genel")[1]]
    if (!is.na(odak_ad) && !identical(unname(odak_ad), "Genel")) {
      parcalar <- c(parcalar, paste("Odak:", unname(odak_ad)))
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
    mcp_araclari = FALSE,
    derin = isTRUE(ayarlar$derin),
    seviye = as.character(ayarlar$seviye %||% "low")[1],
    detay = as.character(ayarlar$detay %||% "standart")[1],
    odak = as.character(ayarlar$odak %||% "genel")[1],
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

  if (identical(family, "mcp_excel")) {
    # Tekil oturumdaki MCP Excel yolu: gerçek araç yürütmesi (dosya analizi,
    # kolon istatistiği, SQL, grafik üretimi). Üretim motoru seçili Excel
    # belgeleri varsa call_llm_worker MCP yoluna geçer. Excel içeriği MCP
    # araçlarının sahasıdır; genel belge-metni bağlamı enjekte edilmez
    # (tekil oturum davranışıyla aynı: model dosyayı araçla okur, tahmin etmez).
    plan$mcp_araclari <- TRUE
    plan$belge_baglami <- FALSE
  }

  if (identical(family, "summarization") &&
      exists("oo_arac_ozetleme_sistem_notu", mode = "function", inherits = TRUE)) {
    # Tekil oturum özetleme sistem prompt'u (Detay + Odak ayarlarıyla).
    # Belge sayısı üretim anında bilinir; motor dosya sayısını verip yeniden
    # üretir — buradaki not tek belge varsayımıyla güvenli taban sağlar.
    # Üretici (oo_arac_ozetleme_sistem_notu) uretim yardımcı dosyasındadır ve
    # manifestte bu dosyadan ÖNCE yüklenir; izole test bağlamlarında yoksa not
    # boş kalır (davranış değişmeden normal LLM yoluna devam edilir).
    plan$sistem_notu <- oo_arac_ozetleme_sistem_notu(
      detay = plan$detay, odak = plan$odak, belge_sayisi = 1L
    )
  }

  plan
}

# Odaya yazılacak genel araç hatası metni (SAF). Ham tanılama içermez.
.oo_arac_genel_hata_metni <- function() {
  paste0(
    "\U000026A0\U0000FE0F Araç yanıtı hazırlanırken bir sorun oluştu; ",
    "ayrıntılar sunucu günlüğüne kaydedildi. Lütfen tekrar deneyin."
  )
}

# Oda transkriptine yazılacak araç/analiz yanıtını güvenli hale getirir (SAF).
# Ortak odada yanıt TÜM katılımcılara kalıcı olarak görünür; bu yüzden ham
# SQL/ODBC/sürücü/DSN tanılaması içeren hata metinleri odaya taşınmaz ve genel
# Türkçe mesaja indirgenir (ayrıntı zaten sunucu günlüğündedir). Olağan analiz
# yanıtları değişmeden geçer; redaksiyon yardımcısı varsa anahtar/parola
# benzeri değerler ek savunma olarak maskelenir.
oo_arac_oda_guvenli_yanit <- function(metin) {
  metin <- as.character(metin %||% "")[1]
  if (is.na(metin) || !nzchar(trimws(metin))) {
    return(.oo_arac_genel_hata_metni())
  }

  # Bilinen ham altyapı tanılama kalıpları: DB hata gövdesi, ODBC/SQLSTATE
  # kodları, sürücü/bağlantı metinleri ve R condition önekleri.
  riskli_kaliplar <- c(
    "**Veritabanı Hatası:**",
    "nanodbc", "SQLSTATE", "ODBC", "odbc.cpp", "SQL Server",
    "HY000", "42S02", "42000", "IM002", "08001", "28000",
    "Login timeout", "Login failed", "Error in ", "error in evaluating",
    "could not connect", "Connection refused", "DSN=", "Driver="
  )
  riskli <- any(vapply(
    riskli_kaliplar,
    function(kalip) grepl(kalip, metin, fixed = TRUE, useBytes = TRUE),
    logical(1)
  ))

  if (riskli) {
    if (exists("log_warn", mode = "function", inherits = TRUE)) {
      tryCatch(
        log_warn(paste(
          "[ORTAK_ARAC] Ham analiz tanılaması odaya yazılmadı;",
          "katılımcılara genel hata mesajı gösterildi."
        )),
        error = function(e) NULL
      )
    }
    return(.oo_arac_genel_hata_metni())
  }

  if (exists("redact_sensitive_text", mode = "function", inherits = TRUE)) {
    metin <- tryCatch(redact_sensitive_text(metin), error = function(e) metin)
  }
  metin
}

# Proje/Kaynak Analizi RLS kimliği soru sahibine bağlı çalışmalıdır. Ortak
# oturum kuyruğunu hangi Shiny session boşaltırsa boşaltsın SQL/RLS analizi
# soruyu soran katılımcının MB_Users.KullaniciAdi değeriyle çözülür; soru
# sahibi çözülemezse başka katılımcının session kimliğine düşülmez.
oo_arac_soran_session <- function(oturum_id, soran_id, current_session = NULL, katilimcilar = NULL) {
  soran_id_int <- suppressWarnings(as.integer(soran_id %||% NA_integer_)[1])

  current_uid <- suppressWarnings(as.integer(tryCatch(
    current_session$userData$user_id %||% NA_integer_,
    error = function(e) NA_integer_
  )[1]))
  if (!is.na(soran_id_int) && !is.na(current_uid) && identical(soran_id_int, current_uid)) {
    return(current_session)
  }

  katilimci_satiri <- NULL
  if (is.data.frame(katilimcilar) && nrow(katilimcilar) > 0L &&
      all(c("KullaniciID", "KullaniciAdi") %in% names(katilimcilar))) {
    eslesen <- katilimcilar[
      suppressWarnings(as.integer(katilimcilar$KullaniciID)) == soran_id_int,
      ,
      drop = FALSE
    ]
    if (nrow(eslesen) > 0L) {
      katilimci_satiri <- eslesen[1L, , drop = FALSE]
    }
  }

  if (is.null(katilimci_satiri) &&
      exists("ortak_db_katilimci_listesi", mode = "function", inherits = TRUE)) {
    liste <- tryCatch(ortak_db_katilimci_listesi(oturum_id), error = function(e) NULL)
    if (is.data.frame(liste) && nrow(liste) > 0L &&
        all(c("KullaniciID", "KullaniciAdi") %in% names(liste))) {
      eslesen <- liste[
        suppressWarnings(as.integer(liste$KullaniciID)) == soran_id_int,
        ,
        drop = FALSE
      ]
      if (nrow(eslesen) > 0L) {
        katilimci_satiri <- eslesen[1L, , drop = FALSE]
      }
    }
  }

  username <- if (!is.null(katilimci_satiri)) {
    as.character(katilimci_satiri$KullaniciAdi[1] %||% "")[1]
  } else {
    ""
  }
  username <- trimws(username)

  user_data <- new.env(parent = emptyenv())
  user_data$user_id <- soran_id_int
  if (nzchar(username)) {
    user_data$system_username <- username
    user_data$user_identity <- list(username = username)
    user_data$sso_active <- TRUE
    user_data$auth_initialized <- TRUE
  } else {
    user_data$sso_active <- TRUE
    user_data$auth_initialized <- FALSE
  }

  list(userData = user_data)
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
    "\U000026A0\U0000FE0F Analiz modülü yanıtı hazırlanamadı; lütfen tekrar deneyin."
  })

  # Doğrudan yanıt yolları paylaşılan transkripte kalıcı yazılır: karakter
  # dönüşleri ve error_message içerikleri ham SQL/ODBC tanılaması taşıyabilir
  # (ör. tekil oturumun "Veritabanı Hatası" gövdesi). Odaya çıkmadan önce
  # güvenli yanıt süzgecinden geçirilir.
  if (is.character(sonuc)) {
    return(list(dogrudan_yanit = oo_arac_oda_guvenli_yanit(as.character(sonuc)[1])))
  }

  if (is.list(sonuc) && identical(sonuc$type, "error_message")) {
    return(list(dogrudan_yanit = oo_arac_oda_guvenli_yanit(
      as.character(sonuc$content %||% "Analiz tamamlanamadı.")[1]
    )))
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
    # Langflow sohbet belleği ODA kapsamlıdır: kimlik soran katılımcıya değil
    # oda + akışa anahtarlanır. Böylece aynı odadaki farklı katılımcıların
    # devam soruları tek paylaşılan bağlamda sürer; farklı odalar ve farklı
    # akışlar birbirinden yalıtık kalır. "oda" öneki kişisel oturum
    # kimlikleriyle (mergen_<uid>_...) çakışmayı önler; soran_id imza uyumu
    # için korunur ama anahtara girmez.
    session_id = mergen_build_langflow_session_id(
      "oda", paste0("oo_", oturum_id), flow_id = flow_id
    ),
    timeout_seconds = timeout_saniye
  )
}

# Langflow yanıtının metnini üretir ve (varsa) belge kaynak işaretleyici bloğunu
# ekler. İşaretleyici oda mesaj render'ında (oo_mesaj_html) tıklanabilir Kaynakça'ya
# yükseltilir; ortak odada tıklama YALNIZCA kurumsal model taban klasörlerinde
# çözümlenir (kişisel kullanıcı kovası taranmaz). Marker üretici yüklü değilse
# (izole test/worker) metin olduğu gibi kalır. Bu birleştirme ANA süreçte
# (then/senkron dal) çalışır; worker tarafına marker üretimi taşınmaz.
.oo_langflow_yanit_metni <- function(yanit) {
  metin <- as.character(yanit$text %||% "")[1]
  if (exists("mergen_langflow_kaynakca_marker_block", mode = "function", inherits = TRUE)) {
    blok <- tryCatch(mergen_langflow_kaynakca_marker_block(yanit$sources), error = function(e) "")
    if (nzchar(blok)) metin <- paste0(metin, blok)
  }
  metin
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
      bitir_fn(yanit_metni = .oo_langflow_yanit_metni(yanit))
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
        bitir_fn(yanit_metni = .oo_langflow_yanit_metni(yanit))
      } else {
        hata <- as.character(yanit$error %||% "Langflow yanıtı alınamadı.")[1]
        # Üst-akış hatası API anahtarı/uç nokta tanılaması yansıtsa bile
        # odaya sızmasın: güvenli yanıt süzgeci + redaksiyon uygulanır.
        hata <- oo_arac_oda_guvenli_yanit(hata)
        if (!startsWith(hata, "\U000026A0")) {
          hata <- paste0("\U000026A0\U0000FE0F ", hata)
        }
        bitir_fn(hata_metni = hata)
      }
    },
    function(e) {
      bitir_fn(hata_metni = "Langflow yanıtı üretilemedi; lütfen tekrar deneyin.")
    }
  )

  invisible(NULL)
}
