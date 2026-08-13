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
# Devralınan varlık bağlamı için KARARLI kimlik anahtarı.
#
# `entity_kind` sütun metadata'sından okunur; yoksa sütun rolü kullanılır.
# Anahtar YALNIZCA bu üçlüden üretilir ki iki farklı sorgu aynı sütun adını
# taşıdığında bağlam sınırı korunsun.
.pk_entity_context_key <- function(query, column, cmeta = NULL) {
  meta_kok <- if (is.list(query) && is.list(query$meta)) query$meta else query
  sorgu_id <- as.character(
    (if (is.list(query)) query$id %||% query$query_id else NULL) %||%
      (if (is.list(meta_kok)) meta_kok$query_id else NULL) %||% ""
  )[1]
  if (is.na(sorgu_id)) sorgu_id <- ""

  tur <- as.character(
    (if (is.list(cmeta)) (cmeta$entity_kinds %||% cmeta$entity_kind %||% cmeta$role) else NULL) %||% ""
  )[1]
  if (is.na(tur)) tur <- ""

  list(query_id = sorgu_id, column = as.character(column)[1], entity_kind = tur)
}

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

# ==============================================================================
# DEVRALINAN VARLIK BAĞLAMI (D11) — OTURUM KAPSAMLI KALICI KAYIT
#
# `pk_entity_resolve_with_history()` bir önceki turda ÇÖZÜLMÜŞ varlığı
# devralabilir, ancak bunun için kalıcı bir bağlam kaydına ihtiyacı vardır.
# Bu kayıt daha önce HİÇ üretilmiyordu: `prior_entity_context` alanını dolduran
# bir üretici yoktu, bu yüzden "peki 2024 için?" gibi bir devam sorusu önceki
# projeyi devralamıyordu ve geçmiş farkındalıklı çözümleyici pratikte ölü koddu.
#
# Kayıt sohbet geçmişi gibi serbest metin DEĞİL, YALNIZCA çözümleyicinin
# `auto` kararıyla ürettiği KANONİK değerlerdir; bu yüzden yeni bir güven
# sınırı açmaz.
# ==============================================================================

.PK_ENTITY_CONTEXT_SLOT <- "pk_entity_prior_context"

#' Oturumda saklanan önceki varlık bağlamını oku.
pk_entity_context_recall <- function(session) {
  if (is.null(session)) return(NULL)
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(NULL)
  kayit <- tryCatch(ud[[.PK_ENTITY_CONTEXT_SLOT]], error = function(e) NULL)
  if (!is.list(kayit) || !length(kayit$values)) return(NULL)
  kayit
}

#' Çözümleme kararlarından devralınabilir bağlamı sakla.
#'
#' Yalnızca ÖZNE (`subject`) rolündeki ve `auto` kararıyla çözülmüş bir yaprak
#' saklanır: ikincil daraltmaların devralınması, kullanıcının sormadığı bir
#' kısıtı sessizce sonraki soruya taşırdı.
pk_entity_context_remember <- function(session, decisions, query = NULL) {
  if (is.null(session)) return(invisible(FALSE))
  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(FALSE))

  kararlar <- if (is.list(decisions)) decisions else list()
  for (karar in rev(kararlar)) {
    if (!is.list(karar) || !identical(karar$decision, "auto")) next
    if (!length(karar$values)) next
    if (!identical(as.character(karar$entity_role %||% "subject")[1], "subject")) next

    sutun <- as.character(karar$column %||% "")[1]
    if (is.na(sutun) || !nzchar(sutun)) next

    tryCatch({
      ud[[.PK_ENTITY_CONTEXT_SLOT]] <- list(
        values = as.character(karar$values),
        key = .pk_entity_context_key(query, sutun, karar$column_meta)
      )
    }, error = function(e) NULL)
    return(invisible(TRUE))
  }

  invisible(FALSE)
}

#' Filtre talimatlarını sohbet geçmişi ve önceki varlık bağlamıyla zenginleştir
#'
#' `extract_filter_criteria_from_prompt()` bu iki alanı ÜRETMEZ; üretim yolu
#' bu yüzden çözümleyiciye her zaman `NULL` veriyordu. Zenginleştirme burada,
#' tek bir yerde yapılır ki senkron ve derin analiz yolları AYNI bağlamı görsün.
pk_filter_instructions_with_context <- function(filter_instructions, chat_history = NULL,
                                                session = NULL) {
  talimatlar <- if (is.list(filter_instructions)) filter_instructions else list()
  talimatlar$chat_history <- chat_history
  talimatlar$prior_entity_context <- pk_entity_context_recall(session)
  talimatlar
}
