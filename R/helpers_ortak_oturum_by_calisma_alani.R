# ==============================================================================
# Dosya Yolu: R/helpers_ortak_oturum_by_calisma_alani.R
# Açıklama: Ortak Bilge Yolaç çalışma alanı SAF yardımcıları: özel proje dizini
#           güvenlik kapısı (uygulamanın yönettiği dosya köklerine işaret
#           edilemez; oda izolasyonu), etkin çalışma dizini çözümü ve panel
#           kart/rozet HTML üreticileri. Sunucu bağlayıcısı
#           R/module_ortak_oturum_bilge_yolac.R içindedir ve bu dosyadan SONRA
#           yüklenir. Bu dosya Shiny reaktif durumu, DB bağlantısı veya süreç
#           başlatma içermez.
# ==============================================================================

# Yol karşılaştırma anahtarı: normalize + ileri eğik çizgi + Windows'ta
# küçük harf (büyük/küçük harf duyarsız dosya sistemi).
.ortak_by_yol_anahtari <- function(yol) {
  yol <- as.character(yol %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) {
    return("")
  }

  norm <- if (file.exists(yol)) {
    normalizePath(yol, winslash = "/", mustWork = TRUE)
  } else if (identical(dirname(yol), yol)) path.expand(yol) else
    file.path(.ortak_by_yol_anahtari(dirname(yol)), basename(yol))
	
  norm <- gsub("\\\\", "/", norm)
  norm <- sub("/+$", "", norm)
  norm <- enc2utf8(norm)

  if (identical(.Platform$OS.type, "windows")) tolower(norm) else norm
}

.ortak_by_kok_icinde_mi <- function(yol, kok) {
  y <- .ortak_by_yol_anahtari(yol)
  k <- .ortak_by_yol_anahtari(kok)
  nzchar(y) && nzchar(k) && startsWith(paste0(y, "/"), paste0(k, "/"))
}

# Dizin varlığı (relaxed): UNC/Türkçe karakter yolları için Bilge Yolaç
# çözücüsü varsa o kullanılır; yoksa base dir.exists.
.ortak_by_dizin_var_mi <- function(yol) {
  yol <- as.character(yol %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) {
    return(FALSE)
  }

  if (exists("cc_resolve_existing_dir_relaxed", mode = "function", inherits = TRUE)) {
    cozulen <- tryCatch(cc_resolve_existing_dir_relaxed(yol), error = function(e) "")
    if (nzchar(as.character(cozulen %||% "")[1])) {
      return(TRUE)
    }
  }

  isTRUE(tryCatch(dir.exists(yol), error = function(e) FALSE))
}

# Uygulamanın yönettiği dosya kökleri: ortak dosya kökü, kalıcı yükleme ve MCP
# tabanları. Özel proje dizini bu köklerin İÇİNE işaret edemez (başka odanın
# çalışma alanını veya başka kullanıcının dosya kovasını okuma riski).
ortak_by_yonetilen_kokler <- function() {
  adaylar <- character(0)

  files_root <- getOption("mergen.files_root", NULL)
  if (is.null(files_root) || !nzchar(as.character(files_root)[1])) {
    files_root <- Sys.getenv("MERGEN_FILES_ROOT", unset = "")
  }
  adaylar <- c(adaylar, as.character(files_root)[1])

  adaylar <- c(
    adaylar,
    Sys.getenv("MERGEN_UPLOADS_DIR", unset = ""),
    Sys.getenv("MERGEN_MCP_BASE_DIR", unset = ""),
    Sys.getenv("MCP_FILES_BASE", unset = "")
  )

  adaylar <- adaylar[!is.na(adaylar) & nzchar(adaylar)]
  unique(adaylar)
}

# Özel proje dizini oda izolasyon kapısı (SAF karar). NULL = engel yok;
# aksi halde kullanıcıya gösterilecek Türkçe engel nedeni döner.
# Odanın KENDİ ortak dosya kökü altındaki yollar serbesttir; diğer tüm
# yönetilen kök içi yollar (başka odalar, kişisel kovalar, indeks alanı)
# reddedilir.
ortak_by_ozel_dizin_engeli <- function(yol,
                                       oturum_id,
                                       yonetilen_kokler = ortak_by_yonetilen_kokler(),
                                       oda_koku = NULL) {
  yol <- trimws(as.character(yol %||% "")[1])
  if (is.na(yol) || !nzchar(yol)) {
    return("Proje dizini boş olamaz.")
  }

  if (is.null(oda_koku) &&
      exists("ortak_oturum_dosya_koku", mode = "function", inherits = TRUE)) {
    oda_koku <- tryCatch(ortak_oturum_dosya_koku(oturum_id), error = function(e) NULL)
  }

  oda_koku <- as.character(oda_koku %||% "")[1]
  if (!is.na(oda_koku) && nzchar(oda_koku) && .ortak_by_kok_icinde_mi(yol, oda_koku)) {
    return(NULL)
  }

  for (kok in yonetilen_kokler) {
    if (.ortak_by_kok_icinde_mi(yol, kok)) {
      return(paste(
        "Bu dizin MERGEN Bilge'nin yönettiği dosya alanının içinde;",
        "başka bir odanın veya kullanıcının dosya alanına işaret edilemez.",
        "Paylaşmak istediğiniz dosyaları kopyalama eylemleriyle çalışma alanına alın."
      ))
    }
  }

  NULL
}

# Özel proje dizini tam doğrulaması: önce oda izolasyon kapısı, sonra merkezi
# Bilge Yolaç çalışma dizini politikası (cc_policy_validate_workdir; kullanıcı
# seçimli dizin izni claude_code_config'ten). Politika katmanı olmayan izole
# bağlamlarda en azından dizin varlığı aranır.
# @return list(ok=, path=, error=)
ortak_by_ozel_dizin_dogrula <- function(yol, oturum_id, user_id = NULL) {
  yol <- trimws(as.character(yol %||% "")[1])

  engel <- ortak_by_ozel_dizin_engeli(yol, oturum_id)
  if (!is.null(engel)) {
    return(list(ok = FALSE, path = yol, error = engel))
  }

  if (exists("cc_policy_validate_workdir", mode = "function", inherits = TRUE)) {
    izinli <- TRUE
    if (exists("claude_code_config", inherits = TRUE) &&
        exists("cc_policy_truthy", mode = "function", inherits = TRUE)) {
      izinli <- cc_policy_truthy(
        get("claude_code_config", inherits = TRUE)$allow_user_selected_workdirs %||% TRUE
      )
    }
    return(tryCatch(
      cc_policy_validate_workdir(yol, user_id = user_id, allow_selected_workdir = izinli),
      error = function(e) list(ok = FALSE, path = yol, error = "Çalışma dizini doğrulanamadı.")
    ))
  }

  if (!.ortak_by_dizin_var_mi(yol)) {
    return(list(ok = FALSE, path = yol, error = paste0("Çalışma dizini bulunamadı: ", yol)))
  }

  list(ok = TRUE, path = yol, error = "")
}

# Odanın etkin çalışma dizini: kayıttaki özel dizin varsa ve erişilebilirse o;
# değilse paylaşılan otomatik oda klasörü. Karar SAF'tır; otomatik klasör
# üreticisi enjekte edilebilir (izole test).
# @return list(yol=, ozel=TRUE/FALSE)
ortak_by_etkin_calisma_dizini <- function(kayit_dizini,
                                          oturum_id,
                                          otomatik_fn = NULL) {
  ozel <- trimws(as.character(kayit_dizini %||% "")[1])
  if (!is.na(ozel) && nzchar(ozel) && .ortak_by_dizin_var_mi(ozel)) {
    return(list(yol = ozel, ozel = TRUE))
  }

  if (is.null(otomatik_fn) &&
      exists("ortak_by_calisma_alani", mode = "function", inherits = TRUE)) {
    otomatik_fn <- get("ortak_by_calisma_alani", inherits = TRUE)
  }
  yol <- if (is.function(otomatik_fn)) otomatik_fn(oturum_id) else NULL

  list(yol = yol, ozel = FALSE)
}

# ------------------------------------------------------------------------------
# SAF HTML üreticileri (tek kullanıcılı Bilge Yolaç kart dilinin oda sürümü;
# tüm kullanıcı metinleri escape edilir)
# ------------------------------------------------------------------------------

# Panel iskeleti: statik başlık (aç/kapa + başlık + CLI rozet yuvası) + kart
# ızgarası. VARSAYILAN KAPALI (oo-by-panel-kapali) gelir; aç/kapa tercihi JS
# köprüsünde saklanır ve yoklama yalnızca iç kart çıktılarını tazelediği için
# tercih yeniden render'da korunur. Dinamik içerikler uiOutput yuvalarındadır.
oo_by_panel_iskeleti_html <- function(ns, senaryolar = list()) {
  div(
    class = "oo-by-panel oo-by-panel-kapali",
    `data-oo-by-panel` = "1",
    div(
      class = "oo-by-baslik",
      tags$button(
        type = "button",
        class = "oo-by-toggle",
        `data-oo-toggle-by` = "1",
        `aria-label` = "Bilge Yolaç çalışma alanı panelini aç/kapat",
        icon("chevron-down", class = "oo-by-toggle-ikon")
      ),
      icon("robot", class = "oo-by-baslik-ikon"),
      span(class = "oo-by-baslik-metin", "Bilge Yolaç Çalışma Alanı"),
      uiOutput(ns("by_durum_rozeti"), inline = TRUE),
      tags$span(
        class = "oo-by-baslik-ipucu",
        "Proje dizini, model ve senaryolar için paneli açın"
      )
    ),
    div(
      class = "oo-by-govde",
      div(
        class = "oo-by-kart-grid",
        uiOutput(ns("by_proje_dizini_karti"), class = "oo-by-kart-yuva oo-by-yuva-genis"),
        uiOutput(ns("by_model_karti"), class = "oo-by-kart-yuva"),
        oo_by_kart_html(
          "Hazır Senaryolar", "bolt",
          div(
            class = "oo-by-senaryo-grid",
            lapply(senaryolar, function(senaryo) {
              actionButton(
                ns(paste0("by_senaryo_", senaryo$id)),
                label = tagList(icon(senaryo$ikon), span(senaryo$baslik)),
                class = "oo-by-senaryo-btn",
                title = senaryo$aciklama
              )
            })
          )
        ),
        oo_by_kart_html(
          "Dizin İçeriği", "folder-tree",
          div(
            class = "oo-by-dizin-baslik",
            uiOutput(ns("by_dizin_yolu_alani"), inline = TRUE),
            actionButton(
              ns("by_dizin_yenile"),
              label = NULL,
              icon = icon("sync"),
              class = "oo-by-mini-btn",
              `aria-label` = "Dizin içeriğini yenile"
            )
          ),
          div(class = "oo-by-dizin-listesi", uiOutput(ns("by_dizin_icerigi")))
        ),
        uiOutput(ns("by_dosya_eylem_karti"), class = "oo-by-kart-yuva oo-by-yuva-genis"),
        oo_by_kart_html(
          "Eklentiler", "puzzle-piece",
          div(class = "oo-by-eklenti-listesi", uiOutput(ns("by_eklentiler")))
        ),
        oo_by_kart_html(
          "Çalıştırma Geçmişi", "clock-rotate-left",
          div(class = "oo-by-gecmis-listesi", uiOutput(ns("by_calistirma_gecmisi")))
        )
      )
    )
  )
}

# Genel çalışma alanı kartı: başlık şeridi + içerik gövdesi.
oo_by_kart_html <- function(baslik, ikon, ..., sinif = NULL) {
  div(
    class = paste("oo-by-kart", sinif),
    div(
      class = "oo-by-kart-baslik",
      icon(ikon, class = "oo-by-kart-ikon"),
      tags$span(HTML(htmltools::htmlEscape(baslik)))
    ),
    div(class = "oo-by-kart-icerik", ...)
  )
}

# CLI bağlantı durumu rozeti (panel başlığında).
oo_by_durum_rozeti_html <- function(cli_bagli) {
  if (isTRUE(cli_bagli)) {
    tags$span(
      class = "oo-rozet oo-rozet-cli-bagli",
      tagList(icon("plug"), span("CLI Bağlı"))
    )
  } else {
    tags$span(
      class = "oo-rozet oo-rozet-cli-yok",
      title = "Claude Code CLI bu ortamda bulunamadı; sorular genel yapay zekâ modeliyle yanıtlanır.",
      tagList(icon("plug-circle-xmark"), span("CLI Bağlı Değil"))
    )
  }
}

# Proje Dizini kartı gövdesi: yazma yetkili roller için düzenlenebilir yol
# girdisi + uygula/sıfırla eylemleri; diğer katılımcılar için salt-okunur yol.
oo_by_proje_dizini_govde_html <- function(girdi_id,
                                          uygula_id,
                                          sifirla_id,
                                          yol,
                                          ozel = FALSE,
                                          yazabilir = FALSE) {
  yol <- as.character(yol %||% "")[1]
  if (is.na(yol)) {
    yol <- ""
  }

  durum_rozeti <- if (isTRUE(ozel)) {
    tags$span(
      class = "oo-rozet oo-by-dizin-ozel",
      title = "Oda, yazılan özel proje dizininde çalışıyor",
      tagList(icon("folder-tree"), span("Özel proje dizini"))
    )
  } else {
    tags$span(
      class = "oo-rozet oo-by-dizin-paylasilan",
      title = "Oda, otomatik oluşturulan paylaşılan klasöründe çalışıyor",
      tagList(icon("users"), span("Paylaşılan oda klasörü"))
    )
  }

  if (!isTRUE(yazabilir)) {
    return(tagList(
      tags$code(
        class = "oo-by-dizin-yolu",
        title = yol,
        HTML(htmltools::htmlEscape(
          if (nzchar(yol)) yol else "Çalışma alanı hazırlanamadı"
        ))
      ),
      div(class = "oo-by-dizin-durum", durum_rozeti)
    ))
  }

  tagList(
    div(
      class = "oo-by-dizin-girdi-satiri",
      tags$input(
        id = girdi_id,
        type = "text",
        class = "form-control oo-by-dizin-girdisi",
        value = yol,
        placeholder = "Proje klasör yolunu girin veya yapıştırın...",
        `aria-label` = "Bilge Yolaç proje dizini yolu"
      ),
      actionButton(
        uygula_id,
        label = NULL,
        icon = icon("check"),
        class = "oo-by-mini-btn oo-by-dizin-uygula",
        title = "Yazılan yolu odanın proje dizini yap"
      ),
      actionButton(
        sifirla_id,
        label = NULL,
        icon = icon("rotate-left"),
        class = "oo-by-mini-btn",
        title = "Paylaşılan oda klasörüne geri dön"
      )
    ),
    div(
      class = "oo-by-dizin-durum",
      durum_rozeti,
      tags$small(
        class = "oo-by-dizin-ipucu",
        "Ağ/proje klasörü yazabilirsiniz; uygulanınca tüm oda bu dizinde çalışır."
      )
    )
  )
}

# Model katmanı düğmeleri (Hızlı/Dengeli/Güçlü): tek kullanıcılı katman
# düğmeleriyle aynı dil; seçim delege JS köprüsüyle hedef girdiye yazılır.
oo_by_model_govde_html <- function(katmanlar, secili, hedef_input_id) {
  if (length(katmanlar) == 0L) {
    return(tags$span(class = "oo-by-model-yok", "Model katmanı bulunamadı (settings.json)"))
  }

  secili <- as.character(secili %||% "")[1]
  if (is.na(secili)) {
    secili <- ""
  }

  div(
    class = "oo-by-model-grup",
    lapply(seq_along(katmanlar), function(i) {
      katman <- katmanlar[[i]]
      deger <- as.character(katman$deger %||% "")[1]
      ikon <- as.character(katman$ikon %||% "")[1]
      aktif <- identical(deger, secili) || (!nzchar(secili) && i == 1L)

      tags$button(
        type = "button",
        class = paste("oo-by-model-btn", if (aktif) "oo-by-model-aktif" else NULL),
        title = katman$aciklama %||% "",
        `data-oo-model-deger` = deger,
        `data-oo-hedef-input` = hedef_input_id,
        if (nzchar(ikon) && !is.na(ikon)) tags$i(class = paste0("fas ", ikon)) else NULL,
        tags$span(HTML(htmltools::htmlEscape(katman$etiket %||% "Model")))
      )
    })
  )
}

# Dizin içeriği satırları.
oo_by_dizin_satirlari_html <- function(ogeler) {
  tagList(lapply(ogeler, function(oge) {
    klasor <- identical(as.character(oge$tip %||% ""), "klasor")
    ad <- as.character(oge$gorunen_ad %||% oge$ad %||% "")[1]
    boyut <- as.character(oge$boyut %||% "")[1]

    div(
      class = "oo-by-dizin-satiri",
      icon(if (klasor) "folder" else "file-lines", class = "oo-by-dizin-ikon"),
      tags$span(class = "oo-by-dizin-ad", title = ad, HTML(htmltools::htmlEscape(ad))),
      if (nzchar(boyut) && !is.na(boyut)) {
        tags$span(class = "oo-by-dizin-boyut", HTML(htmltools::htmlEscape(boyut)))
      } else {
        NULL
      }
    )
  }))
}

# Eklenti envanter satırları (salt-okunur).
oo_by_eklenti_listesi_html <- function(pluginler, bilesen_tanimlari = list()) {
  if (length(pluginler) == 0L) {
    return(div(class = "oo-by-eklenti-yok", "Kurulu eklenti bulunamadı."))
  }

  tagList(lapply(pluginler, function(p) {
    div(
      class = "oo-by-eklenti-satiri",
      title = as.character(p$description %||% ""),
      icon("puzzle-piece", class = "oo-by-eklenti-ikon"),
      tags$span(class = "oo-by-eklenti-ad", HTML(htmltools::htmlEscape(as.character(p$name %||% "")))),
      tags$span(
        class = "oo-by-eklenti-bilesen",
        HTML(htmltools::htmlEscape(paste(
          vapply(as.character(p$components %||% character(0)), function(b) {
            tanim <- bilesen_tanimlari[[b]]
            if (is.list(tanim)) tanim$etiket %||% b else b
          }, character(1)),
          collapse = " · "
        )))
      )
    )
  }))
}

# Çalıştırma geçmişi satırları (en yeni 5).
oo_by_gecmis_listesi_html <- function(calistirmalar) {
  if (!is.data.frame(calistirmalar) || nrow(calistirmalar) == 0L) {
    return(div(class = "oo-by-eklenti-yok", "Henüz çalıştırma yok."))
  }

  calistirmalar <- calistirmalar[
    order(calistirmalar$CalistirmaSirasi, decreasing = TRUE), , drop = FALSE
  ]
  calistirmalar <- utils::head(calistirmalar, 5L)

  tagList(lapply(seq_len(nrow(calistirmalar)), function(i) {
    satir <- calistirmalar[i, , drop = FALSE]
    durum <- as.character(satir$Durum[1] %||% "")
    komut <- as.character(satir$Komut[1] %||% "")
    if (nchar(komut) > 70L) {
      komut <- paste0(substr(komut, 1L, 70L), "…")
    }
    veren <- as.character(satir$KomutuVerenAdi[1] %||% "")
    sure <- suppressWarnings(as.numeric(satir$SureSaniye[1]))

    durum_sinifi <- switch(
      durum,
      "Tamamlandı" = "oo-by-durum-tamam",
      "Çalışıyor" = "oo-by-durum-calisiyor",
      "oo-by-durum-hata"
    )

    div(
      class = "oo-by-gecmis-satiri",
      tags$span(class = paste("oo-rozet", durum_sinifi), HTML(htmltools::htmlEscape(durum))),
      tags$span(
        class = "oo-by-gecmis-komut",
        title = as.character(satir$Komut[1] %||% ""),
        HTML(htmltools::htmlEscape(komut))
      ),
      tags$span(
        class = "oo-by-gecmis-meta",
        HTML(htmltools::htmlEscape(paste(
          Filter(nzchar, c(
            veren,
            if (!is.na(sure)) sprintf("%.0f sn", sure) else ""
          )),
          collapse = " · "
        )))
      )
    )
  }))
}