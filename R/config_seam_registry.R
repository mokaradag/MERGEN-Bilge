# ==============================================================================
# Dosya Yolu: R/config_seam_registry.R
# Açıklama: MERGEN Bilge üretim-kritik dikiş (seam) kayıt defteri.
#           Bu dosya çalışma zamanı davranışını DEĞİŞTİRMEZ; yalnızca saf veri
#           ve saf doğrulama yardımcıları tanımlar.
#
#           Amaç: Shiny runtime, DB/encoding, SSO/JWT, LLM streaming, dosya
#           yaşam döngüsü, API anahtarları, medya/ses, yönetici panelleri ve
#           Bilge Yolaç gibi üretim-kritik sınırların sahipliğini TEK makine
#           tarafından okunabilir haritada toplamaktır.
#
#           Sözleşme:
#             - Her source-manifest bölümü (source_manifest_sections) tam olarak
#               BİR seam'e aittir (bölüm -> seam ortaklığı yok).
#             - Manifest dışı kök/boot çalışma zamanı dosyaları seam'lerin
#               extra_runtime_files alanında açıkça listelenir; böylece R/
#               altında "sahipsiz" dosya kalmaz.
#             - Her seam, kendisini koruyan odaklı guard testlerini ve odaklı
#               doğrulama komutlarını bildirir.
#             - Frontend bölge (zone) sahipliği R/config_ui_asset_zones.R
#               içindedir; seam başına bölge listesi oradan TÜRETİLİR, burada
#               tekrar edilmez.
#
#           Koruyan sözleşme testi: tests/testthat/test-seam-registry-contract.R
#           Operasyonel rapor: tests/scripts/seam_doctor.R
# ==============================================================================

mergen_seam_registry <- function() {
  kayit <- .mergen_seam_ownership()

  # Guard test / odaklı doğrulama listeleri AYRI bir veri dosyasındadır
  # (R/config_seam_guard_tests.R). Sahiplik verisi seam sayısıyla, guard test
  # listesi ise kod tabanı büyüdükçe artar; ikisi tek dosyada tutulduğunda
  # sabit bakım tavanı YENİ BİR TESTİN KAYDEDİLMESİNİ engelliyordu.
  # Genel API değişmez: çağıranlar aynı alanları görür.
  koruma <- if (exists("mergen_seam_guard_tests", mode = "function")) {
    mergen_seam_guard_tests()
  } else {
    list()
  }

  for (id in names(kayit)) {
    kaynak <- koruma[[id]]
    kayit[[id]]$guard_tests <- if (is.list(kaynak) && !is.null(kaynak$guard_tests)) {
      kaynak$guard_tests
    } else {
      character(0)
    }
    kayit[[id]]$focused_validation <- if (is.list(kaynak) &&
                                          !is.null(kaynak$focused_validation)) {
      kaynak$focused_validation
    } else {
      character(0)
    }
  }

  kayit
}

# Sahiplik verisi: bölüm -> seam eşlemesi ve manifest dışı çalışma zamanı
# dosyaları. Guard testleri BURADA DEĞİL, mergen_seam_guard_tests() içindedir.
.mergen_seam_ownership <- function() {
  list(
    temel_altyapi = list(
      title = "Temel Altyapı ve Boot",
      description = paste(
        "Boot zinciri, güvenli kaynak yükleme, kaynak manifesti, paket",
        "doğrulama, ortak yardımcılar, log/redaksiyon, dosya deposu",
        "yapılandırması ve mimari yönetişim kayıtları."
      ),
      manifest_sections = c(
        "foundation",
        "post_future_utils",
        "config_app_core",
        "architecture_governance"
      ),
      extra_runtime_files = c(
        "app.R",
        "global.R",
        "R/utils_safe_source.R",
        "R/bootstrap_source_manifest.R",
        "R/bootstrap_log_path.R",
        "R/config_source_manifest.R"
      ),
      related_seams = c("veritabani_kodlama", "dosya_yasam_dongusu", "kimlik_sso")
    ),

    veritabani_kodlama = list(
      title = "Veritabanı ve Türkçe Encoding",
      description = paste(
        "SQL Server yazma/okuma sınırları, DB-güvenli Unicode escape,",
        "mojibake onarımı, mesaj formatlama, sohbet okuyucu/mutasyon ve",
        "geri bildirim yazma yolları."
      ),
      manifest_sections = c("database", "sql_library"),
      extra_runtime_files = character(0),
      related_seams = c("temel_altyapi", "sohbet_llm_akis")
    ),

    kimlik_sso = list(
      title = "Kimlik, SSO/JWT ve Başlangıç",
      description = paste(
        "Keycloak JWT imza doğrulama, fail-closed yetkilendirme, kimlik",
        "hazırlık sağlayıcıları, başlangıç ekranı/yükleme overlay'i,",
        "kenar çubuğu kullanıcı paneli ve hızlı eylem modülleri."
      ),
      manifest_sections = c("sso_identity_helpers", "module_identity_startup"),
      extra_runtime_files = character(0),
      related_seams = c("shiny_calisma_zamani", "veritabani_kodlama")
    ),

    api_anahtar_model = list(
      title = "API Anahtarları ve Model Yapılandırması",
      description = paste(
        "Kişisel/kurumsal API anahtarı çözümleme, şifreli anahtar deposu,",
        "model yetenekleri (vision/derin düşünme), araç-modu model",
        "çözümleme ve Ayarlar/anahtar seçim modülleri."
      ),
      manifest_sections = c("config_api_model_keys", "module_settings_api_key"),
      extra_runtime_files = character(0),
      related_seams = c("sohbet_llm_akis", "bilge_yolac")
    ),

    sohbet_llm_akis = list(
      title = "Sohbet, LLM ve Streaming Hattı",
      description = paste(
        "send_message istek yaşam döngüsü, SSE/stream I/O, reasoning",
        "akışı, yanıt post-process, sohbet modülleri, özetleme/takip",
        "yardımcıları ve sunucu gönderme handler'ları."
      ),
      manifest_sections = c(
        "language_messaging",
        "chat_send_message_runtime",
        "summarization_followup",
        "llm_pipeline",
        "module_chat",
        # Ortak Oturumlar: paylaşılan yapay zekâ sohbet odaları; tek LLM
        # tetikleyici yol YapayZekaSorusu olduğu için bu seam sahiplenir.
        "ortak_oturumlar",
        "server_handlers_send_message"
      ),
      extra_runtime_files = character(0),
      related_seams = c("api_anahtar_model", "veritabani_kodlama", "mcp_analiz")
    ),

    mcp_analiz = list(
      title = "MCP Araçları ve Analiz",
      description = paste(
        "MCP araç zinciri, Excel/dosya çözümleme, ChartLab spec/çıktı",
        "bağlama, derin analiz ve Proje/Kaynak Analizi (RLS dahil)."
      ),
      manifest_sections = c(
        "mcp_tools",
        "chartlab_helpers",
        "pk_query_metadata",
        "analysis_helpers",
        "module_analysis"
      ),
      # R/helpers_pk_analysis_core.R bu iki kardeş dosyayı manifest DIŞINDA source eder.
      extra_runtime_files = character(0),  # PK çekirdek dosyaları artık manifestte
      related_seams = c("dosya_yasam_dongusu", "sohbet_llm_akis")
    ),

    dosya_yasam_dongusu = list(
      title = "Dosya Yaşam Döngüsü ve Dosya Yönetimi",
      description = paste(
        "Yükleme doğrulama, kullanıcı-izoleli dosya çözümleme, kalıcı",
        "indeks, görünen ad koruması, önizleme hattı ve Dosya Yönetimi",
        "modül zinciri (görsel üretim/galeri ve özetleme modülleri dahil)."
      ),
      manifest_sections = c(
        "files_preview_pipeline",
        "file_manager_helpers",
        "module_files_media"
      ),
      extra_runtime_files = character(0),
      related_seams = c("mcp_analiz", "medya_ses", "temel_altyapi")
    ),

    medya_ses = list(
      title = "Medya, Ses ve AI Uzman",
      description = paste(
        "TTS/STT/arka plan müziği yaşam döngüsü, AI Uzman konuşma",
        "yardımcıları, hibrit VoxCPM2 konuşma varlıkları (kilitli persona",
        "referansları + statik karşılama/rehberlik), karakter video ve",
        "görsel üretim/galeri ön yüz sahipliği."
      ),
      manifest_sections = c("ai_expert_helpers", "speech_assets", "module_ai_audio"),
      extra_runtime_files = character(0),
      related_seams = c("sohbet_llm_akis", "kimlik_sso")
    ),

    bilge_yolac = list(
      title = "Bilge Yolaç (Claude Code)",
      description = paste(
        "Claude Code CLI sarmalayıcısı: süreç başlatma, güvenlik",
        "politikaları, prompt yol-güvenliği, runtime workdir, indirme",
        "kartları, doküman çıkarma ve akış modülleri."
      ),
      manifest_sections = c(
        "config_claude_code",
        "claude_code_helpers",
        "module_claude_code",
        "bilge_savunmasi"
      ),
      extra_runtime_files = character(0),
      related_seams = c("api_anahtar_model", "dosya_yasam_dongusu")
    ),

    destek_yonetici_saglik = list(
      title = "Destek, Yönetici Panelleri ve Sistem Durumu",
      description = paste(
        "Destek sayfaları, yönetici analitik/hata/yanıt analizi",
        "modülleri, sağlık kontrol yardımcıları ve Sistem Durumu",
        "panosu (ChartLab etkileşimli modülü dahil)."
      ),
      manifest_sections = c(
        "support_admin_health_helpers",
        "module_support",
        "module_admin",
        "module_health_chartlab"
      ),
      extra_runtime_files = character(0),
      related_seams = c("veritabani_kodlama", "shiny_calisma_zamani")
    ),

    shiny_calisma_zamani = list(
      title = "Shiny Sunucu Çalışma Zamanı",
      description = paste(
        "ServerRuntimeContext, modül wiring, core interaction/observer",
        "runtime, oturum durumu, karşılama ekranı handler'ları ve",
        "observer katmanı; server.R/ui.R orkestrasyon kabukları."
      ),
      manifest_sections = c(
        "server_init_runtime",
        "server_core_outputs_welcome",
        "server_observers"
      ),
      extra_runtime_files = c("server.R", "ui.R"),
      related_seams = c("kimlik_sso", "sohbet_llm_akis", "temel_altyapi")
    ),

    frontend_varlik = list(
      title = "Frontend Varlık Manifesti ve Bölge Sahipliği",
      description = paste(
        "CSS/JS varlık manifesti, yükleme sırası kuralları, render planı,",
        "frontend bölge (zone) sahipliği haritası ve tarayıcı smoke",
        "koruma katmanı."
      ),
      manifest_sections = c("config_ui_assets"),
      extra_runtime_files = character(0),
      related_seams = c("shiny_calisma_zamani", "temel_altyapi")
    )
  )
}

mergen_seam_ids <- function(registry = mergen_seam_registry()) {
  names(registry)
}

mergen_seam_get <- function(id, registry = mergen_seam_registry()) {
  if (!is.character(id) || length(id) != 1L || !nzchar(id)) {
    stop("Seam id tek bir boş olmayan karakter değeri olmalıdır.", call. = FALSE)
  }

  seam <- registry[[id]]

  if (is.null(seam)) {
    stop(sprintf("Seam kayıt defterinde bulunamadı: %s", id), call. = FALSE)
  }

  seam
}

# Bölüm -> seam sahiplik haritasını üretir. Bir bölüm birden fazla seam'de
# listelenmişse hata yerine her ikisini de döndürür; teklik kontrolü
# mergen_seam_registry_validate() içindedir.
mergen_seam_section_owner_map <- function(registry = mergen_seam_registry()) {
  owners <- character(0)

  for (seam_id in names(registry)) {
    sections <- registry[[seam_id]]$manifest_sections

    for (section in sections) {
      owners <- c(owners, stats::setNames(seam_id, section))
    }
  }

  owners
}

# Manifest dışı kabul edilen çalışma zamanı dosyalarının birleşik listesi.
# R/ klasörü "sahipsiz dosya yok" kontrolünde allowlist olarak kullanılır.
mergen_seam_runtime_allowlist <- function(registry = mergen_seam_registry()) {
  files <- character(0)

  for (seam_id in names(registry)) {
    files <- c(files, registry[[seam_id]]$extra_runtime_files)
  }

  sort(unique(files))
}

# Saf yapısal doğrulama. Sorun yoksa character(0), varsa Türkçe sorun
# mesajları döndürür. Çalışma zamanında ÇAĞRILMAZ; testler ve seam doctor
# tarafından kullanılır.
mergen_seam_registry_validate <- function(registry = mergen_seam_registry(),
                                          manifest_section_names = NULL,
                                          zone_owner_seam_ids = NULL,
                                          repo_root = NULL) {
  problems <- character(0)

  if (!is.list(registry) || length(registry) == 0L) {
    return("Seam kayıt defteri boş olmayan bir liste olmalıdır.")
  }

  seam_ids <- names(registry)

  if (is.null(seam_ids) || any(!nzchar(seam_ids)) || anyDuplicated(seam_ids) > 0L) {
    problems <- c(problems, "Seam kayıt defteri benzersiz ve boş olmayan adlarla adlandırılmalıdır.")
  }

  required_fields <- c(
    "title",
    "description",
    "manifest_sections",
    "extra_runtime_files",
    "guard_tests",
    "focused_validation",
    "related_seams"
  )

  for (seam_id in seam_ids) {
    seam <- registry[[seam_id]]

    missing_fields <- setdiff(required_fields, names(seam))

    if (length(missing_fields) > 0L) {
      problems <- c(problems, sprintf(
        "Seam '%s' zorunlu alanları eksik: %s",
        seam_id,
        paste(missing_fields, collapse = ", ")
      ))
      next
    }

    if (!is.character(seam$title) || length(seam$title) != 1L || !nzchar(seam$title)) {
      problems <- c(problems, sprintf("Seam '%s' için title tek satır metin olmalıdır.", seam_id))
    }

    if (!is.character(seam$manifest_sections) || length(seam$manifest_sections) == 0L) {
      problems <- c(problems, sprintf("Seam '%s' en az bir manifest bölümü sahiplenmelidir.", seam_id))
    }

    if (!is.character(seam$guard_tests) || length(seam$guard_tests) == 0L) {
      problems <- c(problems, sprintf("Seam '%s' en az bir guard testi bildirmelidir.", seam_id))
    }

    unknown_related <- setdiff(seam$related_seams, seam_ids)

    if (length(unknown_related) > 0L) {
      problems <- c(problems, sprintf(
        "Seam '%s' bilinmeyen related seam'lere işaret ediyor: %s",
        seam_id,
        paste(unknown_related, collapse = ", ")
      ))
    }
  }

  owner_map <- mergen_seam_section_owner_map(registry)
  owned_sections <- names(owner_map)
  duplicate_sections <- sort(unique(owned_sections[duplicated(owned_sections)]))

  if (length(duplicate_sections) > 0L) {
    problems <- c(problems, sprintf(
      "Manifest bölümleri birden fazla seam tarafından sahiplenilmiş: %s",
      paste(duplicate_sections, collapse = ", ")
    ))
  }

  if (!is.null(manifest_section_names)) {
    missing_sections <- setdiff(manifest_section_names, owned_sections)
    unknown_sections <- setdiff(owned_sections, manifest_section_names)

    if (length(missing_sections) > 0L) {
      problems <- c(problems, sprintf(
        "Sahipsiz manifest bölümü var (bir seam'e atayın): %s",
        paste(missing_sections, collapse = ", ")
      ))
    }

    if (length(unknown_sections) > 0L) {
      problems <- c(problems, sprintf(
        "Seam kayıt defteri manifestte olmayan bölüme işaret ediyor: %s",
        paste(unknown_sections, collapse = ", ")
      ))
    }
  }

  if (!is.null(zone_owner_seam_ids)) {
    unknown_zone_owners <- setdiff(unique(zone_owner_seam_ids), seam_ids)

    if (length(unknown_zone_owners) > 0L) {
      problems <- c(problems, sprintf(
        "Frontend bölge sahibi olarak bilinmeyen seam kullanılmış: %s",
        paste(unknown_zone_owners, collapse = ", ")
      ))
    }
  }

  if (!is.null(repo_root)) {
    for (seam_id in seam_ids) {
      seam <- registry[[seam_id]]

      checked_files <- c(seam$extra_runtime_files, seam$guard_tests)
      missing_files <- checked_files[!file.exists(file.path(repo_root, checked_files))]

      if (length(missing_files) > 0L) {
        problems <- c(problems, sprintf(
          "Seam '%s' var olmayan dosyalara işaret ediyor: %s",
          seam_id,
          paste(missing_files, collapse = ", ")
        ))
      }
    }
  }

  problems
}
