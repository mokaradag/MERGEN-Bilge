# ==============================================================================
# Dosya Yolu: tests/testthat/test-bilge-savunmasi-validation-behavior.R
# Açıklama: Bilge Savunması sunucu doğrulama/puanlama katmanının davranış
#           testleri: sınırlandırılmış puan yeniden hesabı, koşu özeti
#           doğrulama kapısı (anti-hile sınırları), kontrol noktası ve plan
#           doğrulaması, liderlik eşitlik bozucuları, yıldız/XP/seviye
#           hesapları. Tamamen çevrimdışı ve deterministiktir.
# ==============================================================================

local({
  repo_root <- resolve_repo_root_for_tests()

  if (!exists("normalize_character_id", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_characters.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bilge_savunmasi_enabled", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "config_bilge_savunmasi.R"),
           encoding = "UTF-8", local = globalenv())
  }
  if (!exists("bs_kosu_ozeti_dogrula", mode = "function", inherits = TRUE)) {
    source(file.path(repo_root, "R", "helpers_bilge_savunmasi_validation.R"),
           encoding = "UTF-8", local = globalenv())
  }
})

# Geçerli bir koşu özeti üretir (Bağlam Kapısı, 8 dalga, zafer).
.bs_test_gecerli_ozet <- function() {
  dalgalar <- lapply(seq_len(8L), function(i) {
    list(dalga = i, olduruldu = 8L, sizinti = 0L, puan = 60,
         cekirdek = 20, kaynak = 150)
  })
  list(
    sema = BS_SEMA_SURUMU,
    oyun_surumu = BS_OYUN_SURUMU,
    harita = "baglam_kapisi",
    zorluk = "normal",
    tohum = 12345L,
    mod = "kampanya",
    dalga_ozetleri = dalgalar,
    son_dalga = 8L,
    son_cekirdek = 20,
    zafer = TRUE,
    sure_saniye = 400,
    kullanilan_kahramanlar = list("emre", "selin"),
    olay_ozeti = list()
  )
}

.bs_test_kosu <- function() {
  list(harita = "baglam_kapisi", zorluk = "normal", tohum = 12345L)
}

test_that("geçerli koşu özeti kabul edilir ve puan sunucuda hesaplanır", {
  sonuc <- bs_kosu_ozeti_dogrula(.bs_test_gecerli_ozet(), .bs_test_kosu())

  expect_true(sonuc$gecerli)
  expect_null(sonuc$neden)
  # Dalga başına min(beyan 60, doğrulanmış öldürme sınırı) + çekirdek 20*25
  # + zafer 500: 8*60 + 1000 = 1480.
  expect_identical(sonuc$puan, 1480L)
  expect_identical(sonuc$yildiz, 3L)
  expect_identical(sonuc$xp, 148L)
  expect_true(sonuc$zafer)
  expect_identical(sonuc$kahramanlar, c("emre", "selin"))
})

test_that("şişirilmiş dalga puanı sunucu üst sınırıyla kırpılır", {
  harita <- bs_harita_katalogu()$baglam_kapisi

  # 8 doğrulanmış öldürme -> üst sınır 8 * düşman taban puanı (patron yok).
  expect_identical(bs_dalga_puan_siniri(harita, 5L, olduruldu = 8L),
                   8L * BS_DUSMAN_PUAN_UST_SINIRI)

  # Beyan edilen dalga puanı üst sınırı aşarsa toplam, sınır toplamına düşer.
  ozet <- .bs_test_gecerli_ozet()
  ozet$dalga_ozetleri <- lapply(ozet$dalga_ozetleri, function(d) {
    d$puan <- 999999
    d
  })
  sonuc <- bs_kosu_ozeti_dogrula(ozet, .bs_test_kosu())
  sinir_toplami <- sum(vapply(seq_len(8L), function(i) {
    bs_dalga_puan_siniri(harita, i, olduruldu = 8L)
  }, integer(1)))

  expect_true(sonuc$gecerli)
  expect_identical(sonuc$puan, as.integer(sinir_toplami + 20 * 25 + 500))
  expect_true(sonuc$puan < 999999)
})

test_that("puan, doğrulanmış öldürme sayısına dayanır; sıfır öldürmeyle şişirilmiş puan reddedilir", {
  ozet <- .bs_test_gecerli_ozet()
  ozet$dalga_ozetleri <- lapply(ozet$dalga_ozetleri, function(d) {
    d$olduruldu <- 0L
    d$puan <- 999999
    d
  })
  sonuc <- bs_kosu_ozeti_dogrula(ozet, .bs_test_kosu())

  expect_true(sonuc$gecerli)
  # Sıfır doğrulanmış öldürme sıfır dalga puanı demektir; yalnızca çekirdek
  # ve zafer bonusu kalır.
  expect_identical(sonuc$puan, as.integer(20 * 25 + 500))
  expect_true(sonuc$puan < 1480L)
})

test_that("bs_dalga_puan_siniri öldürme sayısını haritanın üst sınırına kırpar", {
  harita <- bs_harita_katalogu()$baglam_kapisi

  # Şişirilmiş öldürme sayısı dalganın deterministik planına kırpılır ve
  # plan tabanlı eski üst sınırı asla aşamaz.
  expect_identical(bs_dalga_puan_siniri(harita, 1L, olduruldu = 999L),
                   bs_dalga_puan_siniri(harita, 1L))
  expect_identical(bs_dalga_puan_siniri(harita, 8L, olduruldu = 999L),
                   11L * BS_DUSMAN_PUAN_UST_SINIRI + BS_PATRON_PUAN_UST_SINIRI)

  # Negatif/sıfır öldürme puan üretmez (patron bonusu dahil).
  expect_identical(bs_dalga_puan_siniri(harita, 8L, olduruldu = 0L), 0L)

  # Dönen değer her zaman tam sayıdır.
  expect_true(is.integer(bs_dalga_puan_siniri(harita, 3L, olduruldu = 5L)))
})



test_that("patron dalgası kısmi patron öldürmelerini güvenli üst sınırla korur", {
  harita <- bs_harita_katalogu()$baglam_kapisi

  # 8. dalga 11 normal + 1 patron içerir. Özet yalnızca toplam öldürme
  # sayısı taşıdığı için tek öldürme patron olabilir; üst sınır bunu korumalı.
  expect_identical(bs_dalga_puan_siniri(harita, 8L, olduruldu = 1L),
                   BS_PATRON_PUAN_UST_SINIRI)

  # Bir patron + bir normal düşman olabilecek en yüksek meşru dağılımdır.
  expect_identical(bs_dalga_puan_siniri(harita, 8L, olduruldu = 2L),
                   BS_PATRON_PUAN_UST_SINIRI + BS_DUSMAN_PUAN_UST_SINIRI)

  # Tüm dalga temizlenince 11 normal + 1 patron öldürme üst sınırı uygulanır.
  expect_identical(bs_dalga_puan_siniri(harita, 8L, olduruldu = 12L),
                   11L * BS_DUSMAN_PUAN_UST_SINIRI + BS_PATRON_PUAN_UST_SINIRI)
})

test_that("bs_dalga_puan_siniri sunucu harita planı ve değiştirici sınırını kullanır", {
  harita <- bs_harita_katalogu()$baglam_kapisi

  # olduruldu verilmeyen eski çağrılar deterministik plan davranışını korur.
  expect_identical(bs_dalga_puan_siniri(harita, 1L), 6L * BS_DUSMAN_PUAN_UST_SINIRI)
  expect_identical(bs_dalga_puan_siniri(harita, 8L),
                   11L * BS_DUSMAN_PUAN_UST_SINIRI + BS_PATRON_PUAN_UST_SINIRI)
  expect_identical(bs_dalga_puan_siniri(harita, 7L, degistirici = "dirya_dalgalar"),
                   18L * BS_DUSMAN_PUAN_UST_SINIRI)
})

test_that("koşu özeti doğrulaması hile sınırlarını reddeder", {
  kosu <- .bs_test_kosu()

  # Desteklenmeyen şema sürümü.
  ozet <- .bs_test_gecerli_ozet(); ozet$sema <- 99L
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "sema_surumu")

  # Oyun sürümü uyuşmazlığı.
  ozet <- .bs_test_gecerli_ozet(); ozet$oyun_surumu <- "0.0.1"
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "oyun_surumu")

  # Tohum değiştirilmiş (meydan okuma bütünlüğü).
  ozet <- .bs_test_gecerli_ozet(); ozet$tohum <- 999L
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "kosu_eslesmesi")

  # Dalga sırası tekdüze değil.
  ozet <- .bs_test_gecerli_ozet(); ozet$dalga_ozetleri[[3]]$dalga <- 7L
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "dalga_sirasi")

  # Dalga başına düşman sayısı harita üst sınırını aşıyor.
  ozet <- .bs_test_gecerli_ozet(); ozet$dalga_ozetleri[[2]]$olduruldu <- 500L
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "dalga_dusman_sayisi")

  # Çekirdek aralık dışı.
  ozet <- .bs_test_gecerli_ozet(); ozet$dalga_ozetleri[[4]]$cekirdek <- 55
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "cekirdek_araligi")

  # Çekirdek onarım toleransının ötesinde artıyor (3+ artış).
  ozet <- .bs_test_gecerli_ozet()
  ozet$dalga_ozetleri[[3]]$cekirdek <- 10
  ozet$dalga_ozetleri[[4]]$cekirdek <- 18
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "cekirdek_artisi")

  # Zafer iddiası son dalgaya ulaşmadan kabul edilmez.
  ozet <- .bs_test_gecerli_ozet()
  ozet$son_dalga <- 5L
  ozet$dalga_ozetleri <- ozet$dalga_ozetleri[1:5]
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "zafer_kosulu")

  # İmkansız kısa süre.
  ozet <- .bs_test_gecerli_ozet(); ozet$sure_saniye <- 10
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "sure_makullugu")

  # Sunucu saatine göre geçen süreden belirgin uzun beyan (2x hız payının
  # ötesinde bile aşırı): 400 > (100*2)+90 = 290, yine reddedilmeli.
  ozet <- .bs_test_gecerli_ozet()
  sonuc <- bs_kosu_ozeti_dogrula(ozet, kosu, sunucu_gecen_saniye = 100)
  expect_identical(sonuc$neden, "sure_sunucu_uyumu")

  # Kanonik olmayan kahraman kimliği.
  ozet <- .bs_test_gecerli_ozet()
  ozet$kullanilan_kahramanlar <- list("emre", "mergen")
  expect_identical(bs_kosu_ozeti_dogrula(ozet, kosu)$neden, "kahraman_kimlikleri")
})

test_that("süre doğrulaması izin verilen en yüksek hız çarpanını hesaba katar", {
  # Güvenlik/oynanabilirlik regresyonu: istemci sim.tick(gercekDt * kosu.hiz)
  # ile OYUN saatini ilerletir; kosu.hiz en fazla 2 olabilir (bkz.
  # www/js/bilge_savunmasi_uygulama.js). Meşru 2x hızlandırılmış bir koşuda
  # bildirilen sure_saniye (oyun saati), sunucu saatine göre GERÇEK geçen
  # süreden (sunucu_gecen_saniye) neredeyse iki kat büyük olabilir.
  kosu <- .bs_test_kosu()
  ozet <- .bs_test_gecerli_ozet()  # sure_saniye = 400 (oyun saati)

  # Gerçek geçen süre yalnızca ~210 saniye olsa bile (oyunun neredeyse
  # tamamı 2x hızda oynanmış), koşu artık reddedilmemeli:
  # 400 <= (210*2)+90 = 510.
  sonuc <- bs_kosu_ozeti_dogrula(ozet, kosu, sunucu_gecen_saniye = 210)
  expect_true(sonuc$gecerli)
  expect_null(sonuc$neden)

  # BS_MAKS_HIZ_CARPANI ötesinde bir oran (istemcinin sunabileceğinden daha
  # hızlı) hâlâ reddedilmeli: 400 > (100*2)+90 = 290.
  asiri <- bs_kosu_ozeti_dogrula(ozet, kosu, sunucu_gecen_saniye = 100)
  expect_identical(asiri$neden, "sure_sunucu_uyumu")
})

test_that("yenilgi özeti zafer bonusu olmadan kabul edilir", {
  ozet <- .bs_test_gecerli_ozet()
  ozet$zafer <- FALSE
  ozet$son_dalga <- 4L
  ozet$dalga_ozetleri <- ozet$dalga_ozetleri[1:4]
  ozet$dalga_ozetleri[[4]]$cekirdek <- 0
  ozet$son_cekirdek <- 0
  ozet$sure_saniye <- 120

  sonuc <- bs_kosu_ozeti_dogrula(ozet, .bs_test_kosu())
  expect_true(sonuc$gecerli)
  expect_false(sonuc$zafer)
  expect_identical(sonuc$yildiz, 0L)
  # İlk 4 dalganın kırpılmış beyan puanı (4*60); çekirdek 0; zafer bonusu yok.
  expect_identical(sonuc$puan, 240L)
})

test_that("yıldız eşikleri ve seviye hesabı beklenen değerleri üretir", {
  expect_identical(bs_yildiz_hesapla(20, 20, TRUE), 3L)
  expect_identical(bs_yildiz_hesapla(18, 20, TRUE), 3L)   # %90 sınırı
  expect_identical(bs_yildiz_hesapla(13, 20, TRUE), 2L)   # %65
  expect_identical(bs_yildiz_hesapla(5, 20, TRUE), 1L)
  expect_identical(bs_yildiz_hesapla(20, 20, FALSE), 0L)

  expect_identical(bs_seviye_hesapla(0), 1L)
  expect_identical(bs_seviye_hesapla(149), 1L)
  expect_identical(bs_seviye_hesapla(150), 2L)
  expect_identical(bs_seviye_hesapla(600), 3L)

  # XP koşu başına 400 ile sınırlıdır.
  expect_identical(bs_xp_hesapla(3224), 322L)
  expect_identical(bs_xp_hesapla(99999), 400L)
})

test_that("patron dalgası kuralı istemciyle aynı deseni izler", {
  expect_true(bs_patron_dalgasi_mi(4L, 8L))
  expect_true(bs_patron_dalgasi_mi(8L, 8L))
  expect_false(bs_patron_dalgasi_mi(3L, 8L))
  expect_true(bs_patron_dalgasi_mi(10L, 10L))  # son dalga her zaman patron
  expect_false(bs_patron_dalgasi_mi(9L, 10L))
})

test_that("kontrol noktası doğrulaması sınır ve sıra kurallarını uygular", {
  harita <- bs_harita_katalogu()$baglam_kapisi

  gecerli <- bs_kontrol_noktasi_dogrula(3L, "{\"a\":1}", harita, onceki_dalga = 2L)
  expect_true(gecerli$gecerli)
  expect_identical(gecerli$dalga, 3L)

  expect_identical(
    bs_kontrol_noktasi_dogrula(9L, "{}", harita)$neden, "kontrol_dalga"
  )
  expect_identical(
    bs_kontrol_noktasi_dogrula(2L, "{}", harita, onceki_dalga = 5L)$neden,
    "kontrol_sirasi"
  )
  buyuk <- paste(rep("x", BS_MAX_KONTROL_NOKTASI_KARAKTER + 10), collapse = "")
  expect_identical(
    bs_kontrol_noktasi_dogrula(3L, buyuk, harita)$neden, "kontrol_boyutu"
  )
})

test_that("bs_yuk_coz boyut sınırını ve bozuk JSON'u reddeder", {
  expect_identical(bs_yuk_coz("{\"a\": 1}")$a, 1L)
  expect_null(bs_yuk_coz("bozuk json {"))
  expect_null(bs_yuk_coz(NULL))
  expect_null(bs_yuk_coz(""))
  buyuk <- paste0("{\"a\":\"", paste(rep("y", 200), collapse = ""), "\"}")
  expect_null(bs_yuk_coz(buyuk, sinir = 50L))
})

test_that("savunma planı doğrulaması katı şemayı uygular", {
  plan <- list(
    sema = BS_SEMA_SURUMU,
    harita = "baglam_kapisi",
    zorluk = "normal",
    tohum = 777L,
    baslik = "Köşe Savunması",
    yerlesimler = list(
      list(kahraman = "emre", x = 4L, y = 3L, seviye = 2L, dalga = 1L),
      list(kahraman = "ipek", x = 6L, y = 4L, seviye = 1L, dalga = 3L)
    )
  )

  sonuc <- bs_plan_dogrula(plan)
  expect_true(sonuc$gecerli)
  expect_identical(sonuc$plan$baslik, "Köşe Savunması")
  expect_length(sonuc$plan$yerlesimler, 2L)

  # Bilinmeyen alanlar sessizce düşer (yalnızca bilinen alanlar taşınır).
  plan2 <- plan
  plan2$yerlesimler[[1]]$zararli_alan <- "<script>alert(1)</script>"
  sonuc2 <- bs_plan_dogrula(plan2)
  expect_true(sonuc2$gecerli)
  expect_null(sonuc2$plan$yerlesimler[[1]]$zararli_alan)

  # Kanonik olmayan kahraman reddedilir.
  plan3 <- plan; plan3$yerlesimler[[1]]$kahraman <- "kayra"
  expect_identical(bs_plan_dogrula(plan3)$neden, "plan_kahraman")

  # Koordinat/seviye sınırları.
  plan4 <- plan; plan4$yerlesimler[[1]]$x <- 99L
  expect_identical(bs_plan_dogrula(plan4)$neden, "plan_koordinat")
  plan5 <- plan; plan5$yerlesimler[[1]]$seviye <- 9L
  expect_identical(bs_plan_dogrula(plan5)$neden, "plan_seviye")

  # Bilinmeyen harita/şema reddedilir.
  plan6 <- plan; plan6$harita <- "olmayan_harita"
  expect_identical(bs_plan_dogrula(plan6)$neden, "plan_harita")
  plan7 <- plan; plan7$sema <- 42L
  expect_identical(bs_plan_dogrula(plan7)$neden, "plan_sema")

  # Yerleşim sayısı sınırı (60).
  plan8 <- plan
  plan8$yerlesimler <- rep(list(plan$yerlesimler[[1]]), 61L)
  expect_identical(bs_plan_dogrula(plan8)$neden, "plan_yerlesim_sayisi")

  # Kontrol karakterleri başlıktan ayıklanır ve boyut kırpılır.
  plan9 <- plan
  kontrol_karakteri <- rawToChar(as.raw(9L))
  plan9$baslik <- paste0("Kötü", kontrol_karakteri, "Başlık ",
                         paste(rep("a", 200), collapse = ""))
  sonuc9 <- bs_plan_dogrula(plan9)
  expect_true(sonuc9$gecerli)
  expect_false(grepl(kontrol_karakteri, sonuc9$plan$baslik, fixed = TRUE))
  expect_lte(nchar(sonuc9$plan$baslik), 80L)
})

test_that("liderlik sıralaması şeffaf eşitlik bozucuları uygular", {
  girisler <- data.frame(
    UserID = c(1L, 2L, 3L, 4L, 5L),
    Puan = c(1000, 1200, 1200, 1200, 1200),
    Cekirdek = c(20, 15, 18, 18, 18),
    SonDalga = c(8, 8, 8, 8, 8),
    SureSaniye = c(300, 250, 400, 380, 380),
    GonderimZamani = c("2026-07-13 10:00:00", "2026-07-13 11:00:00",
                       "2026-07-13 12:00:00", "2026-07-13 13:00:00",
                       "2026-07-13 09:00:00"),
    stringsAsFactors = FALSE
  )

  sirali <- bs_liderlik_sirala(girisler)

  # 1) puan: 1200'ler önce, 1000 en sonda.
  expect_identical(sirali$UserID[5], 1L)
  # 2) çekirdek: 18'ler 15'ten önce.
  expect_identical(sirali$UserID[4], 2L)
  # 4) süre: eşit çekirdekte kısa süre önce (380 < 400).
  # 5) erken gönderim: eşit sürede erken gönderim önce (09:00 < 13:00).
  expect_identical(sirali$UserID[1], 5L)
  expect_identical(sirali$UserID[2], 4L)
  expect_identical(sirali$UserID[3], 3L)

  # Boş/NULL girdiler güvenle geri döner.
  expect_null(bs_liderlik_sirala(NULL))
  bos <- girisler[0, , drop = FALSE]
  expect_identical(nrow(bs_liderlik_sirala(bos)), 0L)
})
