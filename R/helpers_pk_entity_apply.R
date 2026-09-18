# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_apply.R
# Açıklama: Faz 4 — varlık çözümlemesinin FİLTRE HATTINA bağlanması (§5.4).
#
#           Bu dosya olmadan Faz 4 ÖLÜ KODDUR: normalleştirme, alias/kanonik
#           çözümleme, belirsizlik kapıları, netleştirme çipleri ve D11 geçmiş
#           devralması yalnızca birim testlerinde çalışır, gerçek istekler
#           LLM'in ürettiği ham yaprak değerleriyle filtrelenmeye devam eder.
#
#           BAĞLANMA NOKTASI: filtre planı doğrulandıktan SONRA,
#           `pk_filter_compile()` çağrılmadan ÖNCE. Sıra bilinçlidir —
#           bulanıklık HANGİ DEĞERİN filtreleneceğini çözer, HANGİ SATIRIN
#           değil. Derleyiciye her zaman KANONİK değerler gider.
#
#           KAPALI SÖZLÜK GERÇEK VERİDEN GELİR: sütunun `data` içindeki ayrık
#           değerleri. Uydurma değer üretilmez; çözümleyici yalnızca var olan
#           bir kanonik değeri SEÇEBİLİR.
#
#           KARAR SONUÇLARI:
#             auto        -> yaprak değeri kanonik değerle DEĞİŞTİRİLİR
#             confirm     -> analiz DURDURULUR, kullanıcıya onay sorulur
#             clarify     -> analiz DURDURULUR, çipler gösterilir
#             unresolved  -> (özne) analiz DURDURULUR
#             unfiltered  -> (ikincil daraltma) değer DÜŞÜRÜLÜR + AÇIK uyarı
#             disabled / not_applicable / invalid_input -> değer AYNEN kalır
#
#           Bu dosya v2 yürütücüsünden çağrılır; motor bayrağını KENDİSİ
#           okumaz (§10 motor sınırı: v1 davranışı bit bit korunur).
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Çözümleme hattı, v2 içinde bile kapatılabilir olmalıdır: gerçek sözlük
# davranışı VM'de ölçülene kadar operatörün geri dönüş anahtarı gerekir.
pk_entity_apply_enabled <- function(query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function")) return(FALSE)
  isTRUE(tryCatch(
    pk_config_resolve("MERGEN_PK_RESOLVE_ENABLED", query_meta = query_meta),
    error = function(e) FALSE
  ))
}

# Sütunun kapalı sözlüğü: GERÇEK ayrık değerler.
.pk_entity_apply_vocab <- function(data, column) {
  if (!is.data.frame(data) || !(column %in% names(data))) return(character(0))

  sutun <- data[[column]]
  if (is.factor(sutun)) sutun <- as.character(sutun)
  if (!is.character(sutun)) return(character(0))

  degerler <- unique(sutun[!is.na(sutun)])
  degerler[nzchar(trimws(degerler))]
}

.pk_entity_apply_meta <- function(query, column) {
  cmeta <- NULL
  if (is.list(query)) {
    meta <- if (is.list(query$meta)) query$meta else query
    if (is.list(meta$column_meta)) cmeta <- meta$column_meta[[column]]
  }

  # Metadata erişimcisi WORKER/izole bağlamda yüklü olmayabilir; o durumda
  # sütun metadatası doğrudan okunur. Sessizce "resolve" varsayılmaz —
  # bildirilmiş bir kip her zaman kazanır.
  kip <- if (exists("pk_meta_match_mode", mode = "function")) {
    pk_meta_match_mode(query, column)
  } else if (is.list(cmeta) && !is.null(cmeta$match)) {
    as.character(cmeta$match)[1]
  } else if (is.list(cmeta) && identical(cmeta$role, "id")) {
    "exact"
  } else {
    NULL
  }

  list(
    role = if (is.list(cmeta)) cmeta$role else NULL,
    match_mode = kip,
    aliases = if (is.list(cmeta)) cmeta$aliases else NULL,
    entity_kinds = if (is.list(cmeta)) cmeta$entity_kinds else NULL
  )
}

#' Filtre planındaki varlık değerlerini kanonik değerlere çöz (§5.4)
#'
#' @param data Sorgu sonucu (kapalı sözlüğün kaynağı).
#' @param filters LLM'den gelen ham filtre yaprakları.
#' @param query Seçilen sorgu (metadata taşır).
#' @param chat_history Sohbet geçmişi (D11 devralması için).
#' @param prior_context Önceki turda çözülmüş varlık bağlamı.
#'
#' @return `list(action, filters, decisions, disclosures, message_tr)`.
#'   `action`: "proceed" (derlemeye devam) veya "halt" (analiz yapılmaz).
pk_entity_resolve_filter_plan <- function(data, filters, query = NULL,
                                          chat_history = NULL,
                                          prior_context = NULL) {
  bos <- list(
    action = "proceed", filters = filters, decisions = list(),
    disclosures = character(0), message_tr = NA_character_
  )

  filters <- if (is.list(filters)) filters else list()
  if (!length(filters) || !is.data.frame(data) || !nrow(data)) return(bos)

  meta_kok <- if (is.list(query) && is.list(query$meta)) query$meta else query
  if (!pk_entity_apply_enabled(meta_kok)) return(bos)

  # AÇIK MANTIK GRUPLARININ YAPRAKLARI DA ÇÖZÜMLENİR.
  #
  # `{operator, children}` düğümünün KENDİSİNDE `column` yoktur; eski döngü bu
  # düğümü atlıyor ve çocuk yapraklarının HİÇBİRİ varlık çözümleyicisine
  # ulaşmıyordu. Takma ad, bulanık ad ve önceki varlık bağlamı bu yüzden düz
  # filtrelerde çalışıyor ama MANTIKSAL OLARAK EŞDEĞER gruplu filtrelerde
  # çalışmıyordu: geçerli bir gruplu varlık isteği "eşleşmedi" diye
  # reddedilebiliyor ve çözülen varlık takip sorusu için saklanamıyordu.
  # Yaprak konumları özyinelemeli olarak toplanır; MANTIKSAL YAPI KORUNUR
  # (yalnızca yaprakların `value` alanı yerinde güncellenir).
  yaprak_yollari <- .pk_entity_leaf_paths(filters)

  sutunlar <- vapply(yaprak_yollari, function(yol) {
    y <- .pk_entity_pluck(filters, yol)
    if (!is.list(y)) return("")
    as.character(y$column %||% "")[1]
  }, character(1))

  kararlar <- list()
  aciklamalar <- character(0)
  durdur <- NA_character_

  for (yol in yaprak_yollari) {
    yaprak <- .pk_entity_pluck(filters, yol)
    if (!is.list(yaprak)) next

    sutun <- as.character(yaprak$column %||% "")[1]
    if (is.na(sutun) || !nzchar(sutun)) next

    sozluk <- .pk_entity_apply_vocab(data, sutun)
    if (!length(sozluk)) {
      # ATLANAN YAPRAK SESSİZ KALMAZ, AMA SEBEBİ DOĞRU BİLDİRİLİR.
      #
      # Tek bir "alan metin değil" metni DÖRT farklı durumu anlatıyordu; üstelik
      # sayısal/tarih filtrelerde (çözümleme zaten beklenmez) gereksiz uyarı
      # üretiyordu. `non_text` artık bildirim üretmez; eksik sütun ve boş sözlük
      # ise KENDİ mesajıyla bildirilir.
      not_metni <- .pk_entity_apply_skip_note(
        .pk_entity_apply_vocab_reason(data, sutun), sutun
      )
      if (!is.null(not_metni)) aciklamalar <- c(aciklamalar, not_metni)
      next
    }

    cmeta <- .pk_entity_apply_meta(query, sutun)
    varlik_rolu <- .pk_entity_apply_role(query, sutun, sutunlar)

    ham <- yaprak$value
    if (is.list(ham)) ham <- unlist(ham, use.names = FALSE)
    degerler <- as.character(ham)
    degerler <- degerler[!is.na(degerler) & nzchar(trimws(degerler))]
    if (!length(degerler)) next

    sonuc <- .pk_entity_apply_leaf(
      degerler = degerler, sozluk = sozluk, cmeta = cmeta,
      varlik_rolu = varlik_rolu, meta_kok = meta_kok,
      chat_history = chat_history, prior_context = prior_context,
      sutun = sutun, query = query
    )

    kararlar <- c(kararlar, sonuc$decisions)
    aciklamalar <- c(aciklamalar, sonuc$disclosures)

    if (!is.na(sonuc$halt_message) && is.na(durdur)) durdur <- sonuc$halt_message

    filters <- .pk_entity_set_leaf_value(filters, yol, sonuc$values)
  }

  list(
    action = if (is.na(durdur)) "proceed" else "halt",
    filters = filters,
    decisions = kararlar,
    disclosures = unique(aciklamalar),
    message_tr = durdur
  )
}
