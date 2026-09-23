# ==============================================================================
# Dosya Yolu: R/helpers_pk_numeric_provenance.R
# Açıklama: Sayısal köken (numeric provenance) UYGULAMA katmanı — §5.11.
#
#           SORUMLULUK AYRIMI:
#             LLM  -> dil, yorum, olası açıklama, öneri, anlatı akışı ve
#                     HANGİ olgunun konuya ilgili olduğu.
#             R    -> sayısal DEĞER, biçim, birim, yüzde, para birimi, olgu
#                     kimliği, yetkilendirme ve nihai gösterim.
#
#           Model artık sayıyı YAZMAZ: sayının yerine `{{fact:...}}` yuvasını
#           koyar ve R kanonik gösterimi basar (bkz.
#           `R/helpers_pk_fact_reference.R`). Düzyazıdaki serbest sayıları
#           olgulara GERİYE DOĞRU eşleştiren eski mimari (işaret gruplama,
#           sözcük mesafesi, tolerans, birim/toplulaştırma çıkarımı) tamamen
#           KALDIRILMIŞTIR.
#
#           Kipler (`MERGEN_PK_NUMERIC_PROVENANCE_MODE`):
#             off   -> referanslar çözülür (sayılar R'den gelir); telemetri ve
#                      görünür işaret YOK.
#             log   -> referanslar çözülür; sorunlar YALNIZCA sunucuya yazılır.
#                      Kullanıcı yanıtı DEĞİŞMEDEN alır. VARSAYILANDIR ve
#                      işletimsel güvenlik ağıdır.
#             warn  -> `log` + kullanıcıya görünen, sınırlı bir doğrulama notu.
#             block -> sorunlu İDDİA düzeyinde ayıklanır (yalnızca sorunlu
#                      cümleler düşer). Geriye kullanılabilir içerik kalmazsa
#                      deterministik özet gösterilir.
#
#           HİÇBİR KİPTE uydurma değer basılmaz ve yetkisiz/bilinmeyen bir
#           kimlik değer üretmez; kapalı başarısızlık kipten BAĞIMSIZDIR.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

PK_PROV_MODES <- c("off", "log", "warn", "block")

# Tipli bulgu sınıfları. Protokol/taşıma sorunları ile ESASA ilişkin güven
# sorunları AYRI raporlanır: tek bir "uyuşmazlık oranı" üretimde yanıltıcıydı
# (13 biçim kusuru + 3 gerçek sorun aynı orana giriyordu).
PK_PROV_PROTOCOL_REASONS <- c("malformed_reference", "legacy_reference",
                              "model_numeric_literal", "duplicate_numeric_literal",
                              "render_degraded")
PK_PROV_TRUST_REASONS <- c("unknown_fact", "unavailable_fact", "ambiguous_fact",
                           "unit_conflict")

# Kullanıcıya görünen (yalnızca `warn`) kısa Türkçe karşılıklar. Ham değer,
# satır verisi ya da olgu kimliği KULLANICIYA DA LOGA DA yazılmaz.
.PK_PROV_REASON_TR <- list(
  malformed_reference = "tanımsız olgu referansı",
  legacy_reference = "eski biçim referans işareti",
  model_numeric_literal = "kaynaksız sayısal ifade",
  duplicate_numeric_literal = "yinelenen sayısal ifade",
  render_degraded = "çözümleme bozulması",
  unknown_fact = "bilinmeyen olgu",
  unavailable_fact = "hesaplanamayan olgu",
  ambiguous_fact = "belirsiz olgu",
  unit_conflict = "olguyla uyuşmayan birim"
)

pk_numeric_provenance_mode <- function(query_meta = NULL) {
  if (!exists("pk_config_resolve", mode = "function", inherits = TRUE)) return("log")
  kip <- tryCatch(
    pk_config_resolve("MERGEN_PK_NUMERIC_PROVENANCE_MODE", query_meta = query_meta),
    error = function(e) "log"
  )
  if (!is.character(kip) || length(kip) != 1L || !(kip %in% PK_PROV_MODES)) return("log")
  kip
}

.pk_prov_scalar <- function(x) {
  txt <- suppressWarnings(as.character(x %||% "")[1])
  if (length(txt) != 1L || is.na(txt)) "" else txt
}

#' Model metnindeki olgu referanslarını çöz ve tipli bulguları üret
#'
#' Saf fonksiyondur ve kip OKUMAZ; kip kararı `pk_numeric_provenance_apply()`
#' içindedir.
#'
#' @return `list(kept=, strict=, resolved=, references=, findings=,
#'   protocol=, trust=)`
pk_numeric_provenance_validate <- function(text, facts) {
  index <- pk_facts_index(facts)
  guvenilir <- pk_fact_trusted_input_keys(facts)
  ham <- .pk_prov_scalar(text)

  sayilar <- pk_fact_literal_scan(ham, guvenilir)
  sonuc <- pk_fact_reference_render(ham, index, sayilar)

  nedenler <- vapply(sonuc$findings, function(b) as.character(b$reason)[1], character(1))
  c(sonuc, list(
    protocol = sum(nedenler %in% PK_PROV_PROTOCOL_REASONS),
    trust = sum(nedenler %in% PK_PROV_TRUST_REASONS)
  ))
}

# `warn` kipinin görünür notu: yalnızca KATEGORİ ve SAYAÇ. Hangi sayının
# hangi olguya ait olduğu yazılmaz; ham iş değeri sızmaz.
.pk_prov_warn_note <- function(findings) {
  nedenler <- vapply(findings, function(b) as.character(b$reason)[1], character(1))
  if (!length(nedenler)) return("")
  tablo <- table(nedenler)
  parcalar <- vapply(names(tablo), function(n) {
    etiket <- .PK_PROV_REASON_TR[[n]] %||% n
    sprintf("%s (%d)", etiket, as.integer(tablo[[n]]))
  }, character(1), USE.NAMES = FALSE)

  # KAYNAKSIZ SAYI GÖRÜNÜR KALIYORSA "sayılar R'den" DENMEZ: `warn` kipi modelin
  # yazdığı sayıyı metinde bırakır; o sayıyı doğrulanmış gibi sunmak yanlıştı.
  kaynaksiz <- any(nedenler %in% c("model_numeric_literal", "render_degraded"))
  paste0(
    "\n\n\U000026A0\U0000FE0F **Doğrulama notu:** Bu yanıtta bazı ",
    "ifadeler analiz olgularına bağlanamadı: ",
    paste(sort(parcalar), collapse = ", "), ". ",
    if (kaynaksiz) "Metindeki bazı sayılar doğrulanmamıştır; " else
      "Gösterilen sayısal değerler R tarafından hesaplanmıştır; ",
    "kritik kararlarda ekteki deterministik tabloyu esas alın."
  )
}

# `block` kipinde geriye kullanılabilir içerik kalmadığında gösterilen metin.
.pk_prov_block_fallback <- function(fallback_text) {
  yedek <- .pk_prov_scalar(fallback_text)
  paste0(
    "\U000026A0\U0000FE0F **Yanıt doğrulanamadı:** Üretilen ",
    "açıklamadaki ifadeler hesaplanan olgulara bağlanamadı; ",
    "açıklama gösterilmiyor. Aşağıdaki değerler R ",
    "tarafından hesaplanmıştır.",
    if (nzchar(yedek)) paste0("\n\n", yedek) else ""
  )
}

# Çözümleyici uç durumda düşerse: kalibrasyon kipleri (off/log) kullanıcıya
# görünen yanıtı DEĞİŞTİRMEZ, zorlama kipleri (warn/block) kapalı başarısız olur.
# Kapalı başarısızlık KİPTEN BAĞIMSIZDIR: hiçbir kipte çözülmemiş bir referans
# basılmaz.
.pk_prov_degraded_result <- function(ham, kip, fallback_text) {
  bulgu <- list(list(reason = "render_degraded", category = "protocol",
                     fact_id = NA_character_))
  # ORAN ESASA İLİŞKİNDİR: sıfır referanslı bir protokol bozulması `1.000`
  # güven oranı raporlayıp metrik sözleşmesini bozuyordu.
  temel <- list(mode = kip, checked = 0L, references = 0L, resolved = 0L,
                mismatches = bulgu, protocol = 1L, trust = 0L, rate = 0,
                degraded = TRUE)

  # YUVA JETONU KULLANICIYA ULAŞMAZ: çözümleyici düştüğünde bile jetonların
  # yerine nötr metin konur; aksi hâlde `log` kipinde sayının durması gereken
  # HER noktada iç söz dizimi (`{{fact:...}}`) görünüyordu.
  notr <- tryCatch(pk_fact_reference_neutralize(ham, strict = TRUE),
                   error = function(e) "")

  if (kip %in% c("off", "log")) {
    return(c(list(text = notr, blocked = FALSE), temel))
  }
  if (identical(kip, "warn")) {
    return(c(list(text = paste0(notr, .pk_prov_warn_note(bulgu)), blocked = FALSE),
             temel))
  }
  c(list(text = .pk_prov_block_fallback(fallback_text), blocked = TRUE), temel)
}

#' Kipi uygula ve kullanıcıya gösterilecek metni üret
#'
#' @param fallback_text `block` kipinde kullanılabilir içerik kalmazsa
#'   gösterilecek deterministik metin.
pk_numeric_provenance_apply <- function(text, facts, mode = NULL, fallback_text = NULL) {
  kip <- as.character(mode %||% pk_numeric_provenance_mode())[1]
  if (length(kip) != 1L || is.na(kip) || !(kip %in% PK_PROV_MODES)) kip <- "log"

  ham <- .pk_prov_scalar(text)

  # KAPALI BAŞARISIZLIK: bozuk bir olgu/metadata uç durumu çözümleyiciyi
  # düşürürse `log` kipi YİNE kullanıcıya bir yanıt verir (işletimsel güvenlik
  # ağı), `block` kipi ise deterministik yedeğe iner.
  sonuc <- tryCatch(pk_numeric_provenance_validate(ham, facts), error = function(e) {
    cat(sprintf("[PK_ANALIZ] Olgu referansi cozumlemesi hata verdi: %s\n",
                conditionMessage(e)))
    NULL
  })
  if (is.null(sonuc)) return(.pk_prov_degraded_result(ham, kip, fallback_text))

  bulgular <- sonuc$findings %||% list()
  sayilan <- as.integer(sonuc$references %||% 0L) +
    sum(vapply(bulgular, function(b) {
      isTRUE(as.character(b$reason)[1] %in% c("model_numeric_literal",
                                              "duplicate_numeric_literal"))
    }, logical(1)))

  temel <- list(
    mode = kip,
    checked = sayilan,
    references = as.integer(sonuc$references %||% 0L),
    resolved = as.integer(sonuc$resolved %||% 0L),
    mismatches = bulgular,
    protocol = as.integer(sonuc$protocol %||% 0L),
    trust = as.integer(sonuc$trust %||% 0L),
    # ORAN ARTIK ESASA İLİŞKİNDİR: biçim/protokol kusurları bu oranı
    # ŞİŞİRMEZ. Protokol sayacı ayrı alanda raporlanır.
    rate = if (sonuc$references > 0L) sonuc$trust / sonuc$references else 0,
    degraded = FALSE
  )

  if (identical(kip, "block")) {
    kati <- .pk_prov_scalar(sonuc$strict)
    if (!nzchar(trimws(kati))) {
      return(c(list(text = .pk_prov_block_fallback(fallback_text), blocked = TRUE),
               temel))
    }
    return(c(list(text = kati, blocked = FALSE), temel))
  }

  # KURTARILABİLİR BULGU KULLANICIYA "BAĞLANAMADI" DEDİRTMEZ. Çözülmüş bir
  # yuvanın yanındaki yinelenen sayı/işaret silinir ve hiçbir yanlış değer
  # yayımlanmaz; not yalnızca telemetriye girer.
  gorunur <- Filter(function(b) !isTRUE(b$recoverable), bulgular)
  if (identical(kip, "warn") && length(gorunur)) {
    return(c(list(text = paste0(sonuc$kept, .pk_prov_warn_note(gorunur)),
                  blocked = FALSE), temel))
  }

  c(list(text = sonuc$kept, blocked = FALSE), temel)
}

.PK_PROV_REPORT_MAX_IDS <- 8L

#' Ölçülen bulguları sunucu tarafında raporla (sırsız)
#'
#' PROTOKOL/YAPI ile İÇERİK/GÜVEN bulguları AYRI sayaçlarla yazılır. Tek bir
#' toplu oran üretimde yanıltıcıydı: `uyusmazlik=16 oran=0.286` değerinin 13
#' biçim kusuru + 3 gerçek sorun anlamına geldiği görünmüyordu.
#'
#' Düzyazı, soru metni, iddia edilen/gerçek DEĞERLER ve satır verisi LOGA
#' GİRMEZ; olgu kimliği bir şema tanımlayıcısıdır, veri değeri değildir.
pk_numeric_provenance_report <- function(result, query_id = NULL) {
  if (!is.list(result)) return(invisible(NULL))
  if (identical(as.character(result$mode %||% "")[1], "off")) return(invisible(result))

  bulgular <- result$mismatches %||% list()
  nedenler <- vapply(bulgular, function(b) as.character(b$reason %||% "?")[1],
                     character(1))

  dagilim <- function(kume) {
    alt <- nedenler[nedenler %in% kume]
    if (!length(alt)) return("-")
    tablo <- table(alt)
    paste(sprintf("%s=%d", names(tablo), as.integer(tablo)), collapse = " ")
  }

  kimlikler <- vapply(bulgular, function(b) {
    if (!(as.character(b$reason %||% "")[1] %in% PK_PROV_TRUST_REASONS)) {
      return(NA_character_)
    }
    as.character(b$fact_id %||% NA_character_)[1]
  }, character(1))
  kimlikler <- unique(kimlikler[!is.na(kimlikler) & nzchar(kimlikler)])
  kimlik_ozeti <- if (!length(kimlikler)) {
    "-"
  } else {
    paste0(paste(utils::head(kimlikler, .PK_PROV_REPORT_MAX_IDS), collapse = ","),
           if (length(kimlikler) > .PK_PROV_REPORT_MAX_IDS) ",..." else "")
  }

  cat(sprintf(
    paste0("[PK_ANALIZ] Olgu referansi | kip=%s | sorgu=%s | referans=%d | ",
           "cozulen=%d | protokol=%d | guven=%d | guven_orani=%.3f | ",
           "protokol_dagilim=%s | guven_dagilim=%s | olgular=%s\n"),
    result$mode %||% "?", as.character(query_id %||% "?")[1],
    as.integer(result$references %||% 0L), as.integer(result$resolved %||% 0L),
    as.integer(result$protocol %||% 0L), as.integer(result$trust %||% 0L),
    as.numeric(result$rate %||% 0),
    dagilim(PK_PROV_PROTOCOL_REASONS), dagilim(PK_PROV_TRUST_REASONS),
    kimlik_ozeti
  ))

  invisible(result)
}
