# R/helpers_preview.R

init_docx_preview_js <- function(session) {
  shinyjs::runjs("
    (function(){
      // Aynı sayfada ikinci kez handler kaydetme
      if (window.__docxPreviewInit) return;
      window.__docxPreviewInit = true;

      // Mammoth kütüphanesini oturum başlangıcında önceden yükle
      // (ilk DOCX önizlemede bekleme süresini ortadan kaldırır)
      if (!window.mammoth && !document.getElementById('mammoth_preload_script')) {
        var _s = document.createElement('script');
        _s.id = 'mammoth_preload_script';
        _s.src = 'lib/mammoth/mammoth.browser.min.js?v=20260416';
        document.head.appendChild(_s);
      }

      function ensureMammoth(cb, onFail){
        if (window.mammoth) {
          cb && cb();
          return;
        }

        // Mammoth modal açılırken sayfaya script olarak eklenecek.
        // Burada yalnızca hazır olmasını bekliyoruz.
        var startedAt = Date.now();
        var timer = setInterval(function(){
          if (window.mammoth) {
            clearInterval(timer);
            cb && cb();
            return;
          }

          if ((Date.now() - startedAt) >= 5000) {
            clearInterval(timer);
            onFail && onFail();
          }
        }, 100);
      }

      // base64 -> ArrayBuffer çevirimi
      function b64ToArrayBuffer(b64) {
        var binary = atob(b64), len = binary.length, bytes = new Uint8Array(len);
        for (var i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i);
        return bytes.buffer;
      }

      // iframe için minimal tema
      var DOCX_CSS = [
        'html,body{margin:0;padding:16px;background:#fff;color:#111;font:14px/1.5 -apple-system,Segoe UI,Roboto,Arial,sans-serif;overflow:hidden;}',
        'p{margin:0 0 8px 0;} h1,h2,h3,h4,h5,h6{color:#111;margin:12px 0 8px 0;}',
        'ul,ol{margin:6px 0 8px 26px;} li{margin:4px 0;}',
        'table{border-collapse:collapse;width:100%;margin:8px 0;}',
        'th,td{border:1px solid #ddd;padding:6px;vertical-align:top;}',
        'img{max-width:100%;height:auto;} figure{margin:8px 0;}',
        '.mammoth-header,.mammoth-footer{opacity:.8;font-size:12px;margin:6px 0;}'
      ].join('\\n');

      function renderIntoIframe(target, html) {
        var iframe = target.__docxFrame;
        if (!iframe) {
          iframe = document.createElement('iframe');
          iframe.setAttribute('sandbox','allow-same-origin');
          iframe.setAttribute('scrolling','no');
          iframe.style.overflow = 'hidden';
          iframe.style.width = '100%';
          iframe.style.minHeight = '60vh';
          iframe.style.border = '0';
          target.innerHTML = '';
          target.appendChild(iframe);
          target.__docxFrame = iframe;
        }

        var doc = iframe.contentDocument;
        doc.open();
        doc.write('<!doctype html><html><head><meta charset=\"utf-8\"><style>' + DOCX_CSS + '</style></head><body>' + html + '</body></html>');
        doc.close();

        setTimeout(function(){
          try{
            var h = Math.max(iframe.contentDocument.body.scrollHeight, 500);
            iframe.style.height = h + 'px';
          }catch(_){}
        }, 50);
      }

      Shiny.addCustomMessageHandler('openDocxPreview', function(payload) {
        var targetId = payload.targetId || 'docx_preview_container';
        var target = document.getElementById(targetId);
        if (!target) return;

        target.innerHTML = '<div style=\"padding:8px;font-size:12px;opacity:.7\">Yükleniyor…</div>';

        ensureMammoth(function(){
          try{
            var opts = {
              convertImage: mammoth.images.inline(function(elem){
                return elem.read('base64').then(function(image){
                  return {src: 'data:' + image.contentType + ';base64,' + image.data};
                });
              }),
              includeDefaultStyleMap: true,
              styleMap: [
                'p[style-name=\"Normal\"] => p:fresh',
                'table => table',
                'r[style-name=\"Hyperlink\"] => a',
                'p[style-name=\"Heading 1\"] => h1:fresh',
                'p[style-name=\"Heading 2\"] => h2:fresh'
              ]
            };

            mammoth.convertToHtml({ arrayBuffer: b64ToArrayBuffer(payload.base64) }, opts)
              .then(function(result){
                renderIntoIframe(target, result.value);
              })
              .catch(function(err){
                target.innerHTML = '<div style=\"color:#f87171\">DOCX dönüştürülemedi: ' +
                  (err && err.message ? err.message : err) + '</div>';
              });
          } catch (e) {
            target.innerHTML = '<div style=\"color:#f87171\">Dönüştürme hatası: ' + e + '</div>';
          }
        }, function(){
          target.innerHTML = '<div style=\"color:#f87171\">mammoth.js yüklenemedi. Yerel dosya bulunamadı.</div>';
        });
      });
    })();
  ")
}

openAnyPreview <- function(file_info, session, filePreview) {
  # PDF modu: DOCX -> PDF dönüştür ve PDF'i aç
  # HTML modu: doğrudan filePreview (mammoth ile JS tarafında)
  # Türkçe açıklamalar eklendi

  # Güvenlik: path/isim ayıkla
  # not: bazı akışlarda 'datapath' yoksa 'path' bulunur
  path0 <- file_info$datapath %||% file_info$path %||% ""
  name0 <- file_info$name %||% basename(path0)

  # Mod belirle
  mode <- getOption("mergen.word_preview_mode", "html")

  # DOCX uzantı kontrolü
  ext <- tolower(tools::file_ext(name0))
  is_docx <- ext %in% c("docx","doc","docm")

  if (identical(mode, "pdf") && is_docx) {
    # DOCX -> PDF dönüştürme
    # not: convert_docx_to_pdf global.R içinde tanımlı
    # not: aynı isimli PDF varsa tekrar kullan (hız)
    try({
      # hedef PDF yolu
      if (!path_exists_relaxed(path0)) stop(sprintf("Kaynak DOCX bulunamadı: %s", path0))
      pdf_path_guess <- sub("\\.docx$|\\.docm$|\\.doc$", ".pdf", path0, ignore.case = TRUE)
      if (!path_exists_relaxed(pdf_path_guess)) {
        # yoksa dönüştür
        pdf_path_guess <- convert_docx_to_pdf(path0)  # hata verirse catch'e düşer
      }
      if (!path_exists_relaxed(pdf_path_guess)) stop(sprintf("PDF üretilemedi: %s", pdf_path_guess))

      # PDF için yeni file_info oluştur
      pdf_info <- list(
        name     = basename(pdf_path_guess),
        datapath = pdf_path_guess,
        size     = tryCatch(file.info(pdf_path_guess)$size, error = function(e) NA_real_)
      )

      # Önizlemeyi PDF ile aç
      filePreview$open(pdf_info)   # not: artık doğru yolu gönderiyoruz
      return(invisible(TRUE))
    }, silent = TRUE)
    # Dönüşüm başarısız ise HTML yoluna düş
  }

  # Varsayılan: mevcut davranış (HTML / mammoth)
  filePreview$open(file_info)
  invisible(TRUE)
}

# İstemciden gelen '&&' ipucu parçalarının güvenli olup olmadığını denetler.
# '..', '.', mutlak yol, sürücü harfi ve yol ayırıcı içeren parçalar reddedilir.
.preview_hint_parts_safe <- function(parts) {
  parts <- as.character(parts %||% character(0))
  if (!length(parts)) return(FALSE)

  all(vapply(parts, function(p) {
    p <- trimws(as.character(p)[1])
    if (is.na(p) || !nzchar(p)) return(FALSE)
    if (p %in% c(".", "..")) return(FALSE)
    if (grepl("[/\\\\]", p, perl = TRUE)) return(FALSE)
    if (grepl("^[A-Za-z]:", p, perl = TRUE)) return(FALSE)
    TRUE
  }, logical(1)))
}

# Çözülen adayın gerçekten kökün İÇİNDE kaldığını doğrular.
# Aday ve kök AYNI normalleştiriciden geçmelidir. `handle_source_file_click()`
# (b2) yolunu ham `api_config$local_model_paths` değerinden kurar; iki tarafı
# ayrı `normalizePath()` çağrılarıyla çözmek Windows'ta UNC ile eşlenmiş sürücü
# gösterimlerini farklı döndürebiliyor ve GEÇERLİ bir isabet kapsama denetiminde
# düşüyordu. `normalize_mcp_path()` UNC biçimini korur.
.preview_path_inside <- function(path, root) {
  norm <- function(x) {
    ham <- as.character(x)[1]
    x <- if (exists("normalize_mcp_path", mode = "function", inherits = TRUE)) {
      tryCatch(normalize_mcp_path(ham), error = function(e) ham)
    } else {
      tryCatch(
        normalizePath(ham, winslash = "/", mustWork = FALSE),
        error = function(e) ham
      )
    }
    x <- gsub("\\", "/", as.character(x)[1], fixed = TRUE)
    sub("/+$", "", x, perl = TRUE)
  }

  hedef <- norm(path)
  kok <- norm(root)
  if (!nzchar(hedef) || !nzchar(kok)) return(FALSE)

  # normalizePath var olmayan yollarda '..' segmentlerini sadeleştirmez;
  # sadeleşmemiş geçiş segmenti kalan yol reddedilir.
  if (grepl("(^|/)\\.\\.(/|$)", hedef, perl = TRUE)) return(FALSE)

  if (.Platform$OS.type == "windows") {
    hedef <- tolower(hedef)
    kok <- tolower(kok)
  }

  identical(hedef, kok) || startsWith(hedef, paste0(kok, "/"))
}

handle_source_file_click <- function(event_payload, settings_data, api_config, session, filePreview) {
  # Ham tıklama değeri (Kaynakça'daki data-filename olabilir; '&&' ile ipucu içerebilir)
  raw_hint <- if (is.character(event_payload)) event_payload[1] else (event_payload$filename %||% event_payload$name %||% "")
  log_info("[SRC_CLICK] alındı: raw='{raw_hint}'")

  # Çözümleme kapsamı: ortak oturum odalarındaki kaynaklar scope="model_bases"
  # taşır; bu durumda KİŞİSEL kullanıcı kovası çözümlemesi ATLANIR ve dosya
  # yalnızca kurumsal model taban klasörlerinde aranır. Böylece bir katılımcının
  # oluşturduğu atıf, tıklayan başka bir katılımcının kişisel dosyalarına
  # çözümlenemez (çapraz-kullanıcı sızıntısı önlenir). Diğer tüm çağrılar
  # (tekil sohbet) varsayılan "personal" kapsamıyla mevcut davranışı korur.
  click_scope <- if (is.list(event_payload)) as.character(event_payload$scope %||% "")[1] else ""
  model_bases_only <- identical(click_scope, "model_bases")

  # Not: TAM ipucunu koru; basename'e düşme ancak en sonda yedek olarak kullanılacak
  parts <- strsplit(raw_hint, "&&", fixed = TRUE)[[1]]
  parts <- trimws(parts); parts <- parts[nzchar(parts)]
  last_part     <- if (length(parts)) tail(parts, 1) else raw_hint
  filename_full <- trimws(raw_hint)
  filename_base <- trimws(basename(last_part))

  log_debug("[SRC_CLICK] filename_full='{filename_full}' | filename_base='{filename_base}' | hint_parts_n={length(parts)}")

  # (Opsiyonel) seçili modeli sadece günlük için oku (rezolüsyonda kullanılmıyor)
  current_model <- tryCatch({ as.character(isolate(settings_data$model_selection))[1] }, error = function(e) NA_character_)
  if (!nzchar(current_model)) current_model <- as.character(api_config$local_models[1] %||% "")
  log_info("[SRC_CLICK] aktif model (günlük): '{current_model}'")

  # Tüm model baz klasörlerini tek listeye topla (teknik ad -> yol eşleşmeleri)
  collect_model_bases <- function(local_paths) {
    if (is.null(local_paths)) return(character(0))
    if (is.list(local_paths)) {
      vals <- unlist(local_paths, use.names = FALSE)
    } else if (is.atomic(local_paths)) {
      vals <- as.character(local_paths)
    } else {
      vals <- character(0)
    }
    unique(Filter(function(x) is.character(x) && length(x) == 1 && nzchar(x), vals))
  }
  all_bases <- collect_model_bases(api_config$local_model_paths)
  log_debug("[SRC_CLICK] base_count={length(all_bases)}")

  # --- ÇÖZÜMLEME STRATEJİSİ ---
  # (a) Önce kullanıcı kovası (tam ipucu -> basename)
  # (b) Ardından TÜM model bazlarında '&&' ipucunu kullanarak doğrudan göreli yolu dene,
  #     bulunamazsa aynı baz altında indeksli/rekürsif dosya adı araması yap
  # (c) En son küresel önbellek (index.json) üzerinden çözümle (tam ipucu -> basename)

  found_path <- NULL

  # (a) Kullanıcı kovası - önce TAM adla dene, sonra basename.
  # model_bases_only kapsamında (ortak oturum) bu adım tamamen atlanır.
  uid <- session$userData$user_id %||% NULL
  if (!model_bases_only && !is.null(uid)) {
    log_debug("[SRC_CLICK] (a) kullanıcı kovası aranıyor\U2026 user_id={uid}")
	cand_user_full <- try(
	  resolve_uploaded_file(
		filename_full,
		user_id = uid
	  ),
	  silent = TRUE
	)
    if (!inherits(cand_user_full, "try-error") && !is.null(cand_user_full) && path_exists_relaxed(cand_user_full)) {
      found_path <- normalizePath(cand_user_full, winslash = "/", mustWork = FALSE)
      log_info("[SRC_CLICK] kullanıcı kovasında (TAM ad) bulundu -> {found_path}")
    } else {
		cand_user_base <- try(
		  resolve_uploaded_file(
			filename_base,
			user_id = uid
		  ),
		  silent = TRUE
		)
      if (!inherits(cand_user_base, "try-error") && !is.null(cand_user_base) && path_exists_relaxed(cand_user_base)) {
        found_path <- normalizePath(cand_user_base, winslash = "/", mustWork = FALSE)
        log_info("[SRC_CLICK] kullanıcı kovasında (basename) bulundu -> {found_path}")
      }
    }
  }

  # (b) Tüm model bazları + '&&' yol ipucu
  if (is.null(found_path) && length(all_bases) > 0) {
    rel_parts <- if (length(parts) > 1) parts[seq_len(length(parts) - 1)] else character(0)

    for (base_dir in all_bases) {
      # 1) İpucuyla (A&&B&&C) indeks üzerinden adayları puanlayarak ara
      log_debug("[SRC_CLICK] (b1) ipucu ile arama: base='{base_dir}', hint='{filename_full}'")
      cand_hint <- try(search_file_in_folder(base_dir, filename_full), silent = TRUE)
      if (!inherits(cand_hint, "try-error") && !is.null(cand_hint) && file.exists(cand_hint)) {
        found_path <- normalizePath(cand_hint, winslash = "/", mustWork = FALSE)
        log_info("[SRC_CLICK] (b1) ipucu ile bulundu -> {found_path}")
        break
      }

      # 2) İpuçları direkt göreli yol oluşturuyorsa onu dene.
      #    İpucu parçaları İSTEMCİDEN gelir: doğrulanmadan birleştirildiğinde
      #    '..', mutlak yol veya sürücü harfi ile model baz klasörünün dışına
      #    çıkılabiliyordu. Parçalar süzülür ve sonuç kök içinde doğrulanır.
      if (length(rel_parts) > 0 && .preview_hint_parts_safe(c(rel_parts, last_part))) {
        candidate_rel <- tryCatch(
          normalizePath(do.call(file.path, as.list(c(base_dir, rel_parts, last_part))), winslash = "/", mustWork = FALSE),
          error = function(e) do.call(file.path, as.list(c(base_dir, rel_parts, last_part)))
        )
        if (.preview_path_inside(candidate_rel, base_dir) && path_exists_relaxed(candidate_rel)) {
          found_path <- candidate_rel
          log_info("[SRC_CLICK] (b2) ipucu ile direkt bulundu -> {found_path}")
          break
        }
      }

      # 3) Son çare: sadece dosya adına göre arama
      log_debug("[SRC_CLICK] (b3) rekürsif dosya adı araması: base='{base_dir}', name='{filename_base}'")
      candidate_scan <- try(search_file_in_folder(base_dir, filename_base), silent = TRUE)
      if (!inherits(candidate_scan, "try-error") && !is.null(candidate_scan) && path_exists_relaxed(candidate_scan)) {
        found_path <- normalizePath(candidate_scan, winslash = "/", mustWork = FALSE)
        log_info("[SRC_CLICK] (b3) rekürsif aramada bulundu -> {found_path}")
        break
      }
    }
  }

	# (c) Genel index / çapraz kullanıcı çözümleme güvenlik nedeniyle kapalıdır.
	# Kaynak dosya ya kullanıcının kendi kovasında ya da model baz klasörlerinde bulunmalıdır.
	if (is.null(found_path)) {
	  log_debug("[SRC_CLICK] genel index fallback atlandı; cross-user dosya çözümleme kapalı.")
	}

  # Son durum: bulunamadıysa kullanıcıya bildir
  if (is.null(found_path)) {
    log_error("[SRC_CLICK] dosya bulunamadı: '{filename_base}' | raw='{raw_hint}'")
    showToast(session, paste("Dosya bulunamadı:", filename_base), "error")
    return(invisible(NULL))
  }

  # Önizlemeyi aç
  file_info <- list(
    name     = basename(found_path),
    datapath = found_path,
    size     = suppressWarnings(file.info(found_path)$size)
  )
  log_info("[SRC_CLICK] önizleme açılıyor: {found_path}")
  openAnyPreview(file_info, session, filePreview)
}