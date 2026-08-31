# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_decide.R
# Açıklama: Faz 5 (§5.2) — DETERMİNİSTİK karar politikası ve netleştirme
#           seçenekleri (chips).
#
# Ayrıştırma `helpers_pk_query_selection_parse.R` içindedir; burada YALNIZCA
# doğrulanmış yapıdan karar üretilir. `auto` DIŞINDAKİ her durum "çalıştırma,
# sor/reddet" anlamındadır.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Netleştirmede kullanıcıya gösterilen azami seçenek. §5.2: "Render the top 3
# as clickable chips."
.PK_SELECT_CHIP_LIMIT <- 3L

#' Netleştirme seçeneklerini (chips) kur — en fazla 3 (§5.2)
#'
#' `scores` adlandırılmış listedir; sıralama ÇAĞIRAN tarafından belirlenir.
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

#' Geçiş B GÜVEN SIRALAMASINDAN netleştirme seçenekleri
#'
#' Eski sıralama "seçilen, ikinci aday, sonra Geçiş A sırası" idi ve yalnızca
#' ilk ikisinin skoru vardı. `alternates` artık HER adayı kendi güveniyle
#' taşıdığı için, kullanıcıya gösterilen "ilk 3" gerçekten en yüksek güvenli
#' üç aday olabilir; Geçiş A sırasında öne düşmüş DÜŞÜK güvenli bir aday
#' üçüncü sırayı işgal etmez.
pk_select_ranked_chips <- function(pass_b, candidates_ids, library_index) {
  kimlikler <- pass_b$id
  skorlar <- list()
  skorlar[[pass_b$id]] <- pass_b$confidence

  for (alt in pass_b$alternates) {
    kimlikler <- c(kimlikler, alt$id)
    skorlar[[alt$id]] <- alt$confidence
  }

  # SABİT TİPLİ `vapply()` SKALER BEKLER: Geçiş B bir adayın `confidence` alanını `NULL` ya da çok değerli döndürdüğünde `vapply()` "values must be length 1" ile TÜM seçimi düşürüyordu. Kullanılamayan güven `0L` sayılır; aday listenin SONUNA düşer, sessizce KAYBOLMAZ.
  guvenler <- vapply(kimlikler, function(k) {
    d <- suppressWarnings(as.integer(skorlar[[k]])[1])
    if (length(d) != 1L || is.na(d)) 0L else d
  }, integer(1), USE.NAMES = FALSE)
  sira <- order(-guvenler, kimlikler, method = "radix")
  kimlikler <- kimlikler[sira]

  # Geçiş A adaylarından hâlâ eksik kalan varsa (ör. bozuk cevap yolunda)
  # sonlarına eklenir; skorsuz gösterilirler.
  kimlikler <- unique(c(kimlikler, as.character(candidates_ids)))

  pk_select_chips(kimlikler, library_index, scores = skorlar)
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
    # Tanılama: reddedilen kimlik ve VARLIK->SAYIM kanonikleştirmesi.
    capability_unknown = character(0),
    capability_canonicalized = character(0),
    alternate_scores = list(),
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
#'   1. Yapılandırma geçersiz              -> config_error (otomatik seçim kapalı)
#'   2. Aday yok                           -> no_candidates
#'   3. Geçiş B ayrıştırılamadı            -> malformed
#'   4. İfade edilemeyen anlamsal ihtiyaç  -> unsupported_requirement
#'   5. Yetenek kimliği uydurulmuş         -> unknown_capability
#'   6. Doğrulayıcı çalışamadı             -> validator_error
#'   7. Sorgu yeteneği sunmuyor            -> capability_missing
#'   8. Model eksik bilgi bildirdi         -> missing_info
#'   9. Doğrulanmış ikinci aday yok        -> no_runner_up
#'  10. Güven eşiğin altında               -> low_confidence
#'  11. Marj eşiğin altında                -> close_margin
#'  12. aksi hâlde                         -> auto
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

  # §9 önceliği metadata -> ortam -> options -> varsayılandır. Seçim eşikleri
  # aday belli olmadan çözülemez; SEÇİM YAPILDIKTAN SONRA sorgunun kendi
  # (daha katı) politikası uygulanır.
  cfg <- pk_select_config_for_query(cfg, if (is.list(secilen)) secilen$meta else NULL)
  if (!isTRUE(cfg$valid)) {
    return(.pk_select_decision(
      PK_SELECT_STATUS_CONFIG_ERROR,
      message_tr = paste0(
        "Seçilen sorgunun seçim politikası geçersiz olduğu için analiz ",
        "çalıştırılmadı. Operatöre bildirin: ", paste(cfg$errors, collapse = " ")
      ),
      lexical = lexical
    ))
  }

  dogrulama <- pk_select_validate_requirements(secilen, pass_b$requirements, capability_ids)
  cipler <- pk_select_ranked_chips(pass_b, candidates_ids, library_index)

  ortak <- list(
    query_id = pass_b$id,
    confidence = pass_b$confidence,
    reason = pass_b$reason,
    requirements = pass_b$requirements,
    capability_status = dogrulama$status,
    capability_unknown = dogrulama$unknown %||% character(0),
    capability_canonicalized = dogrulama$canonicalized %||% character(0),
    alternate_scores = .pk_select_alternate_scores(pass_b),
    lexical = lexical
  )

  erken <- .pk_select_semantic_gate(pass_b, dogrulama, cipler, ortak)
  if (!is.null(erken)) return(erken)

  # `not_for` DIŞLAMASI BÜTÜN diğer kurallardan ÖNCE gelir: kapı eskiden ikinci-aday kuralından SONRA duruyordu; Geçiş B tek aday bildirdiğinde `no_runner_up` erken dönüyor ve REDDEDİLEN sorgu çip olarak GERİ TEKLİF ediliyordu. Onay yolu yalnızca saklanan gereksinimleri doğrular, `not_for`u YENİDEN değerlendirmez; kullanıcı o çipe basarak metadata'nın uygunsuz işaretlediği sorguyu çalıştırabiliyordu. `aciklamalar` bu noktada henüz tanımlı değildir; ret metni zaten kendi gerekçesini taşır.
  if (isTRUE(lexical$excluded_by_not_for)) {
    # REDDEDİLEN SORGU GERİ TEKLİF EDİLMEZ.
    .not_for_id <- as.character(pass_b$id %||% "")[1]
    not_for_cipler <- Filter(function(cip) !identical(as.character(cip$id %||% "")[1], .not_for_id), cipler %||% list())
    return(do.call(.pk_select_decision, c(
      list(PK_SELECT_STATUS_CAPABILITY_MISSING, message_tr = paste0(
        "Seçilen analizin tanımı bu tür bir soru için UYGUN OLMADIĞINI açıkça ",
        "belirtiyor; yanlış bir sonuç üretmemek adına analiz çalıştırılmadı. ",
        "Lütfen aşağıdaki seçeneklerden birini belirtin ya da sorunuzu netleştirin."
      ), chips = not_for_cipler, disclosures = character(0)),
      ortak
    )))
  }

  # --- İkinci aday: marj kapısının ÖN KOŞULU (§5.2) -------------------------
  #
  # Marj kapısı "iki analiz de akla yatkın" durumunu yakalamak içindir. İDDİA
  # EDİLEN anlamsalları KARŞILAYAMAYAN bir aday akla yatkın DEĞİLDİR: planlanan
  # işçilik sorusunda, o yeteneği hiç sunmayan bir kalan-işçilik sorgusu yakın
  # skorla "rakip" sayılıp geçerli bir seçimi `close_margin` ile durduruyordu.
  rakipler <- .pk_select_capable_alternates(pass_b, library_index, capability_ids)

  if (!length(pass_b$alternates %||% list())) {
    return(do.call(.pk_select_decision, c(
      list(
        PK_SELECT_STATUS_NO_RUNNER_UP,
        message_tr = paste0(
          "Sorgu seçimi yalnızca tek bir aday üretebildi; ikinci adayın güveni ",
          "olmadan seçimin güvenilirliği ölçülemedi. Lütfen aşağıdaki ",
          "seçeneklerden birini belirtin ya da sorunuzu netleştirin."
        ),
        chips = cipler
      ),
      ortak
    )))
  }

  ikinci <- if (length(rakipler)) rakipler[[1]] else NULL
  if (!is.null(ikinci)) {
    ortak$runner_up_id <- ikinci$id
    ortak$runner_up_confidence <- ikinci$confidence
  }

  # --- Sözlüksel uyuşmazlık: güveni ZAYIFLATIR, karar vermez ---------------
  etkin <- pass_b$confidence
  aciklamalar <- character(0)
  if (isTRUE(lexical$disagrees)) {
    ceza <- max(0L, as.integer(cfg$disagree_penalty))
    etkin <- max(0L, etkin - ceza)
    # `DISAGREE_PENALTY = 0` "sinyali yok say" değil, "skoru etkileme ama RAPORLA" demektir; açıklama cezadan BAĞIMSIZ eklenir.
    # SIRA BİLİNMİYORSA "NA. sıra" YAZILMAZ: `pk_retrieval_agreement()` seçilen sorgu KENDİ `not_for` kaydıyla dışlandığında `rank = NA_integer_` döndürür.
    sira_var <- length(lexical$rank) == 1L && !is.na(lexical$rank)
    aciklamalar <- c(aciklamalar, if (sira_var) {
      sprintf("Sözlüksel getirim bu sorguyu %d. sırada gördü; güven %d -> %d.", as.integer(lexical$rank), pass_b$confidence, etkin)
    } else {
      sprintf("Sözlüksel getirim bu sorguyu aday listesinde GÖRMEDİ (kütüphane kaydı bu soruyu dışlıyor); güven %d -> %d.", pass_b$confidence, etkin)
    })
  }
  ortak$effective_confidence <- etkin

  # Hiçbir rakip iddiayı karşılayamıyorsa BELİRSİZLİK YOKTUR: seçilen sorgu
  # metadata'ya göre TEK yetkin adaydır. Bu durumda reddetmek, iyi tanımlanmış
  # istekleri cezalandıran bir yanlış alarm olurdu. Güven kapısı YİNE uygulanır.
  # RAKİP GÜVENİ SKALERE İNDİRGENİR: `NULL` bir `confidence` ile `etkin - ikinci$confidence` `numeric(0)` üretiyor, `marj` `integer(0)` oluyor ve marj kapısındaki `if (!is.na(integer(0)) && ...)` "argument is of length zero" fırlatıyordu; kapı, kullanıcıdan netleştirme istemek yerine iç hataya düşüyordu.
  ikinci_guven <- if (is.null(ikinci)) NA_integer_ else {
    d <- suppressWarnings(as.integer(ikinci$confidence)[1])
    if (length(d) != 1L) NA_integer_ else d
  }
  marj <- if (is.null(ikinci) || is.na(ikinci_guven)) NA_integer_ else as.integer(etkin - ikinci_guven)
  ortak$margin <- marj
  if (is.null(ikinci)) {
    aciklamalar <- c(aciklamalar, paste0(
      "Diğer adayların hiçbiri sorunun gerektirdiği anlamsal yetenekleri ",
      "sunmuyor; marj kapısı uygulanmadı."
    ))
  }

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

  if (!is.na(marj) && marj < cfg$min_margin) {
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

#' Tüm alternatif güvenlerini adlandırılmış liste olarak sakla
#'
#' Tanılama tablosu eskiden yalnızca seçilen ve ilk ikinci adayı yazıyordu;
#' üçüncü aday geçerli bir skora sahipken tabloda 0 görünüyor ve v1 uyumlu
#' telemetri "model skor vermedi" diyordu.
.pk_select_alternate_scores <- function(pass_b) {
  skorlar <- list()
  for (alt in pass_b$alternates %||% list()) skorlar[[alt$id]] <- alt$confidence
  skorlar
}

#' Anlamsal kapılar (uydurma kimlik / doğrulayıcı çökmesi / eksik yetenek /
#' ifade edilemeyen ihtiyaç / eksik bilgi)
.pk_select_semantic_gate <- function(pass_b, dogrulama, cipler, ortak) {
  karar <- function(status, mesaj, aciklamalar = character(0)) {
    do.call(.pk_select_decision, c(
      list(status, message_tr = mesaj, chips = cipler, disclosures = aciklamalar),
      ortak
    ))
  }

  # Model, sorunun gerektirdiği ama İZİNLİ LİSTEDE OLMAYAN bir anlamsalı
  # bildirdiyse iddia doğrulanamaz. Eskiden istem modelden bu ihtiyacı
  # SİLMESİNİ istiyordu; sonuç, kanıtsız ama yüksek güvenli bir `auto` idi.
  ifade_edilemeyen <- pk_select_unsupported_needs(pass_b$requirements)
  if (length(ifade_edilemeyen)) {
    return(karar(
      PK_SELECT_STATUS_UNSUPPORTED_REQ,
      paste0(
        "Sorunuzun gerektirdiği bazı bilgiler tanımlı analiz yetenekleriyle ",
        "ifade edilemedi; yanlış bir sonuç üretmemek için analiz çalıştırılmadı."
      ),
      sprintf("Karşılanamayan ihtiyaç: %s", paste(ifade_edilemeyen, collapse = ", "))
    ))
  }

  if (identical(dogrulama$status, "unknown_capability")) {
    return(karar(
      PK_SELECT_STATUS_UNKNOWN_CAPABILITY,
      paste0(
        "Sorgu seçimi tanımlı olmayan bir anlamsal yetenek belirtti; analiz ",
        "güvenli biçimde sürdürülemedi. Lütfen sorunuzu farklı ifade edin."
      ),
      dogrulama$errors
    ))
  }

  # Doğrulayıcı çalışamadıysa KAPALI başarısız olunur. Durum `capability_missing`
  # ile BİRLEŞTİRİLMEZ: telemetri/arayüz "metadata eksik" derken gerçek kusur
  # yüklemede/kurulumda kalıyordu.
  if (identical(dogrulama$status, "validator_error")) {
    return(karar(
      PK_SELECT_STATUS_VALIDATOR_ERROR,
      paste0(
        "Sorgu seçiminin anlamsal doğrulaması yapılamadığı için analiz ",
        "çalıştırılmadı. Bu bir yapılandırma/kurulum sorunudur; operatöre ",
        "bildirin."
      ),
      dogrulama$errors
    ))
  }

  if (identical(dogrulama$status, "capability_missing")) {
    return(karar(
      PK_SELECT_STATUS_CAPABILITY_MISSING,
      paste0(
        "Sorunuzun gerektirdiği ölçü/tarih/boyut bilgisi seçilebilecek ",
        "sorgularda tanımlı değil; yanlış bir sonuç üretmemek için analiz ",
        "çalıştırılmadı."
      ),
      dogrulama$errors
    ))
  }

  # ALAN HİÇ YOKSA `is.na(NULL)` `logical(0)` DÖNER: `if (logical(0))` "argument is of length zero" fırlatır ve istek tipli reddetme yerine iç seçim hatasına dönerdi.
  eksik_bilgi <- pass_b$missing_info
  if (length(eksik_bilgi) == 1L && !is.na(eksik_bilgi)) {
    return(karar(
      PK_SELECT_STATUS_MISSING_INFO,
      sprintf("Sorunuzu cevaplamak için ek bilgi gerekiyor: %s", eksik_bilgi)
    ))
  }

  NULL
}

#' İDDİA EDİLEN anlamsalları KARŞILAYABİLEN alternatifler (azalan güven)
#'
#' İddia beyan edilmemişse hiçbir aday elenmez ve liste olduğu gibi döner.
.pk_select_capable_alternates <- function(pass_b, library_index, capability_ids) {
  # SIRALAMA HER İKİ YOLDA DA UYGULANIR: iddia beyan edilmediğinde liste MODEL
  # sırasıyla dönüyor ve marj güçsüz bir adaya karşı ölçülüyordu.
  alternatifler <- .pk_select_sort_by_confidence(pass_b$alternates %||% list())
  if (!length(alternatifler)) return(list())
  if (pk_select_requirements_empty(pass_b$requirements)) return(alternatifler)

  yetkin <- list()
  for (alt in alternatifler) {
    aday <- library_index[[alt$id]]
    if (is.null(aday)) next

    kontrol <- pk_select_validate_requirements(aday, pass_b$requirements, capability_ids)
    if (kontrol$status %in% c("ok", "not_asserted")) {
      yetkin[[length(yetkin) + 1L]] <- alt
    }
  }
  .pk_select_sort_by_confidence(yetkin)
}

# MARJ KAPISI EN GÜÇLÜ YETKİN RAKİBE KARŞI ÖLÇÜLÜR (azalan güven; sonlu olmayan güven en sona düşer).
.pk_select_sort_by_confidence <- function(adaylar) {
  if (!is.list(adaylar) || length(adaylar) < 2L) return(adaylar)
  puanlar <- vapply(adaylar, function(alt) suppressWarnings(as.numeric(alt$confidence)[1]), numeric(1))
  puanlar[!is.finite(puanlar)] <- -Inf
  adaylar[order(-puanlar, method = "radix")]
}
