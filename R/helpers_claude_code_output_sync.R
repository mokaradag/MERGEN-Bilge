# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_output_sync.R
# Açıklama: Bilge Yolaç izole runtime alanındaki çıktı bölgesinin belirlenmesi,
#           YALNIZCA bu çalıştırmada üretilen/değişen dosyaların kaynak dizine
#           geri aktarım planı ve eskiyen runtime/doküman destek klasörlerinin
#           yaşa göre temizliği.
#
#           Runtime klasörünün tamamı ASLA kaynak dizine geri kopyalanmaz.
#           Bu dosya Shiny/reaktif/DB bağımlılığı içermez ve arka plan
#           worker'ında çalıştırılabilir.
# ==============================================================================

#' Bir kökü karşılaştırma için kanonik forma çevir
#'
#' Windows'ta `tempdir()` ve kullanıcı profili yolları 8.3 KISA ad biçiminde
#' gelebilir (kullanici profili bileseni `KULLAN~1` gibi kisalir).
#' `normalizePath(mustWork = FALSE)`
#' var olmayan yolu olduğu gibi döndürdüğü için, karşılaştırmanın iki tarafı
#' farklı semantikle çözülürse kısa ad ile uzun ad karşılaştırılır ve önek
#' eşleşmesi tutmaz. Var olan yollarda `mustWork = TRUE` kısa adı uzun forma
#' açar; yol yoksa mevcut davranışa düşülür.
#'
#' @param path Kök yolu
#' @return Kanonik, ileri-bölülü kök
cc_output_sync_canonical_root <- function(path) {
  ham <- as.character(path %||% "")[1]
  if (!nzchar(ham)) return("")

  kanonik <- tryCatch(
    normalizePath(ham, winslash = "/", mustWork = TRUE),
    error = function(e) NA_character_
  )

  if (is.na(kanonik) || !nzchar(kanonik)) return(.cc_scan_norm(ham))

  .cc_scan_norm(kanonik)
}

#' Bir yolun runtime düzeninde hangi bölgeye ait olduğunu belirle
#'
#' @param path Kontrol edilecek yol
#' @param layout Runtime düzeni
#' @return "output", "input", "metadata", "document_support", "root" veya ""
cc_runtime_zone_of_path <- function(path, layout) {
  yol <- .cc_scan_norm(as.character(path %||% "")[1])
  if (!nzchar(yol) || !is.list(layout)) return("")

  yol_key <- .cc_scan_key(yol)

  icinde <- function(kok) {
    if (is.null(kok) || !nzchar(kok)) return(FALSE)
    kok_key <- .cc_scan_key(.cc_scan_norm(kok))
    identical(yol_key, kok_key) || startsWith(yol_key, paste0(kok_key, "/"))
  }

  for (bolge in c("output", "input", "metadata", "document_support")) {
    if (icinde(layout[[bolge]])) return(bolge)
  }

  if (icinde(layout$root)) return("root")

  ""
}

#' Yalnızca üretilen/değişen çıktı dosyaları için geri aktarım planı üret
#'
#' Runtime klasörünün tamamı kaynak dizine kopyalanmaz. Yalnızca onaylı
#' çıktı bölgesinde bulunan, bu çalıştırmada oluşmuş veya değişmiş ve
#' boyut sınırlarını aşmayan dosyalar planlanır.
#'
#' @param changed_files Snapshot diff sonucundaki yollar
#' @param layout Runtime düzeni
#' @param source_workdir Hedef kaynak dizin
#' @param limits Sınır listesi
#' @return list(items, skipped, total_bytes)
cc_plan_output_sync <- function(changed_files,
                                layout,
                                source_workdir,
                                limits = NULL) {
  changed_files <- unique(as.character(changed_files %||% character(0)))
  bos <- list(items = list(), skipped = character(0), total_bytes = 0)

  if (!length(changed_files) || !is.list(layout)) return(bos)

  hedef_kok <- .cc_scan_norm(as.character(source_workdir %||% "")[1])
  if (!nzchar(hedef_kok) || !dir.exists(hedef_kok)) return(bos)

  max_file_bytes <- cc_runtime_limit("max_output_file_bytes", 100 * 1024^2, limits)
  max_total_bytes <- cc_runtime_limit("max_output_total_bytes", 400 * 1024^2, limits)

  hedef_kok_key <- .cc_scan_key(hedef_kok)

  ogeler <- list()
  atlananlar <- character(0)
  # Onaylı çıktı bölgesinde olup YALNIZCA boyut sınırı nedeniyle aktarılamayan
  # dosyalar ayrı izlenir: bunlar kullanıcıya sessizce kaybolmamalı, kısmi
  # başarısızlık olarak raporlanır.
  atlanan_onayli <- list()
  toplam <- 0

  for (yol in changed_files) {
    kaynak <- .cc_scan_norm(yol)

    # Bölge kararı yalnızca sözlükseldir; dosya kaybolsa bile hangi alana ait
    # olduğu bilinir. Bu yüzden varlık kontrolünden ÖNCE hesaplanır.
    bolge <- cc_runtime_zone_of_path(kaynak, layout)

    if (!isTRUE(file.exists(kaynak)) || isTRUE(dir.exists(kaynak))) {
      atlananlar <- c(atlananlar, kaynak)

      # Snapshot diff'i bu dosyanın ÜRETİLDİĞİNİ kanıtladı. Aktarımdan önce
      # kaybolması (antivirüs karantinası, geciken araç yeniden adlandırması,
      # ağ paylaşımı görünürlük gecikmesi) sessiz bir kayıptır: çalıştırma ne
      # indirme ne de kaynak kopyası üretmeden "başarılı" görünürdü. Onaylı
      # çıktı alanındaki kayıp dosyalar açık birer başarısızlık olarak
      # raporlanır.
      if (identical(bolge, "output")) {
        atlanan_onayli[[length(atlanan_onayli) + 1L]] <- list(
          source_path = kaynak,
          size = NA_real_,
          reason = if (isTRUE(dir.exists(kaynak))) "output_is_directory" else "missing_output"
        )
      }
      next
    }

    # İzole çalışma alanı sözleşmesi gereği yalnızca onaylı output bölgesi
    # kaynak dizine geri taşınabilir. Kopyalanmış input dosyalarındaki edits ve
    # runtime kökündeki tesadüfi CLI dosyaları kaynak ağacı değiştiremez.
    if (!identical(bolge, "output")) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    boyut <- suppressWarnings(as.numeric(file.info(kaynak)$size[1]))
    if (!is.finite(boyut)) boyut <- 0

    if (boyut > max_file_bytes || toplam + boyut > max_total_bytes) {
      atlananlar <- c(atlananlar, kaynak)
      atlanan_onayli[[length(atlanan_onayli) + 1L]] <- list(
        source_path = kaynak,
        size = boyut,
        reason = if (boyut > max_file_bytes) "max_output_file_bytes" else "max_output_total_bytes"
      )
      next
    }

    zone_root <- layout$output
    rel <- cc_scan_relative_paths(kaynak, zone_root)
    rel <- as.character(rel)[1]

    if (!nzchar(rel) || grepl("(^|/)\\.\\.(/|$)", rel, perl = TRUE) ||
        grepl("^(?:[A-Za-z]:|/)", rel, perl = TRUE)) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    hedef <- .cc_scan_norm(file.path(hedef_kok, rel))
    hedef_key <- .cc_scan_key(hedef)

    if (!startsWith(hedef_key, paste0(hedef_kok_key, "/"))) {
      atlananlar <- c(atlananlar, kaynak)
      next
    }

    ogeler[[length(ogeler) + 1L]] <- list(
      source_path = kaynak,
      dest_path = hedef,
      relative_path = rel,
      size = boyut
    )

    toplam <- toplam + boyut
  }

  list(
    items = ogeler, skipped = unique(atlananlar), total_bytes = toplam,
    skipped_approved = atlanan_onayli,
    source_workdir = hedef_kok
  )
}

#' Onaylı alanda aktarılamayan çıktıları başarısız sonuç yap
#'
#' `cc_plan_output_sync()` bu dosyaları yalnızca `skipped_approved` içinde
#' tutar. Çalıştırma sonucunu değerlendiren taraf yalnızca sonuç listesine
#' baktığı için, bunlar açık birer başarısız kayda dönüştürülür. Kapsam iki
#' nedendir: boyut sınırını aşan çıktılar ve snapshot diff'inin ürettiğini
#' kanıtladığı hâlde aktarımdan önce kaybolan çıktılar.
#'
#' @param plan cc_plan_output_sync() çıktısı
#' @return Başarısız sonuç listesi
cc_output_sync_skipped_results <- function(plan) {
  atlananlar <- if (is.list(plan)) plan$skipped_approved %||% list() else list()
  if (!length(atlananlar)) return(list())

  lapply(atlananlar, function(oge) {
    neden <- as.character(oge$reason %||% "size_limit")[1]

    mesaj <- switch(
      neden,
      missing_output = paste0(
        "Üretilen çıktı aktarımdan önce kayboldu veya erişilemez oldu (",
        neden, ")"
      ),
      output_is_directory = paste0(
        "Üretilen çıktı beklenmedik biçimde dizine dönüştü (", neden, ")"
      ),
      paste0(
        "Çıktı boyut sınırını aştığı için kaynak klasöre aktarılmadı (",
        neden, ")"
      )
    )

    list(
      source_path = oge$source_path %||% "",
      dest_path = oge$source_path %||% "",
      success = FALSE,
      size = oge$size %||% NA_real_,
      error = mesaj
    )
  })
}

#' Geri aktarım planını uygula
#'
#' @param plan cc_plan_output_sync() çıktısı
#' @return Dosya başına yapılandırılmış sonuç listesi
cc_apply_output_sync_plan <- function(plan, active_guard = NULL) {
  # Boyut sınırı nedeniyle aktarılamayan onaylı çıktılar da sonuçlara girer;
  # aksi halde çalıştırma eksik dosyayla "tamamlandı" görünür.
  atlanan_sonuclar <- cc_output_sync_skipped_results(plan)

  if (!is.list(plan) || !length(plan$items %||% list())) {
    return(atlanan_sonuclar)
  }

  sonuclar <- atlanan_sonuclar

  for (oge in plan$items) {
    if (!is.null(active_guard) && nzchar(active_guard) && !file.exists(active_guard)) {
      break
    }
    hedef_dizin <- dirname(oge$dest_path)

    # Existing symlink/junction parents must be resolved before directory
    # creation or copying; a lexical destination prefix check is not enough.
    #
    # Onaylı kök ile çözülmüş ata AYNI çözümleme semantiğiyle hesaplanmalıdır.
    # Aksi halde Windows'ta 8.3 kısa ad (KULLAN~1) ile uzun ad biçimi
    # karşılaştırılır, önek eşleşmesi tutmaz ve
    # geçerli bir çıktı "onaylı kaynak kökün dışında" sayılarak sessizce
    # aktarılmaz. mustWork = TRUE her iki tarafta da kısa adı uzun forma açar.
    approved_root <- cc_output_sync_canonical_root(plan$source_workdir %||% hedef_dizin)
    ancestor <- hedef_dizin
    while (!dir.exists(ancestor) && !identical(dirname(ancestor), ancestor)) {
      ancestor <- dirname(ancestor)
    }
    resolved_ancestor <- tryCatch(
      .cc_scan_norm(normalizePath(ancestor, winslash = "/", mustWork = TRUE)),
      error = function(e) ""
    )
    approved_key <- .cc_scan_key(approved_root)
    ancestor_key <- .cc_scan_key(resolved_ancestor)
    parent_safe <- nzchar(approved_root) && nzchar(resolved_ancestor) && (
      identical(ancestor_key, approved_key) ||
        startsWith(ancestor_key, paste0(approved_key, "/"))
    )
    if (!isTRUE(parent_safe)) {
      sonuclar[[length(sonuclar) + 1L]] <- list(
        source_path = oge$source_path, dest_path = oge$dest_path,
        success = FALSE, size = oge$size,
        error = "Hedef üst dizini onaylı kaynak kökün dışında"
      )
      next
    }

    if (!dir.exists(hedef_dizin)) {
      dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
    }

    hata <- ""

    # Hedef yol, onaylı kökle AYNI çözümleme semantiğiyle kanonik forma
    # çevrilir. Windows'ta tempdir()/kullanıcı profili 8.3 KISA ad (KULLAN~1)
    # biçiminde gelebilir; ham hedef yolunu kanonik onaylı kökle
    # karşılaştırmak önek eşleşmesini bozar ve geçerli bir çıktı sessizce
    # "onaylı kökün dışında" sayılarak hiç aktarılmazdı.
    cozulmus_dizin <- cc_output_sync_canonical_root(hedef_dizin)
    beklenen_hedef <- if (nzchar(cozulmus_dizin)) {
      paste0(cozulmus_dizin, "/", basename(.cc_scan_norm(oge$dest_path)))
    } else {
      .cc_scan_norm(oge$dest_path)
    }

    # file.copy(overwrite = TRUE) var olan hedef bağlantısını izleyebilir ve
    # onaylı kök dışındaki dosyayı ezebilir. Bağlantı tespiti taban ad
    # karşılaştırmasıyla DEĞİL, ortak dizin düzeyli yardımcıyla yapılır;
    # Windows'ta Türkçe taban adlar harf katlaması nedeniyle eşitsiz görünüp
    # geçerli her aktarımı bloke ediyordu.
    hedef_var <- isTRUE(file.exists(oge$dest_path)) || isTRUE(dir.exists(oge$dest_path))
    resolved_dest <- if (hedef_var) {
      tryCatch(
        .cc_scan_norm(normalizePath(oge$dest_path, winslash = "/", mustWork = TRUE)),
        error = function(e) ""
      )
    } else {
      beklenen_hedef
    }
    hedef_link <- isTRUE(hedef_var) && (
      !nzchar(resolved_dest) || isTRUE(cc_path_is_reparse_link(oge$dest_path))
    )
    resolved_dest_key <- .cc_scan_key(resolved_dest)
    hedef_guvenli <- nzchar(resolved_dest) && (
      identical(resolved_dest_key, approved_key) ||
        startsWith(resolved_dest_key, paste0(approved_key, "/"))
    )
    if (isTRUE(hedef_link) || !isTRUE(hedef_guvenli)) {
      sonuclar[[length(sonuclar) + 1L]] <- list(
        source_path = oge$source_path, dest_path = oge$dest_path,
        success = FALSE, size = oge$size,
        error = "Hedef dosya bağlantı/reparse-point veya onaylı kökün dışında"
      )
      next
    }

    # Kaynağı önce hedefle AYNI dizindeki bir staging dosyasına kopyala.
    # Büyük bir çıktı kopyalanırken çalıştırma durdurulmuş/stale olabilir;
    # bu durumda kopya BAŞLAMADAN önceki guard kontrolü yeterli değildir,
    # çünkü kopyalama sürerken de guard kaldırılmış olabilir. Hedefe
    # taşımadan (promote) hemen önce guard tekrar doğrulanır; aksi halde
    # durdurulmuş bir çalıştırma büyük bir kopyayı tamamlayıp kaynak
    # dosyayı yine de değiştirebilir.
    ok <- tryCatch({
      if (!is.null(active_guard) && nzchar(active_guard) && !file.exists(active_guard)) {
        stop("Çalıştırma durdurulduğu için aktarım başlatılmadı", call. = FALSE)
      }

      staging <- tempfile(pattern = ".cc-output-", tmpdir = hedef_dizin)
      staged <- isTRUE(tryCatch(
        file.copy(
          from = oge$source_path, to = staging,
          overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE
        ),
        error = function(e) FALSE
      )) && isTRUE(file.exists(staging))

      if (!isTRUE(staged)) {
        unlink(staging, force = TRUE)
        stop("Dosya kaynak dizine kopyalanamadı", call. = FALSE)
      }

      if (!is.null(active_guard) && nzchar(active_guard) && !file.exists(active_guard)) {
        unlink(staging, force = TRUE)
        stop("Çalıştırma durdurulduğu için aktarım iptal edildi", call. = FALSE)
      }

      tasindi <- isTRUE(tryCatch(file.rename(staging, oge$dest_path), error = function(e) FALSE))
      if (!isTRUE(tasindi)) {
        tasindi <- isTRUE(tryCatch(
          file.copy(
            from = staging, to = oge$dest_path,
            overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE
          ),
          error = function(e) FALSE
        ))
        unlink(staging, force = TRUE)
      }

      if (!isTRUE(tasindi)) {
        stop("Dosya kaynak dizine aktarılamadı", call. = FALSE)
      }

      TRUE
    }, error = function(e) {
      hata <<- conditionMessage(e)
      FALSE
    })

    if (!isTRUE(ok) && !nzchar(hata)) {
      hata <- "Dosya kaynak dizine kopyalanamadı"
    }

    sonuclar[[length(sonuclar) + 1L]] <- list(
      source_path = oge$source_path,
      dest_path = oge$dest_path,
      success = isTRUE(ok),
      size = oge$size,
      error = hata
    )
  }

  sonuclar
}

#' Eski runtime/doküman destek klasörlerini yaşa göre temizle
#'
#' Aktif çalışmaları etkilememesi için yalnızca belirtilen süreden eski
#' klasörler ve asla `keep_paths` içindeki yollar silinmez.
#'
#' @param user_id Kullanıcı kimliği
#' @param max_age_sec Saklama süresi (saniye)
#' @param keep_paths Korunacak yollar
#' @return Silinen klasör sayısı
cc_cleanup_stale_runtime_dirs <- function(user_id = NULL,
                                          max_age_sec = NULL,
                                          keep_paths = character(0)) {
  kullanici_dizin <- cc_runtime_user_dir(user_id)
  if (!dir.exists(kullanici_dizin)) return(invisible(0L))

  # NOT: max_age_sec NULL olduğunda as.numeric(NULL[1]) numeric(0) verir ve
  # is.finite() boş vektör döndürerek `if` içinde hata üretir. Bu yüzden
  # uzunluk kontrolü zorunludur.
  max_age_sec <- suppressWarnings(as.numeric(max_age_sec[1]))
  if (length(max_age_sec) != 1L || !is.finite(max_age_sec)) {
    max_age_sec <- suppressWarnings(as.numeric(
      cc_runtime_limit("runtime_retention_sec", 21600)
    )[1])
  }
  if (length(max_age_sec) != 1L || !is.finite(max_age_sec)) return(invisible(0L))

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

  simdi <- Sys.time()
  silinen <- 0L

  for (aday in adaylar) {
    aday_norm <- .cc_scan_norm(aday)
    if (.cc_scan_key(aday_norm) %in% koru) next

    leases <- tryCatch(
      list.files(
        file.path(aday, "metadata"), pattern = "^active-run-.*\\.lease$", recursive = FALSE,
        full.names = TRUE, include.dirs = FALSE
      ),
      error = function(e) character(0)
    )
    if (length(leases)) next

    mtime <- tryCatch(file.info(aday)$mtime[1], error = function(e) NA)
    if (is.na(mtime)) next

    yas <- as.numeric(difftime(simdi, mtime, units = "secs"))
    if (!is.finite(yas) || yas < max_age_sec) next

    ok <- tryCatch({
      unlink(aday, recursive = TRUE, force = TRUE)
      TRUE
    }, error = function(e) FALSE)

    if (isTRUE(ok)) silinen <- silinen + 1L
  }

  invisible(silinen)
}

#' Eski doküman destek klasörlerini yaşa göre temizle
#'
#' Aktif çalıştırmaları etkilememesi için yalnızca `max_age_sec` süresinden
#' eski ve `keep_paths` dışındaki klasörler silinir.
#'
#' @param user_id Kullanıcı kimliği
#' @param max_age_sec Saklama süresi (saniye)
#' @param keep_paths Korunacak klasör yolları
#' @return Silinen klasör sayısı
cc_cleanup_stale_document_support_dirs <- function(user_id = NULL,
                                                   max_age_sec = NULL,
                                                   keep_paths = character(0)) {
  kok <- file.path(
    tempdir(),
    "claude_code_runtime",
    paste0("user_", as.character(user_id %||% "default")),
    "document_support"
  )

  if (!dir.exists(kok)) return(invisible(0L))

  # Saklama süresi tek kaynaktan gelir: operatör CLAUDE_CODE_RUNTIME_RETENTION_SEC
  # değerini değiştirdiğinde doküman desteği de aynı süreye uyar.
  max_age_sec <- suppressWarnings(as.numeric(max_age_sec[1]))
  if (length(max_age_sec) != 1L || !is.finite(max_age_sec)) {
    max_age_sec <- suppressWarnings(as.numeric(
      cc_runtime_limit("runtime_retention_sec", 21600)
    )[1])
  }
  if (length(max_age_sec) != 1L || !is.finite(max_age_sec) || max_age_sec < 0) {
    return(invisible(0L))
  }

  adaylar <- tryCatch(
    list.dirs(kok, full.names = TRUE, recursive = FALSE),
    error = function(e) character(0)
  )

  if (!length(adaylar)) return(invisible(0L))

  koru <- tolower(gsub("\\", "/", as.character(keep_paths %||% character(0)), fixed = TRUE))
  simdi <- Sys.time()
  silinen <- 0L

  for (aday in adaylar) {
    aday_key <- tolower(gsub("\\", "/", aday, fixed = TRUE))
    if (aday_key %in% koru) next

    mtime <- tryCatch(file.info(aday)$mtime[1], error = function(e) NA)
    if (is.na(mtime)) next

    yas <- as.numeric(difftime(simdi, mtime, units = "secs"))
    if (!is.finite(yas) || yas < max_age_sec) next

    ok <- tryCatch({
      unlink(aday, recursive = TRUE, force = TRUE)
      TRUE
    }, error = function(e) FALSE)

    if (isTRUE(ok)) silinen <- silinen + 1L
  }

  invisible(silinen)
}

#' Bilge Yolaç runtime çıktı bölgesinin anlık görüntüsünü al
#'
#' Kaynak klasörün tamamı değil, yalnızca yazılabilir onaylı çıktı alanı
#' (runtime kökü + output) taranır; input/metadata/document_support hariç
#' tutulur.
#'
#' @param runtime_workdir Claude Code çalışma dizini
#' @param mirrored Izole runtime düzeni kullanılıyor mu
#' @param limits Sınır listesi
#' @return snapshot_claude_code_workdir_files() çıktısı
cc_snapshot_run_output_area <- function(runtime_workdir,
                                        mirrored = FALSE,
                                        limits = NULL) {
  # İzole runtime'da build/dist/bin gibi adlar onaylı output alanının normal
  # parçalarıdır; basename tabanlı kaynak-ağaç hariçleri burada uygulanmaz.
  # Input da başlangıç snapshot'ına girer ki Edit değişiklikleri bulunabilsin.
  # metadata/document_support hariç tutması yalnızca runtime KÖKÜNDE
  # uygulanır (exclude_rel_paths); basename eşleşmesi (exclude_dirs) "output/
  # metadata" gibi gerçek üretilmiş iç içe dizinleri de yanlışlıkla dışarıda
  # bırakırdı.
  haric_dir <- character(0)
  haric_rel <- character(0)

  if (isTRUE(mirrored)) {
    haric_rel <- setdiff(cc_scan_runtime_excluded_dirs(), "input")
  } else {
    haric_dir <- cc_scan_default_excluded_dirs()
  }

  snapshot_claude_code_workdir_files(
    workdir = runtime_workdir,
    recursive = TRUE,
    exclude_dirs = haric_dir,
    exclude_rel_paths = haric_rel,
    limits = limits
  )
}
