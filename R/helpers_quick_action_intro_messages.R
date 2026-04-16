# ==============================================================================
# Dosya Yolu: R/helpers_quick_action_intro_messages.R
# Açıklama: Hızlı işlem butonları için LLM çağrısı yapmadan gösterilecek
#           hazır yönlendirme mesajlarını üretir.
# ==============================================================================

resolve_quick_action_user_name <- function(session = NULL, settings_data = NULL) {
  adaylar <- list(
    tryCatch(session$userData$user_config$first_name, error = function(e) NULL),
    tryCatch(settings_data$user_config$first_name, error = function(e) NULL),
    tryCatch(user_config$first_name, error = function(e) NULL),
    tryCatch(session$userData$user_config$name, error = function(e) NULL),
    tryCatch(settings_data$user_config$name, error = function(e) NULL),
    tryCatch(user_config$name, error = function(e) NULL)
  )

  adaylar <- Filter(
    function(x) !is.null(x) && nzchar(trimws(as.character(x)[1])),
    adaylar
  )

  if (!length(adaylar)) {
    return("")
  }

  secilen_ad <- trimws(as.character(adaylar[[1]])[1])

  if (grepl("\\s", secilen_ad)) {
    secilen_ad <- strsplit(secilen_ad, "\\s+")[[1]][1]
  }

  secilen_ad
}

build_quick_action_intro_message <- function(action_id, user_name = NULL, config = api_config) {
  action_id <- as.character(action_id %||% "")[1]
  user_name <- trimws(as.character(user_name %||% "")[1])

  action_cfg <- get_tool_mode_config(action_id, by = "quick_action_id", config = config)
  action_title <- action_cfg$title %||% "Hızlı İşlem"

  selamlama <- if (nzchar(user_name)) {
    paste0("Merhaba **", user_name, "** \U0001F44B")
  } else {
    "Merhaba \U0001F44B"
  }

  varyant_sec <- function(metinler) {
    if (!length(metinler)) {
      return("")
    }
    metinler[[sample.int(length(metinler), size = 1)]]
  }

  metinler <- NULL

  if (identical(action_id, "project-process")) {
    metinler <- list(
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** modu hazır \U0001F9ED\n\n",
        "Bu alanda kurum içi **süreç**, **izleç**, **rehber** ve **şablon** dokümanlarıyla ilgili sorular sorabilirsiniz.\n\n",
        "- Sürecin adını yazın\n",
        "- İlgili form ya da şablonu belirtin\n",
        "- Gerekirse adım adım uygulamayı isteyin"
      ),
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** etkinleştirildi \U0001F4CC\n\n",
        "Hazırsanız belirli bir kurumsal süreci, rehberi veya standart dokümanı sorabilirsiniz. ",
        "Ben de sizi doğrudan ilgili içerik ekseninde yönlendireceğim."
      )
    )
  } else if (identical(action_id, "app-expert")) {
    metinler <- list(
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** modu hazır \U0001F6E0\n\n",
        "Burada **Primavera P6**, **SAP**, **Jira** ve benzeri kurumsal uygulamalar hakkında destek alabilirsiniz.\n\n",
        "- Hangi uygulamayı kullandığınızı yazın\n",
        "- Ne yapmak istediğinizi belirtin\n",
        "- Hata, ekran veya işlem adımını eklerseniz daha net yönlendirme alırsınız"
      ),
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** açıldı \U0001F4BB\n\n",
        "Uygulama kullanımı, ekran akışı, temel kavramlar veya operasyonel adımlar hakkında soru sorabilirsiniz. ",
        "Özellikle hangi modül ya da işlemde olduğunuzu belirtmeniz yeterli."
      )
    )
  } else if (identical(action_id, "resource-analysis")) {
    metinler <- list(
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** modu hazır \U0001F4CA\n\n",
        "Bu alanda **Primavera P6** ve **SAP** tarafındaki proje, kaynak, bütçe ve takvim verileri üzerinden analiz yapabilirsiniz.\n\n",
        "- Hangi metriği görmek istediğinizi yazın\n",
        "- Proje, tarih veya kaynak filtresi ekleyin\n",
        "- Sonucu özet, tablo ya da karşılaştırma olarak isteyin"
      ),
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** etkinleştirildi \U0001F4C8\n\n",
        "Artık proje ve kaynak verileri üzerinden sorgu odaklı analiz isteyebilirsiniz. ",
        "Örneğin kapasite, bütçe, iş yükü, takvim sapması veya dağılım karşılaştırmaları sorabilirsiniz."
      )
    )
  } else if (identical(action_id, "excel-analysis")) {
    metinler <- list(
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** modu hazır \U0001F4D7\n\n",
        "Excel dosyalarınızı analiz etmek için artık doğru araç seçildi.\n\n",
        "- Dosyanın hangi sayfasına bakılacağını yazın\n",
        "- İlgili sütun, filtre veya hesaplamayı belirtin\n",
        "- İsterseniz özet, karşılaştırma veya anomali analizi isteyin"
      ),
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** açıldı \U0001F522\n\n",
        "Hazırsanız Excel içeriği üzerinde belirli bir soru sorabilirsiniz. ",
        "Özellikle sayfa adı, sütun adı ve beklediğiniz çıktı biçimini belirtmeniz sonucu hızlandırır."
      )
    )
  } else if (identical(action_id, "image-creation")) {
    metinler <- list(
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** modu hazır \U0001F3A8\n\n",
        "Burada üretilecek görsel için sahneyi, stili ve kompozisyonu tarif edebilirsiniz.\n\n",
        "- Konu ve ortamı yazın\n",
        "- Stil, ışık, açı ve arka plan ekleyin\n",
        "- Gerekirse negatif istem de belirtin"
      ),
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** etkinleştirildi \U0001F5BC\n\n",
        "Artık doğrudan görsel isteminizi yazabilirsiniz. ",
        "Ne kadar net tanım verirseniz sonuç o kadar kontrollü olur."
      )
    )
  } else if (identical(action_id, "coding-support")) {
    metinler <- list(
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** modu hazır \U0001F4BB\n\n",
        "Kod, hata ayıklama, refaktör, performans ve mimari konularında destek alabilirsiniz.\n\n",
        "- İlgili kod parçasını paylaşın\n",
        "- Hata mesajını ekleyin\n",
        "- Beklediğiniz davranışı kısaca yazın"
      ),
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** açıldı \U0001F9E0\n\n",
        "Hazırsanız dosya, fonksiyon, hata veya geliştirmek istediğiniz bölümü gönderin. ",
        "Ben de doğrudan teknik çözüm odaklı ilerleyeyim."
      )
    )
  } else if (identical(action_id, "summarization")) {
    metinler <- list(
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** modu hazır \U0001F4D1\n\n",
        "Belge özetleme için doğru mod seçildi. Bu akışta **PDF**, **DOC**, **DOCX** ve **TXT** gibi belgeler üzerinden çalışabilirsiniz.\n\n",
        "- Dosyayı Dosya Yönetimi'nden yükleyin\n",
        "- Gerekliyse **Model Bağlamı** olarak seçin\n",
        "- Sonra nasıl bir özet istediğinizi yazın"
      ),
      paste0(
        selamlama, "\n\n",
        "**", action_title, "** etkinleştirildi \U0001F4DA\n\n",
        "Artık belgeler için kısa özet, detaylı özet, yönetici özeti veya madde madde çıkarım isteyebilirsiniz. ",
        "Gerçek özetleme, siz talebinizi yazdığınızda başlayacak."
      )
    )
  }

  if (is.null(metinler) || !length(metinler)) {
    return(paste0(selamlama, "\n\n**", action_title, "** modu hazır. Sorunuzu yazabilirsiniz."))
  }

  varyant_sec(metinler)
}