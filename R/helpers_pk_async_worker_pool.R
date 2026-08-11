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

#' Ana süreçteki DB havuzu seçeneklerinin düz anlık görüntüsü
pk_async_db_pool_option_snapshot <- function() {
  cikti <- list()
  for (ad in .PK_ASYNC_DB_POOL_OPTIONS) {
    deger <- getOption(ad, NULL)
    if (is.null(deger) || length(deger) != 1L) next
    if (is.function(deger) || is.environment(deger) || is.list(deger)) next
    cikti[[ad]] <- deger
  }
  cikti
}

#' Havuz seçeneklerini işçide kur (geri yükleme değerlerini döndürür)
pk_async_db_pool_option_install <- function(snapshot) {
  if (!is.list(snapshot) || length(snapshot) == 0L) return(list())
  gecerli <- snapshot[intersect(names(snapshot), .PK_ASYNC_DB_POOL_OPTIONS)]
  if (length(gecerli) == 0L) return(list())
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
# Bu yüzden işçi havuzu tavanın YALNIZCA KENDİ PAYINI alır. Pay, ana süreç de
# bir havuz tuttuğu için `workers + 1` üzerinden hesaplanır.
#
# DÜRÜSTLÜK NOTU: bu, süreçler arası gerçek bir semafor DEĞİLDİR. Toplam oturum
# sayısı `main_cap + workers * pay` ile SINIRLIDIR ve pay >= 1 olduğundan
# `workers + 1 > cap` yapılandırmasında ilan edilen tavan HÂLÂ aşılabilir; o
# durum AÇIKÇA loglanır ki operatör işçi sayısını DB tavanıyla hizalayabilsin.
pk_async_worker_pool_admission <- function(cap, workers) {
  tavan <- suppressWarnings(as.integer(cap)[1])
  if (length(tavan) != 1L || is.na(tavan) || tavan < 1L) tavan <- 1L

  isci <- suppressWarnings(as.integer(workers)[1])
  if (length(isci) != 1L || is.na(isci) || isci < 1L) isci <- 1L

  # Ana süreç de bir havuz tutar: paylaşan süreç sayısı `isci + 1`.
  pay <- as.integer(max(1L, floor(tavan / (isci + 1L))))
  list(
    cap = tavan,
    workers = isci,
    share = pay,
    # Tavan, paylaşan süreç sayısına BÖLÜNEMİYORSA agregat tavan aşılabilir.
    fits = isTRUE((isci + 1L) <= tavan)
  )
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

  try({
    if (requireNamespace("pool", quietly = TRUE) && inherits(eski, "Pool")) {
      pool::poolClose(eski)
    }
  }, silent = TRUE)
  try(rm("pool", envir = globalenv()), silent = TRUE)
  invisible(TRUE)
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
