# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_session.R
# Açıklama: Faz 5 (§5.2) — seçim hattının OTURUM DURUMU: önceki kararlı sorgu
#           kimliği ve kullanıcıya SUNULAN netleştirme seçenekleri.
#
# SOHBET KAPSAMI ZORUNLUDUR: durum eskiden tek bir `session$userData` yuvasında
# tutuluyordu ve yeni söyleşi/kayıtlı söyleşi geçişlerinde TEMİZLENMİYORDU. Bir
# söyleşide seçilmiş sorgu, tamamen ilgisiz bir söyleşideki eksiltili
# ("peki 2024 için?") soruyu tohumlayabiliyor, hatta aday kümesinden taze bir
# adayı düşürebiliyordu. Durum bu yüzden SÖYLEŞİ ANAHTARIYLA saklanır.
#
# YAZMA ZAMANI DA SÖZLEŞMENİN PARÇASIDIR: seçim, çağıran onu KABUL EDENE kadar
# kalıcılaştırılmaz. `auto` seçilip hemen iptal edilen bir istek eskiden yine de
# "önceki sorgu" olarak yazılıyor ve sonraki takip sorusu kullanıcının durdurduğu
# analizle tohumlanıyordu.
#
# Dosya SAF DEĞİLDİR (oturum okur/yazar) ama Shiny'ye BAĞIMLI değildir: yalnızca
# `session$userData` benzeri bir liste/ortam bekler; testlerde sahte oturumla
# çalışır.
# ==============================================================================

.PK_SELECT_STATE_SLOT <- "pk_select_state"

# Oturumda tutulan söyleşi sayısı. Sınırsız büyüme, uzun ömürlü bir Shiny
# oturumunda sessiz bellek birikimi olurdu.
.PK_SELECT_STATE_MAX_CHATS <- 8L

#' Söyleşi anahtarı — durum bu anahtarla İZOLE edilir
#'
#' Anahtar konuşmanın İLK mesajından türetilir: söyleşi boyunca kararlıdır,
#' yeni söyleşide (boş geçmiş) ve kayıtlı başka bir söyleşi yüklendiğinde
#' FARKLIDIR. DB kimliğine bağımlı değildir; worker/test bağlamında da çalışır.
pk_select_chat_key <- function(chat_history) {
  if (!is.list(chat_history) || !length(chat_history)) return("__yeni__")

  ilk <- chat_history[[1]]
  if (!is.list(ilk)) return("__yeni__")

  icerik <- as.character(ilk$content %||% "")[1]
  if (is.na(icerik) || !nzchar(trimws(icerik))) return("__yeni__")

  substr(trimws(icerik), 1L, 200L)
}

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

#' Önceki kararlı sorgu kimliğini oku (eksiltili takip için)
#'
#' Oturum yoksa (worker/test bağlamı) sessizce `NULL` döner.
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

#' Önceki kararlı kimliği DÜŞÜR
#'
#' Seçim tamamlanmayan (netleştirme/zaman aşımı/reddetme) her istek, o
#' söyleşideki "son başarılı seçim" iddiasını GEÇERSİZ kılar: konu değişmiş
#' olabilir ve bir sonraki eksiltili soru artık eski analize ait değildir.
pk_select_forget_query_id <- function(session, chat_key = "__yeni__") {
  if (is.null(session)) return(invisible(FALSE))

  durum <- .pk_select_state_read(session)
  kayit <- durum[[chat_key]]
  if (!is.list(kayit)) return(invisible(FALSE))

  kayit$query_id <- NULL
  durum[[chat_key]] <- kayit
  .pk_select_state_write(session, durum)
}

#' Kullanıcıya SUNULAN netleştirme seçeneklerini hatırla
#'
#' Bozulma kipinde kullanıcıya "hangisini istersiniz?" denip, cevabı yeniden
#' aynı (erişilemeyen) seçiciye götürmek kapalı bir döngüdür. Sunulan
#' seçenekler saklanır ki bir sonraki mesaj DETERMİNİSTİK olarak çözülebilsin.
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

#' Kullanıcının cevabını SUNULAN seçeneklerden birine deterministik olarak eşle
#'
#' Yalnızca TAM eşleşme kabul edilir (kararlı kimlik, seçenek adı ya da liste
#' numarası). Bulanık eşleştirme YOKTUR: bu yol seçim kararını LLM olmadan
#' verdiği için, belirsiz bir eşleşme sessizce yanlış analizi çalıştırırdı.
#'
#' @return Kararlı kimlik ya da `NA_character_`.
pk_select_resolve_user_choice <- function(session, prompt, chat_key = "__yeni__") {
  durum <- .pk_select_state_read(session)
  kayit <- durum[[chat_key]]
  if (!is.list(kayit) || !length(kayit$offer)) return(NA_character_)

  istek <- trimws(as.character(prompt)[1] %||% "")
  if (is.na(istek) || !nzchar(istek)) return(NA_character_)

  katla <- function(x) {
    if (exists("pk_tr_fold", mode = "function", inherits = TRUE)) {
      return(pk_tr_fold(x))
    }
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
