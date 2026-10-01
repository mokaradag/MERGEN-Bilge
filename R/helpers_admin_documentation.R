# ==============================================================================
# Dosya Yolu: R/helpers_admin_documentation.R
# Açıklama: Yönetici paneli "Dokümantasyon" sayfası için saf yardımcılar.
#            - İzin listeli (allowlist) belge kayıt defteri (tek doğruluk kaynağı)
#            - Yol güvenliği (path traversal / mutlak yol reddi)
#            - UTF-8 güvenli Markdown okuma
#            - commonmark ile Markdown -> HTML + etiket beyaz-liste temizliği
#            - Başlıklardan ASCII-güvenli çapa (anchor) ve İçindekiler üretimi
#
#            Bu dosya yalnızca saf fonksiyon içerir: Shiny/reaktif/DB/ağ erişimi
#            YOKTUR. Böylece çevrimdışı ve deterministik biçimde test edilebilir.
#            CLAUDE.md Markdown/HTML güvenlik sınırı korunur: belgeler güvenilir
#            depo dosyalarıdır; yine de ham script/olay yakalayıcı HTML
#            etkisizleştirilir.
# ==============================================================================

# ------------------------------------------------------------------------------
# BELGE KAYIT DEFTERİ (TEK DOĞRULUK KAYNAĞI / ALLOWLIST)
# ------------------------------------------------------------------------------
# Yalnızca buradaki belgeler uygulama içinde gösterilir. CLAUDE.md, AGENTS.md,
# docs/maintainers/ ve eklenti becerileri (AI ajan sözleşmeleri/istemleri)
# bilinçli olarak DIŞARIDA bırakılmıştır. Kök ve docs/ altına eklenen her yeni
# belge buraya ya da test dışlama listesine eklenmelidir (sözleşme testi).
admin_doc_registry <- function() {
  belge <- function(id, title, file, desc) {
    list(id = id, title = title, file = file, desc = desc)
  }
  list(
    list(
      id = "baslangic", title = "Başlangıç", icon = "rocket",
      docs = list(
        belge("readme", "Genel Bakış (README)", "README.md",
              "Ürünün genel tanıtımı ve ilk giriş belgesi."),
        belge("docs_readme", "Dokümantasyon Haritası", "docs/README.md",
              "Tüm belgelerin haritası ve önerilen okuma sırası.")
      )
    ),
    list(
      id = "mimari", title = "Mimari ve Teknik", icon = "sitemap",
      docs = list(
        belge("architecture", "Mimari Haritası", "docs/architecture-map.md",
              "Uygulama mimarisi, katmanlar ve korunan sınırlar."),
        belge("feature_ownership", "Özellik Sahiplik Haritası",
              "docs/feature-ownership-map.md",
              "Özelliklerin sahip dosyaları, modülleri ve testleri."),
        belge("technical", "Teknik Referans", "docs/technical-reference.md",
              "Derin teknik referans ve modül ayrıntıları."),
        belge("database", "Veritabanı Şeması", "docs/database-schema.md",
              "MB_* tabloları ve veri modeli."),
        belge("database_pooling", "Veritabanı Bağlantı Havuzu",
              "docs/database-pooling.md",
              "İşlem-güvenli bağlantı havuzu ve kullanım kuralları."),
        belge("refactor_log", "Refactor Günlüğü", "docs/refactor-log.md",
              "Yapısal değişikliklerin gerekçeleri ve kayıtları.")
      )
    ),
    list(
      id = "operasyon", title = "Operasyon", icon = "server",
      docs = list(
        belge("runbook", "Operasyon Kılavuzu (RUNBOOK)", "RUNBOOK.md",
              "Windows VM, SSO ve üretim çalıştırma kılavuzu."),
        belge("log_paths", "Üretim Log Yolları", "docs/production-log-paths.md",
              "Log klasörü seçimi ve mojibake onarımı."),
        belge("dependency", "Bağımlılık Kilitleme", "docs/dependency-locking.md",
              "renv ile sürüm kilitleme akışı ve kurallar."),
        belge("renv_status", "renv Kilit Durumu", "RENV_LOCK_STATUS.md",
              "Üretim renv.lock kaynağı ve sağlama notu.")
      )
    ),
    list(
      id = "kalite", title = "Doğrulama", icon = "clipboard-check",
      docs = list(
        belge("vm_evidence", "VM Kanıt Kapısı Durumu", "docs/vm-evidence-status.md",
              "Windows VM doğrulama kapısının son durumu."),
        belge("soak_gate", "Soak / Yük Test Kapısı", "docs/operational-soak-gate.md",
              "Operasyonel yük ve dayanıklılık testi kapısı."),
        belge("performance_plan", "Performans İyileştirme Planı",
              "docs/performance-improvement-plan.md",
              "Performans ölçümleri ve iyileştirme yol haritası (İngilizce).")
      )
    ),
    list(
      id = "ozellikler", title = "Özellikler", icon = "puzzle-piece",
      docs = list(
        belge("pk_master_plan", "Proje ve Kaynak Analizi Planı",
              "docs/proje-kaynak-analizi-master-plan.md",
              "Proje ve Kaynak Analizi yeniden yapılanma planı (İngilizce)."),
        belge("pk_operator", "PK Sorgu Metadata Kılavuzu",
              "docs/pk-phase3b-operator-runbook.md",
              "Sorgu metadata üreticisi ve yerel alias operatör kılavuzu."),
        belge("pk_sql_gate", "PK SQL Salt-Okunur Kapısı", "docs/pk-sql-readonly-gate.md",
              "Analiz sorgularının salt-okunur güvenlik kapısı."),
        belge("ortak_oturumlar", "Ortak Oturumlar", "docs/ortak-oturumlar.md",
              "İşbirlikçi çalışma odaları tasarımı ve kullanımı."),
        belge("bilge_savunmasi", "Bilge Savunması", "docs/bilge-savunmasi.md",
              "Kule savunma oyunu tasarım ve operasyon rehberi.")
      )
    ),
    list(
      id = "konusma", title = "Konuşma", icon = "microphone",
      docs = list(
        belge("speech_runbook", "Konuşma Varlıkları Operatör Rehberi",
              "docs/speech-operator-runbook.md",
              "VoxCPM2 konuşma varlıklarının Windows VM üretim akışı."),
        belge("speech_readme", "Önceden Üretilmiş Konuşmalar", "www/speech/README.md",
              "Statik konuşma varlıklarının klasör düzeni."),
        belge("speech_voices", "Persona Referans Sesleri", "www/speech/voices/README.md",
              "Referans ses, metin ve voice-lock kilitleri."),
        belge("speech_scripts", "Ortak Konuşma Metinleri", "www/speech/scripts/README.md",
              "Persona ortak konuşma/altyazı metinleri."),
        belge("speech_audio", "Persona WAV Kayıtları", "www/speech/audio/README.md",
              "Persona WAV kayıtlarının yerleşimi."),
        belge("speech_generated", "Üretilen Konuşma Üst Verileri",
              "www/speech/generated/README.md",
              "Otomatik üretilen manifest ve durum dosyaları.")
      )
    ),
    list(
      id = "varliklar", title = "Varlıklar", icon = "cubes",
      docs = list(
        belge("offline_assets", "Çevrimdışı Varlık Kontrol Listesi",
              "offline_asset_checklist.md",
              "Çevrimdışı kurulumda yerelden yüklenecek görsel varlıklar."),
        belge("threejs_assets", "Three.js Yerel Dosyaları",
              "www/lib/threejs/INDIRME_TALIMATLARI.md",
              "Three.js yerel dosyalarının indirme talimatları."),
        belge("api_key_assets", "API Anahtarı Modalı Varlıkları",
              "www/assets/api-key-choice/README.md",
              "API anahtarı seçim modalının yerel görsel/medya varlıkları."),
        belge("savunma_assets", "Bilge Savunması Varlıkları",
              "www/assets/bilge_savunmasi/README.md",
              "Bilge Savunması oyununun yerel varlıkları.")
      )
    ),
    list(
      id = "urun", title = "Ürün ve Davranış", icon = "compass",
      docs = list(
        belge("ai_rehber", "Asistan Davranış Rehberi", "ai_rehber.md",
              "Destek sohbet botu ve AI Uzman için bilgi tabanı."),
        belge("release_notes", "Sürüm Notları", "docs/release-notes.md",
              "Sürüm geçmişi ve değişiklik notları."),
        belge("version_history", "Sürüm Geçmişi", "version_history.md",
              "Uygulama içi sürüm bilgilendirmesinin kaynağı.")
      )
    )
  )
}

# Tüm belgeleri tek düz listeye indirger
admin_doc_all_docs <- function() {
  out <- list()
  for (g in admin_doc_registry()) {
    for (d in g$docs) {
      out[[length(out) + 1L]] <- d
    }
  }
  out
}

# Belge kimliğine göre kayıt defteri girdisini döndürür (yoksa NULL)
admin_doc_lookup <- function(doc_id) {
  if (is.null(doc_id) || !is.character(doc_id) ||
      length(doc_id) != 1L || is.na(doc_id) || !nzchar(doc_id)) {
    return(NULL)
  }
  for (d in admin_doc_all_docs()) {
    if (identical(d$id, doc_id)) return(d)
  }
  NULL
}

admin_doc_is_known <- function(doc_id) {
  !is.null(admin_doc_lookup(doc_id))
}

admin_doc_docs_in_group <- function(group_id) {
  for (g in admin_doc_registry()) {
    if (identical(g$id, group_id)) return(g$docs)
  }
  list()
}

admin_doc_default_group_id <- function() {
  admin_doc_registry()[[1]]$id
}

admin_doc_default_doc_id <- function() {
  admin_doc_registry()[[1]]$docs[[1]]$id
}

# ------------------------------------------------------------------------------
# REPO KÖKÜ VE YOL GÜVENLİĞİ
# ------------------------------------------------------------------------------
# Çalışma zamanında repo kökünü bulur: app.R + R/ klasörü olan dizin.
admin_doc_repo_root <- function() {
  candidates <- c(
    getwd(),
    Sys.getenv("MERGEN_REPO_ROOT", ""),
    normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = FALSE),
    normalizePath(file.path(getwd(), "..", ".."), winslash = "/", mustWork = FALSE)
  )
  candidates <- candidates[nzchar(candidates)]

  for (cand in candidates) {
    if (file.exists(file.path(cand, "app.R")) && dir.exists(file.path(cand, "R"))) {
      return(normalizePath(cand, winslash = "/", mustWork = FALSE))
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

# İzin listeli belge kimliğini güvenli mutlak yola çözer.
# Bilinmeyen kimlik, yol kaçışı (..) veya mutlak yol => "" (reddedilir).
admin_doc_resolve_path <- function(doc_id, root = admin_doc_repo_root()) {
  entry <- admin_doc_lookup(doc_id)
  if (is.null(entry)) return("")

  rel <- entry$file
  if (is.null(rel) || !is.character(rel) || length(rel) != 1L || !nzchar(rel)) {
    return("")
  }

  # Güvenlik: yol kaçışı ve mutlak/sürücü-kökü yollar reddedilir
  if (grepl("..", rel, fixed = TRUE)) return("")
  if (grepl("^([A-Za-z]:|/|\\\\)", rel, perl = TRUE)) return("")

  if (is.null(root) || !nzchar(root)) return("")

  candidate <- normalizePath(file.path(root, rel), winslash = "/", mustWork = FALSE)
  root_norm <- normalizePath(root, winslash = "/", mustWork = FALSE)

  # İçerme kontrolü: aday kesinlikle kök altında olmalı
  if (!startsWith(paste0(candidate, "/"), paste0(root_norm, "/"))) {
    return("")
  }

  candidate
}

# UTF-8/BOM/CRLF güvenli okuma; satırları tek metne birleştirir.
admin_doc_read_markdown <- function(path) {
  if (is.null(path) || !is.character(path) || length(path) != 1L ||
      !nzchar(path) || !file.exists(path)) {
    return("")
  }

  lines <- if (exists("read_text_lines_utf8", mode = "function", inherits = TRUE)) {
    read_text_lines_utf8(path)
  } else {
    tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"),
             error = function(e) character(0))
  }

  if (!length(lines)) return("")
  enc2utf8(paste(lines, collapse = "\n"))
}

# ------------------------------------------------------------------------------
# ÇAPA (ANCHOR) / SLUG ÜRETİMİ
# ------------------------------------------------------------------------------
# Türkçe karakterleri ASCII'ye çevirir; ASCII-güvenli slug üretir. tolower yerine
# chartr ile küçültür çünkü Türkçe locale'de tolower("I") -> "ı" (locale-bağımlı).
admin_doc_slugify <- function(text) {
  if (is.null(text) || !is.character(text) || length(text) != 1L || is.na(text)) {
    return("bolum")
  }

  s <- enc2utf8(text)
  tr_from <- c("ç", "Ç", "ğ", "Ğ", "ı", "İ", "ö", "Ö", "ş", "Ş", "ü", "Ü")
  tr_to   <- c("c", "c", "g", "g", "i", "i", "o", "o", "s", "s", "u", "u")
  for (i in seq_along(tr_from)) {
    s <- gsub(tr_from[i], tr_to[i], s, fixed = TRUE)
  }

  # ASCII'ye özel olmayan kalan karakterleri de güvenli biçimde ayıkla
  s <- chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", s)
  s <- gsub("[^a-z0-9]+", "-", s, perl = TRUE)
  s <- gsub("^-+|-+$", "", s, perl = TRUE)

  if (!nzchar(s)) s <- "bolum"
  s
}

# İç metinden HTML etiketlerini ve temel entity'leri ayıklar (İçindekiler metni).
admin_doc_strip_tags <- function(x) {
  if (is.null(x) || !is.character(x) || length(x) != 1L || is.na(x)) return("")
  out <- gsub("<[^>]*>", "", x, perl = TRUE)
  out <- gsub("&lt;", "<", out, fixed = TRUE)
  out <- gsub("&gt;", ">", out, fixed = TRUE)
  out <- gsub("&quot;", "\"", out, fixed = TRUE)
  out <- gsub("&#39;", "'", out, fixed = TRUE)
  out <- gsub("&amp;", "&", out, fixed = TRUE)
  trimws(out)
}

# HTML güvenlik temizliği (etiket beyaz-listesi, tırnak duyarlı etiket ve
# öznitelik ayrıştırıcısı) R/helpers_admin_documentation_sanitize.R içindedir.

# ------------------------------------------------------------------------------
# İÇİNDEKİLER (TOC) + BAŞLIK ÇAPALARI
# ------------------------------------------------------------------------------
# Temizlenmiş HTML üzerinden başlıklara ASCII-güvenli id ekler ve İçindekiler
# listesini üretir. Çakışan başlıklar için benzersizlik eki uygulanır.
admin_doc_extract_toc <- function(html) {
  if (is.null(html) || length(html) != 1L || is.na(html) || !nzchar(html)) {
    return(list(html = if (is.null(html)) "" else html, toc = list()))
  }

  m <- gregexpr("<h([1-6])>(.*?)</h\\1>", html, perl = TRUE)
  matches <- regmatches(html, m)[[1]]
  if (!length(matches)) return(list(html = html, toc = list()))

  used <- new.env(parent = emptyenv())
  toc <- vector("list", length(matches))
  new_heads <- character(length(matches))

  for (i in seq_along(matches)) {
    h <- matches[i]
    level <- as.integer(sub("^<h([1-6])>.*$", "\\1", h, perl = TRUE))
    inner <- sub("^<h[1-6]>(.*)</h[1-6]>$", "\\1", h, perl = TRUE)
    text <- admin_doc_strip_tags(inner)
    if (!nzchar(text)) text <- "Bölüm"

    # Tekrarlanan başlık GitHub/CommonMark kuralıyla `-1`, `-2` eki alır; böylece
    # `#notlar-1` bağlantısı ikinci "Notlar" başlığına gider.
    anchor <- paste0("mbdoc-", admin_doc_slugify(text))
    key <- anchor
    n <- 0L
    while (!is.null(used[[key]])) {
      n <- n + 1L
      key <- paste0(anchor, "-", n)
    }
    used[[key]] <- TRUE
    anchor <- key

    new_heads[i] <- paste0(
      "<h", level, " id=\"", anchor,
      "\" class=\"mb-doc-h mb-doc-h", level, "\">", inner, "</h", level, ">"
    )
    toc[[i]] <- list(level = level, text = text, id = anchor)
  }

  regmatches(html, m) <- list(new_heads)
  list(html = html, toc = toc)
}

# ------------------------------------------------------------------------------
# YÜKSEK SEVİYE RENDER
# ------------------------------------------------------------------------------
admin_doc_render_markdown <- function(content) {
  if (is.null(content) || !is.character(content) || length(content) != 1L ||
      is.na(content) || !nzchar(content)) {
    return(list(html = "", toc = list()))
  }

  raw_html <- commonmark::markdown_html(
    content,
    hardbreaks = FALSE,
    extensions = c("strikethrough", "table")
  )

  safe_html <- admin_doc_sanitize_html(raw_html)
  admin_doc_extract_toc(safe_html)
}

# İzin listeli belge kimliğini güvenli biçimde render eder.
admin_doc_render_document <- function(doc_id, root = admin_doc_repo_root()) {
  entry <- admin_doc_lookup(doc_id)
  if (is.null(entry)) {
    return(list(ok = FALSE, doc_id = doc_id, title = "", source = "",
                html = "", toc = list(),
                message = "Bu belge görüntülenemiyor."))
  }

  path <- admin_doc_resolve_path(doc_id, root)
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    return(list(ok = FALSE, doc_id = doc_id, title = entry$title,
                source = entry$file, html = "", toc = list(),
                message = "Belge dosyası bulunamadı."))
  }

  content <- admin_doc_read_markdown(path)
  rendered <- admin_doc_render_markdown(content)

  list(ok = TRUE, doc_id = doc_id, title = entry$title, source = entry$file,
       html = admin_doc_rewrite_links(rendered$html, entry$file),
       toc = rendered$toc, message = "")
}

# Belge gövdesindeki bağlantılar uygulamadan ayrılmaz (Shiny oturumu kopardı):
# kayıtlı belgeye giden göreli bağlantı sayfa içinde o belgeyi açar
# (data-doc-id, izin listesiyle doğrulanır), dış adres yeni sekmede açılır,
# kayıtsız göreli yol (ör. .R şablonu) tıklanamaz metin olarak kalır.
# `#bolum` parçası korunur (data-doc-anchor): başlık kimliğiyle aynı ASCII
# slug'a çevrilir ve belge açıldıktan sonra o başlığa kaydırılır. `/` ile
# başlayan bağlantı depo kökünden çözülür; kökün üstüne çıkan yol açılmaz.
# Ham HTML bağlantıları da (tek/çift tırnak, öznitelik sırası) aynı kurala tabidir.
admin_doc_rewrite_links <- function(html, source_file) {
  if (!is.character(html) || length(html) != 1L || !nzchar(html)) return(html)
  # Etiket tarayıcısı tırnak duyarlıdır: `title="1 > 0"` içindeki ">" etiketi bitirmez.
  eslesme <- gregexpr("<a\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>|<a\\b[^>]*>", html, perl = TRUE, ignore.case = TRUE)
  etiketler <- regmatches(html, eslesme)[[1]]
  if (!length(etiketler)) return(html)
  kayitli <- list()
  for (g in admin_doc_registry()) for (d in g$docs) kayitli[[d$file]] <- d$id
  taban <- dirname(as.character(source_file %||% "")[1])
  regmatches(html, eslesme) <- list(vapply(etiketler, function(tam) {
    # Öznitelikler tırnak duyarlı ayrıştırılır: başka özniteliğin değerindeki
    # `href=` metni hedef sayılmaz ve silinmez.
    attrs <- admin_doc_parse_attrs(sub(">$", "", sub("^<a\\b", "", tam, perl = TRUE, ignore.case = TRUE)))
    adlar <- vapply(attrs, function(a) a$ad, character(1))
    if (!"href" %in% adlar) return(tam)
    href <- attrs[[match("href", adlar)]]$deger
    if (is.na(href)) href <- ""
    # href/target/rel yeniden yazılır, ping atılır; diğer öznitelikler (ör. title) korunur.
    kalan <- attrs[!adlar %in% c("href", "target", "rel", "ping")]
    yeni <- function(nitelik, cikar = character(0)) {
      diger <- admin_doc_attrs_html(Filter(function(a) !a$ad %in% cikar, kalan))
      paste0("<a ", nitelik, if (nzchar(diger)) paste0(" ", diger), ">")
    }
    if (grepl("^(https?|mailto):", href, ignore.case = TRUE)) {
      return(yeni(sprintf("href=\"%s\" target=\"_blank\" rel=\"noopener noreferrer\"",
                          gsub("\"", "&quot;", href, fixed = TRUE))))
    }
    ham <- sub("[?#].*$", "", href)
    parca <- if (grepl("#", href, fixed = TRUE)) sub("^[^#]*#", "", href) else ""
    capa <- ""
    if (nzchar(parca)) {
      cozulen <- try(utils::URLdecode(parca), silent = TRUE)
      if (inherits(cozulen, "try-error") || !validUTF8(cozulen)) cozulen <- parca
      Encoding(cozulen) <- "UTF-8"
      capa <- sprintf(" data-doc-anchor=\"%s\"", admin_doc_slugify(cozulen))
    }
    if (!nzchar(ham)) return(yeni(paste0("href=\"#\"", capa)))
    # commonmark boşluk ve ASCII dışı karakterleri yüzde kodlar; yol kayıt
    # defteriyle karşılaştırılmadan önce çözülür.
    ham_cozulen <- try(utils::URLdecode(ham), silent = TRUE)
    if (!inherits(ham_cozulen, "try-error") && validUTF8(ham_cozulen)) {
      Encoding(ham_cozulen) <- "UTF-8"
      ham <- ham_cozulen
    }
    kokten <- startsWith(ham, "/")
    parcalar <- strsplit(if (kokten || taban %in% c("", ".")) ham else paste(taban, ham, sep = "/"),
                         "/", fixed = TRUE)[[1]]
    yol <- character(0)
    tasti <- FALSE
    for (p in parcalar) {
      if (p %in% c("", ".")) next
      if (identical(p, "..") && !length(yol)) {
        tasti <- TRUE
        break
      }
      yol <- if (identical(p, "..")) utils::head(yol, -1L) else c(yol, p)
    }
    hedef <- paste(yol, collapse = "/")
    if (!tasti && !is.null(kayitli[[hedef]])) {
      return(yeni(sprintf("href=\"#\" data-doc-id=\"%s\"%s", kayitli[[hedef]], capa),
                  c("data-doc-id", "data-doc-anchor")))
    }
    goster <- if (tasti) ham else hedef
    # Yazarın sınıfı tek `class` özniteliğinde birleştirilir (yinelenen öznitelik yok).
    sinif <- Filter(function(a) identical(a$ad, "class") && !is.na(a$deger), kalan)
    sinif <- trimws(paste("mb-doc-link-offline", if (length(sinif)) sinif[[1]]$deger else ""))
    yeni(sprintf("class=\"%s\" title=\"%s\"", gsub("\"", "&quot;", sinif, fixed = TRUE),
                 htmltools::htmlEscape(paste("Uygulama içinde açılamaz:", goster), attribute = TRUE)),
         c("class", "title"))
  }, character(1), USE.NAMES = FALSE))
  html
}
