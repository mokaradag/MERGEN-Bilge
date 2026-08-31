# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_mention.R
# Açıklama: Faz 4 — kullanıcı ifadesinden VARLIK ANIMI (mention) çıkarımı.
#
#           ÖLÇÜLMÜŞ GEREKÇE: puanlayıcı ifadeyi TEK bir belirteç kümesi
#           saydığı sürece üç yaygın istek biçimi hiçbir katmana ulaşamaz ve
#           çözümleyici analizi bloke eder:
#
#             * Sıralı istek — "ANKA ve AKINCI projeleri": kanonik
#               "ANKA Projesi" adayına karşı kapsama YANLIŞ, J = 2/4 = 0.50.
#               Hiçbir katman tutmaz; kural 3'e BOŞ küme gider.
#             * Tür nitelemeli tekil anım — "ANKA projesi" / kanonik "ANKA":
#               kapsama YANLIŞ, J = 0.50, düzenleme oranı tavanın üstünde.
#             * Çoğul denetim sözcüğü — "tüm ANKA" / kanonik "ANKA":
#               J = 1/2 < 0.60; kural 3 hiçbir aday göremez.
#
#           Bu katman ifadeyi bağlaç/virgülden böler ve denetim/tür
#           belirteçlerini düşürür. GÜVENLİK: yalnızca EK bir geçiştir.
#           Tam ifade önce puanlanır; kesin/alias/ikincil-anahtar katmanı
#           tuttuysa anım geçişi HİÇ çalışmaz. Böylece "KAYNAK LİSTESİ" gibi
#           tür sözcüğü İÇEREN kanonik adlar bozulmaz.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# İfadeyi ayrı varlık anımlarına bölen bağlaçlar.
.PK_ENTITY_SPLIT_WORDS <- c("ve", "veya", "ile", "yada", "ya")

# Varlık adının parçası OLMAYAN, isteğin biçimini anlatan belirteçler.
# TÜRKÇE SABİTLER YÜKLEME ANINDA UTF-8'E SABİTLENİR (`enc2utf8`).
#
# `R/helpers_pk_entity_morph.R` başlığındaki ölçülen arıza burada da geçerlidir:
# Windows VM'de `source(dosya, encoding = "UTF-8")` içeriği YERELE
# (WINDOWS-1254) çevirir ve sabitler "native" işaretli olur; karşılaştırılan
# belirteçler ise `pk_tr_fold()`/`pk_entity_normalize()` yolundan UTF-8 işaretli
# gelir. `%in%`, `identical()` ve `stri_replace_all_fixed()` o durumda native
# tarafı GÜNCEL yerele göre çevirir; yerel `C` iken çeviri başarısız olur ve
# eşleşme SESSİZCE kaybolur. UTF-8 işaretli dizelerde `enc2utf8()` işlemsizdir.

# Çoğul ipuçları burada da yer alır: ipucu ÇOĞULLUK bayrağını belirler,
# ancak varlık adının kendisi değildir ("tüm ANKA" -> "ANKA").
.PK_ENTITY_CONTROL_WORDS <- enc2utf8(c(
  .PK_ENTITY_PLURAL_WORDS,
  "list", "listele", "listesini",
  "göster", "goster", "getir", "bul", "ver",
  "adlı", "adli", "isimli", "olan", "olanlar",
  "için", "icin", "ait", "ilgili"
))

# Metadata'da tanımlı varlık TÜRÜ belirteçleri için güvenli varsayılan.
# Bilinçli olarak KÜÇÜK tutulmuştur: fazlası kanonik adları aşındırır.
# Gerçek liste `entity_kinds` argümanıyla sorgu metadatasından gelir.
.PK_ENTITY_DEFAULT_KINDS <- enc2utf8(c("proje", "program"))

.pk_entity_mention_drop_set <- function(entity_kinds = NULL) {
  turler <- if (is.null(entity_kinds)) character(0) else as.character(entity_kinds)
  turler <- turler[!is.na(turler) & nzchar(turler)]
  turler <- unique(c(.PK_ENTITY_DEFAULT_KINDS, pk_tr_fold(turler)))

  # Tür sözcükleri çekim ekli gelir ("projesi", "programlari"); gövdeleri de
  # düşürülmelidir. Gövde soyma sözlüksüz yapılır: burada amaç kanonik değer
  # üretmek değil, denetim belirtecini tanımaktır.
  govdeler <- vapply(turler, pk_entity_stem_token, character(1), USE.NAMES = FALSE)

  unique(c(.PK_ENTITY_CONTROL_WORDS, turler, govdeler))
}

# Belirteç bir denetim/tür sözcüğünün ÇEKİMLİ biçimi mi?
#
# Basit eşitlik yetmez: "projeleri" tek harfli iyelik eki taşıdığı için genel
# gövde soymayla "proje"ye inmez (tek harfli ekler bilerek listede yoktur).
# Bu yüzden ön ek + BİLİNEN sonek zinciri kalıbı ayrıca denenir. Kalıp
# dardır: "PROJEKSIYON" gibi adlar ("ksiyon" bir sonek zinciri değildir)
# etkilenmez.
.pk_entity_is_drop_token <- function(token, dusur) {
  if (is.na(token) || !nzchar(token)) return(FALSE)
  if (token %in% dusur) return(TRUE)
  if (pk_entity_stem_token(token) %in% dusur) return(TRUE)

  for (kok in dusur) {
    if (nchar(token) <= nchar(kok)) next
    if (nchar(token) - nchar(kok) < 2L) next  # TEK HARFLİK KUYRUK EK SAYILMAZ: `.pk_entity_run_is_suffix_chain()` tek harfli sözlük eklerini de kabul ettiği için `ver` + `i` kalıbı `veri` gibi GERÇEK varlık belirteçlerini denetim sözcüğü sanıp düşürüyordu (`projesi` -> `si`, `projeleri` -> `leri` korunur).
    if (!identical(substring(token, 1L, nchar(kok)), kok)) next
    if (.pk_entity_run_is_suffix_chain(substring(token, nchar(kok) + 1L))) return(TRUE)
  }

  FALSE
}

#' İfadeden varlık anımlarını çıkar
#'
#' @param phrase Kullanıcı ifadesi.
#' @param entity_kinds Metadata'da bildirilen varlık türü belirteçleri.
#' @return Sıfır veya daha fazla anım metni (katlanmış). Tam ifade DÂHİL
#'   EDİLMEZ; çağıran onu zaten ayrıca puanlar.
# NOKTALAMA SINIRLARI NORMALLEŞTİRMEDEN ÖNCE KORUNUR. `pk_entity_normalize()`
# noktalamayı boşluğa indirger; bölme yalnızca bağlaç sözcükleri üzerinden
# yapılınca `ANKA, AKINCI projeleri` TEK bir `anka akinci` anımı üretiyor, anım
# geçişi iki kanonik adayın HİÇBİRİNE ulaşamıyor ve geçerli çok-varlıklı istek
# reddedilebiliyordu.
.PK_ENTITY_PUNCT_SPLIT <- "[,;/|\\n\\r\\t]+"

pk_entity_mentions <- function(phrase, entity_kinds = NULL) {
  # Sınır, bölme belirtecine ("ve") çevrilir. Özyineleme KULLANILMAZ: her
  # parçayı ayrı bir "tam ifade" gibi çözmek, tek belirteçli parçaları (`ANKA`)
  # tam-ifade kuralıyla düşürürdü.
  ham <- as.character(phrase %||% "")[1]
  bolundu <- !is.na(ham) && grepl(.PK_ENTITY_PUNCT_SPLIT, ham, perl = TRUE)
  if (bolundu) {
    phrase <- gsub(.PK_ENTITY_PUNCT_SPLIT, " ve ", ham, perl = TRUE)
  }

  normal <- pk_entity_normalize(phrase)
  if (isTRUE(normal$blank)) return(character(0))

  # Bu noktada noktalama sınırları ZATEN uygulanmıştır; kalan bölme bağlaç
  # sözcükleri üzerinden yapılır.
  belirtecler <- pk_entity_tokens(normal$fold, stem = FALSE)
  if (!length(belirtecler)) return(character(0))

  gruplar <- list()
  gecerli <- character(0)
  for (tok in belirtecler) {
    if (tok %in% .PK_ENTITY_SPLIT_WORDS) {
      if (length(gecerli)) gruplar[[length(gruplar) + 1L]] <- gecerli
      gecerli <- character(0)
      next
    }
    gecerli <- c(gecerli, tok)
  }
  if (length(gecerli)) gruplar[[length(gruplar) + 1L]] <- gecerli

  dusur <- .pk_entity_mention_drop_set(entity_kinds)

  # Bir belirteç grubunu anıma indirger. Hiçbir belirteç kalmadıysa grup
  # tamamen denetim sözcüğüdür ve anım DEĞİLDİR (`""` döner, aşağıda elenir).
  .anim_yap <- function(grup) {
    tut <- !vapply(grup, .pk_entity_is_drop_token, logical(1),
                   dusur = dusur, USE.NAMES = FALSE)
    paste(grup[tut], collapse = " ")
  }

  animlar <- vapply(gruplar, .anim_yap, character(1), USE.NAMES = FALSE)

  # BÖLÜNMEMİŞ ANIM DA KORUNUR (PR #705 incelemesi, P2): `/` ve `|` hem gerçek
  # liste ayırıcısı (`ALFA/BETA`) hem de kanonik adın KENDİ parçası (`AR/GE`,
  # `A/B`) olabilir. Yalnızca bölünmüş parçalar üretilirse `AR/GE projesi`
  # ifadesi `ar` ve `ge` anımlarına düşer ve hiçbir anım `ar ge` kanonik
  # katlamasına ULAŞAMAZ. Bölünmemiş biçim ek aday olur; bölme DEĞİŞMEZ.
  if (isTRUE(bolundu)) {
    bolunmemis <- pk_entity_normalize(ham)
    if (!isTRUE(bolunmemis$blank)) {
      animlar <- c(animlar,
                   .anim_yap(pk_entity_tokens(bolunmemis$fold, stem = FALSE)))
    }
  }

  animlar <- unique(animlar[nzchar(animlar)])

  # Tam ifadeyle aynı olan anım ek bilgi taşımaz.
  animlar[!identical(animlar, normal$fold) & animlar != normal$fold]
}
