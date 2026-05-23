# ==============================================================================
# Dosya Yolu: R/helpers_admin_hata_heatmap_data.R
# Açıklama: Yönetici hata analizi öncelik x kategori heatmap verisini hazırlar.
#           Shiny, highcharter, DB veya reactive durum içermez.
# ==============================================================================

admin_ha_prepare_heatmap_data <- function(data,
                                          kategori_cevirisi,
                                          oncelik_cevirisi) {
  empty_result <- list(
    kategoriler = character(0),
    oncelikler = character(0),
    heatmap_data = list()
  )

  if (is.null(data) || !is.data.frame(data) || nrow(data) == 0L) {
    return(empty_result)
  }

  required_columns <- c("Kategoriler", "Oncelik", "cnt")
  if (!all(required_columns %in% names(data))) {
    return(empty_result)
  }

  ilk_kategori <- vapply(
    strsplit(as.character(data$Kategoriler), ","),
    function(x) trimws(x[1]),
    character(1)
  )

  kategori_tr <- ifelse(
    ilk_kategori %in% names(kategori_cevirisi),
    unname(kategori_cevirisi[ilk_kategori]),
    ilk_kategori
  )

  oncelik_tr <- ifelse(
    data$Oncelik %in% names(oncelik_cevirisi),
    unname(oncelik_cevirisi[data$Oncelik]),
    data$Oncelik
  )

  prepared <- data.frame(
    kategori_tr = as.character(kategori_tr),
    oncelik_tr = as.character(oncelik_tr),
    cnt = data$cnt,
    stringsAsFactors = FALSE
  )

  prepared <- prepared[
    !is.na(prepared$kategori_tr) & nzchar(prepared$kategori_tr) &
      !is.na(prepared$oncelik_tr) & nzchar(prepared$oncelik_tr),
    ,
    drop = FALSE
  ]

  if (nrow(prepared) == 0L) {
    return(empty_result)
  }

  kategoriler <- unique(prepared$kategori_tr)
  oncelikler <- c("Düşük", "Orta", "Yüksek", "Kritik", "Belirtilmedi")
  oncelikler <- oncelikler[oncelikler %in% unique(prepared$oncelik_tr)]

  heatmap_data <- list()
  for (i in seq_along(kategoriler)) {
    for (j in seq_along(oncelikler)) {
      val <- sum(prepared$cnt[
        prepared$kategori_tr == kategoriler[i] &
          prepared$oncelik_tr == oncelikler[j]
      ])
      heatmap_data <- c(heatmap_data, list(list(i - 1, j - 1, val)))
    }
  }

  list(
    kategoriler = kategoriler,
    oncelikler = oncelikler,
    heatmap_data = heatmap_data
  )
}