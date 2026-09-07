# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_file_stability.R
# Açıklama: Bilge Yolaç tarafından yeni üretilen dosyaların kısa süreli
#           kararlı hale gelmesini SINIRLI bir bütçeyle bekler.
#
#           KRİTİK: Bu bekleme yalnızca arka plan worker'ında çağrılmalıdır.
#           Ana Shiny sürecinde çağrılırsa tüm oturumlar bloke olur.
# ==============================================================================

#' Yeni/değişen dosyaların kısa süreli kararlı hale gelmesini bekle
#'
#' Claude Code CLI döndükten hemen sonra Windows üzerinde dosya mtime/size
#' bilgileri kısa süre oynayabilir veya child process dosyayı yeni kapatmış
#' olabilir. Bu yardımcı, staging/encoding normalizasyonu başlamadan önce
#' dosya imzasını kısa aralıklarla kontrol eder. Maksimum denemeden sonra
#' dosyaları düşürmez; son görülen mevcut dosya listesini döndürerek önceki
#' davranışı korur.
#'
#' NOT: Bu bekleme yalnızca arka plan hazırlık/çıktı worker'ında çağrılmalıdır.
#' Ana Shiny sürecinde çağrılırsa tüm oturumlar bloke olur. Toplam bekleme
#' süresi `max_total_ms` ile sınırlıdır.
#'
#' @param file_paths Dosya yolları
#' @param settle_ms Denemeler arasındaki bekleme süresi (ms)
#' @param max_attempts Maksimum kontrol sayısı
#' @param max_total_ms Toplam bekleme bütçesi (ms)
#' @return Kanonik, mevcut ve dosya olan yollar
wait_for_stable_claude_code_file_paths <- function(file_paths,
                                                    settle_ms = 75L,
                                                    max_attempts = 4L,
                                                    max_total_ms = NULL) {
  file_paths <- deduplicate_claude_code_file_paths(file_paths)
  if (!length(file_paths)) return(character(0))

  settle_ms <- suppressWarnings(as.integer(settle_ms[1] %||% 75L))
  if (is.na(settle_ms) || settle_ms < 0L) {
    settle_ms <- 75L
  }

  max_attempts <- suppressWarnings(as.integer(max_attempts[1] %||% 4L))
  if (is.na(max_attempts) || max_attempts < 1L) {
    max_attempts <- 1L
  }

  max_total_ms <- suppressWarnings(as.numeric(max_total_ms)[1])
  if (length(max_total_ms) != 1L || !is.finite(max_total_ms)) {
    max_total_ms <- suppressWarnings(as.numeric(
      tryCatch(cc_runtime_limit("file_settle_total_ms", 1200), error = function(e) 1200)
    )[1])
  }
  if (length(max_total_ms) != 1L || !is.finite(max_total_ms) || max_total_ms < 0) {
    max_total_ms <- 1200
  }

  bekleme_baslangic <- Sys.time()

  file_signature <- function(paths) {
    mevcut <- paths[file.exists(paths) & !dir.exists(paths)]
    mevcut <- deduplicate_claude_code_file_paths(mevcut)

    if (!length(mevcut)) {
      return(data.frame(
        path = character(0),
        size = numeric(0),
        mtime = numeric(0),
        stringsAsFactors = FALSE
      ))
    }

    bilgi <- tryCatch(file.info(mevcut), error = function(e) NULL)
    if (is.null(bilgi) || nrow(bilgi) == 0L) {
      return(data.frame(
        path = character(0),
        size = numeric(0),
        mtime = numeric(0),
        stringsAsFactors = FALSE
      ))
    }

    sonuc <- data.frame(
      path = mevcut,
      size = suppressWarnings(as.numeric(bilgi$size)),
      mtime = suppressWarnings(as.numeric(bilgi$mtime)),
      stringsAsFactors = FALSE
    )

    sonuc <- sonuc[order(tolower(sonuc$path)), , drop = FALSE]
    rownames(sonuc) <- NULL
    sonuc
  }

  same_signature <- function(a, b) {
    if (!is.data.frame(a) || !is.data.frame(b)) return(FALSE)
    if (!identical(nrow(a), nrow(b))) return(FALSE)
    if (!identical(a$path, b$path)) return(FALSE)

    same_size <- isTRUE(all.equal(a$size, b$size, check.attributes = FALSE))
    same_mtime <- isTRUE(all.equal(a$mtime, b$mtime, check.attributes = FALSE))

    isTRUE(same_size) && isTRUE(same_mtime)
  }

  # İLK imza BOŞ olduğunda erken dönülmez: UNC/antivirüs görünürlük gecikmesi
  # ilk yoklamada dosyaları gizleyebiliyor ve aşağıdaki yeniden deneme bütçesi
  # hiç çalışmadan üretilen dosyalar düşüyordu. Döngü boş imzayla da sürer;
  # `same_signature()` satır sayısı farkında FALSE döndüğü için ilk görünen
  # imza referans alınır ve bütçe bittiğinde varlık denetimi yine uygulanır.
  previous <- file_signature(file_paths)

  latest <- previous

  for (attempt in seq_len(max_attempts)) {
    gecen_ms <- as.numeric(difftime(Sys.time(), bekleme_baslangic, units = "secs")) * 1000
    if (gecen_ms >= max_total_ms) break

    if (settle_ms > 0L) {
      Sys.sleep(min(settle_ms, max(0, max_total_ms - gecen_ms)) / 1000)
    }

    current <- file_signature(file_paths)
    if (nrow(current) == 0L) {
      # UNC/ağ paylaşımında dosyalar anlık olarak görünmez olabilir; tüm listeyi
      # hemen düşürmek üretilen dosyaları kaybettiriyordu. Tur atlanır ve son
      # bilinen geçerli imza korunur.
      next
    }

    latest <- current

    if (isTRUE(same_signature(previous, current))) {
      return(deduplicate_claude_code_file_paths(current$path))
    }

    previous <- current
  }

  # Deneme/süre bütçesi tükendi. Geçici UNC görünmezliği toleransı korunur,
  # ancak saklanan imza YENİDEN DOĞRULANIR: dosya gerçekten silinmiş/yeniden
  # adlandırılmışsa çağıran var olmayan bir yol alıp bayat indirme/çıktı
  # metaverisi üretiyordu.
  son_yollar <- deduplicate_claude_code_file_paths(latest$path)
  if (!length(son_yollar)) return(son_yollar)
  var_olan <- vapply(
    son_yollar,
    # `file.exists()` DİZİN için de TRUE döner: çıktı dosyası silinip aynı yolda
    # bir dizin oluşursa bu fonksiyon o dizini "kararlı dosya" olarak döndürüyordu.
    function(p) isTRUE(tryCatch(
      file.exists(p) && !dir.exists(p),
      error = function(e) FALSE
    )),
    logical(1)
  )
  son_yollar[var_olan]
}
