# ==============================================================================
# Dosya Yolu: R/helpers_pk_answer_facts_summary.R
# Açıklama: Olgulardan DETERMİNİSTİK özet üretimi (§5.8 / §5.11).
#
#           İKİ AYRI OKUYUCU, TEK SEÇİM:
#             * `pk_compose_facts_summary()` KULLANICIYA gösterilir; etiket ve
#               R'nin bastığı kanonik DEĞERİ taşır (`block` kipinde model
#               düzyazısı reddedildiğinde görünen metin budur).
#             * `pk_compose_facts_prompt_summary()` İSTEME girer; değer yerine
#               olgunun YUVA jetonunu taşır. Bütçe aşımında pakete değer basan
#               bir özet inince model ya sayıyı hiç anamıyor ya da görünen
#               değeri kopyalayıp protokol ihlali üretiyordu.
#
#           Seçim mantığı ORTAKTIR: iki listenin ayrışması, modelin hiç
#           görmediği bir olguyu anmasına yol açardı.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

# Özet için OLGU SEÇİMİ: her ÖLÇÜ için bir birincil olgu, sonra kalan kota.
# Kullanıcıya görünen özet ile İSTEME giden özet AYNI seçimi paylaşır; iki
# listenin ayrışması, modelin hiç görmediği bir olguyu anmasına yol açardı.
.pk_compose_summary_pick <- function(facts, limit) {
  kullanilabilir <- Filter(function(o) is.list(o) && !is.null(o$value), facts %||% list())
  if (!length(kullanilabilir)) return(list(selected = list(), omitted = 0L))

  # SINIR TAM SAYIYA İNDİRGENİR: `as.integer()` sayısal olmayan/`NA` bir değer
  # için `NA_integer_` döner, `max(1L, NA)` yine `NA` kalır ve aşağıdaki
  # `utils::head(..., NA)` HATA fırlatırdı.
  limit <- .pk_compose_int_or(limit, 12L)
  oncelik <- c("sum", "weighted_mean", "latest", "mean", "median", "max", "min")

  sutunlar <- unique(vapply(kullanilabilir, function(o) as.character(o$column)[1], character(1)))
  birincil <- list()
  for (sutun in sutunlar) {
    alt <- Filter(function(o) identical(as.character(o$column)[1], sutun), kullanilabilir)
    sira <- match(vapply(alt, function(o) as.character(o$aggregation)[1], character(1)), oncelik)
    sira[is.na(sira)] <- length(oncelik) + 1L
    birincil[[length(birincil) + 1L]] <- alt[[which.min(sira)]]
  }

  secilen <- utils::head(birincil, limit)
  kalan_kota <- limit - length(secilen)
  if (kalan_kota > 0L) {
    kimlikler <- vapply(secilen, function(o) as.character(o$fact_id)[1], character(1))
    digerleri <- Filter(function(o) !(as.character(o$fact_id)[1] %in% kimlikler), kullanilabilir)
    secilen <- c(secilen, utils::head(digerleri, kalan_kota))
  }

  list(selected = secilen, omitted = length(kullanilabilir) - length(secilen))
}

#' Bütçe aşımında İSTEME giden özet: değer değil YUVA jetonu taşır
#'
#' Zorunlu paket bütçeye sığmadığında pakete deterministik özet inerdi; o özet
#' yalnızca etiket ve BİÇİMLENMİŞ DEĞER basıyordu. Model o durumda ya sayıyı
#' hiç anamıyor ya da görünen değeri kopyalayıp `model_numeric_literal`
#' üretiyordu. Bu sürüm her satırda olgunun YUVASINI verir; değeri yine R basar.
pk_compose_facts_prompt_summary <- function(facts, limit = 12L) {
  if (!exists("pk_fact_reference_token", mode = "function", inherits = TRUE)) {
    return("")
  }
  secim <- .pk_compose_summary_pick(facts, limit)
  if (!length(secim$selected)) return("")

  satirlar <- vapply(secim$selected, function(o) {
    sprintf("- %s (%s): %s", as.character(o$label %||% o$column)[1],
            as.character(o$aggregation)[1],
            pk_fact_reference_token(as.character(o$fact_id)[1]))
  }, character(1))

  if (secim$omitted > 0L) {
    satirlar <- c(satirlar,
                  sprintf("- _(%s hesaplanan deger daha var; bu listede yok.)_",
                          pk_fmt_number(secim$omitted, 0L)))
  }

  paste(c("**Hesaplanan degerler (yuvali)**", satirlar), collapse = "\n")
}

#' Olgulardan deterministik kısa özet
#'
#' `block` kipinde (§5.11) model düzyazısı reddedildiğinde kullanıcıya
#' gösterilecek metin budur: yalnızca R'nin hesapladığı değerler. Her ÖLÇÜ için
#' önce bir birincil olgu seçilir; aksi hâlde ilk ölçünün istatistikleri
#' bütçenin tamamını yiyor ve sonraki ölçüler sessizce kayboluyordu.
#' @param attachment_available Bir EK GERÇEKTEN sunuluyor mu? `inline_table`
#'   kipinde `pk_compose_block()` hiç artefakt üretmez; bu metin blok kipinde
#'   köken doğrulaması model prozasını reddettiğinde kullanıldığı için,
#'   kullanıcı VAR OLMAYAN bir `Ozet` sayfasına yönlendiriliyordu.
pk_compose_facts_summary <- function(facts, limit = 12L,
                                     attachment_available = TRUE) {
  secim <- .pk_compose_summary_pick(facts, limit)
  secilen <- secim$selected
  if (!length(secilen)) return("")

  satirlar <- vapply(secilen, function(o) {
    sprintf("- %s (%s): %s", as.character(o$label %||% o$column)[1],
            as.character(o$aggregation)[1], as.character(o$display)[1])
  }, character(1))

  atlanan <- secim$omitted
  if (atlanan > 0L) {
    satirlar <- c(satirlar, if (isTRUE(attachment_available)) {
      sprintf("- _(%s hesaplanan değer daha var; tamamı ek dosyanın `Ozet` sayfasındadır.)_",
              pk_fmt_number(atlanan, 0L))
    } else {
      sprintf("- _(%s hesaplanan değer daha var; bu yanıtta gösterilmedi.)_",
              pk_fmt_number(atlanan, 0L))
    })
  }

  paste(c("**Hesaplanan değerler**", satirlar), collapse = "\n")
}
