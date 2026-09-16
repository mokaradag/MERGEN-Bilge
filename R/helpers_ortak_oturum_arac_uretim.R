# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_arac_uretim.R
# Açıklama: Ortak Oturum araç ÜRETİM YOLU yardımcıları: devre dışı araç
#           gerekçesi, özetleme Detay/Odak anahtar eşlemeleri + sistem notu,
#           seçili ortak belgelerden MCP kayıt görüntüsü ve Excel Analizi'nin
#           tekil oturumla aynı call_llm_worker MCP yürütmesi. Araç seçici saf
#           karar katmanından (helpers_ortak_oturum_arac.R) fonksiyon bütçesi
#           nedeniyle ayrıldı; bu dosya ondan ÖNCE yüklenir.
# ==============================================================================

# Desteklenmeyen araçlar için kullanıcıya gösterilen açık Türkçe gerekçe.
# UI ipucu ve dokümantasyon bu tek kaynağı kullanır.
oo_arac_devre_disi_nedeni <- function(family) {
  if (identical(as.character(family %||% "")[1], "image")) {
    return(paste(
      "Görsel Oluşturma ortak oturumlarda desteklenmez: üretilen görseller",
      "kişisel galeriye ve oturum-kapsamlı görsel sunumuna bağlıdır; ortak",
      "odada tüm katılımcılara güvenli görsel dağıtımı henüz sağlanmadığı için",
      "araç bilinçli olarak kapalıdır. Görsel üretimi için Ana Söyleşi'deki",
      "Görsel Oluşturma aracını kullanın."
    ))
  }
  "Bu araç ortak oturumlarda desteklenmez."
}

# Özetleme Detay/Odak değerlerini tekil oturum prompt anahtarlarına çevirir
# (SAF eşleme; build_summarization_system_prompt sözleşmesi).
oo_arac_ozet_detay_anahtari <- function(detay) {
  switch(
    as.character(detay %||% "standart")[1],
    "kisa" = "brief",
    "detayli" = "detailed",
    "standard"
  )
}

oo_arac_ozet_odak_anahtari <- function(odak) {
  switch(
    as.character(odak %||% "genel")[1],
    "sayisal" = "numerical",
    "karar" = "decisions",
    "karsilastirma" = "comparison",
    "general"
  )
}

# Özetleme aracı için tekil oturumla AYNI sistem talimatı (SAF köprü).
# build_summarization_system_prompt yüklü değilse (izole test) kompakt Türkçe
# talimata düşer; Detay/Odak yine yansıtılır.
oo_arac_ozetleme_sistem_notu <- function(detay = "standart",
                                         odak = "genel",
                                         belge_sayisi = 1L,
                                         toplam_karakter = 0L) {
  detail_level <- oo_arac_ozet_detay_anahtari(detay)
  focus_mode <- oo_arac_ozet_odak_anahtari(odak)

  if (exists("build_summarization_system_prompt", mode = "function", inherits = TRUE)) {
    notu <- tryCatch(
      build_summarization_system_prompt(
        file_count = max(1L, as.integer(belge_sayisi %||% 1L)),
        total_chars = as.integer(toplam_karakter %||% 0L),
        detail_level = detail_level,
        focus_mode = focus_mode
      ),
      error = function(e) ""
    )
    if (nzchar(notu)) {
      return(paste(
        notu,
        "\n\nNot: Özetlenecek içerik, bu ortak oturumda bağlama dahil edilen ortak belgelerdir.",
        "Yanıtın tüm katılımcılar tarafından görülecektir."
      ))
    }
  }

  detay_metni <- switch(
    detail_level,
    "brief" = "KISA VE ÖZ özetle: her belge için en fazla 3-5 cümle.",
    "detailed" = "KAPSAMLI ve DETAYLI özetle: tüm bölümleri, başlıkları ve sayısal verileri eksiksiz işle.",
    "Dengeli detayda özetle: ana başlıkları ve kilit sayısal verileri koru."
  )
  odak_metni <- switch(
    focus_mode,
    "numerical" = " ÖZELLİKLE sayısal verilere, istatistiklere ve rakamlara odaklan.",
    "decisions" = " ÖZELLİKLE karar noktalarına, önerilere ve aksiyon maddelerine odaklan.",
    "comparison" = " Belgeleri ve bölümleri birbirleriyle karşılaştır.",
    ""
  )

  paste0(
    "Kullanıcı özetleme aracını seçti: bağlama dahil edilen ortak belgeleri Türkçe özetle. ",
    detay_metni, odak_metni
  )
}

# Seçili ortak belgelerden MCP dosya kayıt görüntüsü üretir (SAF). Yalnızca
# Excel türleri (tekil oturum mcp_excel politikasıyla aynı: xls/xlsx) ve
# fiziksel olarak var olan dosyalar alınır. Girdiler call_llm_worker'ın
# mcp_registry_snapshot sözleşmesiyle aynı şekildedir: token -> list(path, name).
oo_arac_mcp_kayit_goruntusu <- function(belgeler_df,
                                        excel_uzantilari = c("xls", "xlsx")) {
  goruntu <- list()
  if (!is.data.frame(belgeler_df) || nrow(belgeler_df) == 0L) {
    return(goruntu)
  }

  for (i in seq_len(nrow(belgeler_df))) {
    yol <- as.character(belgeler_df$DosyaYolu[i] %||% "")[1]
    ad <- as.character(belgeler_df$DosyaAdi[i] %||% basename(yol))[1]
    dosya_id <- suppressWarnings(as.integer(belgeler_df$OrtakDosyaID[i] %||% NA_integer_)[1])

    if (is.na(yol) || !nzchar(yol)) {
      next
    }
    if (!(tolower(tools::file_ext(yol)) %in% tolower(excel_uzantilari))) {
      next
    }

    var_mi <- if (exists("path_exists_relaxed", mode = "function", inherits = TRUE)) {
      isTRUE(tryCatch(path_exists_relaxed(yol), error = function(e) FALSE))
    } else {
      file.exists(yol)
    }
    if (!var_mi) {
      next
    }

    token <- sprintf("oo_belge_%s", if (!is.na(dosya_id)) dosya_id else i)
    goruntu[[token]] <- list(path = yol, name = ad)
  }

  goruntu
}

# Özetleme/Excel araçları için seçili belge kümesini çözer ve (özetleme ise)
# gerçek belge sayısıyla sistem notunu yeniler. Soru anındaki anlık görüntü
# (belge_ids_snapshot) tercih edilir; kuyruk devralsa bile aynı küme kullanılır.
# @return list(plan = <güncellenmiş plan>, belgeler_df = <data.frame veya NULL>)
oo_arac_uretim_belge_hazirla <- function(plan, oturum_id, soran_id, belge_ids_snapshot = NULL) {
  belgeler_df <- NULL

  if (identical(plan$family, "summarization") || isTRUE(plan$mcp_araclari)) {
    belgeler_df <- tryCatch({
      if (!is.null(belge_ids_snapshot) &&
          exists("ortak_db_belgeler_idlerle", mode = "function", inherits = TRUE)) {
        ortak_db_belgeler_idlerle(oturum_id, soran_id, belge_ids_snapshot)
      } else if (exists("ortak_db_secili_belgeler", mode = "function", inherits = TRUE)) {
        ortak_db_secili_belgeler(oturum_id, soran_id)
      } else {
        NULL
      }
    }, error = function(e) NULL)
  }

  # Özetleme sistem talimatı gerçek belge sayısıyla yeniden üretilir
  # (Detay + Odak ayarları tekil oturum prompt üreticisinden geçer).
  if (identical(plan$family, "summarization") &&
      is.data.frame(belgeler_df) && nrow(belgeler_df) > 0L) {
    plan$sistem_notu <- oo_arac_ozetleme_sistem_notu(
      detay = plan$detay, odak = plan$odak,
      belge_sayisi = nrow(belgeler_df)
    )
  }

  list(plan = plan, belgeler_df = belgeler_df)
}

# LLM bağlamına sistem mesajı katmanlarını ekler (SAF; liste manipülasyonu).
# Nihai sıra başa doğru: persona -> ortak belgeler -> araç notu -> geçmiş.
# Ortak belge bağlamı yalnızca SEÇİLİ belgeler için ve plan$belge_baglami
# açıkken eklenir (Langflow/Excel yolunda kapalıdır). Belge mesajı, son
# kullanıcı içeriğinin önüne katılır; kullanıcı mesajı yoksa başa eklenir.
oo_arac_uretim_baglam_katmanla <- function(gecmis, plan, oturum_id, soran_id,
                                           belge_ids_snapshot = NULL,
                                           persona_kimligi = NULL) {
  # Araç notu (özetleme sistem talimatı vb.).
  if (nzchar(as.character(plan$sistem_notu %||% "")[1])) {
    gecmis <- c(list(list(role = "system", content = plan$sistem_notu)), gecmis)
  }

  # Ortak belge bağlamı.
  if (isTRUE(plan$belge_baglami) &&
      exists("ortak_belge_baglam_sistem_mesaji", mode = "function", inherits = TRUE)) {
    belge_mesaji <- tryCatch(
      ortak_belge_baglam_sistem_mesaji(oturum_id, soran_id, belge_ids = belge_ids_snapshot),
      error = function(e) NULL
    )
    if (!is.null(belge_mesaji)) {
      kullanici_indeksleri <- which(vapply(
        gecmis, function(m) identical(m$role, "user"), logical(1)
      ))
      if (length(kullanici_indeksleri) > 0L) {
        son_kullanici <- max(kullanici_indeksleri)
        gecmis[[son_kullanici]]$content <- paste(
          as.character(belge_mesaji$content %||% "")[1],
          "Kullanıcının sorusu:",
          as.character(gecmis[[son_kullanici]]$content %||% "")[1],
          sep = "\n\n"
        )
      } else {
        gecmis <- c(list(belge_mesaji), gecmis)
      }
    }
  }

  # Persona sistem mesajı: yanıt seçili persona tarzında üretilsin. Boş
  # talimatta davranış değişmeden normal LLM yoluna devam edilir.
  if (exists("ortak_oturum_persona_sistem_prompt", mode = "function", inherits = TRUE)) {
    persona_sistem <- ortak_oturum_persona_sistem_prompt(persona_kimligi, oturum_id)
    if (nzchar(persona_sistem)) {
      gecmis <- c(list(list(role = "system", content = persona_sistem)), gecmis)
    }
  }

  gecmis
}

# Excel Analizi MCP üretimini worker'da koşturur ve sonucu bitir_fn'e teslim
# eder (oo_arac_langflow_uret ile aynı desen: asenkron zincir motor dışında
# tutulur). Tekil oturumla aynı gerçek araç yürütmesi: call_llm_worker seçili
# ortak Excel belgelerinden kurulan kayıt görüntüsüyle MCP araçlarını (dosya
# analizi, kolon istatistiği, SQL, grafik üretimi) çalıştırır; grafikler yanıt
# metnine gömülü ```chartlab blokları olarak döner.
# bitir_fn(yanit_metni=, hata_metni=) motorun tamamlama sözleşmesidir.
oo_arac_mcp_uret <- function(gecmis, ayarlar, secili_belgeler_df,
                             soran_id, session_token, bitir_fn) {
  mcp_goruntu <- oo_arac_mcp_kayit_goruntusu(secili_belgeler_df)

  if (length(mcp_goruntu) == 0L) {
    bitir_fn(yanit_metni = paste(
      "\U0001F4CA Excel Analizi için önce Ortak Belgeler panelinden bir Excel",
      "dosyası (.xlsx/.xls) yükleyin ve \"Bağlama dahil et\" ile seçin.",
      "Seçili Excel belgesi olmadan analiz ve grafik üretimi çalıştırılamaz."
    ))
    return(invisible(NULL))
  }

  if (!exists("call_llm_worker", mode = "function", inherits = TRUE) ||
      !exists("tracked_future_promise", mode = "function", inherits = TRUE)) {
    bitir_fn(hata_metni = "Excel Analizi altyapısı bu ortamda yüklü değil; lütfen tekrar deneyin.")
    return(invisible(NULL))
  }

  ayarlar$enable_mcp_tools <- TRUE
  ayarlar$tool_family <- "mcp_excel"
  ayarlar$mcp_registry_snapshot <- mcp_goruntu
  ayarlar$current_user_id <- soran_id

  api_endpoint <- if (exists("resolve_local_llm_endpoint", mode = "function", inherits = TRUE)) {
    tryCatch(
      resolve_local_llm_endpoint(ayarlar$model_selection),
      error = function(e) Sys.getenv("LOCAL_LLM_ENDPOINT", unset = "")
    )
  } else {
    Sys.getenv("LOCAL_LLM_ENDPOINT", unset = "")
  }
  api_key_val <- ayarlar$api_key_override

  gecmis_kopya <- gecmis
  ayarlar_kopya <- ayarlar

  # tracked_future_promise() gönderim anında SENKRON hata verebilir (worker
  # planı yok, serileştirme hatası). Yakalanmazsa `bitir_fn` hiç çağrılmıyor ve
  # ODA ÜRETİM KİLİDİ kalıcı olarak açık kalıyordu.
  prom <- tryCatch(
    tracked_future_promise(
      task_fn = function() {
        call_llm_worker(gecmis_kopya, ayarlar_kopya, api_endpoint, api_key_val)
      },
      task_type = "ortak_oturum_mcp_excel",
      session_token = session_token,
      globals = list(
        call_llm_worker = call_llm_worker,
        gecmis_kopya = gecmis_kopya,
        ayarlar_kopya = ayarlar_kopya,
        api_endpoint = api_endpoint,
        api_key_val = api_key_val
      )
    ),
    error = function(e) e
  )

  if (inherits(prom, "condition")) {
    if (exists("log_warn", mode = "function", inherits = TRUE)) {
      tryCatch(
        log_warn(paste("[ORTAK_MCP] Excel analizi gönderilemedi:", gsub("[{}]", "", conditionMessage(prom)))),
        error = function(e2) NULL
      )
    }
    bitir_fn(hata_metni = "Excel analizi başlatılamadı; lütfen tekrar deneyin.")
    return(invisible(NULL))
  }

  promises::then(
    prom,
    onFulfilled = function(yanit) {
      icerik <- if (is.list(yanit)) as.character(yanit$content %||% "")[1] else as.character(yanit %||% "")[1]
      if (!is.na(icerik) && nzchar(trimws(icerik))) {
        # call_llm_worker araç hatasını REDDETMEK yerine "Araç hatası: ..."
        # gibi normal içerik olarak döndürebilir; bazı MCP okuyucuları bu
        # metinde ham "Path:" / sürücü tanılaması taşır. Ortak transkripte
        # kalıcı yazılmadan önce paylaşılan oda güvenli-yanıt süzgecinden
        # geçirilir (SQL/BY yollarıyla aynı redaksiyon sınırı).
        if (exists("oo_arac_oda_guvenli_yanit", mode = "function", inherits = TRUE)) {
          icerik <- oo_arac_oda_guvenli_yanit(icerik)
        }
        bitir_fn(yanit_metni = icerik)
      } else {
        bitir_fn(hata_metni = "Excel analizi boş yanıt döndürdü; lütfen tekrar deneyin.")
      }
    },
    onRejected = function(e) {
      if (exists("log_warn", mode = "function", inherits = TRUE)) {
        tryCatch(
          log_warn(paste("[ORTAK_MCP] Excel analizi başarısız:", gsub("[{}]", "", conditionMessage(e)))),
          error = function(e2) NULL
        )
      }
      bitir_fn(hata_metni = "Excel analizi tamamlanamadı; lütfen tekrar deneyin.")
    }
  )

  invisible(NULL)
}