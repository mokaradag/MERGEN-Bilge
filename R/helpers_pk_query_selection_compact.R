# ==============================================================================
# Dosya Yolu: R/helpers_pk_query_selection_compact.R
# Açıklama: Faz 5 (§5.2) — seçim istemlerinin BÜTÇEYE SIĞDIRILMASI.
#
# İLKE: bütçe aşımı bir kütüphane hatası değil, istem şekillendirme durumudur.
# Geri alınamaz olan, bir sorgunun/adayın GÖRÜNMEZ olmasıdır; ayrıntı
# çözünürlüğünün düşmesi değil. Bu yüzden bütçe aşılınca satır/aday DÜŞÜRÜLMEZ,
# ayrıntı deterministik ve tekbiçim seyreltilir. Kapalı başarısızlık yalnızca
# asgari (kimlik + isim + açıklama) şekil bile sığmadığında korunur.
#
# Dosya SAFTIR: Shiny/reactive/DB/LLM/ağ bağımlılığı yoktur, worker güvenlidir.
# ==============================================================================

# Geçiş A seyreltme merdiveni. Basamaklar yalnızca sayısal alan bütçelerini
# düşürür; hiçbiri satır düşürmez, yani her basamakta kütüphanedeki HER sorgu
# görünür kalır. Sıfır bütçe ilgili alanı boşaltır (`.pk_select_clip()`).
PK_SELECT_PASS_A_LADDER <- list(
  list(id = "tam",       overrides = list()),
  list(id = "ornek_1",   overrides = list(sample_n = 1L)),
  list(id = "dar_alan",  overrides = list(sample_n = 1L, sample_chars = 60L,
                                          keyword_chars = 100L, desc_chars = 160L)),
  list(id = "etiketsiz", overrides = list(sample_n = 1L, sample_chars = 60L,
                                          keyword_chars = 90L, desc_chars = 140L,
                                          label_chars = 0L)),
  list(id = "orneksiz",  overrides = list(sample_n = 0L, label_chars = 0L,
                                          keyword_chars = 80L, desc_chars = 120L)),
  list(id = "asgari",    overrides = list(sample_n = 0L, label_chars = 0L,
                                          keyword_chars = 0L, desc_chars = 100L,
                                          name_chars = 80L))
)

#' Merdiven basamağını yapılandırmaya uygula
#'
#' Basamak değerleri iç istem şekillendirmedir, operatör beyanı değildir; bu
#' yüzden `pk_select_normalize_config()` aralık denetiminden geçmez.
pk_select_pass_a_level_cfg <- function(cfg, level) {
  if (!is.list(cfg)) cfg <- list()
  if (!is.list(level) || !length(level$overrides %||% list())) return(cfg)
  # BASAMAK YALNIZCA DARALTIR: sabit değeri körlemesine yazmak, operatörün daha
  # dar bir bütçe verdiği alanı GENİŞLETİR; en dar basamak bir öncekinden büyük
  # olur ve sığabilecek bir yük `truncated` ile reddedilirdi.
  for (alan in names(level$overrides)) {
    yeni <- level$overrides[[alan]]
    mevcut <- suppressWarnings(as.numeric(cfg[[alan]])[1])
    if (is.numeric(yeni) && length(yeni) == 1L &&
        length(mevcut) == 1L && !is.na(mevcut)) {
      yeni <- min(mevcut, yeni)
    }
    cfg[[alan]] <- yeni
  }
  cfg
}

#' Geçiş A seyreltmesinin açıklama metni (karar `disclosures` alanına girer)
pk_select_compaction_disclosure <- function(level_id, chars, budget) {
  if (is.null(level_id) || identical(level_id, "tam")) return(character(0))
  sprintf(
    paste0("Analiz kütüphanesi seçim istemine sığması için ayrıntı düzeyi ",
           "seyreltildi (düzey: %s; %d / %d karakter). Hiçbir sorgu listeden ",
           "düşürülmedi."),
    as.character(level_id)[1], as.integer(chars), as.integer(budget)
  )
}

#' Sütun tanımlarını ENTRY BAZINDA bütçeye sığdır
#'
#' Karakter ortasından kesmek modele yarım metadata gösterir; bu yüzden TAM
#' tanımlar alınır ve kırpma açıkça işaretlenir.
pk_select_fit_column_defs <- function(defs, budget) {
  defs <- as.character(defs)
  defs <- defs[!is.na(defs) & nzchar(defs)]
  if (!length(defs)) return("")

  butce <- suppressWarnings(as.numeric(budget)[1])
  if (length(butce) != 1L || is.na(butce) || butce < 1) return("")
  if (is.infinite(butce)) return(paste(defs, collapse = " ; "))

  ayrac <- 3L  # " ; "
  toplam <- 0L
  alinan <- 0L
  for (i in seq_along(defs)) {
    ek <- nchar(defs[i]) + if (i > 1L) ayrac else 0L
    if (toplam + ek > butce) break
    toplam <- toplam + ek
    alinan <- i
  }

  if (!alinan) return("")
  if (alinan == length(defs)) return(paste(defs, collapse = " ; "))

  # Model kalan sütunların VAR OLDUĞUNU bilmelidir; aksi hâlde eksikliği
  # "sorgu bu alanı sunmuyor" diye yorumlayabilir.
  not <- sprintf(" ; … (%d sütun daha)", length(defs) - alinan)
  while (alinan > 1L && toplam + nchar(not) > butce) {
    toplam <- toplam - (nchar(defs[alinan]) + ayrac)
    alinan <- alinan - 1L
    not <- sprintf(" ; … (%d sütun daha)", length(defs) - alinan)
  }

  # Tek tanım + işaret bile sığmıyorsa geri adım kalmaz; bütçeyi AŞAN metin
  # döndürmek Geçiş B'yi yeniden taşırırdı.
  if (toplam + nchar(not) > butce) return("")

  paste0(paste(defs[seq_len(alinan)], collapse = " ; "), not)
}

#' Geçiş B isteminde İLAN EDİLECEK yetenek kimliklerini adaylara daralt
#'
#' İstem küresel kayıt defterini gösterirken doğrulama SEÇİLEN SORGUNUN
#' beyanına bakıyordu; model küresel olarak geçerli ama o sorguda bulunmayan bir
#' kimlik yazınca doğru seçim reddediliyordu. Daraltma kapıyı GEVŞETMEZ, yalnızca
#' modele gerçekten seçilebilir kimlikleri gösterir.
pk_select_candidate_capability_ids <- function(candidates, capability_ids) {
  izinli <- as.character(capability_ids %||% character(0))
  izinli <- izinli[!is.na(izinli) & nzchar(izinli)]
  if (!length(izinli) || !is.list(candidates) || !length(candidates)) return(izinli)
  # BEYAN KAYNAĞI KAPININ OKUDUĞU KAYNAKTIR: ham `column_meta` taraması, iki
  # sütunun tercihsiz paylaştığı ya da `role` taşımayan bir yeteneği de ilan
  # eder; kapı onu beyan edilmemiş sayar ve DOĞRU seçim reddedilirdi.
  if (!exists(".pk_select_query_capabilities", mode = "function", inherits = TRUE)) {
    return(izinli)
  }

  aday_kimlikleri <- unique(unlist(
    lapply(candidates, .pk_select_query_capabilities), use.names = FALSE
  ))
  # HİÇBİR ADAY BEYAN ETMİYORSA LİSTE BOŞALTILMAZ: boş listede istem modelden
  # ihtiyacı `unsupported` alanına yazmasını ister, o da anlamsal kapıda KAPALI
  # başarısızlıktır. Kısmi küratörlemede bu her isteği reddederdi.
  kesisim <- izinli[izinli %in% aday_kimlikleri]
  if (!length(kesisim)) izinli else kesisim
}

#' Geçiş B aday bloklarına ayrıntı payı dağıt
#'
#' Önce her adayın kimlik gövdesi ayrılır, kalan bütçe adaylara EŞİT bölünür.
#' Eşit pay bilinçlidir: sıraya bağlı paylaşım, aday listesi yeniden
#' sıralandığında aynı soruda farklı istem üretirdi.
pk_select_detail_share <- function(base_chars, budget, n) {
  n <- suppressWarnings(as.integer(n)[1])
  if (length(n) != 1L || is.na(n) || n < 1L) return(list(feasible = FALSE, share = 0))

  butce <- suppressWarnings(as.numeric(budget)[1])
  taban <- suppressWarnings(as.numeric(base_chars)[1])
  if (length(butce) != 1L || is.na(butce) || length(taban) != 1L || is.na(taban)) {
    return(list(feasible = FALSE, share = 0))
  }
  if (taban > butce) return(list(feasible = FALSE, share = 0))

  list(feasible = TRUE, share = floor((butce - taban) / n))
}
