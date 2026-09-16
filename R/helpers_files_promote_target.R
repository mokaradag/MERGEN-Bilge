# ==============================================================================
# Dosya Yolu: R/helpers_files_promote_target.R
# Açıklama: Aşamalı yükleme kopyasının KALICI ADA TERFİ adımı. Terfi
#           OLUŞTURMA anlamlıdır; hiçbir koşulda DEĞİŞTİRME değildir.
#
# NEDEN AYRI DOSYA: `R/helpers_files_copy_promote.R` 130 satır / 12 fonksiyon
# bakım bütçesindedir. Sahiplik kanıtlı terfi (bağlantı -> rezervasyon ->
# taşıma) ve sınırlı görünürlük yoklaması oraya sığmıyordu; bütçe gevşetmek
# yerine terfi adımı buraya alındı ve `helpers_files_copy_promote.R` dosyasından
# ÖNCE yüklenir. Saf yoklama yardımcıları `R/helpers_files_promote_probe.R`
# dosyasındadır ve bu dosyadan ÖNCE yüklenir.
#
# SÖZLEŞME:
#   * `mergen_promote_staged_file()` hedefi ASLA ezmez. Önce `file.link()`
#     (atomik, üzerine-yazmaz) denenir; desteklenmeyen dosya sistemlerinde
#     `dir.create()` rezervasyonu altında `file.rename()` kullanılır.
#   * Hedef EŞZAMANLI olarak belirdiyse `yabanci` bayrağı döner ve çağıran o
#     dosyaya DOKUNMAZ (silmek başka bir yüklemeyi yok ederdi).
#   * `promoted` alanı hedefi BU çağrının oluşturduğunu bildirir. Görünürlük
#     yoklaması TERFİ BAŞARISI DEĞİLDİR: bağlantı/taşıma tamamlandıktan sonra
#     yavaş bir UNC paylaşımında yoklama `FALSE` dönebiliyor, çağıran da
#     TAMAMLANMIŞ yüklemeyi siliyordu (veri kaybı). Çağıran yalnızca
#     `promoted` FALSE iken hedefi temizler.
#   * Görünürlük yoklaması SINIRLIDIR ve deneme sayısı geçersizse güvenli
#     varsayılana düşer; `seq_len(NA)` hatası terfi SONRASINDA oluşup dosyayı
#     kayıtsız bırakıyordu.
#
# BİLİNEN ARTIK RİSK (izleniyor, kapatılmadı): base R'de ÜZERİNE-YAZMAYAN
# `rename` ilkeli yoktur. Yedek yolda (`file.link()` desteklenmiyor) hedefin
# yokluğu rezervasyon altında İKİ BAĞIMSIZ okumayla doğrulanır; yanlış negatif
# penceresi daraltılır, tümüyle kapatılmaz. Depodaki TÜM terfi yolları aynı
# rezervasyondan geçer ve bağlantı desteği dosya sisteminin özelliğidir; bu
# yüzden karışık (bağlantılı + yedek) eşzamanlılık pratikte oluşmaz.
# ==============================================================================

# Terfi rezervasyon dizini. `include.dirs = FALSE` ile listelendiği için dosya
# listelemesinde görünmez; hedef adı her yüklemede benzersiz olduğundan çökmüş
# bir çalıştırmadan kalan rezervasyon yeni yüklemeleri engellemez.
MERGEN_PROMOTE_RESERVATION_SUFFIX <- ".mergen-rsv"

# Staging adı terfiden SONRA düşürülür. Silme BAŞARISIZ olursa terfi GEÇERLİDİR
# (sabit bağlantıda içerik kalıcı adda durur); hedefi silmek tamamlanmış bir
# yüklemeyi yok ederdi. Durum yalnızca raporlanır ve `.mergen-part` soneki
# listelemeden zaten ayıklanır.
.mergen_promote_drop_staging <- function(staging, var_mi) {
  try(unlink(staging, force = TRUE), silent = TRUE)
  if (!mergen_promote_probe(var_mi, staging)) return(invisible(TRUE))
  try(
    warning(sprintf(
      "mergen_promote_staged_file: staging adı silinemedi; terfi geçerli: %s",
      staging
    ), call. = FALSE),
    silent = TRUE
  )
  invisible(FALSE)
}

# Staging dosyasını kalıcı ada terfi ettirir.
# Dönen liste: ok (görünürlük dâhil başarı), yabanci (hedef başka bir yüklemeye
# ait mi), promoted (hedefi BU çağrı oluşturdu mu).
mergen_promote_staged_file <- function(staging, hedef, var_mi,
                                       gorunurluk_denemesi = 10L) {
  var_mi_guvenli <- function(p) mergen_promote_probe(var_mi, p)

  # 1) ATOMİK, ÜZERİNE-YAZMAYAN TERFİ. `file.link()` hedef VARSA başarısız olur,
  #    bu yüzden `!file.exists()` + `file.rename()` ikilisindeki yarış ortadan
  #    kalkar: iki çağrı aynı hedefi seçtiğinde POSIX `file.rename()` diğerinin
  #    dosyasını sessizce değiştiriyordu.
  bagli <- isTRUE(tryCatch(
    suppressWarnings(file.link(staging, hedef)),
    error = function(e) FALSE
  ))
  if (bagli) {
    # Bağlantı kuruldu: staging adı düşürülür, içerik kalıcı adda kalır.
    .mergen_promote_drop_staging(staging, var_mi_guvenli)
    return(list(
      ok = mergen_promote_wait_visible(hedef, var_mi_guvenli, gorunurluk_denemesi),
      yabanci = FALSE,
      promoted = TRUE
    ))
  }

  # 2) Bağlantı kurulamadı: hedef ZATEN VARSA sahibi başka bir yüklemedir.
  if (var_mi_guvenli(hedef)) return(list(ok = FALSE, yabanci = TRUE, promoted = FALSE))

  # 3) Sabit bağlantı desteklenmiyor (bazı ağ paylaşımları / FAT). Terfi ATOMİK
  #    bir rezervasyon altında yapılır: hedef adını yalnızca TEK çalıştırma
  #    sahiplenir ve taşımayı o çalıştırma dener.
  rezerv <- paste0(hedef, MERGEN_PROMOTE_RESERVATION_SUFFIX)
  jeton <- if (exists("mergen_reservation_token", mode = "function", inherits = TRUE)) {
    mergen_reservation_token("uprsv")
  } else {
    ""
  }
  alindi <- nzchar(jeton) &&
    exists("mergen_reservation_acquire", mode = "function", inherits = TRUE) &&
    isTRUE(mergen_reservation_acquire(rezerv, jeton))
  if (!alindi) {
    # FAIL-CLOSED: rezervasyon alınamadıysa terfi DENENMEZ. Sessizce jetonsuz
    # `file.rename()` yapmak, düzeltilen yarışı geri getirirdi.
    return(list(ok = FALSE, yabanci = var_mi_guvenli(hedef), promoted = FALSE))
  }

  sonuc <- tryCatch({
    # İKİ BAĞIMSIZ okuma: yavaş bir UNC paylaşımında tek okuma yanlış negatif
    # verebiliyor ve yedek yoldaki `file.rename()` EŞZAMANLI oluşan hedefi
    # sessizce değiştirebiliyordu.
    if (var_mi_guvenli(hedef) || var_mi_guvenli(hedef)) {
      list(ok = FALSE, yabanci = TRUE, promoted = FALSE)
    } else {
      tasindi <- isTRUE(tryCatch(file.rename(staging, hedef), error = function(e) FALSE))
      if (!tasindi && var_mi_guvenli(staging)) {
        # `overwrite = FALSE`: eşzamanlı beliren hedef EZİLMEZ.
        tasindi <- isTRUE(tryCatch(file.copy(staging, hedef, overwrite = FALSE),
                                   error = function(e) FALSE))
        if (tasindi) .mergen_promote_drop_staging(staging, var_mi_guvenli)
      }
      if (tasindi) {
        list(
          ok = mergen_promote_wait_visible(hedef, var_mi_guvenli, gorunurluk_denemesi),
          yabanci = FALSE,
          promoted = TRUE
        )
      } else {
        # REZERVASYON BİZDEYKEN hedefte oluşan içerik BU çağrının yarım
        # çıktısıdır: rezervasyon alınırken hedefin YOK olduğu doğrulandı ve tüm
        # terfi yolları aynı rezervasyondan geçer. Bu yüzden `yabanci` FALSE
        # döner ve çağıran kısmi hedefi temizler; aksi hâlde yarım dosya kalıcı
        # adla diskte kalıp geçerli bir yükleme gibi listelenirdi.
        list(ok = FALSE, yabanci = FALSE, promoted = FALSE)
      }
    }
  }, finally = {
    if (exists("mergen_reservation_release", mode = "function", inherits = TRUE)) {
      mergen_reservation_release(rezerv, jeton)
    }
  })

  sonuc
}
