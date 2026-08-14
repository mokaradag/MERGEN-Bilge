# ==============================================================================
# Dosya Yolu: R/helpers_pk_prompt_budget.R
# Açıklama: Proje ve Kaynak Analizi v2 istem (prompt) bütçe muhasebecisi
#           (D7 / D8).
#
#             D7 — `MAX_ANALYSIS_PROMPT_CHARS` YALNIZCA `summary_text`
#                  uzunluğuna bakıyordu. Gerçek yük ise modülde SONRADAN
#                  kuruluyordu: 500 satıra kadar örnek satır, JSON olarak
#                  anahtar adları her satırda tekrarlanarak. 500 satır x 25
#                  sütun kolayca yüzlerce KB eder ve bütçe kontrolünün TAMAMEN
#                  DIŞINDA kalırdı.
#             D8 — Bütçe aşımındaki özyineleme yalnızca `max_preview_rows`,
#                  `max_total_chars` ve `pre_aggregated_columns` aktarıyor;
#                  `mode`, `rls_total_rows` ve `user_filter_applied` düşüyordu.
#                  Sonuç: "FİLTRELEME UYARISI" bloğu TAM DA verinin büyük
#                  olduğu, yani yanlış paydanın en çok zarar verdiği durumda
#                  kayboluyordu.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
#           Yalnızca MERGEN_PK_ENGINE=v2 altında çağrılır.
# ==============================================================================

#' Çözülmüş toplam yük karakter bütçesi
#'
#' Dönüş HER ZAMAN pozitiftir. Bu, "yapılandırma ayarlanmamış/geçersiz" ile
#' "kalan bütçe tükendi" ayrımının tek yerde çözülmesini sağlar: sıfır bir
#' TOPLAM bütçe anlamsızdır ve varsayılana düşer, buna karşılık
#' `pk_build_analysis_payload()` içinde ifşa payı düşüldükten sonra HESAPLANAN
#' sıfır gerçekten tükenmiş bir kalan bütçedir ve öyle ele alınır.
pk_prompt_char_budget <- function(query_meta = NULL) {
  ham <- if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) {
    120000L
  } else {
    tryCatch(
      pk_config_resolve("MERGEN_PK_PROMPT_CHAR_BUDGET", query_meta = query_meta),
      error = function(e) 120000L
    )
  }
  ham <- suppressWarnings(as.integer(ham))
  if (is.na(ham) || ham <= 0L) 120000L else ham
}

#' Örnek satırları JSON'a çevir
pk_prompt_preview_json <- function(preview_data) {
  if (is.null(preview_data) || !is.data.frame(preview_data) || nrow(preview_data) == 0L) {
    return("{}")
  }

  guvenli <- if (exists("normalize_pk_dataframe_utf8", mode = "function", inherits = TRUE)) {
    normalize_pk_dataframe_utf8(preview_data)
  } else {
    preview_data
  }

  as.character(jsonlite::toJSON(guvenli, auto_unbox = TRUE, pretty = FALSE, na = "null"))
}

#' TÜM yükü bütçeye sığdır (D7)
#'
#' Özet metni korunur (uyarı blokları oradadır); kırpılan şey örnek satır
#' sayısıdır. Özet tek başına bütçeyi aşıyorsa örnek satır hiç gönderilmez ve
#' bu durum açıkça raporlanır.
#'
#' @param assemble Özet + JSON'dan nihai yük metnini kuran fonksiyon
#'   `function(summary_text, preview_json, preview_rows)`.
#' @return list(payload, preview_rows, preview_json, trimmed, budget, chars, over_budget)
pk_prompt_fit_payload <- function(summary_text, preview_data, assemble, budget = NULL) {
  # AÇIK SIFIR "TÜKENMİŞ" DEMEKTİR, "AYARLANMAMIŞ" DEĞİL.
  #
  # `pk_build_analysis_payload()`, ifşa bloğu ve not payı toplam bütçeyi
  # tükettiğinde `fit_butcesi`'ni BİLİNÇLİ olarak 0'a kenetler. Eskiden bu
  # değer buradaki `budget <= 0L` dalına düşüyor ve 120.000 karakterlik TAZE
  # bir izin kazanıyordu; yani küçük bir sorgu bütçesi veya büyük bir ifşa
  # bloğu, tüm istek bütçesi muhasebesini SESSİZCE devre dışı bırakıyordu.
  #
  # Ayrım korunur: bütçe verilmediyse (NULL) yapılandırma/varsayılan geçerlidir;
  # açıkça verilen 0 ya da negatif değer TÜKENMİŞ bütçedir ve örnek satır
  # gönderilmemesine yol açar.
  acik_butce <- !is.null(budget)
  if (!acik_butce) budget <- pk_prompt_char_budget()
  budget <- suppressWarnings(as.integer(budget))
  if (is.na(budget)) {
    budget <- 120000L
  } else if (budget < 0L) {
    budget <- 0L
  } else if (budget == 0L && !acik_butce) {
    budget <- 120000L
  }

  summary_text <- as.character(summary_text %||% "")[1]
  if (is.na(summary_text)) summary_text <- ""

  satir_sayisi <- if (is.data.frame(preview_data)) nrow(preview_data) else 0L
  kirpildi <- FALSE

  repeat {
    parca <- if (satir_sayisi > 0L) {
      utils::head(preview_data, satir_sayisi)
    } else {
      NULL
    }
    json <- pk_prompt_preview_json(parca)
    yuk <- assemble(summary_text, json, satir_sayisi)
    uzunluk <- nchar(yuk, type = "chars")

    if (uzunluk <= budget || satir_sayisi == 0L) {
      return(list(
        payload = yuk,
        preview_rows = satir_sayisi,
        preview_json = json,
        trimmed = kirpildi,
        budget = budget,
        chars = uzunluk,
        over_budget = uzunluk > budget
      ))
    }

    kirpildi <- TRUE
    # Yarıya indirerek daral; 1 satırdan sonra tamamen düşür.
    satir_sayisi <- if (satir_sayisi > 1L) as.integer(floor(satir_sayisi / 2)) else 0L
  }
}

#' Model yükünü kur (v1 ve v2 için tek giriş noktası)
#'
#' v1 davranışı BİREBİR korunur: örnek satırlar kırpılmadan JSON'a çevrilir ve
#' bütçe muhasebesi uygulanmaz. v2'de ise tüm yük `pk_prompt_fit_payload()`
#' üzerinden bütçeye sığdırılır ve politika ifşaları eklenir.
pk_build_analysis_payload <- function(stat_summary, query, engine_is_v2 = FALSE, policy = NULL) {
  stat_summary <- if (is.list(stat_summary)) stat_summary else list()

  kur <- function(summary_text, preview_json, preview_rows) {
    paste0(
      summary_text,
      "\n\n--- ORNEK SATIRLAR (JSON) ---\n",
      preview_json,
      "\n\n(Not: Yukaridaki istatistikler ", stat_summary$row_count, " satirdan olusturulmustur)"
    )
  }

  if (!isTRUE(engine_is_v2)) {
    # v1 KARAR anlamı korunur (politika ifşası, olgu/paket makinesi YOK), ancak
    # İSTEK BOYUTU sınırı burada da uygulanır.
    #
    # `MERGEN_PK_ENGINE` varsayılanı hâlâ `v1`'dir. Bu dal eskiden örnek
    # satırların TAMAMINI serileştirip bütçeye hiç bakmadan dönüyordu; yani
    # geniş/uzun bir izinli sonuç, varsayılan dağıtımda yerel modelin bağlam
    # sınırını taşırabiliyordu. İstem güvenliğinin v2'ye geçmeye bağlı olması
    # doğru değildir: bütçe modelin GÖRDÜĞÜ nihai yük için geçerlidir.
    #
    # Bütçenin altındaki yükte çıktı BİREBİR aynıdır (aynı `kur()`, aynı JSON
    # seçenekleri); yalnızca bütçe aşıldığında örnek satır sayısı kırpılır ve
    # kırpma açıkça ifşa edilir.
    fit_v1 <- pk_prompt_fit_payload(
      stat_summary$summary_text,
      stat_summary$preview_data,
      kur,
      budget = pk_prompt_char_budget(if (is.list(query)) query$meta else NULL)
    )

    data_str_v1 <- fit_v1$payload
    istenen_v1 <- if (is.null(stat_summary$preview_data)) 0L else nrow(stat_summary$preview_data)
    not_v1 <- pk_prompt_budget_note(fit_v1, istenen_v1)
    if (!is.null(not_v1)) {
      cat(sprintf(
        "[PK_ANALIZ] Istem butcesi (v1): %d/%d karakter, ornek satir: %d\n",
        fit_v1$chars, fit_v1$budget, fit_v1$preview_rows
      ))
      data_str_v1 <- paste0(data_str_v1, not_v1)
    }

    return(data_str_v1)
  }

  # İFŞALAR SIĞDIRMADAN ÖNCE HESAPLANIR VE BÜTÇEDEN DÜŞÜLÜR.
  #
  # Eskiden yük bütçeye sığdırılıyor, ARDINDAN bütçe notu ve politika ifşa
  # bloğu sonuna EKLENİYORDU; yani nihai model yükü bütçeyi aşabiliyordu.
  # Bütçe, modelin GÖRDÜĞÜ nihai yükün tamamı için geçerlidir.
  ifsa <- if (is.list(policy) &&
              exists("pk_filter_policy_disclosure_block", mode = "function", inherits = TRUE)) {
    pk_filter_policy_disclosure_block(
      policy,
      dropped = policy$dropped %||% list(),
      noop_columns = policy$noop_columns %||% character(0)
    )
  } else {
    NULL
  }

  ifsa_metni <- if (is.null(ifsa)) "" else paste0("\n\n", ifsa)

  # Bütçe notunun kendisi de yüke girer; en uzun biçimi için pay ayrılır.
  not_payi <- 220L
  toplam_butce <- pk_prompt_char_budget(if (is.list(query)) query$meta else NULL)
  fit_butcesi <- max(0L, as.integer(toplam_butce) -
                       nchar(ifsa_metni, type = "chars") - not_payi)

  fit <- pk_prompt_fit_payload(
    stat_summary$summary_text,
    stat_summary$preview_data,
    kur,
    budget = fit_butcesi
  )

  data_str <- fit$payload

  istenen <- if (is.null(stat_summary$preview_data)) 0L else nrow(stat_summary$preview_data)
  not <- pk_prompt_budget_note(fit, istenen)
  if (!is.null(not)) {
    cat(sprintf(
      "[PK_ANALIZ] Istem butcesi: %d/%d karakter, ornek satir: %d\n",
      fit$chars, fit$budget, fit$preview_rows
    ))
    data_str <- paste0(data_str, not)
  }

  if (nzchar(ifsa_metni)) data_str <- paste0(data_str, ifsa_metni)

  data_str
}

#' Bütçe kırpmasını kullanıcı/model tarafına ifşa eden not
pk_prompt_budget_note <- function(fit, requested_rows) {
  if (!isTRUE(fit$trimmed) && !isTRUE(fit$over_budget)) return(NULL)

  if (isTRUE(fit$over_budget)) {
    return(sprintf(
      "\n\n\U000026A0\U0000FE0F İSTEM BÜTÇESİ AŞILDI: İstatistiksel özet tek başına %d karakter bütçesini aşıyor; örnek satır GÖNDERİLMEDİ.",
      fit$budget
    ))
  }

  sprintf(
    "\n\n\U000026A0\U0000FE0F İSTEM BÜTÇESİ: Örnek satır sayısı %d karakterlik bütçeye sığması için %d satırdan %d satıra düşürüldü.",
    fit$budget, as.integer(requested_rows), as.integer(fit$preview_rows)
  )
}
