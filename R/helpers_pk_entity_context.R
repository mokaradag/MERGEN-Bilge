# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_context.R
# Açıklama: DEVRALINAN VARLIK BAĞLAMI (D11) — kararlı bağlam anahtarı ve
#           oturum kapsamlı kalıcı kayıt.
#
#           `helpers_pk_entity_apply.R` bakım oranı bütçesine yakındır; bu
#           ayrı ve bütünlüklü sorumluluk oraya değil BURAYA aittir.
#           Saf/oturum-yerel: DB, LLM, ağ veya reaktif okuma YAPILMAZ.
# ==============================================================================
# Devralınan varlık bağlamı için KARARLI kimlik anahtarı.
#
# `entity_kind` sütun metadata'sından okunur; yoksa sütun rolü kullanılır.
# Anahtar YALNIZCA bu üçlüden üretilir ki iki farklı sorgu aynı sütun adını
# taşıdığında bağlam sınırı korunsun.
.pk_entity_context_key <- function(query, column, cmeta = NULL) {
  meta_kok <- if (is.list(query) && is.list(query$meta)) query$meta else query
  sorgu_id <- as.character(
    (if (is.list(query)) query$id %||% query$query_id else NULL) %||%
      (if (is.list(meta_kok)) meta_kok$query_id else NULL) %||% ""
  )[1]
  if (is.na(sorgu_id)) sorgu_id <- ""

  tur <- as.character(
    (if (is.list(cmeta)) (cmeta$entity_kinds %||% cmeta$entity_kind %||% cmeta$role) else NULL) %||% ""
  )[1]
  if (is.na(tur)) tur <- ""

  list(query_id = sorgu_id, column = as.character(column)[1], entity_kind = tur)
}

# ==============================================================================
# DEVRALINAN VARLIK BAĞLAMI (D11) — OTURUM KAPSAMLI KALICI KAYIT
#
# `pk_entity_resolve_with_history()` bir önceki turda ÇÖZÜLMÜŞ varlığı
# devralabilir, ancak bunun için kalıcı bir bağlam kaydına ihtiyacı vardır.
# Bu kayıt daha önce HİÇ üretilmiyordu: `prior_entity_context` alanını dolduran
# bir üretici yoktu, bu yüzden "peki 2024 için?" gibi bir devam sorusu önceki
# projeyi devralamıyordu ve geçmiş farkındalıklı çözümleyici pratikte ölü koddu.
#
# Kayıt sohbet geçmişi gibi serbest metin DEĞİL, YALNIZCA çözümleyicinin
# `auto` kararıyla ürettiği KANONİK değerlerdir; bu yüzden yeni bir güven
# sınırı açmaz.
# ==============================================================================

.PK_ENTITY_CONTEXT_SLOT <- "pk_entity_prior_context"

#' Oturumda saklanan önceki varlık bağlamını oku.
pk_entity_context_recall <- function(session) {
  if (is.null(session)) return(NULL)
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(NULL)
  kayit <- tryCatch(ud[[.PK_ENTITY_CONTEXT_SLOT]], error = function(e) NULL)
  if (!is.list(kayit) || !length(kayit$values)) return(NULL)
  kayit
}

#' Çözümleme kararlarından devralınabilir bağlamı sakla.
#'
#' Yalnızca ÖZNE (`subject`) rolündeki ve `auto` kararıyla çözülmüş bir yaprak
#' saklanır: ikincil daraltmaların devralınması, kullanıcının sormadığı bir
#' kısıtı sessizce sonraki soruya taşırdı.
pk_entity_context_remember <- function(session, decisions, query = NULL) {
  if (is.null(session)) return(invisible(FALSE))
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(FALSE))

  kararlar <- if (is.list(decisions)) decisions else list()
  for (karar in rev(kararlar)) {
    if (!is.list(karar) || !identical(karar$decision, "auto")) next
    if (!length(karar$values)) next
    if (!identical(as.character(karar$entity_role %||% "subject")[1], "subject")) next

    sutun <- as.character(karar$column %||% "")[1]
    if (is.na(sutun) || !nzchar(sutun)) next

    tryCatch({
      ud[[.PK_ENTITY_CONTEXT_SLOT]] <- list(
        values = as.character(karar$values),
        key = .pk_entity_context_key(query, sutun, karar$column_meta)
      )
    }, error = function(e) NULL)
    return(invisible(TRUE))
  }

  invisible(FALSE)
}

#' Filtre talimatlarını sohbet geçmişi ve önceki varlık bağlamıyla zenginleştir
#'
#' `extract_filter_criteria_from_prompt()` bu iki alanı ÜRETMEZ; üretim yolu
#' bu yüzden çözümleyiciye her zaman `NULL` veriyordu. Zenginleştirme burada,
#' tek bir yerde yapılır ki senkron ve derin analiz yolları AYNI bağlamı görsün.
pk_filter_instructions_with_context <- function(filter_instructions, chat_history = NULL,
                                                session = NULL) {
  talimatlar <- if (is.list(filter_instructions)) filter_instructions else list()
  talimatlar$chat_history <- chat_history
  talimatlar$prior_entity_context <- pk_entity_context_recall(session)
  talimatlar
}
