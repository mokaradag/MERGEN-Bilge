// www/js/chart_renderer.js

// Grafik çizdirme fonksiyonu (Global erişim için window'a atanır)
// Highcharts henüz yüklenmemişse otomatik yeniden deneme mekanizması içerir
window.renderSavedCharts = function(wrapperId, retryCount) {
  retryCount = retryCount || 0;
  var maxRetries = 8;
  var retryDelay = 500; // Her denemede 500ms bekle

  // Kapsayıcı elementi bul (ID veya Class ile)
  var wrapper = document.getElementById(wrapperId);
  if (!wrapper) wrapper = document.querySelector('.' + wrapperId);
  if (!wrapper) wrapper = document.body; // Bulunamazsa body içinde ara

  // Henüz çizilmemiş (.rendered sınıfı olmayan) ve grafik verisi içeren kartları bul
  var chartCards = wrapper.querySelectorAll('.chart-card[data-chartlab-spec]:not(.rendered)');

  // Çizilecek grafik yoksa çık
  if (chartCards.length === 0) return;

  // Highcharts henüz yüklenmemişse yeniden dene
  if (typeof Highcharts === 'undefined') {
    if (retryCount < maxRetries) {
      console.log('[CHART] Highcharts henüz yüklenmedi, yeniden deneniyor... (' + (retryCount + 1) + '/' + maxRetries + ')');
      setTimeout(function() {
        window.renderSavedCharts(wrapperId, retryCount + 1);
      }, retryDelay);
    } else {
      console.error('[CHART] Highcharts ' + maxRetries + ' denemeden sonra yüklenemedi.');
      chartCards.forEach(function(card) {
        var container = card.querySelector('.chartlab-placeholder');
        if (container) {
          container.innerHTML = '<div style="color:#f87171">Grafik kütüphanesi yüklenemedi. Sayfayı yenileyip tekrar deneyin.</div>';
        }
      });
    }
    return;
  }

  chartCards.forEach(function(card) {
    var specJson = card.getAttribute('data-chartlab-spec');
    var chartId = card.getAttribute('data-chart-id');
    if (!specJson || !chartId) return;

    // Tekrar çizilmeyi önlemek için işaretle
    card.classList.add('rendered');

    try {
      var spec = JSON.parse(specJson);
      var container = card.querySelector('.chartlab-placeholder');
      if (!container) return;

      container.innerHTML = ''; // "Yükleniyor..." yazısını temizle

      // Grafik tipini belirle (varsayılan: column)
      var chartType = (spec.type || 'column').toLowerCase();
      var mapping = spec.mapping || {};
      var data = spec.data || [];

      var seriesData = [];
      var categories = [];

      // Veriyi Highcharts formatına dönüştür
      if (Array.isArray(data) && data.length > 0) {
        if (chartType === 'pie' || chartType === 'donut') {
           // Pasta/Halka grafik için veri formatı: [{name, y}]
           seriesData = data.map(function(row) {
             return {
               name: row[mapping.x] || row.name || 'Bilinmiyor',
               y: parseFloat(row[mapping.y] || row.value || row.n || row.val) || 0
             };
           });
        } else {
           // XY Grafikleri için (Sütun, Çizgi vb.)
           categories = data.map(function(row) { return row[mapping.x] || ''; });
           var values = data.map(function(row) { return parseFloat(row[mapping.y] || row.n || row.val) || 0; });
           seriesData = [{ name: mapping.y || 'Değer', data: values }];
        }
      }

      // Highcharts ayarları ve çizimi
      Highcharts.chart(container, {
        chart: {
          type: chartType === 'donut' ? 'pie' : chartType,
          backgroundColor: 'transparent',
          style: { fontFamily: 'Inter, sans-serif' }
        },
        title: { text: spec.title || null, style: { color: '#fff' } },
        xAxis: (chartType !== 'pie' && chartType !== 'donut') ? {
          categories: categories,
          labels: { style: { color: '#999' } },
          lineColor: '#444'
        } : undefined,
        yAxis: (chartType !== 'pie' && chartType !== 'donut') ? {
          title: { text: mapping.y || '' },
          labels: { style: { color: '#999' } },
          gridLineColor: '#333'
        } : undefined,
        plotOptions: {
          pie: {
            innerSize: (chartType === 'donut' || spec.params?.donut) ? '60%' : '0%',
            borderWidth: 0,
            dataLabels: { enabled: true, color: '#fff', style: { textOutline: 'none' } }
          },
          series: { borderWidth: 0, borderRadius: 2 }
        },
        colors: ["#60a5fa", "#a78bfa", "#34d399", "#f472b6", "#fbbf24", "#22d3ee"],
        series: (chartType === 'pie' && chartType !== 'donut') ? [{ name: 'Değer', data: seriesData }] : seriesData,
        legend: { itemStyle: { color: '#999' } },
        tooltip: { backgroundColor: '#1a1a1a', style: { color: '#fff' } },
        credits: { enabled: false }
      });
    } catch(e) {
      console.error('[CHART] Grafik çizim hatası:', e);
      // Hata durumunda tekrar denenebilmesi için işareti kaldır
      card.classList.remove('rendered');
    }
  });
};

// Sayfa yüklendiğinde çalışacak gözlemci (Observer)
$(document).ready(function() {
    // Kayıtlı grafiklerin (Geçmiş) DOM'a eklendiğini izleyen gözlemci
    const chartHistoryObserver = new MutationObserver(muts => {
      let needsRender = false;
      muts.forEach(m => {
        if (m.addedNodes) {
          m.addedNodes.forEach(node => {
            if (node.nodeType !== 1) return; // Metin düğümlerini atla
            // Düğümün kendisi veya içeriği bir grafik kartı mı kontrol et
            if (node.classList.contains('chart-card') || node.querySelector('.chart-card')) {
              needsRender = true;
            }
          });
        }
      });
      
      if (needsRender) {
        // Çok fazla çizim isteğini gruplamak için debounce (gecikme) kullan
        if (window.renderChartTimeout) clearTimeout(window.renderChartTimeout);
        window.renderChartTimeout = setTimeout(() => {
             // Sohbet kapsayıcısı içindeki çizilmemiş grafikleri çiz
             if (window.renderSavedCharts) {
               var chartRoot = document.getElementById('chat_content_container') ||
                               document.querySelector('.chat-container');
               if (chartRoot && chartRoot.id) {
                 window.renderSavedCharts(chartRoot.id);
               } else if (chartRoot && chartRoot.classList && chartRoot.classList.contains('chat-container')) {
                 window.renderSavedCharts('chat-container');
               }
             }
        }, 100);
      }
    });

    // Gözlemciyi ana sohbet kapsayıcısına bağla
    const historyContainer = document.querySelector('#chat_content_container') || document.querySelector('.chat-container');
    if (historyContainer) {
      chartHistoryObserver.observe(historyContainer, { childList: true, subtree: true });
    }
});