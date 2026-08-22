# ==============================================================================
# Dosya Yolu: R/helpers_pk_filter_policy.R
# Açıklama: Proje ve Kaynak Analizi v2 filtre politikası (D4 / D9 / D12).
#
#             D4  — Hiçbir satırla eşleşmeyen bir filtre, v1'de yine de
#                   uygulanıyor ve kullanıcıya yalnızca "Filtreleme sonrası
#                   veri bulunamadı" deniyordu. Kullanıcı "bu veri yok" ile
#                   "model veritabanında olmayan bir proje adı uydurdu"
#                   arasını ayıramıyordu.
#             D9  — Filtre LLM'i zaman aşımına uğradığında v1, filtresiz
#                   biçimde TÜM projeleri analiz ediyordu; kullanıcı bunu
#                   asla öğrenmiyordu.
#             D12 — Ölü "genel soru" muhafızı: koşul zaten `length(filters)==0`
#                   gerektiriyor, gövdesi ise `filters <- list()` atıyordu;
#                   yani hiçbir zaman etkisi olmadı. v2 yolunda YOKTUR.
#
#           Karar §5.4 kural 6/7'ye dayanır: BİRİNCİL varlık çözülemediyse
#           analiz YAPILMAZ (tüm projeler üzerinden istatistik, sorulandan
#           BAŞKA bir soruyu yanıtlar); İKİNCİL bir daraltma çözülemediyse
#           belirgin ifşa ile düşürülür ve analiz sürer.
#
#           NOT: "En yakın aday" önerileri bilerek KAPSAM DIŞIDIR; aday
#           sıralaması Faz 4 çözümleyicisine aittir. Faz 1 "bulunamadı" der.
#
#           Dosya bilerek SAFTIR: Shiny/reactive/DB/ağ/LLM bağımlılığı yoktur.
# ==============================================================================

#' Bozulmuş filtre durumunda sessiz tam-küme devamını engelle (D9)
#'
#' Faz 0'ın tipli durumları tüketilir; yeni bir durum sözlüğü icat edilmez.
#'
#' @return list(refuse, message)
pk_filter_degraded_gate <- function(status) {
  bozuk <- exists("pk_filter_status_is_degraded", mode = "function", inherits = TRUE) &&
    isTRUE(pk_filter_status_is_degraded(status))

  if (!bozuk) return(list(refuse = FALSE, message = NULL))

  aciklama <- NULL
  if (exists("pk_degradations_from_filter_status", mode = "function", inherits = TRUE)) {
    bozulmalar <- tryCatch(pk_degradations_from_filter_status(status), error = function(e) list())
    if (length(bozulmalar) > 0) aciklama <- bozulmalar[[1]]$message
  }

  list(
    refuse = TRUE,
    message = paste0(
      "\U000026A0\U0000FE0F **Filtre Belirlenemedi:** Sorunuzdaki filtre ",
      "kriterleri güvenli biçimde çözümlenemedi.",
      if (is.null(aciklama)) "" else paste0(" ", aciklama),
      "\n\nBu durumda tüm kayıtlar üzerinden analiz YAPILMADI; çünkü tüm ",
      "veri üzerinden üretilen istatistikler sorduğunuz sorudan başka bir ",
      "soruyu yanıtlar. Lütfen sorunuzu tekrar gönderin veya filtre ",
      "kriterlerini daha açık yazın."
    )
  )
}

#' Birincil filtre sütununu belirle
#'
#' Sorgu metadatası `primary_entity` taşıyorsa o kullanılır. Metadata yoksa
#' (üretimdeki tüm sorgular şu an Tier-0'dır) BELGELİ geri düşüş uygulanır:
#' tek filtre yaprağı varsa o birincildir.
pk_filter_primary_column <- function(query, filter_columns) {
  filter_columns <- unique(as.character(filter_columns %||% character(0)))
  filter_columns <- filter_columns[!is.na(filter_columns) & nzchar(filter_columns)]

  if (exists("pk_meta_primary_entity", mode = "function", inherits = TRUE)) {
    birincil <- tryCatch(
      pk_meta_primary_entity(query, filter_columns),
      error = function(e) NULL
    )
    if (!is.null(birincil) && nzchar(as.character(birincil)[1])) {
      return(as.character(birincil)[1])
    }
  }

  if (length(filter_columns) == 1L) return(filter_columns)
  NULL
}

.pk_policy_zero_match_message <- function(column, values) {
  degerler <- unique(as.character(values %||% character(0)))
  degerler <- degerler[nzchar(degerler)]
  gosterim <- if (length(degerler)) {
    paste0("`", paste(utils::head(degerler, 5L), collapse = "`, `"), "`")
  } else {
    "belirtilen değer"
  }

  paste0(
    "\U0001F50D **Çözümlenemedi:** Sorunuzun ana konusu olan ", gosterim,
    " değeri, `", column, "` alanında bulunamadı.\n\n",
    "Bu nedenle analiz YAPILMADI. Tüm kayıtlar üzerinden istatistik üretmek ",
    "sorduğunuz sorudan başka bir soruyu yanıtlardı. Lütfen değeri kontrol ",
    "edip tekrar deneyin."
  )
}

#' Uygulanamayan (düşürülen) filtreler için kullanıcıya dönecek red mesajı.
.pk_policy_dropped_message <- function(dropped) {
  dropped <- dropped %||% list()

  satirlar <- vapply(utils::head(dropped, 5L), function(d) {
    sutun <- as.character(d$leaf$column %||% "?")[1]
    degerler <- unique(as.character(d$leaf$values %||% d$leaf$value %||% character(0)))
    degerler <- degerler[nzchar(degerler)]
    gosterim <- if (length(degerler)) {
      paste0(" (`", paste(utils::head(degerler, 3L), collapse = "`, `"), "`)")
    } else {
      ""
    }
    sprintf("`%s`%s -> %s", sutun, gosterim, d$reason %||% "bilinmeyen sebep")
  }, character(1))

  paste0(
    "\U000026A0\U0000FE0F **Filtre uygulanamadı:** Sorunuzda belirttiğiniz daraltma ",
    "kriterleri işlenemedi:\n- ", paste(satirlar, collapse = "\n- "), "\n\n",
    "Bu nedenle analiz YAPILMADI. Kriterleri yok sayıp tüm kayıtlar üzerinden ",
    "istatistik üretmek, sorduğunuz sorudan başka bir soruyu yanıtlardı. ",
    "Lütfen kriteri sadeleştirip tekrar deneyin."
  )
}

#' Sıfır eşleşme politikasını uygula (D4)
#'
#' @param compiled `pk_filter_compile()` çıktısı.
#' @param query Seçilen sorgu (metadata için).
#' @return list(action, mask, primary_column, refusal_message, disclosures, dropped_columns)
#'   action: "proceed" | "refuse" | "dropped_secondary"
pk_filter_zero_match_policy <- function(data, filters, compiled, query = NULL) {
  sonuc <- list(
    action = "proceed",
    mask = compiled$mask,
    primary_column = NULL,
    refusal_message = NULL,
    disclosures = character(0),
    dropped_columns = character(0)
  )

  # --- DÜŞÜRÜLEN YAPRAK KAPISI (kapalı başarısız) ---------------------------
  #
  # Sıfır eşleşme, "filtre uygulandı ama hiçbir satır tutmadı" demektir.
  # DÜŞÜRÜLEN yaprak ise "filtre HİÇ UYGULANAMADI" demektir (bilinmeyen işlem,
  # çevrilemeyen değer, metadata kapısı, bulunmayan sütun). Eski kod ikinciyi
  # hiç incelemiyordu: kullanıcı bir daraltma istediği hâlde derleyici onu
  # düşürdüğünde analiz TÜM YETKİLİ KÜME üzerinde sürüyor ve sonuç, sorulan
  # sorudan başka bir soruyu yanıtlıyordu.
  dusen_sutunlar <- unique(vapply(
    compiled$dropped %||% list(),
    function(d) as.character(d$leaf$column %||% "")[1],
    character(1)
  ))
  dusen_sutunlar <- dusen_sutunlar[nzchar(dusen_sutunlar) & !is.na(dusen_sutunlar)]

  uygulanan_sutunlar <- vapply(compiled$groups %||% list(), function(g) g$column, character(1))
  birincil_on <- pk_filter_primary_column(query, unique(c(uygulanan_sutunlar, dusen_sutunlar)))

  # RED kararında maske de KAPALI hâle getirilir.
  #
  # Çağıranlar bugün `action` alanını okuyup boş çerçeve döndürüyor; ancak
  # düşürülmüş filtre durumunda derleyicinin maskesi TÜMÜ-TRUE'dur. `action`
  # denetimini atlayan/ileride eklenen bir tüketici, reddedilmiş bir istekte
  # TÜM yetkili kümeyi analiz ederdi. Maske reddin kendisiyle tutarlı olmalıdır.
  reddet <- function(mesaj, sutun = NULL) {
    sonuc$primary_column <- sutun
    sonuc$action <- "refuse"
    sonuc$refusal_message <- mesaj
    sonuc$mask <- rep(FALSE, nrow(data))
    sonuc
  }

  # 0a) Kullanıcının istediği HER filtre düşürüldü -> analiz yapılmaz.
  if (isTRUE(compiled$all_dropped)) {
    return(reddet(.pk_policy_dropped_message(compiled$dropped), birincil_on))
  }

  # 0b) BİRİNCİL varlık filtresi düşürüldü -> ikincil daraltmalarla devam etmek
  # popülasyonu sessizce genişletir; RED.
  if (!is.null(birincil_on) && birincil_on %in% dusen_sutunlar &&
      !(birincil_on %in% uygulanan_sutunlar)) {
    return(reddet(
      .pk_policy_dropped_message(
        Filter(function(d) identical(as.character(d$leaf$column %||% "")[1], birincil_on),
               compiled$dropped)
      ),
      birincil_on
    ))
  }

  # 0c) BİRİNCİL varlık BELİRLENEMEDİ ve EN AZ BİR yaprak düşürüldü -> RED.
  #
  # `pk_filter_primary_column()` metadata yokken iki veya daha fazla filtre
  # sütunu görür görmez NULL döner; bu durumda 0b hiç çalışmaz ve 0a yalnızca
  # HER yaprak düşerse devreye girer. Arada kalan durum sessizce genişleyen bir
  # popülasyondur: "ANKA projesinde 2024 harcamaları" isteğinde `ProjeAdi`
  # yaprağı düşürülüp `Yil` uygulanırsa analiz 2024'ün TÜM projelerini özetler.
  # Bu, 1b'deki sıfır eşleşme kuralının reddettiği sonucun aynısıdır; hangi
  # daraltmanın sorunun ÖZNESİ olduğu bilinemediğinden karar SİMETRİK olmalıdır.
  if (is.null(birincil_on) && length(dusen_sutunlar)) {
    return(reddet(.pk_policy_dropped_message(compiled$dropped), NULL))
  }

  sifir_gruplar <- Filter(function(g) isTRUE(g$zero_match), compiled$groups)
  if (!length(sifir_gruplar)) return(sonuc)

  filtre_sutunlari <- vapply(compiled$groups, function(g) g$column, character(1))
  birincil <- pk_filter_primary_column(query, filtre_sutunlari)
  sonuc$primary_column <- birincil

  # 1) Birincil sütunda sıfır eşleşme -> analiz yapılmaz.
  for (grup in sifir_gruplar) {
    if (!is.null(birincil) && identical(grup$column, birincil)) {
      degerler <- unlist(lapply(grup$applied, function(l) l$values), use.names = FALSE)
      sonuc$action <- "refuse"
      sonuc$refusal_message <- .pk_policy_zero_match_message(grup$column, degerler)
      return(sonuc)
    }
  }

  dusurulen <- vapply(sifir_gruplar, function(g) g$column, character(1))

  # 1b) Birincil varlık BELİRLENEMEDİ ve UYGULANAN HER filtre sıfır eşleşti.
  # Bu durumda "ikincil daraltmayı düşür, analiz sürsün" kuralı geriye hiçbir
  # daraltma bırakmaz: tüm yetkili küme üzerinden istatistik üretilir ve bu,
  # §5.4 kural 6'nın engellemek için var olduğu sonucun ta kendisidir —
  # kullanıcı adını verdiği kayıt bulunamamışken tüm veri setinin özetini alır.
  # Kapalı başarısız karar REDdir; metadata birincil varlığı beyan ettiğinde
  # (Faz 3b) bu dal yerini yukarıdaki birincil sütun kuralına bırakır.
  #
  # KAPSAM: kural, sıfır eşleşen grupların HEPSİ olmasını beklemez. Birincil
  # varlık BİLİNMİYORKEN hangi daraltmanın sorunun ÖZNESİ olduğu da bilinemez;
  # bu yüzden TEK bir grubun bile sıfır eşleşmesi, o grubun özne olma ihtimali
  # nedeniyle RED gerektirir. Aksi hâlde "ANKA projesinde 2024 harcamaları"
  # sorusunda `ProjeAdi` sıfır eşleşip düşürülür ve kullanıcı, adını verdiği
  # proje bulunamamışken 2024'ün TÜM projelerinin özetini alır.
  if (is.null(birincil)) {
    degerler <- unlist(
      lapply(sifir_gruplar, function(g) {
        unlist(lapply(g$applied, function(l) l$values), use.names = FALSE)
      }),
      use.names = FALSE
    )
    sonuc$action <- "refuse"
    sonuc$refusal_message <- .pk_policy_zero_match_message(
      paste(unique(dusurulen), collapse = "` / `"), degerler
    )
    return(sonuc)
  }

  # 2) Yalnızca ikincil sütunlarda sıfır eşleşme -> düşür, ifşa et, devam et.
  kalan <- Filter(function(f) {
    yaprak <- pk_filter_normalize_leaf(f)
    !(yaprak$column %in% dusurulen)
  }, filters)

  # KURTARMA DERLEMESİ AYNI METADATA İLE YAPILIR.
  #
  # İlk derleme `query`'yi taşır ve `pk_filter_leaf_mask()` bu sayede
  # `column_meta$filterable = FALSE` olan sütunda kapalı başarısız olur.
  # Burada `query` düşürülürse, metadata tarafından ENGELLENMİŞ bir ikincil
  # filtre (sıfır eşleşmediği için `kalan` içinde durur) bu kez kapıdan
  # geçerdi: kurtarma yolu, ilk derlemenin bilinçli olarak reddettiği bir
  # kriteri uygulayarak anlamsal kapıyı ZAYIFLATIRDI.
  yeniden <- pk_filter_compile(data, kalan, query = query)

  sonuc$action <- "dropped_secondary"
  sonuc$mask <- yeniden$mask
  sonuc$dropped_columns <- dusurulen
  sonuc$disclosures <- vapply(sifir_gruplar, function(g) {
    degerler <- unlist(lapply(g$applied, function(l) l$values), use.names = FALSE)
    degerler <- unique(as.character(degerler %||% character(0)))
    sprintf(
      "`%s` alanındaki `%s` kriteri hiçbir kayıtla eşleşmedi ve UYGULANMADI.",
      g$column,
      paste(utils::head(degerler, 5L), collapse = "`, `")
    )
  }, character(1))

  sonuc
}

#' Politika ifşalarını kullanıcıya gösterilecek bloğa çevir
pk_filter_policy_disclosure_block <- function(policy, dropped = list(), noop_columns = character(0)) {
  satirlar <- character(0)

  if (length(policy$disclosures)) {
    satirlar <- c(satirlar, policy$disclosures)
  }

  for (d in dropped) {
    sutun <- d$leaf$column %||% "?"
    satirlar <- c(satirlar, sprintf(
      "`%s` filtresi uygulanamadı (%s).", sutun, d$reason %||% "bilinmeyen sebep"
    ))
  }

  if (length(noop_columns)) {
    satirlar <- c(satirlar, sprintf(
      "`%s` filtresi neredeyse tüm kayıtları koruduğu için ETKİSİZ kabul edildi.",
      paste(noop_columns, collapse = "`, `")
    ))
  }

  if (!length(satirlar)) return(NULL)

  paste0(
    "\U000026A0\U0000FE0F **Filtreleme Uyarısı:**\n- ",
    paste(satirlar, collapse = "\n- ")
  )
}
