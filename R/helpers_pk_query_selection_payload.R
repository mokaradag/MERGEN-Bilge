# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_payload.R
# Açıklama: Faz 5 (§5.2) — iki geçişin İSTEM YÜKÜ (payload) kurucuları.
#
#           Geçiş A (recall): TÜM kütüphane, sorgu başına TEK kompakt satır.
#           Geçiş B (precision): yalnızca çözümlenmiş adaylar, TAM ayrıntı.
#
# GERİ ALINAMAZLIK İLKESİ: Geçiş A'da görünmeyen bir kanıt SONSUZA DEK
# kaybolur. Sözlüksel katmanın aday EKLEMESİ yasaktır (D10), bu yüzden Geçiş B
# hiçbir zaman elenmiş bir sorguyu geri getiremez. Bu nedenle recall satırı
# artık `intents`, `not_for`, beyan edilen `entity` ve sütun ETİKETLERİNİ de
# taşır: bunların her biri bir sorgunun TEK ayırt edici kanıtı olabilir.
#
# TERSİ DE DOĞRUDUR: Geçiş B, Geçiş A'nın anlamsal ÜST KÜMESİ olmalıdır. Aksi
# hâlde doğru sorgu aday kümesine girer ama precision modeli onu isteğe
# bağlayan tek kanıtı göremez.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
#
# KARARLI KİMLİK SÖZLEŞMESİ (D13): her iki geçiş de `q042` gibi KARARLI `id`
# alanını taşır. Liste KONUMU asla gönderilmez ve asla geri okunmaz.
# ==============================================================================

# Kararlı kimlik DİL BİLGİSİ. Kimlik hem satır tabanlı Geçiş A yüküne hem de
# `--- SORGU <id> ---` Geçiş B ayraçlarına HAM olarak girer; içinde `|`,
# satır sonu ya da başka bir ayraç taşıyan bir kimlik modelin gördüğü YAPIYI
# değiştirir ve metadata'yı yanlış sorguyla ilişkilendirebilir.
.PK_SELECT_ID_PATTERN <- "^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$"

#' Metni deterministik biçimde kırp
#'
#' Kırpma karakter tabanlıdır ve kırpıldığı AÇIKÇA işaretlenir; sessiz kayıp
#' yoktur. `substr()` karakter tabanlı çalıştığı için Türkçe çok baytlı
#' karakterler ortasından bölünmez.
.pk_select_clip <- function(text, budget) {
  if (is.null(text) || !length(text)) return("")

  # NA ÖNCE düşürülür: `paste(NA_character_)` düz metin "NA" üretir ve bu
  # değer Geçiş A satırına sorgunun ADI/AÇIKLAMASI gibi girerdi (ölçüldü).
  # Eksik alan İÇERİK değil YOKLUK demektir.
  ham <- as.character(text)
  ham <- ham[!is.na(ham)]
  if (!length(ham)) return("")

  metin <- trimws(paste(ham, collapse = " "))
  metin <- gsub("[[:space:]]+", " ", metin, perl = TRUE)
  if (!nzchar(metin)) return("")

  budget <- suppressWarnings(as.integer(budget)[1])
  if (!length(budget) || is.na(budget) || budget < 1L) return("")
  if (nchar(metin) <= budget) return(metin)

  paste0(substr(metin, 1L, max(budget - 1L, 1L)), "…")
}

#' Satır içi ayraç ve satır sonu temizliği
#'
#' Geçiş A yükü SATIR TABANLIDIR; içeriğe kaçak `|` veya `\n` girmesi satır
#' yapısını bozar ve modelin kimlikleri yanlış eşlemesine yol açar. Geçiş B
#' blokları da satır tabanlıdır; `intents`/`not_for` gibi metadata değerleri de
#' bu yüzden BU yoldan geçmelidir.
.pk_select_inline <- function(text) {
  # `as.character(character(0))[1]` NA verir ve `%||%` bunu YAKALAMAZ (yalnızca
  # NULL denetler); sonuç Geçiş A satırına düz "NA" olarak sızardı (ölçüldü).
  ham <- as.character(text)
  ham <- ham[!is.na(ham)]
  if (!length(ham)) return("")

  metin <- gsub("[\r\n\t]+", " ", ham[1], perl = TRUE)
  metin <- gsub("|", "/", metin, fixed = TRUE)
  gsub("[[:space:]]+", " ", trimws(metin), perl = TRUE)
}

.pk_select_meta_chr <- function(meta, alan) {
  deger <- if (is.list(meta)) meta[[alan]] else NULL
  if (is.null(deger)) return(character(0))
  if (is.list(deger)) deger <- unlist(deger, use.names = FALSE)
  deger <- as.character(deger)
  deger[!is.na(deger) & nzchar(trimws(deger))]
}

#' Bir metadata liste alanını tek satırlık, bütçeli metne çevir
.pk_select_meta_line <- function(meta, alan, budget) {
  degerler <- .pk_select_meta_chr(meta, alan)
  if (!length(degerler)) return("")
  .pk_select_inline(.pk_select_clip(paste(degerler, collapse = ", "), budget))
}

#' Sorgunun KARARLI kimliğini oku (D13)
#'
#' Kimlik yoksa `NA` döner; konum kimliği UYDURULMAZ.
pk_select_query_id <- function(query) {
  if (!is.list(query)) return(NA_character_)
  kimlik <- query$id
  if (is.null(kimlik) || !length(kimlik) || is.na(kimlik[1])) return(NA_character_)
  kimlik <- trimws(as.character(kimlik)[1])
  if (!nzchar(kimlik)) return(NA_character_)
  kimlik
}

#' Kimlik, istem ayraçlarına GÜVENLE gömülebilir mi?
pk_select_query_id_is_safe <- function(id) {
  if (is.null(id) || !length(id) || is.na(id[1])) return(FALSE)
  grepl(.PK_SELECT_ID_PATTERN, as.character(id)[1], perl = TRUE)
}

#' İstem yüküne girebilecek KARARLI ve GÜVENLİ kimlik
pk_select_safe_query_id <- function(query) {
  kimlik <- pk_select_query_id(query)
  if (is.na(kimlik) || !pk_select_query_id_is_safe(kimlik)) return(NA_character_)
  kimlik
}

#' Bir sorgunun BEYAN ETTİĞİ varlık türleri (entity)
#'
#' `meta$entity` ve `column_meta[*]$entity` birleşimi. `requirements$entity`
#' aşağı akışta TAM OLARAK bu değerlere karşı doğrulanır; model bunları
#' göremezse ya `null` yazar (varlık kanıtı atlanır) ya da uydurur (kapı
#' garantili başarısız olur).
pk_select_query_entities <- function(query) {
  if (!is.list(query)) return(character(0))
  meta <- if (is.list(query$meta)) query$meta else list()

  varliklar <- .pk_select_meta_chr(meta, "entity")
  sutunlar <- meta$column_meta
  if (is.list(sutunlar) && length(sutunlar)) {
    varliklar <- c(varliklar, unlist(lapply(sutunlar, function(cm) {
      if (is.list(cm)) .pk_select_meta_chr(cm, "entity") else character(0)
    }), use.names = FALSE))
  }

  unique(trimws(varliklar[!is.na(varliklar) & nzchar(trimws(varliklar))]))
}

#' Aday kümesindeki TÜM varlık türleri (Geçiş B istemi için)
pk_select_entity_kinds <- function(queries) {
  if (!is.list(queries) || !length(queries)) return(character(0))
  sort(unique(unlist(lapply(queries, pk_select_query_entities), use.names = FALSE)))
}

#' Sütun etiketlerini kompakt metne çevir (Geçiş A)
#'
#' Kullanıcı "kalan işçilik" der, sütun adı `KalanIscilik_sa`dır; ETİKET
#' ikisini birbirine bağlayan tek insan-dili metindir. Sözlüksel indeks bu
#' yüzden etiketleri içerir; Geçiş A onları göremezse ETİKETTE ayırt edilen bir
#' sorgu recall aşamasında GERİ ALINAMAZ biçimde elenir.
.pk_select_column_labels <- function(meta, budget) {
  sutunlar <- meta$column_meta
  if (!is.list(sutunlar) || !length(sutunlar) || is.null(names(sutunlar))) return("")

  etiketler <- vapply(names(sutunlar), function(ad) {
    cm <- sutunlar[[ad]]
    if (!is.list(cm)) return(NA_character_)
    etiket <- cm$label
    if (is.null(etiket) || !length(etiket) || is.na(etiket[1])) return(NA_character_)
    trimws(as.character(etiket)[1])
  }, character(1), USE.NAMES = FALSE)

  etiketler <- unique(etiketler[!is.na(etiketler) & nzchar(etiketler)])
  if (!length(etiketler)) return("")

  .pk_select_inline(.pk_select_clip(paste(etiketler, collapse = ", "), budget))
}

#' Geçiş A için tek sorgu satırı (§5.2)
#'
#' Biçim:
#'   `id | name | description | keywords | intents | not_for | entity |
#'    column labels | sample_questions[1:N]`
#'
#' Alanların HİÇBİRİ küresel olarak düşürülmez; her biri DETERMİNİSTİK ve
#' bütçeli biçimde kırpılır. Ad da kırpılır: başlangıç doğrulaması ada uzunluk
#' sınırı koymaz ve tek bir devasa ad diğer bütçeleri anlamsız kılabilirdi.
pk_select_pass_a_line <- function(query, cfg) {
  kimlik <- pk_select_safe_query_id(query)
  if (is.na(kimlik)) return(NA_character_)

  meta <- if (is.list(query$meta)) query$meta else list()

  ad <- .pk_select_inline(.pk_select_clip(query$name %||% "", cfg$name_chars))
  aciklama <- .pk_select_inline(.pk_select_clip(query$description %||% "", cfg$desc_chars))
  anahtar_metin <- .pk_select_meta_line(meta, "keywords", cfg$keyword_chars)
  niyet_metin <- .pk_select_meta_line(meta, "intents", cfg$keyword_chars)
  uygun_degil_metin <- .pk_select_meta_line(meta, "not_for", cfg$keyword_chars)

  varliklar <- pk_select_query_entities(query)
  varlik_metin <- if (length(varliklar)) {
    .pk_select_inline(.pk_select_clip(paste(varliklar, collapse = ", "), cfg$keyword_chars))
  } else {
    ""
  }

  etiket_metin <- .pk_select_column_labels(meta, cfg$keyword_chars)

  ornekler <- .pk_select_meta_chr(meta, "sample_questions")
  if (length(ornekler) > cfg$sample_n) ornekler <- ornekler[seq_len(cfg$sample_n)]
  ornekler <- vapply(
    ornekler,
    function(s) .pk_select_inline(.pk_select_clip(s, cfg$sample_chars)),
    character(1), USE.NAMES = FALSE
  )
  ornek_metin <- paste(ornekler, collapse = " ; ")

  sprintf(
    "%s | %s | %s | %s | %s | %s | %s | %s | %s",
    kimlik, ad, aciklama, anahtar_metin, niyet_metin,
    uygun_degil_metin, varlik_metin, etiket_metin, ornek_metin
  )
}

# Geçiş A satır başlığı; istemde alan sırasını AÇIKÇA belgeler.
PK_SELECT_PASS_A_HEADER <- paste0(
  "id | isim | aciklama | anahtar kelimeler | niyetler | ",
  "bu sorgu sunlar icin DEGILDIR | varlik turleri | sutun etiketleri | ornek sorular"
)

#' Geçiş A kütüphane yükü
#'
#' Satırlar KARARLI KİMLİĞE göre sıralanır. Kütüphane listesinin sırası artık
#' modelin gördüğü metni DEĞİŞTİRMEZ; D13 iddiası ("yeniden sıralamak hiçbir
#' şeyi değiştirmez") böylece istem düzeyinde de doğru olur.
#'
#' Kararlı/güvenli kimliği olmayan sorgular DIŞARIDA bırakılır ve `skipped`
#' alanında AÇIKÇA raporlanır; konum kimliğine düşülmez (D13). Çağıran bu alanı
#' KAPALI BAŞARISIZ biçimde ele almalıdır: eksik bir satır, geri alınamaz bir
#' recall kaybıdır.
pk_select_pass_a_payload <- function(library, cfg) {
  if (!is.list(library) || !length(library)) {
    return(list(text = "", ids = character(0), skipped = character(0)))
  }

  satirlar <- vapply(library, function(q) pk_select_pass_a_line(q, cfg), character(1))
  kimlikler <- vapply(library, pk_select_safe_query_id, character(1))

  gecerli <- !is.na(satirlar) & !is.na(kimlikler)
  atlanan <- vapply(which(!gecerli), function(i) {
    ad <- if (is.list(library[[i]])) as.character(library[[i]]$name %||% "")[1] else ""
    if (is.na(ad) || !nzchar(ad)) sprintf("#%d", i) else ad
  }, character(1))

  satirlar <- satirlar[gecerli]
  kimlikler <- kimlikler[gecerli]
  sira <- order(kimlikler, method = "radix")

  list(
    text = paste(satirlar[sira], collapse = "\n"),
    ids = kimlikler[sira],
    skipped = atlanan
  )
}

#' Sütun metadata'sını Geçiş B için TAM anlamsal biçimde yaz
#'
#' Etiket + yetenek kimliği YETMEZ:
#'   * `role` olmadan model yeteneği doğru `requirements` alanına koyamaz ve
#'     geçerli bir aday `capability_missing` ile reddedilir (kimlik kendi
#'     rolünü metninde taşımak ZORUNDA değildir; operatör tanımlıdır),
#'   * `aggregate`/`additive`/`unit`/`percent_scale` olmadan aynı yeteneği
#'     sunan iki aday toplanabilirlik açısından AYIRT EDİLEMEZ,
#'   * `filterable`/`match` olmadan istenen yüklem uygulanabilir mi bilinmez.
.pk_select_column_line <- function(ad, cm) {
  if (!is.list(cm)) return(NA_character_)

  etiket <- as.character(cm$label %||% ad)[1]
  parcalar <- character(0)

  yetenek <- as.character(cm$capability %||% "")[1]
  if (!is.na(yetenek) && nzchar(yetenek)) parcalar <- c(parcalar, sprintf("yetenek=%s", yetenek))

  rol <- as.character(cm$role %||% "")[1]
  if (!is.na(rol) && nzchar(rol)) parcalar <- c(parcalar, sprintf("rol=%s", rol))

  varlik <- as.character(cm$entity %||% "")[1]
  if (!is.na(varlik) && nzchar(varlik)) parcalar <- c(parcalar, sprintf("varlik=%s", varlik))

  toplama <- as.character(cm$aggregate %||% "")[1]
  if (!is.na(toplama) && nzchar(toplama)) parcalar <- c(parcalar, sprintf("toplama=%s", toplama))

  if (is.logical(cm$additive) && length(cm$additive) == 1L && !is.na(cm$additive)) {
    parcalar <- c(parcalar, sprintf("toplanabilir=%s", if (isTRUE(cm$additive)) "evet" else "hayir"))
  }

  birim <- as.character(cm$unit %||% "")[1]
  if (!is.na(birim) && nzchar(birim)) parcalar <- c(parcalar, sprintf("birim=%s", birim))

  yuzde <- as.character(cm$percent_scale %||% "")[1]
  if (!is.na(yuzde) && nzchar(yuzde)) parcalar <- c(parcalar, sprintf("yuzde_olcegi=%s", yuzde))

  if (is.logical(cm$filterable) && length(cm$filterable) == 1L && !is.na(cm$filterable)) {
    parcalar <- c(parcalar, sprintf("filtrelenebilir=%s", if (isTRUE(cm$filterable)) "evet" else "hayir"))
  }

  eslesme <- as.character(cm$match %||% "")[1]
  if (!is.na(eslesme) && nzchar(eslesme)) parcalar <- c(parcalar, sprintf("eslesme=%s", eslesme))

  if (!length(parcalar)) return(.pk_select_inline(etiket))
  .pk_select_inline(sprintf("%s [%s]", etiket, paste(parcalar, collapse = ", ")))
}

#' Geçiş B için tek aday bloğu (TAM ayrıntı)
#'
#' Blok, Geçiş A satırının anlamsal ÜST KÜMESİDİR: recall'da görünen her alan
#' burada da vardır (özellikle `keywords` — bir sorgu YALNIZCA anahtar
#' kelimesi yüzünden aday olabilir ve precision modeli o kanıtı görmezse
#' rakibini seçebilir).
pk_select_pass_b_block <- function(query, cfg) {
  kimlik <- pk_select_safe_query_id(query)
  if (is.na(kimlik)) return(NA_character_)

  meta <- if (is.list(query$meta)) query$meta else list()

  satirlar <- c(
    sprintf("--- SORGU %s ---", kimlik),
    sprintf("ISIM: %s", .pk_select_inline(query$name %||% "")),
    sprintf("ACIKLAMA: %s", .pk_select_inline(query$description %||% ""))
  )

  ornekler <- .pk_select_meta_chr(meta, "sample_questions")
  if (length(ornekler)) {
    satirlar <- c(satirlar, sprintf(
      "ORNEK SORULAR: %s", .pk_select_inline(paste(ornekler, collapse = " ; "))
    ))
  }

  anahtarlar <- .pk_select_meta_chr(meta, "keywords")
  if (length(anahtarlar)) {
    satirlar <- c(satirlar, sprintf(
      "ANAHTAR KELIMELER: %s", .pk_select_inline(paste(anahtarlar, collapse = ", "))
    ))
  }

  niyetler <- .pk_select_meta_chr(meta, "intents")
  if (length(niyetler)) {
    satirlar <- c(satirlar, sprintf(
      "NIYETLER: %s", .pk_select_inline(paste(niyetler, collapse = ", "))
    ))
  }

  uygun_degil <- .pk_select_meta_chr(meta, "not_for")
  if (length(uygun_degil)) {
    satirlar <- c(satirlar, sprintf(
      "BU SORGU SUNLAR ICIN DEGILDIR: %s",
      .pk_select_inline(paste(uygun_degil, collapse = ", "))
    ))
  }

  varliklar <- pk_select_query_entities(query)
  if (length(varliklar)) {
    satirlar <- c(satirlar, sprintf(
      "VARLIK TURLERI: %s", .pk_select_inline(paste(varliklar, collapse = ", "))
    ))
  }

  satirlar <- c(satirlar, .pk_select_grain_lines(meta))

  # Sorgu isteğe bağlı filtrelemeyi KAPATIYORSA bu, seçimin bilmesi gereken
  # bir çalışma zamanı anlamıdır: aşağı akış `disable_ai_filters = TRUE` iken
  # istenen yüklemi UYGULAMADAN tüm yetkili veri kümesi üzerinde cevap üretir.
  if (isTRUE(query$disable_ai_filters)) {
    satirlar <- c(satirlar, paste0(
      "DIKKAT: Bu sorgu istek bazli filtrelemeyi UYGULAMAZ; proje/tarih/birim ",
      "gibi bir daraltma istendiyse sonuc TUM yetkili veri uzerinden gelir."
    ))
  }

  sutunlar <- meta$column_meta
  if (is.list(sutunlar) && length(sutunlar) && !is.null(names(sutunlar))) {
    tanimlar <- vapply(
      names(sutunlar),
      function(ad) .pk_select_column_line(ad, sutunlar[[ad]]),
      character(1), USE.NAMES = FALSE
    )
    tanimlar <- tanimlar[!is.na(tanimlar)]
    if (length(tanimlar)) {
      satirlar <- c(satirlar, sprintf("SUTUNLAR: %s", paste(tanimlar, collapse = " ; ")))
    }
  }

  paste(satirlar, collapse = "\n")
}

#' Sorgu TANECİKLİĞİ (grain) satırları
#'
#' Aynı varlığı ve aynı yetenekleri sunan iki aday FARKLI satır taneciğinde
#' olabilir (proje düzeyi vs. aktivite-atama düzeyi). Yetenek kapısı ikisini de
#' doğrular; tanecik gönderilmezse model yanlış olanı seçebilir.
.pk_select_grain_lines <- function(meta) {
  satirlar <- character(0)

  tanecik <- .pk_select_meta_chr(meta, "grain")
  if (length(tanecik)) {
    satirlar <- c(satirlar, sprintf("TANECIK: %s", .pk_select_inline(tanecik[1])))
  }

  tanecik_sutun <- .pk_select_meta_chr(meta, "grain_columns")
  if (length(tanecik_sutun)) {
    satirlar <- c(satirlar, sprintf(
      "TANECIK SUTUNLARI: %s", .pk_select_inline(paste(tanecik_sutun, collapse = ", "))
    ))
  }

  satirlar
}

#' Geçiş B aday bloklarını TOPLAM KARAKTER BÜTÇESİYLE kur
#'
#' Aday SAYISI tek başına bağlamı sınırlamaz: tek bir geniş sorgu tüm
#' açıklama/örnek/sütun metadata'sıyla pencereyi taşırabilir ve SONRAKİ
#' adaylar sessizce kırpılır. Bütçe aşıldığında sessiz kırpma YAPILMAZ; durum
#' `truncated` ile AÇIKÇA raporlanır ve çağıran kapalı başarısız olur.
pk_select_pass_b_blocks <- function(candidates, cfg) {
  bloklar <- character(0)
  kimlikler <- character(0)
  toplam <- 0L
  butce <- cfg$pass_b_chars %||% 24000L

  for (aday in candidates) {
    blok <- pk_select_pass_b_block(aday, cfg)
    if (is.na(blok)) next

    toplam <- toplam + nchar(blok) + 2L
    if (toplam > butce) {
      return(list(text = "", ids = character(0), truncated = TRUE))
    }

    bloklar <- c(bloklar, blok)
    kimlikler <- c(kimlikler, pk_select_safe_query_id(aday))
  }

  list(
    text = paste(bloklar, collapse = "\n\n"),
    ids = kimlikler,
    truncated = FALSE
  )
}
