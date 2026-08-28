# ==============================================================================
# Dosya Yolu: R/helpers_pk_telemetry.R
# Açıklama: Telemetri DB katmanı için uyumluluk yüzeyi. Temel fail-soft yazım
#           helpers_pk_telemetry_base.R içinde korunur; bu dosya gözlem anında
#           gerçek filtre yürütme bilgisini, kullanıcı kimliğini ve
#           yapılandırılmış motoru uygular.
# ==============================================================================

# TABAN DOSYA MANIFESTTEN YUKLENIR; DINAMIK `source()` YOKTUR.
#
# Onceki surum `sys.frame()` icinde `ofile` tarayip goreli yol adaylari
# deneyerek `helpers_pk_telemetry_base.R` dosyasini KENDISI source ediyordu.
# Depo kurali calisma zamani R dosyalarinin ACIK kaynak manifestinden
# yuklenmesini ve gizli/dinamik source ile bagimlilik sirasinin atlanmamasini
# gerektirir; ayrica yukleme `safe_source()` uzerinden gecmelidir. Manifest
# (`R/config_source_manifest.R`, `pk_telemetry` sirasi) taban dosyayi bu
# dosyadan ONCE yukler. Izole test/hata ayiklama oturumlari taban dosyayi
# kendi kaynak listelerine EKLER (bkz. test-pk-telemetry-*-contract.R).
if (!exists("pk_telemetry_log_analysis", mode = "function", inherits = TRUE)) {
  stop(
    "helpers_pk_telemetry_base.R yuklenmemis; ",
    "R/helpers_pk_telemetry.R oncesinde manifestten yuklenmelidir.",
    call. = FALSE
  )
}

.pk_observation_query_meta <- function(info, filter_observation = NULL) {
  if (is.list(info$query_meta)) return(info$query_meta)
  if (is.list(filter_observation$query_meta)) return(filter_observation$query_meta)
  if (!exists("query_library", inherits = TRUE)) return(NULL)

  library <- get("query_library", inherits = TRUE)
  if (!is.list(library) || length(library) == 0L) return(NULL)

  query_id <- as.character(info$query_id %||% "")[1]
  query_name <- as.character(info$query_name %||% "")[1]

  for (candidate in library) {
    if (!is.list(candidate)) next

    candidate_id <- as.character(candidate$id %||% "")[1]
    candidate_name <- as.character(candidate$name %||% "")[1]

    if ((nzchar(query_id) && identical(candidate_id, query_id)) ||
        (nzchar(query_name) && identical(candidate_name, query_name))) {
      return(candidate)
    }
  }

  NULL
}

.pk_dropped_filter_degradations <- function(dropped_filters) {
  if (!is.list(dropped_filters) || length(dropped_filters) == 0L) return(list())

  details <- vapply(dropped_filters, function(item) {
    # `%||%` YALNIZCA `NULL` ATLAR: `item` ya da `item$filter` atomik bir vektör
    # olduğunda `filter$column` "$ operator is invalid for atomic vectors" ile
    # hata verir ve TÜM zenginleştirme (gerçek filtre gözlemi, oturum
    # `user_id`'si, düzeltilmiş `filter_status`, bozulmalar) düşerdi.
    filter <- if (is.list(item) && is.list(item$filter)) item$filter else list()
    column <- as.character(filter$column %||% "?")[1]
    value <- paste(as.character(filter$value %||% ""), collapse = ", ")
    # `item$reason` DA AYNI KORUMAYA TABİDİR: `item` atomik bir vektörse `$`
    # yine "invalid for atomic vectors" hatası verir ve zenginleştirme düşer.
    reason <- as.character((if (is.list(item)) item$reason else NULL) %||% "uygulanamadı")[1]
    sprintf("%s=\"%s\" (%s)", column, value, reason)
  }, character(1))

  list(list(
    code = "filter_dropped",
    message = paste0(
      "Bazı filtreler veri kümesine uygulanamadı ve analizden çıkarıldı: ",
      paste(details, collapse = " · "),
      "."
    )
  ))
}

.pk_observation_session_user_id <- function(session) {
  value <- tryCatch(session$userData$user_id, error = function(e) NULL)
  if (is.null(value) || length(value) == 0L) return(NULL)

  value <- suppressWarnings(as.integer(value)[1])
  if (is.na(value)) NULL else value
}

# Gözlem zenginleştirme: filtre gözlemi, motor etiketi, durum ve bozulmalar.
# FAIL-SOFT'tur; hata verirse çağıran yine de yanıtı teslim eder.
#' Çağıranın bildirdiği ek bozulmaları normalleştir
.pk_observation_extra_degradations <- function(x) {
  if (is.null(x) || !length(x)) return(list())

  metinler <- if (is.list(x)) {
    vapply(x, function(d) {
      deger <- if (is.list(d)) d$message else d
      if (is.null(deger) || !length(deger) || is.na(deger[1])) NA_character_
      else as.character(deger)[1]
    }, character(1), USE.NAMES = FALSE)
  } else {
    as.character(x)
  }

  metinler <- metinler[!is.na(metinler) & nzchar(trimws(metinler))]
  if (!length(metinler)) return(list())

  lapply(metinler, function(m) list(code = "selection_degraded", message = m))
}

.pk_observation_enrich <- function(session, info) {
  if (is.null(info$user_id) || length(info$user_id) == 0L ||
      is.na(suppressWarnings(as.integer(info$user_id)[1]))) {
    info$user_id <- .pk_observation_session_user_id(session)
  }

  filter_observation <- if (exists("pk_filter_observation_take", mode = "function", inherits = TRUE)) {
    tryCatch(pk_filter_observation_take(info), error = function(e) NULL)
  } else {
    NULL
  }

  dropped_degradations <- list()
  if (is.list(filter_observation)) {
    info$filtered_rows <- filter_observation$matched_rows %||% info$filtered_rows
    info$filters <- filter_observation$applied_filters %||% list()
    dropped_degradations <- .pk_dropped_filter_degradations(
      filter_observation$dropped_filters %||% list()
    )

    if (length(info$filters %||% list()) > 0L &&
        identical(info$filter_status, "ok_no_filter")) {
      info$filter_status <- "ok_filtered"
    }

    # Tüm filtreler düşürüldüyse sonuç bozulmuştur. "ok_no_filter" da buraya
    # dâhildir: yalnızca filter_expression dönen ve değerlendirmesi başarısız
    # olan istekte alt bilgi aksi halde hem "soru genel olarak yorumlandı" der
    # hem de düşürülen filtre uyarısı gösterirdi; FiltreDurumu ise meşru bir
    # filtresiz sonuç gibi yazılırdı. timeout/error/stopped/not_reached/disabled
    # daha özgül bilgidir ve ezilmez.
    if (length(info$filters %||% list()) == 0L &&
        length(filter_observation$dropped_filters %||% list()) > 0L &&
        isTRUE(info$filter_status %in% c("ok_filtered", "ok_no_filter"))) {
      info$filter_status <- "malformed"
    }
  }

  query_meta <- .pk_observation_query_meta(info, filter_observation)
  # ÇAĞIRANIN AÇIKÇA BİLDİRDİĞİ MOTOR EZİLMEZ: `"v1"` DE açık bir bildirimdir.
  #
  # Eski koşul açık `"v1"` değerini de çözüm dalına sokuyordu; metadata'sı
  # motoru geçersiz kılan bir sorguda `pk_config_resolve()` `"v2"` döndürüyor ve
  # yanıtı v1 hattı ürettiği hâlde kayıt `v2` raporluyordu. Modül artık her
  # istekte motoru AÇIKÇA geçirdiği için bu dal yalnızca yanlış atfedebilirdi.
  if (!is.character(info$engine) || !nzchar(as.character(info$engine)[1])) {
    cozulen <- tryCatch(
      pk_config_resolve("MERGEN_PK_ENGINE", query_meta = query_meta),
      error = function(e) NULL
    )
    if (is.character(cozulen) && nzchar(cozulen[1])) info$engine <- cozulen[1]
  }

  # Çağıran, filtre hattı dışında oluşan bozulmaları da bildirebilir (ör. Faz 5
  # seçiminde sözlüksel uyuşmazlık nedeniyle güvenin düşürülmesi). Plan kuralı
  # açıktır: her bozulma yanıtta GÖRÜNMELİDİR; yalnızca loglara yazılan bir
  # zayıflatma, kullanıcı açısından hiç olmamış demektir.
  ek_bozulmalar <- .pk_observation_extra_degradations(info$extra_degradations)
  info$extra_degradations <- NULL

  status <- pk_filter_status_normalize(info$filter_status)
  # TELEMETRİ HAZIRLIK KARARI DB HEDEFİ BAŞINA ANAHTARLANIR.
  #
  # Etkin yürütme bağlamı OLMAYAN yollarda (işçi doğrudan-çıkışı, derin gözlem)
  # `.pk_telemetry_target_key()` her bağlantıyı `"primary"` sayıyordu:
  # önbelleğe alınmış bir birincil karar geçerli bir ikincil yazımı ATLAYABİLİR
  # ya da geçersiz bir `INSERT`i ikincil bağlantıda YİNELEYEBİLİRDİ. Hedef,
  # seçilen sorgunun metadata'sından burada çözülür.
  hedef <- as.character(info$db_target %||% query_meta$db_target %||% "")[1]
  list(
    info = info,
    status = status,
    db_target = if (is.na(hedef) || !nzchar(hedef)) NULL else hedef,
    degradations = c(
      pk_degradations_from_filter_status(status), dropped_degradations, ek_bozulmalar
    ),
    provenance_mode = tryCatch(pk_numeric_provenance_mode(query_meta), error = function(e) NULL)
  )
}

#' Bir analiz isteğini gözlemle: alt bilgiyi hazırla + telemetriyi yaz
#'
#' Bu bağdaştırıcı şu doğruluk garantilerini verir:
#'   1. toplulaştırılmış çıktı satırı yerine toplulaştırma öncesi eşleşen kayıt
#'      sayısını kullanır;
#'   2. yalnızca gerçekten uygulanan filtreleri gösterir ve düşürülenleri açıkça
#'      kullanıcıya/telemetriye bildirir;
#'   3. çağıran unutsa bile oturumdaki kimlik doğrulanmış user_id değerini
#'      KullaniciID alanına taşır;
#'   4. motor etiketi çağıranın çözdüğü değer -> sorgu metadata -> ortam ->
#'      option -> varsayılan önceliğiyle çözülür.
#'
#' ZORUNLU TESLİM ile FAIL-SOFT TELEMETRİ AYRIDIR: eskiden tek bir dış
#' `tryCatch` filtre gözlemini, alt bilgi kurulumunu, saklamayı ve telemetriyi
#' birlikte sarıyordu; saklamadan ÖNCEKİ herhangi bir hata boş dize döndürüyor
#' ve istek devam ederken R'ye ait tablo/ek eklenmiyor, sayısal köken hiç
#' uygulanmıyor, `[fact:...]` işaretleri ham düzyazıda kalabiliyordu.
pk_analysis_observe <- function(session, conn, info) {
  info <- if (is.list(info)) info else list()

  zengin <- tryCatch(.pk_observation_enrich(session, info), error = function(e) NULL)
  if (!is.list(zengin)) {
    zengin <- list(info = info,
                   status = tryCatch(pk_filter_status_normalize(info$filter_status),
                                     error = function(e) info$filter_status),
                   db_target = info$db_target,
                   degradations = list(), provenance_mode = NULL)
  }
  info <- zengin$info
  status <- zengin$status

  blok <- as.character(info$answer_block %||% "")[1]
  if (is.na(blok)) blok <- ""

  footer <- tryCatch(pk_build_provenance_footer(list(
    query_id        = info$query_id,
    query_name      = info$query_name,
    filter_status   = status,
    filters         = info$filters %||% list(),
    authorized_rows = info$authorized_rows,
    filtered_rows   = info$filtered_rows,
    degradations    = zengin$degradations,
    # Ek KARTI zaten R'ye ait blokta yer alıyorsa alt bilgiye TEKRAR yazılmaz;
    # aksi hâlde her ek-kipli v2 yanıtında aynı indirme/ret iki kez görünürdü.
    attachment      = if (nzchar(blok)) NULL else info$attachment
  )), error = function(e) "")

  if (!is.character(footer) || length(footer) != 1L || is.na(footer)) footer <- ""

  # Faz 2: R'ye ait yanıt bloğu (tablo/önizleme + ek kartı) alt bilginin
  # ÖNÜNE eklenir; olgular ve deterministik yedek metin ise §5.11 sayısal
  # köken doğrulaması için birlikte saklanır. Alt bilgi kurulamasa BİLE blok
  # teslim edilir.
  # OLGU VARSA KAYIT HER HÂLÜKÂRDA SAKLANIR: alt bilgi ve R'ye ait blok boş
  # olsa bile §5.11 doğrulaması çalışmalıdır; aksi hâlde doğrulanmamış model
  # düzyazısı `[fact:...]` işaretleriyle birlikte teslim edilirdi.
  if (nzchar(footer) || nzchar(blok) || !is.null(info$facts)) {
    try(pk_provenance_stash(
      session, paste0(blok, footer),
      request_id = info$request_id,
      facts = info$facts,
      fallback_text = info$fallback_text,
      query_id = info$query_id,
      mode = zengin$provenance_mode
    ), silent = TRUE)
  }

  info$filter_status <- status
  info$filter_count <- length(info$filters %||% list())
  info$degradation_codes <- vapply(
    zengin$degradations,
    function(d) as.character(d$code)[1],
    character(1)
  )

  # HEDEF AÇIKÇA GEÇİRİLİR: hazırlık kararı DB HEDEFİ başına anahtarlanır ve
  # etkin yürütme bağlamı olmayan yollarda da doğru hedefe düşer.
  try(pk_telemetry_log_analysis(info, conn, db_target = zengin$db_target),
      silent = TRUE)

  invisible(footer)
}
