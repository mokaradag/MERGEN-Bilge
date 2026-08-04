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

# Kullanıcının açıkça liste/döküm/rapor/excel istediği ifadeler.
PK_COMPOSE_EXPORT_HINTS <- c(
  "liste", "listele", "listeyi", "dokum", "döküm", "rapor", "excel",
  "xlsx", "disa aktar", "dışa aktar", "indir", "tablo halinde", "csv"
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

#' Kullanıcı açıkça liste/dışa aktarım istedi mi?
pk_compose_wants_export <- function(user_prompt) {
  katlanmis <- .pk_compose_fold(user_prompt)
  if (!nzchar(katlanmis)) return(FALSE)

  any(vapply(PK_COMPOSE_EXPORT_HINTS, function(ipucu) {
    grepl(.pk_compose_fold(ipucu), katlanmis, fixed = TRUE)
  }, logical(1)))
}

#' Sunum kipini belirle (SIRALI, ilk eşleşen kazanır)
#'
#' @return `list(mode = "attachment"|"inline_table"|"dt", rule=, preview_rows=)`
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

  if (isTRUE(pk_compose_wants_export(user_prompt))) {
    return(list(mode = "attachment", rule = 1L, preview_rows = onizleme))
  }
  if (rows > dt_satir || cols > dt_sutun) {
    return(list(mode = "attachment", rule = 2L, preview_rows = onizleme))
  }
  if (rows <= ic_satir && cols <= ic_sutun) {
    return(list(mode = "inline_table", rule = 3L, preview_rows = rows))
  }

  list(mode = "dt", rule = 4L, preview_rows = onizleme)
}

# Markdown yapısını bozabilecek karakterleri etkisizleştirir. Ham HTML kaçışı
# merkezî markdown güvenlik sınırında yapılır; buradaki amaç tablo yapısının
# LLM/kullanıcı kaynaklı bir hücre yüzünden kırılmamasıdır.
.pk_compose_cell <- function(x, max_chars = 60L) {
  txt <- if (inherits(x, "Date") || inherits(x, "POSIXt")) {
    as.character(x)
  } else if (is.numeric(x)) {
    pk_fmt_number(x)
  } else {
    as.character(x)
  }

  if (length(txt) != 1L || is.na(txt)) txt <- ""
  txt <- gsub("[\r\n\t]+", " ", txt)
  txt <- gsub("|", "\\|", txt, fixed = TRUE)
  txt <- trimws(gsub("[[:space:]]+", " ", txt))
  if (nchar(txt) > max_chars) txt <- paste0(substr(txt, 1L, max_chars), "…")
  txt
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
  basliklar <- vapply(names(gorunur), function(s) {
    cmeta <- sutun_meta[[s]]
    etiket <- if (is.list(cmeta) && is.character(cmeta$label) && nzchar(cmeta$label %||% "")) {
      cmeta$label
    } else {
      s
    }
    .pk_compose_cell(etiket, 40L)
  }, character(1))

  satirlar <- c(
    paste0("| ", paste(basliklar, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(basliklar)), collapse = "|"), "|")
  )

  for (i in seq_len(nrow(gorunur))) {
    hucreler <- vapply(seq_along(gorunur), function(j) .pk_compose_cell(gorunur[[j]][i]),
                       character(1))
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
#' gösterilecek metin budur: yalnızca R'nin hesapladığı değerler.
pk_compose_facts_summary <- function(facts, limit = 12L) {
  kullanilabilir <- Filter(function(o) is.list(o) && !is.null(o$value), facts %||% list())
  if (!length(kullanilabilir)) return("")

  limit <- max(1L, suppressWarnings(as.integer(limit)))
  satirlar <- vapply(utils::head(kullanilabilir, limit), function(o) {
    sprintf("- %s (%s): %s", as.character(o$label %||% o$column)[1],
            as.character(o$aggregation)[1], as.character(o$display)[1])
  }, character(1))

  paste(c("**Hesaplanan değerler**", satirlar), collapse = "\n")
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
  }

  if (!length(parcalar)) return("")
  paste(parcalar, collapse = "")
}
