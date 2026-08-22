# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_canonical.R
# Açıklama: Faz 5 (§5.2) — Geçiş B `requirements` iddiasının DETERMİNİSTİK
#           KANONİKLEŞTİRİLMESİ.
#
#           SORUN (üretim VM tekrar üretimi): Anlamsal olarak AYNI soru,
#           dilbilgisel biçimine göre farklı sonuçlanıyordu:
#             * "Kac geciken aktivite var?"        -> yetenek=ok
#             * "Toplam geciken aktivite sayisi?"  -> yetenek=ok
#             * "Geciken aktiviteler var mi?"      -> unknown_capability (RET)
#           Üçünde de AYNI sorgu %95 güvenle seçiliyordu. Fark, serbest biçimli
#           Geçiş B adımının VARLIK sorusunu ayrı bir yetenek kimliği gibi
#           uydurmasıydı (ör. `activity.delayed_exists`), oysa VARLIK zaten
#           beyan edilmiş bir SAYIM ölçüsünden (`count > 0`) deterministik
#           olarak türetilebilir.
#
#           ÇÖZÜM: kimlik SÖZLÜĞÜNE değil, kimlik YAPISINA dayanan bir ima
#           kuralı. Bir kimlik "VARLIK görünümlü" ise (varlık kipi jetonu
#           taşıyorsa) ve SEÇİLEN ADAYIN sunduğu SAYIM ölçülerinden TAM OLARAK
#           BİRİ aynı kavram anahtarına sahipse, iddia o SAYIM yeteneğine
#           kanonikleştirilir. Aksi hâlde HİÇBİR ŞEY değişmez ve kapı kapalı
#           kalır.
#
#           BU BİR EŞANLAMLI TABLOSU DEĞİLDİR: kullanıcı cümlesi, sorgu kimliği
#           veya iş varlığı adı BURAYA GİRMEZ. Yalnızca kip (aspect) jetonları
#           tanımlıdır; kavram jetonları operatörün yazdığı kimlikten gelir.
#
#           FAIL-CLOSED SÖZLEŞMESİ KORUNUR:
#             * kavram anahtarı eşleşen SIFIR ya da BİRDEN FAZLA sayım varsa
#               kanonikleştirme YAPILMAZ (belirsizlik AUTO'ya dönüşemez),
#               `unknown_capability` aynen kalır,
#             * gerçekten bilinmeyen kavramlar `unknown_capability` kalır,
#               kayıt defterinde olup sorguda olmayan kimlik
#               `capability_missing` kalır,
#             * `unsupported` alanı SERBEST METİNDİR ve ASLA kanonikleştirilmez.
#
#           Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur.
# ==============================================================================

# VARLIK (existential) kip jetonları. Bunlar KAVRAM değil, KİP belirtir:
# "bu şey var mı / mevcut mu / herhangi biri var mı".
.PK_SELECT_EXISTENTIAL_ASPECTS <- c(
  "exists", "exist", "existing", "existence",
  "has", "have", "any", "present", "presence", "occurs", "occurrence",
  "var", "varmi", "varlik", "mevcut", "mevcudiyet", "bulunuyor", "bulunur"
)

# SAYIM kip jetonları. Hedef ölçünün sayım olduğunu YAPISAL olarak gösterir.
.PK_SELECT_COUNT_ASPECTS <- c(
  "count", "counts", "cnt", "num", "number",
  "adet", "sayi", "sayisi", "sayısı"
)

# Boyutsuz SAYIM birimleri. Kayıt defterindeki `unit` alanı da hedefin sayım
# olduğunu kanıtlayabilir (ör. `list(role = "measure", unit = "adet")`).
.PK_SELECT_COUNT_UNITS <- c("adet", "count", "kayit", "kayıt")

# Anlam taşımayan bağlayıcı jetonlar; kavram anahtarından düşülür.
.PK_SELECT_FILLER_ASPECTS <- c("of", "the", "is", "ile", "olan", "bir")

#' Yerel bağımsız ASCII katlama (Türkçe İ/I tuzağı olmadan)
.pk_select_cap_fold <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (is.na(txt)) return("")
  txt <- chartr("ÇĞİIÖŞÜ", "cgiiosu", txt)
  txt <- chartr("çğıöşü", "cgiosu", txt)
  tolower(trimws(txt))
}

#' Yetenek kimliğini ad alanı + jeton kümesine ayır
#'
#' `activity.delayed_count` -> list(ns = "activity", tokens = c("delayed","count"))
.pk_select_cap_parts <- function(id) {
  metin <- .pk_select_cap_fold(id)
  if (!nzchar(metin)) return(NULL)

  parcalar <- strsplit(metin, ".", fixed = TRUE)[[1]]
  if (length(parcalar) < 2L) {
    ns <- ""
    kalan <- metin
  } else {
    ns <- parcalar[1]
    kalan <- paste(parcalar[-1], collapse = ".")
  }

  jetonlar <- unlist(strsplit(kalan, "[^a-z0-9]+"), use.names = FALSE)
  jetonlar <- jetonlar[nzchar(jetonlar)]
  if (!length(jetonlar)) return(NULL)

  list(ns = ns, tokens = jetonlar)
}

#' Kip jetonlarını düşerek KAVRAM anahtarı üret
#'
#' @return `NULL` (anahtar üretilemedi) ya da `list(key=, aspects=)`.
.pk_select_cap_concept <- function(id, drop_aspects) {
  parcalar <- .pk_select_cap_parts(id)
  if (is.null(parcalar)) return(NULL)

  dusen <- intersect(parcalar$tokens, drop_aspects)
  kavram <- setdiff(parcalar$tokens, c(drop_aspects, .PK_SELECT_FILLER_ASPECTS))
  if (!length(kavram)) return(NULL)

  list(
    key = paste0(parcalar$ns, "::", paste(sort(unique(kavram)), collapse = "+")),
    aspects = dusen
  )
}

#' Kayıt defterindeki bir yetenek SAYIM ölçüsü mü?
.pk_select_is_count_capability <- function(id, registry_entry) {
  rol <- if (is.list(registry_entry)) registry_entry$role else NULL
  if (!is.character(rol) || length(rol) != 1L || is.na(rol) ||
      !identical(trimws(rol), "measure")) {
    return(FALSE)
  }

  parcalar <- .pk_select_cap_parts(id)
  if (!is.null(parcalar) && length(intersect(parcalar$tokens, .PK_SELECT_COUNT_ASPECTS))) {
    return(TRUE)
  }

  birim <- if (is.list(registry_entry)) registry_entry$unit else NULL
  if (is.character(birim) && length(birim) == 1L && !is.na(birim)) {
    return(.pk_select_cap_fold(birim) %in% .PK_SELECT_COUNT_UNITS)
  }

  FALSE
}

#' Kayıt defterini oku (enjekte edilebilir; testler için)
.pk_select_capability_registry <- function(registry = NULL) {
  if (!is.null(registry)) return(if (is.list(registry)) registry else list())
  kayit <- tryCatch(
    get0("pk_capability_registry", ifnotfound = NULL), error = function(e) NULL
  )
  if (is.list(kayit)) kayit else list()
}

#' Seçilen adayın SUNDUĞU yetenek kimlikleri
.pk_select_query_capabilities <- function(query) {
  if (!exists("pk_meta_declared_capabilities", mode = "function", inherits = TRUE)) {
    return(character(0))
  }
  beyan <- tryCatch(pk_meta_declared_capabilities(query), error = function(e) NULL)
  if (!is.list(beyan) || !length(beyan) || is.null(names(beyan))) return(character(0))
  adlar <- names(beyan)
  adlar[!is.na(adlar) & nzchar(trimws(adlar))]
}

#' VARLIK iddiasını SAYIM yeteneğine kanonikleştir
#'
#' @param query Seçilen aday sorgu kaydı.
#' @param requirements Normalleştirilmiş (ya da ham) `requirements` nesnesi.
#' @param capability_ids İzinli yetenek kimlikleri (kayıt defteri adları).
#' @param registry Kayıt defteri (enjekte edilebilir).
#' @return `list(requirements=, mappings=, changed=)`. `mappings`, bilinmeyen
#'   kimlikten kanonik SAYIM kimliğine adlandırılmış eşlemedir (tanılama için).
pk_select_canonicalize_requirements <- function(query, requirements,
                                                capability_ids = NULL,
                                                registry = NULL) {
  bos <- list(requirements = requirements, mappings = character(0), changed = FALSE)
  if (!is.list(requirements)) return(bos)

  kayit <- .pk_select_capability_registry(registry)
  if (is.null(capability_ids)) {
    capability_ids <- if (exists("pk_select_capability_ids", mode = "function", inherits = TRUE)) {
      tryCatch(pk_select_capability_ids(kayit), error = function(e) character(0))
    } else {
      names(kayit) %||% character(0)
    }
  }
  capability_ids <- as.character(capability_ids %||% character(0))
  if (!length(capability_ids)) return(bos)

  gorunum <- if (exists(".pk_select_req_view", mode = "function", inherits = TRUE)) {
    .pk_select_req_view(requirements)
  } else {
    requirements
  }

  # `group_by` DIŞINDAKİ yetenek alanları kanonikleştirilebilir. Bir kimlik
  # aynı zamanda `group_by` içindeyse niyet BELİRSİZDİR (kırılım anahtarı bir
  # sayım ölçüsü olamaz) ve dokunulmaz.
  hedef_alanlar <- c("measures", "dates", "dimensions")
  iddia <- unique(unlist(gorunum[hedef_alanlar], use.names = FALSE))
  iddia <- iddia[!is.na(iddia) & nzchar(iddia)]
  bilinmeyen <- setdiff(iddia, capability_ids)
  if (!length(bilinmeyen)) return(bos)

  sunulan <- intersect(.pk_select_query_capabilities(query), capability_ids)
  if (!length(sunulan)) return(bos)

  # Adayın SUNDUĞU sayım ölçüleri: kavram anahtarı -> kimlik.
  sayimlar <- list()
  for (kimlik in sunulan) {
    if (!.pk_select_is_count_capability(kimlik, kayit[[kimlik]])) next
    kavram <- .pk_select_cap_concept(kimlik, .PK_SELECT_COUNT_ASPECTS)
    if (is.null(kavram)) next
    sayimlar[[kavram$key]] <- c(sayimlar[[kavram$key]], kimlik)
  }
  if (!length(sayimlar)) return(bos)

  esleme <- character(0)
  for (u in bilinmeyen) {
    # `group_by` içinde de geçen bir kimlik belirsizdir.
    if (u %in% (gorunum$group_by %||% character(0))) next

    kavram <- .pk_select_cap_concept(u, c(.PK_SELECT_EXISTENTIAL_ASPECTS,
                                          .PK_SELECT_COUNT_ASPECTS))
    if (is.null(kavram)) next
    # İMA YALNIZCA VARLIK KİPİNDEN DOĞAR: kip jetonu taşımayan bir kimlik
    # gerçekten bilinmeyendir ve kapalı başarısız olmalıdır.
    if (!length(intersect(kavram$aspects, .PK_SELECT_EXISTENTIAL_ASPECTS))) next

    adaylar <- unique(sayimlar[[kavram$key]] %||% character(0))
    if (length(adaylar) != 1L) next  # 0 ya da >1 => BELİRSİZ => kapalı başarısız

    esleme[[u]] <- adaylar[[1]]
  }

  if (!length(esleme)) return(bos)

  # Kanonik kimlik KENDİ ROLÜNE ait alana yazılır (sayım ölçüsü -> `measures`);
  # aksi hâlde rol uyuşmazlığı `capability_missing` üretirdi.
  yeni <- gorunum
  for (alan in hedef_alanlar) {
    yeni[[alan]] <- setdiff(yeni[[alan]] %||% character(0), names(esleme))
  }
  yeni$measures <- unique(c(yeni$measures %||% character(0), unname(esleme)))

  list(requirements = yeni, mappings = esleme, changed = TRUE)
}

#' Kanonikleştirmeyi GÜVENLİ biçimde uygula (doğrulayıcı giriş noktası)
#'
#' `pk_select_validate_requirements()` bunu çağırır. Kanonikleştirici yoksa ya
#' da çökerse gereksinimler DEĞİŞMEDEN döner: kanonikleştirme bir OPTİMİZASYON
#' değil, bir KOLAYLIKtır ve başarısızlığı doğrulamayı gevşetmemelidir. Gerçek
#' karar (bilinmeyen kavram, belirsizlik, kayıt defterinde olmayan kimlik) her
#' hâlde doğrulayıcının KAPALI BAŞARISIZ dallarında kalır.
#'
#' @return `list(requirements, mappings)`.
pk_select_apply_canonicalization <- function(query, requirements,
                                             capability_ids = NULL, registry = NULL) {
  bos <- list(requirements = requirements, mappings = character(0))
  if (!exists("pk_select_canonicalize_requirements", mode = "function", inherits = TRUE)) {
    return(bos)
  }

  donusum <- tryCatch(
    pk_select_canonicalize_requirements(query, requirements, capability_ids,
                                        registry = registry),
    error = function(e) NULL
  )
  if (!is.list(donusum) || !isTRUE(donusum$changed) || !is.list(donusum$requirements)) {
    return(bos)
  }

  list(requirements = donusum$requirements,
       mappings = donusum$mappings %||% character(0))
}
