# R/module_health.R

healthUI <- function(id) {
  ns <- NS(id)
  tagList(
    div(
      class = "health-container",
      fluidRow(
        column(
          width = 12,
          div(
            class = "chat-header settings-header-fixed",
            div(
              class = "chat-header-left",
			  h4("Sistem Durumu", class = "page-title"),
              span(class = "admin-badge", icon("shield-alt"), "ADMIN")
            ),
            div(
              class = "chat-header-right",
              # IMPORTANT: keep this id UN-namespaced because your JS updates it by id
              span(id = "last_update_time",
                   style = "color: #999; margin-right: 15px; font-size: 14px;", 
                   "Son Güncelleme: --"),
              actionButton(
                ns("refresh_health"),
                label = tagList(icon("sync-alt"), "Yenile"),
                class = "btn-modern btn-primary"
              )
            )
          )
        )
      ),
      div(
        class = "settings-scrollable-content",
        fluidRow(
          class = "health-cards-row",
          column(
            width = 6,
            class = "health-column",
            div(
              class = "settings-card health-card",
              h3(tagList(icon("database"), " Veritabanı Bağlantı Havuzu"), class = "settings-title"),
              div(class = "health-content", uiOutput(ns("health_db_pool")))
            ),
            div(
              class = "settings-card health-card",
              style = "margin-top: 20px;",
              h3(tagList(icon("cogs"), " İşçi Havuzu (Workers)"), class = "settings-title"),
              div(class = "health-content", uiOutput(ns("health_workers")))
            )
          ),
          column(
            width = 6,
            class = "health-column",
            div(
              class = "settings-card health-card",
              h3(tagList(icon("tachometer-alt"), " Performans Metrikleri"), class = "settings-title"),
              div(class = "health-content", uiOutput(ns("health_performance")))
            ),
            div(
              class = "settings-card health-card",
              style = "margin-top: 20px;",
              h3(tagList(icon("shield-alt"), " Hız Sınırlama Durumu"), class = "settings-title"),
              div(class = "health-content", uiOutput(ns("health_rate_limits")))
            )
		# Mevcut Rate Limits kartından sonra, aynı fluidRow içinde:
		),  # Rate Limits kartının kapanışı
		column(
		  width = 6,
		  class = "health-column",
		  div(
			class = "settings-card health-card",  # Diğer kartlarla aynı dış stil
			style = "margin-top: 20px;",  # Üstteki kartla aynı boşluk
			h3(tagList(icon("server"), " Sistem Kaynakları"), class = "settings-title"),
			div(class = "health-content", uiOutput(ns("health_system_resources")))
		  )
		)
        )
      )
    )
  )
}

healthServer <- function(id, perf_tracker) {
  moduleServer(id, function(input, output, session) {
    # ===== moved from server.R =====
    health_refresh_trigger <- reactiveVal(0)
    health_last_update <- reactiveVal(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
    
    # Auto-refresh every 30s
    observe({
      invalidateLater(30000)
      isolate({
        health_refresh_trigger(health_refresh_trigger() + 1)
        health_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
        session$sendCustomMessage("updateHealthTimestamp", list(time = health_last_update()))
      })
    })
    
    output$health_db_pool <- renderUI({
      health_refresh_trigger()
      pool_info <- get_pool_info()
      if (!is.null(pool_info) && !isFALSE(pool_info$valid)) {
        HTML(sprintf(
          '<div style="line-height: 2;">
            <span style="color: #60a5fa;">Durum:</span> <span style="color: #4ade80;">\U00002713 SAĞLIKLI</span><br>
            <span style="color: #60a5fa;">Bağlantı Modu:</span> <span style="color: #fff;">%s</span><br><br>
            <span style="color: #94a3b8;">%s</span>
          </div>',
          pool_info$mode %||% "Bilinmiyor",
          pool_info$note %||% ""
        ))
      } else {
        HTML(sprintf(
          '<div style="line-height: 2;">
            <span style="color: #f87171;">\U00002717 Veritabanı bağlantısı kurulamadı</span><br>
            <span style="color: #94a3b8;">Hata: %s</span>
          </div>',
          pool_info$error %||% "Bilinmeyen hata"
        ))
      }
    })
    
    output$health_workers <- renderUI({
      health_refresh_trigger()
      worker_info <- monitor_workers()
      active_workers <- worker_info$total_workers - worker_info$free_workers
      usage_pct <- (active_workers / worker_info$total_workers) * 100
      HTML(sprintf(
        '<div style="line-height: 2;">
          <span style="color: #60a5fa;">Toplam İşçi:</span> <span style="color: #fff;">%d</span><br>
          <span style="color: #60a5fa;">Boş İşçi:</span> <span style="color: #fff;">%d</span><br>
          <span style="color: #60a5fa;">Aktif İşçi:</span> <span style="color: #fff;">%d</span><br>
          <span style="color: #60a5fa;">Kullanım Oranı:</span> <span style="color: #fff;">%.1f%%</span>
        </div>',
        worker_info$total_workers,
        worker_info$free_workers,
        active_workers,
        usage_pct
      ))
    })
    
    output$health_performance <- renderUI({
      health_refresh_trigger()
      total <- isolate(perf_tracker$stats$total_requests)
      avg_time <- isolate(perf_tracker$stats$avg_response_time)
      errors <- isolate(perf_tracker$stats$error_count)
      active_users <- isolate(perf_tracker$stats$active_users)
      
      error_rate <- if (total > 0) (errors / total) * 100 else 0
      status_icon <- if (error_rate < 5) "\U00002713" else if (error_rate < 10) "\U000026A0" else "\U00002717"
      status_text <- if (error_rate < 5) "SAĞLIKLI" else if (error_rate < 10) "UYARI" else "KRİTİK"
      status_color <- if (error_rate < 5) "#4ade80" else if (error_rate < 10) "#fbbf24" else "#f87171"
      
      HTML(sprintf(
        '<div style="line-height: 2;">
          <span style="color: #60a5fa;">Genel Durum:</span> <span style="color: %s; font-weight: bold;">%s %s</span><br><br>
          <span style="color: #60a5fa;">Toplam İstek:</span> <span style="color: #fff;">%d</span><br>
          <span style="color: #60a5fa;">Ortalama Yanıt Süresi:</span> <span style="color: #fff;">%.2f saniye</span><br>
          <span style="color: #60a5fa;">Hata Sayısı:</span> <span style="color: #fff;">%d</span><br>
          <span style="color: #60a5fa;">Hata Oranı:</span> <span style="color: #fff;">%.2f%%</span><br>
          <span style="color: #60a5fa;">Aktif Kullanıcı:</span> <span style="color: #fff;">%d</span>
        </div>',
        status_color, status_icon, status_text,
        total, avg_time, errors, error_rate, active_users
      ))
    })
    
    output$health_rate_limits <- renderUI({
      health_refresh_trigger()
      current_time <- Sys.time()
      
      # Clean per-user rate limiter
      user_keys <- ls(envir = rate_limiter$requests)
      active_user_count <- 0
      for (key in user_keys) {
        user_reqs <- rate_limiter$requests[[key]]
        active_reqs <- Filter(function(t) {
          difftime(current_time, t, units = "secs") < rate_limiter$window_size
        }, user_reqs)
        rate_limiter$requests[[key]] <- active_reqs
        if (length(active_reqs) > 0) active_user_count <- active_user_count + 1
      }
      
      # Clean global rate limiter
      active_global <- Filter(function(t) {
        difftime(current_time, t, units = "secs") < global_rate_limiter$window_size
      }, global_rate_limiter$requests)
      global_rate_limiter$requests <<- active_global
      global_count <- length(active_global)
      global_usage_pct <- (global_count / global_rate_limiter$max_total_requests) * 100
      
      HTML(sprintf(
        '<div style="line-height: 2;">
          <span style="color: #a78bfa; font-weight: bold;">Kullanıcı Başına Limit:</span><br>
          <span style="color: #60a5fa; margin-left: 10px;">Limit:</span> <span style="color: #fff;">%d istek / %d saniye</span><br>
          <span style="color: #60a5fa; margin-left: 10px;">Aktif Kullanıcı:</span> <span style="color: #fff;">%d</span><br><br>
          <span style="color: #a78bfa; font-weight: bold;">Genel Limit:</span><br>
          <span style="color: #60a5fa; margin-left: 10px;">Limit:</span> <span style="color: #fff;">%d istek / %d saniye</span><br>
          <span style="color: #60a5fa; margin-left: 10px;">Aktif İstek:</span> <span style="color: #fff;">%d</span><br>
          <span style="color: #60a5fa; margin-left: 10px;">Kullanım:</span> <span style="color: #fff;">%.1f%%</span>
        </div>',
        rate_limiter$max_requests_per_user, rate_limiter$window_size, active_user_count,
        global_rate_limiter$max_total_requests, global_rate_limiter$window_size,
        global_count, global_usage_pct
      ))
    })
	
	# Sistem kaynaklarını göster (disk, bellek, oturum bilgisi)
	output$health_system_resources <- renderUI({
	  health_refresh_trigger()
	  
	  # Disk bilgisi - uygulama dizini için platform-bağımsız yaklaşım
	  app_dir <- getwd()
	  disk_info <- tryCatch({
		if (.Platform$OS.type == "windows") {
		  # Windows için disk bilgisi (wmic komutu)
		  drive_letter <- substr(app_dir, 1, 2)
		  wmic_cmd <- sprintf('wmic logicaldisk where "DeviceID=\'%s\'" get Size,FreeSpace /format:list', drive_letter)
		  wmic_output <- system(wmic_cmd, intern = TRUE, ignore.stderr = TRUE)
		  
		  # Parse output
		  free_bytes <- as.numeric(gsub("FreeSpace=", "", grep("FreeSpace=", wmic_output, value = TRUE)[1]))
		  total_bytes <- as.numeric(gsub("Size=", "", grep("Size=", wmic_output, value = TRUE)[1]))
		  
		  if (!is.na(free_bytes) && !is.na(total_bytes) && total_bytes > 0) {
			used_bytes <- total_bytes - free_bytes
			usage_pct <- round((used_bytes / total_bytes) * 100, 1)
			list(
			  available = sprintf("%.1f GB", free_bytes / (1024^3)),
			  total = sprintf("%.1f GB", total_bytes / (1024^3)),
			  usage_pct = usage_pct
			)
		  } else {
			list(available = "N/A", total = "N/A", usage_pct = 0)
		  }
			} else {
			  # Linux/Mac için df komutu ile disk bilgisi
			  df_cmd <- sprintf("df -h '%s' 2>/dev/null | tail -1", app_dir)
			  df_output <- system(df_cmd, intern = TRUE)

			  if (length(df_output) > 0 && nzchar(df_output)) {
					# Boşluklara göre ayır (birden fazla boşluk olabilir)
					parts <- unlist(strsplit(trimws(df_output), "\\s+"))
					parts <- parts[parts != ""]

					# Tipik df çıktısı: Filesystem Size Used Avail Use% Mounted
					if (length(parts) >= 5) {
					  usage_val <- suppressWarnings(as.numeric(sub("%", "", parts[5])))
					  if (is.na(usage_val)) usage_val <- 0
					  list(
							available = parts[4],  # Kullanılabilir alan
							total = parts[2],      # Toplam alan
							usage_pct = round(usage_val)
					  )
					} else {
					  list(available = "N/A", total = "N/A", usage_pct = 0)
					}
			  } else {
					list(available = "N/A", total = "N/A", usage_pct = 0)
			  }
			}
	  }, error = function(e) {
		cat("[HEALTH] Disk bilgisi alınamadı:", conditionMessage(e), "\n")
		list(available = "N/A", total = "N/A", usage_pct = 0)
	  })
	  
	  # Bellek bilgisi
	  mem_info <- tryCatch({
		mem_used_mb <- as.numeric(pryr::mem_used()) / 1024^2
		sprintf("%.1f MB", mem_used_mb)
	  }, error = function(e) {
		"N/A"
	  })
	  
	  # Oturum bilgisi
	  session_count <- tryCatch({
		length(ls(envir = .GlobalEnv, pattern = "^session"))
	  }, error = function(e) { 1 })
	  
	  r_version <- paste0(R.version$major, ".", R.version$minor)
	  
	  # DuckDB bağlantı durumu
	  duckdb_status <- tryCatch({
		if (exists("helpers_rdata_lake", mode = "list")) {
		  if (file.exists(helpers_rdata_lake$db_path)) {
			db_size <- file.size(helpers_rdata_lake$db_path) / 1024^2
			sprintf("\U00002713 Aktif (%.1f MB)", db_size)
		  } else {
			"\U25CB Hazır değil"
		  }
		} else {
		  "\U25CB Yüklenmedi"
		}
	  }, error = function(e) {
		"\U00002717 Hata"
	  })
	  
	  HTML(sprintf(
		'<div style="line-height: 1.8;">
		  <span style="color: #a78bfa; font-weight: bold;">Disk Kullanımı:</span><br>
		  <span style="color: #60a5fa; margin-left: 10px;">Toplam:</span> <span style="color: #fff;">%s</span><br>
		  <span style="color: #60a5fa; margin-left: 10px;">Kullanılabilir:</span> <span style="color: #fff;">%s</span><br>
		  <span style="color: #60a5fa; margin-left: 10px;">Doluluk:</span> <span style="color: #fff;">%d%%</span><br><br>
		  
		  <span style="color: #a78bfa; font-weight: bold;">Bellek & Oturum:</span><br>
		  <span style="color: #60a5fa; margin-left: 10px;">R Bellek Kullanımı:</span> <span style="color: #fff;">%s</span><br>
		  <span style="color: #60a5fa; margin-left: 10px;">R Sürümü:</span> <span style="color: #fff;">%s</span><br>
		  <span style="color: #60a5fa; margin-left: 10px;">Aktif Oturum:</span> <span style="color: #fff;">%d</span><br><br>
		  
		  <span style="color: #a78bfa; font-weight: bold;">RData Lake:</span><br>
		  <span style="color: #60a5fa; margin-left: 10px;">DuckDB Durumu:</span> <span style="color: #fff;">%s</span>
		</div>',
		disk_info$total, disk_info$available, disk_info$usage_pct,
		mem_info, r_version, session_count,
		duckdb_status
	  ))
	})
    
    observeEvent(input$refresh_health, {
      health_refresh_trigger(health_refresh_trigger() + 1)
      health_last_update(format(Sys.time(), "%d.%m.%Y %H:%M:%S"))
      session$sendCustomMessage("updateHealthTimestamp", list(time = health_last_update()))
      showToast(session, "Sistem durumu güncellendi", "success")
    })
    # ===== end moved block =====
  })
}