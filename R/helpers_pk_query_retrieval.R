# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_retrieval.R
# Açıklama: Faz 5 (§5.2) — sözlüksel (lexical) sorgu getirimi: karakter 3-gram
#           kosinüs benzerliği + IDF ağırlıklandırma.
#
# ROL SINIRI — BU KATMAN ASLA SEÇİM KARARI VERMEZ (D10).
#   Master plan §5.2 açıktır: "The lexical scorer must never make a selection
#   decision — a shortlist that drops the correct query is an unrecoverable
#   silent failure". Bu dosyanın YALNIZCA üç meşru rolü vardır:
#
#     1. BOZULMA KİPİ (degraded mode): LLM erişilemezse ilk 3 aday KULLANICIYA
#        seçenek olarak gösterilir; hiçbir zaman otomatik çalıştırılmaz.
#     2. UYUŞMAZLIK SİNYALİ: LLM'in seçtiği sorgu sözlüksel sıralamada çok
#        gerideyse güven DÜŞÜRÜLÜR (karar değiştirilmez, yalnızca zayıflatılır).
#     3. Altın küme (golden set) tanılaması: recall@N ölçümü.
#
#   Bu dosya `pk_select_*` karar fonksiyonlarını ÇAĞIRMAZ ve hiçbir yerde
#   "bu sorguyu çalıştır" anlamına gelen bir değer döndürmez.
#
# v1 HEURISTIC'İNDEN NEYİ DEVRALMAZ (D10 — bilinçli):
#   * 7 adet sabit kodlanmış `grepl` alan bonusu (bütçe/zaman/kaynak/aktivite/
#     proje/wbs/rol) YOKTUR. Alan bilgisi, sorgunun KENDİ metadata'sındaki
#     `keywords` / `sample_questions` alanlarından gelir; kodda gömülü bir
#     Türkçe eşanlamlı listesi tutulmaz.
#   * max'a göre %100 NORMALİZASYON YOKTUR. Kosinüs zaten [0, 1] aralığında
#     MUTLAK bir ölçüdür; en iyi adayın her zaman %100 görünmesi (ve dolayısıyla
#     eşiği her zaman geçmesi) yapısal olarak imkânsızdır.
#   * Sabit eşik YOKTUR. Bu katman eşik uygulamaz; karar `helpers_pk_query_
#     selection_ai.R` içindedir.
#
# NEDEN 3-GRAM: Türkçe sondan eklemeli bir dildir. `projelerin` / `projeye` /
#   `projedeki` ortak `pro`, `roj`, `oje` üçlülerini paylaşır; bu yüzden ne
#   gövdeleyiciye (stemmer) ne de eşanlamlı listesine ihtiyaç duyulur.
# NEDEN IDF: `proje` gibi kütüphanenin neredeyse tamamında geçen kelimeler
#   aksi hâlde skoru domine eder ve ayırt ediciliği yok eder.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ/dosya G-Ç bağımlılığı yoktur ve
# worker güvenlidir. Türkçe katlama TEK kaynaktan (`pk_tr_fold()`) alınır;
# KOPYALANMAZ.
# ==============================================================================

# Belge metnine giren metadata alanları. Sıra bilinçlidir ancak skor sıraya
# duyarlı DEĞİLDİR (çanta/bag-of-trigrams modeli).
.PK_RETRIEVAL_META_TEXT_FIELDS <- c("keywords", "sample_questions", "intents")

#' Katlanmış metni belirteçlere (token) ayır
#'
#' ÖLÇÜLMÜŞ UYARI — burada `strsplit(..., "[^[:alnum:]]+", perl = TRUE)`
#' KULLANILMAZ. PCRE'nin POSIX sınıfları varsayılan olarak ASCII'dir: bu
#' konteynerde ölçüldüğünde `işçilik` -> `i` + `ilik` şeklinde PARÇALANIYOR,
#' yani her Türkçe kelime ayırt ediciliğini kaybediyordu. `perl = FALSE` (TRE)
#' doğru sonucu verir ama davranışı YERELE bağlıdır; Türkçe Windows VM'de aynı
#' garanti yoktur. `pk_tr_fold()` ile aynı gerekçeyle tek doğrulanmış yol ICU'
#' dur: `\p{L}` (harf) ve `\p{N}` (sayı) Unicode özellik sınıfları yerelden
#' BAĞIMSIZ çalışır.
.pk_retrieval_tokens <- function(text) {
  if (is.null(text) || !length(text)) return(character(0))

  # NA ÖNCE düşürülür. `paste(NA_character_)` düz metin "NA" üretir; bu da
  # katlanıp `na` belirtecine dönüşerek boş bir alanı sahte 3-gram'larla
  # doldururdu (ölçüldü). Eksik alan, İÇERİK değil YOKLUK demektir.
  ham <- as.character(text)
  ham <- ham[!is.na(ham)]
  if (!length(ham)) return(character(0))

  katlanmis <- pk_tr_fold(paste(ham, collapse = " "))
  if (!length(katlanmis) || is.na(katlanmis) || !nzchar(katlanmis)) return(character(0))

  parcalar <- unlist(
    stringi::stri_split_regex(katlanmis, "[^\\p{L}\\p{N}]+"),
    use.names = FALSE
  )
  parcalar <- parcalar[!is.na(parcalar) & nzchar(parcalar)]
  parcalar
}

#' Metinden karakter 3-gramları üret
#'
#' Her belirteç TEK boşlukla iki yandan doldurulur (` proje ` -> ` pr`, `pro`,
#' ...). Dolgu bilinçlidir: kelime başı/sonu bilgisini korur, böylece `proje`
#' ile `iproje` aynı görünmez. İki karakterden kısa belirteçler de (`iş`) bu
#' sayede en az bir 3-gram üretir.
#'
#' @return Karakter vektörü; TEKRARLAR KORUNUR (terim frekansı için gerekir).
pk_retrieval_trigrams <- function(text) {
  belirtecler <- .pk_retrieval_tokens(text)
  if (!length(belirtecler)) return(character(0))

  dolgulu <- paste0(" ", belirtecler, " ")
  n <- nchar(dolgulu)

  parcalar <- lapply(seq_along(dolgulu), function(i) {
    if (n[i] < 3L) return(character(0))
    baslangic <- seq_len(n[i] - 2L)
    substring(dolgulu[i], baslangic, baslangic + 2L)
  })

  unlist(parcalar, use.names = FALSE)
}

#' Bir metadata alanını düz metne çevir
.pk_retrieval_field_text <- function(deger) {
  if (is.null(deger)) return(character(0))
  if (is.list(deger)) deger <- unlist(deger, use.names = FALSE)
  deger <- as.character(deger)
  deger <- deger[!is.na(deger) & nzchar(trimws(deger))]
  deger
}

#' Sorgunun sözlüksel belge metnini kur (§5.2)
#'
#' `name + description + keywords + sample_questions + column labels`. Sütun
#' ETİKETLERİ (label) bilinçli olarak dâhildir: kullanıcı "kalan işçilik" der,
#' sütun adı `KalanIscilik_sa`dır; etiket ikisini birbirine bağlayan tek metin
#' alanıdır. Sütun ADLARI dâhil EDİLMEZ — teknik tanımlayıcılardır ve
#' `KalanIscilik_sa` gibi birleşik biçimleri yanlış 3-gram gürültüsü üretir.
#'
#' `intents` de dâhildir: sorgunun ne için OLDUĞUNU anlatan kısa etiketlerdir.
#' `not_for` bilinçli olarak DIŞARIDA bırakılır — "bütçe için DEĞİL" diyen bir
#' alan, çanta modelinde tam tersi etkiyi yapar ve sorguyu bütçe sorularına
#' çeker.
pk_retrieval_document_text <- function(query) {
  if (!is.list(query)) return("")

  meta <- query$meta
  if (!is.list(meta)) meta <- list()

  parcalar <- c(
    .pk_retrieval_field_text(query$name),
    .pk_retrieval_field_text(query$description)
  )

  for (alan in .PK_RETRIEVAL_META_TEXT_FIELDS) {
    parcalar <- c(parcalar, .pk_retrieval_field_text(meta[[alan]]))
  }

  sutunlar <- meta$column_meta
  if (is.list(sutunlar) && length(sutunlar)) {
    etiketler <- unlist(lapply(sutunlar, function(cm) {
      if (is.list(cm)) .pk_retrieval_field_text(cm$label) else character(0)
    }), use.names = FALSE)
    parcalar <- c(parcalar, etiketler)
  }

  if (!length(parcalar)) return("")
  paste(parcalar, collapse = " ")
}

#' Terim frekansı tablosu (3-gram -> sayı)
.pk_retrieval_tf <- function(trigramlar) {
  if (!length(trigramlar)) return(integer(0))
  tablo <- table(trigramlar)
  sayilar <- as.integer(tablo)
  names(sayilar) <- names(tablo)
  sayilar
}

#' Sözlüksel getirim indeksini kur
#'
#' IDF, `log(1 + N / df)` ile YUMUŞATILIR: her belgede geçen bir 3-gram için
#' `log(2) > 0` verir, yani ağırlık asla tam sıfıra düşmez ve tek belgelik bir
#' kütüphanede indeks çökmez.
#'
#' @param library Sorgu kütüphanesi (her öğe en azından `id` taşımalıdır).
#' @return `pk_retrieval_index` sınıflı liste: `ids`, `tf` (belge başına adlı
#'   tam sayı vektörü), `idf`, `norm` (belge vektör normu), `n`.
pk_retrieval_build_index <- function(library) {
  if (!is.list(library) || !length(library)) {
    return(structure(
      list(ids = character(0), tf = list(), idf = numeric(0), norm = numeric(0), n = 0L),
      class = "pk_retrieval_index"
    ))
  }

  kimlikler <- vapply(seq_along(library), function(i) {
    kayit <- library[[i]]
    kimlik <- if (is.list(kayit)) kayit$id else NULL
    if (is.null(kimlik) || !length(kimlik) || is.na(kimlik[1]) || !nzchar(trimws(as.character(kimlik)[1]))) {
      # KARARLI KİMLİK YOKSA konum kimliği ÜRETİLMEZ (D13). Boş bırakılır ve
      # aşağıda indeksten düşürülür; yanlış bir "q3" uydurmak, kütüphane
      # sırası değiştiğinde sessizce başka sorguyu işaret ederdi.
      return(NA_character_)
    }
    trimws(as.character(kimlik)[1])
  }, character(1))

  gecerli <- which(!is.na(kimlikler))
  kimlikler <- kimlikler[gecerli]

  tf_listesi <- lapply(gecerli, function(i) {
    .pk_retrieval_tf(pk_retrieval_trigrams(pk_retrieval_document_text(library[[i]])))
  })

  n <- length(kimlikler)
  if (!n) {
    return(structure(
      list(ids = character(0), tf = list(), idf = numeric(0), norm = numeric(0), n = 0L),
      class = "pk_retrieval_index"
    ))
  }

  df_sayaci <- table(unlist(lapply(tf_listesi, names), use.names = FALSE))
  idf <- log(1 + n / as.numeric(df_sayaci))
  names(idf) <- names(df_sayaci)

  norm <- vapply(tf_listesi, function(tf) {
    if (!length(tf)) return(0)
    agirlik <- as.numeric(tf) * idf[names(tf)]
    sqrt(sum(agirlik * agirlik))
  }, numeric(1))

  structure(
    list(ids = kimlikler, tf = tf_listesi, idf = idf, norm = norm, n = n),
    class = "pk_retrieval_index"
  )
}

#' Prompt'a göre TÜM kütüphaneyi sözlüksel olarak puanla
#'
#' Skor MUTLAK kosinüs benzerliğidir ([0, 1]); max'a göre normalize EDİLMEZ.
#' Sıralama azalan skor, eşitlikte kararlı kimliğin C-yerel (radix) sırasıdır —
#' böylece Türkçe Windows VM ile POSIX konteyner aynı sırayı üretir.
#'
#' @return `query_id` ve `score` sütunlu data.frame (azalan skor).
pk_retrieval_score <- function(index, prompt) {
  bos <- data.frame(query_id = character(0), score = numeric(0), stringsAsFactors = FALSE)
  if (!is.list(index) || !length(index$ids %||% character(0))) return(bos)

  sorgu_tf <- .pk_retrieval_tf(pk_retrieval_trigrams(prompt))
  if (!length(sorgu_tf)) {
    return(data.frame(
      query_id = index$ids,
      score = rep(0, length(index$ids)),
      stringsAsFactors = FALSE
    )[order(index$ids, method = "radix"), , drop = FALSE])
  }

  # Kütüphanede hiç görülmemiş 3-gramlar hiçbir belgeyle kesişmez; IDF'leri
  # tanımsızdır. Kesişim zaten sıfır katkı verdiği için düşürülürler.
  bilinen <- intersect(names(sorgu_tf), names(index$idf))
  if (!length(bilinen)) {
    return(data.frame(
      query_id = index$ids,
      score = rep(0, length(index$ids)),
      stringsAsFactors = FALSE
    )[order(index$ids, method = "radix"), , drop = FALSE])
  }

  sorgu_agirlik <- as.numeric(sorgu_tf[bilinen]) * index$idf[bilinen]
  names(sorgu_agirlik) <- bilinen
  sorgu_norm <- sqrt(sum(sorgu_agirlik * sorgu_agirlik))
  if (!is.finite(sorgu_norm) || sorgu_norm <= 0) return(bos)

  skorlar <- vapply(seq_along(index$ids), function(i) {
    tf <- index$tf[[i]]
    if (!length(tf) || !is.finite(index$norm[i]) || index$norm[i] <= 0) return(0)

    ortak <- intersect(names(tf), bilinen)
    if (!length(ortak)) return(0)

    belge_agirlik <- as.numeric(tf[ortak]) * index$idf[ortak]
    nokta <- sum(belge_agirlik * as.numeric(sorgu_agirlik[ortak]))
    deger <- nokta / (index$norm[i] * sorgu_norm)
    if (!is.finite(deger)) return(0)

    # Kayan nokta gürültüsü sıralamayı platformlar arasında değiştirmesin.
    round(min(max(deger, 0), 1), 6L)
  }, numeric(1))

  out <- data.frame(query_id = index$ids, score = skorlar, stringsAsFactors = FALSE)
  out[order(-out$score, out$query_id, method = "radix"), , drop = FALSE]
}

#' İlk N sözlüksel aday (yalnızca bozulma kipi ve tanılama için)
#'
#' `n` doğrudan tüketilir; bu dosya yapılandırma OKUMAZ. Çağıran, çözümlenmiş
#' `MERGEN_PK_SELECT_RECALL_N` değerini geçirir.
pk_retrieval_top <- function(index, prompt, n) {
  n <- suppressWarnings(as.integer(n)[1])
  if (!length(n) || is.na(n) || n < 1L) return(pk_retrieval_score(index, prompt)[0, , drop = FALSE])

  siralama <- pk_retrieval_score(index, prompt)
  if (!nrow(siralama)) return(siralama)

  utils::head(siralama, n)
}

#' Sözlüksel UYUŞMAZLIK sinyali (§5.2 — karar değil, yalnızca zayıflatma)
#'
#' LLM'in seçtiği kimlik sözlüksel sıralamada nerede? Çok geride ise bu bir
#' "yanlış olabilir" sinyalidir. Fonksiyon KARAR VERMEZ: yalnızca sıra, skor ve
#' bir `disagrees` bayrağı döndürür; güveni ne kadar düşüreceğine karar
#' politikası karar verir.
#'
#' @param top_n Sözlüksel ilk-N penceresi. Seçim bu pencerenin DIŞINDA kaldıysa
#'   uyuşmazlık raporlanır.
pk_retrieval_agreement <- function(index, prompt, selected_id, top_n) {
  top_n <- suppressWarnings(as.integer(top_n)[1])
  if (!length(top_n) || is.na(top_n) || top_n < 1L) top_n <- 1L

  bos <- list(available = FALSE, rank = NA_integer_, score = NA_real_, disagrees = FALSE)
  if (!is.list(index) || !length(index$ids %||% character(0))) return(bos)
  if (is.null(selected_id) || !length(selected_id) || is.na(selected_id[1])) return(bos)

  siralama <- pk_retrieval_score(index, prompt)
  if (!nrow(siralama)) return(bos)

  # Sözlüksel sinyal tamamen boşsa (tüm skorlar 0) uyuşmazlık İDDİA EDİLMEZ.
  # Aksi hâlde metadata'sı olmayan bir kütüphanede her seçim "şüpheli" olurdu.
  if (all(siralama$score <= 0)) return(bos)

  kimlik <- trimws(as.character(selected_id)[1])
  sira <- match(kimlik, siralama$query_id)
  if (is.na(sira)) return(bos)

  list(
    available = TRUE,
    rank = as.integer(sira),
    score = as.numeric(siralama$score[sira]),
    disagrees = isTRUE(sira > top_n)
  )
}
