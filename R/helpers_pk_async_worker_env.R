# ==============================================================================
# Dosya Yolu: R/helpers_pk_async_worker_env.R
# Açıklama: Faz 6 (§5.10) — İŞÇİ ORTAMI YAŞAM DÖNGÜSÜ: içerik tabanlı kaynak
#           parmak izi, TEMİZ ortama yeniden yükleme ve bootstrap ÖNCESİ
#           yardımcıların işçi `globalenv()`'ine kurulması.
#
# `R/helpers_pk_async_bootstrap.R` içinden BÖLÜNMÜŞTÜR: orası bootstrap
# SÖZLEŞMESİDİR (hangi dosyalar, hangi giriş noktaları) ve 24-fonksiyon bakım
# tavanına dayanmıştı. Ortam yaşam döngüsü ayrı bir sorumluluktur.
#
# SAFTIR: Shiny/reaktif/DB/ağ ÇAĞIRMAZ. Yalnızca dosya sistemi ve ortam işler.
# ==============================================================================

# ------------------------------------------------------------------------------
# BOOTSTRAP ÖNCESİ YARDIMCILARIN İŞÇİYE KURULMASI
# ------------------------------------------------------------------------------
# `dependency_mode = "explicit"` globals'ı görev fonksiyonunun İZOLE ortamına
# yazar. `pk_async_run_analysis()` ise ANA SÜREÇTE tanımlanmış bir kapanıştır ve
# serileştirildiğinde lexical ortamı İŞÇİNİN `globalenv()`'i olur — yani izole
# globals ortamını GÖRMEZ. Bootstrap henüz çalışmadığı için o `globalenv()`
# BOŞTUR ve temiz bir PSOCK işçisi ham bir "could not find function" ile ölerdi.
#
# Bu yüzden görev fonksiyonu, kendi ortamındaki paketi analiz başlamadan ÖNCE
# işçinin `globalenv()`'ine kurar. Bootstrap sonradan aynı sembolleri repo
# dosyalarından yeniden tanımlar; iki kaynak da AYNI revizyondur.
#
# Ana süreçte (senkron/test yolu) bu işlem NO-OP'a yakındır: aynı isimler aynı
# nesnelerle üzerine yazılır.
#
# Paket, işçi globals paketi olduğunu kanıtlayan bir İŞARET taşır; işaretsiz
# hiçbir ortam `globalenv()`'e kopyalanmaz.
.PK_ASYNC_WORKER_BUNDLE_MARK <- ".pk_async_worker_bundle"
pk_async_worker_install_globals <- function(env, exclude = c("request", "task_fn")) {
  if (!is.environment(env)) return(invisible(character(0)))

  hedef <- globalenv()
  adlar <- tryCatch(ls(env, all.names = TRUE), error = function(e) character(0))

  # GÜVENLİK KAPISI: yalnızca AÇIKÇA işaretlenmiş işçi paketi kurulur. Bu
  # olmadan, kip yanlışlıkla "auto"ya çevrilirse bir gözlemci/oturum kapanışının
  # tüm bağları `globalenv()`'e kopyalanabilirdi.
  if (!(.PK_ASYNC_WORKER_BUNDLE_MARK %in% adlar)) return(invisible(character(0)))

  adlar <- setdiff(adlar, c(as.character(exclude %||% character(0)),
                            .PK_ASYNC_WORKER_BUNDLE_MARK))
  if (!length(adlar)) return(invisible(character(0)))

  kurulan <- character(0)
  for (ad in adlar) {
    ok <- tryCatch({
      deger <- get(ad, envir = env, inherits = FALSE)
      # Ana süreçte kendi kendini üzerine yazmak gereksiz iş olurdu.
      if (!identical(hedef, env)) assign(ad, deger, envir = hedef)
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(ok)) kurulan <- c(kurulan, ad)
  }

  invisible(kurulan)
}

# ------------------------------------------------------------------------------
# İÇERİK TABANLI KAYNAK PARMAK İZİ
# ------------------------------------------------------------------------------
# Kalıcı bir PSOCK işçisi ilk yüklediği uygulamayı ömrü boyunca saklar. Parmak
# izi değiştiğinde önbellek geçersizleşir ve işçi yeniden yüklenir.
#
# mtime + boyut YETMEZ: zaman damgalarını koruyan bir dağıtım/kopya, bir dosyayı
# AYNI uzunlukta FARKLI içerikle değiştirebilir; işçi o zaman eski kodu süresiz
# çalıştırmaya devam ederdi. Bu yüzden parmak izi DOSYA İÇERİĞİNDEN türetilir.
.pk_async_file_digest <- function(path) {
  boyut <- suppressWarnings(file.info(path)$size[1])
  if (is.na(boyut) || boyut <= 0) return(paste0(basename(path), ":yok"))

  ham <- tryCatch({
    con <- file(path, open = "rb")
    on.exit(close(con), add = TRUE)
    readBin(con, what = "raw", n = boyut)
  }, error = function(e) NULL)
  if (is.null(ham)) return(paste0(basename(path), ":okunamadi"))

  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(ham, algo = "sha256", serialize = FALSE))
  }
  if (requireNamespace("openssl", quietly = TRUE)) {
    return(paste(as.character(openssl::sha256(ham)), collapse = ""))
  }
  # Son çare: uzunluk + konum ağırlıklı toplam. `digest`/`openssl` üretimde
  # ZORUNLU bağımlılıktır; bu dal yalnızca çıplak test ortamları içindir.
  paste0(boyut, ":", sum(as.integer(ham) * seq_along(ham)) %% .Machine$integer.max)
}

# `config_sql_loader.R` her sorgunun HARİCİ `sql_file` dosyasını source anında
# `query_library` içine okur. Bir operatör `library_queries.R` dosyasına HİÇ
# dokunmadan bir `.sql` dosyasını güncellerse, ana süreç yeni SQL'i yüklerken
# kalıcı işçi aynı parmak izini görüp `cached = TRUE` döndürür ve ESKİ SQL'i
# süresiz çalıştırır. Bu yüzden çözülen SQL bağımlılıkları da parmak izine girer.
pk_async_worker_sql_dependencies <- function(repo_root) {
  kutuphane <- get0("query_library", inherits = TRUE)
  if (!is.list(kutuphane) || !length(kutuphane)) return(character(0))

  yollar <- vapply(kutuphane, function(sorgu) {
    if (!is.list(sorgu)) return("")
    yol <- tryCatch(as.character(sorgu$sql_file)[1], error = function(e) "")
    if (is.null(yol) || is.na(yol)) "" else yol
  }, character(1))

  yollar <- unique(yollar[nzchar(yollar)])
  if (!length(yollar)) return(character(0))

  # Göreli yollar repo köküne göre çözülür (loader `getwd()` kullanır).
  mutlak <- ifelse(
    grepl("^([A-Za-z]:)?[/\\\\]", yollar),
    yollar,
    file.path(repo_root, yollar)
  )
  sort(unique(mutlak))
}

#' Bootstrap kaynak parmak izi (İÇERİK tabanlı, SQL bağımlılıkları dahil)
pk_async_bootstrap_fingerprint <- function(repo_root, files) {
  tam <- file.path(repo_root, files)
  sql <- tryCatch(pk_async_worker_sql_dependencies(repo_root), error = function(e) character(0))

  hedefler <- c(tam, sql)
  parcalar <- vapply(hedefler, function(p) {
    paste0(basename(p), "@", .pk_async_file_digest(p))
  }, character(1), USE.NAMES = FALSE)

  ham <- paste(c(length(files), parcalar), collapse = "|")
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(ham, algo = "sha256"))
  }
  if (requireNamespace("openssl", quietly = TRUE)) {
    return(paste(as.character(openssl::sha256(ham)), collapse = ""))
  }
  paste0(length(hedefler), ":", nchar(ham))
}

# ------------------------------------------------------------------------------
# TEMİZ ORTAMA YENİDEN YÜKLEME
# ------------------------------------------------------------------------------
# Sıcak bir işçiye yeni revizyonu doğrudan `globalenv()` üzerine source etmek,
# KALDIRILMIŞ veya YENİDEN ADLANDIRILMIŞ sembolleri geride bırakır: işçi eski ve
# yeni güvenlik mantığının KARIŞIMINI çalıştırabilirdi. Bu yüzden yeni revizyon
# önce bir SAHNELEME ortamına yüklenir ve YALNIZCA tamamı başarılı olduğunda
# `globalenv()`'e alınır; bir önceki bootstrap'ın sahiplendiği isimler o anda
# temizlenir.
.PK_ASYNC_OWNED_NAMES_SLOT <- ".mergen_pk_async_bootstrap_names"

pk_async_worker_stage_env <- function() {
  new.env(parent = globalenv())
}

#' Sahneleme ortamını `globalenv()`'e al (önceki bootstrap isimlerini temizler)
pk_async_worker_commit_env <- function(stage, target = globalenv()) {
  if (!is.environment(stage)) return(invisible(character(0)))

  onceki <- get0(.PK_ASYNC_OWNED_NAMES_SLOT, envir = target, inherits = FALSE)
  onceki <- as.character(onceki %||% character(0))

  yeni <- tryCatch(ls(stage, all.names = TRUE), error = function(e) character(0))

  # Yeni revizyonda ARTIK OLMAYAN eski bootstrap sembolleri kaldırılır.
  atilacak <- setdiff(onceki, yeni)
  for (ad in atilacak) {
    try(rm(list = ad, envir = target), silent = TRUE)
  }

  for (ad in yeni) {
    try(assign(ad, get(ad, envir = stage, inherits = FALSE), envir = target), silent = TRUE)
  }

  assign(.PK_ASYNC_OWNED_NAMES_SLOT, yeni, envir = target)
  invisible(yeni)
}

# ------------------------------------------------------------------------------
# ÜRETİLEN ARTIFACT KAYDI
# ------------------------------------------------------------------------------
# Terminal temizlik YOLLARI yalnızca `sonuc` üzerinden ERİŞİLEBİLEN dosyaları
# silebilir. Ancak `.pk_result_v2()` dışa aktarımı ürettikten HEMEN SONRA
# Durdur gelirse `list(type = "pk_stopped")` döner (yollar kaybolur) ve bir
# istisna `pk_async_pipeline_error`'a dönüşürken de aynı şey olur. Her iki
# durumda da büyük XLSX/CSV dosyaları işçinin kalıcı temp dizininde ÖKSÜZ
# kalırdı. Bu yüzden dosyalar ÜRETİLDİKLERİ anda kaydedilir.
.pk_artifact_registry <- new.env(parent = emptyenv())
.pk_artifact_registry$paths <- character(0)

#' Üretilen artifact yollarını kaydet (istek kapsamı)
pk_artifact_track <- function(paths) {
  yollar <- tryCatch(as.character(paths %||% character(0)), error = function(e) character(0))
  yollar <- yollar[!is.na(yollar) & nzchar(yollar)]
  if (!length(yollar)) return(invisible(character(0)))
  .pk_artifact_registry$paths <- unique(c(.pk_artifact_registry$paths, yollar))
  invisible(.pk_artifact_registry$paths)
}

#' Kaydı SİLMEDEN boşalt (başarılı yolda sahiplik ana sürece geçer)
pk_artifact_release_tracked <- function() {
  onceki <- .pk_artifact_registry$paths
  .pk_artifact_registry$paths <- character(0)
  invisible(onceki)
}

#' Kaydedilmiş artifact'leri SİL (her başarısız terminal yolda)
pk_artifact_discard_tracked <- function() {
  yollar <- pk_artifact_release_tracked()
  if (!length(yollar)) return(invisible(FALSE))

  for (yol in yollar) try(unlink(yol, force = TRUE), silent = TRUE)
  # Her dışa aktarım KENDİ `run_*` dizinine yazar; boşalan dizin de kaldırılır.
  for (dizin in unique(dirname(yollar))) {
    norm <- gsub("\\\\", "/", dizin)
    if (grepl("(^|/)run_[^/]*$", norm) && dir.exists(dizin) && !length(list.files(dizin))) {
      try(unlink(dizin, recursive = TRUE, force = TRUE), silent = TRUE)
    }
  }
  invisible(TRUE)
}
