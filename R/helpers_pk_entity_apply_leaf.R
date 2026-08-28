# ==============================================================================
# Dosya Yolu: R/helpers_pk_entity_apply_leaf.R
# Açıklama: Faz 4 — filtre planındaki TEK BİR YAPRAĞIN varlık kararı (§5.4).
#
#           NEDEN AYRI DOSYA: `helpers_pk_entity_apply.R` plan gezintisinin
#           orkestrasyonunu tutar; yaprak düzeyi karar (rol tespiti + karar
#           sonuçlarının değere yansıtılması) ayrı bir sorumluluktur ve bakım
#           ratchet'i altında kalması için bölünmüştür. Davranış sözleşmesi
#           `helpers_pk_entity_apply.R` başlığındaki KARAR SONUÇLARI tablosudur.
#
#           İKİ KAPALI BAŞARISIZLIK BURADA YAŞAR:
#             * `config_error` (çözümleyici yapılandırması bozuk) ÖZNE
#               yaprağında analizi REDDEDER; ham model değeri filtreye
#               derlenmez.
#             * Birincil varlık BİLİNMİYORSA ve birden fazla filtre sütunu
#               varsa hiçbir sütun "özne" sayılmaz; ikincil bir daraltmanın
#               çözümlenememesi TÜM analizi durdurmaz.
#
# Dosya saftır: Shiny/reactive/DB/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Sütun sorunun ÖZNESİ mi, ikincil daraltma mı? Kural 6 ile 7'nin farkı budur.
.pk_entity_apply_role <- function(query, column, filter_columns) {
  birincil <- if (exists("pk_meta_primary_entity", mode = "function")) {
    pk_meta_primary_entity(query, filter_columns)
  } else if (is.list(query)) {
    meta <- if (is.list(query$meta)) query$meta else query
    meta$primary_entity
  } else {
    NULL
  }

  # BİRİNCİL VARLIK BİLİNMİYORSA HER SÜTUN "ÖZNE" OLAMAZ. `pk_meta_primary_entity()`
  # küratörlü `primary_entity` yokken ve BİRDEN FAZLA filtre sütunu varken `NULL`
  # döner. Eskiden bu durumda her yaprak "subject" sayılıyordu; çözümlenemeyen bir
  # İKİNCİL daraltma kural 7 (`unfiltered`, düşür + bildir) yerine kural 6
  # (`unresolved`, DURDUR) üretiyor ve TÜM analizi iptal ediyordu.
  if (is.null(birincil) || !length(birincil)) {
    sutunlar <- as.character(filter_columns %||% character(0))
    sutunlar <- unique(sutunlar[!is.na(sutunlar) & nzchar(sutunlar)])
    return(if (length(sutunlar) > 1L) "refinement" else "subject")
  }
  if (identical(as.character(birincil)[1], column)) return("subject")
  "refinement"
}

# Tek bir yaprağın tüm değerlerini çözer. `query` AÇIK PARAMETRE olmalıdır: gövdedeki `.pk_entity_context_key(query, ...)` üst düzey tanımdan ötürü çağıranın ortamını GÖREMEZ; tembel değerlendirme yüzünden hata yalnızca D11 devralma yolunda `object 'query' not found` olarak çıkardı.
.pk_entity_apply_leaf <- function(degerler, sozluk, cmeta, varlik_rolu, meta_kok,
                                  chat_history, prior_context, sutun, query = NULL) {
  kararlar <- list()
  aciklamalar <- character(0)
  yeni_degerler <- character(0)
  durdur <- NA_character_

  for (deger in degerler) {
    karar <- pk_entity_resolve_with_history(
      phrase = deger,
      candidates = sozluk,
      chat_history = chat_history,
      aliases = cmeta$aliases,
      role = cmeta$role,
      match_mode = cmeta$match_mode,
      entity_role = varlik_rolu,
      query_meta = meta_kok,
      entity_kinds = cmeta$entity_kinds,
      prior_context = prior_context,
      # BAĞLAM ANAHTARI SORGU KİMLİĞİNİ DE İÇERİR.
      #
      # `pk_entity_resolve_with_history()` anahtarı TAM KİMLİK olarak
      # karşılaştırır ve sözleşmesi query_id + column + entity_kind'dir.
      # Yalnızca `column` vermek iki yönlü bozuktu: doğru kurulmuş bir bağlam
      # ASLA eşleşemiyordu (devralma ölü koddu) ve eşleşseydi bile iki FARKLI
      # sorgudaki aynı adlı sütun (ör. `ProjeAdi`) birbirinin bağlamını
      # devralabilirdi.
      context_key = .pk_entity_context_key(query, sutun, cmeta)
    )

    karar$column <- sutun
    karar$phrase <- deger
    # BAĞLAM KAYDI İÇİN GEREKEN İKİ ALAN BURADAN GEÇER.
    #
    # `pk_entity_context_remember()` kararın `entity_role` ve `column_meta`
    # alanlarını okur; `pk_entity_resolve*()` bunları DÖNDÜRMEZ ve bu devir
    # yalnızca `column`/`phrase` ekliyordu. Sonuç iki yönlü bozuktu: her karar
    # varsayılan `subject` sayılıyor (sondaki ikincil daraltma gerçek öznenin
    # yerine hatırlanabiliyor) ve saklanan bağlam anahtarı varlık türü OLMADAN
    # kuruluyordu; sonraki turda anahtar `cmeta` ile kurulduğu için kayıt KENDİ
    # kimlik denetimini geçemiyordu.
    karar$entity_role <- varlik_rolu
    karar$column_meta <- cmeta
    kararlar[[length(kararlar) + 1L]] <- karar

    if (identical(karar$decision, "auto") && length(karar$values)) {
      yeni_degerler <- c(yeni_degerler, karar$values)
      next
    }

    if (karar$decision %in% c("confirm", "clarify", "unresolved")) {
      if (is.na(durdur)) durdur <- karar$message_tr
      # Analiz yapılmayacağı için değer olduğu gibi korunur; kullanıcı seçim
      # yaptığında istek yeniden kurulur.
      yeni_degerler <- c(yeni_degerler, deger)
      next
    }

    if (identical(karar$decision, "unfiltered")) {
      # İkincil daraltma çözümlenemedi: DÜŞÜRÜLÜR ve AÇIKÇA bildirilir.
      aciklamalar <- c(aciklamalar, sprintf(
        "'%s' değeri %s sütununda çözümlenemedi; bu daraltma UYGULANMADI.",
        deger, sutun
      ))
      next
    }

    if (identical(karar$decision, "config_error")) {
      aciklamalar <- c(aciklamalar, karar$message_tr)
      # KAPALI BAŞARISIZLIK: `config_error` bir veri belirsizliği DEĞİL, çözümleyici
      # YAPILANDIRMASININ (eşikler / alias kaydı) bozuk olmasıdır. Özne yaprağında
      # ham model değeriyle devam etmek, doğrulanmamış bir varlık değerini SQL
      # filtresine derlemek demekti; `durdur` kurulmadığı için plan "proceed"
      # dönüyordu. Özne yaprağında istek REDDEDİLİR; ikincil daraltmada karar
      # yalnızca bildirilir (değeri düşürmek sonucu GENİŞLETİRDİ).
      # ROLDEN BAĞIMSIZ KAPALI BAŞARISIZLIK: `primary_entity` beyan edilmediğinde
      # ve planda birden fazla filtre sütunu olduğunda HİÇBİR yaprak "subject"
      # olmaz; rol koşulu o durumda `durdur` kurmuyor, plan "proceed" dönüyor ve
      # doğrulanmamış ham değerler SQL filtresine derleniyordu.
      if (is.na(durdur)) {
        durdur <- karar$message_tr
      }
    }

    # disabled / not_applicable / invalid_input / config_error: ham değer kalır.
    yeni_degerler <- c(yeni_degerler, deger)
  }

  list(
    decisions = kararlar,
    disclosures = aciklamalar,
    values = unique(yeni_degerler),
    halt_message = durdur
  )
}

# BOŞ SÖZLÜĞÜN SEBEBİ: dört FARKLI durum aynı `character(0)` ile dönüyordu ve
# hepsi "alan metin değil" diye bildiriliyordu. Sebep artık ayrıştırılır:
#   * `absent`     -> sütun sonuç kümesinde YOK (gerçek bir plan hatası),
#   * `non_text`   -> sayısal/mantıksal/tarih sütun (çözümleme zaten beklenmez),
#   * `empty`      -> sütun metin ama tüm değerler NA/boş,
#   * `no_data`    -> `data` bir veri çerçevesi değil.
.pk_entity_apply_vocab_reason <- function(data, column) {
  if (!is.data.frame(data)) return("no_data")
  if (!(column %in% names(data))) return("absent")
  sutun <- data[[column]]
  if (is.factor(sutun)) sutun <- as.character(sutun)
  if (!is.character(sutun)) return("non_text")
  "empty"
}

# `non_text` için BİLDİRİM ÜRETİLMEZ: sayısal/tarih filtreler (`Yil = 2024`)
# için varlık çözümlemesi hiçbir zaman beklenmez; eski davranış neredeyse HER
# analizde gereksiz bir uyarı gösteriyordu.
.pk_entity_apply_skip_note <- function(sebep, sutun) {
  switch(
    sebep,
    absent = sprintf(paste(
      "`%s` alanı sorgu sonucunda BULUNAMADI; filtre değeri modelden geldiği",
      "gibi kullanıldı ve varlık çözümlemesi uygulanmadı."), sutun),
    empty = sprintf(paste(
      "`%s` alanında çözümlenebilir bir değer yok (tüm değerler boş);",
      "filtre değeri modelden geldiği gibi kullanıldı."), sutun),
    no_data = sprintf(paste(
      "Sonuç kümesi okunamadığı için `%s` alanında varlık çözümlemesi",
      "UYGULANMADI; filtre değeri modelden geldiği gibi kullanıldı."), sutun),
    NULL
  )
}
