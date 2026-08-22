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

# BİLİNMEYEN BİRLEŞTİRİCİ SESSİZCE `and`E ÇEVRİLMEZ.
#
# Eskiden OR olmayan HER belirteç AND sayılıyordu; model `not`/`xor` ya da bir
# yazım hatası ürettiğinde ayrıştırıcı `{operator, children}` nesnesini kabul
# ediyor ve ifade FARKLI ANLAMLA sessizce çalıştırılıyordu — kendinden emin
# ama yanlış bir alt küme. Belirteç açık AND/OR kümelerine karşı doğrulanır;
# bilinmeyen değer `NA` döner ve grup REDDEDİLİR.
.pk_filter_group_operator <- function(x) {
  ham <- as.character(x$operator %||% x$logic %||% NA_character_)[1]
  if (is.null(ham) || length(ham) != 1L || is.na(ham) || !nzchar(trimws(ham))) {
    # Belirteç HİÇ verilmemişse sözleşmenin varsayılanı `and`dir.
    return("and")
  }

  belirtec <- .pk_filter_ascii_lower(trimws(ham))
  if (is.na(belirtec)) return(NA_character_)
  if (belirtec %in% PK_FILTER_OR_TOKENS) return("or")
  if (belirtec %in% PK_FILTER_AND_TOKENS) return("and")
  NA_character_
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
  if (is.na(islec)) {
    return(list(mask = NULL, applied = list(), dropped = list(list(
      leaf = list(column = "__group__", values = character(0)),
      reason = sprintf("desteklenmeyen mantik birlestirici: %s",
                       as.character(node$operator %||% node$logic %||% "?")[1])
    ))))
  }

  cocuklar <- node$children
  # BOŞ GRUP SESSİZCE YOK SAYILMAZ.
  #
  # Çocuksuz bir grup, kullanıcının istediği kısıtın KAYBOLMASI demektir.
  # `bos` sonucu `mask = NULL`, `applied`/`dropped` boş döndürdüğü için düğüm
  # `pk_filter_compile()` içinde sayılmıyor, `all_dropped` FALSE kalıyor ve
  # ifşa hattı sessizleşiyordu: analiz DAHA GENİŞ popülasyonu, grup uygulanmış
  # gibi raporluyordu. Diğer tüm ret yolları gibi burada da `__group__` kaydı
  # döndürülür.
  if (!length(cocuklar)) {
    return(list(mask = NULL, applied = list(), dropped = list(list(
      leaf = list(column = "__group__", values = character(0)),
      reason = sprintf("filtre grubu bos; hicbir kosul tasimiyor (islec: %s)", islec)
    ))))
  }

  maskeler <- list()
  uygulanan <- list()
  dusen <- list()

  # KISMEN DEĞERLENDİRİLEN GRUP REDDEDİLİR.
  #
  # Bir çocuk değerlendirilemediğinde (geçersiz değer, olmayan sütun, alt grubun
  # reddi) eskiden yalnızca O çocuk düşürülüyor, kalan maskeler birleştiriliyordu.
  # Bu, kullanıcının İSTEDİĞİ mantıksal ifadeyi SESSİZCE DEĞİŞTİRMEKTİR:
  # `(Proje = A AND Yil = 2024)` içinde proje yaprağı düşerse geriye TÜM
  # projeleri kapsayan bir yıl filtresi kalır ve sıfır-eşleşme politikası bu
  # GENİŞLETİLMİŞ kümeyle çalışır. Grup ya TAMAMEN uygulanır ya da REDDEDİLİR.
  basarisiz <- FALSE

  for (cocuk in cocuklar) {
    if (.pk_filter_is_group_node(cocuk)) {
      alt <- .pk_filter_eval_group(data, cocuk, query = query, depth = depth + 1L)
      dusen <- c(dusen, alt$dropped)
      uygulanan <- c(uygulanan, alt$applied)
      if (is.null(alt$mask)) {
        basarisiz <- TRUE
      } else {
        maskeler[[length(maskeler) + 1L]] <- alt$mask
      }
      next
    }

    yaprak <- pk_filter_normalize_leaf(cocuk)
    sonuc <- pk_filter_leaf_mask(data, yaprak, query = query)
    if (!isTRUE(sonuc$ok)) {
      dusen[[length(dusen) + 1L]] <- list(leaf = yaprak, reason = sonuc$reason)
      basarisiz <- TRUE
      next
    }

    maske <- sonuc$mask
    if (.pk_filter_leaf_role(yaprak$operation) %in% "exclude") maske <- !maske
    maskeler[[length(maskeler) + 1L]] <- maske
    uygulanan[[length(uygulanan) + 1L]] <- yaprak
  }

  if (isTRUE(basarisiz)) {
    return(list(mask = NULL, applied = list(), dropped = c(dusen, list(list(
      leaf = list(column = "__group__", values = character(0)),
      reason = "grup icindeki bir kosul degerlendirilemedi; grup TAMAMEN reddedildi"
    )))))
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
