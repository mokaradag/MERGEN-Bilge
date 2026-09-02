# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_history.R
# Açıklama: Faz 4 — D11: `chat_history` ile devam sorusu daraltması.
#
#           D11 (§3, S3): `pk_analiz_process_request()` ve `select_smart_query()`
#           `chat_history` parametresini ALIR ama gövdelerinde HİÇ OKUMAZ. Bu
#           yüzden "peki 2024 için?" veya "sadece aktif olanlar" gibi eksiltili
#           devam soruları, bir önceki soruda çözülmüş varlığı kaybeder.
#
#           Bu dosya o boşluğu SAF bir katman olarak doldurur.
#
#           DÖRT GÜVENLİK SINIRI (hepsi ölçülmüş kusurlardan doğdu):
#
#             1) GÜNCEL TUR ÖNCELİKLİDİR. Gönderme yolu kullanıcı mesajını
#                geçmişe EKLEDİKTEN sonra istek kurar; yani `chat_history`
#                zaten güncel ifadeyi içerir. Devralmadan önce hem güncel
#                mesaj geçmişten düşülür hem de güncel ifadenin BAŞINDAKİ
#                devam belirteçleri atılıp yeniden çözümleme denenir
#                ("peki AKINCI?" -> "AKINCI").
#             2) YALNIZCA İLGİLİ TUR. Geriye doğru "bir şey çözülene kadar"
#                arama YAPILMAZ; aksi hâlde araya giren ilgisiz bir soru
#                atlanıp çok daha eski bir bağlam diriltilir. Yalnızca bir
#                önceki kullanıcı turu (veya kalıcı bağlam) kullanılır.
#             3) DEVRALINAN SONUÇ ASLA OTOMATİK DEĞİLDİR. Devralınan şey
#                kullanıcının BU mesajda yazmadığı bir filtredir; sonuç en
#                fazla ONAY isteğine indirgenir ve `values` boşaltılır.
#             4) KİMLİK BAĞI. Devralınan varlık, çözüldüğü SORGU/SÜTUN
#                kimliğiyle birlikte taşınır ve yalnızca aynı yaprakta
#                yeniden kullanılır; aksi hâlde bir proje adı, aynı değeri
#                taşıyan bir departman sütununa sızabilir.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Sohbet geçmişi bu depoda iki biçimde dolaşır: LLM yolunda `role`/`content`,
# sohbet çalışma zamanında `type`/`content`. İkisi de desteklenir.
# UTF-8'e SABİTLENİR (dosyadaki diğer Türkçe sabitlerle AYNI kural).
#
# Windows VM'de `source(..., encoding = "UTF-8")` sabiti NATIVE işaretler;
# `pk_tr_fold(rol)` ise UTF-8 döner. Locale `C` iken yeniden kodlama başarısız
# olur, `%in%` karşılaştırması kullanıcı turunu KAÇIRIR ve D11 devralma durur.
.PK_ENTITY_USER_ROLES <- enc2utf8(c("user", "human", "kullanici", "kullanıcı"))

# İlk belirteç olarak göründüğünde devam sorusu sinyali veren ifadeler.
# TÜRKÇE SABİTLER YÜKLEME ANINDA UTF-8'E SABİTLENİR (`enc2utf8`).
#
# `R/helpers_pk_entity_morph.R` başlığındaki ölçülen arıza burada da geçerlidir:
# Windows VM'de `source(dosya, encoding = "UTF-8")` içeriği YERELE
# (WINDOWS-1254) çevirir ve sabitler "native" işaretli olur; karşılaştırılan
# belirteçler ise `pk_tr_fold()`/`pk_entity_normalize()` yolundan UTF-8 işaretli
# gelir. `%in%`, `identical()` ve `stri_replace_all_fixed()` o durumda native
# tarafı GÜNCEL yerele göre çevirir; yerel `C` iken çeviri başarısız olur ve
# eşleşme SESSİZCE kaybolur. UTF-8 işaretli dizelerde `enc2utf8()` işlemsizdir.

# Türkçe adıllar ÇEKİM EKİ alır; belirtme (`onu`), yönelme (`ona`) ve
# bulunma biçimleri de listede olmalıdır, aksi hâlde "onu göster" veya
# "buna 2024 için bak" devam sorusu sayılmaz.
.PK_ENTITY_FOLLOWUP_LEAD <- enc2utf8(c(
  "peki", "ya", "sadece", "yalnızca", "yalnizca", "ayrıca", "ayrica",
  "onun", "onu", "ona", "onda", "ondan", "onlar", "onları", "onlari",
  "bunun", "bunu", "buna", "bunda", "bundan", "bunları", "bunlari",
  "şunun", "sunun", "şunu", "sunu", "şuna", "suna",
  "hepsi", "hepsini", "tümü", "tumu", "tümünü", "tumunu",
  "hem", "ve"
))

# İfadenin herhangi bir yerinde geçmesi yeterli olan güçlü sinyaller.
.PK_ENTITY_FOLLOWUP_ANY <- enc2utf8(c(
  "peki", "sadece", "yalnızca", "yalnizca", "ayrıca", "ayrica",
  "aynısı", "aynisi", "aynısını", "aynisini"
))

# Yapısal devam sinyali: kısa bir daraltma ifadesinde geçen belirteçler.
# "2024 için?", "aktif olanlar?", "sadece kapalı olanlar" gibi biçimler
# hiçbir işaret sözcüğü taşımaz ama tam olarak D11'in hedefidir.
.PK_ENTITY_REFINEMENT_WORDS <- enc2utf8(c(
  "için", "icin", "ile", "olan", "olanlar", "olanları", "olanlari",
  "itibariyle", "itibarıyla", "arası", "arasi", "sonrası", "sonrasi",
  "öncesi", "oncesi", "yılı", "yili", "yılında", "yilinda",
  "de", "da", "te", "ta", "mi", "mı", "mu", "mü"
))

# Yapısal devam ifadesinde kabul edilen azami belirteç sayısı. Daha uzun bir
# ifade artık "eksiltili devam" değil, kendi başına bir sorudur.
.PK_ENTITY_FOLLOWUP_MAX_TOKENS <- 3L

# ÖLÇÜLMÜŞ GEREKÇE (tasarım kararı E4) — devralınan SORU sözcükleri atılır.
#
#   Devralınan şey bir varlık ifadesi değil, kullanıcının önceki TAM
#   SORUSUDUR: "elektronik harp şebekesi bütçesi nedir". Soru sözcükleri
#   belirteç kümesini şişirir ve Jaccard'ı her katmanın altına düşürür —
#   ölçüldü: kanonik "Sentetik Elektronik Harp Şebekesi" adayına karşı
#   J = 0.50 < 0.60, yani HİÇBİR eşleşme üretilmez.
#
#   Bu liste YALNIZCA devralınan önceki mesajlara uygulanır; kullanıcının
#   GÜNCEL ifadesine ve kanonik adaylara DOKUNULMAZ. Alan adları (bütçe,
#   maliyet, süre gibi) BİLEREK listede DEĞİLDİR: onlar ayırt edici olabilir.
#
#   Bu yeniden yazım KAYIPLIDIR: "Bir Proje bütçesi nedir" ifadesi
#   "proje bütçesi"ne dönüşüp FARKLI bir kanonik değere denk gelebilir. Bu
#   yüzden yeniden yazımdan doğan hiçbir sonuç otomatik kabul edilmez.
.PK_ENTITY_QUESTION_WORDS <- enc2utf8(c(
  "nedir", "ne", "kadar", "kaç", "kac", "kaçtır", "kactir",
  "hangi", "hangisi", "hangileri", "nasıl", "nasil", "neden", "niçin", "nicin",
  "nerede", "nereye", "kim", "kimdir",
  "mi", "mı", "mu", "mü", "midir", "mıdır", "mudur", "müdür",
  "göster", "goster", "listele", "ver", "söyle", "soyle", "açıkla", "acikla",
  "getir", "bul", "hesapla", "raporla", "özetle", "ozetle",
  "için", "icin", "ile", "ve", "veya", "ya", "da", "de",
  "bu", "şu", "su", "o", "bir", "en", "var", "yok",
  "olan", "olanlar", "oldu", "nedeni", "durumu", "bilgisi"
))

#' Devralınan önceki sorudan soru sözcüklerini at (yalnızca geçmiş katmanı)
#'
#' Sonuç boş kalırsa orijinal metin korunur: boş bir ifade GEÇERSİZ GİRDİDİR ve
#' çözümleyiciye boş dizgi göndermek anlamsız bir hata üretir.
pk_entity_strip_question_words <- function(text) {
  normal <- pk_entity_normalize(text)
  if (isTRUE(normal$blank)) return(NA_character_)

  belirtecler <- pk_entity_tokens(normal$fold, stem = FALSE)
  kalan <- belirtecler[!(belirtecler %in% .PK_ENTITY_QUESTION_WORDS)]

  if (!length(kalan)) return(normal$fold)
  paste(kalan, collapse = " ")
}

#' Güncel ifadenin BAŞINDAKİ devam belirteçlerini at
#'
#' "peki AKINCI?" ifadesinde varlık GÜNCEL turda açıkça yazılmıştır; yalnızca
#' başındaki bağlantı sözcüğü puanlamayı bozar. Geçmişe bakmadan ÖNCE bu
#' biçim denenir, böylece açıkça adlandırılmış yeni varlık eski bağlamla
#' değiştirilmez.
pk_entity_strip_leading_markers <- function(phrase) {
  normal <- pk_entity_normalize(phrase)
  if (isTRUE(normal$blank)) return(NA_character_)

  belirtecler <- pk_entity_tokens(normal$fold, stem = FALSE)
  if (!length(belirtecler)) return(NA_character_)

  i <- 1L
  while (i <= length(belirtecler) &&
         belirtecler[i] %in% .PK_ENTITY_FOLLOWUP_LEAD) {
    i <- i + 1L
  }

  if (i == 1L || i > length(belirtecler)) return(NA_character_)
  paste(belirtecler[i:length(belirtecler)], collapse = " ")
}

.pk_entity_msg_field <- function(msg, fields) {
  if (!is.list(msg)) return(NA_character_)

  for (alan in fields) {
    deger <- msg[[alan]]
    if (is.null(deger) || !length(deger)) next
    metin <- as.character(deger)[1]
    if (!is.na(metin) && nzchar(trimws(metin))) return(metin)
  }

  NA_character_
}

.pk_entity_msg_is_user <- function(msg) {
  rol <- .pk_entity_msg_field(msg, c("role", "type", "sender"))
  if (is.na(rol)) return(FALSE)

  # Rol adları saf ASCII/Türkçe sabitlerdir; katlama yerelden bağımsız olsun
  # diye `tolower()` yerine pk_tr_fold() kullanılır.
  katlanmis <- pk_tr_fold(rol)
  if (!length(katlanmis) || is.na(katlanmis)) return(FALSE)

  katlanmis %in% .PK_ENTITY_USER_ROLES
}

#' Sohbet geçmişindeki kullanıcı sorularını EN YENİDEN ESKİYE doğru döndür
#'
#' @param chat_history Mesaj listesi. Her mesaj `role`/`type` ve `content`
#'   alanlarını taşıyan bir liste olmalıdır.
#' @param limit En fazla kaç önceki soru döndürülsün. `0` ve altı, devralmayı
#'   TAMAMEN kapatır (belgelenen anlam budur; sessizce 1'e yükseltilmez).
#' @param exclude_phrase Güncel istek metni. Gönderme yolu kullanıcı mesajını
#'   geçmişe EKLEDİKTEN sonra istek kurduğu için geçmiş, güncel ifadenin
#'   KENDİSİNİ içerir; bu kopya düşülmezse istek kendi kendisinin "önceki
#'   sorusu" sayılır.
pk_entity_prior_user_prompts <- function(chat_history, limit = 5L,
                                         exclude_phrase = NULL) {
  if (is.null(chat_history) || !is.list(chat_history) || !length(chat_history)) {
    return(character(0))
  }

  sinir <- suppressWarnings(as.integer(limit)[1])
  if (is.na(sinir) || sinir < 1L) return(character(0))

  haric <- NA_character_
  if (!is.null(exclude_phrase) && length(exclude_phrase)) {
    haric_norm <- pk_entity_normalize(exclude_phrase)
    if (!isTRUE(haric_norm$blank)) haric <- haric_norm$fold
  }

  toplanan <- character(0)
  guncel_dusuldu <- FALSE
  for (i in rev(seq_along(chat_history))) {
    mesaj <- chat_history[[i]]
    if (!.pk_entity_msg_is_user(mesaj)) next

    metin <- .pk_entity_msg_field(mesaj, c("content", "text", "message", "icerik"))
    if (is.na(metin)) next

    if (!guncel_dusuldu && !is.na(haric)) {
      aday <- pk_entity_normalize(metin)
      if (!isTRUE(aday$blank) && identical(aday$fold, haric)) {
        guncel_dusuldu <- TRUE
        next
      }
    }

    toplanan <- c(toplanan, metin)
    if (length(toplanan) >= sinir) break
  }

  toplanan
}

#' İfade eksiltili bir devam sorusu mu?
#'
#' Sezgiseldir ve BİLEREK sınırlıdır: sonucu yalnızca çözümleme ZATEN
#' başarısız olduğunda kullanılır ve devralınan sonuç en fazla ONAY isteğine
#' indirgenir; bu yüzden yanlış pozitifin maliyeti "önceki soruyu da dene"
#' adımıdır, sessiz bir varsayım değil.
pk_entity_is_followup <- function(phrase) {
  normal <- pk_entity_normalize(phrase)
  if (isTRUE(normal$blank)) return(FALSE)

  belirtecler <- pk_entity_tokens(normal$fold, stem = FALSE)
  if (!length(belirtecler)) return(FALSE)

  if (belirtecler[1] %in% .PK_ENTITY_FOLLOWUP_LEAD) return(TRUE)
  if (any(belirtecler %in% .PK_ENTITY_FOLLOWUP_ANY)) return(TRUE)

  # "bir de ..." kalıbı tek belirteçle yakalanamaz.
  if (length(belirtecler) >= 2L &&
      identical(belirtecler[1], "bir") && identical(belirtecler[2], "de")) {
    return(TRUE)
  }

  # YAPISAL SİNYAL — işaret sözcüğü taşımayan kısa daraltmalar.
  #
  # SAYISAL BELİRTEÇ TEK BAŞINA DEVAM SİNYALİ DEĞİLDİR. `"ANKA 2024"` gibi bir
  # ifade bu turda GERÇEK bir varlık adı taşır; yalnızca rakam içerdiği için
  # devam sayıldığında `.pk_entity_context_decision()` çip kümesini ÖNCEKİ turun
  # değerleriyle değiştiriyor ve kullanıcının BU turda yazdığı varlık hiç
  # sunulmuyordu. Rakam ancak bir daraltma sözcüğüyle BİRLİKTE sinyaldir
  # (ör. "sadece 2024"); yalnız rakamdan oluşan ifade (ör. "2024") de kendi
  # başına bir varlık adı değildir ve devam sayılır.
  if (length(belirtecler) <= .PK_ENTITY_FOLLOWUP_MAX_TOKENS) {
    daraltma <- any(belirtecler %in% .PK_ENTITY_REFINEMENT_WORDS)
    sayisal <- grepl("^[0-9]+$", belirtecler)
    if (daraltma || (length(sayisal) && all(sayisal))) {
      return(TRUE)
    }
  }

  FALSE
}

#' Devam sorusu planı (saf)
#'
#' @return `is_followup`, `prior_prompts` (en yeniden eskiye) ve
#'   `inherited_phrase` (devralınacak ifade; yoksa `NA`).
pk_entity_followup_plan <- function(chat_history, phrase, limit = 5L) {
  oncekiler <- pk_entity_prior_user_prompts(
    chat_history, limit = limit, exclude_phrase = phrase
  )

  list(
    is_followup = pk_entity_is_followup(phrase),
    prior_prompts = oncekiler,
    inherited_phrase = if (length(oncekiler)) oncekiler[1] else NA_character_
  )
}

# Bir kararın işaret ettiği birincil kanonik değer (karşılaştırma için).
.pk_entity_primary_value <- function(karar) {
  if (length(karar$values)) return(as.character(karar$values)[1])
  # UZUNLUK SÖZLEŞMESİ: çağıran `vapply(..., character(1))` kullanır; boş ya da
  # çok elemanlı bir `value` alanı TÜM çözümlemeyi hataya düşürürdü.
  if (length(karar$chips)) {
    deger <- as.character(karar$chips[[1]]$value)
    return(if (length(deger)) deger[1] else NA_character_)
  }
  NA_character_
}

# Devralınan karar ASLA otomatik değildir.
.pk_entity_mark_inherited <- function(karar, kaynak, phrase) {
  if (identical(karar$decision, "auto")) {
    aday <- .pk_entity_primary_value(karar)
    karar$decision <- "confirm"
    karar$rule <- 5L
    karar$values <- character(0)
    if (!is.na(aday)) {
      karar$chips <- list(list(
        label = aday, value = aday, score = karar$top_score,
        tier = "inherited", low_confidence = "inherited", preselected = TRUE
      ))
      karar$total_strong <- 1L
      karar$offer_all <- FALSE
      karar$message_tr <- sprintf(
        "Önceki sorunuzdaki bağlamı sürdürüyorum. Şunu mu kastettiniz: %s", aday
      )
    }
  }

  karar$inherited <- TRUE
  karar$inherited_from <- kaynak
  karar$original_phrase <- as.character(phrase)[1]
  karar
}

# Bir önceki sorudan denenecek ifade varyantları.
.pk_entity_history_variants <- function(onceki) {
  sade <- pk_entity_strip_question_words(onceki)
  tam <- unique(c(as.character(onceki)[1], sade))
  tam <- tam[!is.na(tam) & nzchar(tam)]

  belirtecler <- character(0)
  if (!is.na(sade) && nzchar(sade)) {
    belirtecler <- pk_entity_tokens(sade, stem = FALSE)
    belirtecler <- belirtecler[!(belirtecler %in% .PK_ENTITY_QUESTION_WORDS)]
    belirtecler <- setdiff(unique(belirtecler), tam)
  }

  list(full = tam, tokens = belirtecler)
}

# Bir kararın KESİN (kayıpsız) bir katmandan gelip gelmediği.
.pk_entity_is_strong_result <- function(karar) {
  if (!length(karar$candidates)) return(FALSE)
  # KATMAN KÜMESİ `helpers_pk_entity_scan.R` İÇİNDEKİ `guclu_katman` İLE AYNIDIR: ikincil anahtar katmanları da kayıpsızdır (kullanıcı hiç Türkçe harf yazmadığında ASCII katlama kayıp üretmez). Dar küme, bu turda AÇIKÇA yazılmış `"akinci icin"` gibi bir varlığı (`ascii_key` -> `AKINCI`) "zayıf" sayıp DÜŞÜRÜYOR ve onay istemi ESKİ turun bağlamını öneriyordu.
  as.character(karar$candidates[[1]]$tier)[1] %in% c("exact_fold", "alias", "ascii_key", "punct_key", "compact_key")
}

#' Geçmiş farkındalıklı varlık çözümleme (D11)
#'
#' @param prior_context Önceki turda ÇÖZÜLMÜŞ varlık bağlamı:
#'   `list(values = , key = list(query_id = , column = , entity_kind = ))`.
#'   Verildiğinde önceki soruyu yeniden puanlamak yerine bu kalıcı bağlam
#'   kullanılır (kısa proje adları tam soruyu yeniden puanlayarak
#'   bulunamadığı için gereklidir).
#' @param context_key Güncel yaprağın kimliği. `prior_context$key` ile
#'   EŞLEŞMEZSE devralma YAPILMAZ.
pk_entity_resolve_with_history <- function(phrase, candidates, chat_history = NULL,
                                           aliases = NULL, role = NULL,
                                           match_mode = NULL,
                                           entity_role = "subject",
                                           query_meta = NULL, thresholds = NULL,
                                           limit = 5L, prior_context = NULL,
                                           context_key = NULL,
                                           entity_kinds = NULL) {
  coz <- function(ifade, plural_override = NULL) {
    pk_entity_resolve(
      phrase = ifade, candidates = candidates, aliases = aliases,
      role = role, match_mode = match_mode, entity_role = entity_role,
      query_meta = query_meta, thresholds = thresholds,
      entity_kinds = entity_kinds, plural_override = plural_override
    )
  }

  ilk <- coz(phrase)

  # Yapılandırma hatası, devre dışı kip ve geçersiz girdi devralmayla DÜZELMEZ.
  if (ilk$decision %in% c("config_error", "invalid_input", "disabled",
                          "not_applicable")) {
    return(ilk)
  }

  devam_mi <- pk_entity_is_followup(phrase)

  # Güçlü (kesin/alias) bir güncel sonuç geçmişten HER ZAMAN üstündür.
  if (!(ilk$decision %in% c("unresolved", "unfiltered"))) {
    if (!devam_mi || .pk_entity_is_strong_result(ilk)) return(ilk)
    # Devam sorusu artı ZAYIF bir doğrudan eşleşme: "peki" ifadesinin
    # `PEKİN` değerine düzenleme mesafesiyle 50 puan vermesi gibi çakışmalar
    # eski bağlamı bastırmamalıdır. Geçmiş de değerlendirilir.
  }

  # (1) GÜNCEL TUR ÖNCELİKLİ: baştaki devam belirteçleri atılıp yeniden dene.
  if (devam_mi) {
    kirpik <- pk_entity_strip_leading_markers(phrase)
    if (!is.na(kirpik) && nzchar(kirpik)) {
      guncel <- coz(kirpik, plural_override = pk_entity_phrase_is_plural(phrase))
      if (guncel$decision %in% c("auto", "confirm", "clarify")) {
        guncel$marker_stripped <- TRUE
        guncel$original_phrase <- as.character(phrase)[1]
        return(guncel)
      }
    }
  }

  if (!devam_mi) return(ilk)

  cogul <- pk_entity_phrase_is_plural(phrase)

  # (1b) GÜNCEL TURUN BELİRTEÇLERİ ÖNCE DENENİR. Kısa kanonik adlar tam ifade
  #      puanlanarak bulunamaz (bkz. (5) J = 1/3 notu); belirteçler yalnızca
  #      GEÇMİŞ için denendiğinde, bu turda AÇIKÇA yazılmış bir varlık
  #      (`"ANKA icin"`) kalıcı bağlamla DEĞİŞTİRİLİYORDU: kullanıcının az önce
  #      yazdığı özne hiç teklif edilmiyor, onay istemi ESKİ özneyi öneriyordu.
  #      BELİRTEÇLER KATLANMIŞ METİNDEN TÜRETİLİR: ham `pk_entity_tokens()` yalnızca boşluktan böler, `.PK_ENTITY_REFINEMENT_WORDS` ise katlanmış küçük harfli formları tutar. `"AKINCI İÇİN?"` girdisinde `setdiff()` HİÇBİR ŞEY elemiyor, daraltma sözcüğü için de tam sözlük taraması çalışıyordu. `tokens_raw` aynı boru hattının SOYULMAMIŞ çıktısıdır (satır 122/139/236 ile aynı kural).
  for (belirtec in setdiff(pk_entity_normalize(phrase)$tokens_raw, .PK_ENTITY_REFINEMENT_WORDS)) {
    karar <- coz(belirtec, plural_override = cogul)
    if (karar$decision %in% c("auto", "confirm") &&
        .pk_entity_is_strong_result(karar)) {
      karar$original_phrase <- as.character(phrase)[1]
      return(karar)
    }
  }

  # (2) KALICI BAĞLAM — sorgu/sütun kimliği eşleşiyorsa yeniden puanlama YOK.
  baglam <- .pk_entity_context_decision(
    prior_context, context_key, ilk, phrase, cogul
  )
  if (!is.null(baglam)) return(baglam)

  # (3) YALNIZCA BİR ÖNCEKİ TUR. Geriye doğru "bir şey çözülene kadar" arama
  #     yapılmaz; araya giren ilgisiz bir soru atlanıp eski bağlam dirilemez.
  oncekiler <- pk_entity_prior_user_prompts(
    chat_history, limit = limit, exclude_phrase = phrase
  )
  if (!length(oncekiler)) return(ilk)

  onceki <- oncekiler[1]
  varyantlar <- .pk_entity_history_variants(onceki)

  sonuclar <- list()
  for (aday_ifade in varyantlar$full) {
    karar <- coz(aday_ifade, plural_override = cogul)
    if (karar$decision %in% c("auto", "confirm", "clarify")) {
      sonuclar[[length(sonuclar) + 1L]] <- karar
    }
  }

  # (4) HAM ve YENİDEN YAZILMIŞ yorumlar ÇELİŞİYORSA yineleme sırası karar
  #     veremez; kullanıcıya sorulur.
  degerler <- unique(vapply(sonuclar, .pk_entity_primary_value, character(1)))
  degerler <- degerler[!is.na(degerler)]
  if (length(degerler) > 1L) {
    return(.pk_entity_ambiguous_history(sonuclar, degerler, onceki, phrase))
  }

  if (length(sonuclar)) {
    return(.pk_entity_mark_inherited(sonuclar[[1]], onceki, phrase))
  }

  # (5) Kısa kanonik adlar tam soruyu yeniden puanlayarak bulunamaz
  #     ("ANKA 2024 bütçesi nedir" -> J = 1/3). Tek tek belirteçler denenir,
  #     ancak YALNIZCA kayıpsız kesin/alias eşleşmesi kabul edilir.
  for (belirtec in varyantlar$tokens) {
    karar <- coz(belirtec, plural_override = cogul)
    if (karar$decision %in% c("auto", "confirm") &&
        .pk_entity_is_strong_result(karar)) {
      return(.pk_entity_mark_inherited(karar, onceki, phrase))
    }
  }

  ilk
}

# Kalıcı bağlamdan devralma. Kimlik eşleşmezse NULL döner.
.pk_entity_context_decision <- function(prior_context, context_key, ilk, phrase,
                                        cogul) {
  if (is.null(prior_context) || !is.list(prior_context)) return(NULL)

  degerler <- as.character(prior_context$values)
  degerler <- degerler[!is.na(degerler) & nzchar(degerler)]
  if (!length(degerler)) return(NULL)

  # KİMLİK BAĞI: bağlam çözüldüğü sorgu/sütun/varlık türüyle birlikte
  # taşınır. Aynı değeri taşıyan başka bir yaprağa sızmasına izin verilmez.
  # KİMLİK YOKSA DEVRALMA YAPILMAZ: `identical(NULL, NULL)` TRUE döner ve
  # anahtarsız bir bağlamda kimlik bağı HİÇ çalışmadan önceki turun değerleri
  # herhangi bir yaprağa devrolurdu.
  if (is.null(prior_context$key) || is.null(context_key)) return(NULL)
  if (!identical(prior_context$key, context_key)) return(NULL)

  karar <- ilk
  karar$decision <- "confirm"
  karar$rule <- 5L
  karar$values <- character(0)
  karar$chips <- lapply(degerler, function(d) list(
    label = d, value = d, score = 0L, tier = "inherited",
    low_confidence = "inherited", preselected = TRUE
  ))
  karar$total_strong <- length(degerler)
  karar$overflow_count <- 0L
  karar$offer_all <- isTRUE(cogul) && length(degerler) > 1L
  karar$message_tr <- sprintf(
    "Önceki sorunuzdaki bağlamı sürdürüyorum: %s. Onaylıyor musunuz?",
    paste(degerler, collapse = ", ")
  )
  karar$inherited <- TRUE
  karar$inherited_from <- "prior_context"
  karar$original_phrase <- as.character(phrase)[1]
  karar
}

# Çelişen geçmiş yorumları -> netleştirme.
.pk_entity_ambiguous_history <- function(sonuclar, degerler, onceki, phrase) {
  karar <- sonuclar[[1]]
  karar$decision <- "clarify"
  karar$rule <- 2L
  karar$values <- character(0)
  karar$chips <- lapply(degerler, function(d) list(
    label = d, value = d, score = 0L, tier = "inherited",
    low_confidence = "inherited", preselected = FALSE
  ))
  karar$total_strong <- length(degerler)
  karar$overflow_count <- 0L
  karar$offer_all <- FALSE
  karar$message_tr <- paste0(
    "Önceki sorunuz birden fazla biçimde yorumlanabiliyor. Hangisini ",
    "sürdürelim?"
  )
  karar$inherited <- TRUE
  karar$inherited_from <- onceki
  karar$original_phrase <- as.character(phrase)[1]
  karar
}
