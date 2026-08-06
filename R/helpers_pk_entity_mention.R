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
# Çoğul ipuçları burada da yer alır: ipucu ÇOĞULLUK bayrağını belirler,
# ancak varlık adının kendisi değildir ("tüm ANKA" -> "ANKA").
.PK_ENTITY_CONTROL_WORDS <- c(
  .PK_ENTITY_PLURAL_WORDS,
  "list", "listele", "listesini",
  "göster", "goster", "getir", "bul", "ver",
  "adlı", "adli", "isimli", "olan", "olanlar",
  "için", "icin", "ait", "ilgili"
)

# Metadata'da tanımlı varlık TÜRÜ belirteçleri için güvenli varsayılan.
# Bilinçli olarak KÜÇÜK tutulmuştur: fazlası kanonik adları aşındırır.
# Gerçek liste `entity_kinds` argümanıyla sorgu metadatasından gelir.
.PK_ENTITY_DEFAULT_KINDS <- c("proje", "program")

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
pk_entity_mentions <- function(phrase, entity_kinds = NULL) {
  normal <- pk_entity_normalize(phrase)
  if (isTRUE(normal$blank)) return(character(0))

  # Virgül/noktalı virgül gibi ayırıcılar noktalama sadeleştirmesinde zaten
  # boşluğa döndüğü için bölme YALNIZCA bağlaç sözcükleri üzerinden yapılır.
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

  animlar <- character(0)
  for (grup in gruplar) {
    tut <- !vapply(grup, .pk_entity_is_drop_token, logical(1),
                   dusur = dusur, USE.NAMES = FALSE)
    kalan <- grup[tut]

    # Hiçbir belirteç kalmadıysa grup tamamen denetim sözcüğüdür; anım DEĞİLDİR.
    if (!length(kalan)) next
    animlar <- c(animlar, paste(kalan, collapse = " "))
  }

  animlar <- unique(animlar[nzchar(animlar)])

  # Tam ifadeyle aynı olan anım ek bilgi taşımaz.
  animlar[!identical(animlar, normal$fold) & animlar != normal$fold]
}
