# ==============================================================================
# Dosya Yolu: R/helpers_pk_statistical_summary.R
# Açıklama: Proje ve Kaynak Analizi istatistiksel özet kurucusu.
#
#           `generate_statistical_summary()` helpers_pk_analysis_security_summary.R
#           içinden BİREBİR taşınmıştır (yalnızca D8 özyineleme düzeltmesi
#           uygulanmış hâliyle). Amaç bakım yüzeyidir: RLS/kimlik dosyası
#           sözleşme testindeki 400 satır bütçesinin altında kalmalıdır ve
#           master plan §5.7 bu fonksiyonu Faz 2'de analiz paketiyle
#           DEĞİŞTİRECEKTİR; ayrı bir dosyada olması o değişimi izole eder.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

# ÖLÇÜ SÖZLEŞMESİ (PR #705, U45)
#
# `is.numeric()` bir ÖLÇÜ sözleşmesi DEĞİLDİR. Sayısal kimlikler, yıl alanları,
# durum kodları ve toplanamaz oranlar da sayısaldır; bunlara toplam/ortalama/
# standart sapma üretmek modele MAKUL AMA ANLAMSIZ istatistik verir.
#
# Karar sırası:
#   1) Küratörlü sütun metadatası varsa `role`/`additive` KESİNDİR
#      (`measure` + toplanabilir -> ölçü; `dimension`/`date`/`id` -> ölçü değil).
#   2) Metadata YOKSA yalnızca YAPISAL bir kimlik dışlaması uygulanır
#      (tamsayı değerli VE satır başına benzersiz -> kimlik gibi davranır).
#      Bu bir anlam ÜRETMEZ; yalnızca kanıtlanabilir biçimde ölçü OLMAYANI eler.
# Sözlük/eşanlamlı tablosu YOKTUR; her fiziksel sütunun metadatası da GEREKMEZ.
# Metadata YOKKEN kimlik çıkarımı için gereken ASGARİ örneklem. Bunun altında
# benzersizlik hiçbir şey KANITLAMAZ.
.PK_STAT_ID_MIN_ROWS <- 20L

.pk_stat_meta_role <- function(column_meta, col) {
  if (!is.list(column_meta) || !length(column_meta)) return(NULL)
  girdi <- column_meta[[col]]
  if (!is.list(girdi)) return(NULL)
  rol <- girdi$role
  if (!is.character(rol) || !length(rol) || is.na(rol[1]) || !nzchar(rol[1])) return(NULL)
  list(role = tolower(trimws(rol[1])), additive = girdi$additive)
}

.pk_stat_is_measure <- function(values, column_meta, col) {
  bilgi <- .pk_stat_meta_role(column_meta, col)
  if (!is.null(bilgi)) {
    if (!identical(bilgi$role, "measure")) return(FALSE)
    # TOPLANABİLİRLİK AÇIKÇA `TRUE` OLMALIDIR.
    #
    # Eksik/`NA`/mantıksal olmayan/vektör bir `additive` değeri "toplanabilir"
    # DEĞİL, "toplulaştırma sözleşmesi BİLİNMİYOR" demektir. Eskiden bu durum
    # `TRUE` sayılıyordu ve oran, yüzde, anlık bakiye gibi bir ölçü için
    # toplam/ortalama üretiliyordu; model bu sayıyı gerçek bir ölçü gibi
    # aktarır. Bu, `is.numeric()` yerine metadata koymanın TAM OLARAK önlemek
    # istediği hatadır. Metadata HİÇ yoksa davranış değişmez (aşağıdaki
    # yapısal kimlik dışlaması); değişen yalnızca "metadata var ama eksik"
    # hâlidir ve o hâlde karar KAPALI BAŞARISIZdır.
    if (!(is.logical(bilgi$additive) && length(bilgi$additive) == 1L &&
          isTRUE(bilgi$additive))) {
      return(FALSE)
    }
    return(TRUE)
  }

  # Metadata yok: yalnızca KANITLANABİLİR kimlik dışlaması.
  #
  # Benzersizlik TEK BAŞINA zayıf kanıttır: 3 satırlık gerçek bir ölçü de
  # benzersiz olur. Bu yüzden dışlama için YETERLİ ÖRNEKLEM aranır; altında
  # hiçbir anlam ÜRETİLMEZ ve sütun ölçü sayılır (mevcut davranış korunur).
  gecerli <- values[!is.na(values)]
  if (length(gecerli) < .PK_STAT_ID_MIN_ROWS) return(TRUE)
  tamsayi <- all(is.finite(gecerli)) && isTRUE(all(gecerli == round(gecerli)))
  if (!tamsayi) return(TRUE)
  if (length(unique(gecerli)) != length(gecerli)) return(TRUE)

  # BENZERSİZLİK + TAMSAYILIK TEK BAŞINA KİMLİK KANITI DEĞİLDİR.
  #
  # Gerçek bir ölçü de bu testi geçer: 24 satırlık bir sonuçta `Tutar`
  # sütunundaki tutarlar tam sayı ve birbirinden farklı olabilir. Eski kural
  # o sütunu `num_cols` dışına atıyor; toplam/ortalama/medyan/std ÜRETİLMİYOR
  # ve istem bloğu modele "bu değerleri ASLA toplama" diyordu. Kullanıcı
  # gerçek bir ölçünün doğru toplamını KAYBEDİYORDU.
  #
  # Vekil anahtarın (surrogate key) ürettiği YOĞUN ARTAN dizi aranır:
  # `max - min + 1 == n`. `1..24` bu testi geçer, dağınık tutarlar geçmez.
  # Yoğunluk kanıtlanamıyorsa sütun ÖLÇÜ sayılır (kapalı başarısızlık yönü
  # burada "istatistik üret"tir; anlam metadata ile kesinleşir).
  # `integer` ÇIKARMASI TAŞABİLİR: SQL `INT` sütunu R'de `integer` gelir; benzersiz tam değerlerin açıklığı `2^31 - 1` üzerindeyse çıkarma "NAs produced by integer overflow" uyarısı üretir. Sınıflandırma yönü güvenli kalır ama uyarı NORMAL analiz yolunda doğar ve süite `stop_on_warning = TRUE` ile çalışır.
  sinirlar <- as.numeric(c(min(gecerli), max(gecerli)))
  aralik <- sinirlar[2] - sinirlar[1] + 1
  !isTRUE(aralik == length(gecerli))
}

generate_statistical_summary <- function(data, max_preview_rows = 20, max_total_chars = MAX_ANALYSIS_PROMPT_CHARS, mode = "summary", rls_total_rows = NULL, user_filter_applied = FALSE, pre_aggregated_columns = NULL, column_meta = NULL) {
  # Kolon adlarını okunabilir hale getirme fonksiyonu
  prettify_col_name <- function(col) {
    # CamelCase ayırma
    col <- gsub("([a-z])([A-Z])", "\\1 \\2", col)
    # Alt çizgi ve noktaları boşluk yap
    col <- gsub("_|\\.", " ", col)
    # Baş harfleri büyük yap
    col <- gsub("\\b([a-z])", "\\U\\1", col, perl = TRUE)
    return(col)
  }

  if (is.null(data) || nrow(data) == 0) {
    return(list(
      summary_text = "Veri yok.",
      row_count = 0,
      preview_data = NULL
    ))
  }

  total_rows <- nrow(data)
  total_cols <- ncol(data)
  col_names <- names(data)

  dt <- data.table::as.data.table(data)

  num_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
  cat_cols <- names(dt)[vapply(dt, function(x) is.character(x) || is.factor(x), logical(1))]

  # U45: sayısal depolama tipi ölçü DEMEK DEĞİLDİR (yukarıdaki sözleşme).
  olcu_disi <- character(0)
  olcu_belirsiz <- character(0)
  if (length(num_cols) > 0) {
    olcu_mu <- vapply(
      num_cols,
      function(col) .pk_stat_is_measure(dt[[col]], column_meta, col),
      logical(1)
    )
    disarida <- num_cols[!olcu_mu]
    # KAPALI BAŞARISIZ KARAR AYNI, İFŞA METNİ FARKLI.
    #
    # `role = "measure"` ama `additive` beyan EDİLMEMİŞ bir sütun ölçü
    # muamelesi görmez (doğru), ama "kimlik/kod/yıl gibi" DEĞİLDİR. Tek metin
    # kullanmak, modele gerçek bir ölçüyü KİMLİK diye tanıtıyor ve model bu
    # sınıflandırmayı kullanıcıya tekrarlayabiliyordu.
    belirsiz_mu <- vapply(disarida, function(col) {
      bilgi <- .pk_stat_meta_role(column_meta, col)
      is.list(bilgi) && identical(bilgi$role, "measure")
    }, logical(1))
    olcu_belirsiz <- disarida[belirsiz_mu]
    olcu_disi <- disarida[!belirsiz_mu]
    num_cols <- num_cols[olcu_mu]
  }

  # Önceden toplulaştırılmış sütunları sayısal özetten çıkar
  pre_agg_cols <- character(0)
  if (!is.null(pre_aggregated_columns) && length(pre_aggregated_columns) > 0) {
    pre_agg_cols <- intersect(pre_aggregated_columns, num_cols)
    if (length(pre_agg_cols) > 0) {
      num_cols <- setdiff(num_cols, pre_agg_cols)
      cat(sprintf("[PK_ANALIZ] Önceden toplulaştırılmış sütunlar istatistik özetinden çıkarıldı: %s\n",
                  paste(pre_agg_cols, collapse = ", ")))
    }
  }

  summary_parts <- list()
  summary_parts[[1]] <- sprintf("TOPLAM SATIR: %d | TOPLAM SUTUN: %d", total_rows, total_cols)

  # NA satır sayısı bir KARŞILAŞTIRMA DEĞİLDİR: `NA > n` koşulu `NA` döner ve
  # R "missing value where TRUE/FALSE needed" hatası verir. `generate_statistical_summary()`
  # tryCatch taşımadığı için tüm analiz isteği düşerdi; `isTRUE()` kapatır.
  if (isTRUE(user_filter_applied) && isTRUE(rls_total_rows > total_rows)) {
    summary_parts[[length(summary_parts) + 1]] <- sprintf(
      "\n\n\U000026A0\U0000FE0F FİLTRELEME UYARISI:\n- Yetki dahilinde toplam satır: %d\n- Kullanıcı filtreleme sonrası satır: %d\n- BU %d SATIR SPESİFİK FİLTRELEME KRİTERİNE AİTTİR (tüm veri için değil!)\n- Oran/yüzde hesaplarken SADECE filtreleme sonrası %d satırı referans al",
      rls_total_rows, total_rows, total_rows, total_rows
    )
  }

  # Önceden toplulaştırılmış sütunlar hakkında AI'a uyarı ekle
  if (length(pre_agg_cols) > 0) {
    pretty_names <- vapply(pre_agg_cols, prettify_col_name, character(1))
    summary_parts[[length(summary_parts) + 1]] <- sprintf(
      paste0(
        "\n\n\U000026A0\U0000FE0F ÖNCEDEN TOPLULAŞTIRILMIŞ SÜTUN UYARISI:\n",
        "Aşağıdaki sütunlar SQL sorgusunda zaten toplulaştırılmıştır (SUM/AVG/COUNT OVER PARTITION BY vb.):\n",
        "- %s\n",
        "Bu sütunlardaki değerler satırlar arasında tekrar edebilir.\n",
        "ASLA bu sütunlara toplam, ortalama veya herhangi bir istatistiksel özet hesaplama UYGULAMA.\n",
        "Bu sütunları YALNIZCA satır bazında yorumla, olduğu gibi aktar."
      ),
      paste(pretty_names, collapse = ", ")
    )
  }

  if (length(olcu_disi) > 0) {
    # Sütunlar GİZLENMEZ; yalnızca ÖLÇÜ MUAMELESİ GÖRMEZ. Model bunları satır
    # bazında okuyabilir, ama toplam/ortalama üretmemelidir.
    summary_parts[[length(summary_parts) + 1]] <- sprintf(
      paste0(
        "\n\n\U000026A0\U0000FE0F ÖLÇÜ OLMAYAN SAYISAL SÜTUNLAR:\n",
        "- %s\n",
        "Bu sütunlar sayısal saklanır ama ÖLÇÜ DEĞİLDİR (kimlik/kod/yıl gibi).\n",
        "ASLA toplam, ortalama, medyan veya standart sapma hesaplama."
      ),
      paste(vapply(olcu_disi, prettify_col_name, character(1)), collapse = ", ")
    )
  }

  if (length(olcu_belirsiz) > 0) {
    # TOPLULAŞTIRMA SÖZLEŞMESİ BİLİNMİYOR: sütun bir ÖLÇÜdür ama `additive`
    # beyan edilmediği için toplam/ortalama ÜRETİLMEZ (kapalı başarısız).
    summary_parts[[length(summary_parts) + 1]] <- sprintf(
      paste0(
        "\n\n\U000026A0\U0000FE0F TOPLULAŞTIRMA SÖZLEŞMESİ BİLİNMEYEN ÖLÇÜLER:\n",
        "- %s\n",
        "Bu sütunlar ÖLÇÜDÜR ama toplanabilirlikleri (additive) BEYAN EDİLMEMİŞTİR.\n",
        "Kimlik/kod/yıl DEĞİLDİRLER; yalnızca toplam/ortalama/medyan/standart ",
        "sapma HESAPLANAMAZ. Değerleri satır bazında olduğu gibi aktar."
      ),
      paste(vapply(olcu_belirsiz, prettify_col_name, character(1)), collapse = ", ")
    )
  }

  if (length(num_cols) > 0) {
    num_summary_list <- lapply(num_cols, function(col) {
      vals <- dt[[col]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(NULL)

      # `integer64` İSTATİSTİK FONKSİYONLARINA GİRMEDEN ÖNCE ÇEVRİLİR.
      #
      # `bit64::integer64` `is.numeric()` denetimini geçer, ama `sd()`/`median()`
      # bu sınıfa dispatch etmez ve HAM DOUBLE BİT DESENİ üzerinden hesap yapıp
      # anlamsız bir `StdSapma` üretirdi. `Toplam`/`Min`/`Max` de aynı riski
      # taşır. 2^53 üstü büyüklüklerde hassasiyet kaybı olabileceği için çevrim
      # AÇIKÇA yapılır; sessiz bir bit deseni yerine bilinen bir yaklaşımdır.
      if (inherits(vals, "integer64")) vals <- as.numeric(vals)
      # `integer` TOPLAMI TAŞABİLİR (PR #705 incelemesi, P3).
      #
      # R 4.5 öncesinde `sum(<integer>)` 2^31-1 sınırını aşınca UYARI verip
      # `NA` döner. Sonuç kümesinde büyük bir tam sayı ölçüsü varken model
      # `Toplam = NA` görürken `Ortalama`/`Medyan` dolu kalıyor ve TUTARSIZ bir
      # toplam sunulabiliyordu; test paketi `stop_on_warning = TRUE` ile
      # çalıştığı için aynı uyarı eski R sürümlerinde paketi de kırardı.
      # Toplama öncesi açık çevrim davranışı sürümden BAĞIMSIZ kılar.
      if (is.integer(vals)) vals <- as.numeric(vals)

      data.frame(
        Sutun = prettify_col_name(col),
        Toplam = sum(vals, na.rm = TRUE),
        Ortalama = mean(vals, na.rm = TRUE),
        Medyan = median(vals, na.rm = TRUE),
        Min = min(vals, na.rm = TRUE),
        Max = max(vals, na.rm = TRUE),
        StdSapma = sd(vals, na.rm = TRUE),
        Kayit = length(vals),
        stringsAsFactors = FALSE
      )
    })

    num_summary_df <- do.call(rbind, Filter(Negate(is.null), num_summary_list))

    if (!is.null(num_summary_df) && nrow(num_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nSAYISAL SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(num_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }

  date_cols <- names(dt)[vapply(dt, function(x) inherits(x, "Date") || inherits(x, "POSIXt"), logical(1))]
  if (length(date_cols) > 0) {
    date_summary_list <- lapply(date_cols, function(col) {
      vals <- dt[[col]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(NULL)

      data.frame(
        Sutun = prettify_col_name(col),
        EnEskiTarih = as.character(min(vals)),
        EnYeniTarih = as.character(max(vals)),
        KayitSayisi = length(vals),
        stringsAsFactors = FALSE
      )
    })

    date_summary_df <- do.call(rbind, Filter(Negate(is.null), date_summary_list))

    if (!is.null(date_summary_df) && nrow(date_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nTARIH SUTUNLARI OZETI (TUM VERİ UZERINDEN):"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(date_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }

  if (length(cat_cols) > 0) {
    cat_summary_list <- lapply(head(cat_cols, 5), function(col) {
      tbl <- sort(table(dt[[col]], useNA = "no"), decreasing = TRUE)
      # SIFIR SAYILI DÜZEYLER GÖZLEM DEĞİLDİR: `table()` faktör sütununda
      # KULLANILMAYAN düzeyleri de tutar; tamamı `NA` olan bir faktör sütunu
      # için modele `Adet = 0` ile rastgele bir "en sık değer" bildiriliyordu.
      # Aynı içerikteki `character` sütun ise atlanıyor, iki depolama türü
      # birbiriyle ÇELİŞİYORDU.
      tbl <- tbl[tbl > 0]
      top5 <- head(tbl, 5)

      # FIX: If top5 is empty, return NULL to skip this column
      if (length(top5) == 0) {
        return(NULL)
      }

      # FIX: Handle potential NA in names explicitly
      top_name <- names(top5)[1]
      if (is.null(top_name) || is.na(top_name)) top_name <- "Yok"

      data.frame(
        Sutun = prettify_col_name(col),
        EnSikDeger = top_name,
        Adet = as.integer(top5[1]),
        # `EnSikDeger`/`Adet` `table(..., useNA = "no")` üzerinden gelir, yani
        # eksik değeri DIŞLAR. Ham `unique()` ise `NA`yı ayrı bir kategori
        # sayıyor ve modele GERÇEK kategori sayısından bir fazlasını
        # bildiriyordu; bu sayı kullanıcıya raporlanabiliyordu.
        BenzerSayi = length(unique(dt[[col]][!is.na(dt[[col]])])),
        stringsAsFactors = FALSE
      )
    })

    # Remove NULL results before rbind (Prevents list of NULLs crashing rbind)
    cat_summary_list <- Filter(Negate(is.null), cat_summary_list)
    cat_summary_df <- do.call(rbind, cat_summary_list)

    if (!is.null(cat_summary_df) && nrow(cat_summary_df) > 0) {
      summary_parts[[length(summary_parts) + 1]] <- "\n\nKATEGORIK SUTUNLAR OZETI:"
      summary_parts[[length(summary_parts) + 1]] <- paste(capture.output(print(cat_summary_df, row.names = FALSE)), collapse = "\n")
    }
  }

  preview_data <- NULL
  if (mode == "full") {
    full_table_md <- paste0(
      "+===============================================================+\n",
      "|           DETAYLI İSTATİSTİKSEL ANALİZ MODU                 |\n",
      "+===============================================================+\n\n",
      "AŞAĞIDAKİ TÜM SÜTUNLARI DETAYLI ANALİZ ET!\n\n"
    )

    full_table_md <- paste0(full_table_md, sprintf("**Toplam Satır Sayısı:** %d | **Toplam Sütun Sayısı:** %d\n", total_rows, total_cols))

    if (total_rows > 0) {
      cat_summary <- paste0("\n**Örnek Veri Yapısı (İlk 3 Satır):**\n")
      preview_rows <- head(data, min(3, nrow(data)))
      for (i in seq_len(nrow(preview_rows))) {
        row_data <- paste0(names(preview_rows), ": ", sapply(preview_rows[i, ], as.character), collapse = " | ")
        cat_summary <- paste0(cat_summary, sprintf("Satır %d: %s\n", i, row_data))
      }
      full_table_md <- paste0(full_table_md, cat_summary)
    }

    summary_parts[[1]] <- full_table_md
    preview_data <- head(data, min(5, nrow(data)))
  } else {
    if (total_rows > max_preview_rows) {
      preview_data <- head(data, max_preview_rows)
      summary_parts[[length(summary_parts) + 1]] <- sprintf("\n\n(İlk %d satir gosteriliyor; toplam %d satir mevcut)", max_preview_rows, total_rows)
    } else {
      preview_data <- data
    }
  }

  # Prompt boyutunu kontrol et ve gerektiğinde kırp
  current_text <- paste(summary_parts, collapse = "\n")
  if (nchar(current_text) > max_total_chars) {
    cat(sprintf("[PK_ANALIZ] UYARI: Prompt çok büyük (%d karakter), kırpılıyor.\n", nchar(current_text)))
    # D8: ozyineleme mode / rls_total_rows / user_filter_applied parametrelerini
    # DUSURUYORDU; bu yuzden "FILTRELEME UYARISI" blogu tam da verinin buyuk
    # oldugu durumda kayboluyordu. Artik TUM baglam tek yoldan aktarilir.
    # Önce preview satır sayısını yarıya indir
    if (max_preview_rows > 5) {
      # v1 ozyinelemesi de KAPSAM argumanlarini tasir. Aksi halde
      # kirpilan bir `mode="full"` istegi sessizce `summary`'ye donuyor ve
      # FILTRELENMIS bir istek, sayilarin yalnizca filtreli kumeyi anlattigi
      # UYARISINI kaybediyordu. Kirpma yalnizca onizleme satirlarini azaltmali,
      # analiz semantigini DEGISTIRMEMELIDIR.
      return(generate_statistical_summary(
        data,
        max_preview_rows = floor(max_preview_rows / 2),
        max_total_chars = max_total_chars,
        mode = mode,
        rls_total_rows = rls_total_rows,
        user_filter_applied = user_filter_applied,
        pre_aggregated_columns = pre_aggregated_columns,
        column_meta = column_meta
      ))
    }
    # Eğer hala büyükse, sadece temel özet gönder
    basic_summary <- sprintf("TOPLAM SATIR: %d | TOPLAM SUTUN: %d", total_rows, total_cols)
    # FİLTRELEME UYARISI MOTOR BAYRAĞINA BAĞLI DEĞİLDİR.
    #
    # Ana özet yolunda (yukarıda) bu uyarı `pk_v2` koşulu OLMADAN üretilir.
    # Terminal geri düşmede `pk_v2 &&` koşulu vardı: v1'de `mode = "full"`
    # bir istek önizleme kırpması beş satıra indikten sonra buraya düşünce,
    # yanıt FİLTRELENMİŞ bir alt kümeyi anlatıp kapsam uyarısını KAYBEDİYORDU.
    # NA satır sayısı için `isTRUE()` (yukarıdaki kapı ile aynı gerekçe).
    if (isTRUE(user_filter_applied) && isTRUE(rls_total_rows > total_rows)) {
      basic_summary <- paste0(
        basic_summary,
        sprintf(
          "\n\n\U000026A0\U0000FE0F FİLTRELEME UYARISI:\n- Yetki dahilinde toplam satır: %d\n- Kullanıcı filtreleme sonrası satır: %d\n- BU %d SATIR SPESİFİK FİLTRELEME KRİTERİNE AİTTİR (tüm veri için değil!)\n- Oran/yüzde hesaplarken SADECE filtreleme sonrası %d satırı referans al",
          rls_total_rows, total_rows, total_rows, total_rows
        )
      )
    }
    return(list(
      summary_text = basic_summary,
      row_count = total_rows,
      preview_data = head(data, 5)
    ))
  }

  summary_text <- paste(summary_parts, collapse = "\n")

  return(list(
    summary_text = summary_text,
    row_count = total_rows,
    preview_data = preview_data
  ))
}