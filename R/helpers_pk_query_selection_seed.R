# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_seed.R
# Açıklama: Faz 5 (§5.2) — Geçiş A aday bütçesi ve önceki sorgu tohumu.
# ==============================================================================

#' Geçiş A adaylarını önceki kararlı sorguyla, recall bütçesini aşmadan tohumla
#'
#' Taze recall adayları bütçenin sahibidir. Önceki sorgu yalnızca boş yer varsa
#' eklenir; böylece konu değişiminde geçerli bir taze aday bayat tohum yüzünden
#' geri alınamaz biçimde düşmez.
pk_select_seed_candidates <- function(recalled_ids, prior_query_id, cfg) {
  aday <- as.character(recalled_ids)
  aday <- unique(aday[!is.na(aday) & nzchar(aday)])

  sinir <- suppressWarnings(as.integer(cfg$recall_n)[1])
  if (!length(sinir) || is.na(sinir) || sinir < 1L) return(character(0))

  aday <- utils::head(aday, sinir)
  if (length(aday) >= sinir || is.null(prior_query_id) || !length(prior_query_id) ||
      is.na(prior_query_id[1])) {
    return(aday)
  }

  onceki <- trimws(as.character(prior_query_id)[1])
  if (!nzchar(onceki) || onceki %in% aday) return(aday)

  c(aday, onceki)
}
