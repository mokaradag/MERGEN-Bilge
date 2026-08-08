# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_parse.R
# Açıklama: Faz 5 (§5.2) — LLM çıktısının AYRIŞTIRILMASI, `requirements`
#           doğrulaması ve DETERMİNİSTİK karar politikası.
#
# Bu dosya modelin metnine değil, YALNIZCA doğrulanmış yapıya güvenir:
#   * kimlikler KARARLI olmalıdır ve aday kümesinde bulunmalıdır (D13),
#   * güven değerleri tam sayı ve 0..100 aralığında olmalıdır,
#   * `alternates` KENDİ güvenini taşımalıdır; aksi hâlde ikinci-aday marjı
#     hesaplanamaz ve `MERGEN_PK_SELECT_MIN_MARGIN` uygulanamaz (§5.2),
#   * `requirements` içindeki her yetenek kimliği `pk_capability_registry`
#     ALLOWLIST'inde olmalı ve seçilen sorgu o kimliği AYNEN sunmalıdır.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Karar durumları. `auto` DIŞINDAKİ her durum "çalıştırma, sor/reddet"
# anlamındadır; yanlış finansal sorguyu çalıştırmaktansa hiçbir şey
# çalıştırmamak yeğdir (§5.2).
PK_SELECT_STATUS_AUTO               <- "auto"
PK_SELECT_STATUS_CLARIFY            <- "clarify"
PK_SELECT_STATUS_LOW_CONFIDENCE     <- "low_confidence"
PK_SELECT_STATUS_CLOSE_MARGIN       <- "close_margin"
PK_SELECT_STATUS_NO_RUNNER_UP       <- "no_runner_up"
PK_SELECT_STATUS_NO_CANDIDATES      <- "no_candidates"
PK_SELECT_STATUS_CAPABILITY_MISSING <- "capability_missing"
PK_SELECT_STATUS_UNKNOWN_CAPABILITY <- "unknown_capability"
PK_SELECT_STATUS_MISSING_INFO       <- "missing_info"
PK_SELECT_STATUS_MALFORMED          <- "malformed"
PK_SELECT_STATUS_TIMEOUT            <- "timeout"
PK_SELECT_STATUS_LLM_UNAVAILABLE    <- "llm_unavailable"
PK_SELECT_STATUS_CONFIG_ERROR       <- "config_error"
PK_SELECT_STATUS_DISABLED           <- "disabled"

# Netleştirmede kullanıcıya gösterilen azami seçenek. §5.2: "Render the top 3
# as clickable chips."
.PK_SELECT_CHIP_LIMIT <- 3L

#' Model çıktısındaki JSON gövdesini güvenli biçimde ayrıştır
#'
#' Kod bloğu işaretleri temizlenir; ardından İLK `{`..son `}` aralığı denenir.
#' Ayrıştırma başarısızsa `NULL` döner — kısmi/tahmini kurtarma YAPILMAZ.
pk_select_parse_json <- function(text) {
  if (is.null(text) || !length(text)) return(NULL)
  ham <- as.character(text)[1]
  if (is.na(ham) || !nzchar(trimws(ham))) return(NULL)

  ham <- gsub("```json|```", "", ham, perl = TRUE)
  ham <- trimws(ham)

  bas <- regexpr("{", ham, fixed = TRUE)
  son <- .pk_select_last_index(ham, "}")
  if (bas < 1L || is.na(son) || son < bas) return(NULL)

  govde <- substr(ham, bas, son)
  tryCatch(
    jsonlite::fromJSON(govde, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

.pk_select_last_index <- function(text, ch) {
  konumlar <- gregexpr(ch, text, fixed = TRUE)[[1]]
  if (length(konumlar) == 1L && konumlar[1] == -1L) return(NA_integer_)
  as.integer(konumlar[length(konumlar)])
}

#' Tek bir kararlı kimliği normalleştir
.pk_select_norm_id <- function(x) {
  if (is.null(x) || !length(x)) return(NA_character_)
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  if (!length(x) || is.na(x[1])) return(NA_character_)
  kimlik <- trimws(as.character(x)[1])
  if (!nzchar(kimlik)) return(NA_character_)
  kimlik
}

#' Güven değerini DOĞRULA (tahmin etme)
#'
#' Eksik, metin, `NA`, sonsuz veya aralık dışı güven KABUL EDİLMEZ ve `NA`
#' döner. Varsayılan bir güven UYDURMAK, tam olarak D10'un kusuruydu: v1
#' `confidence %||% 0` ile devam ediyor ve sonra hiçbir yerde
#' karşılaştırmıyordu.
.pk_select_norm_confidence <- function(x) {
  if (is.null(x) || !length(x)) return(NA_integer_)
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  if (!length(x) || is.na(x[1])) return(NA_integer_)

  deger <- suppressWarnings(as.numeric(x[1]))
  if (is.na(deger) || !is.finite(deger)) return(NA_integer_)
  if (deger < 0 || deger > 100) return(NA_integer_)

  as.integer(round(deger))
}

#' Geçiş A çıktısını ayrıştır (§5.2)
#'
#' Yalnızca kütüphanede GERÇEKTEN var olan kararlı kimlikler kabul edilir;
#' bilinmeyen kimlikler düşürülür ve `unknown` alanında raporlanır. Sıra
#' modelin verdiği sıradır (en olası önce); tekrarlar sadeleştirilir.
pk_select_parse_pass_a <- function(text, library_ids) {
  ayrisik <- pk_select_parse_json(text)
  if (is.null(ayrisik)) {
    return(list(ok = FALSE, ids = character(0), unknown = character(0),
                error = "Geçiş A çıktısı geçerli JSON değil."))
  }

  ham <- ayrisik$candidates %||% ayrisik$ids %||% ayrisik$candidate_ids
  if (is.null(ham)) {
    return(list(ok = FALSE, ids = character(0), unknown = character(0),
                error = "Geçiş A çıktısında 'candidates' alanı yok."))
  }

  if (is.list(ham)) ham <- unlist(ham, use.names = FALSE)
  ham <- as.character(ham)
  ham <- trimws(ham[!is.na(ham)])
  ham <- ham[nzchar(ham)]
  ham <- unique(ham)

  bilinmeyen <- setdiff(ham, library_ids)
  gecerli <- ham[ham %in% library_ids]

  list(
    ok = TRUE,
    ids = gecerli,
    unknown = bilinmeyen,
    error = if (length(gecerli)) NA_character_ else "Geçiş A hiç geçerli aday kimliği döndürmedi."
  )
}

#' Geçiş B çıktısını ayrıştır (§5.2)
#'
#' `alternates` KENDİ güven değerlerini taşımalıdır. Güveni doğrulanamayan bir
#' alternatif kümeye ALINMAZ; böylece "ikinci aday var ama güveni yok" durumu
#' sessizce marj kapısını atlatamaz.
pk_select_parse_pass_b <- function(text, candidate_ids) {
  bos <- list(ok = FALSE, id = NA_character_, confidence = NA_integer_,
              reason = NA_character_, alternates = list(),
              requirements = NULL, missing_info = NA_character_,
              error = NA_character_)

  ayrisik <- pk_select_parse_json(text)
  if (is.null(ayrisik)) {
    bos$error <- "Geçiş B çıktısı geçerli JSON değil."
    return(bos)
  }

  kimlik <- .pk_select_norm_id(ayrisik$id)
  if (is.na(kimlik)) {
    bos$error <- "Geçiş B çıktısında kararlı 'id' alanı yok."
    return(bos)
  }
  if (!kimlik %in% candidate_ids) {
    bos$error <- sprintf(
      "Geçiş B aday kümesinde olmayan bir kimlik döndürdü: %s", kimlik
    )
    return(bos)
  }

  guven <- .pk_select_norm_confidence(ayrisik$confidence)
  if (is.na(guven)) {
    bos$id <- kimlik
    bos$error <- "Geçiş B 'confidence' değeri 0-100 aralığında bir sayı değil."
    return(bos)
  }

  alternatifler <- list()
  ham_alt <- ayrisik$alternates
  if (is.list(ham_alt) && length(ham_alt)) {
    for (girdi in ham_alt) {
      alt_id <- .pk_select_norm_id(if (is.list(girdi)) girdi$id else girdi)
      alt_guven <- .pk_select_norm_confidence(if (is.list(girdi)) girdi$confidence else NULL)

      if (is.na(alt_id) || is.na(alt_guven)) next
      if (!alt_id %in% candidate_ids) next
      if (identical(alt_id, kimlik)) next
      if (alt_id %in% vapply(alternatifler, function(a) a$id, character(1))) next

      alternatifler[[length(alternatifler) + 1L]] <- list(id = alt_id, confidence = alt_guven)
    }
  }

  # Kararlı sıralama: azalan güven, eşitlikte C-yerel kimlik sırası (E8).
  if (length(alternatifler) > 1L) {
    guvenler <- vapply(alternatifler, function(a) a$confidence, integer(1))
    kimlikler <- vapply(alternatifler, function(a) a$id, character(1))
    alternatifler <- alternatifler[order(-guvenler, kimlikler, method = "radix")]
  }

  eksik <- ayrisik$missing_info
  eksik <- if (is.null(eksik) || !length(eksik) || is.na(eksik[1])) {
    NA_character_
  } else {
    metin <- trimws(as.character(eksik)[1])
    if (!nzchar(metin) || identical(tolower(metin), "null")) NA_character_ else metin
  }

  list(
    ok = TRUE,
    id = kimlik,
    confidence = guven,
    reason = {
      gerekce <- ayrisik$reason
      if (is.null(gerekce) || !length(gerekce) || is.na(gerekce[1])) NA_character_
      else trimws(as.character(gerekce)[1])
    },
    alternates = alternatifler,
    requirements = if (is.list(ayrisik$requirements)) ayrisik$requirements else NULL,
    missing_info = eksik,
    error = NA_character_
  )
}

#' Yetenek kayıt defterindeki İZİNLİ kimlikleri oku
#'
#' Kayıt defteri yoksa boş vektör döner; bu durumda `requirements` içinde
#' BEYAN EDİLEN her kimlik izinsizdir (fail-closed) — uydurulmuş bir kimliğin
#' "doğrulandı" sayılması imkânsızdır.
pk_select_capability_ids <- function(registry = NULL) {
  if (is.null(registry)) {
    registry <- tryCatch(
      get0("pk_capability_registry", ifnotfound = NULL),
      error = function(e) NULL
    )
  }
  if (!is.list(registry) || !length(registry) || is.null(names(registry))) {
    return(character(0))
  }

  adlar <- names(registry)
  adlar <- trimws(adlar[!is.na(adlar) & nzchar(trimws(adlar))])
  adlar
}

#' `requirements` nesnesini normalleştir ve İZİNLİ kimliklere karşı doğrula
#'
#' İki ayrı başarısızlık AYRIT EDİLİR ve bilinçli olarak birbirine karıştırılmaz:
#'   * `unknown_capability` — model kayıt defterinde OLMAYAN bir kimlik uydurdu,
#'   * `capability_missing` — kimlik geçerli ama SEÇİLEN SORGU onu sunmuyor.
#' İlki bir model hatasıdır (onarım denemesi anlamlıdır), ikincisi bir yetenek
#' eksikliğidir (başka sorgu gerekir). Aynı kovaya konsalardı onarım denemesi
#' asla düzeltemeyeceği bir şeyi tekrar tekrar denerdi.
#'
#' `requirements` HİÇ beyan edilmemişse doğrulanacak bir iddia yoktur ve kapı
#' `not_asserted` ile geçilir. Beyan edildiğinde ise metadata YOKSA reddedilir
#' (§8 Faz 5: "metadata-free semantic requirements refuse before SQL").
pk_select_validate_requirements <- function(query, requirements, capability_ids = NULL) {
  if (is.null(capability_ids)) capability_ids <- pk_select_capability_ids()

  bos <- list(status = "not_asserted", asserted = FALSE,
              unknown = character(0), missing = character(0),
              columns = list(), errors = character(0))

  if (is.null(requirements) || !is.list(requirements) || !length(requirements)) {
    return(bos)
  }

  alanlar <- c("measures", "dates", "dimensions")
  istenen <- character(0)
  for (alan in alanlar) {
    deger <- requirements[[alan]]
    if (is.null(deger)) next
    if (is.list(deger)) deger <- unlist(deger, use.names = FALSE)
    deger <- as.character(deger)
    deger <- trimws(deger[!is.na(deger)])
    istenen <- c(istenen, deger[nzchar(deger)])
  }

  grup <- requirements$group_by
  if (!is.null(grup)) {
    if (is.list(grup)) grup <- unlist(grup, use.names = FALSE)
    grup <- trimws(as.character(grup))
    grup <- grup[!is.na(grup) & nzchar(grup)]
  } else {
    grup <- character(0)
  }
  istenen <- unique(c(istenen, grup))

  varlik <- requirements$entity
  varlik <- if (is.null(varlik) || !length(varlik) || is.na(varlik[1])) {
    NA_character_
  } else {
    metin <- trimws(as.character(varlik)[1])
    if (!nzchar(metin) || identical(tolower(metin), "null")) NA_character_ else metin
  }

  # Hiçbir anlamsal iddia yoksa doğrulanacak bir şey de yoktur.
  if (!length(istenen) && is.na(varlik)) return(bos)

  bilinmeyen <- setdiff(istenen, capability_ids)
  if (length(bilinmeyen)) {
    return(list(
      status = "unknown_capability", asserted = TRUE,
      unknown = bilinmeyen, missing = character(0), columns = list(),
      errors = sprintf(
        "İzinli olmayan yetenek kimliği: %s", paste(bilinmeyen, collapse = ", ")
      )
    ))
  }

  if (!exists("pk_meta_capability_check", mode = "function", inherits = TRUE)) {
    return(list(
      status = "validator_error", asserted = TRUE,
      unknown = character(0), missing = istenen, columns = list(),
      errors = "Yetenek doğrulayıcısı yüklenmedi; anlamsal iddia doğrulanamadı."
    ))
  }

  # `requirements` YENİDEN kurulur: modelin gönderdiği ham nesne bilinmeyen
  # alanlar taşıyabilir ve doğrulayıcı bunları geçersiz sayar. Doğrulanacak
  # olan, yukarıda zaten normalleştirilmiş iddialardır.
  temiz <- list(
    measures   = .pk_select_req_field(requirements$measures),
    dates      = .pk_select_req_field(requirements$dates),
    dimensions = .pk_select_req_field(requirements$dimensions),
    group_by   = grup
  )
  if (!is.na(varlik)) temiz$entity <- varlik

  # Doğrulayıcının ÇÖKMESİ ile "sorgu bu yeteneği sunmuyor" AYNI ŞEY DEĞİLDİR.
  # İkisini tek kovaya koymak, eksik bir bağımlılığı (ör. yüklenmemiş şema
  # dosyası) "metadata eksik" gibi gösterir; operatör metadata doldurmaya
  # çalışırken gerçek kusur yüklemede kalır. Ölçülerek bulundu.
  cagri_hatasi <- NULL
  kontrol <- tryCatch(
    pk_meta_capability_check(query, temiz),
    error = function(e) {
      cagri_hatasi <<- conditionMessage(e)
      NULL
    }
  )

  if (is.null(kontrol)) {
    return(list(
      status = "validator_error", asserted = TRUE,
      unknown = character(0), missing = istenen, columns = list(),
      errors = sprintf(
        "Yetenek doğrulayıcısı çalıştırılamadı: %s",
        cagri_hatasi %||% "bilinmeyen hata"
      )
    ))
  }

  if (!identical(kontrol$status, PK_META_STATUS_OK)) {
    eksik <- as.character(kontrol$missing %||% istenen)
    return(list(
      status = "capability_missing", asserted = TRUE,
      unknown = character(0), missing = eksik,
      columns = kontrol$columns %||% list(),
      errors = sprintf(
        "Seçilen sorgu şu anlamsal yetenekleri sunmuyor: %s",
        paste(eksik, collapse = ", ")
      )
    ))
  }

  list(
    status = "ok", asserted = TRUE,
    unknown = character(0), missing = character(0),
    columns = kontrol$columns %||% list(), errors = character(0)
  )
}

.pk_select_req_field <- function(x) {
  if (is.null(x)) return(character(0))
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  deger <- trimws(as.character(x))
  deger[!is.na(deger) & nzchar(deger)]
}

#' Netleştirme seçeneklerini (chips) kur — en fazla 3 (§5.2)
pk_select_chips <- function(ids, library_index, scores = NULL) {
  ids <- as.character(ids)
  ids <- ids[!is.na(ids) & nzchar(ids)]
  if (!length(ids)) return(list())

  ids <- utils::head(unique(ids), .PK_SELECT_CHIP_LIMIT)

  lapply(ids, function(kimlik) {
    kayit <- library_index[[kimlik]]
    list(
      id = kimlik,
      name = if (is.list(kayit)) as.character(kayit$name %||% kimlik)[1] else kimlik,
      confidence = if (is.null(scores) || is.null(scores[[kimlik]])) NA_integer_ else scores[[kimlik]]
    )
  })
}

#' Karar nesnesi
.pk_select_decision <- function(status, message_tr = NA_character_, ...) {
  out <- list(
    status = status,
    query_id = NA_character_,
    confidence = NA_integer_,
    effective_confidence = NA_integer_,
    runner_up_id = NA_character_,
    runner_up_confidence = NA_integer_,
    margin = NA_integer_,
    reason = NA_character_,
    requirements = NULL,
    capability_status = "not_asserted",
    lexical = list(available = FALSE, rank = NA_integer_, score = NA_real_, disagrees = FALSE),
    chips = list(),
    disclosures = character(0),
    message_tr = message_tr
  )
  ust <- list(...)
  if (length(ust)) out[names(ust)] <- ust
  out
}

#' DETERMİNİSTİK karar politikası (§5.2)
#'
#' Kural sırası bilinçlidir ve TESTLE KİLİTLİDİR:
#'   1. Yapılandırma geçersiz            -> config_error (otomatik seçim kapalı)
#'   2. Aday yok                         -> no_candidates
#'   3. Geçiş B ayrıştırılamadı          -> malformed
#'   4. Yetenek kimliği uydurulmuş       -> unknown_capability
#'   5. Sorgu yeteneği sunmuyor          -> capability_missing
#'   6. Model eksik bilgi bildirdi       -> missing_info
#'   7. Doğrulanmış ikinci aday yok      -> no_runner_up
#'   8. Güven eşiğin altında             -> low_confidence
#'   9. Marj eşiğin altında              -> close_margin
#'  10. aksi hâlde                       -> auto
#'
#' Yetenek kapısı GÜVENDEN ÖNCE gelir (§5.2): gerekli yeteneği sunmayan bir
#' sorguya %95 güvenle işaret eden model yine de o soruyu cevaplayamaz ve bu
#' SQL'den ÖNCE kanıtlanmalıdır.
#'
#' Sözlüksel uyuşmazlık KARAR VERMEZ; yalnızca güveni `disagree_penalty` kadar
#' düşürür ve sonuç eşiklerden geçmezse karar zaten aşağıdaki kurallarla ASKIYA
#' alınır.
pk_select_decide <- function(pass_b, candidates_ids, library_index, cfg,
                             lexical = NULL, capability_ids = NULL) {
  bos_lex <- list(available = FALSE, rank = NA_integer_, score = NA_real_, disagrees = FALSE)
  if (!is.list(lexical)) lexical <- bos_lex

  if (!isTRUE(cfg$valid)) {
    return(.pk_select_decision(
      PK_SELECT_STATUS_CONFIG_ERROR,
      message_tr = paste0(
        "Sorgu seçimi yapılandırması geçersiz olduğu için otomatik seçim ",
        "devre dışı bırakıldı. Operatöre bildirin: ",
        paste(cfg$errors, collapse = " ")
      ),
      lexical = lexical
    ))
  }

  if (!length(candidates_ids)) {
    return(.pk_select_decision(
      PK_SELECT_STATUS_NO_CANDIDATES,
      message_tr = paste0(
        "Sorunuza karşılık gelen bir analiz sorgusu bulunamadı. Lütfen sorunuzu ",
        "farklı kelimelerle yeniden ifade edin."
      ),
      lexical = lexical
    ))
  }

  if (!is.list(pass_b) || !isTRUE(pass_b$ok)) {
    hata <- if (is.list(pass_b)) pass_b$error else NA_character_
    return(.pk_select_decision(
      PK_SELECT_STATUS_MALFORMED,
      message_tr = paste0(
        "Sorgu seçimi güvenilir bir sonuç üretemedi. Lütfen sorunuzu biraz daha ",
        "açık yazarak tekrar deneyin."
      ),
      chips = pk_select_chips(candidates_ids, library_index),
      disclosures = if (is.na(hata %||% NA_character_)) character(0) else as.character(hata),
      lexical = lexical
    ))
  }

  secilen <- library_index[[pass_b$id]]
  dogrulama <- pk_select_validate_requirements(secilen, pass_b$requirements, capability_ids)

  ortak <- list(
    query_id = pass_b$id,
    confidence = pass_b$confidence,
    reason = pass_b$reason,
    requirements = pass_b$requirements,
    capability_status = dogrulama$status,
    lexical = lexical
  )

  if (identical(dogrulama$status, "unknown_capability")) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_UNKNOWN_CAPABILITY,
        message_tr = paste0(
          "Sorgu seçimi tanımlı olmayan bir anlamsal yetenek belirtti; analiz ",
          "güvenli biçimde sürdürülemedi. Lütfen sorunuzu farklı ifade edin."
        ),
        chips = pk_select_chips(candidates_ids, library_index),
        disclosures = dogrulama$errors
      ),
      ortak
    )))
  }

  # Doğrulayıcı çalışamadıysa KAPALI başarısız olunur: iddia doğrulanamadığı
  # için otomatik çalıştırma yapılmaz. Mesaj bunun bir METADATA eksikliği
  # değil, bir sistem kusuru olduğunu söyler.
  if (identical(dogrulama$status, "validator_error")) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_CAPABILITY_MISSING,
        message_tr = paste0(
          "Sorgu seçiminin anlamsal doğrulaması yapılamadığı için analiz ",
          "çalıştırılmadı. Bu bir yapılandırma/kurulum sorunudur; operatöre ",
          "bildirin."
        ),
        chips = pk_select_chips(candidates_ids, library_index),
        disclosures = dogrulama$errors
      ),
      ortak
    )))
  }

  if (identical(dogrulama$status, "capability_missing")) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_CAPABILITY_MISSING,
        message_tr = paste0(
          "Sorunuzun gerektirdiği ölçü/tarih/boyut bilgisi seçilebilecek ",
          "sorgularda tanımlı değil; yanlış bir sonuç üretmemek için analiz ",
          "çalıştırılmadı."
        ),
        chips = pk_select_chips(candidates_ids, library_index),
        disclosures = dogrulama$errors
      ),
      ortak
    )))
  }

  if (!is.na(pass_b$missing_info)) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_MISSING_INFO,
        message_tr = sprintf(
          "Sorunuzu cevaplamak için ek bilgi gerekiyor: %s", pass_b$missing_info
        ),
        chips = pk_select_chips(candidates_ids, library_index)
      ),
      ortak
    )))
  }

  # --- İkinci aday: marj kapısının ÖN KOŞULU (§5.2) -------------------------
  ikinci <- if (length(pass_b$alternates)) pass_b$alternates[[1]] else NULL
  if (is.null(ikinci)) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_NO_RUNNER_UP,
        message_tr = paste0(
          "Sorgu seçimi yalnızca tek bir aday üretebildi; ikinci adayın güveni ",
          "olmadan seçimin güvenilirliği ölçülemedi. Lütfen aşağıdaki ",
          "seçeneklerden birini belirtin ya da sorunuzu netleştirin."
        ),
        chips = pk_select_chips(
          unique(c(pass_b$id, candidates_ids)), library_index,
          scores = stats::setNames(list(pass_b$confidence), pass_b$id)
        )
      ),
      ortak
    )))
  }

  ortak$runner_up_id <- ikinci$id
  ortak$runner_up_confidence <- ikinci$confidence

  # --- Sözlüksel uyuşmazlık: güveni ZAYIFLATIR, karar vermez ---------------
  etkin <- pass_b$confidence
  aciklamalar <- character(0)
  if (isTRUE(lexical$disagrees) && cfg$disagree_penalty > 0L) {
    etkin <- max(0L, etkin - cfg$disagree_penalty)
    aciklamalar <- c(aciklamalar, sprintf(
      "Sözlüksel getirim bu sorguyu %d. sırada gördü; güven %d -> %d düşürüldü.",
      lexical$rank, pass_b$confidence, etkin
    ))
  }
  ortak$effective_confidence <- etkin

  marj <- as.integer(etkin - ikinci$confidence)
  ortak$margin <- marj

  cipler <- pk_select_chips(
    unique(c(pass_b$id, ikinci$id, candidates_ids)), library_index,
    scores = stats::setNames(
      list(pass_b$confidence, ikinci$confidence),
      c(pass_b$id, ikinci$id)
    )
  )

  if (etkin < cfg$min_confidence) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_LOW_CONFIDENCE,
        message_tr = paste0(
          "Sorunuza hangi analizin cevap vereceğinden yeterince emin olunamadı. ",
          "Yanlış bir analiz çalıştırmamak için aşağıdaki seçeneklerden birini ",
          "belirtmenizi ya da sorunuzu netleştirmenizi rica ederiz."
        ),
        chips = cipler, disclosures = aciklamalar
      ),
      ortak
    )))
  }

  if (marj < cfg$min_margin) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_CLOSE_MARGIN,
        message_tr = paste0(
          "Sorunuza birden fazla analiz benzer ölçüde uygun görünüyor. Yanlış ",
          "olanı çalıştırmamak için hangisini istediğinizi belirtmenizi rica ederiz."
        ),
        chips = cipler, disclosures = aciklamalar
      ),
      ortak
    )))
  }

  do.call(.pk_select_decision, c(
    list(
      PK_SELECT_STATUS_AUTO,
      message_tr = NA_character_,
      chips = list(), disclosures = aciklamalar
    ),
    ortak
  ))
}
