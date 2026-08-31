# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_session.R
# Açıklama: Faz 5 (§5.2) — seçim hattının OTURUM DURUMU: önceki kararlı sorgu
#           kimliği ve kullanıcıya sunulan netleştirme seçenekleri.
#
# Durum söyleşi anahtarıyla izole edilir ve seçim, çağıran onu kabul edene kadar
# kalıcılaştırılmaz. Geçmiş-pencere kimliği ayrı history helper'ındadır.
# ==============================================================================

.PK_SELECT_STATE_SLOT <- "pk_select_state"
.PK_SELECT_STATE_MAX_CHATS <- 8L
.PK_SELECT_STATE_MAX_SIGNATURES <- 12L

.pk_select_state_read <- function(session) {
  if (is.null(session)) return(list())
  durum <- tryCatch(session$userData[[.PK_SELECT_STATE_SLOT]], error = function(e) NULL)
  if (!is.list(durum)) list() else durum
}

.pk_select_state_write <- function(session, state, touched = NULL) {
  if (is.null(session)) return(invisible(FALSE))

  # AYIKLAMA EKLEME SIRASINA GÖRE DEĞİL SON KULLANIMA GÖRE YAPILIR: hatırlama yardımcıları var olan adlı ögeyi YERİNDE günceller, öge ilk konumunu korur ve `.PK_SELECT_STATE_MAX_CHATS` aşıldığında `utils::tail()` AZ ÖNCE kullanılan söyleşiyi düşürebilirdi. Saklanan sorgu kimliği ve bekleyen teklif kaybolur, sonraki eksiltili takip sorusu bağlamını yitirirdi.
  if (length(touched) == 1L && !is.na(touched) &&
      as.character(touched) %in% names(state)) {
    anahtar <- as.character(touched)
    kayit <- state[[anahtar]]
    state[[anahtar]] <- NULL
    state[[anahtar]] <- kayit
  }

  if (length(state) > .PK_SELECT_STATE_MAX_CHATS) {
    state <- utils::tail(state, .PK_SELECT_STATE_MAX_CHATS)
  }

  tryCatch({
    session$userData[[.PK_SELECT_STATE_SLOT]] <- state
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

# Geçmiş imzası/kimliği kendi sorumluluk dosyasında tutulur ve manifestte bu
# dosyadan ÖNCE yüklenir; oturum helper'ı çalışma dizinine göre kaynak yüklemez.

#' Önceki kararlı sorgu kimliğini oku (eksiltili takip için)
pk_select_prior_query_id <- function(session = NULL, chat_key = "__yeni__") {
  durum <- .pk_select_state_read(session)
  kayit <- durum[[chat_key]]
  if (!is.list(kayit)) return(NULL)

  deger <- kayit$query_id
  if (is.null(deger) || !length(deger) || is.na(deger[1])) return(NULL)

  kimlik <- trimws(as.character(deger)[1])
  if (!nzchar(kimlik)) return(NULL)
  kimlik
}

#' Seçilen kararlı kimliği oturuma yaz (söyleşi kapsamlı)
pk_select_remember_query_id <- function(session, query_id, chat_key = "__yeni__") {
  if (is.null(session) || is.null(query_id) || !length(query_id) || is.na(query_id[1])) {
    return(invisible(FALSE))
  }

  kimlik <- trimws(as.character(query_id)[1])
  if (!nzchar(kimlik)) return(invisible(FALSE))

  durum <- .pk_select_state_read(session)
  kayit <- if (is.list(durum[[chat_key]])) durum[[chat_key]] else list()
  kayit$query_id <- kimlik
  durum[[chat_key]] <- kayit
  .pk_select_state_write(session, durum, touched = chat_key)
}

#' Önceki kararlı kimliği düşür
pk_select_forget_query_id <- function(session, chat_key = "__yeni__") {
  if (is.null(session)) return(invisible(FALSE))

  durum <- .pk_select_state_read(session)
  kayit <- durum[[chat_key]]
  if (!is.list(kayit)) return(invisible(FALSE))

  kayit$query_id <- NULL
  durum[[chat_key]] <- kayit
  .pk_select_state_write(session, durum)
}

#' Kullanıcıya sunulan netleştirme seçeneklerini hatırla
pk_select_remember_offer <- function(session, chips, chat_key = "__yeni__",
                                     requirements = NULL) {
  if (is.null(session)) return(invisible(FALSE))

  # SEÇENEKSİZ RED, ÖNCEKİ TEKLİFİ GEÇERSİZ KILAR.
  #
  # Eskiden `!length(chips)` durumunda erken dönülüyor ve ESKİ teklif oturumda
  # kalıyordu. Kullanıcının bir sonraki turda yazdığı sıradan bir "2" ya da
  # eski bir sorgu adı, ARTIK sunulmamış bir seçeneği onaylamış sayılabiliyordu.
  if (!length(chips)) return(pk_select_forget_offer(session, chat_key))

  secenekler <- lapply(chips, function(cip) {
    list(
      id = as.character(cip$id)[1],
      name = as.character(cip$name %||% cip$id)[1]
    )
  })

  durum <- .pk_select_state_read(session)
  kayit <- if (is.list(durum[[chat_key]])) durum[[chat_key]] else list()
  kayit$offer <- secenekler
  # GEREKSİNİMLER TEKLİFLE BİRLİKTE SAKLANIR: onaylanan aday, teklifi üreten
  # isteğin yetenek gereksinimlerine karşı YENİDEN doğrulanır (bkz.
  # `pk_select_confirmed_decision`).
  kayit$offer_requirements <- requirements
  durum[[chat_key]] <- kayit
  .pk_select_state_write(session, durum, touched = chat_key)
}

#' Teklifle birlikte saklanmış yetenek gereksinimlerini oku
pk_select_offer_requirements <- function(session, chat_key = "__yeni__") {
  durum <- .pk_select_state_read(session)
  kayit <- durum[[chat_key]]
  if (!is.list(kayit)) return(NULL)
  kayit$offer_requirements
}

#' Kullanıcının cevabını sunulan seçeneklerden birine deterministik olarak eşle
#'
#' Yalnızca tam eşleşme kabul edilir (kararlı kimlik, seçenek adı ya da liste
#' numarası). Bulanık eşleştirme yoktur.
pk_select_resolve_user_choice <- function(session, prompt, chat_key = "__yeni__") {
  durum <- .pk_select_state_read(session)
  kayit <- durum[[chat_key]]
  if (!is.list(kayit) || !length(kayit$offer)) return(NA_character_)

  istek <- trimws(as.character(prompt)[1] %||% "")
  if (is.na(istek) || !nzchar(istek)) return(NA_character_)

  katla <- function(x) {
    if (exists("pk_tr_fold", mode = "function", inherits = TRUE)) return(pk_tr_fold(x))
    tolower(trimws(x))
  }

  hedef <- katla(istek)
  secenekler <- kayit$offer
  eslesenler <- character(0)

  for (i in seq_along(secenekler)) {
    secenek <- secenekler[[i]]
    adaylar <- c(katla(secenek$id), katla(secenek$name), as.character(i))
    if (hedef %in% adaylar) eslesenler <- c(eslesenler, secenek$id)
  }

  eslesenler <- unique(eslesenler)
  if (length(eslesenler) != 1L) return(NA_character_)
  eslesenler
}

#' Sunulan seçenekleri unut (seçim tamamlandığında)
pk_select_forget_offer <- function(session, chat_key = "__yeni__") {
  if (is.null(session)) return(invisible(FALSE))

  durum <- .pk_select_state_read(session)
  kayit <- durum[[chat_key]]
  if (!is.list(kayit)) return(invisible(FALSE))

  kayit$offer <- NULL
  # GEREKSİNİMLER DE TEKLİFLE BİRLİKTE SİLİNİR.
  #
  # Eskiden yalnızca `offer` temizleniyordu; `pk_select_offer_requirements()`
  # GERİ ÇEKİLMİŞ teklifin gereksinimlerini döndürmeye devam ediyordu. Boş çip
  # durumu da buraya yönlendiği için REDDEDİLEN bir teklif yetenek
  # gereksinimlerini kurulu bırakıyor, yeni teklif saklanmadan önce
  # gereksinimleri okuyan bir onay yolu adayı BAYAT gereksinimlere göre
  # doğruluyordu.
  kayit$offer_requirements <- NULL
  durum[[chat_key]] <- kayit
  .pk_select_state_write(session, durum)
}
