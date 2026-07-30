# Dosya Yolu: R/module_destek_yardim.R
# Açıklama: Yardım Merkezi alt sayfası modülü.
#            E-posta ve telefon destek bilgilerini gösterir.
#            Yapay zeka destekli sohbet asistanı içerir (bilgi kaynağı: ai_rehber.md).

# ==============================================================================
# YARDIM MERKEZİ UI
# ==============================================================================

destekYardimUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "destek-yardim-container",

      # Başlık ve giriş (ikon başlığın yanında, kompakt)
      div(
        class = "destek-yardim-header-compact",
        div(class = "destek-section-icon destek-icon-pulse",
          icon("circle-question")
        ),
        div(class = "destek-yardim-header-text",
          h3("Bize Ulaşın"),
          p(class = "destek-section-desc",
            "Size nasıl yardımcı olabiliriz? İletişim kanallarımızdan bize ulaşabilirsiniz."
          )
        )
      ),

      # İletişim kartları (yatay, geniş, kompakt)
      div(
        class = "destek-contact-grid destek-contact-grid-wide",
        # E-posta kartı
        div(
          class = "destek-contact-card destek-contact-card-wide",
          div(class = "destek-contact-icon destek-icon-float",
            icon("envelope")
          ),
          div(class = "destek-contact-card-body",
            h4(class = "destek-email-title", "E-posta Destek"),
            p(class = "destek-contact-desc",
              "Her türlü sorunuz, öneriniz veya şikayetiniz için bize e-posta gönderebilirsiniz."
            ),
			tags$a(
			  href = mergen_mailto_href(
				to = "destek@mergen.ai",
				subject = "MERGEN Bilge - Destek Talebi",
				body = paste0(
				  "Merhaba MERGEN Bilge Destek Ekibi,\n\n",
				  "Aşağıdaki konu hakkında desteğinize ihtiyacım bulunmaktadır:\n\n",
				  "Konu: \n",
				  "Açıklama: \n\n",
				  "İyi çalışmalar dilerim,\n\n",
				  "Uygulama: ", get_app_version_full_label(), "\n",
				  "Tarih: ", format(Sys.Date(), "%d.%m.%Y")
				)
			  ),
			  class = "destek-contact-link",
			  icon("arrow-right"),
			  "destek@mergen.ai"
			)
          )
        ),
        # Telefon kartı
        div(
          class = "destek-contact-card destek-contact-card-wide",
          div(class = "destek-contact-icon destek-icon-rotate",
            icon("phone")
          ),
          div(class = "destek-contact-card-body",
            h4(class = "destek-phone-title", "Telefon Destek"),
            p(class = "destek-contact-desc",
              "Destek gerektiren konular için aşağıdaki numarayı arayabilirsiniz."
            ),
            tags$a(
              href = "tel:+908501234567",
              class = "destek-contact-link",
              icon("arrow-right"),
              "+90 850 123 45 67"
            )
          )
        )
      ),

      # Yapay Zeka Sohbet Asistanı
      div(
        class = "destek-chatbot-container",
        # Chatbot başlığı
        div(
          class = "destek-chatbot-header",
          div(class = "destek-chatbot-header-icon",
            icon("robot")
          ),
          div(class = "destek-chatbot-header-text",
            span(class = "destek-chatbot-title", "Yardım Asistanı"),
            span(class = "destek-chatbot-subtitle", "MERGEN Bilge hakkında sorularınızı yanıtlar")
          ),
          div(class = "destek-chatbot-header-actions",
            div(class = "destek-chatbot-status",
              span(class = "destek-chatbot-status-dot"),
              "Çevrimiçi"
            ),
            tags$button(
              class = "destek-chatbot-clear-btn",
              type = "button",
              title = "Sohbeti temizle",
              onclick = sprintf("destekChatbotTemizle('%s')", ns("")),
              icon("trash-can")
            )
          )
        ),
        # Sohbet mesajları alanı
        div(
          id = ns("chatbot_messages"),
          class = "destek-chatbot-messages",
          # Başlangıç mesajı
          div(
            class = "destek-chatbot-message destek-chatbot-message-bot",
            div(class = "destek-chatbot-avatar",
              icon("robot")
            ),
            div(class = "destek-chatbot-bubble",
              "Merhaba! Ben MERGEN Bilge Yardım Asistanı. Uygulama hakkında sorularınızı yanıtlayabilirim. Nasıl yardımcı olabilirim?"
            )
          )
        ),
        # Düşünme animasyonu (gizli)
        div(
          id = ns("chatbot_thinking"),
          class = "destek-chatbot-thinking",
          style = "display: none;",
          div(class = "destek-chatbot-avatar",
            icon("robot")
          ),
          div(class = "destek-chatbot-thinking-dots",
            span(class = "destek-thinking-dot"),
            span(class = "destek-thinking-dot"),
            span(class = "destek-thinking-dot")
          )
        ),
        # Mesaj giriş alanı
        div(
          class = "destek-chatbot-input-area",
          tags$input(
            type = "text",
            id = ns("chatbot_input"),
            class = "destek-chatbot-input",
            placeholder = "Sorunuzu yazın...",
            maxlength = "500",
            autocomplete = "off",
            onkeydown = sprintf(
              "if(event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); destekChatbotGonder('%s'); }",
              ns("")
            )
          ),
          tags$button(
            id = ns("chatbot_send_btn"),
            class = "destek-chatbot-send-btn",
            type = "button",
            onclick = sprintf("destekChatbotGonder('%s')", ns("")),
            icon("paper-plane")
          )
        )
      )
    )
  )
}

# ==============================================================================
# YARDIM MERKEZİ SERVER
# ==============================================================================

destekYardimServer <- function(id, current_user_id = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Metni güvenli UTF-8'e dönüştür
    destek_guvenli_utf8 <- function(x) {
      if (is.null(x) || length(x) == 0) return("")
      if (!is.character(x)) x <- as.character(x)
      x <- paste(x, collapse = "\n")
      x <- sub("^\ufeff", "", x, perl = TRUE)
      x <- suppressWarnings(iconv(x, from = "", to = "UTF-8", sub = ""))
      if (is.na(x)) return("")
      enc2utf8(x)
    }

    # UTF-8 bayt sayısı, token sayısı için güvenli üst sınır olarak kullanılır.
    destek_bayt_sayisi <- function(x) {
      if (is.null(x) || length(x) == 0L) return(0L)
      x <- as.character(x)
      x[is.na(x)] <- ""
      sum(nchar(x, type = "bytes"))
    }

    # Metni UTF-8 karakterlerini bölmeden verilen bayt sınırına indir.
    destek_bayta_kirp <- function(x, en_fazla_bayt) {
      x <- destek_guvenli_utf8(x)
      en_fazla_bayt <- suppressWarnings(as.integer(en_fazla_bayt))
      if (!nzchar(x) || is.na(en_fazla_bayt) || en_fazla_bayt <= 0L) return("")
      if (destek_bayt_sayisi(x) <= en_fazla_bayt) return(x)

      alt <- 0L
      ust <- nchar(x, type = "chars")
      while (alt < ust) {
        orta <- as.integer(ceiling((alt + ust) / 2))
        if (destek_bayt_sayisi(substr(x, 1L, orta)) <= en_fazla_bayt) {
          alt <- orta
        } else {
          ust <- orta - 1L
        }
      }
      substr(x, 1L, alt)
    }

    # İlk geçerli pozitif ortam değişkenini oku.
    destek_env_tamsayi <- function(adlar, varsayilan) {
      for (ad in adlar) {
        deger <- trimws(Sys.getenv(ad, unset = ""))
        sayi <- suppressWarnings(as.integer(deger))
        if (nzchar(deger) && !is.na(sayi) && sayi > 0L) return(sayi)
      }
      as.integer(varsayilan)
    }

    # Basit yerel bölüm seçimi için arama sözcüklerini hazırla.
    destek_arama_sozcukleri <- function(x) {
      x <- enc2utf8(tolower(destek_guvenli_utf8(x)))
      x <- gsub("[^[:alnum:]çğıöşü]+", " ", x, perl = TRUE)
      kelimeler <- unlist(strsplit(x, "\\s+", perl = TRUE), use.names = FALSE)
      kelimeler <- kelimeler[nchar(kelimeler) >= 3L]
      kelimeler <- setdiff(kelimeler, c(
        "acaba", "ama", "bir", "bunu", "burada", "icin", "için", "ile",
        "mi", "mı", "mu", "mü", "nasıl", "nedir", "olan", "olarak", "ve"
      ))
      unique(kelimeler)
    }

    # Rehberi ikinci ve üçüncü düzey Markdown başlıklarından bölümlere ayır.
    destek_rehber_bolumleri <- function(rehber) {
      satirlar <- strsplit(rehber, "\n", fixed = TRUE)[[1]]
      baslangiclar <- grep("^#{2,3}\\s+", satirlar, perl = TRUE)
      if (length(baslangiclar) == 0L) return(list(rehber))
      if (baslangiclar[[1]] > 1L) baslangiclar <- c(1L, baslangiclar)
      bitisler <- c(baslangiclar[-1L] - 1L, length(satirlar))
      Map(function(a, b) paste(satirlar[a:b], collapse = "\n"), baslangiclar, bitisler)
    }

    # Rehber bütçeye sığmıyorsa tamamını tarayıp soruyla en ilgili bölümleri seç.
    destek_rehber_sec <- function(rehber, soru, bayt_butcesi) {
      rehber <- destek_guvenli_utf8(rehber)
      bayt_butcesi <- suppressWarnings(as.integer(bayt_butcesi))
      if (!nzchar(rehber) || is.na(bayt_butcesi) || bayt_butcesi <= 0L) return("")
      if (destek_bayt_sayisi(rehber) <= bayt_butcesi) return(rehber)

      bolumler <- destek_rehber_bolumleri(rehber)
      bolum_metinleri <- vapply(bolumler, identity, character(1))
      sorgu_kelimeleri <- destek_arama_sozcukleri(soru)
      puanlar <- vapply(seq_along(bolumler), function(i) {
        bolum <- bolumler[[i]]
        baslik <- strsplit(bolum, "\n", fixed = TRUE)[[1]][1]
        ortak <- intersect(sorgu_kelimeleri, destek_arama_sozcukleri(bolum))
        baslik_ortak <- intersect(sorgu_kelimeleri, destek_arama_sozcukleri(baslik))
        4 * length(baslik_ortak) + length(ortak)
      }, numeric(1))

      temel_bolumler <- unique(c(
        1L,
        grep("^## 1\\. MERGEN Bilge Nedir\\?", bolum_metinleri, perl = TRUE),
        grep("^### 2\\.2 Yardım Asistanı İçin", bolum_metinleri, perl = TRUE)
      ))
      siralama <- unique(c(order(puanlar, decreasing = TRUE), temel_bolumler, seq_along(bolumler)))
      secilenler <- integer()
      kalan <- bayt_butcesi
      ayirici_bayt <- destek_bayt_sayisi("\n\n---\n\n")

      for (i in siralama) {
        bolum <- bolumler[[i]]
        gereken <- destek_bayt_sayisi(bolum) + if (length(secilenler)) ayirici_bayt else 0L
        if (gereken <= kalan) {
          secilenler <- c(secilenler, i)
          kalan <- kalan - gereken
        }
        if (kalan < 512L) break
      }

      if (length(secilenler) == 0L) {
        return(destek_bayta_kirp(bolumler[[siralama[[1]]]], bayt_butcesi))
      }
      paste(bolumler[sort(unique(secilenler))], collapse = "\n\n---\n\n")
    }

    # Mesajların UTF-8 bayt toplamına JSON/rol yükü için küçük bir pay ekle.
    destek_mesaj_baytlari <- function(mesajlar) {
      if (!is.list(mesajlar) || length(mesajlar) == 0L) return(0L)
      sum(vapply(mesajlar, function(m) {
        destek_bayt_sayisi(m$role %||% "") +
          destek_bayt_sayisi(m$content %||% "") + 64L
      }, integer(1)))
    }

    # En yeni mesajları toplam bütçeyi aşmadan ve sıralarını koruyarak seç.
    destek_gecmis_sec <- function(gecmis, bayt_butcesi) {
      bayt_butcesi <- suppressWarnings(as.integer(bayt_butcesi))
      if (!is.list(gecmis) || length(gecmis) == 0L ||
          is.na(bayt_butcesi) || bayt_butcesi <= 0L) return(list())

      secilenler <- list()
      kalan <- bayt_butcesi
      for (i in rev(seq_along(gecmis))) {
        m <- gecmis[[i]]
        gereken <- destek_mesaj_baytlari(list(m))
        if (gereken <= kalan || length(secilenler) == 0L) {
          if (gereken > kalan) {
            rol_bayti <- destek_bayt_sayisi(m$role %||% "") + 64L
            m$content <- destek_bayta_kirp(m$content %||% "", max(0L, kalan - rol_bayti))
            gereken <- destek_mesaj_baytlari(list(m))
          }
          secilenler <- c(list(m), secilenler)
          kalan <- max(0L, kalan - gereken)
        }
        if (kalan < 128L) break
      }
      secilenler
    }

    # Bilgi tabanını farklı kodlamaları deneyerek oku
    destek_dosya_oku <- function(dosya_yolu) {
      if (!file.exists(dosya_yolu)) {
        return("Bilgi tabanı yüklenemedi.")
      }

      dosya_boyutu <- file.info(dosya_yolu)$size
      if (is.na(dosya_boyutu) || dosya_boyutu <= 0) {
        return("")
      }

      ham_icerik <- readBin(dosya_yolu, what = "raw", n = dosya_boyutu)
      aday_kodlamalar <- c("UTF-8", "WINDOWS-1254", "latin1")

      for (kodlama in aday_kodlamalar) {
        metin <- tryCatch(
          iconv(list(ham_icerik), from = kodlama, to = "UTF-8", sub = "")[[1]],
          error = function(e) NA_character_
        )

        if (!is.na(metin) && nzchar(metin)) {
          metin <- sub("^\ufeff", "", metin, perl = TRUE)
          return(enc2utf8(metin))
        }
      }

      "Bilgi tabanı yüklenemedi."
    }

    # Bilgi tabanını yükle (ai_rehber.md)
    bilgi_tabani <- tryCatch({
      destek_dosya_oku(file.path("ai_rehber.md"))
    }, error = function(e) {
      "Bilgi tabanı yüklenemedi."
    })

    # Sohbet geçmişi (LLM bağlamı için)
    sohbet_gecmisi <- reactiveVal(list())

    # Chatbot mesajı gönderildiğinde
    observeEvent(input$chatbot_mesaj, {
      kullanici_mesaji <- trimws(destek_guvenli_utf8(input$chatbot_mesaj %||% ""))
      if (!nzchar(kullanici_mesaji)) return()

      # Kullanıcı mesajını ekrana ekle (JS ile)
      shinyjs::runjs(sprintf(
        "destekChatbotMesajEkle('%s', %s, 'user');",
        ns(""),
        jsonlite::toJSON(kullanici_mesaji, auto_unbox = TRUE)
      ))

      # Düşünme animasyonunu göster
      shinyjs::runjs(sprintf(
        "destekChatbotDusunmeGoster('%s');",
        ns("")
      ))

      # Sohbet geçmişini güncelle
      gecmis <- sohbet_gecmisi()
      gecmis[[length(gecmis) + 1]] <- list(role = "user", content = kullanici_mesaji)

      # LLM'e gönder (helpers_ai_expert.R ile aynı desen)
      tryCatch({
        # Destek chatbot modeli
        chatbot_model <- Sys.getenv("DESTEK_CHATBOT_MODEL", unset = "")
        if (!nzchar(chatbot_model)) {
          chatbot_model <- Sys.getenv("AI_EXPERT_MODEL", unset = "")
        }
        if (!nzchar(chatbot_model)) {
          chatbot_model <- Sys.getenv("FILTER_MODEL", unset = "")
        }

        # API uç noktası
        api_endpoint <- Sys.getenv("LOCAL_LLM_ENDPOINT", unset = "")
        if (!nzchar(api_endpoint)) {
          stop("LLM endpoint tanımlı değil.")
        }

        # API anahtarı - önce kullanıcının kişisel anahtarını dene (Ana Söyleşi ile aynı desen)
        # API gateway rate limiter kullanıcı anahtarına göre tanımlama yapar
        user_api_key <- NULL
        if (!is.null(session$userData$ai_api_key)) {
          user_api_key <- as.character(session$userData$ai_api_key)[1]
        }
        env_api_key <- Sys.getenv("LOCAL_LLM_API_KEY", unset = "")
        api_key <- if (!is.null(user_api_key) && nzchar(user_api_key)) user_api_key else env_api_key

        bilgi_icerigi <- destek_guvenli_utf8(bilgi_tabani)
        max_yanit_token <- 4096L
        context_token_limiti <- destek_env_tamsayi(
          c(
            "DESTEK_CHATBOT_CONTEXT_TOKENS",
            "AI_EXPERT_CONTEXT_TOKENS",
            "LOCAL_LLM_CONTEXT_TOKENS"
          ),
          varsayilan = 32768L
        )
        context_token_limiti <- max(context_token_limiti, max_yanit_token + 8192L)
        girdi_butcesi <- context_token_limiti - max_yanit_token - 1024L

        # Sistem mesajı (kısa talimatlar - bilgi tabanı ayrı mesajda)
        sistem_mesaji <- paste0(
          "Sen MERGEN Bilge uygulamasinin Yardim Asistanisin. ",
          "Gorevin YALNIZCA bu soru icin rehberin tamami taranarak secilen bilgi tabani icerigini kullanarak kullanicinin sorularini yanitlamaktir. ",
          "Bilgi tabani disinda bir konuda soru sorulursa, kibar bir sekilde bu konuda bilginin olmadigini belirt ",
          "ve kullaniciyi E-posta Destek (REHIS Proje Yönetimi Birimi) veya Telefon Destek (81875) kanallarina yonlendir.\n\n",
          "KURALLAR:\n",
          "- Sadece bilgi tabanindaki icerigi kullanarak yanit ver.\n",
          "- Uydurma veya tahmine dayali bilgi verme.\n",
          "- Yanitlarini Turkce ver.\n",
          "- Soruyu dogrudan ve yeterli ayrintiyla yanitla; gerekiyorsa adimlari sirala.\n",
          "- Gerektiginde Markdown bicimlendirme kullanabilirsin (kalin, italik, liste, kod blogu).\n",
          "- Emoji kullanma."
        )
        bilgi_on_eki <- paste0(
          "MERGEN Bilge kullanici rehberinin tamami bu soru icin tarandi. ",
          "Asagida baglam butcesine sigan rehberin tamami veya soruyla en ilgili bolumleri yer aliyor. ",
          "Yalnizca bu icerikte acikca bulunan bilgilere dayan:\n\n"
        )
        hazirlik_mesaji <- "Anladim, bilgi tabanini inceledim. MERGEN Bilge hakkindaki sorularinizi yanitlamaya hazirim."

        # Geçmiş ve rehber aynı toplam bağlam bütçesini paylaşır.
        sabit_mesajlar <- list(
          list(role = "system", content = sistem_mesaji),
          list(role = "assistant", content = hazirlik_mesaji)
        )
        asgari_rehber_butcesi <- min(8192L, max(2048L, as.integer(girdi_butcesi * 0.35)))
        gecmis_butcesi <- min(
          12000L,
          max(1024L, girdi_butcesi - destek_mesaj_baytlari(sabit_mesajlar) -
                destek_bayt_sayisi(bilgi_on_eki) - 64L - asgari_rehber_butcesi)
        )
        son_mesajlar <- destek_gecmis_sec(tail(gecmis, 10), gecmis_butcesi)
        sabit_bayt <- destek_mesaj_baytlari(c(sabit_mesajlar, son_mesajlar)) +
          destek_bayt_sayisi(bilgi_on_eki) + 64L
        rehber_butcesi <- max(1024L, girdi_butcesi - sabit_bayt)
        secili_bilgi <- destek_rehber_sec(bilgi_icerigi, kullanici_mesaji, rehber_butcesi)

        # Mesaj listesini oluştur - bilgi tabanı ayrı user mesajı olarak
        mesajlar <- list(
          list(role = "system", content = sistem_mesaji),
          list(role = "user", content = paste0(bilgi_on_eki, secili_bilgi)),
          list(role = "assistant", content = hazirlik_mesaji)
        )
        for (m in son_mesajlar) {
          mesajlar[[length(mesajlar) + 1]] <- m
        }

        # Başlıklar (helpers_ai_expert.R ile aynı desen)
        hds <- list(`Content-Type` = "application/json")
        if (nzchar(api_key)) hds$Authorization <- paste("Bearer", api_key)

        # İstek gövdesi
        body <- list(
          model = chatbot_model,
          messages = mesajlar,
          stream = FALSE,
          temperature = 0.3,
          max_tokens = max_yanit_token
        )

        # API çağrısı (httr encode = "json" kullan - kanıtlanmış yöntem)
        response <- httr::POST(
          url = api_endpoint,
          body = body,
          encode = "json",
          do.call(httr::add_headers, hds),
          httr::timeout(60)
        )

        if (httr::status_code(response) < 400) {
          parsed <- httr::content(response, "parsed")

          bot_yaniti <- NULL
          if (is.list(parsed$choices) && length(parsed$choices) > 0) {
            choice <- parsed$choices[[1]]
            if (!is.null(choice$message) && !is.null(choice$message$content)) {
              bot_yaniti <- trimws(destek_guvenli_utf8(choice$message$content))
            }
          }

          if (!is.null(bot_yaniti) && nzchar(bot_yaniti)) {
            # Geçmişe ekle
            gecmis[[length(gecmis) + 1]] <- list(role = "assistant", content = bot_yaniti)
            sohbet_gecmisi(gecmis)

            # Düşünme animasyonunu gizle ve yanıtı göster
            shinyjs::runjs(sprintf(
              "destekChatbotDusunmeGizle('%s');", ns("")
            ))
            shinyjs::runjs(sprintf(
              "destekChatbotMesajEkle('%s', %s, 'bot');",
              ns(""),
              jsonlite::toJSON(bot_yaniti, auto_unbox = TRUE)
            ))
          } else {
            sohbet_gecmisi(gecmis)
            shinyjs::runjs(sprintf("destekChatbotDusunmeGizle('%s');", ns("")))
            shinyjs::runjs(sprintf(
              "destekChatbotMesajEkle('%s', %s, 'bot');",
              ns(""),
              jsonlite::toJSON("Üzgünüm, yanıt oluşturulamadı. Lütfen daha sonra tekrar deneyin.", auto_unbox = TRUE)
            ))
          }
        } else {
          # Hata detayını logla (teşhis için)
          hata_detay <- tryCatch(
            httr::content(response, "text", encoding = "UTF-8"),
            error = function(e2) "yanit govdesi okunamadi"
          )
          cat(sprintf("[DESTEK CHATBOT] API HTTP hatasi: %d - %s\n",
                      httr::status_code(response), substr(hata_detay, 1, 500)))
          sohbet_gecmisi(gecmis)
          shinyjs::runjs(sprintf("destekChatbotDusunmeGizle('%s');", ns("")))
          shinyjs::runjs(sprintf(
            "destekChatbotMesajEkle('%s', %s, 'bot');",
            ns(""),
            jsonlite::toJSON("Üzgünüm, şu anda yanıt veremiyorum. Lütfen daha sonra tekrar deneyin veya E-posta Destek (destek@mergen.ai) kanalından bize ulaşın.", auto_unbox = TRUE)
          ))
        }

      }, error = function(e) {
        cat("[DESTEK CHATBOT] Hata:", conditionMessage(e), "\n")
        sohbet_gecmisi(gecmis)
        shinyjs::runjs(sprintf("destekChatbotDusunmeGizle('%s');", ns("")))
        shinyjs::runjs(sprintf(
          "destekChatbotMesajEkle('%s', %s, 'bot');",
          ns(""),
          jsonlite::toJSON("Üzgünüm, şu anda yanıt veremiyorum. Lütfen E-posta Destek (destek@mergen.ai) veya Telefon Destek (+90 850 123 45 67) kanallarından bize ulaşın.", auto_unbox = TRUE)
        ))
      })
    }, ignoreInit = TRUE)

    # Sohbet temizleme
    observeEvent(input$chatbot_temizle, {
      sohbet_gecmisi(list())
    }, ignoreInit = TRUE)

    invisible(NULL)
  })
}
