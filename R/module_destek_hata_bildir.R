# Dosya Yolu: R/module_destek_hata_bildir.R
# Açıklama: Hata Bildirimi alt modülü.
#            Hata konuları, kategoriler, öncelik seviyesi, açıklama ve
#            dosya ekleri (ekler) yönetimini sağlar.

# ==============================================================================
# HATA BİLDİR UI
# ==============================================================================

destekHataBildirUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-form-card",

      # Konu (Zorunlu - Çoklu giriş) - Dinamik etiket JS ile güncellenir
      div(
        class = "destek-form-group",
        tags$label(
          class = "destek-form-label destek-label-required",
          id = ns("konu_label"),
          "Konu"
        ),
        div(
          id = ns("konular_container"),
          class = "destek-konular-container",
          # İlk konu girişi
          div(
            class = "destek-konu-row",
            `data-index` = "1",
            tags$input(
              type = "text",
              class = "destek-text-input destek-konu-input",
              id = ns("konu_1"),
              placeholder = "Örn: Profil resmi yüklenmiyor",
              maxlength = "200",
              oninput = sprintf("destekCollectKonular('%s')", ns(""))
            )
          )
        ),
        # Yeni konu ekleme butonu
        div(
          class = "destek-add-btn-wrapper",
          tags$button(
            id = ns("konu_ekle_btn"),
            class = "destek-add-btn",
            type = "button",
            onclick = sprintf("destekAddKonu('%s')", ns("")),
            icon("plus"),
            "Konu Ekle"
          )
        ),
        div(id = ns("hata_konular"), class = "destek-error-msg", style = "display:none;",
          icon("circle-exclamation"),
          "Lütfen en az bir konu girin."
        )
      ),

      # Kategori (Zorunlu - Çoklu seçim) - Animasyonlu ikonlar
      div(
        class = "destek-form-group",
        tags$label(
          class = "destek-form-label destek-label-required",
          "Kategori"
        ),
        div(
          class = "destek-category-container",
          id = ns("kategori_container"),
          lapply(list(
            list(id = "arayuz", label = "Arayüz / Tasarım", icon = "palette", renk = "purple"),
            list(id = "fonksiyonellik", label = "Fonksiyonellik", icon = "wrench", renk = "blue"),
            list(id = "performans", label = "Performans", icon = "bolt", renk = "amber"),
            list(id = "cokme", label = "Çökme / Hata", icon = "triangle-exclamation", renk = "red"),
            list(id = "diger", label = "Diğer", icon = "ellipsis", renk = "cyan")
          ), function(kat) {
            div(
              class = paste0("destek-category-btn destek-cat-", kat$renk),
              `data-category` = kat$id,
              onclick = sprintf(
                "destekToggleCategory(this, '%s')",
                ns("secili_kategoriler")
              ),
              div(class = paste0("destek-cat-icon-wrapper destek-cat-icon-", kat$renk),
                icon(kat$icon)
              ),
              span(kat$label)
            )
          })
        ),
        tags$input(
          type = "hidden",
          id = ns("secili_kategoriler"),
          name = ns("secili_kategoriler"),
          value = ""
        ),
        div(id = ns("hata_kategoriler"), class = "destek-error-msg", style = "display:none;",
          icon("circle-exclamation"),
          "Lütfen en az bir kategori seçin."
        )
      ),

      # Öncelik Seviyesi (Opsiyonel - seçim iptal edilebilir)
      div(
        class = "destek-form-group",
        tags$label(class = "destek-form-label", "Öncelik Seviyesi"),
        div(
          class = "destek-priority-container",
          id = ns("oncelik_container"),
          lapply(list(
            list(id = "dusuk", label = "Düşük", renk = "blue"),
            list(id = "orta", label = "Orta", renk = "amber"),
            list(id = "yuksek", label = "Yüksek", renk = "orange"),
            list(id = "kritik", label = "Kritik", renk = "red")
          ), function(onc) {
            div(
              class = "destek-priority-btn",
              `data-priority` = onc$id,
              onclick = sprintf(
                "destekSelectPriority(this, '%s')",
                ns("secili_oncelik")
              ),
              span(class = paste0("destek-priority-dot destek-dot-", onc$renk)),
              span(onc$label)
            )
          })
        ),
        tags$input(
          type = "hidden",
          id = ns("secili_oncelik"),
          name = ns("secili_oncelik"),
          value = ""
        )
      ),

      # Açıklama & Yeniden Üretme Adımları (Zorunlu)
      div(
        class = "destek-form-group",
        tags$label(
          class = "destek-form-label destek-label-required",
          "Açıklama & Yeniden Üretme Adımları"
        ),
        div(
          class = "destek-textarea-wrapper",
          tags$textarea(
            id = ns("hata_aciklama"),
            class = "destek-textarea destek-textarea-lg",
            placeholder = "Sorunu nasıl yaşadığınızı adım adım anlatın...",
            maxlength = "500",
            rows = 6,
            oninput = sprintf("destekUpdateCharCount(this, '%s')", ns("aciklama_counter"))
          ),
          span(id = ns("aciklama_counter"), class = "destek-char-counter", "0 / 500")
        ),
        div(id = ns("hata_aciklama_msg"), class = "destek-error-msg", style = "display:none;",
          icon("circle-exclamation"),
          "Lütfen açıklama alanını doldurun."
        )
      ),

      # Ekler (Opsiyonel - Sürükle-Bırak)
      div(
        class = "destek-form-group",
        tags$label(class = "destek-form-label", "Ekler"),
        div(
          id = ns("upload_zone"),
          class = "destek-upload-zone",
          ondragover = "event.preventDefault(); this.classList.add('destek-drag-over');",
          ondragleave = "this.classList.remove('destek-drag-over');",
          ondrop = sprintf("destekHandleDrop(event, '%s')", ns("")),
          onclick = sprintf("document.getElementById('%s').click();", ns("dosya_input")),
          div(class = "destek-upload-content",
            icon("cloud-arrow-up", class = "destek-upload-icon"),
            p(class = "destek-upload-text",
              "Dosyaları sürükleyin veya ",
              tags$span(class = "destek-upload-link", "göz atın")
            ),
            p(class = "destek-upload-hint",
              "PNG, JPG, GIF, MP4 \U2022 Maks. 10MB")
          )
        ),
        # Gizli dosya girişi
        tags$input(
          type = "file",
          id = ns("dosya_input"),
          style = "display:none;",
          multiple = "multiple",
          accept = "image/png,image/jpeg,image/gif,video/mp4"
        ),
        # Yüklenen dosya listesi
        div(
          id = ns("dosya_listesi"),
          class = "destek-file-list"
        )
      ),

      # Gönder butonu
      div(
        class = "destek-form-actions",
        div(
          class = "destek-submit-wrapper",
          actionButton(
            ns("gonder_hata"),
            label = tagList(icon("paper-plane"), "Gönder"),
            class = "destek-submit-btn",
            title = "Ctrl + Enter ile gönder"
          )
        )
      )
    )
  )
}

# ==============================================================================
# HATA BİLDİR SERVER
# ==============================================================================

destekHataBildirServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    resolve_current_user_id <- function() {
      resolve_effective_user_id(
        session = session,
        current_user_id = current_user_id
      )
    }

    yuklenen_dosyalar <- reactiveVal(list())
    basarili_trigger <- reactiveVal(0)

    # Ek dosyaların fiziksel kökü sunucu tarafından belirlenir; istemciden gelen
    # hiçbir yol bu kökün dışını gösteremez.
    destek_ek_koku <- function() {
      kok <- tryCatch(
        normalizePath("destek_uploads", winslash = "/", mustWork = FALSE),
        error = function(e) "destek_uploads"
      )
      sub("/+$", "", gsub("\\\\", "/", kok))
    }

    # Tarayıcı dosya adına güvenilmez: yol ayırıcı/'..' içeren bir ad hedef yolu
    # destek_uploads kökünün dışına taşıyabilirdi. Yalnızca taban ad kullanılır.
    destek_ek_adi_temizle <- function(ad) {
      ad <- as.character(ad %||% "")[1]
      if (is.na(ad)) ad <- ""
      ad <- basename(gsub("\\\\", "/", ad))
      ad <- gsub("[/\\\\]", "_", ad)
      # Windows normal dosya adında `: * ? " < > |` kabul etmez; Windows DIŞI
      # bir istemciden gelen `log:1.png` gibi bir ad `file.copy()` çağrısını
      # sunucuda başarısız kılıyordu.
      ad <- gsub("[:*?\"<>|]", "_", ad, perl = TRUE)
      # Ad bileşeninin sonundaki nokta/boşluk da Windows'ta geçersizdir.
      ad <- sub("[ .]+$", "", ad)
      if (ad %in% c("", ".", "..")) ad <- "ek"
      ad
    }

    # Ek yolu YALNIZCA ETKİN KULLANICININ kendi alt klasöründe olabilir. Ortak
    # `destek_uploads` kökünü denetlemek yeterli değildi: aynı tarayıcı
    # oturumunda kimlik değişirse (token süresi dolup yeniden giriş) yeni
    # kullanıcı, eski kullanıcının ekini silebiliyor ya da kendi bildirimine
    # ekleyebiliyordu.
    destek_ek_yolu_guvenli <- function(yol, user_id = NULL) {
      yol <- as.character(yol %||% "")[1]
      if (is.na(yol) || !nzchar(yol)) return(FALSE)

      yol_slash <- sub("/+$", "", gsub("\\\\", "/", yol))
      if (!nzchar(yol_slash)) return(FALSE)
      if (grepl("(^|/)\\.\\.(/|$)", yol_slash, perl = TRUE)) return(FALSE)

      # HEDEF DOSYA HENÜZ VAR OLMAYABİLİR. POSIX'te
      # `normalizePath(yol, mustWork = FALSE)` var olmayan yolu OLDUĞU GİBİ
      # (göreli) döndürürken `destek_ek_koku()` MUTLAK yol üretiyor; önek kıyası
      # bu yüzden FALSE oluyor ve kimliği doğrulanmış HER yükleme `file.copy()`
      # çalışmadan reddediliyordu. ÜST DİZİN (çağrı anında zaten oluşturulmuştur)
      # normalize edilir ve hedef `basename()` ile yeniden kurulur.
      ust <- tryCatch(
        normalizePath(dirname(yol_slash), winslash = "/", mustWork = FALSE),
        error = function(e) dirname(yol_slash)
      )
      ust <- sub("/+$", "", gsub("\\\\", "/", ust))
      hedef <- paste0(ust, "/", basename(yol_slash))
      if (grepl("(^|/)\\.\\.(/|$)", hedef, perl = TRUE)) return(FALSE)

      uid <- suppressWarnings(as.integer(user_id %||% NA_integer_)[1])
      kok <- if (!is.na(uid) && uid > 0L) {
        paste0(destek_ek_koku(), "/", as.character(uid), "/")
      } else {
        paste0(destek_ek_koku(), "/")
      }

      startsWith(hedef, kok)
    }

    observeEvent(input$dosya_bilgisi, {
      dosya_verisi <- input$dosya_bilgisi
      if (is.null(dosya_verisi)) return()

      mevcut <- yuklenen_dosyalar()

      if (!is.null(dosya_verisi$size) && dosya_verisi$size > 10 * 1024 * 1024) {
        showToast(session, "Dosya boyutu 10MB'dan büyük olamaz.", "error")
        return()
      }

      # İstemciden gelen `path` alanına GÜVENİLMEZ: keyfi sunucu dosyasının
      # silinmesine veya eke iliştirilmesine yol açıyordu. Fiziksel yol yalnızca
      # gerçek fileInput yükleme yolunda sunucu tarafından üretilir.
      mevcut[[length(mevcut) + 1]] <- list(
        name = as.character(dosya_verisi$name %||% "")[1],
        size = suppressWarnings(as.numeric(dosya_verisi$size %||% NA_real_)[1]),
        path = NULL
      )
      yuklenen_dosyalar(mevcut)
    }, ignoreInit = TRUE)

    # Kimlik DEĞİŞİRSE ek durumu temizlenir: aksi hâlde yeni kullanıcı, önceki
    # kullanıcının ek listesini görmeye devam ediyordu.
    ek_sahibi_uid <- reactiveVal(NA_integer_)
    # Silinemeyen ekler yeniden denenmek üzere kuyrukta tutulur; yeni kullanıcıya
    # GÖRÜNMEZLER (liste her durumda temizlenir).
    ek_silme_kuyrugu <- reactiveVal(character(0))

    observe({
      aktif <- suppressWarnings(as.integer(resolve_current_user_id())[1])
      onceki <- isolate(ek_sahibi_uid())
      if (identical(aktif, onceki)) return(invisible(NULL))

      ek_sahibi_uid(aktif)
      if (is.na(onceki)) return(invisible(NULL))

      # GÖNDERİLMEMİŞ ekler diskte KALMAMALIDIR: hiçbir modül/oturum yaşam
      # döngüsü `destek_uploads/<eski-uid>/...` dosyalarını kaldırmıyordu.
      adaylar <- vapply(
        isolate(yuklenen_dosyalar()),
        function(e) as.character(e$path %||% "")[1],
        character(1)
      )
      adaylar <- c(isolate(ek_silme_kuyrugu()), adaylar)
      adaylar <- unique(adaylar[!is.na(adaylar) & nzchar(adaylar)])

      kalan <- character(0)
      for (ek_yolu in adaylar) {
        # Silme YALNIZCA ÖNCEKİ sahibin alt klasöründe geçerlidir.
        if (!isTRUE(destek_ek_yolu_guvenli(ek_yolu, onceki))) next
        if (!isTRUE(file.exists(ek_yolu))) next
        silindi <- isTRUE(suppressWarnings(file.remove(ek_yolu))) &&
          !isTRUE(file.exists(ek_yolu))
        if (!silindi) kalan <- c(kalan, ek_yolu)
      }
      ek_silme_kuyrugu(kalan)

      if (length(isolate(yuklenen_dosyalar())) > 0L) {
        yuklenen_dosyalar(list())
        shinyjs::runjs(sprintf("destekUpdateFileList('%s', []);", ns("")))
      }
    })

    observeEvent(input$dosya_sil, {
      idx <- as.integer(input$dosya_sil)
      if (is.null(idx) || is.na(idx)) return()

      mevcut <- yuklenen_dosyalar()
      if (idx >= 1 && idx <= length(mevcut)) {
        silinecek <- mevcut[[idx]]$path
        aktif_uid <- resolve_current_user_id()
        # Sahibi FARKLI olan ek silinemez: kayıt yalnızca sahibinin alt
        # klasöründe geçerlidir.
        if (!is.null(silinecek) &&
            !isTRUE(destek_ek_yolu_guvenli(silinecek, aktif_uid))) {
          showToast(session, "Bu ek bu oturuma ait değil.", "warning")
          return(invisible(NULL))
        }
        silme_tamam <- TRUE
        if (!is.null(silinecek) && destek_ek_yolu_guvenli(silinecek, aktif_uid) &&
            file.exists(silinecek)) {
          # file.remove() kilitli dosya / erişim hatasında FALSE döner. Ek
          # durumunu yine de kaldırmak, dosyayı destek_uploads altında bırakıp
          # kullanıcıyı ne silebilir ne gönderebilir hâle getiriyordu.
          silme_tamam <- isTRUE(suppressWarnings(file.remove(silinecek))) &&
            !isTRUE(file.exists(silinecek))
        }

        if (!isTRUE(silme_tamam)) {
          showToast(session, "Dosya silinemedi; lütfen tekrar deneyin.", "error")
          return(invisible(NULL))
        }

        mevcut[[idx]] <- NULL
        yuklenen_dosyalar(mevcut)

        shinyjs::runjs(sprintf(
          "destekUpdateFileList('%s', %s);",
          ns(""),
          jsonlite::toJSON(lapply(mevcut, function(d) {
            list(name = d$name, size = d$size)
          }), auto_unbox = TRUE)
        ))
      }
    }, ignoreInit = TRUE)

    observeEvent(input$dosya_input, {
      dosyalar <- input$dosya_input
      if (is.null(dosyalar)) return()

      effective_user_id <- resolve_current_user_id()
      if (effective_user_id <= 0) {
        showToast(session, "Kimlik doğrulama tamamlanmadan dosya yüklenemez.", "warning")
        return(invisible(NULL))
      }

      if (is.data.frame(dosyalar)) {
        for (i in seq_len(nrow(dosyalar))) {
          dosya <- dosyalar[i, ]
          if (dosya$size > 10 * 1024 * 1024) {
            showToast(session, paste0(dosya$name, " dosyası 10MB sınırını aşıyor."), "error")
            next
          }

          hedef_dir <- file.path("destek_uploads", as.character(effective_user_id))
          if (!dir.exists(hedef_dir)) dir.create(hedef_dir, recursive = TRUE)

          # ÇARPIŞMA GÜVENLİ AD: yalnızca saniye çözünürlüklü damga, aynı
          # saniyede yüklenen iki ekte aynı yolu üretiyor; `file.copy()`
          # varsayılan `overwrite = FALSE` ile FALSE dönüyor ve yeni ek ESKİ
          # dosyayı gösteriyordu.
          hedef_yol <- file.path(
            hedef_dir,
            paste0(
              format(Sys.time(), "%Y%m%d%H%M%S"), "_",
              basename(tempfile("")), "_",
              destek_ek_adi_temizle(dosya$name)
            )
          )

          if (!destek_ek_yolu_guvenli(hedef_yol, effective_user_id)) {
            showToast(session, paste0(dosya$name, " dosyası güvenli konuma yazılamadı."), "error")
            next
          }

          # KOPYA DOĞRULANIR: sonuç yok sayıldığında hiç kaydedilmemiş bir ek
          # arayüzde/DB'de kayıtlı görünüyordu.
          kopyalandi <- isTRUE(tryCatch(
            suppressWarnings(file.copy(dosya$datapath, hedef_yol)),
            error = function(e) FALSE
          ))
          if (!kopyalandi || !file.exists(hedef_yol)) {
            try(unlink(hedef_yol, force = TRUE), silent = TRUE)
            showToast(session, paste0(dosya$name, " dosyası kaydedilemedi."), "error")
            next
          }

          mevcut <- yuklenen_dosyalar()
          mevcut[[length(mevcut) + 1]] <- list(
            name = dosya$name,
            size = dosya$size,
            path = hedef_yol
          )
          yuklenen_dosyalar(mevcut)
        }

        mevcut <- yuklenen_dosyalar()
        shinyjs::runjs(sprintf(
          "destekUpdateFileList('%s', %s);",
          ns(""),
          jsonlite::toJSON(lapply(mevcut, function(d) {
            list(name = d$name, size = d$size)
          }), auto_unbox = TRUE)
        ))
      }
    }, ignoreInit = TRUE)

    observeEvent(input$gonder_hata, {
      hatalar <- FALSE

      konular_text <- input$konular_birlesik
      if (is.null(konular_text) || !nzchar(trimws(konular_text %||% ""))) {
        shinyjs::show("hata_konular")
        hatalar <- TRUE
      } else {
        shinyjs::hide("hata_konular")
      }

      kategoriler <- input$secili_kategoriler
      if (is.null(kategoriler) || kategoriler == "") {
        shinyjs::show("hata_kategoriler")
        hatalar <- TRUE
      } else {
        shinyjs::hide("hata_kategoriler")
      }

      aciklama <- input$hata_aciklama
      if (is.null(aciklama) || !nzchar(trimws(aciklama %||% ""))) {
        shinyjs::show("hata_aciklama_msg")
        hatalar <- TRUE
      } else {
        shinyjs::hide("hata_aciklama_msg")
      }

      if (hatalar) {
        showToast(session, "Lütfen zorunlu alanları doldurun: İşaretli alanları kontrol edin.", "error")
        return(invisible(NULL))
      }

      effective_user_id <- resolve_current_user_id()
      if (effective_user_id <= 0) {
        showToast(session, "Kimlik doğrulama tamamlanmadan hata bildirimi gönderilemez.", "warning")
        return(invisible(NULL))
      }

      dosyalar <- yuklenen_dosyalar()
      # Yalnızca ETKİN KULLANICININ kökü içindeki ve HÂLÂ VAR OLAN ek yolları
      # kaydedilir. Yükleme ile gönderim arasında silinen bir ek, var olmayan
      # yol olarak `ek_dosya_yollari` alanına yazılıyordu.
      gecerli_yollar <- Filter(
        function(yol) {
          isTRUE(destek_ek_yolu_guvenli(yol, effective_user_id)) &&
            isTRUE(file.exists(yol))
        },
        vapply(dosyalar, function(d) as.character(d$path %||% "")[1], character(1))
      )
      ek_yollari <- if (length(gecerli_yollar) > 0) {
        paste(gecerli_yollar, collapse = ",")
      } else {
        NULL
      }

      tryCatch({
        destek_hata_bildir_kaydet(
          user_id = effective_user_id,
          konular = konular_text,
          kategoriler = kategoriler,
          oncelik = if (!is.null(input$secili_oncelik) && nzchar(input$secili_oncelik)) input$secili_oncelik else "belirtilmedi",
          aciklama = aciklama,
          ek_dosya_yollari = ek_yollari
        )

        yuklenen_dosyalar(list())
        shinyjs::runjs(sprintf("destekResetBugForm('%s');", ns("")))
        basarili_trigger(basarili_trigger() + 1)

      }, error = function(e) {
        cat("[DESTEK] Hata bildirimi kaydedilemedi:", conditionMessage(e), "\n")
        showToast(session, "Hata bildirimi kaydedilemedi. Lütfen tekrar deneyin.", "error")
      })
    })

    return(list(
      basarili = reactive(basarili_trigger())
    ))
  })
}