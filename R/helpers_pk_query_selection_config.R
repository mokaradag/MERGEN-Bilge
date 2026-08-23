# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_config.R
# Açıklama: Faz 5 (§5.2 / §9) — iki geçişli sorgu seçiminin KAPALI BAŞARISIZ
#           yapılandırma çözümlemesi.
#
# `pk_config_resolve()` geçersiz bir kaynağı SESSİZCE atlar ve varsayılana
# düşer. Seçim eşikleri için bu kabul edilemez: `MERGEN_PK_SELECT_RECALL_N=1`
# yazan bir operatör, marj kapısını devre dışı bıraktığını sanmadan varsayılan
# 5 ile çalışmaya devam ederdi.
#
# İKİ ÖLÇÜLMÜŞ DÜZELTME (Faz 5 incelemesi):
#   * `pk_config_probe()` TÜM katmanlardaki geçersiz değerleri raporlar; daha
#     YÜKSEK öncelikli geçerli bir değerin GÖLGELEDİĞİ eski/geçersiz bir
#     `options()` girdisi bu yüzden seçimi tamamen kapatıyordu. Artık yalnızca
#     GERÇEKTEN KAZANAN kaynak denetlenir.
#   * "Yok" ile "var ama şekli bozuk" ayrılmıyordu: vektör değerli bir seçenek
#     (`c(90, 95)`), açık `NA` ya da boş dize kaynağı YOKMUŞ gibi ele alınıyor,
#     çözümleme sessizce daha düşük öncelikli bir değere düşüyordu. Şekli bozuk
#     bir kaynak artık KAZANIR ve GEÇERSİZDİR.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

.PK_SELECT_CONFIG_KEYS <- c(
  "MERGEN_PK_SELECT_TIMEOUT_SEC",
  "MERGEN_PK_SELECT_RECALL_N",
  "MERGEN_PK_SELECT_MIN_CONFIDENCE",
  "MERGEN_PK_SELECT_MIN_MARGIN",
  "MERGEN_PK_SELECT_DISAGREE_PENALTY",
  "MERGEN_PK_SELECT_DESC_CHARS",
  "MERGEN_PK_SELECT_SAMPLE_CHARS",
  "MERGEN_PK_SELECT_SAMPLE_N",
  "MERGEN_PK_SELECT_HISTORY_TURNS",
  "MERGEN_PK_SELECT_NAME_CHARS",
  "MERGEN_PK_SELECT_KEYWORD_CHARS",
  "MERGEN_PK_SELECT_HISTORY_CHARS",
  "MERGEN_PK_SELECT_PASS_B_CHARS",
  "MERGEN_PK_SELECT_PASS_A_CHARS"
)

# Yapılandırma alan adı -> anahtar eşlemesi. Tek kaynak: hem çözümleme hem de
# dışarıdan verilen nesnenin yeniden doğrulanması bunu kullanır.
.PK_SELECT_FIELD_MAP <- c(
  timeout_sec       = "MERGEN_PK_SELECT_TIMEOUT_SEC",
  recall_n          = "MERGEN_PK_SELECT_RECALL_N",
  min_confidence    = "MERGEN_PK_SELECT_MIN_CONFIDENCE",
  min_margin        = "MERGEN_PK_SELECT_MIN_MARGIN",
  disagree_penalty  = "MERGEN_PK_SELECT_DISAGREE_PENALTY",
  desc_chars        = "MERGEN_PK_SELECT_DESC_CHARS",
  sample_chars      = "MERGEN_PK_SELECT_SAMPLE_CHARS",
  sample_n          = "MERGEN_PK_SELECT_SAMPLE_N",
  history_turns     = "MERGEN_PK_SELECT_HISTORY_TURNS",
  name_chars        = "MERGEN_PK_SELECT_NAME_CHARS",
  keyword_chars     = "MERGEN_PK_SELECT_KEYWORD_CHARS",
  history_chars     = "MERGEN_PK_SELECT_HISTORY_CHARS",
  pass_b_chars      = "MERGEN_PK_SELECT_PASS_B_CHARS",
  pass_a_chars      = "MERGEN_PK_SELECT_PASS_A_CHARS"
)

# Karar aşamasında sorgu metadata'sının GEÇERSİZ KILABİLECEĞİ alanlar.
# Getirim/Geçiş A ayarları bu listede DEĞİLDİR: hangi sorgunun seçileceği
# belli olmadan onun metadata'sı okunamaz.
.PK_SELECT_DECISION_FIELDS <- c("min_confidence", "min_margin", "disagree_penalty")

#' Tek bir kaynağın ham değerini oku
#'
#' @return `present` (kaynak var mı) ve `raw` alanlı liste.
.pk_select_raw_source <- function(key, source, query_meta) {
  if (identical(source, "query_meta")) {
    if (!is.list(query_meta)) return(list(present = FALSE, raw = NULL))
    ad <- pk_config_meta_key(key)
    if (!(ad %in% names(query_meta))) return(list(present = FALSE, raw = NULL))
    return(list(present = TRUE, raw = query_meta[[ad]]))
  }

  if (identical(source, "environment")) {
    ham <- Sys.getenv(key, unset = NA_character_)
    # Ayarlanmamış ortam değişkeni `NA`dır; ayarlanmış boş dize ise VARDIR ve
    # geçersizdir (operatör bir şey yazmayı denemiştir).
    if (length(ham) != 1L || is.na(ham)) return(list(present = FALSE, raw = NULL))
    return(list(present = TRUE, raw = ham))
  }

  ham <- getOption(pk_config_option_key(key), default = NULL)
  if (is.null(ham)) return(list(present = FALSE, raw = NULL))
  list(present = TRUE, raw = ham)
}

#' Öncelik sırasına DUYARLI kapalı-başarısız sonda
#'
#' Öncelik: `query_meta` -> `environment` -> `options` -> varsayılan (§9).
#' İLK VAR OLAN kaynak kazanır; kazanan geçersizse yapılandırma hatalıdır.
#' Alt katmanlardaki geçersiz değerler gölgelendiği için raporlanmaz.
pk_select_probe_key <- function(key, query_meta = NULL) {
  spec <- pk_config_spec[[key]]
  if (is.null(spec)) {
    return(list(value = NULL, invalid_source = "spec",
                error = sprintf("%s tanımlı bir yapılandırma anahtarı değil.", key)))
  }

  for (kaynak in c("query_meta", "environment", "options")) {
    sonda <- .pk_select_raw_source(key, kaynak, query_meta)
    if (!isTRUE(sonda$present)) next

    ham <- sonda$raw
    # Şekli bozuk (vektör / NA / boş) bir kaynak YOK sayılmaz: operatör bir
    # değer BEYAN ETMİŞTİR ve o beyan okunamıyordur.
    if (length(ham) != 1L || is.na(ham[1]) ||
        (is.character(ham) && !nzchar(trimws(ham[1])))) {
      return(list(value = NULL, invalid_source = kaynak, error = sprintf(
        "%s geçersiz bir değer taşıyor (kaynak: %s); sessizce varsayılana düşülmedi.",
        key, kaynak
      )))
    }

    deger <- .pk_config_coerce(ham, spec)
    if (is.null(deger)) {
      return(list(value = NULL, invalid_source = kaynak, error = sprintf(
        "%s geçersiz bir değer taşıyor (kaynak: %s); sessizce varsayılana düşülmedi.",
        key, kaynak
      )))
    }

    return(list(value = deger, invalid_source = NA_character_, error = NA_character_))
  }

  list(value = spec$default, invalid_source = NA_character_, error = NA_character_)
}

#' Seçim yapılandırmasını KAPALI BAŞARISIZ biçimde çöz (§5.2 / §9)
#'
#' @param query_meta Karar aşamasında seçilen sorgunun metadata'sı. Verildiğinde
#'   YALNIZCA `.PK_SELECT_DECISION_FIELDS` alanları o metadata ile yeniden
#'   çözülür.
#' @return `valid`, `errors` ve çözümlenmiş alanları taşıyan liste.
pk_select_config <- function(query_meta = NULL) {
  ham <- list()
  hatalar <- character(0)

  for (alan in names(.PK_SELECT_FIELD_MAP)) {
    anahtar <- .PK_SELECT_FIELD_MAP[[alan]]
    meta <- if (alan %in% .PK_SELECT_DECISION_FIELDS) query_meta else NULL

    sonda <- tryCatch(
      pk_select_probe_key(anahtar, query_meta = meta),
      error = function(e) NULL
    )

    if (is.null(sonda)) {
      hatalar <- c(hatalar, sprintf("%s çözümlenemedi.", anahtar))
      next
    }
    if (!is.na(sonda$invalid_source %||% NA_character_)) {
      hatalar <- c(hatalar, sonda$error)
    }

    ham[[alan]] <- sonda$value
  }

  cfg <- pk_select_normalize_config(ham)
  cfg$errors <- unique(c(hatalar, cfg$errors))
  cfg$valid <- !length(cfg$errors)
  cfg
}

#' Dışarıdan verilen seçim yapılandırmasını NORMALLEŞTİR ve DOĞRULA
#'
#' Çağıranın `valid = TRUE` iddiasına GÜVENİLMEZ (Faz 4 incelemesinin
#' `thresholds=` bulgusu). Alan varlığı, tipi, tam sayılığı ve aralığı burada
#' YENİDEN denetlenir; `pk_config_spec` sınırları tek kaynaktır.
pk_select_normalize_config <- function(x) {
  hatalar <- character(0)
  cikti <- list()

  for (alan in names(.PK_SELECT_FIELD_MAP)) {
    anahtar <- .PK_SELECT_FIELD_MAP[[alan]]
    spec <- pk_config_spec[[anahtar]]
    deger <- if (is.list(x) && !is.null(x[[alan]])) x[[alan]] else NULL

    # Tam sayı denetimi COERCE'DAN ÖNCE yapılır: `as.integer(3e9)` `NA` verir,
    # `NA != 3e9` de `NA`dır ve `if (NA)` KAPALI BAŞARISIZ OLMAK YERİNE HATA
    # FIRLATIR. Bu fonksiyon tam olarak dışarıdan gelen yapılandırmanın
    # kapalı-başarısız sınırıdır; hata fırlatamaz.
    if (is.null(deger) || is.logical(deger) || !is.numeric(deger) ||
        length(deger) != 1L || is.na(deger[1]) || !is.finite(deger[1]) ||
        abs(as.numeric(deger[1])) > .Machine$integer.max ||
        as.numeric(deger[1]) != round(as.numeric(deger[1]))) {
      hatalar <- c(hatalar, sprintf("%s tek bir tam sayı olmalıdır.", anahtar))
      next
    }

    deger <- as.integer(deger[1])

    if (!is.null(spec$min) && deger < as.integer(spec$min)) {
      hatalar <- c(hatalar, sprintf(
        "%s en az %d olmalıdır (verilen: %d).", anahtar, as.integer(spec$min), deger
      ))
      next
    }
    if (!is.null(spec$max) && deger > as.integer(spec$max)) {
      hatalar <- c(hatalar, sprintf(
        "%s en fazla %d olmalıdır (verilen: %d).", anahtar, as.integer(spec$max), deger
      ))
      next
    }

    cikti[[alan]] <- deger
  }

  # İlişki denetimi: HER İKİ güvenlik kapısı da sıfırlanırsa tamamen belirsiz
  # bir beraberlik (seçilen 0, ikinci aday 0) `auto` olur ve kapıların
  # kapalı-başarısız amacı ortadan kalkar. `DISAGREE_PENALTY = 0`ın aksine
  # bu kombinasyon hiçbir yerde bilinçli bir "kapatma anahtarı" olarak
  # belgelenmemiştir.
  #
  # NOT: `min_confidence + min_margin > 100` DENETİMİ YOKTUR. İki kapı FARKLI
  # nicelikleri sınırlar (mutlak güven ve ikinci adayla fark); ör. 90 + 20,
  # güven 90 / ikinci aday 0 ile SAĞLANABİLİR. Toplama bakan eski denetim
  # tamamen uygulanabilir yapılandırmaları geçersiz sayıyordu.
  if (!is.null(cikti$min_confidence) && !is.null(cikti$min_margin) &&
      cikti$min_confidence <= 0L && cikti$min_margin <= 0L) {
    hatalar <- c(hatalar, paste0(
      "MERGEN_PK_SELECT_MIN_CONFIDENCE ve MERGEN_PK_SELECT_MIN_MARGIN birlikte ",
      "sıfır olamaz; bu yapılandırmada tamamen belirsiz bir beraberlik bile ",
      "otomatik çalıştırılabilirdi. En az biri pozitif olmalıdır."
    ))
  }

  cikti$errors <- hatalar
  cikti$valid <- !length(hatalar)
  cikti
}

#' Dışarıdan verilen `cfg` nesnesini YENİDEN doğrula
#'
#' `pk_select_run(cfg = ...)` enjeksiyonu testler için vardır; ama üretimde bir
#' çağıran `valid = TRUE` iddiasıyla aralık dışı eşik geçirebilirdi. Normalleştirme
#' burada TEKRAR uygulanır; normalleştirilmiş alanlar dışındaki alanlar korunur.
pk_select_revalidate_config <- function(cfg) {
  if (is.null(cfg)) return(pk_select_config())
  if (!is.list(cfg)) {
    return(list(valid = FALSE, errors = "Seçim yapılandırması bir liste olmalıdır."))
  }
  # NORMALLEŞTİRİLMEYEN ALANLAR KORUNUR. `pk_select_normalize_config()` çıktıyı
  # sıfırdan kurar ve yalnızca `.PK_SELECT_FIELD_MAP` anahtarları + `errors` /
  # `valid` yazar; sonucu doğrudan döndürmek enjekte edilen `cfg` üzerindeki
  # diğer alanları SİLİYORDU ve sonradan okuyan çağıran `NULL` görüyordu.
  normal <- pk_select_normalize_config(cfg)
  for (ad in names(normal)) cfg[[ad]] <- normal[[ad]]
  cfg
}

#' Karar eşiklerini SEÇİLEN SORGUNUN metadata'sıyla yeniden çöz (§9)
#'
#' §9 önceliği metadata -> ortam -> options -> varsayılandır, ama seçim
#' yapılandırması çalışma zamanında HİÇ metadata görmeden çözülüyordu. Bir
#' sorgu `meta$select_min_confidence = 90` gibi DAHA KATI bir politika
#' beyan ettiğinde bile küresel 50/15 ile yargılanıyordu.
#'
#' Yalnızca karar aşaması alanları yeniden çözülür; getirim/istem bütçeleri
#' aday seçilmeden önce kullanıldığı için değişmez.
pk_select_config_for_query <- function(cfg, query_meta) {
  if (!is.list(cfg) || !isTRUE(cfg$valid)) return(cfg)
  if (!is.list(query_meta) || !length(query_meta)) return(cfg)

  ilgili <- vapply(
    .PK_SELECT_DECISION_FIELDS,
    function(alan) pk_config_meta_key(.PK_SELECT_FIELD_MAP[[alan]]) %in% names(query_meta),
    logical(1)
  )
  if (!any(ilgili)) return(cfg)

  yeni <- pk_select_config(query_meta = query_meta)
  if (!isTRUE(yeni$valid)) return(yeni)

  # YALNIZCA METADATA'NIN GERÇEKTEN GEÇERSİZ KILDIĞI ALANLAR KOPYALANIR.
  #
  # `pk_select_config(query_meta = ...)` üç karar alanını da ortam/seçenek/
  # varsayılan basamağından YENİDEN çözer. Eski döngü üçünü birden yazdığı için,
  # sorgu yalnızca `select_min_confidence`'ı geçersiz kıldığında çağıranın
  # İSTEK KAPSAMLI `min_margin` değeri de sessizce süreç varsayılanıyla
  # değiştiriliyordu; bu, istek için sıkılaştırılmış bir seçim kapısını
  # gevşetip AUTO/red davranışını değiştirebilirdi.
  for (i in seq_along(.PK_SELECT_DECISION_FIELDS)) {
    if (!isTRUE(ilgili[[i]])) next
    alan <- .PK_SELECT_DECISION_FIELDS[[i]]
    cfg[[alan]] <- yeni[[alan]]
  }

  # BİRLEŞTİRİLMİŞ NESNE YENİDEN DOĞRULANIR.
  #
  # İlişki değişmezi (`min_confidence` ile `min_margin` BİRLİKTE sıfır olamaz)
  # `ham` ve `yeni` üzerinde AYRI AYRI denetleniyor, birleşmiş nesnede HİÇ
  # denetlenmiyordu: çağıran `min_confidence = 0` + `min_margin = 15` verip
  # sorgu yalnızca `select_min_margin = 0` beyan ettiğinde sonuç 0/0 oluyor ve
  # tamamen belirsiz bir beraberlik bile OTOMATİK çalıştırılabiliyordu.
  # Geçersiz birleşim metadata geçersiz kılmasını DÜŞÜRÜR; çağıranın kendi
  # doğrulanmış yapılandırması korunur.
  # Metadata geçersizse kullanılmak üzere özgün yapılandırmayı koru.
  original_cfg <- cfg

  birlesik <- pk_select_normalize_config(cfg)
  if (!isTRUE(birlesik$valid)) {
    cat(sprintf(
      "[PK_SELECT] Metadata gecersiz kilmasi birlesik yapilandirmayi bozdu, yok sayildi: %s\n",
      paste(birlesik$errors, collapse = "; ")
    ))
    return(original_cfg)
  }
  cfg
}
