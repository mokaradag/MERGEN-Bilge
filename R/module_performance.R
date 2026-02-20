# ==============================================================================
# R/module_performance.R
# Dosya Yolu: R/module_performance.R
# Açıklama: Shiny uygulaması için performans takip modülü.
# Aktif kullanıcı sayısı, toplam istek, ortalama yanıt süresi ve hata
# sayılarını izler; performans optimizasyonu için belirli aralıklarla diske kaydeder.
# ==============================================================================

performanceStatsServer <- function(id, current_user_id) {
  moduleServer(id, function(input, output, session) {
    
    # --- PERFORMANS İSTATİSTİKLERİ ---
    # Başlangıç değerlerini atayarak reaktif değişkenleri oluşturur
    stats <- reactiveValues(
      active_users = 1,
      total_requests = 0,
      avg_response_time = 0,
      error_count = 0,
      last_request_time = NULL,
      uptime_start = Sys.time()
    )
    
    # İstatistiklerin kaydedileceği dosya yolu
    stats_file <- "logs/performance_stats.txt"
    
    # --- MEVCUT İSTATİSTİKLERİ YÜKLEME ---
    # Uygulama başladığında diske kaydedilmiş eski verileri okur (isolate içinde)
    isolate({
      if (file.exists(stats_file)) {
        saved <- tryCatch({
          read.table(stats_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        }, error = function(e) NULL)
        
        if (!is.null(saved) && nrow(saved) > 0) {
          stats$total_requests <- as.numeric(saved$total_requests[1])
          stats$avg_response_time <- as.numeric(saved$avg_response_time[1])
          stats$error_count <- as.numeric(saved$error_count[1])
          
          cat(sprintf("[STATS LOADED] Total: %d, Avg: %.2f, Errors: %d\n", 
                      stats$total_requests, stats$avg_response_time, stats$error_count))
        }
      }
    })
    
    # --- BAŞARILI İSTEK TAKİBİ ---
    # Başarılı bir isteği kaydeder ve ortalama yanıt süresini hesaplayarak günceller
    track_request <- function(duration_seconds = NULL) {
      isolate({
        stats$total_requests <- stats$total_requests + 1
        stats$last_request_time <- Sys.time()
        
        if (!is.null(duration_seconds) && is.finite(duration_seconds)) {
          current_total <- stats$total_requests
          current_avg <- stats$avg_response_time
          
          stats$avg_response_time <- 
            (current_avg * (current_total - 1) + duration_seconds) / current_total
        }
        
        cat(sprintf("[STATS] Total: %d, Avg: %.2f, Errors: %d\n", 
                    stats$total_requests, stats$avg_response_time, stats$error_count))
        
        # Her 10 istekte bir diske kaydet (performans optimizasyonu)
        if (stats$total_requests %% 10 == 0) {
          tryCatch({
            if (!dir.exists("logs")) dir.create("logs", recursive = TRUE)
            
            stats_df <- data.frame(
              total_requests = stats$total_requests,
              avg_response_time = stats$avg_response_time,
              error_count = stats$error_count,
              stringsAsFactors = FALSE
            )
            
            write.table(stats_df, stats_file, 
                        row.names = FALSE, sep = "\t", quote = FALSE)
          }, error = function(e) {
            cat("[ERROR] Failed to save stats:", e$message, "\n")
          })
        }
      })
    }
    
    # --- HATA TAKİBİ ---
    # Başarısız istekleri kaydeder ve hata sayacını artırır
    track_error <- function() {
      isolate({
        stats$total_requests <- stats$total_requests + 1
        stats$error_count <- stats$error_count + 1
        
        cat(sprintf("[STATS] Total: %d, Errors: %d\n", 
                    stats$total_requests, stats$error_count))
        
        # Her 10 istekte bir diske kaydet (performans optimizasyonu)
        if (stats$total_requests %% 10 == 0) {
          tryCatch({
            if (!dir.exists("logs")) dir.create("logs", recursive = TRUE)
            
            stats_df <- data.frame(
              total_requests = stats$total_requests,
              avg_response_time = stats$avg_response_time,
              error_count = stats$error_count,
              stringsAsFactors = FALSE
            )
            
            write.table(stats_df, stats_file, 
                        row.names = FALSE, sep = "\t", quote = FALSE)
          }, error = function(e) {
            cat("[ERROR] Failed to save stats:", e$message, "\n")
          })
        }
      })
    }
    
    # --- MODÜL DIŞA AKTARIMI ---
    # Modülün diğer bileşenler tarafından kullanılabilecek arayüzünü döndürür
    return(list(
      track_request = track_request,
      track_error = track_error,
      stats = stats
    ))
  })
}