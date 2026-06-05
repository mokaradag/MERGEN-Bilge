# ==============================================================================
# Dosya Yolu: R/helpers_llm_worker_tool_results_preview.R
# Açıklama:   helpers_llm_worker_tool_results.R için MCP araç sonuçlarından
#             sonuç_önizleme / sonuc_onizleme / preview DataFrame'ini çıkaran
#             küçük, saf yardımcı fonksiyon.
#             Shiny reactive state'e dokunmaz; ham araç payload'ını değiştirmez.
# ==============================================================================

llm_worker_extract_preview_df <- function(raw) {
  if (!is.list(raw)) {
    return(NULL)
  }

  raw_names <- names(raw)
  candidate_names <- c("sonuç_önizleme", "sonuc_onizleme", "preview")

  if (!is.null(raw_names)) {
    raw_names_utf8 <- enc2utf8(raw_names)
    candidate_names_utf8 <- enc2utf8(candidate_names)

    matched_idx <- match(candidate_names_utf8, raw_names_utf8)
    matched_idx <- matched_idx[!is.na(matched_idx)]

    if (length(matched_idx)) {
      return(raw[[matched_idx[[1]]]])
    }
  }

  dataframe_idx <- which(vapply(raw, is.data.frame, logical(1)))

  if (length(dataframe_idx) == 1L) {
    return(raw[[dataframe_idx[[1]]]])
  }

  NULL
}