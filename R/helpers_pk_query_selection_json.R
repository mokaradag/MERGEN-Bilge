# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_json.R
# Açıklama: Faz 5 (§5.2) — sorgu seçimi LLM çıktısının KATI JSON ilkeleri.
#
# Bu katman "kurtarmaya" değil, REDDETMEYE ayarlıdır. Karar kapılarının
# (güven, marj, yetenek) güvenilirliği doğrudan buradaki tip katılığına
# bağlıdır: sözleşme dışı bir değeri sessizce zorlamak, bir onarım denemesiyle
# düzeltilebilecek model hatasını "geçerli seçim"e çevirir.
#
# Katılık kuralları:
#   * cevabın TAMAMI tek bir JSON nesnesi olmalıdır (sarmalayıcı düzyazı
#     kabul edilmez; yalnızca tek bir kod bloğu çiti soyulur),
#   * aynı nesnede TEKRAR EDEN anahtar varsa cevap bozuktur (çelişkili
#     `confidence`/`id` alanları sessizce birine indirgenmez),
#   * skaler dize gerçekten TEK dize olmalıdır (dizi/nesne unlist EDİLMEZ),
#   * güven değeri gerçek bir JSON TAM SAYISI olmalıdır (metin, mantıksal,
#     dizi ya da kesirli değer kabul edilmez).
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

#' Tek bir kod bloğu çitini soy
#'
#' Yalnızca metnin TAMAMINI saran tek bir çit kabul edilir. Metnin ortasındaki
#' çitler soyulmaz; öyle bir cevap zaten düzyazı taşıyor demektir.
.pk_select_strip_fence <- function(text) {
  metin <- trimws(text)
  if (!grepl("^```", metin)) return(metin)

  # KAPANMAMIŞ ÇİT SOYULMAZ.
  #
  # Eskiden yalnızca AÇILIŞ çiti aranıyordu; kesilmiş (truncated) bir model
  # yanıtı olan "```json\n{...kesildi" açılışı soyulup gövde JSON gibi
  # değerlendiriliyordu. Kapanış çiti YOKSA yanıt EKSİKTİR ve ayrıştırma
  # denenmemelidir: metin olduğu gibi döner ve dıştaki katı `{...}` denetimi
  # onu reddeder.
  govde <- sub("^```[[:alnum:]_+-]*[[:space:]]*", "", metin)
  if (!grepl("```[[:space:]]*$", govde)) return(metin)

  trimws(sub("```[[:space:]]*$", "", govde))
}

# JSON dize kaçışlarını çöz (yalnızca anahtar KARŞILAŞTIRMASI için).
#
# `"model"` ile `"\u006dodel"` AYNI JSON üye adıdır; ham metinde ise farklı
# görünürler. Kaçışlar çözülmeden yapılan yineleme denetimi bu yüzden
# atlatılabiliyordu: çelişkili iki `confidence` alanından biri kaçışla
# yazıldığında denetim kaçırıyor ve `jsonlite` sessizce birini seçiyordu.
.pk_select_decode_json_name <- function(name) {
  if (!nzchar(name)) return(name)
  if (!grepl("\\", name, fixed = TRUE)) return(name)

  cozulmus <- tryCatch(
    jsonlite::fromJSON(paste0("\"", name, "\""), simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.character(cozulmus) && length(cozulmus) == 1L && !is.na(cozulmus)) {
    return(cozulmus)
  }
  name
}

#' Aynı JSON nesnesinde tekrar eden anahtarları bul
#'
#' `jsonlite` tekrar eden anahtarları SESSİZCE tek bir değere indirger; hangi
#' değerin kazandığı sözleşmenin parçası değildir. Çelişkili iki `confidence`
#' alanı bu yüzden ayrıştırıcıya kadar hiç görünmeden karar kapısına ulaşırdı.
#' Küçük bir tarayıcı ile ham metin üzerinde denetlenir; cevaplar birkaç KB
#' olduğu için maliyet önemsizdir.
pk_select_json_duplicate_keys <- function(text) {
  if (is.null(text) || !length(text)) return(character(0))
  ham <- as.character(text)[1]
  if (is.na(ham) || !nzchar(ham)) return(character(0))

  karakterler <- strsplit(ham, "", fixed = TRUE)[[1]]
  n <- length(karakterler)

  yigin <- list()        # her açık nesne için görülen anahtarlar
  bekleyen <- NULL       # en son okunan dize (anahtar adayı)
  tekrar <- character(0)
  i <- 1L

  while (i <= n) {
    ch <- karakterler[i]

    if (identical(ch, "\"")) {
      j <- i + 1L
      basla <- j
      while (j <= n) {
        if (identical(karakterler[j], "\\")) { j <- j + 2L; next }
        if (identical(karakterler[j], "\"")) break
        j <- j + 1L
      }
      bekleyen <- if (j > basla) paste(karakterler[basla:(j - 1L)], collapse = "") else ""
      bekleyen <- .pk_select_decode_json_name(bekleyen)
      i <- j + 1L
      next
    }

    if (identical(ch, "{")) {
      yigin[[length(yigin) + 1L]] <- character(0)
      bekleyen <- NULL
    } else if (identical(ch, "}")) {
      if (length(yigin)) yigin[[length(yigin)]] <- NULL
      bekleyen <- NULL
    } else if (identical(ch, ":")) {
      if (length(yigin) && !is.null(bekleyen)) {
        gorulen <- yigin[[length(yigin)]]
        if (bekleyen %in% gorulen) tekrar <- c(tekrar, bekleyen)
        yigin[[length(yigin)]] <- c(gorulen, bekleyen)
      }
      bekleyen <- NULL
    } else if (identical(ch, ",")) {
      bekleyen <- NULL
    }

    i <- i + 1L
  }

  unique(tekrar)
}

#' Model çıktısını KATI biçimde ayrıştır
#'
#' Sarmalayıcı düzyazı REDDEDİLİR. Eskiden ilk `{` ile son `}` arası
#' kesiliyordu; bu, "karar veremiyorum, ornek cikti: {...}" gibi bir cevabı
#' gerçek bir seçim gibi kabul ediyordu. Cevabın tamamı tek bir JSON nesnesi
#' olmalıdır.
#'
#' @return Ayrıştırılmış liste ya da `NULL` (kısmi/tahmini kurtarma YOKTUR).
pk_select_parse_json <- function(text) {
  if (is.null(text) || !length(text)) return(NULL)
  ham <- as.character(text)[1]
  if (is.na(ham) || !nzchar(trimws(ham))) return(NULL)

  govde <- .pk_select_strip_fence(ham)
  if (!nzchar(govde)) return(NULL)
  if (!startsWith(govde, "{") || !endsWith(govde, "}")) return(NULL)
  if (length(pk_select_json_duplicate_keys(govde))) return(NULL)

  ayrisik <- tryCatch(
    jsonlite::fromJSON(govde, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(ayrisik) || is.null(names(ayrisik))) return(NULL)
  ayrisik
}

#' KATI skaler dize
#'
#' `simplifyVector = FALSE` altında bir JSON dizisi listeye dönüşür; eski
#' davranış onu `unlist()` edip ilk öğeyi alıyordu. Böylece `"id":["q002","q001"]`
#' gibi "seçim yapamadım" anlamına gelen bir cevap kesin bir `q002` seçimine
#' çevriliyordu. Artık yalnızca gerçek tek dize kabul edilir.
pk_select_scalar_string <- function(x) {
  if (is.null(x) || !is.character(x) || length(x) != 1L || is.na(x)) return(NA_character_)
  deger <- trimws(x)
  if (!nzchar(deger)) return(NA_character_)
  deger
}

#' KATI skaler TAM SAYI (güven değerleri için)
#'
#' Reddedilenler: metin (`"95"`), mantıksal (`true`), dizi (`[95, 10]`),
#' kesirli (`49.6`) ve aralık dışı değerler. `is.numeric(TRUE)` R'de zaten
#' `FALSE`tur; mantıksal değer bu yüzden ilk kapıda düşer.
#'
#' @param min,max Kapsayıcı aralık.
pk_select_scalar_integer <- function(x, min = NULL, max = NULL) {
  if (is.null(x) || is.logical(x) || !is.numeric(x) || length(x) != 1L) return(NA_integer_)
  if (is.na(x) || !is.finite(x)) return(NA_integer_)
  if (!isTRUE(all.equal(as.numeric(x), round(as.numeric(x)))) ||
      as.numeric(x) != round(as.numeric(x))) {
    return(NA_integer_)
  }
  if (abs(as.numeric(x)) > .Machine$integer.max) return(NA_integer_)

  deger <- as.integer(round(as.numeric(x)))
  if (!is.null(min) && deger < as.integer(min)) return(NA_integer_)
  if (!is.null(max) && deger > as.integer(max)) return(NA_integer_)
  deger
}

#' KATI dize dizisi (düz, yalnızca skaler dizeler)
#'
#' `unlist()` iç içe nesneleri de düzleştirir; `{"id":"q001","reason":"q004"}`
#' gibi bir öğe iki ayrı adaya dönüşüyordu. Artık her öğe TEK dize olmalıdır.
#'
#' @return `ok` ve `values` alanlı liste.
pk_select_string_array <- function(x) {
  if (is.null(x)) return(list(ok = FALSE, values = character(0)))
  if (is.character(x) && !is.null(names(x))) return(list(ok = FALSE, values = character(0)))

  # DİZİ İSTENEN YERDE SKALER DİZE KABUL EDİLMEZ.
  #
  # `simplifyVector = FALSE` ile ayrıştırılan GERÇEK bir JSON dizisi HER ZAMAN
  # listedir. Skaleri `as.list()` ile diziye yükseltmek, sözleşmeyi ihlal eden
  # bir yanıtı (`"aday": "Q1"` yerine `["Q1"]`) sessizce kabul etmek demekti;
  # model dizi sözleşmesini bozduğunda bunu görmemiz gerekir.
  if (!is.list(x)) return(list(ok = FALSE, values = character(0)))
  ogeler <- x
  if (!length(ogeler)) return(list(ok = TRUE, values = character(0)))
  if (!is.null(names(ogeler)) && any(nzchar(names(ogeler)))) {
    return(list(ok = FALSE, values = character(0)))
  }

  degerler <- character(length(ogeler))
  for (i in seq_along(ogeler)) {
    deger <- pk_select_scalar_string(ogeler[[i]])
    if (is.na(deger)) return(list(ok = FALSE, values = character(0)))
    degerler[i] <- deger
  }

  list(ok = TRUE, values = degerler)
}

#' Açıkça `null` OLABİLEN skaler metin alanı
#'
#' Üç durum AYRIT EDİLİR: alan yok (`absent`), açıkça `null` (`null`) ve
#' geçerli metin (`text`). "Yok" ile "null" aynı kovaya konduğunda, kırpılmış
#' bir cevabın eksik `missing_info` alanı "eksik bilgi yok" anlamına geliyordu.
pk_select_nullable_text <- function(container, field) {
  if (!is.list(container) || !(field %in% names(container))) {
    return(list(state = "absent", value = NA_character_))
  }

  deger <- container[[field]]
  if (is.null(deger)) return(list(state = "null", value = NA_character_))

  metin <- pk_select_scalar_string(deger)
  if (is.na(metin)) return(list(state = "invalid", value = NA_character_))
  list(state = "text", value = metin)
}
