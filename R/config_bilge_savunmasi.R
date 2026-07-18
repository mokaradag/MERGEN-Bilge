# ==============================================================================
# Dosya Yolu: R/config_bilge_savunmasi.R
# Açıklama: Bilge Savunması (kule savunma oyunu) yapılandırması: özellik
#           bayrağı, sürüm sabitleri, yük boyutu sınırları, persona oyun
#           manifesti, harita/zorluk katalogları, haftalık meydan okuma
#           türetimi ve başarım kataloğu.
#
# Sözleşmeler:
#   * Persona KİMLİĞİ tek kaynağı R/config_characters.R'dir. Bu dosya kimlik
#     alanlarını (id, ad, ünvan, renk, görsel yolları) oradan türetir; yalnızca
#     oyuna özgü rol/yetenek META verisini ekler. Oyun sayısal dengesi
#     (hasar, menzil, maliyet) istemci tarafında www/js/bilge_savunmasi_denge.js
#     dosyasındadır; sunucu yalnızca sınır/di doğrulama değerlerini tutar.
#   * Eski mitolojik kimlikler bu dosyada YER ALMAZ; geçiş yalnızca
#     normalize_character_id() sınırında yaşar.
#   * Haftalık meydan okuma türetimi DETERMİNİSTİKTİR: aynı hafta kodu her
#     zaman aynı harita/tohum/degistirici bileşimini üretir (Europe/Istanbul
#     takvimi, ISO hafta).
#   * Bu dosya Shiny/reaktif/DB erişimi içermez; saf yapılandırma + saf
#     fonksiyonlardan oluşur ve izole testlerde tek başına source edilebilir.
# ==============================================================================

# --- Sürüm ve sınır sabitleri -------------------------------------------------

# Oyun istemci/sunucu protokol sürümü (uyumsuz istemci yükü reddedilir).
BS_OYUN_SURUMU <- "1.0.0"

# Denge sürümü: sayısal denge değişimlerinde artırılır; koşu kayıtlarına yazılır.
BS_DENGE_SURUMU <- "2026.07"

# Koşu/plan yük şema sürümü (JSON şekli değişirse artırılır).
BS_SEMA_SURUMU <- 1L

# Sunucuya gönderilen JSON yüklerinin üst karakter sınırları.
BS_MAX_YUK_KARAKTER <- 60000L
BS_MAX_KONTROL_NOKTASI_KARAKTER <- 40000L
BS_MAX_PLAN_KARAKTER <- 20000L

#' Bilge Savunması Özellik Bayrağı
#'
#' @description Oyunun görünür/etkin olup olmadığını belirler. Öncelik:
#' options(mergen.bilge_savunmasi.enabled) > MERGEN_BILGE_SAVUNMASI_ENABLED
#' ortam değişkeni > varsayılan TRUE. Yalnızca açık "kapalı" değerleri
#' (false/f/0/no/off/hayır/kapalı) oyunu devre dışı bırakır.
bilge_savunmasi_enabled <- function() {
  kapali_degerler <- c("false", "f", "0", "no", "off", "hayır", "hayir", "kapalı", "kapali")

  opt <- getOption("mergen.bilge_savunmasi.enabled", default = NULL)
  if (!is.null(opt)) {
    if (isFALSE(opt)) return(FALSE)
    if (is.character(opt) && tolower(trimws(opt[1])) %in% kapali_degerler) return(FALSE)
    return(TRUE)
  }

  env <- Sys.getenv("MERGEN_BILGE_SAVUNMASI_ENABLED", unset = "")
  if (nzchar(env) && tolower(trimws(env)) %in% kapali_degerler) {
    return(FALSE)
  }

  TRUE
}

#' Oyun Sürüm Bilgisi Paketi
bs_surum_bilgisi <- function() {
  list(
    oyun = BS_OYUN_SURUMU,
    denge = BS_DENGE_SURUMU,
    sema = BS_SEMA_SURUMU
  )
}

# --- Persona oyun manifesti ---------------------------------------------------

# Oyuna özgü rol/yetenek META verisi. Kimlik alanları BURADA TANIMLANMAZ;
# yalnızca kanonik persona kimliklerine oyun rolü eklenir. Yetenek kimlikleri
# persona sözleşmesindeki modern yetenek adlarıdır.
.bs_persona_rolleri <- list(
  emre = list(
    rol = "Komuta",
    rol_aciklama = "Dengeli saldırı ve yakın savunuculara komuta aurası",
    yetenek_id = "cozum_dalgasi",
    yetenek_ad = "Çözüm Dalgası",
    yetenek_aciklama = "Kısa süreli alan hasarı ve yakın savunuculara hız desteği"
  ),
  selin = list(
    rol = "Onarım",
    rol_aciklama = "Bilgi Çekirdeği'ni ve yapıları onaran yapıcı uzman",
    yetenek_id = "sinyal_taramasi",
    yetenek_ad = "Sinyal Taraması",
    yetenek_aciklama = "Çekirdeğe onarım uygular ve gizli tehditleri görünür kılar"
  ),
  deniz = list(
    rol = "Kontrol",
    rol_aciklama = "Rota kontrolü, yavaşlatma ve dalga öngörüsü",
    yetenek_id = "rota_projesi",
    yetenek_ad = "Rota Projesi",
    yetenek_aciklama = "Geniş alanda tehditleri yavaşlatan stratejik bölge açar"
  ),
  can = list(
    rol = "Doğrulama",
    rol_aciklama = "Zırh kırma, işaretleme ve yüksek değerli hedef avı",
    yetenek_id = "dogrulama_isini",
    yetenek_ad = "Doğrulama Işını",
    yetenek_aciklama = "İşaretli hedeflere yüksek kritik hasarlı doğrulama ışını"
  ),
  ipek = list(
    rol = "Destek",
    rol_aciklama = "Menzil/kaynak desteği ve kalkan yenileme rehberi",
    yetenek_id = "rehber_halkasi",
    yetenek_ad = "Rehber Halkası",
    yetenek_aciklama = "Yakın savunuculara kalkan ve küçük kaynak desteği verir"
  )
)

#' Oyun Persona Manifesti
#'
#' @description Beş kanonik personayı oyun istemcisine taşınacak biçimde
#' derler. Kimlik alanları get_characters_data() üzerinden okunur (tek
#' kaynak); bu fonksiyon yalnızca oyun rolü/yetenek meta verisini ekler.
#' @return Persona başına liste: id, ad, tam_ad, unvan, aksan renkleri,
#'   avatar/portre yolları ve rol/yetenek alanları.
bs_persona_manifest <- function() {
  chars <- get_characters_data()

  lapply(chars$styles, function(rec) {
    rol <- .bs_persona_rolleri[[rec$id]]
    if (is.null(rol)) {
      # Tanımsız persona manifestte yer almaz (savunmacı sınır).
      return(NULL)
    }

    list(
      id = rec$id,
      ad = rec$label,
      tam_ad = rec$full_name,
      unvan = rec$subtitle,
      aksan = rec$accent,
      aksan_koyu = rec$accent_active,
      avatar = rec$avatar,
      portre = rec$image,
      rol = rol$rol,
      rol_aciklama = rol$rol_aciklama,
      yetenek_id = rol$yetenek_id,
      yetenek_ad = rol$yetenek_ad,
      yetenek_aciklama = rol$yetenek_aciklama
    )
  }) |> Filter(f = Negate(is.null))
}

# --- Harita ve zorluk katalogları ---------------------------------------------

#' Kampanya Harita Kataloğu
#'
#' @description Sunucu tarafı doğrulama ve ilerleme için harita üst verisi.
#' Görsel/yol/yerleşim ayrıntıları istemcidedir; burada yalnızca doğrulama
#' sınırları ve kilit zinciri tutulur.
bs_harita_katalogu <- function() {
  list(
    baglam_kapisi = list(
      sira = 1L,
      ad = "Bağlam Kapısı",
      aciklama = "Tek ana rotalı öğretici savunma hattı",
      dalga_sayisi = 8L,
      taban_cekirdek = 20L,
      dalga_dusman_ust_siniri = 28L,
      dalga_dusman_sayilari = c(6L, 12L, 10L, 12L, 11L, 10L, 15L, 12L),
      dalga_patron_sayilari = c(0L, 0L, 0L, 1L, 0L, 0L, 0L, 1L),
      acilis_kosulu = NULL
    ),
    celiski_kavsagi = list(
      sira = 2L,
      ad = "Çelişki Kavşağı",
      aciklama = "Çift rotalı kavşak; hedef önceliği ve kontrol öğretir",
      dalga_sayisi = 10L,
      taban_cekirdek = 20L,
      dalga_dusman_ust_siniri = 34L,
      dalga_dusman_sayilari = c(8L, 12L, 12L, 10L, 13L, 10L, 11L, 13L, 17L, 10L),
      dalga_patron_sayilari = c(0L, 0L, 0L, 1L, 0L, 0L, 0L, 1L, 0L, 1L),
      acilis_kosulu = "baglam_kapisi"
    ),
    bilgi_cekirdegi = list(
      sira = 3L,
      ad = "Bilgi Çekirdeği",
      aciklama = "Elit tehditler ve patron dalgalı ileri seviye savunma",
      dalga_sayisi = 12L,
      taban_cekirdek = 20L,
      dalga_dusman_ust_siniri = 42L,
      dalga_dusman_sayilari = c(14L, 13L, 12L, 11L, 12L, 9L, 14L, 12L, 18L, 16L, 13L, 11L),
      dalga_patron_sayilari = c(0L, 0L, 0L, 1L, 0L, 0L, 0L, 1L, 0L, 0L, 0L, 1L),
      acilis_kosulu = "celiski_kavsagi"
    )
  )
}

#' Zorluk Kataloğu
#'
#' @description Zorluk seviyeleri ve puan çarpanları. "gelismis" zorluk,
#' ilgili haritanın normal zorlukta tamamlanmasıyla açılır.
bs_zorluk_katalogu <- function() {
  list(
    normal = list(ad = "Normal", puan_carpani = 1.0),
    gelismis = list(ad = "Gelişmiş", puan_carpani = 1.35)
  )
}

# Tek dalga için sunucu tarafı puan üst sınırı hesabında kullanılan katsayılar.
BS_DUSMAN_PUAN_UST_SINIRI <- 18L   # Normal düşman başına en yüksek taban puan
BS_PATRON_PUAN_UST_SINIRI <- 320L  # Patron dalgası ek puan üst sınırı

# Sunucu tarafı dalga puan hesabı, istemcinin bildirdiği olduruldu/puan
# alanlarına değil bu deterministik harita planından türetilen düşman sayısına
# dayanır. Kimlikler www/js/bilge_savunmasi_denge.js ile aynı tutulmalıdır.
.bs_haftalik_dalga_sayi_carpanlari <- list(
  hizli_tehditler = 1,
  kisitli_kaynak = 1,
  dirya_dalgalar = 1.2
)

bs_dalga_sayi_carpani <- function(degistirici = NULL) {
  kimlik <- if (is.null(degistirici)) "" else as.character(degistirici)[1]
  if (is.na(kimlik)) kimlik <- ""
  carpan <- .bs_haftalik_dalga_sayi_carpanlari[[kimlik]]
  if (is.null(carpan)) 1 else as.numeric(carpan)
}

# İstemcinin izin verilen en yüksek oyun hızı çarpanı (bkz.
# www/js/bilge_savunmasi_uygulama.js: kosu.hiz yalnızca 1 veya 2 olabilir).
# Süre makullüğü doğrulaması, bildirilen OYUN süresini (sure_saniye) sunucu
# saatine göre GERÇEK geçen süreyle karşılaştırırken bu çarpanı hesaba
# katmalıdır; aksi halde meşru 2x hızlandırılmış koşular reddedilir.
BS_MAKS_HIZ_CARPANI <- 2

# Yıldız eşikleri: kalan çekirdek oranına göre (zafer = en az 1 yıldız).
BS_YILDIZ_ESIKLERI <- c(uc = 0.90, iki = 0.60)

# --- Haftalık meydan okuma ----------------------------------------------------

#' Hafta Kodu (Europe/Istanbul, ISO hafta)
#'
#' @param tarih POSIXct/Date; varsayılan şimdi.
#' @return "2026-W29" biçiminde hafta kodu.
bs_hafta_kodu <- function(tarih = Sys.time()) {
  yerel <- as.POSIXct(tarih, tz = "Europe/Istanbul")
  format(yerel, "%G-W%V")
}

#' Hafta Kodundan Deterministik Tohum
#'
#' @description Aynı hafta kodu her zaman aynı 31-bit pozitif tam sayı tohumu
#' üretir. Basit çarpımsal karma; kripto amaçlı değildir. Hesap R integer
#' aralığını taşırmamak için double aritmetiği + mod 2^31-1 ile yapılır
#' (ara değerler 2^53 hassasiyet sınırının çok altında kalır).
bs_hafta_tohumu <- function(hafta_kodu) {
  bytes <- utf8ToInt(paste0("bilge-savunmasi:", hafta_kodu))
  h <- 17
  for (b in bytes) {
    h <- (h * 31 + b) %% 2147483647
  }
  as.integer(max(1, h))
}

# Haftadan haftaya dönen oyun değiştiricileri (istemci sim tarafından bilinir).
.bs_haftalik_degistiriciler <- list(
  list(id = "hizli_tehditler", ad = "Hızlı Tehditler", aciklama = "Tehdit hızı %15 artar"),
  list(id = "kisitli_kaynak", ad = "Kısıtlı Kaynak", aciklama = "Başlangıç kaynağı %20 azalır"),
  list(id = "dirya_dalgalar", ad = "Yoğun Dalgalar", aciklama = "Dalga başına tehdit sayısı artar")
)

#' Haftalık Meydan Okuma Yapılandırması
#'
#' @description Verilen tarihe ait deterministik haftalık meydan okuma
#' bileşimini döndürür: hafta kodu, dönen harita, gelişmiş zorluk, tohum ve
#' değiştirici. Tüm oyuncular aynı haftada aynı bileşimi alır.
bs_haftalik_meydan_okuma <- function(tarih = Sys.time()) {
  hafta <- bs_hafta_kodu(tarih)
  tohum <- bs_hafta_tohumu(hafta)

  haritalar <- names(bs_harita_katalogu())
  hafta_no <- suppressWarnings(as.integer(sub("^.*-W", "", hafta)))
  if (is.na(hafta_no)) hafta_no <- 1L

  harita <- haritalar[(hafta_no %% length(haritalar)) + 1L]
  degistirici <- .bs_haftalik_degistiriciler[[(hafta_no %% length(.bs_haftalik_degistiriciler)) + 1L]]

  list(
    hafta_kodu = hafta,
    harita = harita,
    zorluk = "gelismis",
    tohum = tohum,
    degistirici = degistirici,
    sema = BS_SEMA_SURUMU
  )
}

# --- Başarım kataloğu ---------------------------------------------------------

#' Başarım ve Kalıcı Açılım Kataloğu
#'
#' @description Sunucu tarafında değerlendirilen başarımlar. "tur" alanı
#' "basarim" (rozet) veya "acilim" (kalıcı kozmetik/taktik açılım) olabilir.
bs_basarim_katalogu <- function() {
  list(
    list(id = "ilk_zafer", tur = "basarim", ad = "İlk Zafer",
         aciklama = "Herhangi bir haritayı ilk kez tamamla"),
    list(id = "kusursuz_savunma", tur = "basarim", ad = "Kusursuz Savunma",
         aciklama = "Bir haritayı çekirdek hasarı almadan tamamla"),
    list(id = "uc_yildiz", tur = "basarim", ad = "Üç Yıldız",
         aciklama = "Bir haritada üç yıldız kazan"),
    list(id = "patron_avcisi", tur = "basarim", ad = "Patron Avcısı",
         aciklama = "Bir patron dalgasını çekirdek kaybı olmadan atlat"),
    list(id = "kampanya_ustasi", tur = "basarim", ad = "Kampanya Ustası",
         aciklama = "Üç kampanya haritasını da tamamla"),
    list(id = "haftalik_katilimci", tur = "basarim", ad = "Haftalık Katılımcı",
         aciklama = "Bir haftalık meydan okumayı tamamla"),
    list(id = "tam_kadro", tur = "basarim", ad = "Tam Kadro",
         aciklama = "Bir koşuda beş savunucunun tamamını konuşlandır"),
    list(id = "acilim_gece_temasi", tur = "acilim", ad = "Gece Operasyonu Teması",
         aciklama = "Kampanya Ustası sonrası açılan görsel harita teması"),
    list(id = "acilim_veri_izleri", tur = "acilim", ad = "Veri İzleri Efekti",
         aciklama = "Üç Yıldız sonrası açılan mermi izi görünümü")
  )
}
