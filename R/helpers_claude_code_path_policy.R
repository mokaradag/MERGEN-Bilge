# ==============================================================================
# Dosya Yolu: R/helpers_claude_code_path_policy.R
# Açıklama: Bilge Yolaç Claude Code güvenlik ilkesinin yol/kök katmanı.
#           Yol normalizasyonu, izin verilen çalışma kökleri/çıktı kökleri ve
#           çalışma dizini doğrulaması burada toplanır. Bu dosya
#           R/helpers_claude_code_security_policy.R'den ayrıştırıldı; çalıştırma
#           izin/CLI arg politikaları orada kalır.
#
#           Dosya bölünmesinin nedeni: güvenlik ilkesi dosyası UNC error
#           handler'ları sonrası 25 fonksiyona ulaşmıştı; bu dosya
#           taşıma ile her iki dosyayı da 25+ fonksiyon eşiğinin altına
#           indirir ve maintainability ratchet'i koruyacak şekilde
#           güncel taban çizgisini düşürür.
# ==============================================================================

cc_policy_split_roots <- function(value) {
  value <- as.character(value %||% character(0))
  value <- value[nzchar(value)]

  if (!length(value)) {
    return(character(0))
  }

  parcalar <- unlist(strsplit(value, "[;,\n\r]+", perl = TRUE), use.names = FALSE)
  unique(trimws(parcalar[nzchar(trimws(parcalar))]))
}


cc_policy_collapse_dot_segments <- function(path) {
  yol <- as.character(path %||% "")[1]
  if (is.na(yol) || !nzchar(yol)) return("")

  yol <- gsub("\\", "/", yol, fixed = TRUE)
  unc_prefix <- ""
  drive_prefix <- ""
  absolute <- startsWith(yol, "/")

  if (grepl("^//[^/]+/[^/]+", yol, perl = TRUE)) {
    parcalar <- strsplit(sub("^//", "", yol), "/+", perl = TRUE)[[1]]
    if (length(parcalar) >= 2) {
      unc_prefix <- paste0("//", parcalar[1], "/", parcalar[2])
      parcalar <- parcalar[-c(1, 2)]
      absolute <- TRUE
    }
  } else if (grepl("^[A-Za-z]:/", yol, perl = TRUE)) {
    drive_prefix <- substr(yol, 1, 2)
    yol <- substring(yol, 4)
    absolute <- TRUE
    parcalar <- strsplit(yol, "/+", perl = TRUE)[[1]]
  } else {
    parcalar <- strsplit(sub("^/+", "", yol), "/+", perl = TRUE)[[1]]
  }

  if (!length(parcalar) || identical(parcalar, character(0))) {
    parcalar <- character(0)
  }

  stack <- character(0)
  for (parca in parcalar) {
    if (!nzchar(parca) || identical(parca, ".")) {
      next
    }

    if (identical(parca, "..")) {
      if (length(stack) && !identical(stack[length(stack)], "..")) {
        stack <- stack[-length(stack)]
      } else if (!isTRUE(absolute)) {
        stack <- c(stack, parca)
      }
      next
    }

    stack <- c(stack, parca)
  }

  govde <- paste(stack, collapse = "/")
  if (nzchar(unc_prefix)) {
    return(if (nzchar(govde)) paste0(unc_prefix, "/", govde) else unc_prefix)
  }
  if (nzchar(drive_prefix)) {
    return(if (nzchar(govde)) paste0(drive_prefix, "/", govde) else paste0(drive_prefix, "/"))
  }
  if (isTRUE(absolute)) {
    return(paste0("/", govde))
  }

  govde
}

cc_policy_normalize_path <- function(path, must_exist = FALSE) {
  path <- as.character(path %||% "")[1]
  if (is.na(path) || !nzchar(path)) return("")

  # UNC yolları (\\server\share veya //server/share) Windows VM'de mapped
  # drive harfine çözülebiliyor (örn. //rehisds/... -> M:/rehisds/...). Çözülen
  # M:/ formu is_problematic_windows_workdir tarafından UNC olarak algılanmadığı
  # için runtime aynalama atlanır ve processx'in spawn ettiği cmd.exe oturumu
  # M:/ drive haritalamasına sahip değilse "directory is empty" veya
  # "The system cannot find the path specified" hatasıyla biter. Bu yüzden
  # güvenlik politikası katmanı UNC yollarını UNC olarak korur.
  #
  # NOT: gsub("\\\\", "/", x, fixed=TRUE) yalnızca ardışık çift ters slash'ı
  # eşler; bu yüzden \\server\share\sub gibi tek aralık ters slash'lı UNC'ler
  # için yanlış pozitif/negatif üretebilir. is_windows_unc_path hem çift slash
  # hem de tek slash ağ yolu varyantlarını birlikte tanır; mevcutsa onu
  # kullanırız. Yoksa yedek olarak tüm ters slash'ları forward slash'a çevirip
  # yeniden test ederiz.
  is_unc <- FALSE
  if (exists("is_windows_unc_path", mode = "function", inherits = TRUE)) {
    is_unc <- tryCatch(
      isTRUE(is_windows_unc_path(path)),
      error = function(e) FALSE
    )
  }

  if (!isTRUE(is_unc)) {
    candidate_slash <- gsub("\\", "/", path, fixed = TRUE)
    is_unc <- grepl("^//[^/]+/[^/]+", candidate_slash, perl = TRUE)
  }

  if (isTRUE(is_unc)) {
    if (exists("normalize_mcp_path", mode = "function", inherits = TRUE)) {
      cozulen <- tryCatch(
        normalize_mcp_path(path, must_exist = must_exist),
        error = function(e) NA_character_
      )

      if (!is.na(cozulen) && nzchar(cozulen)) {
        cozulen_slash <- gsub("\\", "/", cozulen, fixed = TRUE)
        if (grepl("^//", cozulen_slash, perl = TRUE)) {
          # UNC yolunda da nokta segmentleri sadeleştirilmelidir; aksi hâlde
          # `//sunucu/pay/../../disari` kök önek denetimini geçerdi (CWE-22).
          cozulen_slash <- cc_policy_collapse_dot_segments(cozulen_slash)
          return(sub("/+$", "", cozulen_slash, perl = TRUE))
        }
      }
    }

    cleaned <- gsub("\\", "/", path, fixed = TRUE)
    cleaned <- paste0("//", sub("^/+", "", cleaned))
    cleaned <- cc_policy_collapse_dot_segments(cleaned)
    return(sub("/+$", "", cleaned, perl = TRUE))
  }

  sonuc <- tryCatch(
    normalizePath(path, winslash = "/", mustWork = isTRUE(must_exist)),
    error = function(e) {
      tryCatch(
        normalizePath(path, winslash = "/", mustWork = FALSE),
        error = function(e2) path
      )
    }
  )

  # NOT: normalizePath winslash="/" ile zaten forward slash üretir ama herhangi
  # bir karma slash kalırsa tek ters slash'a göre değiştirme yaparız (çiftli
  # gsub baştaki çift slash dışında diğer ters slash'ları kaçırırdı).
  sonuc <- gsub("\\", "/", sonuc, fixed = TRUE)
  sonuc <- cc_policy_collapse_dot_segments(sonuc)
  sub("/+$", "", sonuc, perl = TRUE)
}

cc_policy_normalize_roots <- function(roots) {
  roots <- cc_policy_split_roots(roots)
  if (!length(roots)) return(character(0))

  roots <- vapply(
    roots,
    cc_policy_normalize_path,
    character(1),
    must_exist = FALSE,
    USE.NAMES = FALSE
  )

  unique(roots[nzchar(roots)])
}

cc_policy_default_user_workspace <- function(user_id = NULL) {
  user_id <- suppressWarnings(as.integer(user_id %||% NA_integer_))

  if (is.na(user_id) || user_id <= 0L) {
    return("")
  }

  if (!exists("get_user_workspace", mode = "function", inherits = TRUE)) {
    return("")
  }

  tryCatch(
    get_user_workspace(user_id),
    error = function(e) ""
  )
}

cc_policy_allowed_workdir_roots <- function(user_id = NULL,
                                            extra_roots = character(0),
                                            allow_system_temp = FALSE) {
  configured <- character(0)

  if (exists("claude_code_config", inherits = TRUE)) {
    configured <- c(
      configured,
      claude_code_config$allowed_workdir_roots %||% "",
      claude_code_config$default_workdir %||% ""
    )
  }

  configured <- c(
    configured,
    Sys.getenv("CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS", ""),
    cc_policy_default_user_workspace(user_id),
    extra_roots
  )

  if (isTRUE(allow_system_temp)) {
    # Tüm tempdir() kökünü açmak, aynı R sürecindeki başka kullanıcının runtime
    # klasörünü de erişilebilir kılıyordu. Yalnızca Bilge Yolaç'ın kendi geçici
    # alt ağaçlarına izin verilir.
    #
    # Kullanıcı kimliği biliniyorsa ÜST kökler değil, YALNIZCA o kullanıcının
    # runtime dizini açılır. `cc_policy_path_inside_roots()` yalnızca kök önekine
    # baktığı için üst kök, başka kullanıcıların `user_<id>` alt ağaçlarını da
    # çalışma dizini olarak seçilebilir kılıyordu.
    kullanici_no <- suppressWarnings(as.integer(user_id %||% NA_integer_))
    kullanici_kapsamli <- !is.na(kullanici_no) && kullanici_no > 0L &&
      exists("cc_runtime_user_dir", mode = "function", inherits = TRUE)

    if (isTRUE(kullanici_kapsamli)) {
      # Kullanıcı çalışma alanı zaten cc_policy_default_user_workspace() ile
      # eklendi; burada yalnızca runtime kökü kullanıcıya daraltılır.
      configured <- c(configured, cc_runtime_user_dir(kullanici_no))
    } else {
      configured <- c(
        configured,
        file.path(tempdir(), "claude_code_runtime"),
        file.path(tempdir(), "claude_code_workspaces")
      )
    }
  }

  cc_policy_normalize_roots(configured)
}

# `allow_system_temp` yalnızca Bilge Yolaç'ın kendi geçici alt ağaçlarını açar;
# `tempdir()` KÖKÜ artık izinli değildir. Bağlantı testi gibi "boş ama izinli"
# bir çalışma dizinine ihtiyaç duyan çağrılar bu kökü kullanmalıdır (dizin
# yoksa oluşturulur; politika denetimi var olan dizin şartı arar).
cc_policy_temp_workspace_root <- function() {
  yol <- file.path(tempdir(), "claude_code_workspaces")
  if (!dir.exists(yol)) {
    dir.create(yol, recursive = TRUE, showWarnings = FALSE)
  }
  yol
}

cc_policy_allowed_output_roots <- function(user_id = NULL, workdir = "") {
  configured <- character(0)

  if (exists("claude_code_config", inherits = TRUE)) {
    configured <- c(configured, claude_code_config$allowed_output_roots %||% "")
  }

  download_root <- if (exists("get_claude_code_download_root", mode = "function", inherits = TRUE)) {
    tryCatch(get_claude_code_download_root(), error = function(e) "")
  } else {
    ""
  }

  configured <- c(
    configured,
    Sys.getenv("CLAUDE_CODE_ALLOWED_OUTPUT_ROOTS", ""),
    workdir %||% "",
    cc_policy_allowed_workdir_roots(user_id),
    download_root
  )

  cc_policy_normalize_roots(configured)
}

cc_policy_path_inside_roots <- function(path, roots, must_exist = FALSE) {
  hedef <- cc_policy_normalize_path(path, must_exist = must_exist)
  kokler <- cc_policy_normalize_roots(roots)

  if (!nzchar(hedef) || !length(kokler)) {
    return(FALSE)
  }

  hedef_key <- if (.Platform$OS.type == "windows") tolower(hedef) else hedef

  for (kok in kokler) {
    kok_key <- if (.Platform$OS.type == "windows") tolower(kok) else kok

    if (identical(hedef_key, kok_key) || startsWith(hedef_key, paste0(kok_key, "/"))) {
      return(TRUE)
    }
  }

  FALSE
}

cc_policy_validate_workdir <- function(workdir,
                                       user_id = NULL,
                                       extra_allowed_roots = character(0),
                                       allow_system_temp = FALSE,
                                       allow_selected_workdir = FALSE) {
  ham_yol <- as.character(workdir %||% "")[1]

  if (is.na(ham_yol) || !nzchar(ham_yol)) {
    return(list(
      ok = FALSE,
      path = "",
      error = "Çalışma dizini boş olamaz."
    ))
  }

  # UNC / Türkçe karakter / native encoding durumları için mevcut relaxed resolver'ı kullan.
  resolved_existing <- ""
  if (exists("cc_resolve_existing_dir_relaxed", mode = "function", inherits = TRUE)) {
    resolved_existing <- tryCatch(
      cc_resolve_existing_dir_relaxed(ham_yol),
      error = function(e) ""
    )
  }

  if (!nzchar(resolved_existing)) {
    aday_yol <- cc_policy_normalize_path(ham_yol, must_exist = FALSE)
    exists_base <- tryCatch(
      isTRUE(dir.exists(aday_yol)) || isTRUE(fs::dir_exists(aday_yol)),
      error = function(e) FALSE
    )

    if (isTRUE(exists_base)) {
      resolved_existing <- aday_yol
    }
  }

  if (!nzchar(resolved_existing)) {
    return(list(
      ok = FALSE,
      path = cc_policy_normalize_path(ham_yol, must_exist = FALSE),
      error = paste0("Çalışma dizini bulunamadı: ", ham_yol)
    ))
  }

  yol <- cc_policy_normalize_path(resolved_existing, must_exist = FALSE)

  selected_roots <- character(0)
  if (isTRUE(allow_selected_workdir)) {
    selected_roots <- yol
  }

  kokler <- cc_policy_allowed_workdir_roots(
    user_id = user_id,
    extra_roots = c(extra_allowed_roots, selected_roots),
    allow_system_temp = allow_system_temp
  )

  allowed_by_base_policy <- cc_policy_path_inside_roots(
    yol,
    cc_policy_allowed_workdir_roots(
      user_id = user_id,
      extra_roots = extra_allowed_roots,
      allow_system_temp = allow_system_temp
    ),
    must_exist = TRUE
  )

  if (!cc_policy_path_inside_roots(yol, kokler, must_exist = TRUE)) {
    return(list(
      ok = FALSE,
      path = yol,
      error = paste0(
        "Çalışma dizini güvenlik ilkesi tarafından engellendi: ",
        ham_yol,
        ". İzin verilen köklerden biri içinde bir klasör seçin veya ",
        "CLAUDE_CODE_ALLOWED_WORKDIR_ROOTS ayarını açıkça yapılandırın."
      )
    ))
  }

  if (isTRUE(allow_selected_workdir) && !isTRUE(allowed_by_base_policy)) {
    log_warn(paste(
      CLAUDE_CODE_LOG_PREFIX,
      "Çalışma dizini kullanıcı seçimiyle bu çalışma için onaylandı:",
      gsub("[{}]", "", yol)
    ))
  }

  list(ok = TRUE, path = yol, error = "")
}

cc_policy_filter_generated_file_paths <- function(file_paths,
                                                  allowed_roots,
                                                  context = "üretilen dosya") {
  file_paths <- unique(Filter(nzchar, as.character(file_paths %||% character(0))))

  if (!length(file_paths)) {
    return(character(0))
  }

  izinli <- character(0)

  for (yol in file_paths) {
    yol_norm <- cc_policy_normalize_path(yol, must_exist = FALSE)

    if (!cc_policy_path_inside_roots(yol_norm, allowed_roots, must_exist = FALSE)) {
      log_warn(paste(
        CLAUDE_CODE_LOG_PREFIX,
        context,
        "izin verilen köklerin dışında olduğu için engellendi:",
        gsub("[{}]", "", yol_norm)
      ))
      next
    }

    izinli <- c(izinli, yol_norm)
  }

  unique(izinli)
}

# ------------------------------------------------------------------------------
# Yerel klasör yüklemesinde hedef yolu güvenli biçimde çözer.
#
# Tarayıcıdan gelen göreli yol (webkitRelativePath) veya dosya adı doğrulanmadan
# çalışma alanıyla birleştirildiğinde '..', mutlak yol ya da sürücü harfi taşıyan
# bir girdi çalışma alanının DIŞINA yazabiliyordu (overwrite = TRUE ile başka
# kullanıcı/runtime dosyalarının üzerine yazma). Güvenli değilse NULL döner.
# ------------------------------------------------------------------------------
# Karşılaştırma anahtarı: Windows'ta harf büyüklüğü ve kodlama işareti farkı
# aynı yolu eşitsiz gösterir.
.cc_yol_anahtari <- function(yol) {
  yol <- enc2utf8(sub("/+$", "", gsub("\\\\", "/", as.character(yol))))
  if (.Platform$OS.type == "windows") tolower(yol) else yol
}

# KALAN SINIR (bilinçli): base R yalnızca YOL TABANLI dosya çağrıları sunar
# (`openat`/`renameat` gibi tanıtıcı-bağıl temel işlemler yoktur). Bu yüzden
# son kimlik denetimi ile `file.rename()` arasındaki mikro pencere kapatılamaz;
# çalışma alanına yazabilen YEREL bir saldırgan tam o anda bir atayı takas
# ederse yazma dışarı düşebilir. Kod bu durumda BAŞARI BİLDİRMEZ ve hiçbir yol
# tabanlı silme denemez; tam kapatma yerel bir C yardımcısı gerektirir.
#
# Yerel klasör yüklemesini doğrulama-sonrası takasa (TOCTOU) karşı yazar.
# `file.copy(..., overwrite = TRUE)` son bileşendeki bağlantıyı İZLER: doğrulama
# ile yazma arasında hedef veya bir atası bağlantıyla değiştirilirse servis
# hesabı çalışma alanı DIŞINA yazar. Bu yüzden önce hedef dizinde geçici bir ada
# kopyalanır, geçici dosyanın KANONİK yolu kökün altında mı diye bakılır (ata
# takası burada yakalanır) ve ancak sonra file.rename() ile son ada taşınır;
# rename son bileşendeki bağlantıyı izlemez, onu değiştirir.
cc_yerel_yukleme_yaz <- function(kaynak, hedef, kok) {
  hedef_dizin <- dirname(hedef)
  if (!dir.exists(hedef_dizin)) {
    dir.create(hedef_dizin, recursive = TRUE, showWarnings = FALSE)
  }
  if (!dir.exists(hedef_dizin)) {
    return(FALSE)
  }

  kok_c <- try(normalizePath(kok, winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(kok_c, "try-error")) {
    return(FALSE)
  }
  kok_a <- .cc_yol_anahtari(kok_c)

  # Hedef dizinin KOPYADAN ÖNCEKİ kanonik kimliği. Temizlik yalnızca geçici
  # dosya hâlâ bu kimlikteki dizindeyken yapılır; aradaki bir ata takası
  # kimliği değiştirir ve silme adımı hiç çalışmaz.
  dizin_once <- try(normalizePath(hedef_dizin, winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(dizin_once, "try-error")) {
    return(FALSE)
  }
  dizin_once_a <- .cc_yol_anahtari(dizin_once)

  # DEĞİŞMEZ KURAL: geçici dosya HEDEFİN KENDİ DİZİNİNDE üretilir. Böylece
  # `hedef`in son bileşeni dışındaki HER atası aynı zamanda `gecici`nin de
  # atasıdır. Doğrulama ile rename arasında bir ata bağlantıyla değiştirilirse
  # KAYNAK yol da o bağlantının içine düşer, geçici dosya orada bulunmaz ve
  # rename ENOENT ile başarısız olur; yazma çalışma alanının dışına taşamaz.
  # Son bileşeni rename İZLEMEZ, değiştirir. Geçici dosyayı başka bir dizine
  # (ör. tempdir()) taşımak bu korumayı ORTADAN KALDIRIR.
  gecici <- file.path(
    hedef_dizin,
    paste0(".cc_yukleme_", basename(tempfile("")), ".part")
  )
  kopyalandi <- isTRUE(try(
    suppressWarnings(file.copy(kaynak, gecici, overwrite = FALSE)),
    silent = TRUE
  ))
  if (!kopyalandi) {
    # Hiçbir dosya oluşturmadık; bu yolda unlink DENENMEZ. Ata takas edilmişse
    # yol tabanlı silme başkasının dosyasını yok ederdi.
    return(FALSE)
  }

  # `overwrite = FALSE` ile kopyalama başarılıysa bu yolda daha önce dosya
  # YOKTU: geçici dosya bize aittir. Kanonik yolu bağlantıları çözer; kökün
  # dışına düşüyorsa doğrulamadan sonra bir ata değiştirilmiştir.
  gecici_c <- try(normalizePath(gecici, winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(gecici_c, "try-error") ||
      !startsWith(.cc_yol_anahtari(gecici_c), paste0(kok_a, "/"))) {
    if (!inherits(gecici_c, "try-error") &&
        identical(.cc_yol_anahtari(dirname(gecici_c)), dizin_once_a)) {
      try(unlink(gecici_c, force = TRUE), silent = TRUE)
    }
    return(FALSE)
  }

  # Taşımadan HEMEN ÖNCE kimlik yeniden doğrulanır: bir ata bağlantıyla
  # değiştirildiyse geçici dosya artık kopyadan önceki dizinde değildir ve
  # taşıma hiç denenmez.
  tasima_c <- try(normalizePath(gecici, winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(tasima_c, "try-error") ||
      !identical(.cc_yol_anahtari(dirname(tasima_c)), dizin_once_a)) {
    return(FALSE)
  }

  # `file.rename()` izinler elverdiği sürece var olan hedefin ÜZERİNE yazar;
  # ayrı bir silme adımına gerek yoktur. Başarısız rename'den sonra
  # `unlink(hedef)` DENENMEZ: yol tabanlı silme ata bileşenlerini izler ve bir
  # ata bağlantıyla değiştirilmişse çalışma alanının DIŞINDAKİ dosyayı silerdi.
  # Kaynak olarak ham `gecici` kullanılır; paylaşılan-ata değişmezi ancak
  # böyle korunur (kanonik kaynak, ata takasında hedefin dışarı kaymasına
  # izin verirdi).
  tasindi <- isTRUE(try(suppressWarnings(file.rename(gecici, hedef)), silent = TRUE))
  if (!tasindi) {
    # Temizlik KİMLİĞE bağlıdır: geçici dosya yeniden çözülür ve yalnızca hâlâ
    # kopyadan önceki dizindeyse silinir. Ata takas edildiyse ya yol çözülemez
    # ya da dizin kimliği tutmaz; her iki durumda da silme yapılmaz.
    son_c <- try(normalizePath(gecici, winslash = "/", mustWork = TRUE), silent = TRUE)
    if (!inherits(son_c, "try-error") &&
        identical(.cc_yol_anahtari(dirname(son_c)), dizin_once_a)) {
      try(unlink(son_c, force = TRUE), silent = TRUE)
    }
    return(FALSE)
  }

  # SON DOĞRULAMA: taşıma gerçekten çalışma alanının İÇİNE indi mi? Ata takası
  # tam rename anında yapılırsa hem kaynak hem hedef dışarı çözülebilir; böyle
  # bir durumda BAŞARI BİLDİRİLMEZ.
  hedef_c <- try(normalizePath(hedef, winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(hedef_c, "try-error") ||
      !startsWith(.cc_yol_anahtari(hedef_c), paste0(kok_a, "/")) ||
      !identical(.cc_yol_anahtari(dirname(hedef_c)), dizin_once_a)) {
    return(FALSE)
  }

  TRUE
}

cc_setup_yerel_yukleme_hedefi <- function(calisma_alani, goreceli) {
  goreceli <- as.character(goreceli %||% "")[1]
  if (is.na(goreceli) || !nzchar(goreceli)) {
    return(NULL)
  }

  goreceli <- gsub("\\\\", "/", goreceli)

  # Mutlak yol, UNC ve sürücü harfi hiçbir biçimde kabul edilmez.
  if (startsWith(goreceli, "/") || grepl("^[A-Za-z]:", goreceli, perl = TRUE)) {
    return(NULL)
  }

  parcalar <- Filter(nzchar, strsplit(goreceli, "/", fixed = TRUE)[[1]])
  if (!length(parcalar) || any(parcalar %in% c(".", ".."))) {
    return(NULL)
  }

  hedef <- do.call(file.path, as.list(c(calisma_alani, parcalar)))

  anahtar <- .cc_yol_anahtari

  # Kanonik kapsama denetimi. normalizePath() yalnızca VAR OLAN yolu çözer;
  # Windows'ta var olmayan yol 8.3 kısa adıyla (KULLAN~1) döner, kök ise uzun
  # ada açılır ve geçerli her yükleme reddedilirdi. Bu yüzden var olan EN DERİN
  # ata kanoniklestirilir (kardeş çıktı eşitleme yolu da aynı deseni kullanır).
  kok <- try(normalizePath(calisma_alani, winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(kok, "try-error")) {
    return(NULL)
  }
  ata <- dirname(hedef)
  while (!dir.exists(ata) && !identical(dirname(ata), ata)) {
    ata <- dirname(ata)
  }
  coz <- try(normalizePath(ata, winslash = "/", mustWork = TRUE), silent = TRUE)
  if (inherits(coz, "try-error")) {
    return(NULL)
  }
  kok_a <- anahtar(kok)
  coz_a <- anahtar(coz)
  if (!identical(coz_a, kok_a) && !startsWith(coz_a, paste0(kok_a, "/"))) {
    return(NULL)
  }

  # SON BİLEŞEN denetimi. Yukarıdaki kanoniklestirme yalnızca üst dizinler
  # üzerinde çalışır; hedefin KENDİSİ çalışma alanı dışına işaret eden bir
  # bağlantı ise file.copy(..., overwrite = TRUE) bağlantıyı İZLER ve harici
  # dosyayı ezer.
  taban <- parcalar[length(parcalar)]
  ust_dizin <- dirname(hedef)
  var_mi <- isTRUE(file.exists(hedef)) || isTRUE(dir.exists(hedef))

  # SARKAN bağlantı (POSIX): file.exists() bağlantıyı izlediği için kırık bir
  # symlink'te FALSE döner, ancak giriş üst dizin listesinde durur ve kopyalama
  # yine bağlantıyı izler. Var olmayan ama listede görünen ad bu yüzden
  # reddedilir (listeleme başarısızsa kapalı-başarısız). Windows'ta aynı giriş
  # var sayıldığı için aşağıdaki var-olan-hedef dalından geçer.
  if (!var_mi && dir.exists(ust_dizin)) {
    girisler <- try(
      suppressWarnings(list.files(ust_dizin, all.files = TRUE, no.. = TRUE)),
      silent = TRUE
    )
    if (inherits(girisler, "try-error") || anahtar(taban) %in% anahtar(girisler)) {
      return(NULL)
    }
  }

  # Var olan hedef: bağlantı olmamalı, stat edilebilmeli ve kanonik olarak
  # kökün altında kalmalı. Doğrulama yapılamıyorsa kapalı-başarısız davranılır.
  if (var_mi) {
    hedef_guvenli <- tryCatch({
      bag_kontrol <- get0("cc_path_is_reparse_link", mode = "function")
      # Stat edilemeyen giriş (sarkan bağlantı, erişilemeyen reparse point)
      # çözülemez; üzerine yazmak bağlantıyı izleyip dışarıyı ezebilir.
      stat_ok <- !is.na(suppressWarnings(file.info(hedef)$isdir[1]))
      if (!is.function(bag_kontrol) || isTRUE(bag_kontrol(hedef)) || !isTRUE(stat_ok)) {
        FALSE
      } else {
        hedef_coz <- anahtar(normalizePath(hedef, winslash = "/", mustWork = TRUE))
        nzchar(hedef_coz) && startsWith(hedef_coz, paste0(kok_a, "/"))
      }
    }, error = function(e) FALSE)

    if (!isTRUE(hedef_guvenli)) {
      return(NULL)
    }
  }

  hedef
}
