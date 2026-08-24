# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_seed.R
# Açıklama: Faz 5 (§5.2) — Geçiş A aday bütçesi ve önceki sorgu tohumu.
# ==============================================================================

#' Geçiş A adaylarını önceki kararlı sorguyla tohumla
#'
#' `recall_n`, Geçiş A'nın taze recall bütçesidir. Önceki kararlı sorgu bu
#' bütçenin dışında konuşma-bağlamı tohumu olarak korunur: taze recall kümesi
#' eksilmez, ancak eksiltili bir takip de tek konuşma-derived adayını kaybetmez.
#' @param library_ids YÜKLÜ kütüphanenin kimlik kümesi. Verildiğinde tohum bu
#'   kümeye karşı DOĞRULANIR; verilmezse eski davranış korunur.
pk_select_seed_candidates <- function(recalled_ids, prior_query_id, cfg,
                                      library_ids = NULL) {
  aday <- as.character(recalled_ids)
  aday <- unique(aday[!is.na(aday) & nzchar(aday)])

  sinir <- suppressWarnings(as.integer(cfg$recall_n)[1])
  if (!length(sinir) || is.na(sinir) || sinir < 1L) return(character(0))

  aday <- utils::head(aday, sinir)
  if (is.null(prior_query_id) || !length(prior_query_id) || is.na(prior_query_id[1])) {
    return(aday)
  }

  onceki <- trimws(as.character(prior_query_id)[1])
  if (!nzchar(onceki) || onceki %in% aday) return(aday)

  # TOHUM DA KÜTÜPHANEDE OLMAK ZORUNDADIR.
  #
  # `recalled_ids` Geçiş A ayrıştırıcısında kütüphaneye karşı doğrulanır, ama
  # oturum durumundan gelen bu tohum doğrulanmıyordu. Kütüphane yeniden
  # üretildiğinde / bir sorgu emekliye ayrıldığında / kimlik kayıtlı bir
  # söyleşiden geri yüklendiğinde `library_index[[kimlik]]` NULL bir aday kaydı
  # üretiyor, Geçiş B ise kaydı OLMAYAN bir kimlikle çalışıyordu: seçilen
  # kimlik var olmayan bir sorguya işaret edebilirdi.
  if (!is.null(library_ids) && !(onceki %in% trimws(as.character(library_ids)))) {
    return(aday)
  }

  c(onceki, aday)
}
