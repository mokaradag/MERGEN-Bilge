# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_input_matching.R
# Açıklama: Bilge Yolaç girdi/doküman seçiminde kullanılan ad eşleştirme
#           katmanı: prompt'ta geçen dosya adlarının çıkarımı, kalıcı depolama
#           adının görünen ada çevrilmesi, ayraç duyarlı anahtar eşleştirmesi
#           ve adı geçen dosyaların doğrudan diskten çözümlenmesi.
#
#           Saf karar katmanıdır: Shiny, reaktif değer, DB veya ağ bağımlılığı
#           yoktur ve arka plan worker'ında çalıştırılabilir.
# ==============================================================================

#' Prompt metninde geçen dosya adlarını çıkar
#'
#' @param prompt Kullanıcı metni
#' @return Orijinal harf büyüklüğü korunmuş aday dosya adları/göreli yollar
cc_extract_prompt_file_mentions <- function(prompt) {
  metin <- enc2utf8(paste(as.character(prompt %||% ""), collapse = " "))
  if (!nzchar(metin)) return(character(0))

  # Tırnak/backtick içindeki dosya adları boşluk içerebilir (ör. "Q1 rapor.csv"
  # veya `reports/Q1 budget.csv`). Boşlukta duran genel regex bunları tek
  # kelimeye kırpar; tırnaklı içerik burada BÜTÜN olarak yakalanır. Her iki
  # regex denemesi TEK bir tryCatch altında toplanır (gereksiz ek anonim
  # fonksiyon/karmaşıklık bütçesi eklememek için).
  sonuc <- tryCatch({
    tirnak_deseni <- "[\"'`]([^\"'`]+\\.[A-Za-z0-9]{1,8})[\"'`]"
    tirnakli <- regmatches(metin, gregexpr(tirnak_deseni, metin, perl = TRUE))[[1]]

    ic_icerik <- character(0)
    if (length(tirnakli)) {
      ic_icerik <- sub("^[\"'`]", "", tirnakli, perl = TRUE)
      ic_icerik <- sub("[\"'`]$", "", ic_icerik, perl = TRUE)
    }

    # Tırnaklı aralıklar genel regex'e TEKRAR girmemeli; aksi halde
    # "reports/Q1 budget.csv" içindeki "budget.csv" ayrıca ve yanlışlıkla
    # bağımsız bir aday olarak da yakalanır (istenmeyen ikinci dosya seçimi).
    metin_tirnaksiz <- if (length(tirnakli)) {
      gsub(tirnak_deseni, " ", metin, perl = TRUE)
    } else {
      metin
    }

    eslesmeler <- regmatches(
      metin_tirnaksiz,
      gregexpr("[^\\s\"'`<>|:*?]+\\.[A-Za-z0-9]{1,8}\\b", metin_tirnaksiz, perl = TRUE)
    )[[1]]

    c(ic_icerik, eslesmeler)
  }, error = function(e) character(0))

  if (!length(sonuc)) return(character(0))

  sonuc <- gsub("[\\\\/]+", "/", sonuc, perl = TRUE)
  sonuc <- sub("[.,;:)\\]]+$", "", sonuc, perl = TRUE)
  sonuc <- sonuc[nzchar(sonuc)]

  # NOT: harf büyüklüğü kasıtlı olarak KORUNUR (case-sensitive dosya
  # sistemlerinde diskten çözümleme için gereklidir). Eşleştirme yapan
  # çağıranlar kendi karşılaştırmasında tolower() uygulamalıdır.
  unique(sonuc)
}

# Kalıcı depolama adını (zaman damgası + hash öneki) kullanıcıya görünen ada
# çevirir. Yükleme klasöründeki dosyalar diskte önekli durur ama kullanıcı
# onları arayüzde gördüğü adla anar; eşleştirme her iki adı da denemelidir.
.cc_prepare_display_names <- function(paths) {
  adlar <- basename(as.character(paths %||% character(0)))
  if (!length(adlar)) return(character(0))

  if (exists("recover_display_name_from_storage_name", mode = "function", inherits = TRUE)) {
    return(vapply(
      adlar,
      function(ad) as.character(recover_display_name_from_storage_name(ad))[1],
      character(1),
      USE.NAMES = FALSE
    ))
  }

  sub("^\\d{15,20}_[0-9A-Fa-f]{4,64}_[0-9A-Fa-f]{4,64}_", "", adlar, perl = TRUE)
}

.cc_prepare_mention_matches <- function(files, relatives, mentions) {
  if (!length(files) || !length(mentions)) return(logical(length(files)))

  # Windows dosya sistemi büyük/küçük harf duyarsızdır; Linux/mac gibi
  # case-sensitive dosya sistemlerinde harfleri küçültmek "Data/Report.CSV"
  # isteğinin aynı dizindeki farklı bir "data/report.csv" dosyasıyla da
  # yanlışlıkla eşleşmesine (ikisinin birden seçilmesine) yol açar.
  duyarsiz <- identical(.Platform$OS.type, "windows")

  anahtar <- function(x) {
    # Kodlama daima UTF-8'e sabitlenir: Türkçe Windows'ta yerel kodlamalı ve
    # UTF-8 işaretli aynı ad farklı katlanır ("İ" -> "ı" / "i").
    x <- enc2utf8(as.character(x))
    if (duyarsiz) tolower(x) else x
  }

  rel_key <- anahtar(relatives)
  base_key <- anahtar(basename(files))
  display_key <- anahtar(.cc_prepare_display_names(files))
  mention_keys <- anahtar(mentions)

  vapply(seq_along(files), function(i) {
    any(vapply(mention_keys, function(m) {
      .cc_prepare_key_matches(c(base_key[i], display_key[i], rel_key[i]), m)
    }, logical(1)))
  }, logical(1))
}

# Anma, adın tamamı olabileceği gibi ayraçtan sonraki son parçası da olabilir.
# İki gerçek durum bunu zorunlu kılar: yükleme klasöründeki depolama öneki
# (`<zaman>_<hash>_<ad>`) ve prompt'ta boşluklu bir adın yalnızca son
# sözcüğünün yakalanması ("EK-U Süreç.pdf" -> "Süreç.pdf").
.cc_prepare_key_matches <- function(keys, mention) {
  keys <- as.character(keys %||% character(0))
  mention <- as.character(mention %||% "")[1]
  if (!length(keys) || !nzchar(mention)) return(FALSE)

  for (anahtar in keys) {
    if (!nzchar(anahtar)) next
    if (identical(anahtar, mention)) return(TRUE)
    if (!endsWith(anahtar, mention)) next

    onek <- substr(anahtar, 1L, nchar(anahtar) - nchar(mention))
    if (nzchar(onek) && grepl("[/_ -]$", onek)) return(TRUE)
  }

  FALSE
}

#' Adı geçen dosyaları doğrudan diskte çöz (kesilmiş tarama yedeği)
#'
#' Sınırlı tarama, adı geçen dosya numaralandırılmadan önce kesilebilir. Bu
#' durumda otomatik alt kümeye düşmek yerine, güvenli göreli yol adaylarını
#' kökün altında doğrudan doğrularız. Mutlak yol, sürücü harfi ve `..`
#' geçişleri asla kabul edilmez; sonuç her zaman kökün içinde kalır.
#'
#' @param mentions Küçük harfli aday dosya adları/göreli yollar
#' @param root Kaynak kök dizin
#' @param max_files Doğrulanacak maksimum dosya sayısı
#' @return Kök altında var olan mutlak dosya yolları
cc_resolve_mentioned_files_on_disk <- function(mentions,
                                               root,
                                               max_files = 40L) {
  mentions <- unique(as.character(mentions %||% character(0)))
  mentions <- mentions[nzchar(mentions)]

  kok <- .cc_scan_norm(as.character(root %||% "")[1])
  if (!length(mentions) || !nzchar(kok) ||
      !isTRUE(tryCatch(dir.exists(kok), error = function(e) FALSE))) {
    return(character(0))
  }

  kok_key <- .cc_scan_key(kok)
  max_files <- max(0L, suppressWarnings(as.integer(max_files)))
  if (!is.finite(max_files) || max_files == 0L) return(character(0))

  bulunanlar <- character(0)

  for (aday in mentions) {
    if (length(bulunanlar) >= max_files) break

    rel <- gsub("\\", "/", aday, fixed = TRUE)
    rel <- sub("^\\./+", "", rel, perl = TRUE)

    # Mutlak yol / sürücü harfi / UNC / üst dizin geçişi kabul edilmez.
    if (grepl("^(?:[A-Za-z]:|/|//)", rel, perl = TRUE)) next
    if (grepl("(^|/)\\.\\.(/|$)", rel, perl = TRUE)) next
    if (!nzchar(rel)) next

    hedef <- .cc_scan_norm(file.path(kok, rel))
    hedef_key <- .cc_scan_key(hedef)

    if (!startsWith(hedef_key, paste0(kok_key, "/"))) next
    if (!isTRUE(file.exists(hedef)) || isTRUE(dir.exists(hedef))) next

    bulunanlar <- c(bulunanlar, hedef)
  }

  unique(bulunanlar)
}
