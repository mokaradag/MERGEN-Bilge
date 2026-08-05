# ==============================================================================
# Dosya Yolu: R/helpers_pk_answer_compose.R
# Açıklama: Yanıt kompozisyonu — düzyazı + tablo + ek yönlendirmesi (§5.8).
#
#           Sözleşme:
#             * Düzyazı MODELE aittir ve yalnızca pakette bulunan olguları
#               alıntılayabilir; hiçbir aritmetik yapmaz.
#             * TABLO R'ye aittir ve model tarafından ASLA yeniden üretilmez.
#               Bu yüzden sistem isteminden "markdown tablo üret" talimatı
#               kaldırılmıştır (D20 / §5.8) — o talimat aracın en yüksek riskli,
#               en düşük değerli LLM görevi ve yuvarlanmış/uydurulmuş sayıların
#               doğrudan kaynağıydı.
#             * EK R'ye aittir: tam yetkili+filtreli sonuç ya eksiksiz aktarılır
#               ya da açıkça reddedilir; sessizce kırpılmış bir dosya "eksiksiz"
#               diye sunulmaz.
#             * R'ye ait tablo hücreleri de VERİDİR: markdown bağlantı/görsel
#               söz dizimi etkisizleştirilir, sayılar sütun metadata'sıyla
#               (birim / ondalık / yüzde ölçeği) biçimlenir.
#
#           Eşik kuralları SIRALIDIR ve İLK EŞLEŞEN KAZANIR. Sıra olmadan
#           100 satır x 20 sütunluk bir sonuç hem "<= 200 satır" hem "> 12 sütun"
#           koşulunu sağlar ve iki uygulama farklı davranır.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

.pk_compose_cfg <- function(key, query_meta = NULL, fallback) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return(fallback)
  tryCatch(pk_config_resolve(key, query_meta = query_meta), error = function(e) fallback)
}

# Kullanıcının açıkça liste/döküm/rapor/excel istediği KÖKLER. Türkçe eklemeli
# bir dildir; bu yüzden kök EŞLEŞMESİ sözcük başında aranır ("listeyi",
# "excel'e", "raporunu" hepsi sayılır) ama sözcük ORTASINDA aranmaz.
PK_COMPOSE_EXPORT_HINTS <- c(
  "liste", "listele", "listeyi", "dokum", "döküm", "rapor", "excel",
  "xlsx", "disa aktar", "dışa aktar", "indir", "tablo halinde", "csv"
)

PK_COMPOSE_CSV_HINTS <- c("csv")
PK_COMPOSE_XLSX_HINTS <- c("excel", "xlsx")

# Olumsuzlama: "Excel istemiyorum", "rapor gerek yok", "dosya olmasın".
PK_COMPOSE_NEGATIONS <- c(
  "isteme", "istemem", "istemiyor", "gerek yok", "gerekmiyor", "olmasin",
  "gerekli degil", "lazim degil", "hayir", "yollama", "gonderme", "ekleme",
  "cikarma", "olusturma", "uretme"
)

.pk_compose_fold <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (is.na(txt)) return("")
  if (exists("pk_tr_fold", mode = "function", inherits = TRUE)) {
    katlanmis <- tryCatch(pk_tr_fold(txt), error = function(e) NULL)
    if (is.character(katlanmis) && length(katlanmis) == 1L && !is.na(katlanmis)) {
      return(katlanmis)
    }
  }
  # pk_tr_fold yoksa SESSİZCE tolower()'a düşmek yerine yalnızca ASCII katlanır;
  # Türkçe İ/I eşlemesi tahmin edilmez.
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", txt)
}

# Kök, sözcük BAŞINDA mı geçiyor? ("excel" -> "excelde" evet, "makexcel" hayır)
#
# Eşleşme SABİT metinle yapılır; ipucu köklerini düzenli ifadeye kaçırmak
# gereksiz ve kırılgandır (köşeli ifade içinde `{}` TRE'de geçersizdir).
.pk_compose_has_root <- function(katlanmis, kok) {
  if (!nzchar(kok)) return(FALSE)

  konum <- gregexpr(kok, katlanmis, fixed = TRUE)[[1]]
  if (identical(konum[1], -1L)) return(FALSE)

  onceki <- ifelse(konum == 1L, "", substr(katlanmis, konum - 1L, konum - 1L))
  any(konum == 1L | !grepl("^[a-z0-9]$", onceki))
}

#' Kullanıcının dışa aktarım niyeti (biçim dâhil)
#'
#' Çıplak alt dize eşleşmesi `Excel istemiyorum; sadece özetle` isteğini de
#' "Excel istiyor" sayıyor ve kullanıcının AÇIK talimatına rağmen tam eki ve
#' G/Ç'sini zorluyordu. Niyet cümlecik cümlecik değerlendirilir; olumsuzlama
#' taşıyan cümlecikteki ipucu SAYILMAZ.
#'
#' @return `list(wants = , format = "xlsx"|"csv"|NA_character_)`
pk_compose_export_intent <- function(user_prompt) {
  katlanmis <- .pk_compose_fold(user_prompt)
  if (!nzchar(katlanmis)) return(list(wants = FALSE, format = NA_character_))

  cumlecikler <- unlist(strsplit(katlanmis, "[.;:\n]|,| ama | ancak | fakat ", perl = TRUE))
  cumlecikler <- trimws(cumlecikler)
  cumlecikler <- cumlecikler[nzchar(cumlecikler)]
  if (!length(cumlecikler)) cumlecikler <- katlanmis

  istiyor <- FALSE
  bicim <- NA_character_

  for (cumle in cumlecikler) {
    olumsuz <- any(vapply(PK_COMPOSE_NEGATIONS, function(n) {
      grepl(.pk_compose_fold(n), cumle, fixed = TRUE)
    }, logical(1)))
    if (olumsuz) next

    eslesen <- Filter(function(ipucu) {
      .pk_compose_has_root(cumle, .pk_compose_fold(ipucu))
    }, PK_COMPOSE_EXPORT_HINTS)
    if (!length(eslesen)) next

    istiyor <- TRUE
    if (is.na(bicim)) {
      if (any(vapply(PK_COMPOSE_CSV_HINTS, function(h) {
        .pk_compose_has_root(cumle, .pk_compose_fold(h))
      }, logical(1)))) {
        bicim <- "csv"
      } else if (any(vapply(PK_COMPOSE_XLSX_HINTS, function(h) {
        .pk_compose_has_root(cumle, .pk_compose_fold(h))
      }, logical(1)))) {
        bicim <- "xlsx"
      }
    }
  }

  list(wants = istiyor, format = bicim)
}

#' Kullanıcı açıkça liste/dışa aktarım istedi mi?
pk_compose_wants_export <- function(user_prompt) {
  isTRUE(pk_compose_export_intent(user_prompt)$wants)
}

#' Sunum kipini belirle (SIRALI, ilk eşleşen kazanır)
#'
#' @return `list(mode = "attachment"|"inline_table"|"dt", rule=, preview_rows=,
#'   format=)`
pk_compose_decide <- function(rows, cols, user_prompt = "", query_meta = NULL) {
  rows <- suppressWarnings(as.integer(rows %||% 0L))
  cols <- suppressWarnings(as.integer(cols %||% 0L))
  if (is.na(rows)) rows <- 0L
  if (is.na(cols)) cols <- 0L

  onizleme <- .pk_compose_cfg("MERGEN_PK_PREVIEW_ROWS", query_meta, 10L)
  dt_satir <- .pk_compose_cfg("MERGEN_PK_DT_MAX_ROWS", query_meta, 200L)
  dt_sutun <- .pk_compose_cfg("MERGEN_PK_INLINE_MAX_COLS_DT", query_meta, 12L)
  ic_satir <- .pk_compose_cfg("MERGEN_PK_INLINE_MAX_ROWS", query_meta, 15L)
  ic_sutun <- .pk_compose_cfg("MERGEN_PK_INLINE_MAX_COLS", query_meta, 8L)

  niyet <- pk_compose_export_intent(user_prompt)

  if (isTRUE(niyet$wants)) {
    return(list(mode = "attachment", rule = 1L, preview_rows = onizleme,
                format = niyet$format))
  }
  if (rows > dt_satir || cols > dt_sutun) {
    return(list(mode = "attachment", rule = 2L, preview_rows = onizleme,
                format = NA_character_))
  }
  if (rows <= ic_satir && cols <= ic_sutun) {
    return(list(mode = "inline_table", rule = 3L, preview_rows = rows,
                format = NA_character_))
  }

  list(mode = "dt", rule = 4L, preview_rows = onizleme, format = NA_character_)
}

#' Model metnini R'ye ait blok eklenebilecek hâle getir
#'
#' Kapatılmamış bir çitli kod bloğu, ardına eklenen tabloyu/eki/alt bilgiyi
#' kendi içine alır: indirme bağlantısı tıklanamaz, alt bilgi kod gibi görünür.
pk_compose_close_markdown <- function(text) {
  txt <- as.character(text %||% "")[1]
  if (length(txt) != 1L || is.na(txt) || !nzchar(txt)) return("")

  satirlar <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  cit <- sum(grepl("^\\s*(```|~~~)", satirlar, perl = TRUE))
  if (cit %% 2L == 1L) txt <- paste0(txt, "\n```")

  txt
}

# Markdown yapısını bozabilecek karakterleri etkisizleştirir. Ham HTML kaçışı
# merkezî markdown güvenlik sınırında yapılır; buradaki amaç hem tablo
# yapısının bir hücre yüzünden kırılmaması hem de VERİ DEĞERİNİN etkin
# bağlantı/görsele dönüşememesidir.
.pk_compose_escape <- function(txt, max_chars = 120L) {
  if (length(txt) != 1L || is.na(txt)) txt <- ""
  txt <- gsub("[\r\n\t]+", " ", txt)
  txt <- gsub("|", "\\|", txt, fixed = TRUE)
  # `[etiket](url)` ve `![](url)` veri hücresinden ETKİN bağlantı/görsel
  # üretemez; köşeli parantezler sökülür.
  txt <- gsub("[][]", "", txt)
  txt <- gsub("`", "'", txt, fixed = TRUE)
  txt <- trimws(gsub("[[:space:]]+", " ", txt))

  kirpildi <- nchar(txt) > max_chars
  if (kirpildi) txt <- paste0(substr(txt, 1L, max_chars), "…")

  list(text = txt, truncated = kirpildi)
}

# Sayısal hücreler dışa aktarımla AYNI değer sözleşmesini kullanır: kesir
# olarak saklanan bir yüzde (`0,613`) tabloda `%61,3` görünür, `points`
# ölçeğindeki `61,3` de öyle. Ölçek beyan edilmemişse değer ÖLÇEKLENMEZ ve
# yüzde işareti EKLENMEZ (tahmin, tam da %6130,0 hatasını üreten davranıştır).
.pk_compose_cell <- function(x, cmeta = NULL, max_chars = 120L) {
  cmeta <- if (is.list(cmeta)) cmeta else list()

  if (inherits(x, "Date") || inherits(x, "POSIXt")) {
    return(.pk_compose_escape(format(x), max_chars))
  }

  if (is.numeric(x)) {
    birim <- as.character(cmeta$unit %||% "")[1]
    if (is.na(birim)) birim <- ""
    ondalik <- cmeta$decimals
    olcek <- as.character(cmeta$percent_scale %||% "")[1]

    if (identical(birim, "%")) {
      if (identical(olcek, "fraction")) {
        return(.pk_compose_escape(
          paste0("%", pk_fmt_number(x * 100, ondalik %||% 1L)), max_chars))
      }
      if (identical(olcek, "points")) {
        return(.pk_compose_escape(
          paste0("%", pk_fmt_number(x, ondalik %||% 1L)), max_chars))
      }
      return(.pk_compose_escape(pk_fmt_number(x, ondalik), max_chars))
    }

    return(.pk_compose_escape(pk_fmt_number(x, ondalik, if (nzchar(birim)) birim else NULL),
                              max_chars))
  }

  .pk_compose_escape(as.character(x), max_chars)
}

# Başlık: metadata etiketi + birim. Yüzde sütunlarında ölçek beyan edilmemişse
# birim başlıkta "(%)" olarak görünür (dışa aktarımla aynı sözleşme).
.pk_compose_header <- function(column, cmeta) {
  cmeta <- if (is.list(cmeta)) cmeta else list()
  etiket <- if (is.character(cmeta$label) && nzchar(cmeta$label %||% "")) cmeta$label else column
  birim <- as.character(cmeta$unit %||% "")[1]
  if (is.na(birim)) birim <- ""

  if (identical(birim, "%") &&
      !(as.character(cmeta$percent_scale %||% "")[1] %in% c("points", "fraction"))) {
    etiket <- sprintf("%s (%%)", etiket)
  } else if (nzchar(birim) && !identical(birim, "%") && !grepl(birim, etiket, fixed = TRUE)) {
    etiket <- sprintf("%s (%s)", etiket, birim)
  }

  .pk_compose_escape(etiket, 60L)$text
}

#' Deterministik markdown tablo (R'ye aittir; model üretmez)
pk_compose_markdown_table <- function(data, max_rows = 15L, max_cols = 12L, meta = list()) {
  if (!is.data.frame(data) || !nrow(data) || !ncol(data)) return(NULL)

  max_rows <- max(1L, suppressWarnings(as.integer(max_rows)))
  max_cols <- max(1L, suppressWarnings(as.integer(max_cols)))

  gorunur <- utils::head(data, max_rows)
  sutun_kirp <- ncol(gorunur) > max_cols
  if (sutun_kirp) gorunur <- gorunur[, seq_len(max_cols), drop = FALSE]

  sutun_meta <- if (is.list(meta) && is.list(meta$column_meta)) meta$column_meta else list()
  basliklar <- vapply(names(gorunur), function(s) .pk_compose_header(s, sutun_meta[[s]]),
                      character(1))

  satirlar <- c(
    paste0("| ", paste(basliklar, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(basliklar)), collapse = "|"), "|")
  )

  kirpilan_hucre <- 0L
  for (i in seq_len(nrow(gorunur))) {
    hucreler <- character(ncol(gorunur))
    for (j in seq_along(gorunur)) {
      sonuc <- .pk_compose_cell(gorunur[[j]][i], sutun_meta[[names(gorunur)[j]]])
      hucreler[j] <- sonuc$text
      if (isTRUE(sonuc$truncated)) kirpilan_hucre <- kirpilan_hucre + 1L
    }
    satirlar <- c(satirlar, paste0("| ", paste(hucreler, collapse = " | "), " |"))
  }

  notlar <- character(0)
  if (nrow(data) > max_rows) {
    notlar <- c(notlar, sprintf("%s satırın ilk %s satırı gösteriliyor",
                                pk_fmt_number(nrow(data), 0L), pk_fmt_number(max_rows, 0L)))
  }
  if (sutun_kirp) {
    notlar <- c(notlar, sprintf("%s sütunun ilk %s sütunu gösteriliyor",
                                pk_fmt_number(ncol(data), 0L), pk_fmt_number(max_cols, 0L)))
  }
  # Hücre kırpması da AÇIKÇA bildirilir: 60. karakterden sonra ayrışan iki
  # proje adı aksi hâlde ayırt edilemez görünürdü.
  if (kirpilan_hucre > 0L) {
    notlar <- c(notlar, sprintf("%s hücre uzunluk nedeniyle kısaltıldı; tam değerler ek dosyadadır",
                                pk_fmt_number(kirpilan_hucre, 0L)))
  }

  if (length(notlar)) {
    satirlar <- c(satirlar, sprintf("\n_(%s)_", paste(notlar, collapse = "; ")))
  }

  paste(satirlar, collapse = "\n")
}

#' Ek (attachment) kartının kullanıcıya görünen metni
pk_compose_attachment_card <- function(artifact) {
  if (!is.list(artifact)) return(NULL)

  if (identical(artifact$status, "refused")) {
    return(paste0("\n\n\U000026A0\U0000FE0F **Dışa aktarım yapılmadı:** ",
                  as.character(artifact$message %||% "")[1]))
  }
  if (identical(artifact$status, "failed")) {
    return(paste0("\n\n\U000026A0\U0000FE0F **Ek üretilemedi:** ",
                  as.character(artifact$message %||% "Dosya oluşturulamadı.")[1]))
  }
  # Açıkça Excel/CSV istenen ama sıfır satır dönen bir sorgu SESSİZ kalmamalı.
  if (identical(artifact$status, "empty")) {
    return(paste0("\n\n\U000026A0\U0000FE0F **Dışa aktarılacak satır yok:** ",
                  as.character(artifact$message %||%
                                 "Filtre sonrası aktarılacak kayıt bulunamadı.")[1]))
  }
  if (!length(artifact$files %||% list())) return(NULL)

  satirlar <- character(0)
  for (dosya in artifact$files) {
    boyut <- suppressWarnings(file.info(dosya$path)$size[1])
    boyut_metni <- if (is.na(boyut)) "" else sprintf(" · %s KB",
                                                     pk_fmt_number(boyut / 1024, 0L))
    etiket <- sprintf("%s (%s satır × %s sütun%s)", dosya$name,
                      pk_fmt_number(dosya$rows, 0L), pk_fmt_number(dosya$cols, 0L),
                      boyut_metni)
    satirlar <- c(satirlar, if (is.null(dosya$url) || !nzchar(dosya$url)) {
      sprintf("- %s", etiket)
    } else {
      sprintf("- [%s](%s)", etiket, dosya$url)
    })
  }

  basi <- if (identical(artifact$status, "csv_fallback")) {
    sprintf("\n\n**\U0001F4CE Ek (CSV):** %s\n", as.character(artifact$message %||% "")[1])
  } else {
    "\n\n**\U0001F4CE Ek (Excel):**\n"
  }

  paste0(basi, paste(satirlar, collapse = "\n"))
}

#' Olgulardan deterministik kısa özet
#'
#' `block` kipinde (§5.11) model düzyazısı reddedildiğinde kullanıcıya
#' gösterilecek metin budur: yalnızca R'nin hesapladığı değerler. Her ÖLÇÜ için
#' önce bir birincil olgu seçilir; aksi hâlde ilk ölçünün istatistikleri
#' bütçenin tamamını yiyor ve sonraki ölçüler sessizce kayboluyordu.
pk_compose_facts_summary <- function(facts, limit = 12L) {
  kullanilabilir <- Filter(function(o) is.list(o) && !is.null(o$value), facts %||% list())
  if (!length(kullanilabilir)) return("")

  limit <- max(1L, suppressWarnings(as.integer(limit)))
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

  satirlar <- vapply(secilen, function(o) {
    sprintf("- %s (%s): %s", as.character(o$label %||% o$column)[1],
            as.character(o$aggregation)[1], as.character(o$display)[1])
  }, character(1))

  atlanan <- length(kullanilabilir) - length(secilen)
  if (atlanan > 0L) {
    satirlar <- c(satirlar, sprintf(
      "- _(%s hesaplanan değer daha var; tamamı ek dosyanın `Ozet` sayfasındadır.)_",
      pk_fmt_number(atlanan, 0L)
    ))
  }

  paste(c("**Hesaplanan değerler**", satirlar), collapse = "\n")
}

# HTML öznitelik kaçışı: metadata'daki tırnak/açılı ayraç üretilen işaretlemeyi
# BOZAMAZ.
.pk_compose_attr <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (length(txt) != 1L || is.na(txt)) return("")
  txt <- gsub("&", "&amp;", txt, fixed = TRUE)
  txt <- gsub("<", "&lt;", txt, fixed = TRUE)
  txt <- gsub(">", "&gt;", txt, fixed = TRUE)
  txt <- gsub("\"", "&quot;", txt, fixed = TRUE)
  gsub("'", "&#39;", txt, fixed = TRUE)
}

#' Sorgu metadata'sındaki ek dosya/bağlantı satırları (R'ye AİTTİR)
#'
#' Eskiden bu iki bağlantı sistem isteminde modele "şu HTML'i cevabının en
#' altına ekle" diye veriliyordu; model bağlantıyı atlayabilir, değiştirebilir
#' veya uydurabilirdi. Bağlantılar artık deterministik olarak burada üretilir;
#' `info_url` yalnızca `http`/`https` şemasıyla kabul edilir (`javascript:` gibi
#' bir şema hiç yazılmaz).
pk_compose_reference_links <- function(query) {
  if (!is.list(query)) return("")
  parcalar <- character(0)

  dosya <- as.character(query$info_file %||% "")[1]
  if (!is.na(dosya) && nzchar(dosya)) {
    yol <- .pk_compose_attr(gsub("\\\\", "/", dosya))
    parcalar <- c(parcalar, paste0(
      "\U0001F449 <span class=\"analysis-file-link\" data-filepath=\"", yol,
      "\" style=\"color:#007bff; cursor:pointer; text-decoration:underline; ",
      "font-weight:bold;\">İlgili Dosyayı Görüntüle</span>"
    ))
  }

  adres <- as.character(query$info_url %||% "")[1]
  if (!is.na(adres) && nzchar(adres) && grepl("^https?://", trimws(adres), perl = TRUE)) {
    parcalar <- c(parcalar, paste0(
      "\U0001F310 <a href=\"", .pk_compose_attr(trimws(adres)),
      "\" target=\"_blank\" rel=\"noopener noreferrer\"><b>Daha Fazla Bilgi</b></a>"
    ))
  }

  if (!length(parcalar)) return("")
  paste0("\n\n", paste(parcalar, collapse = "<br>"))
}

#' R'ye ait yanıt bloğunu kur (tablo + ek + kip notu)
#'
#' Model düzyazısının ARDINA eklenir; baloncuğun tablo duvarına dönmesini
#' engelleyen şey sıralı eşik kurallarıdır.
pk_compose_block <- function(decision, data, artifact = NULL, meta = list(),
                             query_meta = NULL) {
  parcalar <- character(0)

  ic_satir <- .pk_compose_cfg("MERGEN_PK_INLINE_MAX_ROWS", query_meta, 15L)
  ic_sutun <- .pk_compose_cfg("MERGEN_PK_INLINE_MAX_COLS", query_meta, 8L)

  if (identical(decision$mode, "inline_table")) {
    tablo <- pk_compose_markdown_table(data, ic_satir, ic_sutun, meta)
    if (!is.null(tablo)) parcalar <- c(parcalar, paste0("\n\n**Sonuç tablosu**\n\n", tablo))
  } else {
    onizleme <- pk_compose_markdown_table(data, decision$preview_rows, ic_sutun, meta)
    if (!is.null(onizleme)) {
      parcalar <- c(parcalar, paste0("\n\n**Önizleme**\n\n", onizleme))
    }
    kart <- pk_compose_attachment_card(artifact)
    if (!is.null(kart)) parcalar <- c(parcalar, kart)

    # `dt` kipi karar katmanında vardır ama etkileşimli tablo seam'i (çıktı
    # bağlama + kayıtlı söyleşide yeniden bağlama) henüz yoktur. Kullanıcıya
    # var olmayan bir özellik ima etmemek için durum AÇIKÇA yazılır; veriye
    # erişim ek dosya üzerinden korunur.
    if (identical(decision$mode, "dt")) {
      parcalar <- c(parcalar, paste0(
        "\n\n_(Etkileşimli tablo görünümü henüz etkin değil; yukarıdaki önizleme ",
        "ile birlikte tam sonuç ek dosyadadır.)_"
      ))
    }
  }

  if (!length(parcalar)) return("")
  paste(parcalar, collapse = "")
}
