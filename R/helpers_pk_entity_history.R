# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_history.R
# Açıklama: Faz 4 — D11: `chat_history` ile devam sorusu daraltması.
#
#           D11 (§3, S3): `pk_analiz_process_request()` ve `select_smart_query()`
#           `chat_history` parametresini ALIR ama gövdelerinde HİÇ OKUMAZ. Bu
#           yüzden "peki 2024 icin?" veya "sadece aktif olanlar" gibi eksiltili
#           devam soruları, bir onceki soruda cozulmus varligi kaybeder.
#
#           Bu dosya o boslugu SAF bir katman olarak doldurur: sohbet gecmisini
#           okur, eksiltili devam sorusunu tespit eder ve mevcut ifade
#           cozumlenemediginde onceki kullanici sorusundan varlik baglamini
#           DEVRALIR.
#
#           Devralma YALNIZCA cozumleme basarisiz oldugunda denenir ve sonuc
#           `inherited = TRUE` ile isaretlenir; boylece cagiran taraf bunu
#           kullaniciya acikca bildirebilir. Sessiz devralma YAPILMAZ.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Sohbet gecmisi bu depoda iki bicimde dolasir: LLM yolunda `role`/`content`,
# sohbet calisma zamaninda `type`/`content`. Ikisi de desteklenir.
.PK_ENTITY_USER_ROLES <- c("user", "human", "kullanici", "kullanıcı")

# Ilk belirtec olarak gorundugunde devam sorusu sinyali veren ifadeler.
.PK_ENTITY_FOLLOWUP_LEAD <- c(
  "peki", "ya", "sadece", "yalnızca", "yalnizca", "ayrıca", "ayrica",
  "onun", "onlar", "onları", "onlari", "ondan", "onda",
  "bunun", "bunları", "bunlari", "bundan", "bunda",
  "şunun", "sunun", "hem", "ve"
)

# Ifadenin herhangi bir yerinde gecmesi yeterli olan guclu sinyaller.
.PK_ENTITY_FOLLOWUP_ANY <- c(
  "peki", "sadece", "yalnızca", "yalnizca", "ayrıca", "ayrica",
  "aynısı", "aynisi", "aynısını", "aynisini"
)

# ÖLÇÜLMÜŞ GEREKÇE (tasarım kararı E4) — devralinan SORU sozcukleri atilir.
#
#   Devralinan sey bir varlik ifadesi degil, kullanicinin onceki TAM SORUSUDUR:
#   "elektronik harp sebekesi butcesi nedir". Soru sozcukleri belirtec kumesini
#   sisirir ve Jaccard'i her katmanin altina duşurur — olculdu: kanonik
#   "Sentetik Elektronik Harp Sebekesi" adayina karsi J = 0.50 < 0.60, yani
#   HICBIR eslesme uretilmez ve D11 ornegi ("peki 2024 icin?") calismaz.
#
#   Bu liste YALNIZCA devralinan onceki mesajlara uygulanir; kullanicinin
#   GUNCEL ifadesine ve kanonik adaylara DOKUNULMAZ. Alan adlari (butce, maliyet,
#   sure gibi) BILEREK listede DEGILDIR: onlar ayirt edici olabilir. Guncel
#   sorudan varlik ifadesi cikarma isi filtre planina (§5.3) aittir ve Faz 5'in
#   kapsamindadir.
.PK_ENTITY_QUESTION_WORDS <- c(
  "nedir", "ne", "kadar", "kaç", "kac", "kaçtır", "kactir",
  "hangi", "hangisi", "hangileri", "nasıl", "nasil", "neden", "niçin", "nicin",
  "nerede", "nereye", "kim", "kimdir",
  "mi", "mı", "mu", "mü", "midir", "mıdır", "mudur", "müdür",
  "göster", "goster", "listele", "ver", "söyle", "soyle", "açıkla", "acikla",
  "getir", "bul", "hesapla", "raporla", "özetle", "ozetle",
  "için", "icin", "ile", "ve", "veya", "ya", "da", "de",
  "bu", "şu", "su", "o", "bir", "en", "var", "yok",
  "olan", "olanlar", "oldu", "nedeni", "durumu", "bilgisi"
)

#' Devralinan onceki sorudan soru sozcuklerini at (yalnizca gecmis katmani)
#'
#' Sonuc bos kalirsa orijinal metin korunur: bos bir ifade GECERSIZ GIRDIDIR ve
#' cozumleyiciye bos dizgi gondermek anlamsiz bir hata uretir.
pk_entity_strip_question_words <- function(text) {
  normal <- pk_entity_normalize(text)
  if (isTRUE(normal$blank)) return(NA_character_)

  belirtecler <- pk_entity_tokens(normal$fold, stem = FALSE)
  kalan <- belirtecler[!(belirtecler %in% .PK_ENTITY_QUESTION_WORDS)]

  if (!length(kalan)) return(normal$fold)
  paste(kalan, collapse = " ")
}

.pk_entity_msg_field <- function(msg, fields) {
  if (!is.list(msg)) return(NA_character_)

  for (alan in fields) {
    deger <- msg[[alan]]
    if (is.null(deger) || !length(deger)) next
    metin <- as.character(deger)[1]
    if (!is.na(metin) && nzchar(trimws(metin))) return(metin)
  }

  NA_character_
}

.pk_entity_msg_is_user <- function(msg) {
  rol <- .pk_entity_msg_field(msg, c("role", "type", "sender"))
  if (is.na(rol)) return(FALSE)

  # Rol adlari saf ASCII/Turkce sabitlerdir; katlama yerelden bagimsiz olsun
  # diye `tolower()` yerine pk_tr_fold() kullanilir.
  katlanmis <- pk_tr_fold(rol)
  if (!length(katlanmis) || is.na(katlanmis)) return(FALSE)

  katlanmis %in% .PK_ENTITY_USER_ROLES
}

#' Sohbet gecmisindeki kullanici sorularini EN YENIDEN ESKIYE dogru dondur
#'
#' @param chat_history Mesaj listesi. Her mesaj `role`/`type` ve `content`
#'   alanlarini tasiyan bir liste olmalidir.
#' @param limit En fazla kac onceki soru dondurulsun.
pk_entity_prior_user_prompts <- function(chat_history, limit = 5L) {
  if (is.null(chat_history) || !is.list(chat_history) || !length(chat_history)) {
    return(character(0))
  }

  sinir <- suppressWarnings(as.integer(limit)[1])
  if (is.na(sinir) || sinir < 1L) sinir <- 1L

  toplanan <- character(0)
  for (i in rev(seq_along(chat_history))) {
    mesaj <- chat_history[[i]]
    if (!.pk_entity_msg_is_user(mesaj)) next

    metin <- .pk_entity_msg_field(mesaj, c("content", "text", "message", "icerik"))
    if (is.na(metin)) next

    toplanan <- c(toplanan, metin)
    if (length(toplanan) >= sinir) break
  }

  toplanan
}

#' Ifade eksiltili bir devam sorusu mu?
#'
#' Sezgiseldir ve BILEREK sinirlidir: sonucu yalnizca cozumleme ZATEN
#' basarisiz oldugunda kullanilir, bu yuzden yanlis pozitifin maliyeti
#' "onceki soruyu da dene" adimidir, sessiz bir varsayim degil.
pk_entity_is_followup <- function(phrase) {
  normal <- pk_entity_normalize(phrase)
  if (isTRUE(normal$blank)) return(FALSE)

  belirtecler <- pk_entity_tokens(normal$fold, stem = FALSE)
  if (!length(belirtecler)) return(FALSE)

  if (belirtecler[1] %in% .PK_ENTITY_FOLLOWUP_LEAD) return(TRUE)
  if (any(belirtecler %in% .PK_ENTITY_FOLLOWUP_ANY)) return(TRUE)

  # "bir de ..." kalibi tek belirtecle yakalanamaz.
  if (length(belirtecler) >= 2L &&
      identical(belirtecler[1], "bir") && identical(belirtecler[2], "de")) {
    return(TRUE)
  }

  FALSE
}

#' Devam sorusu plani (saf)
#'
#' @return `is_followup`, `prior_prompts` (en yeniden eskiye) ve
#'   `inherited_phrase` (devralinacak ifade; yoksa `NA`).
pk_entity_followup_plan <- function(chat_history, phrase, limit = 5L) {
  oncekiler <- pk_entity_prior_user_prompts(chat_history, limit = limit)

  list(
    is_followup = pk_entity_is_followup(phrase),
    prior_prompts = oncekiler,
    inherited_phrase = if (length(oncekiler)) oncekiler[1] else NA_character_
  )
}

#' Gecmis farkindalikli varlik cozumleme (D11)
#'
#' Once mevcut ifade cozulur. Cozulemezse VE ifade eksiltili bir devam sorusu
#' ise, onceki kullanici sorulari sirayla denenir. Basarili devralma
#' `inherited = TRUE` ve `inherited_from` ile ISARETLENIR.
#'
#' Devralma yalnizca kesin bir sonuc uretirse kabul edilir; devralinan ifade de
#' cozumlenemezse ORIJINAL karar korunur, boylece hata mesaji kullanicinin
#' gercekten yazdigi ifadeye ait kalir.
pk_entity_resolve_with_history <- function(phrase, candidates, chat_history = NULL,
                                           aliases = NULL, role = NULL,
                                           match_mode = NULL,
                                           entity_role = "subject",
                                           query_meta = NULL, thresholds = NULL,
                                           limit = 5L) {
  ilk <- pk_entity_resolve(
    phrase = phrase, candidates = candidates, aliases = aliases,
    role = role, match_mode = match_mode, entity_role = entity_role,
    query_meta = query_meta, thresholds = thresholds
  )

  # Yapilandirma hatasi ve gecersiz girdi devralmayla DUZELMEZ.
  if (!(ilk$decision %in% c("unresolved", "unfiltered"))) return(ilk)

  plan <- pk_entity_followup_plan(chat_history, phrase, limit = limit)
  if (!isTRUE(plan$is_followup) || !length(plan$prior_prompts)) return(ilk)

  for (onceki in plan$prior_prompts) {
    # Once ham metin (onceki mesaj SADECE varlik adiysa bu yeterlidir), sonra
    # soru sozcukleri atilmis biçim denenir (tasarim karari E4).
    denemeler <- unique(c(onceki, pk_entity_strip_question_words(onceki)))
    denemeler <- denemeler[!is.na(denemeler) & nzchar(denemeler)]

    for (aday_ifade in denemeler) {
      devralinan <- pk_entity_resolve(
        phrase = aday_ifade, candidates = candidates, aliases = aliases,
        role = role, match_mode = match_mode, entity_role = entity_role,
        query_meta = query_meta, thresholds = thresholds
      )

      if (devralinan$decision %in% c("auto", "confirm", "clarify")) {
        devralinan$inherited <- TRUE
        devralinan$inherited_from <- onceki
        devralinan$original_phrase <- as.character(phrase)[1]
        return(devralinan)
      }
    }
  }

  ilk
}
