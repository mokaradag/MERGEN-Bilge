# R/helpers_ai_expert_handlers_support.R
# AI Uzman (AI Expert) sunucu işleyicileri için saf karar yardımcıları.
#
# Bu dosya yalnızca SAF karar/biçim mantığını içerir: sayfa adı çevirisi,
# sıklık -> gecikme/aralık eşlemesi ve boşta konuşma kullanıcı bağlamı metni.
# Shiny/reactive erişimi, DB/ağ çağrısı, dosya yazımı veya değişken durum YOKTUR.
# Böylece izole testlerde (Shiny/DB başlatmadan) doğrudan source edilip
# çağrılabilir ve R/server_ai_expert_handlers.R orkestrasyona odaklı kalır.

#' AI Uzman sayfa kimliğini Türkçe sayfa adına çevir
#'
#' Sayfa rehberliği ve boşta konuşma akışları için tek kaynak sayfa adı
#' eşlemesidir. Bilinen sekmeler için Türkçe etiketi, "chat" için
#' "Ana Söyleşi" değerini, bilinmeyen/boş sayfa için NULL döndürür.
#'
#' @param page Sekme kimliği (örn. "history", "claude_code", "chat").
#' @return Türkçe sayfa adı (karakter) veya bilinmeyen/boş için NULL.
ai_expert_page_name_tr <- function(page) {
  page <- as.character(page)
  if (length(page) != 1L || is.na(page) || !nzchar(page)) {
    return(NULL)
  }

  switch(
    page,
    "chat"                  = "Ana Söyleşi",
    "history"               = "Söyleşi Geçmişi",
    "saved_chats"           = "Kayıtlı Söyleşiler",
    "image_gallery"         = "Görsel Galerisi",
    "claude_code"           = "Bilge Yolaç",
    "files"                 = "Dosya Yönetimi",
    "settings_yapilandirma" = "Yapılandırma",
    "destek_yardim"         = "Yardım Merkezi",
    "destek_geri_bildirim"  = "Geri Bildirim ve Hata Bildirimi",
    "destek_surum"          = "Yenilikler",
    "destek_hakkinda"       = "Hakkında",
    NULL
  )
}

#' Frekans ayarını güvenli bir tekil sıklık değerine indir
#'
#' @param frequency Ham sıklık değeri (NULL/NA/boş olabilir).
#' @return Tekil karakter sıklık değeri; geçersizse "orta".
.ai_expert_normalize_frequency <- function(frequency) {
  if (length(frequency) == 1L && !is.na(frequency) && nzchar(frequency)) {
    return(as.character(frequency))
  }
  "orta"
}

#' İlk boşta konuşma gecikmesini (ms) sıklık ayarına bağla
#'
#' @param frequency Sıklık ayarı ("az" / "orta" / "sik").
#' @return Milisaniye cinsinden ilk boşta konuşma gecikmesi.
ai_expert_first_idle_delay_ms <- function(frequency = "orta") {
  switch(
    .ai_expert_normalize_frequency(frequency),
    "az" = 30000,
    "orta" = 20000,
    "sik" = 12000,
    20000
  )
}

#' Boşta konuşma tekrar aralığını (ms) sıklık ayarına bağla
#'
#' @param frequency Sıklık ayarı ("az" / "orta" / "sik").
#' @return Milisaniye cinsinden boşta konuşma tekrar aralığı.
ai_expert_idle_interval_ms <- function(frequency = "orta") {
  switch(
    .ai_expert_normalize_frequency(frequency),
    "az"  = 60000,  # 60 saniye
    "orta" = 35000, # 35 saniye
    "sik" = 20000,  # 20 saniye
    35000
  )
}

#' Boşta konuşma için kullanıcı bağlamı metnini oluştur
#'
#' Saf metin birleştirme yardımcısıdır; LLM'e gönderilecek boşta konuşma
#' kullanıcı bağlamını parça parça kurar. Sys.time() doğrudan kullanılmaz;
#' güncel zaman metni `now_text` ile dışarıdan verilir (deterministik test).
#'
#' @param page_name_tr Türkçe sayfa adı.
#' @param user_work_context Kullanıcı çalışma bağlamı listesi veya NULL
#'   (effective_unit / department / mudurluk alanları).
#' @param idle_count Bu oturumdaki boşta konuşma sırası (tam sayı).
#' @param session_msgs Bu oturumdaki kullanıcı mesajları (karakter vektörü) veya NULL.
#' @param recent_prompts Veritabanından son konuşma konuları veya NULL.
#' @param now_text Güncel zaman metni (örn. "%d %B %Y %H:%M" biçiminde).
#' @return Birleştirilmiş kullanıcı bağlamı metni (tek karakter).
build_ai_expert_idle_user_context <- function(page_name_tr,
                                              user_work_context = NULL,
                                              idle_count = 1L,
                                              session_msgs = NULL,
                                              recent_prompts = NULL,
                                              now_text = "") {
  context_parts <- list()
  context_parts <- c(context_parts, sprintf(
    "Kullanıcı şu anda '%s' sayfasında ve bir süredir etkileşimde bulunmadı.",
    page_name_tr
  ))

  if (is.list(user_work_context)) {
    effective_unit <- safe_trimws(user_work_context$effective_unit %||% "")
    department <- safe_trimws(user_work_context$department %||% "")
    mudurluk <- safe_trimws(user_work_context$mudurluk %||% "")

    if (safe_nzchar(department) && safe_nzchar(mudurluk)) {
      context_parts <- c(context_parts, sprintf(
        "Kullanıcının departmanı: %s. Bağlı olduğu müdürlük/direktörlük: %s. Bu bilgiyi yalnızca bağlam kurmak için kullan; kullanıcının güncel işi veya görevi hakkında varsayım üretme.",
        department, mudurluk
      ))
    } else if (safe_nzchar(effective_unit)) {
      context_parts <- c(context_parts, sprintf(
        "Kullanıcının çalıştığı birim: %s. Bu bilgiyi yalnızca bağlam kurmak için kullan; kullanıcının güncel işi veya görevi hakkında varsayım üretme.",
        effective_unit
      ))
    }
  }

  context_parts <- c(context_parts, sprintf(
    "Bu oturumda %d. boşta konuşman. ÖNEMLİ: Selam verme, merhaba deme, hoş geldin deme. Bu zaten devam eden bir sohbet. Önceki konuşmalarını tekrarlama, her seferinde farklı bir konuya değin ve farklı bir giriş cümlesi kullan. Yaratıcı ol, sürpriz yap.",
    idle_count
  ))

  if (!is.null(session_msgs) && length(session_msgs) > 0) {
    session_text <- paste(sprintf("- \"%s\"", substr(session_msgs, 1, 200)), collapse = "\n")
    context_parts <- c(context_parts, sprintf(
      "Bu oturumdaki kullanıcı mesajları (EN GÜNCEL - bu konulara öncelik ver):\n%s",
      session_text
    ))
  }

  if (!is.null(recent_prompts) && length(recent_prompts) > 0) {
    prompts_text <- paste(sprintf("- \"%s\"", substr(recent_prompts, 1, 120)), collapse = "\n")
    context_parts <- c(context_parts, sprintf("Veritabanından son konuşma konuları:\n%s", prompts_text))
  }

  context_parts <- c(context_parts, sprintf("Şimdi: %s", now_text))
  paste(context_parts, collapse = "\n\n")
}
