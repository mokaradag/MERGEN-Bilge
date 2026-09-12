# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_runtime_lease.R
# Açıklama: Bilge Yolaç aktif çalışma "lease" dosyasının yaşam döngüsü:
#           bırakma (idempotent temizlik) ve heartbeat (uzun süren
#           çalıştırmalarda çalışma alanının yetim sayılıp silinmesini önler).
#           R/helpers_claude_code_run_lifecycle.R dosyasından AYRILDI; o dosya
#           küresel 24 fonksiyon tavanındaydı ve bakım oranı bütçesini
#           tüketiyordu. Manifestte run_lifecycle'dan ÖNCE yüklenir.
# ==============================================================================

# Kilit dizinleri runtime adaylarının KARDEŞİ olan bu klasörde tutulur; temizlik
# döngüsü bu adı aday listesinden çıkarır.
CC_RUNTIME_LOCK_DIR_NAME <- ".cc-locks"

#' Bir çalışma alanının aktif çalışma lease dosyasını bırak
#'
#' Terminal yolların aynı idempotent temizliği paylaşmasını sağlar. Boş veya
#' daha önce kaldırılmış lease yolları başarıyla bırakılmış kabul edilir.
cc_release_runtime_lease <- function(runtime_lease = NULL) {
  lease <- try(as.character(runtime_lease %||% "")[1], silent = TRUE)
  if (inherits(lease, "try-error") || is.na(lease) || !nzchar(lease)) {
    return(invisible(FALSE))
  }

  silindi <- try(unlink(lease, force = TRUE), silent = TRUE)
  if (inherits(silindi, "try-error")) return(invisible(FALSE))

  invisible(!isTRUE(file.exists(lease)))
}

#' Aktif çalışma lease dosyasının mtime değerini tazele (heartbeat)
#'
#' Uzun süren bir CLI çalıştırmasında lease hiç tazelenmezse temizlik yolu onu
#' yetim sayıp aktif çalışma alanını silebiliyordu.
#'
#' `Sys.setFileTime()` bazı UNC/ağ paylaşımlarında sessizce BAŞARISIZ olur ve
#' poll döngüsü dönüş değerini denetlemiyordu; lease mtime'ı yetim eşiğini aşınca
#' AKTİF çalışma alanı silinebiliyordu. Başarısızlıkta dosya YENİDEN YAZILIR
#' (yazma mtime'ı yan etki olarak günceller); o da başarısızsa uyarı yazılır.
cc_touch_runtime_lease <- function(runtime_lease = NULL) {
  lease <- try(as.character(runtime_lease %||% "")[1], silent = TRUE)
  if (inherits(lease, "try-error") || is.na(lease) || !nzchar(lease) ||
      !isTRUE(file.exists(lease))) {
    return(invisible(FALSE))
  }

  sonuc <- try(Sys.setFileTime(lease, Sys.time()), silent = TRUE)
  if (!inherits(sonuc, "try-error") && isTRUE(sonuc)) return(invisible(TRUE))

  yazildi <- try(
    writeLines(format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3"), lease, useBytes = TRUE),
    silent = TRUE
  )
  if (inherits(yazildi, "try-error")) {
    if (exists("cc_log_warn", mode = "function", inherits = TRUE)) {
      try(cc_log_warn(paste("[RUNTIME_LEASE] heartbeat yazılamadı:", basename(lease))),
          silent = TRUE)
    }
    return(invisible(FALSE))
  }

  invisible(TRUE)
}

#' Bir runtime çalışma alanının temizlik/lease kilidi dizini
#'
#' Kilit, çalışma alanının KENDİSİNİN dışında (`.cc-locks` kardeş klasöründe)
#' tutulur: aday dizinin silinmesi kilidi de yok etmemelidir.
cc_runtime_cleanup_lock_dir <- function(runtime_dir) {
  yol <- as.character(runtime_dir %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) return("")
  file.path(dirname(yol), CC_RUNTIME_LOCK_DIR_NAME, paste0(basename(yol), ".lock"))
}

#' Temizlik/lease kritik bölümünü TEK kilit altında çalıştır
#'
#' Lease denetimi ile `unlink()` AYRI adımlar olduğunda yeni bir çalıştırma
#' aralıkta lease oluşturabiliyor ve AKTİF çalışma alanı siliniyordu (TOCTOU).
#' Lease EDİNİMİ de aynı kilidi kullanır; kilit alınamazsa ifade ÇALIŞTIRILMAZ
#' ve `fallback` döner (yıkıcı işlem HİÇ denenmez).
cc_with_runtime_cleanup_lock <- function(runtime_dir, expr, fallback = NULL,
                                         attempts = 40L) {
  lock_dir <- cc_runtime_cleanup_lock_dir(runtime_dir)
  if (!nzchar(lock_dir)) return(fallback)

  # Kilit primitifleri yüklenmemişse (izole test/worker bağlamı) davranış
  # bugünküyle aynı kalır: ifade kilitsiz çalışır.
  if (!exists(".cc_codex_acquire_dir_lock", mode = "function", inherits = TRUE) ||
      !exists(".cc_codex_reap_dir_lock", mode = "function", inherits = TRUE)) {
    return(force(expr))
  }

  dir.create(dirname(lock_dir), recursive = TRUE, showWarnings = FALSE)
  jeton <- try(.cc_codex_acquire_dir_lock(lock_dir, attempts = attempts), silent = TRUE)
  if (inherits(jeton, "try-error") || !nzchar(as.character(jeton)[1])) return(fallback)

  on.exit(try(.cc_codex_reap_dir_lock(lock_dir, jeton), silent = TRUE), add = TRUE)
  force(expr)
}

#' Yetim kalmış runtime çalışma alanlarını AÇIK bir kurtarma adımıyla geri kazan
#'
#' Rutin temizlik (`cc_cleanup_stale_runtime_dirs`) lease taşıyan bir çalışma
#' alanını ASLA silmez. Çöken bir süreçten kalan lease diski kalıcı olarak
#' doldurmasın diye geri kazanım bu AYRI işlemde yapılır ve tüm tutucuların
#' bıraktığı DOĞRULANIR: hem her lease dosyası hem de çalışma alanının KENDİSİ
#' yetim eşiğinden eski olmalıdır (eşik, kilit altında yeniden okunur).
#'
#' @param user_id Kullanıcı kimliği
#' @param keep_paths Korunacak çalışma alanı yolları
#' @return Geri kazanılan çalışma alanı sayısı
cc_reclaim_orphaned_runtime_dirs <- function(user_id = NULL,
                                             keep_paths = character(0)) {
  kullanici_dizin <- cc_runtime_user_dir(user_id)
  if (!dir.exists(kullanici_dizin)) return(invisible(0L))

  esik <- suppressWarnings(as.numeric(
    cc_runtime_limit("runtime_lease_orphan_sec", 86400)
  )[1])
  # Eşik SONLU değilse geri kazanım YAPILMAZ (operatör kapatmış demektir).
  if (length(esik) != 1L || !is.finite(esik) || esik <= 0) return(invisible(0L))

  adaylar <- tryCatch(
    list.dirs(kullanici_dizin, full.names = TRUE, recursive = FALSE),
    error = function(e) character(0)
  )
  if (!length(adaylar)) return(invisible(0L))

  koru <- .cc_scan_key(vapply(
    as.character(keep_paths %||% character(0)),
    .cc_scan_norm,
    character(1),
    USE.NAMES = FALSE
  ))

  kilit_klasoru <- if (exists("CC_RUNTIME_LOCK_DIR_NAME", inherits = TRUE)) {
    CC_RUNTIME_LOCK_DIR_NAME
  } else {
    ".cc-locks"
  }

  simdi <- Sys.time()
  geri_kazanilan <- 0L

  for (aday in adaylar) {
    if (identical(basename(aday), kilit_klasoru)) next
    if (.cc_scan_key(.cc_scan_norm(aday)) %in% koru) next

    ok <- cc_with_runtime_cleanup_lock(aday, fallback = FALSE, {
      leases <- tryCatch(
        list.files(
          file.path(aday, "metadata"), pattern = "^active-run-.*\\.lease$", recursive = FALSE,
          full.names = TRUE, include.dirs = FALSE
        ),
        error = function(e) character(0)
      )

      if (!length(leases)) {
        FALSE
      } else {
        lease_mtime <- tryCatch(file.info(leases)$mtime, error = function(e) rep(NA, length(leases)))
        lease_yas <- as.numeric(difftime(simdi, lease_mtime, units = "secs"))
        dizin_mtime <- tryCatch(file.info(aday)$mtime[1], error = function(e) NA)
        dizin_yas <- as.numeric(difftime(simdi, dizin_mtime, units = "secs"))

        # Metaveri okunamıyorsa (UNC kesintisi) geri kazanım YAPILMAZ.
        if (anyNA(lease_yas) || is.na(dizin_yas) || !is.finite(dizin_yas)) {
          try(log_warn(paste(
            CLAUDE_CODE_LOG_PREFIX,
            "Yetim runtime geri kazanımı atlandı (metaveri okunamadı):", basename(aday)
          )), silent = TRUE)
          FALSE
        } else if (any(lease_yas < esik) || dizin_yas < esik) {
          FALSE
        } else {
          try(log_warn(paste(
            CLAUDE_CODE_LOG_PREFIX,
            "Yetim runtime çalışma alanı geri kazanıldı:", basename(aday)
          )), silent = TRUE)
          isTRUE(tryCatch({
            unlink(aday, recursive = TRUE, force = TRUE)
            TRUE
          }, error = function(e) FALSE))
        }
      }
    })

    if (isTRUE(ok)) geri_kazanilan <- geri_kazanilan + 1L
  }

  invisible(geri_kazanilan)
}
