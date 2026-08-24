# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_requirements.R
# Açıklama: Faz 5 (§5.2) — Geçiş B `requirements` nesnesinin KATI
#           normalleştirilmesi ve yetenek kayıt defterine karşı doğrulanması.
#
# İki ayrı sorumluluk vardır ve bilinçli olarak ayrılmıştır:
#   1. NORMALLEŞTİRME (`pk_select_normalize_requirements`): modelin gönderdiği
#      nesnenin ŞEKLİ sözleşmeye uyuyor mu? Uymuyorsa cevap BOZUKTUR ve onarım
#      denemesi anlamlıdır.
#   2. DOĞRULAMA (`pk_select_validate_requirements`): şekli doğru olan iddia,
#      SEÇİLEN SORGU tarafından gerçekten karşılanıyor mu?
#
# `requirements` ARTIK ZORUNLUDUR. Eskiden eksik/liste olmayan bir değer sessizce
# `NULL`a çevriliyor, aşağı akış bunu "iddia yok" sayıyor ve yetenek kapısı
# tamamen atlanabiliyordu. Sözleşmeye uymayan bir cevap artık bozuk sayılır.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# `requirements` içinde İZİN VERİLEN alanlar. Bilinmeyen bir alan (ör. `measure`
# yerine `measures` yazılmaması) sessizce yok sayılmaz: yazım hatası, iddianın
# TAMAMEN kaybolması demektir ve kapı boşa çalışır.
.PK_SELECT_REQ_FIELDS <- c(
  "entity", "measures", "dates", "dimensions", "group_by", "unsupported"
)

# Yetenek kimliği taşıyan (kayıt defterine karşı doğrulanan) alanlar.
.PK_SELECT_REQ_CAPABILITY_FIELDS <- c("measures", "dates", "dimensions", "group_by")

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
  trimws(adlar[!is.na(adlar) & nzchar(trimws(adlar))])
}

#' Yetenek kimliği -> rol eşlemesi (istem için)
#'
#' Kayıt defteri rolü taşır ama Geçiş B'ye yalnızca çıplak kimlik listesi
#' gönderiliyordu. Kimliğin rolü kendi metninden ÇIKARILAMAZ (operatör
#' tanımlıdır), bu yüzden model doğru alanı seçemiyor ve geçerli bir aday
#' `capability_missing` ile reddediliyordu.
pk_select_capability_roles <- function(registry = NULL) {
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
  gecerli <- !is.na(adlar) & nzchar(trimws(adlar))
  adlar <- trimws(adlar[gecerli])

  roller <- vapply(registry[gecerli], function(kayit) {
    rol <- if (is.list(kayit)) kayit$role else NULL
    if (is.null(rol) || !length(rol) || is.na(rol[1])) return(NA_character_)
    trimws(as.character(rol)[1])
  }, character(1), USE.NAMES = FALSE)

  stats::setNames(roller, adlar)
}

.pk_select_req_array <- function(container, field) {
  if (!(field %in% names(container))) return(list(ok = TRUE, values = character(0)))

  deger <- container[[field]]
  if (is.null(deger)) return(list(ok = TRUE, values = character(0)))

  dizi <- pk_select_string_array(deger)
  if (!isTRUE(dizi$ok)) return(list(ok = FALSE, values = character(0)))

  list(ok = TRUE, values = unique(dizi$values))
}

#' `requirements` nesnesini KATI biçimde normalleştir
#'
#' @return `ok`, `error` ve `value` alanlı liste. `value`, doğrulayıcıya
#'   verilebilecek temiz bir nesnedir.
pk_select_normalize_requirements <- function(raw) {
  bos <- list(
    entity = NA_character_, measures = character(0), dates = character(0),
    dimensions = character(0), group_by = character(0), unsupported = character(0)
  )

  if (is.null(raw)) {
    return(list(ok = FALSE, value = bos,
                error = "Geçiş B 'requirements' nesnesi zorunludur; eksik."))
  }
  if (!is.list(raw)) {
    return(list(ok = FALSE, value = bos,
                error = "Geçiş B 'requirements' alanı bir JSON nesnesi olmalıdır."))
  }

  adlar <- names(raw)
  if (length(raw) && (is.null(adlar) || any(is.na(adlar) | !nzchar(trimws(adlar))))) {
    return(list(ok = FALSE, value = bos,
                error = "Geçiş B 'requirements' adlandırılmış bir nesne olmalıdır."))
  }
  adlar <- adlar %||% character(0)

  bilinmeyen <- setdiff(adlar, .PK_SELECT_REQ_FIELDS)
  if (length(bilinmeyen)) {
    return(list(ok = FALSE, value = bos, error = sprintf(
      "Geçiş B 'requirements' bilinmeyen alan içeriyor: %s",
      paste(bilinmeyen, collapse = ", ")
    )))
  }

  cikti <- bos
  for (alan in c(.PK_SELECT_REQ_CAPABILITY_FIELDS, "unsupported")) {
    dizi <- .pk_select_req_array(raw, alan)
    if (!isTRUE(dizi$ok)) {
      return(list(ok = FALSE, value = bos, error = sprintf(
        "Geçiş B 'requirements$%s' alanı düz bir metin dizisi olmalıdır.", alan
      )))
    }
    cikti[[alan]] <- dizi$values
  }

  # BOŞ `requirements` NESNESİ KABUL EDİLMEZ.
  #
  # `"requirements": {}` geldiğinde doğrulayıcı yetenek kaydı denetimini
  # tamamen ATLIYOR ve seçilen sorgu hiçbir yetenek iddiası olmadan
  # ilerleyebiliyordu. Geçiş B ya BEYAN eder ya da nesneyi hiç göndermez;
  # gönderilen boş nesne SÖZLEŞME İHLALİDİR.
  if (length(raw) == 0L) {
    return(list(ok = FALSE, value = bos, error = paste0(
      "Geçiş B 'requirements' nesnesi boş olamaz; en az bir yetenek alanı ",
      "beyan edilmeli ya da alan hiç gönderilmemelidir."
    )))
  }

  varlik <- pk_select_nullable_text(raw, "entity")
  if (identical(varlik$state, "invalid")) {
    return(list(ok = FALSE, value = bos, error = paste0(
      "Geçiş B 'requirements$entity' alanı tek bir metin ya da null olmalıdır."
    )))
  }
  cikti$entity <- varlik$value

  list(ok = TRUE, value = cikti, error = NA_character_)
}

#' TOLERANSLI görünüm — doğrulama tarafı için
#'
#' Katılık AYRIŞTIRICININ işidir (`pk_select_normalize_requirements`). Doğrulayıcı
#' hem ayrıştırıcının ürettiği normalleştirilmiş nesneyle hem de doğrudan
#' çağrılarla (testler, gelecekteki iç kullanıcılar) çalışabilmelidir; bu yüzden
#' burada YENİDEN katı doğrulama yapılmaz, yalnızca ortak şekle indirgenir.
#' Fonksiyon İDEMPOTENTTİR: normalleştirilmiş bir nesne aynen geri döner.
.pk_select_req_view <- function(requirements) {
  bos <- list(
    entity = NA_character_, measures = character(0), dates = character(0),
    dimensions = character(0), group_by = character(0), unsupported = character(0)
  )
  if (!is.list(requirements)) return(bos)

  for (alan in c(.PK_SELECT_REQ_CAPABILITY_FIELDS, "unsupported")) {
    deger <- requirements[[alan]]
    if (is.null(deger)) next
    if (is.list(deger)) deger <- unlist(deger, use.names = FALSE)
    deger <- trimws(as.character(deger))
    bos[[alan]] <- unique(deger[!is.na(deger) & nzchar(deger)])
  }

  varlik <- requirements$entity
  if (!is.null(varlik) && length(varlik) == 1L && !is.na(varlik[1])) {
    metin <- trimws(as.character(varlik)[1])
    if (nzchar(metin) && !identical(tolower(metin), "null")) bos$entity <- metin
  }

  bos
}

#' `unsupported` alanını normalleştir (SERBEST METİN ihtiyaç listesi)
#'
#' Hem normal karar yolu hem de ÇİP ONAYI yolu aynı kapıya bakar; alan liste ya
#' da karakter vektörü olabilir. Tek sahip burasıdır.
pk_select_unsupported_needs <- function(requirements) {
  if (!is.list(requirements)) return(character(0))
  ham <- requirements$unsupported %||% character(0)
  if (is.list(ham)) ham <- unlist(ham, use.names = FALSE)
  ham <- trimws(as.character(ham))
  unique(ham[!is.na(ham) & nzchar(ham)])
}

#' Normalleştirilmiş iddia BOŞ mu (doğrulanacak bir şey var mı)?
pk_select_requirements_empty <- function(requirements) {
  gorunum <- .pk_select_req_view(requirements)
  iddia <- unlist(gorunum[.PK_SELECT_REQ_CAPABILITY_FIELDS], use.names = FALSE)
  !length(iddia) && is.na(gorunum$entity)
}

#' Normalleştirilmiş `requirements` iddiasını SEÇİLEN SORGUYA karşı doğrula
#'
#' Ayrı ayrı raporlanan başarısızlıklar:
#'   * `unknown_capability` — kayıt defterinde OLMAYAN kimlik (model hatası;
#'     onarım denemesi anlamlıdır),
#'   * `capability_missing`  — kimlik geçerli ama SORGU onu sunmuyor (başka
#'     sorgu gerekir),
#'   * `validator_error`     — doğrulayıcı yüklenmedi ya da çöktü (SİSTEM
#'     kusuru; metadata doldurmak düzeltmez).
#' @param registry Yetenek kayıt defteri. `NULL` çalışma zamanındaki
#'   `pk_capability_registry`yi okur; testler TUTARLI bir defter enjekte eder.
pk_select_validate_requirements <- function(query, requirements, capability_ids = NULL,
                                            registry = NULL) {
  if (is.null(capability_ids)) capability_ids <- pk_select_capability_ids(registry)

  bos <- list(status = "not_asserted", asserted = FALSE,
              unknown = character(0), missing = character(0),
              columns = list(), canonicalized = character(0), errors = character(0))

  if (!is.list(requirements)) return(bos)

  requirements <- .pk_select_req_view(requirements)
  if (pk_select_requirements_empty(requirements)) return(bos)

  # VARLIK -> SAYIM kanonikleştirmesi (deterministik ima; ayrıntı ve kapalı
  # başarısızlık kuralları `R/helpers_pk_query_selection_canonical.R` içinde).
  kanon <- pk_select_apply_canonicalization(query, requirements, capability_ids, registry)
  requirements <- .pk_select_req_view(kanon$requirements)
  kanonik <- kanon$mappings

  istenen <- unique(unlist(
    requirements[.PK_SELECT_REQ_CAPABILITY_FIELDS], use.names = FALSE
  ))
  istenen <- istenen[!is.na(istenen) & nzchar(istenen)]

  bilinmeyen <- setdiff(istenen, capability_ids)
  if (length(bilinmeyen)) {
    return(list(
      status = "unknown_capability", asserted = TRUE,
      unknown = bilinmeyen, missing = character(0), columns = list(),
      canonicalized = kanonik,
      errors = sprintf(
        "İzinli olmayan yetenek kimliği: %s", paste(bilinmeyen, collapse = ", ")
      )
    ))
  }

  if (!exists("pk_meta_capability_check", mode = "function", inherits = TRUE)) {
    return(list(
      status = "validator_error", asserted = TRUE,
      unknown = character(0), missing = istenen, columns = list(),
      canonicalized = kanonik,
      errors = "Yetenek doğrulayıcısı yüklenmedi; anlamsal iddia doğrulanamadı."
    ))
  }

  temiz <- .pk_select_capability_payload(requirements)

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
      canonicalized = kanonik,
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
      columns = kontrol$columns %||% list(), canonicalized = kanonik,
      errors = sprintf(
        "Seçilen sorgu şu anlamsal yetenekleri sunmuyor: %s",
        paste(eksik, collapse = ", ")
      )
    ))
  }

  list(
    status = "ok", asserted = TRUE,
    unknown = character(0), missing = character(0),
    columns = kontrol$columns %||% list(), canonicalized = kanonik,
    errors = character(0)
  )
}

#' Doğrulayıcıya gidecek yükü kur — BEYAN EDİLEN ROL KORUNUR
#'
#' `pk_meta_capability_check()` her `group_by` değerini KOŞULSUZ `dimensions`
#' kovasına katar ve `dimension` rolü bekler. Metadata sözleşmesi tarih
#' sütunlarının gruplama anahtarı olmasına izin verdiği için, geçerli bir
#' `dates = ["date.project_start"]` + `group_by = ["date.project_start"]`
#' isteği "çoklu rol" sayılıp DETERMİNİSTİK biçimde reddediliyordu. Bu yüzden
#' başka bir rol altında ZATEN beyan edilmiş gruplama anahtarları doğrulayıcıya
#' ikinci kez gönderilmez; rolleri kendi alanlarından doğrulanır.
.pk_select_capability_payload <- function(requirements) {
  # BASTIRMA KÜMESİ YALNIZCA TARİH VE BOYUT BEYANLARIDIR.
  #
  # Yukarıdaki gerekçe SADECE tarih durumunu haklı çıkarır. `measures` de
  # kümeye katıldığında, bir ölçü yeteneğini tekrarlayan `group_by` girdisi
  # doğrulamadan ÖNCE siliniyor; `pk_meta_capability_check()` o yetenek için
  # gruplama anlambilimini HİÇ doğrulamıyor ve sorgu, istenen kırılımı
  # üretemese bile otomatik seçilebiliyordu.
  zaten <- unique(c(requirements$dates, requirements$dimensions))
  zaten <- zaten[!is.na(zaten) & nzchar(zaten)]

  gruplama <- setdiff(requirements$group_by, zaten)

  temiz <- list(
    measures   = as.character(requirements$measures),
    dates      = as.character(requirements$dates),
    dimensions = as.character(requirements$dimensions),
    group_by   = as.character(gruplama)
  )
  if (!is.na(requirements$entity)) temiz$entity <- requirements$entity
  temiz
}
