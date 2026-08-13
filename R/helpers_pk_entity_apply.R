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

# Sütun sorunun ÖZNESİ mi, ikincil daraltma mı? Kural 6 ile 7'nin farkı budur.
.pk_entity_apply_role <- function(query, column, filter_columns) {
  birincil <- if (exists("pk_meta_primary_entity", mode = "function")) {
    pk_meta_primary_entity(query, filter_columns)
  } else if (is.list(query)) {
    meta <- if (is.list(query$meta)) query$meta else query
    meta$primary_entity
  } else {
    NULL
  }

  if (is.null(birincil) || !length(birincil)) return("subject")
  if (identical(as.character(birincil)[1], column)) return("subject")
  "refinement"
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

  sutunlar <- vapply(filters, function(f) {
    if (!is.list(f)) return("")
    as.character(f$column %||% "")[1]
  }, character(1))

  kararlar <- list()
  aciklamalar <- character(0)
  durdur <- NA_character_

  for (i in seq_along(filters)) {
    yaprak <- filters[[i]]
    if (!is.list(yaprak)) next

    sutun <- as.character(yaprak$column %||% "")[1]
    if (is.na(sutun) || !nzchar(sutun)) next

    sozluk <- .pk_entity_apply_vocab(data, sutun)
    if (!length(sozluk)) next

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
      sutun = sutun
    )

    kararlar <- c(kararlar, sonuc$decisions)
    aciklamalar <- c(aciklamalar, sonuc$disclosures)

    if (!is.na(sonuc$halt_message) && is.na(durdur)) durdur <- sonuc$halt_message

    filters[[i]]$value <- sonuc$values
  }

  list(
    action = if (is.na(durdur)) "proceed" else "halt",
    filters = filters,
    decisions = kararlar,
    disclosures = unique(aciklamalar),
    message_tr = durdur
  )
}

# Tek bir yaprağın tüm değerlerini çözer.
.pk_entity_apply_leaf <- function(degerler, sozluk, cmeta, varlik_rolu, meta_kok,
                                  chat_history, prior_context, sutun) {
  kararlar <- list()
  aciklamalar <- character(0)
  yeni_degerler <- character(0)
  durdur <- NA_character_

  for (deger in degerler) {
    karar <- pk_entity_resolve_with_history(
      phrase = deger,
      candidates = sozluk,
      chat_history = chat_history,
      aliases = cmeta$aliases,
      role = cmeta$role,
      match_mode = cmeta$match_mode,
      entity_role = varlik_rolu,
      query_meta = meta_kok,
      entity_kinds = cmeta$entity_kinds,
      prior_context = prior_context,
      # BAĞLAM ANAHTARI SORGU KİMLİĞİNİ DE İÇERİR.
      #
      # `pk_entity_resolve_with_history()` anahtarı TAM KİMLİK olarak
      # karşılaştırır ve sözleşmesi query_id + column + entity_kind'dir.
      # Yalnızca `column` vermek iki yönlü bozuktu: doğru kurulmuş bir bağlam
      # ASLA eşleşemiyordu (devralma ölü koddu) ve eşleşseydi bile iki FARKLI
      # sorgudaki aynı adlı sütun (ör. `ProjeAdi`) birbirinin bağlamını
      # devralabilirdi.
      context_key = .pk_entity_context_key(query, sutun, cmeta)
    )

    karar$column <- sutun
    karar$phrase <- deger
    kararlar[[length(kararlar) + 1L]] <- karar

    if (identical(karar$decision, "auto") && length(karar$values)) {
      yeni_degerler <- c(yeni_degerler, karar$values)
      next
    }

    if (karar$decision %in% c("confirm", "clarify", "unresolved")) {
      if (is.na(durdur)) durdur <- karar$message_tr
      # Analiz yapılmayacağı için değer olduğu gibi korunur; kullanıcı seçim
      # yaptığında istek yeniden kurulur.
      yeni_degerler <- c(yeni_degerler, deger)
      next
    }

    if (identical(karar$decision, "unfiltered")) {
      # İkincil daraltma çözümlenemedi: DÜŞÜRÜLÜR ve AÇIKÇA bildirilir.
      aciklamalar <- c(aciklamalar, sprintf(
        "'%s' değeri %s sütununda çözümlenemedi; bu daraltma UYGULANMADI.",
        deger, sutun
      ))
      next
    }

    if (identical(karar$decision, "config_error")) {
      aciklamalar <- c(aciklamalar, karar$message_tr)
    }

    # disabled / not_applicable / invalid_input / config_error: ham değer kalır.
    yeni_degerler <- c(yeni_degerler, deger)
  }

  list(
    decisions = kararlar,
    disclosures = aciklamalar,
    values = unique(yeni_degerler),
    halt_message = durdur
  )
}
