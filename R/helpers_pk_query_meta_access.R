# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_meta_access.R
# Açıklama: Tier-0 yapısal çıkarım, HER TÜKETİCİ İÇİN belgelenmiş Tier-0 geri
#           düşüş yolları, tüketici erişimcileri, istek zamanı yetenek kapısı
#           ve ZORUNLU getirme-sonrası gerçek sütun doğrulaması.
#           Master plan §5.1 ve §8 "Phase 3a".
#
# Sözleşme:
#   * Dosya SAFTIR: Shiny/reactive/DB/ağ bağımlılığı yoktur.
#   * Geri düşüşlerin tamamı FAIL-CLOSED yöndedir: metadata yoksa araç daha AZ
#     şey yapar (toplamaz, bulanık eşleştirmez, filtrelemez), asla tahmin
#     ederek daha çok şey yapmaz.
#   * Tier-0 yalnızca YAPISAL çıkarım yapar. Anlamsal yetenek kimliği (bir
#     tarihin başlangıç mı bitiş mi, bir sayının planlanan mı kalan işçilik mi
#     olduğu) yapıdan ÇIKARILAMAZ; Tier-0 bunu asla uydurmaz.
#
# NOT (Faz 3a sınırı): `pk_meta_validate_actual_columns()` burada TANIMLIDIR ve
#   test edilir, ancak v1 çalışma zamanı akışına BAĞLANMAZ. Faz 3a saf
#   sözleşme/veri katmanıdır; RLS'in fail-closed hâle getirilmesi ve bu
#   doğrulamanın istek akışına takılması Faz 1/2'ye aittir (master plan §10,
#   motor sınırı sözleşmesi).
# ==============================================================================

# Yetenek gereksinimi karşılanamadığında dönen kararlı durum kodu.
PK_META_STATUS_NO_SEMANTICS <- "unknown_no_semantic_metadata"
PK_META_STATUS_OK <- "ok"

#' Tier-0 geri düşüşlerinin BELGELENMİŞ kaydı
#'
#' Her tüketici alanı için "metadata yoksa ne yapılır" kararını tek yerde
#' toplar. Test bu kaydı ADIYLA doğrular; böylece bir sonraki faz sessizce
#' kendi ad hoc yedeğini uyduramaz.
pk_meta_tier0_fallbacks <- function() {
  list(
    primary_entity = paste(
      "primary_entity yok -> tek filtre yapragi birincil kabul edilir;",
      "birden fazla yaprak varsa birincil varlik SECILMEZ."
    ),
    additive = paste(
      "additive yok -> toplama YAPILMAZ; olcu satir bazinda raporlanir."
    ),
    aggregate = "aggregate yok -> 'none' (satir bazinda), asla ortalama/toplam degil.",
    grain = "grain yok -> tekillestirme iddiasi yok; her satir kendi grain'idir.",
    grain_columns = "grain_columns yok -> mukerrer satir elemesi yapilmaz.",
    default_measures = "default_measures yok -> ortulu olcu secilmez.",
    default_group_by = "default_group_by yok -> ortulu gruplama yapilmaz.",
    row_cap = "row_cap yok -> MERGEN_PK_ROW_CAP genel degeri kullanilir.",
    unit = "unit yok -> sayiya birim eklenmez.",
    decimals = "decimals yok -> zorlamali yuvarlama yapilmaz.",
    match = "match yok -> 'none'; bulanik varlik cozumleme YAPILMAZ.",
    filterable = "filterable yok -> sutun filtrelenebilir SAYILMAZ (fail-closed).",
    domain = "domain yok -> kod/etiket cevirisi yapilmaz; ham deger gosterilir.",
    high_cardinality = "high_cardinality yok -> bilinmeyen (NA); dusuk kardinalite VARSAYILMAZ.",
    capability = paste(
      "capability yok -> anlamsal gereksinimli istek SQL'den ONCE",
      PK_META_STATUS_NO_SEMANTICS, "dondurur."
    )
  )
}

# R sınıfından yapısal rol çıkarımı. Anlam DEĞİL, yalnızca yapı.
.pk_meta_role_from_class <- function(tip) {
  tip <- tolower(as.character(tip)[1])

  if (tip %in% c("date", "posixct", "posixt", "posixlt", "datetime", "idate")) return("date")
  if (tip %in% c("numeric", "double", "integer", "int", "num", "integer64", "decimal", "float")) {
    return("measure")
  }

  "dimension"
}

#' Tier-0 yapısal `column_meta` üret
#'
#' @param schema Adlandırılmış karakter vektörü: sütun adı -> R sınıfı/tipi.
#'   (Bir `data.frame` de verilebilir; sınıfları kendisi çıkarılır.)
#' @return `column_meta` biçiminde liste. Yalnızca YAPISAL alanlar doldurulur.
pk_meta_tier0_column_meta <- function(schema) {
  if (is.data.frame(schema)) {
    tipler <- vapply(schema, function(s) class(s)[1], character(1))
    schema <- stats::setNames(as.character(tipler), names(schema))
  }

  if (is.null(schema) || !length(schema) || is.null(names(schema))) return(list())

  out <- list()

  for (sutun in names(schema)) {
    if (!nzchar(sutun)) next

    rol <- .pk_meta_role_from_class(schema[[sutun]])

    out[[sutun]] <- list(
      label = sutun,
      role = rol,
      # Tier-0 anlam uretmez: yetenek, birim, additive ve domain BILINMEZ.
      capability = NULL,
      # Fail-closed: bulanik eslesme ve filtre yetkisi verilmez.
      match = "none",
      filterable = FALSE,
      # Bir onek ornegi kardinalite/null/tanimlayici iddiasini KANITLAYAMAZ.
      high_cardinality = NA,
      tier = 0L,
      inferred_from = "structural_schema"
    )
  }

  out
}

# Bir sorgunun metadata listesini güvenli biçimde alır.
.pk_meta_of <- function(query) {
  if (is.null(query)) return(list())
  if (is.list(query) && is.list(query$meta)) return(query$meta)
  if (is.list(query)) return(query)
  list()
}

#' Birincil varlık sütunu (Tier-0 geri düşüşlü)
#'
#' @param filter_columns İstek içindeki filtre yapraklarının sütunları. Tek
#'   yaprak varsa birincil odur; birden fazlaysa birincil SEÇİLMEZ.
pk_meta_primary_entity <- function(query, filter_columns = character(0)) {
  meta <- .pk_meta_of(query)

  if (.pk_meta_is_scalar_text(meta$primary_entity)) return(trimws(meta$primary_entity))

  filter_columns <- unique(as.character(filter_columns %||% character(0)))
  filter_columns <- filter_columns[nzchar(filter_columns)]

  if (length(filter_columns) == 1L) return(filter_columns)

  NULL
}

#' Bir ölçünün toplama kipi (Tier-0 geri düşüşlü)
#'
#' `additive` bilinmiyorsa toplama YAPILMAZ. Bilinmeyen bir sütunu toplamak,
#' grain tekrarları yüzünden proje toplamlarını aktivite satırı sayısı kadar
#' şişirir; bu, planın "asla sessizce yanlış" kuralının tipik ihlalidir.
pk_meta_aggregate_for <- function(query, column) {
  cmeta <- .pk_meta_of(query)$column_meta[[column]]

  if (is.list(cmeta) && .pk_meta_is_scalar_text(cmeta$aggregate)) {
    return(cmeta$aggregate)
  }

  if (is.list(cmeta) && isTRUE(cmeta$additive)) return("sum")

  "none"
}

#' Sütunun eşleşme kipi (Tier-0 geri düşüşlü: bulanık eşleşme yok)
pk_meta_match_mode <- function(query, column) {
  cmeta <- .pk_meta_of(query)$column_meta[[column]]

  if (is.list(cmeta) && .pk_meta_is_scalar_text(cmeta$match)) return(cmeta$match)

  # Kod/kimlik sutunlari her kosulda tam eslesir.
  if (is.list(cmeta) && identical(cmeta$role, "id")) return("exact")

  "none"
}

#' Sütun filtrelenebilir mi (Tier-0 geri düşüşlü: hayır)
pk_meta_is_filterable <- function(query, column) {
  cmeta <- .pk_meta_of(query)$column_meta[[column]]
  is.list(cmeta) && isTRUE(cmeta$filterable)
}

#' Etkin satır tavanı
#'
#' Öncelik zinciri `pk_config_resolve()` içindedir: sorgu metadata (`row_cap`)
#' -> .Renviron -> options() -> yerleşik varsayılan. Burada sabit sayı YOKTUR.
pk_meta_row_cap <- function(query) {
  meta <- .pk_meta_of(query)

  if (!exists("pk_config_resolve", mode = "function")) {
    # Yapilandirma cozumleyicisi yuklenmemisse (izole test), metadata degeri
    # dogrudan okunur; yine de sabit sayi uydurulmaz.
    deger <- suppressWarnings(as.integer(meta$row_cap %||% NA))
    return(if (is.na(deger)) NULL else deger)
  }

  pk_config_resolve("MERGEN_PK_ROW_CAP", query_meta = meta)
}

#' İstek zamanı yetenek kapısı (SQL'den ÖNCE çalışır)
#'
#' Aday sorgu, isteğin talep ettiği anlamsal yetenekleri BEYAN ETMİYORSA
#' çalıştırma durur. Etiketten veya ham sütun adından tahmin YAPILMAZ.
#'
#' @param requirements `list(measures = , dates = , dimensions = )` — hepsi
#'   yetenek kimliği vektörüdür, sütun adı veya etiket değil.
pk_meta_capability_check <- function(query, requirements = list()) {
  meta <- .pk_meta_of(query)

  istenen <- unique(c(
    as.character(requirements$measures %||% character(0)),
    as.character(requirements$dates %||% character(0)),
    as.character(requirements$dimensions %||% character(0))
  ))
  istenen <- istenen[nzchar(istenen)]

  if (!length(istenen)) {
    return(list(status = PK_META_STATUS_OK, missing = character(0), columns = list()))
  }

  beyan <- pk_meta_declared_capabilities(query)
  eksik <- setdiff(istenen, names(beyan))

  if (length(eksik)) {
    return(list(
      status = PK_META_STATUS_NO_SEMANTICS,
      missing = eksik,
      columns = beyan[intersect(istenen, names(beyan))]
    ))
  }

  list(
    status = PK_META_STATUS_OK,
    missing = character(0),
    columns = beyan[istenen]
  )
}

#' Sorgunun beyan ettiği yetenek kimliği -> sütun eşlemesi
#'
#' Aynı yeteneği birden fazla sütun açığa çıkarıyorsa, metadata açık bir
#' varyant seçim kuralı (`capability_variants[[cap]]$prefer`) bildirmelidir;
#' aksi hâlde başlangıç doğrulaması zaten hata verir.
pk_meta_declared_capabilities <- function(query) {
  meta <- .pk_meta_of(query)
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar)) return(list())

  out <- list()

  for (sutun in names(sutunlar)) {
    cmeta <- sutunlar[[sutun]]
    if (!is.list(cmeta) || !.pk_meta_is_scalar_text(cmeta$capability)) next

    cap <- trimws(cmeta$capability)
    tercih <- meta$capability_variants[[cap]]$prefer

    if (.pk_meta_is_scalar_text(tercih)) {
      if (identical(tercih, sutun)) out[[cap]] <- sutun
      next
    }

    if (is.null(out[[cap]])) out[[cap]] <- sutun
  }

  out
}

#' ZORUNLU getirme-sonrası gerçek sütun doğrulaması (fail-closed)
#'
#' Başlangıçta şema yoksa doğrulama ERTELENİR; ama SQL döndükten sonra bu
#' kontrol KOŞULSUZDUR. Beyan edilmiş bir RLS sütunu gerçek sonuçta yoksa
#' istek daima kapanır (D6); şemanın başlangıçta olmaması tespiti geciktirir,
#' istek zamanı zorlamayı ASLA zayıflatmaz.
#'
#' @param actual_columns SQL'den dönen gerçek sütun adları.
#' @return `list(ok =, fail_closed =, missing_rls =, missing_declared =, errors =)`
pk_meta_validate_actual_columns <- function(query, actual_columns) {
  meta <- .pk_meta_of(query)
  gercek <- as.character(actual_columns %||% character(0))

  eksik_rls <- character(0)
  rls <- if (is.list(query)) query$rls_columns else NULL
  if (is.list(rls)) {
    for (alan in names(rls)) {
      deger <- rls[[alan]]
      if (!.pk_meta_is_scalar_text(deger)) next
      if (!(trimws(deger) %in% gercek)) eksik_rls <- c(eksik_rls, trimws(deger))
    }
  }

  beyan <- unique(c(
    names(meta$column_meta %||% list()),
    as.character(meta$grain_columns %||% character(0)),
    as.character(meta$default_group_by %||% character(0)),
    as.character(meta$default_measures %||% character(0)),
    if (.pk_meta_is_scalar_text(meta$primary_entity)) meta$primary_entity else character(0),
    .pk_meta_reference_columns(meta)
  ))
  beyan <- beyan[nzchar(beyan)]
  eksik_beyan <- setdiff(beyan, gercek)

  hatalar <- character(0)
  if (length(eksik_rls)) {
    hatalar <- c(hatalar, sprintf(
      "Beyan edilen RLS sutunu gercek sonucta yok: %s", paste(unique(eksik_rls), collapse = ", ")
    ))
  }
  if (length(eksik_beyan)) {
    hatalar <- c(hatalar, sprintf(
      "Beyan edilen metadata sutunu gercek sonucta yok: %s",
      paste(eksik_beyan, collapse = ", ")
    ))
  }

  list(
    ok = !length(hatalar),
    # Eksik RLS sutunu HER ZAMAN kapatir; diger eksikler de gecerli sayilmaz.
    fail_closed = length(eksik_rls) > 0L,
    missing_rls = unique(eksik_rls),
    missing_declared = eksik_beyan,
    errors = hatalar
  )
}

# Metadata içinde başka sütunlara yapılan atıflar (ağırlık, sıralama, eşitlik
# bozucu). Bunlar da gerçek sonuçta bulunmalıdır.
.pk_meta_reference_columns <- function(meta) {
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar)) return(character(0))

  out <- character(0)

  for (cmeta in sutunlar) {
    if (!is.list(cmeta)) next
    out <- c(
      out,
      as.character(cmeta$weight_by %||% character(0)),
      as.character(cmeta$latest_by %||% character(0)),
      as.character(cmeta$latest_tie_by %||% character(0))
    )
  }

  unique(out[nzchar(out)])
}
