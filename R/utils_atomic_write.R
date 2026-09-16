# ==============================================================================
# Dosya Yolu: R/utils_atomic_write.R
# Açıklama: Disk üzerine dosya yazımı için atomik (hepsi-ya-hiçbiri) yardımcıları.
#           Windows VM ortamında file.rename başarısız olursa file.copy fallback
#           yolunu kullanır. UTF-8 içerik binary modda yazılarak Windows native
#           codepage bozulmaları ve kısmi JSON/index yazımları önlenir.
#
# KAPSAM: ATOMİKLİK vs DAYANIKLILIK (bilinen ve İZLENEN sınır)
#   Bu katman ATOMİKLİK sağlar: geçici dosyaya yaz -> boyutu doğrula -> hedefe
#   taşı. Okuyucu hedefte ya ESKİ ya YENİ tam içeriği görür; yarım dosya görmez.
#
#   DAYANIKLILIK (power-loss sonrası kalıcılık) İDDİA EDİLMEZ. `flush(con)` ve
#   `close(con)` baytları işletim sistemi önbelleğine verir; kalıcı depoya
#   indirilmelerini GARANTİ ETMEZ. Taşımadan sonra kapsayan dizin de
#   eşitlenmez. Base R `fsync`/`fdatasync` ya da dizin eşitleme için bir temel
#   işlem SUNMAZ (derlenmiş bir bağımlılık olmadan kapatılamaz) ve alt süreç
#   çağırmak bu yolda kabul edilebilir bir çözüm değildir. Bu yüzden ani güç
#   kesintisi, başarıyla raporlanmış bir indeks/manifest/API-anahtarı yazımını
#   yine de kaybettirebilir.
#
#   Operatör azaltımı: kalıcı depo diskinde write-back önbelleğini kapatın ya da
#   pil destekli/"write-through" bir birim kullanın. Bu sınırı "çözüldü" olarak
#   raporlamayın; kapatmak derlenmiş bir eşitleme yardımcısı gerektirir.
# ==============================================================================

# Hedefteki baytların beklenen içerikle birebir aynı olup olmadığını söyler.
# Fallback yolunda "kopya FALSE bildirdi ama yazma aslında tamamlandı" durumunu
# ayırt etmek ve eşzamanlı bir yazıcının dosyasını silmemek için kullanılır.
.atomic_ayni_icerik <- function(path, beklenen_raw) {
  tryCatch({
    if (!file.exists(path)) return(FALSE)
    boyut <- suppressWarnings(file.info(path)$size[1])
    if (is.na(boyut) || boyut != length(beklenen_raw)) return(FALSE)
    mevcut <- readBin(path, what = "raw", n = length(beklenen_raw))
    identical(mevcut, beklenen_raw)
  }, error = function(e) FALSE)
}

# UNC/Windows'ta `file.info()` kopyadan hemen sonra geçici olarak NA dönebilir;
# boyut okuması sınırlı olarak yeniden denenir ve yalnızca denemeler tükendiğinde
# NA döner.
.atomic_boyut_oku <- function(path, deneme_sayisi = 3L, bekleme_sn = 0.05) {
  boyut <- NA_real_
  for (deneme in seq_len(deneme_sayisi)) {
    boyut <- suppressWarnings(file.info(path)$size[1])
    if (!is.na(boyut)) break
    Sys.sleep(bekleme_sn)
  }
  boyut
}

# Verilen içeriği aynı dizinde geçici dosyaya yazar, ardından file.rename ile
# hedefe taşır. Başarısızlık durumunda file.copy + unlink fallback kullanır.
# final_path üzerinde kısmi yazım kalması engellenir.
#
# ÖNEMLİ:
# - file.rename() ve file.copy() burada bilerek namespace ile çağrılmaz.
#   tests/testthat/test-atomic-write-fallback.R bu fonksiyonları izole
#   atomic_env içinde stub ederek fallback davranışını doğrular.
# - Yazım binary modda yapılır; böylece Windows VM native codepage'e düşülmez.
atomic_write_text <- function(content, final_path, encoding = "UTF-8") {
  if (!is.character(final_path) ||
      length(final_path) != 1L ||
      is.na(final_path) ||
      !nzchar(final_path)) {
    stop("atomic_write_text: 'final_path' tek elemanli, bos olmayan karakter olmali.")
  }

  if (!is.character(content)) {
    stop("atomic_write_text: 'content' karakter vektoru olmali.")
  }

  final_path <- suppressWarnings(
    normalizePath(final_path, winslash = "/", mustWork = FALSE)
  )

  dir_path <- dirname(final_path)

  if (!dir.exists(dir_path)) {
    dir_ready <- tryCatch({
      if (requireNamespace("fs", quietly = TRUE)) {
        fs::dir_create(dir_path, recurse = TRUE)
      } else {
        dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
      }
      TRUE
    }, error = function(e) FALSE)

    if (!isTRUE(dir_ready) || !dir.exists(dir_path)) {
      stop(sprintf(
        "atomic_write_text: hedef dizin oluşturulamadı: %s",
        dir_path
      ))
    }
  }

  tmp_path <- tempfile(
    pattern = "atomic_",
    tmpdir = dir_path,
    fileext = ".tmp"
  )

  on.exit({
    if (file.exists(tmp_path)) {
      try(unlink(tmp_path, force = TRUE), silent = TRUE)
    }
  }, add = TRUE)

  if (!dir.exists(dirname(tmp_path))) {
    stop(sprintf(
      "atomic_write_text: geçici dosya dizini bulunamadı: %s",
      dirname(tmp_path)
    ))
  }

  # İçeriği tek UTF-8 metne indir ve raw byte dizisine çevir.
  # Bu değişkenin adı aşağıdaki writeBin() ile aynı kalmalıdır.
  content_utf8 <- enc2utf8(paste(content, collapse = "\n"))
  content_raw <- charToRaw(content_utf8)

  con <- tryCatch(
    file(tmp_path, open = "wb"),
    error = function(e) {
      stop(sprintf(
        "atomic_write_text: geçici dosya açılamadı: %s | %s",
        tmp_path,
        conditionMessage(e)
      ), call. = FALSE)
    }
  )

  tryCatch(
    {
      writeBin(content_raw, con)
      flush(con)
    },
    finally = {
      close(con)
    }
  )

  # Referans BEKLENEN içerik uzunluğudur. Disk/kota dolduğunda `flush()` hata
  # yerine UYARI üretir; kısa yazılan geçici dosya "tam" sayılıp hedefe
  # işleniyor ve doğrulanmış yedek siliniyordu.
  # Boyut SINIRLI YENİDEN DENEMELİ okuyucuyla alınır: `file.info()` UNC/Windows
  # birimlerinde `close(con)` sonrasında kısa süre `NA` dönebiliyor ve TAM
  # yazılmış geçici dosya "tam yazılamadı" diye reddediliyordu (`.save_index()`
  # ve `save_user_api_key()` doğru yazımı başarısız bildiriyordu).
  tmp_boyut <- .atomic_boyut_oku(tmp_path)
  if (!file.exists(tmp_path) || is.na(tmp_boyut) ||
      tmp_boyut != length(content_raw)) {
    stop("atomic_write_text: geçici dosya tam yazılamadı.")
  }

  moved <- suppressWarnings(file.rename(tmp_path, final_path))

  if (!isTRUE(moved)) {
    # Windows VM'de kilitli dosya / rename başarısızlığı görülebilir.
    # Testler bu fallback yolunun çalıştığını doğrular. Kopya atomik olmadığı
    # için mevcut hedef önce yedeklenir; kopya başarısız/eksikse geri yüklenir.
    # Yedeğin KAYNAK boyutuyla eşleştiği doğrulanır. Kısmi bir yedek (disk
    # dolması) daha sonra "geri yüklendi" sayılıyordu, çünkü doğrulama hedefi
    # yalnızca o kısmi yedeğin boyutuyla karşılaştırıyordu.
    yedek <- NA_character_
    kaynak_boyut <- NA_real_
    hedef_vardi <- file.exists(final_path)
    if (hedef_vardi) {
      # UNC/Windows'ta `file.info()` kopyadan hemen sonra geçici olarak NA
      # dönebilir; tek okuma başarılı bir yedeği "doğrulanamadı" sayıp yazmayı
      # gereksiz yere düşürüyordu.
      kaynak_boyut <- .atomic_boyut_oku(final_path)
      yedek <- paste0(final_path, ".bak_", basename(tempfile("aw")))
      yedek_ok <- isTRUE(suppressWarnings(file.copy(final_path, yedek, overwrite = TRUE)))
      yedek_boyut_ilk <- .atomic_boyut_oku(yedek)
      if (!isTRUE(yedek_ok) || is.na(kaynak_boyut) || is.na(yedek_boyut_ilk) ||
          yedek_boyut_ilk != kaynak_boyut) {
        # Doğrulanmış yedek YOK: mevcut hedefin üzerine yazmak, kısmi kopya
        # durumunda tek sağlam kopyayı yok eder. Hedefe hiç dokunulmaz.
        try(unlink(yedek, force = TRUE), silent = TRUE)
        stop(sprintf(
          "atomic_write_text: mevcut hedef için doğrulanmış yedek oluşturulamadı: %s",
          final_path
        ), call. = FALSE)
      }
    }

    # SAHİPLİK REZERVASYONU: hedef bu çağrıdan ÖNCE YOKKEN kopya kısmi yazımdan
    # sonra FALSE dönerse, kalan `final_path` bırakılamaz (satır 54 sözleşmesi:
    # kısmi hedef oluşmaz) ama körlemesine de silinemez — eşzamanlı bir yazar
    # aynı adı oluşturmuş olabilir. Ad atomik bir rezervasyonla kilitlenir:
    # rezervasyon bizdeyken hedefte oluşan içerik BU çağrının çıktısıdır ve
    # yalnızca o zaman silinir. Rezervasyon alınamazsa (başka bir terfi sahibi)
    # hedefe DOKUNULMAZ ve durum loglanır.
    # NEDEN YALNIZCA YEDEK YOLDA: yukarıdaki `file.rename()` ATOMİKTİR ve
    # hiçbir koşulda kısmi hedef bırakmaz; eşzamanlı iki yazarda son terfi
    # kazanır (bu fonksiyonun sözleşmesi budur, karşılaştır-ve-değiştir
    # değildir). Rezervasyon, ATOMİK OLMAYAN `file.copy()` yedeği için gerekir.
    # `index.json` gibi gerçek karşılıklı dışlama gerektiren yazarlar ayrıca
    # `.file_store_with_index_lock()` altında çalışır.
    # BİLİNEN ARTIK RİSK: aynı rezervasyondan geçmeyen bir yazar bu kanıtın
    # dışındadır; pencere daraltılır, kapatılmaz (bkz. utils_path_reservation.R).
    sahiplik <- FALSE
    rezerv_denendi <- FALSE
    rezerv_yolu <- ""
    rezerv_jetonu <- ""
    if (!isTRUE(hedef_vardi) &&
        exists("mergen_reservation_token", mode = "function", inherits = TRUE) &&
        exists("mergen_reservation_acquire", mode = "function", inherits = TRUE)) {
      rezerv_denendi <- TRUE
      rezerv_yolu <- paste0(final_path, ".aw-rsv")
      rezerv_jetonu <- mergen_reservation_token("awrsv")
      sahiplik <- isTRUE(mergen_reservation_acquire(rezerv_yolu, rezerv_jetonu))
      if (!sahiplik &&
          exists("mergen_reservation_takeover", mode = "function", inherits = TRUE)) {
        # Çökmüş bir çalıştırma `on.exit` çalıştırmadan ölürse `.aw-rsv` dizini
        # diskte kalır ve aynı hedefe yapılan SONRAKİ her yedek yazım kalıcı
        # olarak engellenirdi. Bayat rezervasyon sahiplik kanıtıyla devralınır.
        sahiplik <- isTRUE(mergen_reservation_takeover(rezerv_yolu, rezerv_jetonu))
      }
      if (sahiplik) {
        on.exit({
          if (exists("mergen_reservation_release", mode = "function", inherits = TRUE)) {
            mergen_reservation_release(rezerv_yolu, rezerv_jetonu)
          }
        }, add = TRUE)
      }
    }

    # REZERVASYON İSTENDİ AMA ALINAMADI: hedef adı başka bir yazarın. Kopya
    # ATOMİK DEĞİLDİR; üzerine yazmak, kısmi kopyada (disk dolması, UNC
    # kesilmesi) sahiplik kanıtı olmadığı için SİLİNEMEYEN bozuk bir dosya
    # bırakıyordu (`index.json` ayrıştırılamaz hâle geliyordu). Satır 54
    # sözleşmesi gereği hedefe DOKUNULMAZ.
    if (isTRUE(rezerv_denendi) && !isTRUE(sahiplik)) {
      try(unlink(tmp_path, force = TRUE), silent = TRUE)
      stop(sprintf(
        "atomic_write_text: hedef adı başka bir yazar tarafından rezerve edilmiş: %s",
        final_path
      ), call. = FALSE)
    }

    copied <- suppressWarnings(file.copy(tmp_path, final_path, overwrite = TRUE))
    # UNC/Windows dosya sisteminde metaveri kopyalamadan hemen sonra NA
    # dönebiliyor. Tek okumaya güvenmek BAŞARILI kopyayı geri alıyordu (yeni
    # dosya siliniyor, mevcut dosya eski sürüme döndürülüyordu).
    hedef_boyut <- .atomic_boyut_oku(final_path)
    tam <- isTRUE(copied) && !is.na(hedef_boyut) &&
      hedef_boyut == length(content_raw)

    # Kopya FALSE bildirse bile hedefte TAM ve bizimkiyle AYNI içerik varsa
    # yazma gerçekleşmiştir; geri alma eşzamanlı yazıcının sonucunu ezerdi.
    if (!tam && .atomic_ayni_icerik(final_path, content_raw)) {
      tam <- TRUE
    }

    if (tam) {
      try(unlink(tmp_path, force = TRUE), silent = TRUE)
      if (!is.na(yedek)) {
        try(unlink(yedek, force = TRUE), silent = TRUE)
        # Silme sonucu DENETLENİR: Windows/UNC üzerinde kilitli bir yedek sessizce
        # kalıyor ve her fallback yazımı yeni bir `.bak_*` kopyası biriktiriyordu.
        if (file.exists(yedek)) {
          try(
            log_warn(paste0(
              "[ATOMIC_WRITE] Yedek silinemedi; el ile temizlenmelidir: ", yedek
            )),
            silent = TRUE
          )
        }
      }
      moved <- TRUE
    } else if (!is.na(yedek) && file.exists(yedek)) {
      # Geri yükleme DOĞRULANMADAN yedek silinirse (ör. disk dolduğunda kopya
      # da başarısız olur) kısmi hedef kalır ve tek sağlam kopya yok edilirdi.
      geri <- suppressWarnings(file.copy(yedek, final_path, overwrite = TRUE))
      # Metaveri okuması UNC'de kopyadan hemen sonra NA dönebilir; tek okumaya
      # güvenmek BAŞARILI geri yüklemeyi "doğrulanamadı" sayıyordu.
      son_boyut <- .atomic_boyut_oku(final_path)
      geri_tam <- isTRUE(geri) && !is.na(son_boyut) && !is.na(kaynak_boyut) &&
        son_boyut == kaynak_boyut
      if (isTRUE(geri_tam)) {
        try(unlink(yedek, force = TRUE), silent = TRUE)
      } else {
        try(
          log_warn(paste0(
            "[ATOMIC_WRITE] Geri yükleme doğrulanamadı; yedek korunuyor: ", yedek
          )),
          silent = TRUE
        )
      }
    } else {
      # Buraya yalnızca hedef bu çağrıdan ÖNCE YOKKEN düşülür (var olan hedef
      # doğrulanmış yedek olmadan hiç değiştirilmez). Kısmi dosya bırakılmaz;
      # ancak eşzamanlı bir yazıcının TAM dosyası silinmemelidir.
      # Boyut farkı sahiplik KANITI DEĞİLDİR: eşzamanlı bir yazarın farklı
      # boyuttaki GEÇERLİ dosyası da bu koşulu sağlayıp siliniyordu. Silme
      # yalnızca hedef bu çağrıdan ÖNCE YOKKEN yapılır; kanıt ya kopyanın bu
      # çağrı tarafından BİLDİRİLMESİ ya da hedef adının bu çağrı tarafından
      # REZERVE EDİLMİŞ olmasıdır. İkinci kanıt, kısmi yazımdan sonra `FALSE`
      # dönen kopyanın hedefi diskte bırakmasını engeller.
      bizim_kismi <- !isTRUE(hedef_vardi) && (isTRUE(copied) || isTRUE(sahiplik))
      if (file.exists(final_path) && isTRUE(bizim_kismi)) {
        try(unlink(final_path, force = TRUE), silent = TRUE)
      } else if (file.exists(final_path)) {
        try(
          log_warn(paste0(
            "[ATOMIC_WRITE] Sahipliği doğrulanamayan hedef korunuyor: ", final_path
          )),
          silent = TRUE
        )
      }
    }
  }

  if (!isTRUE(moved)) {
    stop(sprintf("atomic_write_text: hedefe taşıma başarısız: %s", final_path))
  }

  invisible(TRUE)
}

# JSON serileştirme + atomik yazım. jsonlite::write_json doğrudan dosyaya yazdığı
# için kısmi yazım riski vardır; bu yardımcı önce metne serileştirir, sonra atomik
# yazar. pretty/auto_unbox parametreleri jsonlite::toJSON ile birebir geçirilir.
atomic_write_json <- function(data,
                              final_path,
                              pretty = TRUE,
                              auto_unbox = TRUE,
                              null = "null") {
  json_metni <- jsonlite::toJSON(
    data,
    pretty = pretty,
    auto_unbox = auto_unbox,
    null = null
  )

  atomic_write_text(
    as.character(json_metni),
    final_path = final_path,
    encoding = "UTF-8"
  )
}