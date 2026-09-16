# ==============================================================================
# Dosya Yolu: R/config_file_store_bucket_clear.R
# Açıklama: Kullanıcı kovasının FİZİKSEL temizliği ve indeks uzlaştırması.
#
# NEDEN AYRI DOSYA: `R/config_file_store.R` 25 fonksiyon bakım tavanındadır.
# Üç durumlu dizin varlık kararı ve kilit sahipliği kaybında indeks uzlaştırması
# oraya sığmıyordu; bütçe gevşetmek yerine kova temizliği buraya alındı.
# `R/config_file_store_index_lock.R` dosyasından SONRA yüklenmelidir: fiziksel
# silme ile indeks temizliği TEK kilit altında yürür.
#
# SÖZLEŞME:
#   * Dizin varlığı KANITLANAMIYORSA (okunamayan üst dizin, geçici UNC hatası)
#     indeks kovası KORUNUR ve `FALSE` döner; "yok" varsayımı diskte kayıtsız
#     yetim dosya bırakıyordu.
#   * Silinemeyen dosyanın kaydı KORUNUR; diskten SİLİNEN dosyanın kaydı DÜŞER.
#   * Kilit sahipliği silme sırasında kaybedilirse mutasyon DURUR; o ana kadar
#     silinen yollar DIŞ KİLİT BIRAKILDIKTAN SONRA, yeniden alınan kilit
#     altında uzlaştırılır (dizin tabanlı kilit yeniden girişli DEĞİLDİR).
#   * Çözüldüğünde kova DIŞINA çıkan yol (sembolik bağlantı / junction) hiç
#     silinmez; `unlink()` hedefi izlediği için bu bir kaçış yoluydu.
# ==============================================================================

# Aday dizin için ÜÇ DURUMLU varlık kararı: "var" | "yok" | "belirsiz".
# "yok" kararı ancak ÜST dizin listelenebiliyor ve aday ad orada GÖRÜNMÜYORSA
# verilir; üst dizin de okunamıyorsa karar "belirsiz"dir ve çağıran indeksi
# korur. Windows'ta `file.access()` izinleri tam yansıtmaz; bu denetim
# POSIX/UNC üzerinde kesin, Windows'ta en iyi çabadır.
.kova_dizin_durumu <- function(dir) {
  if (isTRUE(tryCatch(dir.exists(dir), error = function(e) FALSE))) return("var")
  if (isTRUE(tryCatch(path_exists_relaxed(dir), error = function(e) FALSE))) return("var")

  ust <- tryCatch(dirname(dir), error = function(e) "")
  if (!nzchar(ust) || identical(ust, dir)) return("belirsiz")
  # ÜST dizin YOKSA aday da KESİN yoktur; bu "belirsiz" DEĞİLDİR. Eski davranış
  # henüz oluşturulmamış bir kökü (`MERGEN_MCP_BASE_DIR` yeni kurulumda yok)
  # "belirsiz" sayıyor, `sayim_basarisiz` TRUE oluyor ve kullanıcı dosyalarını
  # HİÇ temizleyemiyordu ("Dosyalar kalıcı klasörden temizlenemedi").
  # Yokluk, ata zincirinde de KANITLANIR; yalnızca dizin.exists hatası
  # verdiğinde karar "belirsiz" kalır.
  ust_var <- tryCatch(dir.exists(ust), error = function(e) NA)
  if (length(ust_var) != 1L || is.na(ust_var)) return("belirsiz")
  if (!isTRUE(ust_var)) {
    return(if (identical(.kova_dizin_durumu(ust), "yok")) "yok" else "belirsiz")
  }
  ust_okunur <- isTRUE(tryCatch(
    identical(as.integer(file.access(ust, mode = 4L))[1], 0L),
    error = function(e) FALSE
  ))
  if (!ust_okunur) return("belirsiz")

  girdiler <- tryCatch(
    list.files(ust, all.files = TRUE, no.. = TRUE),
    error = function(e) NULL
  )
  if (is.null(girdiler)) return("belirsiz")
  # Ad üst dizinde GÖRÜNÜYOR ama `dir.exists()` FALSE dedi: çelişki güvenli
  # tarafa yazılır.
  if (basename(dir) %in% girdiler) return("belirsiz")
  "yok"
}

# Kullanıcının tüm dosyalarını ve indeks kovasını temizler
mergen_clear_user_bucket <- function(user_id) {
  uid <- as.character(user_id)
  user_folder_name <- sprintf("user_%s", uid)

  # Olası tüm dizin adaylarını topla (UNC, yerel, MCP)
  candidate_dirs <- unique(c(
    tryCatch(mergen_user_upload_dir(user_id), error = function(e) NULL),
    file.path(MERGEN_UPLOADS_DIR, user_folder_name),
    file.path(MERGEN_MCP_BASE_DIR, user_folder_name)
  ))
  candidate_dirs <- candidate_dirs[!vapply(candidate_dirs, is.null, logical(1))]

  # Fiziksel silme ve indeks temizliği TEK kilit altındadır: silme kilit dışında
  # yapılırken eşzamanlı bir kayıt indekse var olmayan dosya yazabiliyordu.
  # Yol karşılaştırma anahtarı (Windows'ta harf büyüklüğü ayırt edilmez).
  # `gsub("\\\\", "/", ..., fixed = TRUE)` İKİ ardışık ters bölü arar; tek
  # Windows ayracı (`C:\dizin\dosya.txt`) dokunulmadan kalıyor ve aynı dosyanın
  # iki gösterimi eşleşmiyordu. `chartr()` HER ters bölüyü çevirir.
  .kova_yol_anahtari <- function(x) {
    yol <- chartr("\\", "/", as.character(x %||% "")[1])
    if (identical(.Platform$OS.type, "windows")) tolower(yol) else yol
  }

  # Çözülen yol kovanın İÇİNDE mi? Kök doğrulanamıyorsa KAPALI-BAŞARISIZ olur
  # (`mergen_path_inside_root()` aynı sözleşmeyi taşır). Yardımcı yüklenmemişse
  # silme YAPILMAZ: kanıtsız silme, kova dışındaki dosyayı yok edebilir.
  .kova_icinde_mi <- function(yol, kok) {
    if (!exists("mergen_path_inside_root", mode = "function", inherits = TRUE)) {
      return(FALSE)
    }
    isTRUE(tryCatch(mergen_path_inside_root(yol, kok), error = function(e) FALSE))
  }

  # Başarıyla silinen yolları indeksten ayıklar; diğer kayıtlar KORUNUR.
  # Numaralandırma hatasıyla erken dönüldüğünde de çağrılır, aksi hâlde daha
  # önceki dizinlerde SİLİNMİŞ dosyalar indekste kalıyordu.
  .kova_silinenleri_ayikla <- function(uid, silinen, anahtar_fn) {
    if (!length(silinen)) return(invisible(NULL))
    idx <- .load_index()
    kova <- idx[[uid]]
    if (is.null(kova)) return(invisible(NULL))
    tut <- vapply(
      kova,
      function(e) {
        yol <- if (is.list(e)) e$path else as.character(e %||% "")[1]
        !(anahtar_fn(yol) %in% silinen)
      },
      logical(1)
    )
    idx[[uid]] <- if (any(tut)) kova[tut] else NULL
    .save_index(idx)
    invisible(NULL)
  }

  # Sahiplik kaybından sonra indeks uzlaştırması YENİDEN alınan kilit altında
  # yapılır: mevcut kilit artık bize ait değildir ve kilitsiz `.save_index()`
  # yeni sahibin güncellemesini ezerdi. Zaman aşımı KISADIR (Shiny olay döngüsü
  # bu istisnai yolda uzun süre bloke edilmemelidir); kilit alınamazsa
  # uzlaştırma YAPILMAZ ve durum loglanır. İndekste kalan bayat kayıtlar
  # `mergen_list_user_files()` içindeki bayat-kayıt ayıklamasıyla temizlenir.
  .kova_silinenleri_kilitle_ayikla <- function(uid, silinen, anahtar_fn) {
    if (!length(silinen)) return(invisible(NULL))
    if (!exists(".file_store_with_index_lock", mode = "function", inherits = TRUE)) {
      return(.kova_silinenleri_ayikla(uid, silinen, anahtar_fn))
    }
    sonuc <- try(
      .file_store_with_index_lock(
        .kova_silinenleri_ayikla(uid, silinen, anahtar_fn),
        timeout_sec = 1,
        require_lock = TRUE
      ),
      silent = TRUE
    )
    if (inherits(sonuc, "try-error")) {
      try(
        log_warn(paste0(
          "[INDEX] Sahiplik kaybı sonrası indeks uzlaştırması yapılamadı; ",
          "bayat kayıtlar listeleme sırasında ayıklanacak."
        )),
        silent = TRUE
      )
    }
    invisible(NULL)
  }

  temizle <- function() {
    silinemeyen <- character(0)
    # Başarıyla silinen yollar: numaralandırma hatasında bile indeksten
    # ayıklanmalıdır, çünkü bu dosyalar artık diskte YOKTUR.
    silinen <- character(0)
    # Kilit sahipliği silme sırasında kaybedilirse mutasyon DURDURULUR.
    sahiplik_kaybi <- FALSE
    # Dizin içeriği okunamadığında hangi dosyaların kaldığı BİLİNMEZ; indeks
    # kovasını silmek diskte kayıtsız yetim dosya bırakır.
    sayim_basarisiz <- FALSE
    # Listeleme hiç görmediği hâlde diskte KALAN kayıt (okunamayan alt dizin).
    kalan_kayit <- FALSE
    kalan <- logical(0)

    for (dir in candidate_dirs) {
      # ÜÇ DURUMLU VARLIK DENETİMİ. `dir.exists()` ve `path_exists_relaxed()`
      # geçici bir UNC/izin hatasında da `FALSE` döner; bu "yok" sayıldığında
      # dizin atlanıyor, `idx[[uid]]` kaldırılıyor ve dosyalar diskte KALIRKEN
      # fonksiyon başarı bildiriyordu. Varlık KANITLANAMIYORSA indeks korunur.
      durum <- .kova_dizin_durumu(dir)
      if (identical(durum, "belirsiz")) {
        sayim_basarisiz <- TRUE
        next
      }
      dir_ok <- identical(durum, "var")
      if (isTRUE(dir_ok)) {
        # `list.files()` OKUNAMAYAN dizinde de sessizce `character(0)` döndürür;
        # bu boş sonuç "dizin boş" sayıldığında kova indeksi siliniyordu.
        okunabilir <- tryCatch(
          identical(as.integer(file.access(dir, mode = 4L))[1], 0L),
          error = function(e) FALSE
        )
        # ÖZYİNELEMELİ listeleme: `recursive = FALSE` yalnızca kök dosyaları
        # görüyordu. Alt dizin içeren bir kovada alt dosyalar hiç silinmiyor,
        # `silinemeyen` boş kaldığı için indeks kaydı düşüyor ve fonksiyon
        # `TRUE` dönerken dosyalar diskte KAYITSIZ kalıyordu. Gizli dosyalar da
        # sayılır; aksi hâlde nokta ile başlayan girdiler geride kalırdı.
        files <- tryCatch(
          list.files(
            dir, full.names = TRUE, recursive = TRUE,
            all.files = TRUE, include.dirs = FALSE
          ),
          error = function(e) {
            okunabilir <<- FALSE
            character(0)
          }
        )
        if (!isTRUE(okunabilir)) {
          sayim_basarisiz <- TRUE
          next
        }
        for (f in files) {
          # BAĞLANTI KAÇIŞI ENGELİ (CWE-59). `list.files(recursive = TRUE)`
          # dizin sembolik bağlantılarını/junction'larını İZLER ve `unlink()`
          # hedefi siler. Bilge Yolaç kullanıcının seçtiği yükleme klasöründe
          # kabuk komutu çalıştırabildiği için kullanıcı kovaya bir dizin
          # bağlantısı koyup kova DIŞINDAKİ dosyaları sildirebiliyordu. Yol
          # ÇÖZÜLDÜKTEN sonra kovanın içinde kalmıyorsa DOKUNULMAZ.
          if (!.kova_icinde_mi(f, dir)) {
            silinemeyen <- c(silinemeyen, .kova_yol_anahtari(f))
            try(
              log_warn(
                "[INDEX] Kova dışına çözülen yol silinmedi (bağlantı kaçışı): {f}"
              ),
              silent = TRUE
            )
            next
          }
          # `unlink()` hata FIRLATMAZ; Windows kilidi/izin hatasında sıfırdan
          # farklı döner. Dönüş yok sayıldığında indeks kovası tamamen
          # siliniyor, dosya diskte kalıyor ve dosya sistemi fallback'i onu
          # yeniden sunabiliyordu.
          # Yerel ad `durum` DEĞİLDİR: dış döngüde `durum` üç durumlu dizin
          # kararını taşır ve burada ezilmesi ileride sessiz hata üretir.
          silme_durumu <- tryCatch(unlink(f, force = TRUE), error = function(e) 1L)
          hala_var <- tryCatch(file.exists(f), error = function(e) TRUE)
          if (!identical(as.integer(silme_durumu)[1], 0L) || isTRUE(hala_var)) {
            silinemeyen <- c(silinemeyen, .kova_yol_anahtari(f))
          } else {
            silinen <- c(silinen, .kova_yol_anahtari(f))
          }
          # Uzun/yavaş UNC kovasında silme 60 sn'yi aşabilir; marker tazelenmezse
          # CANLI kilit bayat sayılıp başka bir yazar kritik bölüme girebiliyordu.
          # SONUÇ DENETLENİR: sahiplik kaybedildiyse silmeye devam edip sonunda
          # `.save_index()` çağırmak, kilidi devralan yazarın güncellemesini
          # eziyordu (lost update). Silme DURDURULUR; o ana kadar silinen yollar
          # yeniden alınan kilit altında indeksle uzlaştırılır.
          if (exists("file_store_index_lock_heartbeat", mode = "function", inherits = TRUE)) {
            if (!isTRUE(file_store_index_lock_heartbeat())) {
              # Döngü `temizle()` gövdesindedir; `<<-` yerel çerçeveyi ATLAR ve
              # aşağıdaki `break`/başarısızlık dalını ölü koda çevirir.
              sahiplik_kaybi <- TRUE
              break
            }
          }
        }
      }
      if (isTRUE(sahiplik_kaybi)) break
    }

    if (isTRUE(sahiplik_kaybi)) {
      # Kilit artık bizim değil. Uzlaştırma BURADA YAPILAMAZ: bu gövde zaten
      # `.file_store_with_index_lock(temizle(), require_lock = TRUE)` içinde
      # çalışır ve dizin tabanlı kilit YENİDEN GİRİŞLİ DEĞİLDİR; iç içe
      # `dir.create()` her turda başarısız olur, marker taze olduğu için bayat
      # kırma devreye girmez ve `require_lock = TRUE` zaman aşımından sonra
      # hata fırlatır (uzlaştırma ölü kod olurdu, üstelik Shiny olay döngüsü
      # bir saniye boş yere bloklanırdı). Silinen yollar ÇAĞIRANA döndürülür;
      # uzlaştırma dış kilit BIRAKILDIKTAN sonra yapılır.
      warning(
        "mergen_clear_user_bucket: indeks kilidi sahipliği kaybedildi; temizlik durduruldu.",
        call. = FALSE
      )
      return(list(ok = FALSE, silinen = silinen, sahiplik_kaybi = TRUE))
    }

    if (isTRUE(sayim_basarisiz)) {
      # Bu dizinden ÖNCE silinen dosyalar artık diskte yoktur; kayıtları
      # bırakmak indekste var olmayan dosya gösterirdi. Okunamayan dizinin
      # kayıtları KORUNUR.
      .kova_silinenleri_ayikla(uid, silinen, .kova_yol_anahtari)
      warning(
        "mergen_clear_user_bucket: kullanıcı klasörü listelenemedi; indeks kaydı korundu.",
        call. = FALSE
      )
      return(list(ok = FALSE, silinen = silinen, sahiplik_kaybi = FALSE))
    }

    idx <- .load_index()
    if (!is.null(idx[[uid]])) {
      kova <- idx[[uid]]
      if (length(silinemeyen)) {
        # Silinemeyen dosyaların indeks kaydı KORUNUR; aksi hâlde diskte kalan
        # dosya kayıtsız yetim olur.
        tut <- vapply(
          kova,
          function(e) {
            # Eski ATOMİK indeks kayıtları düz karakter yol taşır; `e$path`
            # böyle bir girdide hata fırlatıp `.save_index()` öncesinde
            # temizliği yarıda kesiyordu.
            yol <- if (is.list(e)) e$path else as.character(e %||% "")[1]
            anahtar <- .kova_yol_anahtari(yol)
            # Silinemeyen dosya KORUNUR; diskten SİLİNEN dosyanın kaydı DÜŞER.
            # Eski koşul yalnızca `silinemeyen` ile eşleşmeye bakıyordu: hiç
            # eşleşme olmadığında kova tümüyle korunuyor ve BAŞARIYLA SİLİNEN
            # dosyaların kayıtları da indekste kalıyordu (indeks diskte olmayan
            # dosyayı listeliyordu). Eşleşmeyen kayıtlar (gösterim farkı)
            # yine KORUNUR.
            anahtar %in% silinemeyen || !(anahtar %in% silinen)
          },
          logical(1)
        )
        # HİÇBİR kayıt eşleşmezse kova KORUNUR: 8.3 kısa ad, UNC ya da UTF-8
        # gösterim farkı yüzünden eşleşme kaçabilir ve diskte KALAN dosyanın
        # indeks kaydını silmek onu kayıtsız yetim bırakırdı. `any(tut)` bu iki
        # durumu AYIRT ETMEZ: TÜM kayıtlar `silinen` ile eşleştiğinde de FALSE
        # olur ve diskten silinmiş dosyalar indekste kalıyordu. Ayrım, kaydın
        # HERHANGİ bir anahtarla eşleşip eşleşmediğine bakılarak yapılır.
        eslesen <- vapply(
          kova,
          function(e) {
            yol <- if (is.list(e)) e$path else as.character(e %||% "")[1]
            anahtar <- .kova_yol_anahtari(yol)
            anahtar %in% silinemeyen || anahtar %in% silinen
          },
          logical(1)
        )
        if (any(eslesen)) {
          idx[[uid]] <- if (any(tut)) kova[tut] else NULL
        }
      } else {
        # `list.files(recursive = TRUE)` OKUNAMAYAN bir ALT dizini SESSİZCE
        # atlar; üst dizin denetimi bunu yakalamaz. Kovayı koşulsuz düşürmek,
        # diskte KALAN dosyaları kayıtsız yetim bırakıyor ve fonksiyon yine de
        # `TRUE` dönüyordu. Diskte hâlâ var olan kayıtlar KORUNUR.
        kalan <- vapply(
          kova,
          function(e) {
            yol <- if (is.list(e)) e$path else as.character(e %||% "")[1]
            if (!nzchar(yol)) return(FALSE)
            isTRUE(tryCatch(path_exists_relaxed(yol), error = function(err) FALSE))
          },
          logical(1)
        )
        if (any(kalan)) {
          idx[[uid]] <- kova[kalan]
          kalan_kayit <- TRUE
        } else {
          idx[[uid]] <- NULL
        }
      }
      .save_index(idx)
    }

    if (isTRUE(kalan_kayit)) {
      warning(sprintf(
        "mergen_clear_user_bucket: %d dosya diskte kaldı; indeks kayıtları korundu.",
        sum(kalan)
      ), call. = FALSE)
      return(list(ok = FALSE, silinen = silinen, sahiplik_kaybi = FALSE))
    }

    if (length(silinemeyen)) {
      warning(sprintf(
        "mergen_clear_user_bucket: %d dosya silinemedi; indeks kayıtları korundu.",
        length(silinemeyen)
      ), call. = FALSE)
      return(list(ok = FALSE, silinen = silinen, sahiplik_kaybi = FALSE))
    }

    list(ok = TRUE, silinen = silinen, sahiplik_kaybi = FALSE)
  }

  # KİLİTSİZ TEMİZLİK YOK: kilit alınamazsa eşzamanlı bir kayıt indekse var
  # olmayan dosya yazabiliyor ve `.load_index()`/`.save_index()` çifti kilit
  # dışında kaldığı için yeni girdiyi eziyordu. Hata çağırana bildirilir.
  sonuc <- if (exists(".file_store_with_index_lock", mode = "function", inherits = TRUE)) {
    .file_store_with_index_lock(temizle(), require_lock = TRUE)
  } else {
    temizle()
  }

  # Uzlaştırma dış kilit BIRAKILDIKTAN sonra, YENİDEN alınan kilit altında
  # yapılır. İç içe edinim denemesi kilit yeniden girişli olmadığı için her
  # zaman düşüyordu ve sözleşmedeki "silinen yollar uzlaştırılır" adımı hiç
  # çalışmıyordu.
  if (is.list(sonuc) && isTRUE(sonuc$sahiplik_kaybi)) {
    .kova_silinenleri_kilitle_ayikla(uid, sonuc$silinen, .kova_yol_anahtari)
  }

  invisible(is.list(sonuc) && isTRUE(sonuc$ok))
}
