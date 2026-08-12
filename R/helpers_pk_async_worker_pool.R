# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_worker_pool.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ TARAFI DB HAVUZU ADMİSYONU.
#
# `R/helpers_pk_async_bootstrap.R` içinden BÖLÜNMÜŞTÜR: orası "işçiyi nasıl
# ayağa kaldırırım" sözleşmesidir ve 24-fonksiyon bakım tavanına dayanmıştı.
# Havuz admisyonu AYRI bir sorumluluktur: "işçi DB'ye kaç oturumla girebilir".
#
# SAFTIR sayılmaz (havuz kurar/kapatır) ama Shiny/reaktif DOKUNMAZ.
# ==============================================================================

# ------------------------------------------------------------------------------
# HAVUZ SEÇENEKLERİNİN İŞÇİYE TAŞINMASI
# ------------------------------------------------------------------------------
# `is_db_pool_enabled()` hem `MERGEN_DB_POOL_ENABLED` ortam değişkenini hem de
# `getOption("mergen.db.pool_enabled")` seçeneğini destekler. TEMİZ bir PSOCK
# işçisi ana sürecin rastgele `options()` değerlerini GÖRMEZ; belgelenmiş R
# seçeneğiyle havuzu açan bir kurulum, Shiny'de havuzlu çalışırken işçide
# doğrudan `dbConnect()` yoluna düşerdi. Bu yüzden havuz seçenekleri isteğin
# yapılandırma anlık görüntüsüyle birlikte AÇIKÇA taşınır.
.PK_ASYNC_DB_POOL_OPTIONS <- c(
  "mergen.db.pool_enabled",
  "mergen.db.pool_fail_fast"
)

# AÇIK "KALDIRILDI" DEĞERİ.
#
# `NULL` değerleri anlık görüntüden DÜŞÜRMEK, bir option'ın SİLİNMESİNİ temsil
# edemez (PR #703 incelemesi): ana süreç `options(mergen.db.pool_enabled = NULL)`
# ile ortam/varsayılana dönerse anlık görüntü o anahtarı hiç taşımaz ve SICAK
# işçi eski değerini SÜRESİZ korurdu — yani çalışma zamanı geri alma işçilerde
# hiç uygulanmazdı. Bu yüzden HER anahtar taşınır; yokluk açık bir sentinel'dir.
.PK_ASYNC_OPTION_UNSET <- "__pk_option_unset__"

#' Ana süreçteki DB havuzu seçeneklerinin düz anlık görüntüsü
#'
#' Anlık görüntü TAMDIR: `.PK_ASYNC_DB_POOL_OPTIONS` içindeki her anahtar ya
#' değeriyle ya da `.PK_ASYNC_OPTION_UNSET` sentinel'iyle yer alır.
pk_async_db_pool_option_snapshot <- function() {
  cikti <- list()
  for (ad in .PK_ASYNC_DB_POOL_OPTIONS) {
    deger <- getOption(ad, NULL)
    tasinabilir <- !is.null(deger) && length(deger) == 1L &&
      !is.function(deger) && !is.environment(deger) && !is.list(deger)
    cikti[[ad]] <- if (tasinabilir) deger else .PK_ASYNC_OPTION_UNSET
  }
  cikti
}

#' Havuz seçeneklerini işçide kur (geri yükleme değerlerini döndürür)
#'
#' Sentinel taşıyan anahtarlar işçide AÇIKÇA `NULL`'a çekilir; böylece sıcak bir
#' işçi ana süreçte SİLİNMİŞ bir option'ı taşımaya devam etmez.
pk_async_db_pool_option_install <- function(snapshot) {
  if (!is.list(snapshot) || length(snapshot) == 0L) return(list())
  gecerli <- snapshot[intersect(names(snapshot), .PK_ASYNC_DB_POOL_OPTIONS)]
  if (length(gecerli) == 0L) return(list())
  gecerli <- lapply(gecerli, function(x) {
    if (identical(x, .PK_ASYNC_OPTION_UNSET)) NULL else x
  })
  # `options()` `NULL` değeri LİSTE ELEMANI olarak alır ve option'ı siler; ancak
  # `do.call` çağrısında `NULL` eleman düşmesin diye liste ADLARI korunur.
  do.call(options, gecerli)
}

# ------------------------------------------------------------------------------
# AGREGAT ADMİSYON PAYI
# ------------------------------------------------------------------------------
# `MERGEN_DB_POOL_MAX_SIZE` her `Pool` nesnesi İÇİNDE uygulanır; PSOCK süreçleri
# ARASINDA değil. Faz 6 eşzamanlı işçi eklediği için, her işçinin kendi havuzuna
# yapılandırılmış TAVANIN TAMAMINI vermek canlı SQL Server oturum sayısını
# `workers * cap` seviyesine çıkarırdı — yani ilan edilen tavan gerçek DEĞİLDİR.
#
# TEK KÜRESEL BÜTÇE, DETERMİNİSTİK BÖLÜŞÜM (PR #703 incelemesi).
#
# Eskiden YALNIZCA işçi havuzları bölünüyordu; ana süreç tavanın TAMAMINI
# koruyordu. `cap = 8`, 3 işçi ile toplam `8 + 3*2 = 14` canlı oturum demekti —
# ilan edilen tavan GERÇEK DEĞİLDİ.
#
# Artık tavan TÜM süreçler (ana + N işçi) arasında bölüştürülür ve toplam
# `main_share + workers * worker_share <= cap` OLMASI garanti edilir. Bu gerçek
# bir süreçler arası semafor değildir, ama BİLDİRİLEN ÜST SINIR artık doğrudur:
# hiçbir süreç kombinasyonu tavanın üstünde fiziksel oturum AÇAMAZ.
#
# `cap < workers + 1` (her sürece 1 oturum bile düşmüyor) yapılandırması TEK
# istisnadır: orada her sürece 1 verilir, `fits = FALSE` döner ve durum AÇIKÇA
# loglanır ki operatör işçi sayısını DB tavanıyla hizalayabilsin.
pk_db_admission_plan <- function(cap, workers) {
  tavan <- suppressWarnings(as.integer(cap)[1])
  if (length(tavan) != 1L || is.na(tavan) || tavan < 1L) tavan <- 1L

  isci <- suppressWarnings(as.integer(workers)[1])
  if (length(isci) != 1L || is.na(isci) || isci < 0L) isci <- 0L

  paylasan <- isci + 1L
  sigar <- isTRUE(paylasan <= tavan)

  isci_payi <- as.integer(max(1L, floor(tavan / paylasan)))
  ana_pay <- if (sigar) as.integer(max(1L, tavan - isci * isci_payi)) else 1L

  list(
    cap = tavan,
    workers = isci,
    share = isci_payi,        # geriye dönük ad (işçi payı)
    worker_share = isci_payi,
    main_share = ana_pay,
    total = as.integer(ana_pay + isci * isci_payi),
    fits = sigar
  )
}

#' Geriye dönük ad: işçi tarafı admisyon payı
pk_async_worker_pool_admission <- function(cap, workers) {
  pk_db_admission_plan(cap, workers)
}

#' BU SÜRECİN havuz tavanı payı
#'
#' `db_pool_config()` bunu çağırır. İşçi tarafında pay ZATEN ortam değişkeniyle
#' daraltılmış olduğundan (`pk_async_worker_pool_apply_share()`) yeniden
#' bölüştürme YAPILMAZ; aksi hâlde pay iki kez küçülürdü.
#'
#' Asenkron KAPALIYKEN (varsayılan geri alma kipi) bölüşüm hiç uygulanmaz:
#' işçi süreci yoktur ve eski davranış bit bazında korunur.
pk_db_pool_process_share <- function(cap) {
  tavan <- suppressWarnings(as.integer(cap)[1])
  if (length(tavan) != 1L || is.na(tavan) || tavan < 1L) return(tavan)

  if (identical(Sys.getenv("MERGEN_DB_POOL_SHARE_APPLIED", unset = ""), "1")) return(tavan)
  if (!exists("pk_async_enabled", mode = "function", inherits = TRUE)) return(tavan)
  if (!isTRUE(tryCatch(pk_async_enabled(NULL), error = function(e) FALSE))) return(tavan)

  isci <- if (exists("pk_async_worker_count", mode = "function", inherits = TRUE)) {
    suppressWarnings(as.integer(tryCatch(pk_async_worker_count(), error = function(e) 0L))[1])
  } else {
    0L
  }
  if (length(isci) != 1L || is.na(isci) || isci < 1L) return(tavan)

  pk_db_admission_plan(tavan, isci)$main_share
}

#' İŞÇİ HAVUZU YAPILANDIRMA PARMAK İZİ
#'
#' Sıcak bir işçide havuz YALNIZCA BİR KEZ kuruluyordu: kod parmak izi
#' değişmediği sürece `MERGEN_DB_POOL_ENABLED` true -> false geçişi, fail-fast
#' veya boyut/admisyon değişiklikleri o işçide HİÇ uygulanmıyordu (PR #703
#' incelemesi). Bu parmak izi, havuzu ETKİLEYEN her girdiyi kapsar; değiştiğinde
#' havuz yeniden kurulur (ve eski nesne emekliye ayrılır).
pk_async_worker_pool_fingerprint <- function(workers = NULL) {
  oku <- function(ad) {
    ham <- Sys.getenv(ad, unset = NA_character_)
    if (is.na(ham)) "<unset>" else as.character(ham)[1]
  }
  secenek <- function(ad) {
    deger <- getOption(ad, NULL)
    if (is.null(deger) || length(deger) != 1L) "<unset>" else as.character(deger)[1]
  }
  isci <- suppressWarnings(as.integer(workers)[1])
  if (length(isci) != 1L || is.na(isci)) isci <- NA_integer_

  paste(c(
    oku("MERGEN_DB_POOL_ENABLED"), oku("MERGEN_DB_POOL_FAIL_FAST"),
    oku("MERGEN_DB_POOL_MAX_SIZE"), oku("MERGEN_DB_POOL_MIN_SIZE"),
    oku("MERGEN_DB_POOL_IDLE_TIMEOUT"),
    secenek("mergen.db.pool_enabled"), secenek("mergen.db.pool_fail_fast"),
    as.character(isci)
  ), collapse = "|")
}

#' İşçi havuzu payını ortam değişkeni olarak uygula (geri yükleyici döndürür)
#'
#' `db_pool_config()` tavanı YALNIZCA ortamdan okur; havuz dosyasını
#' değiştirmeden payı uygulamanın tek yolu bu değişkeni istek süresince
#' geçici olarak daraltmaktır.
pk_async_worker_pool_apply_share <- function(admission) {
  if (!is.list(admission) || is.null(admission$share)) return(function() invisible(FALSE))

  eski <- Sys.getenv("MERGEN_DB_POOL_MAX_SIZE", unset = NA_character_)
  Sys.setenv(MERGEN_DB_POOL_MAX_SIZE = as.character(admission$share))
  # PAY UYGULANDI İŞARETİ: `db_pool_config()` bu süreçte yeniden bölüştürme
  # YAPMAZ (aksi hâlde pay iki kez küçülürdü). İşaret GERİ ALINMAZ çünkü bu bir
  # SÜREÇ ROLÜDÜR ("ben bir PK işçisiyim"), isteğe özgü bir ayar değil.
  Sys.setenv(MERGEN_DB_POOL_SHARE_APPLIED = "1")

  # Minimum boyut paydan büyük kalırsa havuz kurulumu tutarsız olurdu.
  eski_min <- Sys.getenv("MERGEN_DB_POOL_MIN_SIZE", unset = NA_character_)
  min_sayi <- suppressWarnings(as.integer(eski_min))
  if (!is.na(min_sayi) && min_sayi > admission$share) {
    Sys.setenv(MERGEN_DB_POOL_MIN_SIZE = as.character(admission$share))
  }

  function() {
    if (is.na(eski)) Sys.unsetenv("MERGEN_DB_POOL_MAX_SIZE")
    else Sys.setenv(MERGEN_DB_POOL_MAX_SIZE = eski)
    if (is.na(eski_min)) Sys.unsetenv("MERGEN_DB_POOL_MIN_SIZE")
    else Sys.setenv(MERGEN_DB_POOL_MIN_SIZE = eski_min)
    invisible(TRUE)
  }
}

# ------------------------------------------------------------------------------
# ESKİ HAVUZUN EMEKLİYE AYRILMASI
# ------------------------------------------------------------------------------
# Parmak izi değiştiğinde `helpers_db_pool.R` YENİDEN source edilir ve dosya
# başındaki `.mergen_db_pool_state` TAZE bir ortamla değiştirilir. O anda hâlâ
# CANLI olan işçi havuzu artık `st$pools` içinde GÖRÜNMEZ ama `.GlobalEnv$pool`
# nesnesi (ve altındaki SQL oturumları) DURUR. Her kod yenilemesi bu şekilde
# kalıcı bir PSOCK işçisi başına bir havuz ÖKSÜZ bırakır ve sonunda DB
# kapasitesini tüketir. Bu yüzden yeni havuz kurulmadan ÖNCE eski nesne
# açıkça kapatılır.
pk_async_worker_pool_retire <- function(hedef) {
  ortam <- if (is.environment(hedef)) hedef else globalenv()
  eski <- get0("pool", envir = globalenv(), inherits = FALSE)
  if (is.null(eski)) return(invisible(FALSE))

  # Güncel havuz durumu bu nesneyi HÂLÂ tanıyorsa kapatmak yanlış olurdu.
  tanidik <- isTRUE(tryCatch({
    st <- get0(".mergen_db_pool_state", envir = ortam, inherits = TRUE)
    if (!is.environment(st) || !is.list(st$pools)) FALSE
    else any(vapply(st$pools, function(p) identical(p, eski), logical(1)))
  }, error = function(e) FALSE))
  if (isTRUE(tanidik)) return(invisible(FALSE))

  # SINIRLI EMEKLİYE AYIRMA (PR #703 incelemesi).
  #
  # `pool::poolClose()` altındaki fiziksel ODBC bağlantılarını SENKRON kapatır
  # ve bu dosyanın da belgelediği gibi `dbDisconnect()` sürücü içinde bloklayabilir.
  # Bu çağrı BOOTSTRAP sırasında yapılır: sınırsız bırakılırsa bozuk/asılı tek
  # bir bağlantı PSOCK işçisini analiz son tarihinin ve Durdur'un ÖTESİNDE
  # tutabilirdi — üstelik tam da kod yenileme/geri alma yolunda.
  #
  # `setTimeLimit()` iş birliğine dayalıdır ve derlenmiş çağrıyı GARANTİLİ
  # kesemez; bu yüzden ayrıca REFERANS her hâlükârda düşürülür ve başarısız
  # kapatma AÇIKÇA loglanır. "Kapatamadım" demek, süresiz bloklamaktan iyidir.
  kapandi <- .pk_async_pool_close_bounded(eski)
  try(rm("pool", envir = globalenv()), silent = TRUE)
  if (!isTRUE(kapandi)) {
    .pk_async_pool_log(
      "[PK_ASYNC] Eski isci havuzu SINIRLI surede kapatilamadi; referans dusuruldu."
    )
  }
  invisible(TRUE)
}

# Havuzu kalan teardown bütçesiyle kapat (varsayılan taban: 10 sn).
.pk_async_pool_close_bounded <- function(havuz, budget_sec = NULL) {
  if (!requireNamespace("pool", quietly = TRUE) || !inherits(havuz, "Pool")) {
    return(invisible(FALSE))
  }
  butce <- suppressWarnings(as.numeric(budget_sec %||% NA_real_)[1])
  if (length(butce) != 1L || is.na(butce) || !is.finite(butce) || butce <= 0) {
    kalan <- if (exists(".db_pk_teardown_budget_sec", mode = "function", inherits = TRUE)) {
      suppressWarnings(as.numeric(tryCatch(.db_pk_teardown_budget_sec(),
                                           error = function(e) NA_real_))[1])
    } else {
      NA_real_
    }
    butce <- if (is.na(kalan) || !is.finite(kalan)) 10 else max(2, min(10, kalan))
  }

  isTRUE(tryCatch({
    on.exit(try(setTimeLimit(cpu = Inf, elapsed = Inf, transient = TRUE), silent = TRUE),
            add = TRUE)
    setTimeLimit(cpu = Inf, elapsed = max(0.05, butce), transient = TRUE)
    pool::poolClose(havuz)
    TRUE
  }, error = function(e) FALSE))
}

# ------------------------------------------------------------------------------
# İŞÇİ HAVUZUNUN KURULMASI
# ------------------------------------------------------------------------------
#' İşçi tarafında DB havuzunu kur
#'
#' @param hedef Bootstrap hedef ortamı (normalde `globalenv()`).
#' @param workers Ana süreçteki future işçi sayısı (agregat pay için).
#' @return `list(ok = TRUE/FALSE, enabled = TRUE/FALSE, fatal = TRUE/FALSE)`.
#'   `fatal = TRUE` yalnızca `MERGEN_DB_POOL_FAIL_FAST` açıkken ve havuz
#'   kurulamadığında döner; bu durumda bootstrap DÜŞMELİDİR.
.pk_async_worker_db_pool_init <- function(hedef, workers = NULL) {
  etkin <- tryCatch(
    is.function(get0("is_db_pool_enabled", envir = hedef, inherits = TRUE)) &&
      isTRUE(get("is_db_pool_enabled", envir = hedef)()),
    error = function(e) FALSE
  )

  if (!isTRUE(etkin)) {
    # ÇALIŞMA ZAMANI GERİ ALMA: `MERGEN_DB_POOL_ENABLED=true` -> `false` geçişi
    # sıcak işçilerde de etkili OLMALIDIR. Eski `.GlobalEnv$pool` nesnesi
    # bırakılırsa `get_connection()` onu koşulsuz algılar ve havuz kapatılmış
    # olmasına rağmen kullanmaya DEVAM ederdi.
    pk_async_worker_pool_retire(hedef)
    return(list(ok = TRUE, enabled = FALSE, fatal = FALSE))
  }

  baslat <- get0("init_db_pool_once", envir = hedef, inherits = TRUE)
  if (!is.function(baslat)) return(list(ok = FALSE, enabled = TRUE, fatal = FALSE))

  # Yeniden source sonrası ÖKSÜZ kalmış havuz varsa önce o kapatılır.
  pk_async_worker_pool_retire(hedef)

  yapilandirma <- tryCatch(get0("db_pool_config", envir = hedef, inherits = TRUE), error = function(e) NULL)
  cfg <- if (is.function(yapilandirma)) tryCatch(yapilandirma(), error = function(e) NULL) else NULL
  kapali_basarisiz <- isTRUE(tryCatch(cfg$fail_fast, error = function(e) FALSE))

  pay <- pk_async_worker_pool_admission(cfg$max_size %||% 8L, workers)
  geri_yukle <- pk_async_worker_pool_apply_share(pay)
  on.exit(try(geri_yukle(), silent = TRUE), add = TRUE)

  if (!isTRUE(pay$fits)) {
    .pk_async_pool_log(
      "[PK_ASYNC] DB havuz tavani (%d) isci sayisina (%d) BOLUNEMIYOR; agregat oturum sayisi tavani asabilir.",
      pay$cap, pay$workers
    )
  }

  sonuc <- tryCatch({ baslat("primary"); TRUE }, error = function(e) {
    .pk_async_pool_log("[PK_ASYNC] Isci DB havuzu kurulamadi: %s", conditionMessage(e))
    FALSE
  })

  if (isTRUE(sonuc)) return(list(ok = TRUE, enabled = TRUE, fatal = FALSE))

  # `init_db_pool_once()` `MERGEN_DB_POOL_FAIL_FAST=true` iken BİLEREK hata
  # atar. Bu hatayı yutmak, operatör tam da "kapalı başarısız ol" dediğinde
  # işçiyi doğrudan `dbConnect()` yoluna düşürür ve admisyon tavanını atlar.
  list(ok = FALSE, enabled = TRUE, fatal = isTRUE(kapali_basarisiz))
}

.pk_async_pool_log <- function(fmt, ...) {
  metin <- try(sprintf(fmt, ...), silent = TRUE)
  if (!inherits(metin, "try-error")) try(cat(metin, "\n", sep = ""), silent = TRUE)
  invisible(NULL)
}
