# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_request_markers.R
# Açıklama: Faz 6 (§5.10) — OTURUM ÜZERİNDEKİ İSTEK İŞARETLERİ: açıkça terk
#           edilmiş istek kimlikleri ve iptal jetonu SAHİPLİĞİ.
#
# `R/helpers_pk_async_session_registry.R` içinden BÖLÜNMÜŞTÜR: orası AKTİF
# istek defteri ve oturum-sonu kancasıdır ve 24-fonksiyon bakım tavanına
# dayanmıştı. Bu iki işaret kümesi defterin YAŞAM DÖNGÜSÜNE değil, tek tek
# İSTEKLERİN durumuna aittir.
#
# Shiny `session$userData` üzerine yazar; REAKTİF okuma YAPMAZ.
# ==============================================================================

# Terk edilmiş istek kimlikleri (sonuçları ARTIK uygulanamaz).
mergen_pk_invalidate_requests <- function(session, request_ids) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(character(0)))

  kimlikler <- tryCatch(as.character(request_ids), error = function(e) character(0))
  kimlikler <- kimlikler[!is.na(kimlikler) & nzchar(kimlikler)]
  if (!length(kimlikler)) return(invisible(character(0)))

  mevcut <- tryCatch(ud[["pk_abandoned_requests"]], error = function(e) NULL)
  if (!is.character(mevcut)) mevcut <- character(0)
  # Pencere sınırlı tutulur: oturum ömrü boyunca sınırsız büyümemeli.
  yeni <- utils::tail(unique(c(mevcut, kimlikler)), 200L)
  try(ud[["pk_abandoned_requests"]] <- yeni, silent = TRUE)
  invisible(yeni)
}

#' Bu istek AÇIKÇA terk edildi mi?
mergen_pk_request_abandoned <- function(session, request_id) {
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(FALSE)
  terk <- tryCatch(session$userData[["pk_abandoned_requests"]], error = function(e) NULL)
  is.character(terk) && kimlik %in% terk
}

# ------------------------------------------------------------------------------
# JETON SAHİPLİĞİ KAYDI
# ------------------------------------------------------------------------------
# Durdur gözlemcisi HER istek için çalışır (sohbet, görsel, özetleme...).
# Yalnızca PK dağıtıcısının SAHİP OLDUĞU istekler için jeton yazılmalıdır;
# aksi hâlde hiçbir tamamlanma yolunun temizlemediği `.flag` dosyaları birikir.
mergen_pk_register_cancel_token <- function(session, request_id) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(FALSE))
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))

  mevcut <- tryCatch(ud[["pk_cancel_token_owners"]], error = function(e) NULL)
  if (!is.character(mevcut)) mevcut <- character(0)
  # Kayıt penceresi sınırlı tutulur: oturum ömrü boyunca sınırsız büyümemeli.
  mevcut <- utils::tail(unique(c(mevcut, kimlik)), 50L)
  # YAZIM SONUCU DENETLENİR: `userData` yazılamazsa Durdur gözlemcisi
  # `mergen_pk_request_has_cancel_token()` üzerinden sahipliği GÖREMEZ ve işçinin
  # dosya jetonunu HİÇ işaretlemez — yani Durdur sessizce çalışmaz hâle gelirdi.
  yazildi <- try({ ud[["pk_cancel_token_owners"]] <- mevcut; TRUE }, silent = TRUE)
  if (!identical(yazildi, TRUE)) return(invisible(FALSE))
  invisible(mergen_pk_request_has_cancel_token(session, kimlik))
}

#' Jeton sahipliğini KALDIR (isteğin her terminal yolunda)
#'
#' `bitir_istek()` bayrağı temizler ve aktif isteği siler, ama sahiplik kaydı
#' kalırsa nihai LLM sırasında basılan Durdur AYNI istek kimliğiyle YENİ bir
#' `.flag` dosyası üretir. O dosyayı temizleyecek bir PK yolu artık YOKTUR.
mergen_pk_unregister_cancel_token <- function(session, request_id) {
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(FALSE))
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(invisible(FALSE))

  mevcut <- tryCatch(ud[["pk_cancel_token_owners"]], error = function(e) NULL)
  if (!is.character(mevcut) || !length(mevcut)) return(invisible(FALSE))
  try(ud[["pk_cancel_token_owners"]] <- setdiff(mevcut, kimlik), silent = TRUE)
  invisible(TRUE)
}

mergen_pk_request_has_cancel_token <- function(session, request_id) {
  kimlik <- tryCatch(as.character(request_id)[1], error = function(e) NA_character_)
  if (is.na(kimlik) || !nzchar(kimlik)) return(FALSE)
  sahipler <- tryCatch(session$userData[["pk_cancel_token_owners"]], error = function(e) NULL)
  is.character(sahipler) && kimlik %in% sahipler
}
