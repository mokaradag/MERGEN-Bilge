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
          h3("Yardım Merkezi"),
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
              href = paste0(
                "mailto:destek@mergen.ai",
                "?subject=", utils::URLencode("MERGEN Bilge - Destek Talebi"),
                "&body=", utils::URLencode(paste0(
                  "Merhaba MERGEN Bilge Destek Ekibi,\n\n",
                  "Aşağıdaki konu hakkında desteğinize ihtiyacım bulunmaktadır:\n\n",
                  "Konu: \n",
                  "Açıklama: \n\n",
                  "İyi çalışmalar dilerim,\n\n",
                  "Uygulama: MERGEN Bilge v0.9\n",
                  "Tarih: ", format(Sys.Date(), "%d.%m.%Y")
                ))
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
          div(class = "destek-chatbot-status",
            span(class = "destek-chatbot-status-dot"),
            "Çevrimiçi"
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

    # Bilgi tabanını yükle (ai_rehber.md)
    bilgi_tabani <- tryCatch({
      rehber_yolu <- file.path("ai_rehber.md")
      if (file.exists(rehber_yolu)) {
        readLines(rehber_yolu, encoding = "UTF-8", warn = FALSE) |> paste(collapse = "\n")
      } else {
        "Bilgi tabanı yüklenemedi."
      }
    }, error = function(e) {
      "Bilgi tabanı yüklenemedi."
    })

    # Sohbet geçmişi (LLM bağlamı için)
    sohbet_gecmisi <- reactiveVal(list())

    # Chatbot mesajı gönderildiğinde
    observeEvent(input$chatbot_mesaj, {
      kullanici_mesaji <- trimws(input$chatbot_mesaj)
      if (is.null(kullanici_mesaji) || !nzchar(kullanici_mesaji)) return()

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

        # API anahtarı (.Renviron'dan)
        api_key <- Sys.getenv("LOCAL_LLM_API_KEY", unset = "")

        # Sistem mesajı
        sistem_mesaji <- paste0(
          "Sen MERGEN Bilge uygulamasının Yardım Asistanısın. ",
          "Görevin YALNIZCA aşağıdaki bilgi tabanındaki içeriğe dayanarak kullanıcının sorularını yanıtlamaktır. ",
          "Bilgi tabanı dışında bir konuda soru sorulursa, kibar bir şekilde bu konuda bilginin olmadığını belirt ",
          "ve kullanıcıyı E-posta Destek (destek@mergen.ai) veya Telefon Destek (+90 850 123 45 67) kanallarına yönlendir.\n\n",
          "KURALLAR:\n",
          "- Sadece bilgi tabanındaki içeriğe dayanarak yanıt ver.\n",
          "- Uydurma veya tahmine dayalı bilgi verme.\n",
          "- Yanıtlarını Türkçe ver.\n",
          "- Kısa ve öz yanıtlar ver, gereksiz uzatma.\n",
          "- Markdown biçimlendirme kullanma, düz metin olarak yanıt ver.\n",
          "- Emoji kullanma.\n\n",
          "BİLGİ TABANI:\n",
          bilgi_tabani
        )

        # Mesaj listesini oluştur
        mesajlar <- list(
          list(role = "system", content = sistem_mesaji)
        )

        # Son 10 mesajı ekle (bağlam penceresi)
        son_mesajlar <- tail(gecmis, 10)
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
          max_tokens = 800
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
              bot_yaniti <- trimws(choice$message$content)
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
          cat(sprintf("[DESTEK CHATBOT] API HTTP hatası: %d\n", httr::status_code(response)))
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

    invisible(NULL)
  })
}