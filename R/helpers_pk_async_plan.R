# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_plan.R
# Açıklama: Faz 6 (§5.10) — FUTURE PLANI YETENEK KAPISI.
#
# `MERGEN_PK_ASYNC=true` NİYETİ belirtir; bu dosya YETENEĞİ ölçer: plan gerçekten
# ayrı bir süreçte mi çalışıyor, işçiler YEREL mi, dosya tabanlı iptal jetonu ve
# repo bootstrap anlamlı mı.
#
# `R/helpers_pk_async_request.R` içinden BÖLÜNMÜŞTÜR: orası istek ANLIK
# GÖRÜNTÜSÜ ve globals paketidir ve 24-fonksiyon bakım tavanına dayanmıştı.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ.
# ==============================================================================

# Plan sınıfı TEK BAŞINA yeterli değildir:
#   * `multisession`/`multicore` tek işçiyle KURULDUĞUNDA future sequential'a
#     düşer; iş yine olay döngüsünde çalışır (tam olarak D15 donması).
#   * `multicore` fork tabanlıdır: işçi ana sürecin durumunu (ve `.GlobalEnv$pool`
#     üzerinden CANLI DB havuzunu) devralır. ODBC/Pool tutamaçları fork sonrası
#     paylaşılamaz ve bu Faz 6'nın "bağlantı işçiye geçmez" sınırını ihlal eder.
#   * Uzak `cluster` işçileri ana sürecin dosya sistemini GÖRMEZ: `repo_root`
#     bootstrap'ı ve dosya tabanlı iptal jetonu orada anlamsızdır.
.PK_ASYNC_REJECTED_PLAN_CLASSES <- c(
  "sequential", "uniprocess", "transparent", "multicore"
)

pk_async_plan_capability <- function() {
  if (!requireNamespace("future", quietly = TRUE)) {
    return(list(ok = FALSE, reason = "future_missing"))
  }

  tryCatch({
    strateji <- future::plan("list")[[1]]
    siniflar <- class(strateji)

    carpisan <- intersect(siniflar, .PK_ASYNC_REJECTED_PLAN_CLASSES)
    if (length(carpisan) > 0L) {
      return(list(ok = FALSE, reason = paste0("plan_", carpisan[1])))
    }

    # İŞÇİ SAYISI TEK BAŞINA KARAR VERMEZ ama TEK İŞÇİ AMBİVALANTTIR.
    #
    # `future` sözleşmesi: SIRADAN sayısal `plan(multisession, workers = 1)`
    # BİLİNÇLİ OLARAK ana R oturumunda değerlendirmeye düşer; yalnızca
    # `workers = I(1)` (AsIs) ayrı bir arka plan oturumunu korur. Strateji her
    # iki hâlde de `multisession` SINIFINI taşıdığı için yukarıdaki sınıf
    # denetimi bu farkı GÖREMEZ (PR #703 incelemesi). Sayısal 1 kabul edilirse
    # PK analizi Shiny olay döngüsünde çalışır — tam olarak D15 donması.
    isci_sayisi <- suppressWarnings(as.numeric(
      tryCatch(future::nbrOfWorkers(), error = function(e) NA_real_)
    )[1])
    if (!is.na(isci_sayisi) && is.finite(isci_sayisi) && isci_sayisi < 1) {
      return(list(ok = FALSE, reason = "no_worker_plan"))
    }

    belirtim <- .pk_async_plan_worker_spec(strategy = strateji)
    if (.pk_async_spec_is_plain_single(belirtim)) {
      return(list(ok = FALSE, reason = "single_worker_falls_back"))
    }

    # TEK İŞÇİLİ yapılandırma AsIs işaretiyle geçerlidir; yine de KANIT aranır:
    # işçi PID'i ana sürecin PID'i ise iş olay döngüsünde çalışıyor demektir.
    # Sonda SÜREÇ BAŞINA BİR KEZ çalışır ve yalnızca bu AMBİVALANT durumda
    # (tek işçi) yapılır; 2+ işçili planlarda belirsizlik yoktur.
    if (!is.na(isci_sayisi) && is.finite(isci_sayisi) && isci_sayisi == 1) {
      sonda <- .pk_async_worker_pid_probe()
      if (identical(sonda, FALSE)) {
        return(list(ok = FALSE, reason = "worker_shares_main_process"))
      }
    }

    if ("cluster" %in% siniflar && !isTRUE(.pk_async_cluster_is_local(strateji))) {
      return(list(ok = FALSE, reason = "remote_cluster_plan"))
    }

    list(ok = TRUE, reason = "ok")
  }, error = function(e) list(ok = FALSE, reason = "plan_probe_failed"))
}

# Uzak küme tespiti: düğüm adları yalnızca localhost/127.0.0.1 ise ana süreçle
# aynı dosya sistemi paylaşılır. Ad çözülemezse UZAK varsayılır (kapalı başarısız).
#
# İşçi belirtimi SIRADAN bir `multisession`/`cluster` planında ad-hoc bir
# `workers` bağı olarak DEĞİL, KURULMUŞ stratejinin/backend'in argümanlarında
# taşınır. Yalnızca `environment(strategy)$workers` bakmak standart yerel
# `plan(multisession, workers = 2)` kurulumunu "uzak küme" sanıp PK'yi senkron
# yola zorlardı. Bu yüzden birden çok kaynak sırayla denenir.
.pk_async_plan_worker_spec <- function(strategy) {
  adaylar <- list(
    function() environment(strategy)$workers,
    function() attr(strategy, "workers"),
    # `future` >= 1.20: kurulmuş stratejinin argümanları.
    function() attr(strategy, "init")$workers,
    function() formals(strategy)$workers,
    # Kurulmuş backend (varsa) gerçek düğüm listesini taşır.
    function() attr(strategy, "backend")$workers,
    function() environment(strategy)$backend$workers
  )

  for (aday in adaylar) {
    deger <- tryCatch(aday(), error = function(e) NULL)
    if (is.null(deger) || is.symbol(deger)) next
    if (is.language(deger)) deger <- tryCatch(eval(deger), error = function(e) NULL)
    if (is.null(deger)) next
    return(deger)
  }
  NULL
}

# SIRADAN (AsIs OLMAYAN) tek işçi belirtimi mi?
#
# `I(1)` sınıfı `AsIs` taşır ve future bunu "gerçekten tek bir ARKA PLAN
# oturumu" diye yorumlar. `1` ise ana oturuma düşer. Belirtim ÇÖZÜLEMEZSE
# (NULL) karar verilmez: sonda/diğer denetimler devreye girer.
.pk_async_spec_is_plain_single <- function(spec) {
  if (is.null(spec)) return(FALSE)
  if (inherits(spec, "AsIs")) return(FALSE)
  if (!is.numeric(spec) || length(spec) != 1L) return(FALSE)
  deger <- suppressWarnings(as.numeric(spec)[1])
  !is.na(deger) && deger == 1
}

# İşçi PID sondası (SÜREÇ BAŞINA MEMOIZE)
#
# @return `TRUE` işçi AYRI süreçte, `FALSE` işçi ANA süreçte, `NA` ölçülemedi.
.pk_async_plan_probe_cache <- new.env(parent = emptyenv())

.pk_async_worker_pid_probe <- function(force = FALSE, plan_key = NULL) {
  anahtar <- tryCatch(as.character(plan_key %||% .pk_async_plan_key())[1],
                      error = function(e) "plan")
  if (!isTRUE(force) && !is.null(.pk_async_plan_probe_cache$result) &&
      identical(.pk_async_plan_probe_cache$key, anahtar)) {
    return(.pk_async_plan_probe_cache$result)
  }
  .pk_async_plan_probe_cache$key <- anahtar
  sonuc <- tryCatch({
    f <- future::future(Sys.getpid(), lazy = FALSE, seed = TRUE)
    isci_pid <- future::value(f)
    isci_pid <- suppressWarnings(as.integer(isci_pid)[1])
    if (is.na(isci_pid)) NA else !identical(isci_pid, Sys.getpid())
  }, error = function(e) NA)
  .pk_async_plan_probe_cache$result <- sonuc
  sonuc
}

#' Sonda önbelleğini sıfırla (plan değiştiğinde / testlerde)
pk_async_plan_probe_reset <- function() {
  .pk_async_plan_probe_cache$result <- NULL
  .pk_async_plan_probe_cache$key <- NULL
  invisible(TRUE)
}

# Plan KİMLİĞİ: sonda önbelleği plan değiştiğinde KENDİLİĞİNDEN geçersizleşir.
.pk_async_plan_key <- function() {
  tryCatch({
    strateji <- future::plan("list")[[1]]
    paste(c(class(strateji),
            as.character(suppressWarnings(future::nbrOfWorkers()))),
          collapse = "/")
  }, error = function(e) "plan")
}

.pk_async_cluster_is_local <- function(strategy) {
  dugumler <- .pk_async_plan_worker_spec(strategy)

  adlar <- tryCatch({
    if (is.character(dugumler)) {
      dugumler
    } else if (is.numeric(dugumler)) {
      # Sayısal işçi belirtimi = YEREL çok oturumlu plan.
      "localhost"
    } else if (is.list(dugumler)) {
      vapply(dugumler, function(n) as.character(n$host %||% "")[1], character(1))
    } else {
      character(0)
    }
  }, error = function(e) character(0))

  adlar <- adlar[!is.na(adlar) & nzchar(adlar)]
  if (!length(adlar)) return(FALSE)
  all(tolower(adlar) %in% c("localhost", "127.0.0.1", "::1"))
}

#' Ana süreçteki future işçi sayısı (agregat DB admisyon payı için)
pk_async_worker_count <- function() {
  if (!requireNamespace("future", quietly = TRUE)) return(1L)
  sayi <- suppressWarnings(as.integer(
    tryCatch(future::nbrOfWorkers(), error = function(e) NA_integer_)
  )[1])
  if (length(sayi) != 1L || is.na(sayi) || sayi < 1L) return(1L)
  sayi
}

pk_async_plan_is_async <- function() {
  isTRUE(pk_async_plan_capability()$ok)
}