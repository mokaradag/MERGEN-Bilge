# ==============================================================================
# Dosya Yolu: R/helpers_pk_filter_group.R
# Açıklama: AÇIK mantık gruplarının (AND/OR) INERT değerlendiricisi.
#
#           Bu dosya, model üretimi `filter_expression` metnini R kodu olarak
#           çalıştıran `eval(parse())` yolunun YERİNE geçer. İç içe VEYA/VE
#           gereksinimi burada VERİ olarak temsil edilir:
#
#             list(operator = "or", children = list(<yaprak>, <yaprak|grup>))
#
#           Hiçbir aşamada `parse()`/`eval()` yoktur; yalnızca
#           `PK_FILTER_KNOWN_OPS` içindeki işlemler ve `and`/`or`
#           birleştiricileri yorumlanır. Yaprak maskeleri
#           `pk_filter_leaf_mask()` üzerinden üretilir.
#
#           `R/helpers_pk_filter_compile.R` içinden BÖLÜNMÜŞTÜR: derleyici
#           25-fonksiyon bakım tavanına dayanmıştı ve grup değerlendirmesi
#           ayrı bir sorumluluktur.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

# --- AÇIK MANTIK GRUBU DEĞERLENDİRİCİSİ ---------------------------------------
#
# Bu, `eval(parse())` yolunun YERİNE geçen inert değerlendiricidir. Yalnızca
# `PK_FILTER_KNOWN_OPS` içindeki işlemler ve `and`/`or` birleştiricileri
# yorumlanır; hiçbir R ifadesi ayrıştırılmaz veya çalıştırılmaz.
.pk_filter_is_group_node <- function(x) {
  is.list(x) && !is.null(x$children) && is.list(x$children)
}

.pk_filter_group_operator <- function(x) {
  belirtec <- .pk_filter_ascii_lower(trimws(as.character(x$operator %||% x$logic %||% "and")[1]))
  if (is.na(belirtec)) belirtec <- "and"
  if (belirtec %in% PK_FILTER_OR_TOKENS) "or" else "and"
}

.pk_filter_eval_group <- function(data, node, query = NULL, depth = 0L) {
  n <- nrow(data)
  bos <- list(mask = NULL, applied = list(), dropped = list())

  # Derinlik sınırı: kötü biçimli/özyinelemeli bir yapı derleyiciyi kilitlemez.
  if (depth > 8L) {
    return(list(mask = NULL, applied = list(), dropped = list(list(
      leaf = list(column = "__group__", values = character(0)),
      reason = "filtre grubu izin verilen derinligi asti"
    ))))
  }

  islec <- .pk_filter_group_operator(node)
  cocuklar <- node$children
  if (!length(cocuklar)) return(bos)

  maskeler <- list()
  uygulanan <- list()
  dusen <- list()

  for (cocuk in cocuklar) {
    if (.pk_filter_is_group_node(cocuk)) {
      alt <- .pk_filter_eval_group(data, cocuk, query = query, depth = depth + 1L)
      dusen <- c(dusen, alt$dropped)
      uygulanan <- c(uygulanan, alt$applied)
      if (!is.null(alt$mask)) maskeler[[length(maskeler) + 1L]] <- alt$mask
      next
    }

    yaprak <- pk_filter_normalize_leaf(cocuk)
    sonuc <- pk_filter_leaf_mask(data, yaprak, query = query)
    if (!isTRUE(sonuc$ok)) {
      dusen[[length(dusen) + 1L]] <- list(leaf = yaprak, reason = sonuc$reason)
      next
    }

    maske <- sonuc$mask
    if (.pk_filter_leaf_role(yaprak$operation) %in% "exclude") maske <- !maske
    maskeler[[length(maskeler) + 1L]] <- maske
    uygulanan[[length(uygulanan) + 1L]] <- yaprak
  }

  if (!length(maskeler)) return(list(mask = NULL, applied = uygulanan, dropped = dusen))

  birlesik <- maskeler[[1]]
  if (length(maskeler) > 1L) {
    for (i in 2:length(maskeler)) {
      birlesik <- if (identical(islec, "or")) (birlesik | maskeler[[i]]) else (birlesik & maskeler[[i]])
    }
  }

  list(mask = birlesik, applied = uygulanan, dropped = dusen)
}
