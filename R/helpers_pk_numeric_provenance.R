# ==============================================================================
# Dosya Yolu: R/helpers_pk_numeric_provenance.R
# Açıklama: Sayısal köken (numeric provenance) doğrulaması — master plan §5.11.
#
#           Çıplak jeton karşılaştırması YETERSİZDİR: paket `47` sayısını
#           "farklı kişi sayısı" olarak içeriyorsa, düzyazıdaki "tamamlanma %47"
#           ifadesi jeton olarak eşleşse bile YANLIŞTIR. Bu yüzden paket, her
#           sayı için yapılandırılmış bir olgu (fact) yayımlar ve kompozisyon
#           istemi her sayısal iddianın yanına makine tarafından okunabilir bir
#           `[fact:...]` referansı koymak zorundadır. Doğrulayıcı hem DEĞERİ hem
#           de ANLAMSAL kullanımı (birim/kullanılabilirlik) denetler; referans
#           işaretleri gösterimden ancak doğrulamadan SONRA silinir.
#
#           Kipler (`MERGEN_PK_NUMERIC_PROVENANCE_MODE`):
#             off   -> kapalı (yalnızca işaretler temizlenir)
#             log   -> uyuşmazlıklar KAYDEDİLİR; kullanıcıya görünen yanıt
#                      değişmez. KALİBRASYON kipidir ve varsayılandır.
#             warn  -> doğrulanamayan sayılar görünür biçimde işaretlenir
#             block -> düzyazı reddedilir; deterministik özet gösterilir
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

PK_PROV_MODES <- c("off", "log", "warn", "block")

# Düzyazıdaki sayı + (isteğe bağlı) yüzde/birim + `[fact:...]` referansı.
.PK_PROV_MARKER <- "\\[fact:([A-Za-z0-9_.]+)\\]"

pk_numeric_provenance_mode <- function(query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return("log")
  kip <- tryCatch(
    pk_config_resolve("MERGEN_PK_NUMERIC_PROVENANCE_MODE", query_meta = query_meta),
    error = function(e) "log"
  )
  if (!is.character(kip) || length(kip) != 1L || !(kip %in% PK_PROV_MODES)) return("log")
  kip
}

#' Türkçe veya sade biçimli bir sayıyı ayrıştır
#'
#' "18.420,5" -> 18420.5 · "61,3" -> 61.3 · "18420.5" -> 18420.5
#' Belirsiz gruplama (ör. "1.234,56.7") reddedilir.
pk_parse_number_tr <- function(txt) {
  ham <- as.character(txt %||% "")[1]
  if (is.na(ham) || !nzchar(ham)) return(NULL)

  ham <- gsub("[[:space:] ]", "", ham)
  negatif <- startsWith(ham, "-")
  if (negatif || startsWith(ham, "+")) ham <- substring(ham, 2L)

  if (!grepl("^[0-9.,]+$", ham)) return(NULL)

  virgul <- gregexpr(",", ham, fixed = TRUE)[[1]]
  virgul_sayisi <- if (identical(virgul[1], -1L)) 0L else length(virgul)
  if (virgul_sayisi > 1L) return(NULL)

  if (virgul_sayisi == 1L) {
    parcalar <- strsplit(ham, ",", fixed = TRUE)[[1]]
    tam <- parcalar[1]
    kesir <- if (length(parcalar) > 1L) parcalar[2] else ""
    if (grepl(".", kesir, fixed = TRUE)) return(NULL)
    if (grepl(".", tam, fixed = TRUE) && !grepl("^[0-9]{1,3}(\\.[0-9]{3})+$", tam)) return(NULL)
    tam <- gsub(".", "", tam, fixed = TRUE)
    ham <- if (nzchar(kesir)) paste0(tam, ".", kesir) else tam
  } else if (grepl("^[0-9]{1,3}(\\.[0-9]{3})+$", ham)) {
    # Yalnızca binlik gruplama; "1.234" burada 1234'tur.
    ham <- gsub(".", "", ham, fixed = TRUE)
  } else if (lengths(regmatches(ham, gregexpr(".", ham, fixed = TRUE))) > 1L) {
    return(NULL)
  }

  num <- suppressWarnings(as.numeric(ham))
  if (length(num) != 1L || is.na(num) || !is.finite(num)) return(NULL)
  if (negatif) num <- -num
  num
}

# İddia edilen sayının ondalık basamak sayısı -> yuvarlama toleransı.
#
# Ayrım kritiktir: "18.420" Türkçe binlik gruplamadır ve ondalık basamak
# TAŞIMAZ. Noktayı ondalık ayraç sanmak toleransı 0,0005'e düşürür ve tam
# sayıya yuvarlanmış meşru bir alıntı yanlışlıkla uyuşmazlık sayılır.
.pk_prov_decimals <- function(gosterim) {
  txt <- gsub("[[:space:]]", "", as.character(gosterim %||% "")[1])
  if (is.na(txt) || !nzchar(txt)) return(0L)

  if (grepl(",", txt, fixed = TRUE)) {
    kesir <- sub("^.*,", "", txt)
    return(if (grepl("^[0-9]+$", kesir)) nchar(kesir) else 0L)
  }

  # Yalnızca binlik gruplama: ondalık basamak yok.
  if (grepl("^-?[0-9]{1,3}(\\.[0-9]{3})+$", txt)) return(0L)

  if (grepl(".", txt, fixed = TRUE)) {
    kesir <- sub("^.*\\.", "", txt)
    return(if (grepl("^[0-9]+$", kesir)) nchar(kesir) else 0L)
  }

  0L
}

.pk_prov_tolerance <- function(gosterim, gercek) {
  0.5 * 10^(-.pk_prov_decimals(gosterim)) + abs(as.numeric(gercek)) * 1e-9
}

#' Olguları kimliğe göre indeksle
pk_facts_index <- function(facts) {
  out <- list()
  for (olgu in (facts %||% list())) {
    if (is.list(olgu) && is.character(olgu$fact_id) && nzchar(olgu$fact_id)) {
      out[[olgu$fact_id]] <- olgu
    }
  }
  out
}

# Metindeki her `[fact:...]` referansını ve hemen ÖNCESİNDEKİ sayıyı çıkarır.
.pk_prov_claims <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt) || !nzchar(txt)) return(list())

  konum <- gregexpr(.PK_PROV_MARKER, txt, perl = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(list())

  uzunluk <- attr(konum, "match.length")
  out <- list()

  for (i in seq_along(konum)) {
    isaret <- substr(txt, konum[i], konum[i] + uzunluk[i] - 1L)
    fact_id <- sub("^\\[fact:", "", sub("\\]$", "", isaret))

    onceki <- substr(txt, max(1L, konum[i] - 60L), konum[i] - 1L)
    eslesme <- regmatches(
      onceki,
      gregexpr("(%\\s*)?-?[0-9][0-9.,]*\\s*(%|[A-Za-zÇĞİÖŞÜçğıöşü]{1,12})?\\s*$",
               onceki, perl = TRUE)
    )[[1]]

    ham <- if (length(eslesme)) trimws(eslesme[length(eslesme)]) else ""
    yuzde <- grepl("%", ham, fixed = TRUE)
    sayi_metni <- trimws(gsub("%", "", ham))
    birim <- sub("^-?[0-9][0-9.,]*\\s*", "", sayi_metni)
    sayi_metni <- regmatches(sayi_metni, regexpr("^-?[0-9][0-9.,]*", sayi_metni))
    sayi_metni <- if (length(sayi_metni)) sayi_metni[1] else ""

    out[[length(out) + 1L]] <- list(
      fact_id = fact_id,
      marker = isaret,
      raw = ham,
      number_text = sayi_metni,
      value = pk_parse_number_tr(sayi_metni),
      percent = yuzde,
      unit = trimws(birim)
    )
  }

  out
}

#' Sayısal iddiaları olgulara karşı doğrula
#'
#' @return `list(checked=, mismatches=, rate=, claims=)`
pk_numeric_provenance_validate <- function(text, facts) {
  index <- pk_facts_index(facts)
  iddialar <- .pk_prov_claims(text)
  uyusmazliklar <- list()

  for (iddia in iddialar) {
    olgu <- index[[iddia$fact_id]]

    if (is.null(olgu)) {
      uyusmazliklar[[length(uyusmazliklar) + 1L]] <- list(
        fact_id = iddia$fact_id, reason = "unknown_fact", claimed = iddia$number_text
      )
      next
    }

    if (is.null(olgu$value)) {
      uyusmazliklar[[length(uyusmazliklar) + 1L]] <- list(
        fact_id = iddia$fact_id, reason = "unavailable_fact", claimed = iddia$number_text,
        status = olgu$status
      )
      next
    }

    if (is.null(iddia$value)) {
      uyusmazliklar[[length(uyusmazliklar) + 1L]] <- list(
        fact_id = iddia$fact_id, reason = "no_number", claimed = iddia$raw
      )
      next
    }

    if (abs(iddia$value - olgu$value) > .pk_prov_tolerance(iddia$number_text, olgu$value)) {
      uyusmazliklar[[length(uyusmazliklar) + 1L]] <- list(
        fact_id = iddia$fact_id, reason = "value_mismatch",
        claimed = iddia$number_text, actual = olgu$value
      )
      next
    }

    # Anlamsal denetim: doğru sayı YANLIŞ ölçü için alıntılanamaz. Yüzde
    # işareti taşıyan bir iddia, birimi yüzde OLMAYAN bir olguya bağlanamaz.
    olgu_birimi <- as.character(olgu$unit %||% "")[1]
    if (is.na(olgu_birimi)) olgu_birimi <- ""

    if (isTRUE(iddia$percent) && !identical(olgu_birimi, "%")) {
      uyusmazliklar[[length(uyusmazliklar) + 1L]] <- list(
        fact_id = iddia$fact_id, reason = "unit_mismatch",
        claimed = "%", actual = olgu_birimi
      )
      next
    }

    if (!isTRUE(iddia$percent) && identical(olgu_birimi, "%") && nzchar(iddia$unit)) {
      uyusmazliklar[[length(uyusmazliklar) + 1L]] <- list(
        fact_id = iddia$fact_id, reason = "unit_mismatch",
        claimed = iddia$unit, actual = olgu_birimi
      )
      next
    }

    if (nzchar(iddia$unit) && nzchar(olgu_birimi) &&
        !identical(tolower(iddia$unit), tolower(olgu_birimi))) {
      uyusmazliklar[[length(uyusmazliklar) + 1L]] <- list(
        fact_id = iddia$fact_id, reason = "unit_mismatch",
        claimed = iddia$unit, actual = olgu_birimi
      )
    }
  }

  list(
    checked = length(iddialar),
    mismatches = uyusmazliklar,
    rate = if (length(iddialar)) length(uyusmazliklar) / length(iddialar) else 0,
    claims = iddialar
  )
}

#' Referans işaretlerini gösterimden temizle
pk_numeric_provenance_strip <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (is.na(txt)) return("")
  txt <- gsub(paste0("[[:space:]]*", .PK_PROV_MARKER), "", txt, perl = TRUE)
  txt
}

#' Doğrulamayı uygula ve gösterilecek metni üret
#'
#' `block` kipinde düzyazı REDDEDİLİR: yeniden üretim isteği çağıranın
#' sorumluluğundadır; bu fonksiyon deterministik yedek metni döndürür.
#'
#' @param fallback_text `block` kipinde gösterilecek deterministik metin.
pk_numeric_provenance_apply <- function(text, facts, mode = NULL, fallback_text = NULL) {
  kip <- as.character(mode %||% pk_numeric_provenance_mode())[1]
  if (!(kip %in% PK_PROV_MODES)) kip <- "log"

  ham <- as.character(text %||% "")[1]
  if (is.na(ham)) ham <- ""

  if (identical(kip, "off")) {
    return(list(text = pk_numeric_provenance_strip(ham), mode = kip,
                checked = 0L, mismatches = list(), rate = 0, blocked = FALSE))
  }

  sonuc <- pk_numeric_provenance_validate(ham, facts)
  temiz <- pk_numeric_provenance_strip(ham)

  if (identical(kip, "warn") && length(sonuc$mismatches)) {
    parcalar <- vapply(sonuc$mismatches, function(m) {
      sprintf("%s (%s)", as.character(m$claimed %||% "?")[1], m$reason)
    }, character(1))
    temiz <- paste0(
      temiz,
      "\n\n\U000026A0\U0000FE0F **Doğrulanamayan sayılar:** ",
      paste(unique(parcalar), collapse = ", "),
      ". Bu değerler hesaplanan olgularla eşleştirilemedi; lütfen ekteki ",
      "deterministik tabloyu esas alın."
    )
  }

  engellendi <- identical(kip, "block") && length(sonuc$mismatches) > 0L
  if (engellendi) {
    yedek <- as.character(fallback_text %||% "")[1]
    temiz <- paste0(
      "\U000026A0\U0000FE0F **Yanıt doğrulanamadı:** Üretilen açıklamadaki sayılar ",
      "hesaplanan olgularla eşleşmedi; açıklama gösterilmiyor. Aşağıdaki ",
      "değerler R tarafından hesaplanmıştır.",
      if (nzchar(yedek) && !is.na(yedek)) paste0("\n\n", yedek) else ""
    )
  }

  list(
    text = temiz, mode = kip, checked = sonuc$checked,
    mismatches = sonuc$mismatches, rate = sonuc$rate, blocked = engellendi
  )
}

#' Ölçülen uyuşmazlık oranını sunucu tarafında raporla (sırsız)
#'
#' Yalnızca sayaç/oran ve uyuşmazlık nedenleri yazılır; düzyazı, soru metni ya
#' da herhangi bir veri değeri LOGA GİRMEZ.
pk_numeric_provenance_report <- function(result, query_id = NULL) {
  if (!is.list(result)) return(invisible(NULL))

  nedenler <- vapply(result$mismatches %||% list(),
                     function(m) as.character(m$reason %||% "?")[1], character(1))
  ozet <- if (length(nedenler)) paste(sort(unique(nedenler)), collapse = ",") else "-"

  cat(sprintf(
    "[PK_ANALIZ] Sayisal koken | kip=%s | sorgu=%s | iddia=%d | uyusmazlik=%d | oran=%.3f | nedenler=%s\n",
    result$mode %||% "?", as.character(query_id %||% "?")[1],
    as.integer(result$checked %||% 0L), length(result$mismatches %||% list()),
    as.numeric(result$rate %||% 0), ozet
  ))

  invisible(result)
}
