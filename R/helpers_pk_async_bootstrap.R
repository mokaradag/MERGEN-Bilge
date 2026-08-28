# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_bootstrap.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ BOOTSTRAP sözleşmesi, oturum vekili ve işçiye
#           taşınacak globals paketi.
#
# Bu dosya `R/helpers_pk_async_request.R` içinden BÖLÜNMÜŞTÜR: tek dosya bakım
# ratchet'inin 25-fonksiyon tavanını tüketiyordu. Ayrım aynı zamanda daha iyi
# bir sınır: "işçiyi nasıl ayağa kaldırırım" ile "işçiye ne veri gider" farklı
# sorumluluklardır.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca dosya sistemi (bootstrap
# kaynak yükleme) ve düz veri işler.
# ==============================================================================


# İşçinin çalıştırmak için ihtiyaç duyduğu manifest BÖLÜMLERİ. Dosya listesi
# değil BÖLÜM listesi donmuştur: böylece bir bölüme yeni yardımcı eklendiğinde
# işçi otomatik olarak onu da alır (sürüklenme yok), ama işçinin GÖREBİLECEĞİ
# yüzey açıkça gözden geçirilebilir kalır.
#
# UI/modül/gözlemci bölümleri BİLİNÇLİ OLARAK DIŞARIDADIR: işçide Shiny yoktur.
# Tek istisna, aşağıdaki dosya-listesi kurucusunda açıkça eklenen gerçek PK giriş
# dosyasıdır (`module_proje_kaynak_analizi.R`). Böylece bütün module_analysis
# bölümünü worker yüzeyine açmadan `pk_analiz_process_request()` yüklenir.
pk_async_worker_manifest_sections <- function() {
  c(
    "foundation",
    "post_future_utils",
    "config_app_core",
    "config_api_model_keys",
    "database",
    "pk_query_metadata",
    "sql_library",
    "language_messaging",
    "analysis_helpers",
    "llm_pipeline"
  )
}

#' İşçi bootstrap dosya listesi (ana süreçte, manifestten türetilir)
#'
#' @param sections Bölüm adları (varsayılan: donmuş liste).
#' @param manifest `source_manifest_sections` (test için enjekte edilebilir).
#' @return Repo köküne göreli dosya yolları; sıra manifest sırasıdır
#'   (BAĞIMLILIK SIRASI KORUNUR).
pk_async_worker_bootstrap_files <- function(sections = NULL, manifest = NULL) {
  varsayilan <- is.null(sections)
  bolumler <- if (varsayilan) pk_async_worker_manifest_sections() else as.character(sections)

  if (is.null(manifest)) {
    if (!exists("source_manifest_sections", inherits = TRUE)) return(character(0))
    manifest <- get("source_manifest_sections", inherits = TRUE)
  }
  if (!is.list(manifest)) return(character(0))

  yollar <- character(0)
  for (bolum in bolumler) {
    dosyalar <- manifest[[bolum]]
    if (is.null(dosyalar)) next
    yollar <- c(yollar, as.character(dosyalar))
  }

  # Worker'ın gerçek giriş noktası runtime manifestinde module_analysis içinde
  # yaşar. Bölümün tamamını izinli bölüm listesine katmak yerine yalnızca bu
  # sahip dosya, varsayılan worker yüzeyinde explicit olarak eklenir.
  if (isTRUE(varsayilan)) {
    giris <- as.character(manifest[["module_analysis"]] %||% character(0))
    giris <- giris[basename(giris) == "module_proje_kaynak_analizi.R"]
    yollar <- c(yollar, giris)
    # Ana süreçte `server_*` katmanının kurduğu PK gözlemci sarmalayıcıları
    # işçide de gereklidir; aksi hâlde asenkron istekler yalnızca bayrak açık
    # diye doğrudan-çıkış telemetrisini ve v2 derin gözlemci kapsamını kaybeder.
    # Shiny wiring İŞÇİYE GİRMEZ: sarmalayıcılar bu tek amaçlı dosyalardadır.
    # SIRA ZORUNLU: doğrudan-çıkış sarmalayıcısı, gözlemci dosyasında tanımlı
    # `.pk_worker_is_wrapped()` yardımcısını kullanır.
    yollar <- c(yollar, "R/helpers_pk_worker_observers.R",
                "R/helpers_pk_worker_direct_exit.R")
  }

  # Manifest sırası korunur; yalnızca yinelenenler (bölümler arası) tekilleşir.
  unique(yollar)
}

# İşçide BULUNMASI ZORUNLU dosyalar. Diğer manifest girdilerinin yokluğu
# (ör. VM'e özel opsiyonel metadata) NORMALDİR; ama bu dosyalar eksikken
# bootstrap "başarılı" raporlarsa, derin bir istek sessizce standart boru
# hattına düşer ve kullanıcı hiç istemediği bir analizi alır.
pk_async_worker_required_files <- function() {
  c(
    "R/module_proje_kaynak_analizi.R",
    "R/helpers_deep_analysis.R",
    "R/helpers_pk_sql_execute.R",
    # Sınırlı SQL KÖPRÜSÜ de zorunludur: `pk_async_run_analysis()` bunu
    # `pk_async_worker_ready()` denetiminden HEMEN SONRA çağırır. Kısmi bir
    # dağıtımda dosya yoksa bootstrap "hazır" derdi, işçi boru hattı
    # `tryCatch`'inin DIŞINDA hata verirdi ve ana süreç bunu altyapı reddi
    # sayıp SENKRON analize düşerdi — yani tam da bu rollout'un engellemek
    # istediği olay-döngüsü bloklaması geri gelirdi.
    "R/helpers_pk_async_worker_sql.R",
    "R/helpers_pk_analysis_security_summary.R",
    # PK GÖZLEMCİ SARMALAYICILARI DA ZORUNLUDUR.
    #
    # `pk_async_worker_bootstrap_files()` bunları varsayılan yüzeye EKLER, ama
    # zorunlu kümede olmadıkları için eksik bir dağıtımda kaynak döngüsü onları
    # atlıyor ve bootstrap "başarılı" raporluyordu: doğrudan-çıkış telemetrisi
    # ve v2 derin gözlemci kapsamı işçide SESSİZCE kayboluyordu.
    "R/helpers_pk_worker_observers.R",
    "R/helpers_pk_worker_direct_exit.R"
  )
}

# İşçi bootstrap'ının SÜREÇ BAŞINA bir kez çalıştığını işaretleyen yuva adı.
# İşçinin global ortamında tutulur; ana süreçte de aynı ad kullanılır ama ana
# süreç zaten yüklü olduğu için bootstrap NO-OP'tur.
.PK_ASYNC_BOOTSTRAP_FLAG <- ".mergen_pk_async_bootstrapped"

# Havuz HAZIRLIĞI kaynak yüklemesinden AYRI izlenir. `.pk_async_worker_db_pool_init()`
# ölümcül olmayan bir hatayı yutabilir; parmak izi değişmediği için sonraki her
# istek önbellekli yoldan dönerse geçici bir başlangıç hatası havuzu O İŞÇİNİN
# ÖMRÜ BOYUNCA devre dışı bırakırdı.
.PK_ASYNC_POOL_READY_FLAG <- ".mergen_pk_async_pool_ready"

#' İşçi tarafında gerekli yardımcıları SÜREÇ BAŞINA BİR KEZ yükle
#'
#' PSOCK işçilerinde uygulama kaynak yüklü DEĞİLDİR; explicit-mode future
#' yalnızca verilen globals'ı taşır. Yüzlerce fonksiyonu tek tek saymak
#' sürüklenmeye açıktır; bunun yerine işçi, DONMUŞ bölüm listesindeki dosyaları
#' kendi global ortamına yükler. `R/helpers_mcp_bootstrap.R` ile aynı desen.
#'
#' @param repo_root Repo kökü (ana süreçten taşınır; `getwd()` VARSAYILMAZ).
#' @param files Repo köküne göreli dosya yolları.
#' @return `list(ok = TRUE/FALSE, loaded = <int>, failed = <chr>, cached = TRUE/FALSE)`.
pk_async_worker_bootstrap <- function(repo_root, files,
                                      required_files = pk_async_worker_required_files(),
                                      stage_gate = NULL,
                                      workers = NULL,
                                      db_pool_options = NULL,
                                      deadline_at = NULL) {
  hedef <- globalenv()

  # BOOTSTRAP DOSYA SİSTEMİ ÇAĞRILARI SINIRLIDIR (PR #703 incelemesi).
  # Askıda bir UNC/NFS yolunda `file.info()`/`readBin()`/`sys.source()` tek
  # başına son tarihi aşabilir; aşamalar arası kapı bunu göremez. Sınır,
  # `pk_async_bounded_fs()` içinde MUTLAK son tarihten türetilir.

  # BOOTSTRAP KENDİSİ SINIRLIDIR. Yalnızca bootstrap ÖNCESİ bir kapı koymak,
  # zaten GERÇEKLEŞMİŞ bir iptali yakalar; `file.info()`/`sys.source()`/havuz
  # kurulumu askıda kalırsa sonraki bir Durdur veya mutlak son tarih bootstrap
  # dönene kadar GÖZLENEMEZDİ. Bu yüzden kapı her dosya arasında yoklanır.
  kapi <- if (is.function(stage_gate)) stage_gate else function() list(halt = FALSE, status = "ok")
  durdur <- function(loaded) {
    durum <- tryCatch(kapi(), error = function(e) list(halt = FALSE))
    if (!isTRUE(durum$halt)) return(NULL)
    list(ok = FALSE, loaded = loaded, failed = "halted", cached = FALSE,
         halted = TRUE, halt_status = as.character(durum$status %||% "cancelled")[1])
  }

  kok <- tryCatch(as.character(repo_root)[1], error = function(e) NA_character_)
  # VARLIK DENETİMİ SINIRLIDIR: askıda bir UNC/NFS bağlamasında çıplak
  # `dir.exists()` iptal/son tarih kapısına HİÇ ulaşmadan işçiyi sabitliyordu.
  if (is.na(kok) || !nzchar(kok) ||
      !pk_async_bounded_path_exists(kok, dir = TRUE, deadline_at = deadline_at)) {
    return(list(ok = FALSE, loaded = 0L, failed = "repo_root", cached = FALSE))
  }

  dosyalar <- as.character(files %||% character(0))
  if (!length(dosyalar)) {
    return(list(ok = FALSE, loaded = 0L, failed = "empty_file_list", cached = FALSE))
  }

  # Havuz seçenekleri (option basamağı) kaynak yüklemeden ÖNCE kurulur: aksi
  # hâlde `is_db_pool_enabled()` işçide her zaman ortam değişkenine düşerdi.
  if (is.list(db_pool_options) && length(db_pool_options) > 0L) {
    try(pk_async_db_pool_option_install(db_pool_options), silent = TRUE)
  }

  erken <- durdur(0L)
  if (!is.null(erken)) return(erken)

  parmak_sonuc <- pk_async_bounded_fs(
    function() pk_async_bootstrap_fingerprint(kok, dosyalar), deadline_at
  )
  if (!isTRUE(parmak_sonuc$ok)) {
    # Parmak izi HESAPLANAMADI: repo yolu askıda/erişilemez. Devam etmek, aynı
    # askıda yolda dosya dosya `sys.source()` denemek olurdu.
    # SEBEP TAŞINIR: "fingerprint_unavailable" tek başına askıda yolu, bütçe
    # tükenmesini ve gerçek bir R hatasını AYIRT ETTİRMEZ; alan teşhisinde
    # operatör yanlış tarafa bakardı.
    neden <- as.character(parmak_sonuc$error %||% NA_character_)[1]
    return(list(ok = FALSE, loaded = 0L,
                failed = c("fingerprint_unavailable",
                           if (!is.na(neden) && nzchar(neden)) neden else NULL),
                cached = FALSE))
  }
  # ÇÖZÜLEMEYEN PARMAK İZİ SESSİZ BİR PERFORMANS ÇÖKÜŞÜ DEĞİL, AÇIK HATADIR.
  #
  # Sınırlı çağrı BAŞARILI dönüp değer skaler DEĞİLSE eski kod `NA` saklıyordu;
  # aşağıdaki `!is.na(parmak)` koşulu bir daha ASLA tutmadığı için o işçi HER
  # istekte tüm bootstrap dosya kümesini yeniden `sys.source()` ediyor ve tüm
  # yükleme süresi her isteğe ekleniyordu. Kusur artık tipli bir bootstrap
  # hatası olarak bildirilir (çağıran senkron yola düşer, sessizce yavaşlamaz).
  parmak <- parmak_sonuc$value
  if (is.null(parmak) || length(parmak) != 1L || is.na(parmak)) {
    return(list(ok = FALSE, loaded = 0L,
                failed = c("fingerprint_unavailable", "non_scalar_fingerprint"),
                cached = FALSE))
  }
  parmak <- as.character(parmak)[1]
  onceki <- get0(.PK_ASYNC_BOOTSTRAP_FLAG, envir = hedef, ifnotfound = NULL)
  if (!is.null(onceki) && identical(as.character(onceki)[1], parmak)) {
    # Kaynaklar TAZE ama havuz hazır DEĞİLSE (ilk denemede geçici bir hata
    # olduysa) yeniden denenir; aksi hâlde havuz o işçide kalıcı olarak ölürdü.
    havuz <- .pk_async_worker_pool_ensure(hedef, workers)
    if (isTRUE(havuz$fatal)) {
      return(list(ok = FALSE, loaded = 0L, failed = "db_pool_fail_fast", cached = TRUE))
    }
    return(list(ok = TRUE, loaded = 0L, failed = character(0), cached = TRUE))
  }

  # `config_sql_loader.R` göreli `sql_file` yollarını `getwd()` üzerinden
  # çözer. Ana süreç `MERGEN_REPO_ROOT` verdiğinde işçinin çalışma dizini
  # BAŞKA BİR YER olabilir; o zaman dosyalar yüklenir ama SQL kütüphanesi
  # bulunamaz. Bootstrap süresince çalışma dizini repo köküne alınır.
  eski_wd <- tryCatch(getwd(), error = function(e) NULL)
  if (!is.null(eski_wd)) {
    # `normalizePath()`/`setwd()` DE BÜTÇEYE TABİDİR (PR #705 incelemesi, P2):
    # takılmış bir UNC/NFS kökünde işçi çağrının İÇİNDE bloke olur, aşama kapısı
    # yukarıda geçildiği için ne Durdur belirteci ne mutlak son tarih görülür ve
    # asenkron şerit askıda kalır. chdir başarısızlığı bootstrap HATASIDIR:
    # uzun ömürlü işçi SQL'i ÖNCEKİ checkout'tan çözerdi.
    cd <- pk_async_bounded_fs(function() {
      if (identical(normalizePath(eski_wd, winslash = "/", mustWork = FALSE),
                    normalizePath(kok, winslash = "/", mustWork = FALSE))) return(FALSE)
      setwd(kok)
      TRUE
    }, deadline_at)
    if (!isTRUE(cd$ok)) {
      return(list(ok = FALSE, loaded = 0L, failed = "repo_root_chdir", cached = FALSE))
    }
    if (isTRUE(cd$value)) on.exit(try(setwd(eski_wd), silent = TRUE), add = TRUE)
  }

  # Kaynak-zamanı yan etkileri (tüm uygulama paket setinin attach edilmesi,
  # günlük log dosyası + sahte "uygulama başladı" başlığı) İŞÇİDE İSTENMEZ.
  eski_mod <- Sys.getenv("MERGEN_PK_WORKER_BOOTSTRAP", unset = NA_character_)
  Sys.setenv(MERGEN_PK_WORKER_BOOTSTRAP = "true")
  on.exit({
    if (is.na(eski_mod)) Sys.unsetenv("MERGEN_PK_WORKER_BOOTSTRAP")
    else Sys.setenv(MERGEN_PK_WORKER_BOOTSTRAP = eski_mod)
  }, add = TRUE)

  zorunlu <- as.character(required_files %||% character(0))
  yuklenen <- 0L
  basarisiz <- character(0)

  # SICAK işçi TEMİZ bir ortama yüklenir: yeni revizyonu doğrudan `globalenv()`
  # üzerine yazmak, KALDIRILMIŞ/YENİDEN ADLANDIRILMIŞ sembolleri geride bırakır
  # ve işçi eski+yeni güvenlik mantığının KARIŞIMINI çalıştırabilirdi. Sahneleme
  # ortamı yalnızca TAMAMI başarılı olduğunda devreye alınır.
  sahne <- pk_async_worker_stage_env(hedef)

  for (goreli in dosyalar) {
    ara <- durdur(yuklenen)
    if (!is.null(ara)) return(ara)

    # SAHNELEME EBEVEYNİ HER DOSYADAN ÖNCE TAZELENİR.
    #
    # `library()` paketi arama yolunun BAŞINA, yani `parent.env(globalenv())`
    # konumuna ekler. Ebeveyni kurulum anında dondurursak, bootstrap sırasında
    # `R/config_packages.R` tarafından attach edilen paketler (logger, DBI, ...)
    # SONRAKİ dosyalara GÖRÜNMEZ olur ve `R/config_logging.R`
    # "could not find function log_threshold" ile düşer; bootstrap 156/159
    # dosyada `bootstrap_failed` döner. Sembol izolasyonu KORUNUR: ebeveyn
    # `parent.env(hedef)`'tir, `hedef`'in KENDİSİ değil; önceki bootstrap'ın
    # `globalenv()` sembolleri hâlâ görünmez.
    if (exists("pk_async_worker_stage_refresh", mode = "function", inherits = TRUE)) {
      pk_async_worker_stage_refresh(sahne, hedef)
    }

    tam <- file.path(kok, goreli)
    # Aynı gerekçeyle SINIRLI (bkz. repo kökü denetimi).
    if (!pk_async_bounded_path_exists(tam, deadline_at = deadline_at)) {
      # Opsiyonel katmanlar (ör. VM'e özel metadata dosyaları) yokluğu NORMALDİR;
      # ama ZORUNLU giriş dosyalarının yokluğu bootstrap başarısızlığıdır.
      #
      # KARŞILAŞTIRMA TAM GÖRELİ YOL ÜZERİNDEDİR: `basename()` eşitliği, zorunlu
      # bir dosyayla AYNI temel ada sahip BAŞKA dizindeki bir manifest girdisini
      # "var" sayıyordu; zorunlu dosya yokken bootstrap başarı raporlardı.
      if (goreli %in% zorunlu) {
        basarisiz <- c(basarisiz, paste0(goreli, " (eksik)"))
      }
      next
    }

    # `toplevel.env = globalenv()` ZORUNLUDUR.
    #
    # `sys.source()` varsayılan olarak `options(topLevelEnvironment = envir)`
    # ayarlar. Sahneleme ortamı ADSIZ bir `new.env()` olduğu için `topenv()`
    # onu döndürür ve `environmentName()` BOŞ dize verir. `logger` (ve
    # `topenv()` ile arayanın ad alanını çözen diğer paketler) bu boş adı ad
    # alanı anahtarı olarak kullanır ve `library(logger)` doğrudan
    # `exists("", envir = namespaces, inherits = FALSE)` -> "invalid first
    # argument" ile PATLAR. Sonuç: `R/config_logging.R` (ve ona bağlı her
    # dosya) TEMİZ bir işçide YÜKLENEMEZ, bootstrap `bootstrap_failed` döner
    # ve `MERGEN_PK_ASYNC=true` her istekte senkron yedeğe düşerdi.
    #
    # Ana süreçte dosyalar `globalenv()` içine yüklendiği için `topenv()`
    # zaten `globalenv()`'tir; bu argüman işçiyi AYNI davranışa hizalar.
    # Sembol izolasyonu KORUNUR: değerler hâlâ `sahne` içine yazılır.
    yukleme <- pk_async_bounded_fs(function() {
      suppressWarnings(suppressMessages(
        sys.source(tam, envir = sahne, keep.source = FALSE,
                   toplevel.env = globalenv())
      ))
      TRUE
    }, deadline_at)

    if (isTRUE(yukleme$ok)) yuklenen <- yuklenen + 1L else basarisiz <- c(basarisiz, goreli)
  }

  eksik_zorunlu <- setdiff(zorunlu, dosyalar)
  if (length(eksik_zorunlu) > 0L) {
    basarisiz <- c(basarisiz, paste0(eksik_zorunlu, " (listede yok)"))
  }

  if (length(basarisiz) > 0L) {
    # Sahneleme ortamı ATILIR: `globalenv()` eski (çalışan) revizyonda kalır.
    return(list(ok = FALSE, loaded = yuklenen, failed = basarisiz, cached = FALSE))
  }

  son <- durdur(yuklenen)
  if (!is.null(son)) return(son)

  # ATOMİK COMMIT: kısmî yazım BOOTSTRAP BAŞARISIZLIĞIDIR. Aksi hâlde eski
  # uygulama yerinde kalırken parmak izi "yeni revizyon" diye işaretlenir ve
  # işçi ESKİ+YENİ KARIŞIMINI çalıştırmaya devam ederdi.
  commit <- pk_async_worker_commit_env(sahne, hedef)
  if (!isTRUE(commit$ok)) {
    # Parmak izi YAZILMAZ: sonraki istek yeniden dener. Bu işçi karışık
    # durumda olabileceği için bootstrap AÇIKÇA başarısız döner.
    try(assign(.PK_ASYNC_BOOTSTRAP_FLAG, NULL, envir = hedef), silent = TRUE)
    return(list(ok = FALSE, loaded = yuklenen,
                failed = c("commit_partial", utils::head(commit$failed, 5L)),
                cached = FALSE))
  }
  assign(.PK_ASYNC_BOOTSTRAP_FLAG, parmak %||% TRUE, envir = hedef)
  # Yeni revizyon devreye alındı: havuz hazırlığı da sıfırlanır (kaynak yeniden
  # yüklendiği için `.mergen_db_pool_state` TAZEDİR ve eski havuz ÖKSÜZDÜR).
  assign(.PK_ASYNC_POOL_READY_FLAG, FALSE, envir = hedef)

  havuz <- .pk_async_worker_pool_ensure(hedef, workers)
  if (isTRUE(havuz$fatal)) {
    return(list(ok = FALSE, loaded = yuklenen, failed = "db_pool_fail_fast", cached = FALSE))
  }
  list(ok = TRUE, loaded = yuklenen, failed = character(0), cached = FALSE)
}

# Havuz kurulumunu SÜREÇ BAŞINA bir kez başarıyla tamamla; başarısızsa sonraki
# istekte YENİDEN DENE (geçici DB hataları havuzu kalıcı olarak öldürmemelidir).
.pk_async_worker_pool_ensure <- function(hedef, workers = NULL) {
  # HAZIR BAYRAĞI ARTIK YAPILANDIRMA PARMAK İZİDİR (PR #703 incelemesi).
  #
  # Eskiden `TRUE` saklanıyordu ve kod parmak izi değişmediği sürece havuz bir
  # daha HİÇ kurulmuyordu: `MERGEN_DB_POOL_ENABLED` true -> false çalışma zamanı
  # geri alması, fail-fast/boyut değişiklikleri ve işçi sayısına bağlı admisyon
  # payı sıcak işçilerde sessizce ESKİ değerlerde kalıyordu.
  parmak <- tryCatch(pk_async_worker_pool_fingerprint(workers),
                     error = function(e) NA_character_)
  hazir <- get0(.PK_ASYNC_POOL_READY_FLAG, envir = hedef, ifnotfound = FALSE)
  if (!is.na(parmak) && identical(as.character(hazir)[1], parmak)) {
    return(list(ok = TRUE, fatal = FALSE))
  }

  sonuc <- tryCatch(.pk_async_worker_db_pool_init(hedef, workers = workers),
                    error = function(e) list(ok = FALSE, enabled = TRUE, fatal = FALSE))
  if (isTRUE(sonuc$ok)) {
    # `%||%` `NA`yı DEĞİŞTİRMEZ: çözülemeyen bir parmak izi bayrağı `NA` yapıyor
    # ve yukarıdaki `!is.na(parmak)` denetimi her istekte başarısız olduğu için
    # havuz kurulumu o işçinin ÖMRÜ BOYUNCA her istekte yeniden çalışıyordu.
    isaret <- if (length(parmak) == 1L && !is.na(parmak) && nzchar(parmak)) parmak else TRUE
    assign(.PK_ASYNC_POOL_READY_FLAG, isaret, envir = hedef)
  }
  sonuc
}

#' İşçinin ihtiyaç duyduğu MİNİMUM giriş noktalarının varlığını doğrula
#'
#' Bootstrap "hata vermedi" ile "boru hattı çalıştırılabilir" AYNI ŞEY DEĞİLDİR.
pk_async_worker_entry_points <- function() {
  c(
    "pk_analiz_process_request",
    # Derin istek işçiye geldiğinde bu giriş noktası YOKSA, standart boru
    # hattına sessizce düşmek kullanıcıya istemediği bir analizi vermek olurdu.
    "pk_deep_analysis_process",
    "pk_sql_execute_bounded",
    # Sınırlı SQL köprüsü: `pk_async_run_analysis()` bu ikisini bootstrap
    # doğrulamasından hemen sonra çağırır. Eksiklerse hata boru hattı
    # `tryCatch`'inin DIŞINDA oluşur ve istek sessizce senkron yola düşerdi.
    "pk_async_sql_status_box",
    "pk_async_bounded_sql_executor",
    "get_connection",
    "release_connection",
    "resolve_pk_analysis_username",
    "pk_sql_readonly_guard",
    "apply_rls_to_data"
  )
}

pk_async_worker_ready <- function(entry_points = NULL) {
  noktalar <- entry_points %||% pk_async_worker_entry_points()
  eksik <- noktalar[!vapply(
    noktalar,
    function(fn) exists(fn, mode = "function", inherits = TRUE),
    logical(1)
  )]
  list(ready = length(eksik) == 0L, missing = eksik)
}

# ------------------------------------------------------------------------------
# İŞÇİ TARAFI OTURUM VEKİLİ
# ------------------------------------------------------------------------------

#' İşçi içinde düz anlık görüntüden oturum vekili kur
#'
#' `userData` bir ORTAMDIR (liste değil): boru hattı yardımcıları oraya yazar
#' (seçim durumu, köken alt bilgisi) ve iş bittiğinde ana süreç bu yazımları
#' geri toplar. Liste kullanılsaydı kopya semantiği yüzünden yazımlar sessizce
#' kaybolurdu.
#'
#' Ortak Oturum köprüsü de aynı deseni kullanır (`list(userData = ...)`).
pk_async_worker_session <- function(request) {
  ud <- new.env(parent = emptyenv())

  anlik <- if (is.list(request$user_session)) request$user_session else list()
  for (alan in names(anlik)) ud[[alan]] <- anlik[[alan]]

  kullanici <- as.character(request$username %||% "")[1]
  if (nzchar(kullanici)) ud$system_username <- kullanici

  # SSO hazırlığı ANA SÜREÇTE doğrulandı; işçi bunu yeniden yapamaz (DB kimliği
  # yok). Vekil bu yüzden hazır olarak işaretlenir ve kullanıcı adı ZORUNLUDUR.
  ud$auth_initialized <- TRUE

  # Kişisel anahtar yalnızca gerçekten kişisel çözüldüyse taşınır; sahiplik
  # işareti de birlikte konur ki ownership denetimi birebir aynı kararı versin.
  anahtar <- as.character(request$api_key %||% "")[1]
  if (nzchar(anahtar) && nzchar(kullanici)) {
    ud$ai_api_key <- anahtar
    ud$ai_api_key_owner <- kullanici
  }

  # Seçim durumu (eksiltili takip sorusu kimliği) taşınır.
  if (is.list(request$select_state) && length(request$select_state) > 0L) {
    ud[["pk_select_state"]] <- request$select_state
  }

  # D11 devralınan varlık bağlamı vekile de kurulur (sanitize edilmiş biçim).
  # ALAN ADI `user_session`'DIR: `user_session_snapshot` kurucunun PARAMETRE
  # adıdır ve istekte BULUNMAZ; yanlış ad okunduğunda devralınan varlık kısıtı
  # işçiye HİÇ kurulmuyordu.
  duz <- tryCatch(.pk_async_plain_user_data(request$user_session),
                  error = function(e) NULL)
  if (is.list(duz) && is.list(duz[["pk_entity_prior_context"]])) {
    ud[["pk_entity_prior_context"]] <- duz[["pk_entity_prior_context"]]
  }

  # Köken alt bilgisi istek kimliğine bağlıdır; vekilde de aynı kimlik olmalı.
  istek <- as.character(request$request_id %||% "")[1]
  if (nzchar(istek)) ud[["pk_provenance_request_id"]] <- istek

  list(userData = ud, token = istek)
}

# İş bittiğinde ana sürece geri taşınacak oturum yazımları.
.PK_ASYNC_HARVEST_SLOTS <- c(
  "pk_select_state",
  "pk_provenance_pending",
  # Asenkron çalıştırmada çözülen varlık bağlamı da ana sürece döner; aksi
  # hâlde bir sonraki eksiltili soru ("peki 2024 için?") o kısıtı göremezdi.
  "pk_entity_prior_context"
)

#' İŞÇİ TARAFINDA üretilmiş dışa aktarım artifact'ini yerelde sil
#'
#' Bir çalıştırma, iptal/son tarih GÖZLENMEDEN önce büyük bir XLSX/CSV dosyası
#' üretmiş olabilir. Sonuç düşürüldüğünde ana sürecin temizleyecek bir yol
#' listesi kalmaz; dosya işçinin kalıcı temp dizininde ÖKSÜZ kalır. Bu yüzden
#' halt yolunda dosya İŞÇİDE silinir.
#'
#' Ana süreçteki `mergen_pk_cleanup_worker_artifact()` ile aynı işi yapar ama
#' işçi bootstrap yüzeyindedir (server katmanı işçiye yüklenmez).
pk_async_discard_worker_artifact <- function(result) {
  if (!is.list(result) || !is.list(result$pk_attachment)) return(invisible(FALSE))
  dosyalar <- result$pk_attachment$files
  if (!is.list(dosyalar) || !length(dosyalar)) return(invisible(FALSE))

  yollar <- vapply(dosyalar, function(x) {
    if (!is.list(x)) return("")
    yol <- tryCatch(as.character(x$path)[1], error = function(e) "")
    if (is.na(yol)) "" else yol
  }, character(1))
  yollar <- yollar[nzchar(yollar)]
  if (!length(yollar)) return(invisible(FALSE))

  for (yol in yollar) try(unlink(yol, force = TRUE), silent = TRUE)
  for (dizin in unique(dirname(yollar))) {
    norm <- gsub("\\\\", "/", dizin)
    if (grepl("(^|/)run_[^/]*$", norm) && dir.exists(dizin) && !length(list.files(dizin))) {
      try(unlink(dizin, recursive = TRUE, force = TRUE), silent = TRUE)
    }
  }
  invisible(TRUE)
}

#' İşçi vekilinden ana sürece taşınacak yazımları topla
#'
#' Toplanan değerler ana süreçte YALNIZCA istek-kimliği koruması geçtikten
#' sonra uygulanır. Bayat bir işçi sonucu daha yeni bir isteğin seçim durumunu
#' veya köken alt bilgisini EZEMEZ.
pk_async_harvest_session <- function(worker_session) {
  if (is.null(worker_session)) return(list())
  ud <- tryCatch(worker_session$userData, error = function(e) NULL)
  if (is.null(ud)) return(list())

  cikti <- list()
  for (yuva in .PK_ASYNC_HARVEST_SLOTS) {
    deger <- tryCatch(ud[[yuva]], error = function(e) NULL)
    if (is.null(deger)) next
    cikti[[yuva]] <- deger
  }

  cikti
}

#' Toplanan oturum yazımlarını ana süreçte uygula
#'
#' @return Uygulanan yuva adları.
pk_async_apply_session_writes <- function(session, writes) {
  if (is.null(session) || !is.list(writes) || length(writes) == 0L) {
    return(invisible(character(0)))
  }

  ud <- tryCatch(session$userData, error = function(e) NULL)
  if (is.null(ud)) return(invisible(character(0)))

  uygulanan <- character(0)
  for (yuva in intersect(names(writes), .PK_ASYNC_HARVEST_SLOTS)) {
    ok <- tryCatch({
      ud[[yuva]] <- writes[[yuva]]
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) uygulanan <- c(uygulanan, yuva)
  }

  invisible(uygulanan)
}
