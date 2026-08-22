# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_tree.R
# Aciklama: Filtre agacinda MANTIK GRUBU GEZINTISI (saf yol yardimcilari).
#
#           `filters` duz bir yaprak listesi olabilecegi gibi
#           `{operator, children}` dugumleri de icerebilir. Bu yardimcilar
#           yapraklarin KONUMUNU (indeks yolu) uretir, o konumdaki dugumu okur
#           ve yerinde gunceller; agac YAPISI degismez.
#
#           Dosya bilerek SAFTIR: Shiny/reaktif/DB/ag/LLM bagimliligi YOKTUR.
#           Yukleme sirasi: `R/helpers_pk_entity_apply.R` dosyasindan ONCE.
# ==============================================================================

# --- MANTIK GRUBU GEZİNTİSİ (saf yol yardımcıları) ----------------------------
#
# `filters` ya düz yaprak listesi ya da `{operator, children}` düğümleri
# içerebilir. Bu üç yardımcı, yaprakların KONUMUNU (indeks yolu) üretir, o
# konumdaki düğümü okur ve yerinde günceller; ağaç YAPISI değişmez.
.pk_entity_is_group_node <- function(x) {
  is.list(x) && !is.null(x$children) && is.list(x$children)
}

.pk_entity_leaf_paths <- function(node, prefix = integer(0), depth = 0L) {
  if (depth > 8L) return(list())
  out <- list()
  for (i in seq_along(node)) {
    cocuk <- node[[i]]
    if (!is.list(cocuk)) next
    if (.pk_entity_is_group_node(cocuk)) {
      out <- c(out, .pk_entity_leaf_paths(cocuk$children, c(prefix, i, NA_integer_),
                                          depth + 1L))
      next
    }
    out[[length(out) + 1L]] <- c(prefix, i)
  }
  out
}

# `NA_integer_` yol adımı "children" alanı demektir (adlandırılmış erişim).
.pk_entity_pluck <- function(x, path) {
  dugum <- x
  for (adim in path) {
    if (is.na(adim)) {
      dugum <- dugum$children
    } else {
      dugum <- dugum[[adim]]
    }
    if (is.null(dugum)) return(NULL)
  }
  dugum
}

# Yol TAMAMEN tam sayı vektörüdür (`NA` = `children` alanı); `value` alanı
# atomik bir yola KARIŞTIRILMAZ, aksi hâlde `c(yol, "value")` tüm adımları
# metne çevirir ve adsız liste indekslemesi bozulur.
.pk_entity_set_leaf_value <- function(x, path, value) {
  if (!length(path)) {
    x$value <- value
    return(x)
  }
  adim <- path[[1]]
  kalan <- path[-1]
  if (is.na(adim)) {
    x$children <- .pk_entity_set_leaf_value(x$children, kalan, value)
  } else {
    x[[adim]] <- .pk_entity_set_leaf_value(x[[adim]], kalan, value)
  }
  x
}
