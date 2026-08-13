# ==============================================================================
# Dosya Yolu: R/helpers_pk_analysis_filters_v2.R
# Açıklama: Proje ve Kaynak Analizi v2 filtre yürütücüsü.
#
#           Derleyici (helpers_pk_filter_compile.R) ve politika
#           (helpers_pk_filter_policy.R) saf katmanlardır; bu dosya ikisini
#           birleştirip v1 ile AYNI dönüş şeklini üretir. Böylece modül tarafı
#           tek bir `apply_smart_filters()` sözleşmesiyle çalışmaya devam eder.
#
#           v1'den ayrılan noktalar (tümü MERGEN_PK_ENGINE=v2 arkasında):
#             * D5 — `filter_expression` ASLA değerlendirilmez; `eval(parse())`
#                    yolu yoktur. Alan gelirse tipli bir düşürme kaydı üretilir.
#             * D12 — ölü "genel soru" muhafızı yoktur.
#             * D1/D2/D3 — derleyici üzerinden.
#             * D4 — politika üzerinden; karar öznitelik olarak taşınır.
# ==============================================================================

# Politika kararı ve köken bilgisi çağırana ÖZNİTELİK ile taşınır; dönüş tipi
# (data.frame) v1 ile birebir aynı kalır.
PK_FILTER_V2_ATTR <- "pk_filter_v2"

# Politika sonrası GERÇEKTEN yürürlükte kalan yaprakları döndürür.
.pk_v2_retained_leaves <- function(groups, dropped_columns = character(0)) {
  dropped_columns <- as.character(dropped_columns %||% character(0))
  kalan <- Filter(function(g) !(g$column %in% dropped_columns), groups %||% list())
  unlist(lapply(kalan, function(g) g$applied), recursive = FALSE) %||% list()
}

# Desteklenen toplulaştırmalar; bunun dışındaki bir değer SESSİZCE ham satır
# listesine düşmez, tipli bir red üretir.
PK_FILTER_V2_AGGREGATIONS <- c("list", "none", "count", "sum", "group_by")

# Toplanabilir ölçü sütunları. Metadata sütun tanımı YOKSA (Tier-0 / eski
# sorgu) davranış korunur ve tüm sayısal sütunlar toplanabilir sayılır; aksi
# hâlde bu değişiklik metadata'sız her sorguyu reddederdi. Metadata VARSA
# `pk_meta_aggregate_for()` tek yetkilidir ve "sum" demediği sütun toplanmaz.
.pk_v2_additive_columns <- function(query, numeric_columns) {
  numeric_columns <- as.character(numeric_columns %||% character(0))
  if (!length(numeric_columns)) return(character(0))

  meta <- if (is.list(query)) (query$meta %||% query) else NULL
  sutun_meta <- if (is.list(meta)) meta$column_meta else NULL
  if (!is.list(sutun_meta) || !length(sutun_meta)) return(numeric_columns)

  if (!exists("pk_meta_aggregate_for", mode = "function", inherits = TRUE)) {
    return(numeric_columns)
  }

  Filter(function(sutun) {
    if (!(sutun %in% names(sutun_meta))) return(FALSE)
    identical(tryCatch(pk_meta_aggregate_for(query, sutun), error = function(e) "none"), "sum")
  }, numeric_columns)
}

#' v2 filtre yürütmesi
#'
#' @return v1 ile aynı şekilde bir data.frame; `attr(x, PK_FILTER_V2_ATTR)`
#'   politika kararını, ifşaları ve köken kayıtlarını taşır.
pk_apply_smart_filters_v2 <- function(data, filter_instructions, query = NULL) {
  filter_instructions <- if (is.list(filter_instructions)) filter_instructions else list()

  filters <- filter_instructions$filters %||% list()
  aggregation <- filter_instructions$aggregation
  group_col <- filter_instructions$group_column

  sonuc_ekle <- function(df, matched_rows, karar) {
    attr(df, PK_FILTER_V2_ATTR) <- karar
    df
  }

  bos_karar <- list(
    action = "proceed", refusal_message = NULL, disclosures = character(0),
    dropped = list(), noop_columns = character(0), applied = list(),
    matched_rows = 0L, primary_column = NULL
  )

  if (nrow(data) == 0L) {
    return(sonuc_ekle(data.frame(), 0L, bos_karar))
  }

  # D5: filter_expression bilerek YOK SAYILIR. v1'de bu alan
  # `subset(dt, eval(parse(text = expr_str)))` ile çalıştırılıyordu; ifade
  # metni LLM üretimi olduğundan bu, prompt enjeksiyonuyla erişilebilen
  # RCE biçimli bir yoldu.
  ifade_dusurmesi <- list()
  ifade <- filter_instructions$filter_expression
  if (!is.null(ifade) && nzchar(as.character(ifade)[1])) {
    ifade_dusurmesi <- list(list(
      leaf = list(column = "filter_expression", values = character(0)),
      reason = "çalıştırılabilir ifade v2 motorunda kabul edilmez"
    ))
    cat("[SMART_FILTER_V2] filter_expression yok sayildi (D5: eval(parse) kaldirildi).\n")
  }

  # --- Faz 4 (§5.4): VARLIK ÇÖZÜMLEME -------------------------------------
  # Filtre planı doğrulandıktan SONRA, derlemeden ÖNCE. Bulanıklık HANGİ
  # DEĞERİN filtreleneceğini çözer, hangi satırın değil; bu yüzden derleyiciye
  # her zaman KANONİK değerler gider. Belirsiz/çözümlenemeyen bir ÖZNE analizi
  # DURDURUR: yanlış bir varlık üzerinden üretilmiş sayı, hiç yanıt
  # vermemekten daha zararlıdır.
  cozumleme <- NULL
  if (exists("pk_entity_resolve_filter_plan", mode = "function")) {
    cozumleme <- tryCatch(
      pk_entity_resolve_filter_plan(
        data = data, filters = filters, query = query,
        chat_history = filter_instructions$chat_history,
        prior_context = filter_instructions$prior_entity_context
      ),
      error = function(e) {
        # KAPALI BAŞARISIZ: çözümleyici hatası "çözümleme yokmuş gibi devam et"
        # ANLAMINA GELMEZ. Geçici bir bağımlılık/yapılandırma hatası, HANGİ
        # DEĞERİN filtreleneceğini sessizce değiştirir (kanonik değer yerine ham
        # LLM değeri) ve kullanıcı bunu göremez. Analiz durdurulur.
        cat(sprintf("[SMART_FILTER_V2] Varlik cozumleme HATASI: %s\n",
                    conditionMessage(e)))
        list(
          action = "halt",
          filters = filters,
          decisions = list(),
          disclosures = character(0),
          message_tr = paste0(
            "\U000026A0\U0000FE0F **Analiz yapılamadı:** Sorunuzdaki varlık ",
            "(proje/kişi/masraf yeri) adı doğrulanamadı. Doğrulanmamış bir ",
            "değer üzerinden üretilen sayı yanıltıcı olacağı için analiz ",
            "DURDURULDU. Lütfen tekrar deneyin."
          )
        )
      }
    )
  }

  if (!is.null(cozumleme)) {
    filters <- cozumleme$filters

    if (identical(cozumleme$action, "halt")) {
      karar <- bos_karar
      karar$action <- "refuse"
      karar$refusal_message <- cozumleme$message_tr
      karar$disclosures <- cozumleme$disclosures
      karar$entity_decisions <- cozumleme$decisions
      karar$matched_rows <- 0L
      return(sonuc_ekle(data[0, , drop = FALSE], 0L, karar))
    }
  }

  derleme <- pk_filter_compile(data, filters, query = query)
  politika <- pk_filter_zero_match_policy(data, filters, derleme, query)

  # Sıfır eşleşme nedeniyle DÜŞÜRÜLEN ikincil sütunlar da köken kaydına girer;
  # böylece Faz 0'ın gözlem hattı bunları kullanıcıya görünen alt bilgide
  # "düşürülen filtre" uyarısı olarak yayımlar.
  sifir_dusurmeleri <- list()
  if (identical(politika$action, "dropped_secondary")) {
    sifir_dusurmeleri <- lapply(politika$dropped_columns, function(sutun) {
      list(
        leaf = list(column = sutun, values = character(0)),
        reason = "hiçbir kayıtla eşleşmediği için uygulanmadı"
      )
    })
  }

  dusenler <- c(derleme$dropped, ifade_dusurmesi, sifir_dusurmeleri)

  karar <- list(
    action = politika$action,
    refusal_message = politika$refusal_message,
    disclosures = c(
      politika$disclosures,
      if (is.null(cozumleme)) character(0) else cozumleme$disclosures
    ),
    entity_decisions = if (is.null(cozumleme)) list() else cozumleme$decisions,
    dropped = dusenler,
    dropped_columns = politika$dropped_columns,
    noop_columns = derleme$noop_columns,
    primary_column = politika$primary_column,
    # RAPORLANAN FİLTRELER = POLİTİKADAN SONRA GERÇEKTEN KALANLAR.
    #
    # Eskiden burada derleyicinin uyguladığı TÜM yapraklar bildiriliyordu;
    # oysa sıfır eşleşme politikası bir kısmını sonradan DÜŞÜRÜP maskeyi
    # yeniden derliyor. Köken alt bilgisi/telemetri bu yüzden uygulanmamış bir
    # filtreyi uygulanmış gibi gösterebiliyordu.
    applied = .pk_v2_retained_leaves(derleme$groups, politika$dropped_columns),
    groups = derleme$groups
  )

  if (identical(politika$action, "refuse")) {
    karar$matched_rows <- 0L
    return(sonuc_ekle(data[0, , drop = FALSE], 0L, karar))
  }

  maske <- politika$mask
  if (is.null(maske)) maske <- rep(TRUE, nrow(data))
  filtrelenmis <- data[maske, , drop = FALSE]
  eslesen <- nrow(filtrelenmis)
  karar$matched_rows <- eslesen

  cat(sprintf(
    "[SMART_FILTER_V2] Filtre grubu: %d | eslesen satir: %d / %d\n",
    length(derleme$groups), eslesen, nrow(data)
  ))

  if (!is.null(aggregation)) {
    # Yerelden bağımsız ASCII küçük harf: Türkçe Windows'ta `tolower()` "I"yı
    # noktasız `ı` yapar ve büyük harfle gelen bir toplulaştırma adı sessizce
    # tanınmaz hâle gelir.
    agg <- if (exists("pk_ascii_token", mode = "function", inherits = TRUE)) {
      pk_ascii_token(as.character(aggregation)[1])
    } else {
      chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz",
             trimws(as.character(aggregation)[1]))
    }

    reddet <- function(mesaj) {
      karar$action <- "refuse"
      karar$refusal_message <- mesaj
      karar$matched_rows <- 0L
      sonuc_ekle(data[0, , drop = FALSE], 0L, karar)
    }

    # BİLİNMEYEN TOPLULAŞTIRMA SESSİZCE HAM SATIRA DÜŞMEZ.
    #
    # Eskiden tanınmayan bir `aggregation` değeri (ya da eksik/geçersiz
    # `group_column`) hiçbir dala girmiyor ve fonksiyon filtrelenmiş HAM
    # satırları döndürüyordu. Kullanıcı "departman bazında topla" derken
    # binlerce satırlık ham liste alıyor, üstelik bunu istediği özet sanıyordu.
    if (!(agg %in% PK_FILTER_V2_AGGREGATIONS)) {
      return(reddet(paste0(
        "\U000026A0\U0000FE0F **Analiz yapılamadı:** İstenen özetleme biçimi (`",
        as.character(aggregation)[1], "`) desteklenmiyor. Lütfen sorunuzu ",
        "sayma, toplama veya gruplama olarak yeniden ifade edin."
      )))
    }

    if (identical(agg, "count")) {
      aciklama <- if (length(filters) > 0) "Filtrelenen Kayıt Sayısı" else "Toplam Kayıt Sayısı"
      return(sonuc_ekle(
        data.frame(Sonuc = aciklama, Adet = eslesen, stringsAsFactors = FALSE),
        eslesen, karar
      ))
    }

    if (identical(agg, "sum")) {
      # TOPLAMA YALNIZCA METADATA'NIN TOPLANABİLİR (additive) İLAN ETTİĞİ
      # ÖLÇÜLERE UYGULANIR.
      #
      # Eskiden her sayısal sütun toplanıyordu; oran, yüzde, birim fiyat,
      # stok/anlık bakiye ve ID benzeri sütunlar da dâhil. Bunların toplamı
      # ANLAMSIZDIR ve model bu sayıyı gerçek bir ölçü gibi aktarır.
      sayisal <- names(filtrelenmis)[vapply(filtrelenmis, is.numeric, logical(1))]
      toplanabilir <- .pk_v2_additive_columns(query, sayisal)

      if (!length(toplanabilir)) {
        return(reddet(paste0(
          "\U000026A0\U0000FE0F **Toplama yapılamadı:** Bu sorgunun sonucunda ",
          "toplanabilir (additive) olarak tanımlanmış bir ölçü sütunu yok. ",
          "Oran/yüzde/birim değer gibi sütunların toplamı yanıltıcı olacağı ",
          "için toplama YAPILMADI. Sayma veya gruplama deneyebilirsiniz."
        )))
      }

      toplamlar <- lapply(toplanabilir, function(nc) sum(filtrelenmis[[nc]], na.rm = TRUE))
      names(toplamlar) <- toplanabilir
      return(sonuc_ekle(as.data.frame(toplamlar, stringsAsFactors = FALSE), eslesen, karar))
    }

    if (identical(agg, "group_by")) {
      if (is.null(group_col) || !(as.character(group_col)[1] %in% names(filtrelenmis))) {
        return(reddet(paste0(
          "\U000026A0\U0000FE0F **Gruplama yapılamadı:** Gruplanacak sütun (`",
          as.character(group_col %||% "belirtilmedi")[1],
          "`) sonuç kümesinde bulunamadı. Ham kayıt listesi döndürmek ",
          "sorduğunuz sorudan başka bir soruyu yanıtlardı."
        )))
      }
      dt <- data.table::as.data.table(filtrelenmis)
      return(sonuc_ekle(as.data.frame(dt[, .N, by = group_col]), eslesen, karar))
    }
  }

  sonuc_ekle(as.data.frame(filtrelenmis), eslesen, karar)
}
