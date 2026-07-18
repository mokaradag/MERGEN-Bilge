# ==============================================================================
# Dosya Yolu: R/helpers_bilge_savunmasi_validation.R
# Açıklama: Bilge Savunması sunucu tarafı doğrulama ve puanlama katmanı.
#           İstemciden gelen koşu özetleri, kontrol noktaları ve savunma
#           planı (blueprint) yükleri burada doğrulanır; nihai puan istemci
#           beyanından değil, sınırlandırılmış dalga özetlerinden SUNUCUDA
#           yeniden hesaplanır.
#
# Sözleşmeler:
#   * Bu dosya SAFTIR: Shiny, DB, ağ, dosya sistemi ve reaktif durum içermez;
#     izole testlerde tek başına (config ile birlikte) source edilebilir.
#   * İstemciden gelen hiçbir serbest puan değeri doğrudan kabul edilmez.
#     bs_puan_yeniden_hesapla() dalga başına üst sınır uygular.
#   * Patron dalgası kuralı (dalga %% 4 == 0 veya son dalga) istemci
#     www/js/bilge_savunmasi_dalga.js ile AYNI olmalıdır.
#   * Plan yükleri yalnızca bilinen alanları, sınırlı boyutları ve kanonik
#     persona kimliklerini kabul eder; çalıştırılabilir içerik reddedilir.
# ==============================================================================

# --- Küçük saf yardımcılar ----------------------------------------------------

.bs_tam_sayi <- function(x, varsayilan = NA_integer_) {
  v <- suppressWarnings(as.integer(x[1]))
  if (length(v) == 0 || is.na(v)) return(varsayilan)
  v
}

.bs_sayi <- function(x, varsayilan = NA_real_) {
  v <- suppressWarnings(as.numeric(x[1]))
  if (length(v) == 0 || is.na(v) || !is.finite(v)) return(varsayilan)
  v
}

# Kullanıcı metnini sınırla ve kontrol karakterlerini ayıkla (görüntüleme
# tarafı ayrıca htmlEscape uygular; bu katman yalnızca boyut/karakter sınırı).
.bs_metin_temizle <- function(x, max_karakter = 80L) {
  if (is.null(x) || length(x) == 0) return("")
  metin <- as.character(x[1])
  if (is.na(metin)) return("")
  metin <- gsub("[[:cntrl:]]", " ", metin)
  metin <- trimws(metin)
  if (nchar(metin) > max_karakter) {
    metin <- substr(metin, 1L, max_karakter)
  }
  metin
}

#' JSON Yükünü Boyut Sınırıyla Güvenli Çöz
#'
#' @description Metin biçimindeki JSON yükünü önce karakter sınırından geçirir,
#' sonra güvenli biçimde listeye çözer. Sınır aşımı veya bozuk JSON NULL döner.
bs_yuk_coz <- function(json_metin, sinir = BS_MAX_YUK_KARAKTER) {
  if (is.null(json_metin) || length(json_metin) == 0) return(NULL)
  metin <- as.character(json_metin[1])
  if (is.na(metin) || !nzchar(metin)) return(NULL)
  if (nchar(metin, type = "bytes") > sinir) return(NULL)

  tryCatch(
    jsonlite::fromJSON(metin, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

# --- Patron dalgası ve puan sınırları -----------------------------------------

#' Patron Dalgası mı?
#'
#' @description Dalga numarasının patron dalgası olup olmadığını döndürür.
#' Kural istemci dalga denetleyicisi ile birebir aynıdır: her 4. dalga ve
#' haritanın son dalgası patron dalgasıdır.
bs_patron_dalgasi_mi <- function(dalga_no, dalga_sayisi) {
  d <- .bs_tam_sayi(dalga_no)
  n <- .bs_tam_sayi(dalga_sayisi)
  if (is.na(d) || is.na(n)) return(FALSE)
  (d %% 4L == 0L) || (d == n)
}

#' Tek Dalga İçin Sunucu Puanı
#'
#' @description Dalga puanı istemcinin serbestçe beyan ettiği `puan` veya
#' `olduruldu` değerlerinden değil, sunucunun harita kataloğunda tuttuğu
#' deterministik dalga düşman sayısından türetilir. Haftalık sayı değiştiricisi
#' varsa sunucuya ait normal düşman sayısına uygulanır ve sonuç yine haritanın
#' dalga üst sınırıyla kırpılır.
bs_dalga_puan_siniri <- function(harita_kaydi, dalga_no, degistirici = NULL) {
  ust <- .bs_tam_sayi(harita_kaydi$dalga_dusman_ust_siniri, 30L)
  d <- .bs_tam_sayi(dalga_no)
  sayilar <- harita_kaydi$dalga_dusman_sayilari
  patron_sayilari <- harita_kaydi$dalga_patron_sayilari
  adet <- if (!is.na(d) && length(sayilar) >= d) .bs_tam_sayi(sayilar[[d]], ust) else ust
  patron_adet <- if (!is.na(d) && length(patron_sayilari) >= d) {
    .bs_tam_sayi(patron_sayilari[[d]], 0L)
  } else {
    0L
  }
  carpan <- if (exists("bs_dalga_sayi_carpani", mode = "function", inherits = TRUE)) {
    bs_dalga_sayi_carpani(degistirici)
  } else {
    1
  }
  if (is.na(adet) || adet < 0L) adet <- 0L
  if (is.na(patron_adet) || patron_adet < 0L) patron_adet <- 0L
  if (is.na(carpan) || !is.finite(carpan) || carpan <= 0) carpan <- 1
  normal_adet <- max(0L, adet - patron_adet)
  adet <- min(as.integer(round(normal_adet * carpan)) + patron_adet, ust)

  taban <- adet * BS_DUSMAN_PUAN_UST_SINIRI
  if (adet > 0L && bs_patron_dalgasi_mi(dalga_no, harita_kaydi$dalga_sayisi)) {
    taban <- taban + BS_PATRON_PUAN_UST_SINIRI
  }
  as.integer(taban)
}

# --- Puan, yıldız, seviye -----------------------------------------------------

#' Dalga Özetlerinden Sunucu Puanını Yeniden Hesapla
#'
#' @description Dalga puanını istemci beyanından bağımsız olarak, sunucuya ait
#' deterministik dalga planından hesaplar; çekirdek ve zafer bonusunu ekler,
#' zorluk çarpanını uygular. Dönen değer sunucunun NİHAİ puanıdır.
bs_puan_yeniden_hesapla <- function(dalga_ozetleri,
                                    son_cekirdek,
                                    harita_kaydi,
                                    zorluk_kaydi,
                                    zafer = FALSE,
                                    degistirici = NULL) {
  ham <- 0
  for (dalga in dalga_ozetleri) {
    ham <- ham + bs_dalga_puan_siniri(harita_kaydi, dalga$dalga, degistirici)
  }

  cekirdek <- max(0, .bs_sayi(son_cekirdek, 0))
  bonus <- cekirdek * 25
  if (isTRUE(zafer)) bonus <- bonus + 500

  carpan <- .bs_sayi(zorluk_kaydi$puan_carpani, 1)
  as.integer(round((ham + bonus) * carpan))
}

#' Yıldız Sayısını Hesapla
#'
#' @description Zafer yoksa 0; zafer varsa kalan çekirdek oranına göre 1-3
#' yıldız. Eşikler BS_YILDIZ_ESIKLERI sabitinden okunur.
bs_yildiz_hesapla <- function(son_cekirdek, taban_cekirdek, zafer) {
  if (!isTRUE(zafer)) return(0L)
  taban <- .bs_sayi(taban_cekirdek, 20)
  if (is.na(taban) || taban <= 0) return(1L)
  oran <- max(0, .bs_sayi(son_cekirdek, 0)) / taban

  if (oran >= BS_YILDIZ_ESIKLERI[["uc"]]) return(3L)
  if (oran >= BS_YILDIZ_ESIKLERI[["iki"]]) return(2L)
  1L
}

#' Koşu Puanından XP Hesapla (koşu başına sınırlı)
bs_xp_hesapla <- function(puan) {
  p <- max(0, .bs_sayi(puan, 0))
  as.integer(min(400L, floor(p / 10)))
}

#' Toplam XP'den Oyuncu Seviyesi
bs_seviye_hesapla <- function(toplam_xp) {
  xp <- max(0, .bs_sayi(toplam_xp, 0))
  as.integer(1L + floor(sqrt(xp / 150)))
}

# --- Koşu özeti doğrulama (ana kapı) ------------------------------------------

.bs_dogrulama_hatasi <- function(neden) {
  list(gecerli = FALSE, neden = neden)
}

#' Koşu Bitirme Özetini Doğrula ve Puanla
#'
#' @description Sunucunun verdiği koşu kaydına (harita/zorluk/tohum/sürümler)
#' karşı istemci özetini doğrular. Başarıda sunucu tarafından hesaplanan puan,
#' yıldız ve XP ile birlikte gecerli=TRUE döner; aksi halde açıklayıcı bir
#' neden döner.
#'
#' @param ozet İstemci özeti: dalga_ozetleri, son_cekirdek, son_dalga, zafer,
#'   sure_saniye, kullanilan_kahramanlar, sema, oyun_surumu alanları.
#' @param kosu Sunucu koşu kaydı: harita, zorluk, tohum, baslangic_zamani
#'   (POSIXct) alanları.
#' @param sunucu_gecen_saniye Sunucu saatine göre koşu süresi (NA olabilir).
bs_kosu_ozeti_dogrula <- function(ozet,
                                  kosu,
                                  sunucu_gecen_saniye = NA_real_,
                                  harita_katalogu = bs_harita_katalogu(),
                                  zorluk_katalogu = bs_zorluk_katalogu()) {
  if (!is.list(ozet)) return(.bs_dogrulama_hatasi("ozet_bicimi"))

  # Sürüm uyumu: şema ve oyun sürümü desteklenmeli.
  if (!identical(.bs_tam_sayi(ozet$sema), BS_SEMA_SURUMU)) {
    return(.bs_dogrulama_hatasi("sema_surumu"))
  }
  if (!identical(as.character(ozet$oyun_surumu)[1], BS_OYUN_SURUMU)) {
    return(.bs_dogrulama_hatasi("oyun_surumu"))
  }

  harita_kaydi <- harita_katalogu[[as.character(kosu$harita)[1]]]
  zorluk_kaydi <- zorluk_katalogu[[as.character(kosu$zorluk)[1]]]
  if (is.null(harita_kaydi) || is.null(zorluk_kaydi)) {
    return(.bs_dogrulama_hatasi("kosu_kaydi"))
  }

  # Harita/zorluk/tohum istemci özetiyle çelişmemeli (meydan okuma bütünlüğü).
  if (!identical(as.character(ozet$harita)[1], as.character(kosu$harita)[1]) ||
      !identical(as.character(ozet$zorluk)[1], as.character(kosu$zorluk)[1]) ||
      !identical(.bs_tam_sayi(ozet$tohum), .bs_tam_sayi(kosu$tohum))) {
    return(.bs_dogrulama_hatasi("kosu_eslesmesi"))
  }

  dalga_sayisi <- harita_kaydi$dalga_sayisi
  son_dalga <- .bs_tam_sayi(ozet$son_dalga)
  if (is.na(son_dalga) || son_dalga < 1L || son_dalga > dalga_sayisi) {
    return(.bs_dogrulama_hatasi("son_dalga"))
  }

  # Dalga özetleri: 1..son_dalga, kesin artan, sınır içinde.
  dalgalar <- ozet$dalga_ozetleri
  if (!is.list(dalgalar) || length(dalgalar) != son_dalga) {
    return(.bs_dogrulama_hatasi("dalga_ozetleri"))
  }

  taban_cekirdek <- harita_kaydi$taban_cekirdek
  onceki_cekirdek <- taban_cekirdek
  onarim_toleransi <- 3  # Selin onarımı: dalga başına sınırlı artış

  for (i in seq_along(dalgalar)) {
    dalga <- dalgalar[[i]]
    if (!identical(.bs_tam_sayi(dalga$dalga), i)) {
      return(.bs_dogrulama_hatasi("dalga_sirasi"))
    }

    olduruldu <- .bs_tam_sayi(dalga$olduruldu, -1L)
    if (is.na(olduruldu) || olduruldu < 0L ||
        olduruldu > harita_kaydi$dalga_dusman_ust_siniri) {
      return(.bs_dogrulama_hatasi("dalga_dusman_sayisi"))
    }

    cekirdek <- .bs_sayi(dalga$cekirdek, -1)
    if (is.na(cekirdek) || cekirdek < 0 || cekirdek > taban_cekirdek) {
      return(.bs_dogrulama_hatasi("cekirdek_araligi"))
    }
    if (cekirdek > onceki_cekirdek + onarim_toleransi) {
      return(.bs_dogrulama_hatasi("cekirdek_artisi"))
    }
    onceki_cekirdek <- cekirdek

    kaynak <- .bs_sayi(dalga$kaynak, 0)
    if (is.na(kaynak) || kaynak < 0 || kaynak > 99999) {
      return(.bs_dogrulama_hatasi("kaynak_araligi"))
    }
  }

  son_cekirdek <- .bs_sayi(ozet$son_cekirdek, -1)
  if (is.na(son_cekirdek) || son_cekirdek < 0 || son_cekirdek > taban_cekirdek) {
    return(.bs_dogrulama_hatasi("son_cekirdek"))
  }

  zafer <- isTRUE(ozet$zafer)
  if (zafer && (son_dalga != dalga_sayisi || son_cekirdek <= 0)) {
    return(.bs_dogrulama_hatasi("zafer_kosulu"))
  }

  # Süre makullüğü: en hızlı oyun temposunda bile dalga başına alt sınır var;
  # sunucu saatine göre geçen süre de (tolerans payıyla) aşılamaz.
  sure <- .bs_sayi(ozet$sure_saniye, -1)
  if (is.na(sure) || sure < son_dalga * 6 || sure > 4 * 3600) {
    return(.bs_dogrulama_hatasi("sure_makullugu"))
  }
  # Bildirilen sure_saniye OYUN saatidir (sim.tick(gercekDt * kosu.hiz) ile
  # ilerler); istemci en fazla 2x hız sunar, bu yüzden 2x'te oyun saati
  # gerçek geçen sürenin ~iki katına ulaşabilir. Sunucu saatine göre geçen
  # süreyle karşılaştırma, izin verilen en yüksek hız çarpanıyla
  # ölçeklendirilmelidir; aksi halde meşru hızlandırılmış koşular
  # sure_sunucu_uyumu ile reddedilir.
  if (is.finite(sunucu_gecen_saniye) && !is.na(sunucu_gecen_saniye) &&
      sure > (sunucu_gecen_saniye * BS_MAKS_HIZ_CARPANI) + 90) {
    return(.bs_dogrulama_hatasi("sure_sunucu_uyumu"))
  }

  # Kullanılan kahramanlar kanonik kimlik alt kümesi olmalı.
  kahramanlar <- unique(unlist(ozet$kullanilan_kahramanlar, use.names = FALSE))
  kahramanlar <- as.character(kahramanlar)
  if (length(kahramanlar) > 5L ||
      (length(kahramanlar) > 0 && !all(kahramanlar %in% CHARACTER_VALID_IDS))) {
    return(.bs_dogrulama_hatasi("kahraman_kimlikleri"))
  }

  puan <- bs_puan_yeniden_hesapla(
    dalgalar, son_cekirdek, harita_kaydi, zorluk_kaydi, zafer = zafer,
    degistirici = kosu$degistirici
  )
  yildiz <- bs_yildiz_hesapla(son_cekirdek, taban_cekirdek, zafer)

  list(
    gecerli = TRUE,
    neden = NULL,
    puan = puan,
    yildiz = yildiz,
    xp = bs_xp_hesapla(puan),
    zafer = zafer,
    son_dalga = son_dalga,
    son_cekirdek = son_cekirdek,
    sure_saniye = sure,
    kahramanlar = kahramanlar
  )
}

#' Kontrol Noktası Yükünü Doğrula
#'
#' @description Kontrol noktası dalga numarasının harita sınırında ve tekdüze
#' ilerlemede olduğunu, durum JSON'unun boyut sınırını aşmadığını doğrular.
bs_kontrol_noktasi_dogrula <- function(dalga_no, durum_json, harita_kaydi,
                                       onceki_dalga = 0L) {
  d <- .bs_tam_sayi(dalga_no)
  if (is.na(d) || d < 1L || d > harita_kaydi$dalga_sayisi) {
    return(.bs_dogrulama_hatasi("kontrol_dalga"))
  }
  if (d <= .bs_tam_sayi(onceki_dalga, 0L)) {
    return(.bs_dogrulama_hatasi("kontrol_sirasi"))
  }
  metin <- as.character(durum_json)[1]
  if (is.na(metin) || !nzchar(metin) ||
      nchar(metin, type = "bytes") > BS_MAX_KONTROL_NOKTASI_KARAKTER) {
    return(.bs_dogrulama_hatasi("kontrol_boyutu"))
  }
  list(gecerli = TRUE, neden = NULL, dalga = d)
}

# --- Savunma planı (blueprint) doğrulama --------------------------------------

#' Savunma Planı Yükünü Doğrula
#'
#' @description Yayınlanacak plan yükünü katı bir şemaya göre doğrular:
#' yalnızca bilinen alanlar, kanonik persona kimlikleri, sınırlı yerleşim
#' sayısı ve sınırlı koordinat/seviye aralıkları kabul edilir. Çalıştırılabilir
#' içerik (script, HTML, yol, SQL) taşınamaz; başlık boyutu kırpılır.
bs_plan_dogrula <- function(plan,
                            harita_katalogu = bs_harita_katalogu(),
                            zorluk_katalogu = bs_zorluk_katalogu()) {
  if (!is.list(plan)) return(.bs_dogrulama_hatasi("plan_bicimi"))

  if (!identical(.bs_tam_sayi(plan$sema), BS_SEMA_SURUMU)) {
    return(.bs_dogrulama_hatasi("plan_sema"))
  }

  harita <- as.character(plan$harita)[1]
  if (is.na(harita) || !harita %in% names(harita_katalogu)) {
    return(.bs_dogrulama_hatasi("plan_harita"))
  }
  zorluk <- as.character(plan$zorluk)[1]
  if (is.na(zorluk) || !zorluk %in% names(zorluk_katalogu)) {
    return(.bs_dogrulama_hatasi("plan_zorluk"))
  }
  tohum <- .bs_tam_sayi(plan$tohum)
  if (is.na(tohum) || tohum < 1L) {
    return(.bs_dogrulama_hatasi("plan_tohum"))
  }

  baslik <- .bs_metin_temizle(plan$baslik, 80L)
  if (!nzchar(baslik)) baslik <- "İsimsiz Savunma Planı"

  yerlesimler <- plan$yerlesimler
  if (!is.list(yerlesimler) || length(yerlesimler) > 60L) {
    return(.bs_dogrulama_hatasi("plan_yerlesim_sayisi"))
  }

  temiz_yerlesimler <- vector("list", length(yerlesimler))
  for (i in seq_along(yerlesimler)) {
    y <- yerlesimler[[i]]
    if (!is.list(y)) return(.bs_dogrulama_hatasi("plan_yerlesim_bicimi"))

    kahraman <- as.character(y$kahraman)[1]
    if (is.na(kahraman) || !kahraman %in% CHARACTER_VALID_IDS) {
      return(.bs_dogrulama_hatasi("plan_kahraman"))
    }
    x <- .bs_tam_sayi(y$x); yk <- .bs_tam_sayi(y$y)
    seviye <- .bs_tam_sayi(y$seviye, 1L)
    dalga <- .bs_tam_sayi(y$dalga, 1L)
    if (is.na(x) || is.na(yk) || x < 0L || x > 40L || yk < 0L || yk > 40L) {
      return(.bs_dogrulama_hatasi("plan_koordinat"))
    }
    if (is.na(seviye) || seviye < 1L || seviye > 3L) {
      return(.bs_dogrulama_hatasi("plan_seviye"))
    }
    if (is.na(dalga) || dalga < 1L || dalga > 20L) {
      return(.bs_dogrulama_hatasi("plan_dalga"))
    }

    # Yalnızca bilinen alanlar taşınır (bilinmeyen alanlar sessizce düşer).
    temiz_yerlesimler[[i]] <- list(
      kahraman = kahraman, x = x, y = yk, seviye = seviye, dalga = dalga
    )
  }

  list(
    gecerli = TRUE,
    neden = NULL,
    plan = list(
      sema = BS_SEMA_SURUMU,
      harita = harita,
      zorluk = zorluk,
      tohum = tohum,
      baslik = baslik,
      yerlesimler = temiz_yerlesimler
    )
  )
}

# --- Liderlik tablosu sıralaması ----------------------------------------------

#' Liderlik Tablosu Deterministik Sıralaması
#'
#' @description Girişleri şeffaf eşitlik bozucu kurallarla sıralar:
#' 1) puan (yüksek), 2) kalan çekirdek (yüksek), 3) en yüksek dalga (yüksek),
#' 4) süre (düşük), 5) en erken geçerli gönderim. Girdi data.frame'i
#' Puan/Cekirdek/SonDalga/SureSaniye/GonderimZamani kolonlarını taşımalıdır.
bs_liderlik_sirala <- function(girisler) {
  if (is.null(girisler) || !is.data.frame(girisler) || nrow(girisler) == 0) {
    return(girisler)
  }
  sira <- order(
    -as.numeric(girisler$Puan),
    -as.numeric(girisler$Cekirdek),
    -as.numeric(girisler$SonDalga),
    as.numeric(girisler$SureSaniye),
    as.character(girisler$GonderimZamani),
    method = "radix"
  )
  girisler[sira, , drop = FALSE]
}
