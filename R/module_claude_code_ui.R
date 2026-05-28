# ==============================================================================
# Dosya Yolu: R/module_claude_code_ui.R
# Açıklama: Bilge Yolaç sayfasının UI tanımını içerir.
#           Sunucu mantığı R/module_claude_code.R içinde kalır.
# ==============================================================================

claudeCodeUI <- function(id) {
  ns <- NS(id)

  # settings.json'dan model listesini oku ve katman etiketleriyle eşleştir
  ayarlar <- read_claude_settings_json()
  model_secenekleri <- ayarlar$models
  varsayilan_model <- ayarlar$default_model

  # Model katmanlarını oluştur
  katmanlar <- build_model_tier_choices(model_secenekleri)

  # Kısa etiketler ikon + isim, açıklama tooltip ile gösterilir
  model_degerleri <- setNames(
    sapply(katmanlar, function(k) k$deger),
    sapply(katmanlar, function(k) k$etiket)
  )

  # Açıklama ve ikon verilerini JavaScript'e iletmek için hazırla
  model_meta <- lapply(katmanlar, function(k) {
    list(
      deger = k$deger,
      etiket = k$etiket,
      ikon = k$ikon,
      aciklama = k$aciklama
    )
  })

  tagList(
    div(
      class = "claude-code-container",
      `data-character` = "emre",

      div(
        class = "chat-header settings-header-fixed",
        div(
          class = "chat-header-left",
          h4("Bilge Yolaç", class = "page-title"),
          tags$span(class = "cc-badge", "AJAN")
        ),
        div(
          class = "chat-header-right",
          uiOutput(ns("connection_status_badge"))
        )
      ),

      div(
        class = "cc-main-content",

        div(
          class = "cc-sidebar-panel",

          div(
            class = "cc-settings-card",
            h5(class = "cc-card-title", icon("folder-open"), "Proje Dizini"),

            div(
              class = "cc-workdir-row",
              textInput(
                ns("workdir"),
                label = NULL,
                value = claude_code_config$default_workdir,
                placeholder = "Proje klasör yolunu girin..."
              ),
              actionButton(
                ns("go_upload_folder"),
                label = NULL,
                icon = icon("folder-open"),
                class = "cc-browse-btn",
                title = "Yükleme klasörüne git"
              ),
              div(
                style = "display:none;",
                fileInput(ns("yerel_klasor"), label = NULL, multiple = TRUE)
              ),
              actionButton(
                ns("yerel_klasor_btn"),
                label = NULL,
                icon = icon("laptop"),
                class = "cc-browse-btn",
                title = "Yerel klasörü Bilge Yolaç çalışma alanına kopyala",
                onclick = sprintf(
                  "document.getElementById('%s').click();",
                  ns("yerel_klasor")
                )
              ),
              tags$script(HTML(sprintf("
$(function(){
  var fi = document.getElementById('%s');
  if(fi){
    fi.setAttribute('webkitdirectory','');
    fi.setAttribute('directory','');
    fi.addEventListener('change', function(e){
      var yollar = [];
      for(var i = 0; i < e.target.files.length; i++){
        yollar.push(e.target.files[i].webkitRelativePath || e.target.files[i].name);
      }
      Shiny.setInputValue('%s', JSON.stringify(yollar), {priority:'event'});
    });
  }
});", ns("yerel_klasor"), ns("yerel_klasor_yollar"))))
            ),

            div(
              class = "cc-model-select-wrapper",
              tags$label(class = "cc-select-label", "Model"),
              div(
                class = "cc-model-tier-group",
                lapply(model_meta, function(m) {
                  secili <- if (nzchar(varsayilan_model)) {
                    identical(m$deger, varsayilan_model)
                  } else {
                    identical(m$etiket, "Dengeli")
                  }

                  tags$button(
                    type = "button",
                    class = paste0(
                      "cc-model-tier-btn",
                      if (secili) " active" else ""
                    ),
                    `data-value` = m$deger,
                    `data-ikon` = m$ikon,
                    title = m$aciklama,
                    onclick = sprintf(
                      "document.querySelectorAll('.cc-model-tier-btn').forEach(function(b){b.classList.remove('active')});this.classList.add('active');Shiny.setInputValue('%s',this.getAttribute('data-value'),{priority:'event'});",
                      ns("model")
                    ),
                    tags$i(class = paste0("fas ", m$ikon)),
                    tags$span(m$etiket)
                  )
                })
              ),
				tags$script(HTML(sprintf(
				"
				(function() {
				  // Bilge Yolaç varsayılan model değeri yalnızca Shiny bağlantısı hazırken gönderilir.
				  // DOM hazır olsa bile SSO/varlık yükleme sırası nedeniyle Shiny.setInputValue gecikebilir.
				  var inputId = %s;
				  var defaultModel = %s;
				  var sent = false;

				  function sendDefaultModel() {
					if (sent) return true;

					if (window.Shiny && typeof window.Shiny.setInputValue === 'function') {
					  window.Shiny.setInputValue(inputId, defaultModel, { priority: 'event' });
					  sent = true;
					  return true;
					}

					return false;
				  }

				  if (!sendDefaultModel()) {
					$(document).one('shiny:connected', sendDefaultModel);
				  }
				})();
				",
				  jsonlite::toJSON(ns("model"), auto_unbox = TRUE),
				  jsonlite::toJSON(
					if (nzchar(varsayilan_model)) varsayilan_model else "",
					auto_unbox = TRUE
				  )
				)))
            )
          ),

          div(
            class = "cc-settings-card cc-scenarios-card",
            h5(class = "cc-card-title", icon("bolt"), "Hazır Senaryolar"),
            div(
              class = "cc-scenario-grid",
              lapply(claude_code_scenarios, function(senaryo) {
                actionButton(
                  ns(paste0("scenario_", senaryo$id)),
                  label = tagList(
                    icon(senaryo$ikon),
                    span(senaryo$baslik)
                  ),
                  class = "cc-scenario-btn",
                  title = senaryo$aciklama
                )
              })
            )
          ),

          div(
            class = "cc-settings-card cc-dir-card",
            h5(class = "cc-card-title", icon("folder-tree"), "Dizin İçeriği"),
            div(
              class = "cc-dir-nav",
              actionButton(
                ns("dir_go_up"),
                label = NULL,
                icon = icon("arrow-up"),
                class = "btn-sm cc-dir-up-btn",
                title = "Üst dizine git"
              ),
              span(
                id = ns("dir_current_path"),
                class = "cc-dir-current-path"
              ),
              actionButton(
                ns("refresh_dir"),
                label = NULL,
                icon = icon("sync"),
                class = "btn-sm cc-refresh-btn",
                title = "Yenile"
              )
            ),
            uiOutput(ns("dir_contents_ui"))
          ),

          claudeCodePluginsUI(ns)
        ),

        div(
          class = "cc-terminal-panel",

          div(
            class = "cc-output-wrapper",
            div(
              id = ns("welcome_screen"),
              class = "cc-welcome-screen cc-welcome-active"
            ),
            div(
              id = ns("output_area"),
              class = "cc-output-area"
            )
          ),

          div(
            id = ns("thinking_overlay"),
            class = "cc-thinking-mini cc-hidden",
            tags$canvas(
              id = ns("pixel_canvas"),
              class = "cc-pixel-canvas-mini",
              width = "48",
              height = "48"
            ),
            div(
              id = ns("thinking_text"),
              class = "cc-thinking-text-mini"
            )
          ),

          div(
            class = "cc-input-area",
            div(
              class = "cc-input-wrapper",
              tags$textarea(
                id = ns("prompt_input"),
                class = "cc-prompt-input",
                placeholder = "Bilge Yolaç'a bir komut yazın...",
                rows = 3
              ),
              div(
                class = "cc-input-actions",
                uiOutput(ns("active_character_indicator")),
                actionButton(
                  ns("clear_output"),
                  label = NULL,
                  icon = icon("eraser"),
                  class = "cc-action-btn cc-clear-btn",
                  title = "Çıktıyı Temizle"
                ),
                actionButton(
                  ns("stop_command"),
                  label = tagList(icon("stop"), "Durdur"),
                  class = "cc-stop-btn cc-hidden",
                  title = "İşlemi durdur"
                ),
                actionButton(
                  ns("run_command"),
                  label = tagList(icon("play"), "Çalıştır"),
                  class = "cc-run-btn"
                )
              )
            ),
            div(
              class = "cc-status-bar",
              span(id = ns("status_text"), class = "cc-status-text"),
              span(id = ns("duration_text"), class = "cc-duration-text")
            )
          )
        )
      )
    )
  )
}