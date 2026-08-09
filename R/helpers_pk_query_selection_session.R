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

.pk_select_state_write <- function(session, state) {
  if (is.null(session)) return(invisible(FALSE))
  if (length(state) > .PK_SELECT_STATE_MAX_CHATS) {
    state <- utils::tail(state, .PK_SELECT_STATE_MAX_CHATS)
  }

  tryCatch({
    session$userData[[.PK_SELECT_STATE_SLOT]] <- state
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}

# Geçmiş imzası/kimliği kendi sorumluluk dosyasında tutulur; bu dosya oturum
# durumunu okuma/yazma ve seçim/teklif yaşam döngüsüne odaklı kalır.
.pk_select_history_path <- file.path("R", "helpers_pk_query_selection_history.R")
if (!file.exists(.pk_select_history_path)) {
  stop(sprintf("%s bulunamadı; sorgu seçimi oturum durumu yüklenemiyor.", .pk_select_history_path),
       call. = FALSE)
}
source(.pk_select_history_path, encoding = "UTF-8", local = globalenv())
rm(.pk_select_history_path)

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
  .pk_select_state_write(session, durum)
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
pk_select_remember_offer <- function(session, chips, chat_key = "__yeni__") {
  if (is.null(session) || !length(chips)) return(invisible(FALSE))

  secenekler <- lapply(chips, function(cip) {
    list(
      id = as.character(cip$id)[1],
      name = as.character(cip$name %||% cip$id)[1]
    )
  })

  durum <- .pk_select_state_read(session)
  kayit <- if (is.list(durum[[chat_key]])) durum[[chat_key]] else list()
  kayit$offer <- secenekler
  durum[[chat_key]] <- kayit
  .pk_select_state_write(session, durum)
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
  durum[[chat_key]] <- kayit
  .pk_select_state_write(session, durum)
}
