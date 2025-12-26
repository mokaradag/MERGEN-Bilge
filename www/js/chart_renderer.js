// www/js/chart_renderer.js

// Grafik çizdirme fonksiyonu (Global erişim için window'a atanır)
window.renderSavedCharts = function(wrapperId) {
  // Kapsayıcı elementi bul (ID veya Class ile)
  var wrapper = document.getElementById(wrapperId);
  if (!wrapper) wrapper = document.querySelector('.' + wrapperId);
  if (!wrapper) wrapper = document.body; // Bulunamazsa body içinde ara

  // Henüz çizilmemiş (.rendered sınıfı olmayan) ve grafik verisi içeren kartları bul
  var chartCards = wrapper.querySelectorAll('.chart-card[data-chartlab-spec]:not(.rendered)');
  
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
      
      // Highcharts kütüphanesinin yüklü olup olmadığını kontrol et
      if (typeof Highcharts !== 'undefined') {
        container.innerHTML = ''; // "Loading..." yazısını temizle
        
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
             // Kategorileri (X ekseni) hazırla
             categories = data.map(function(row) { return row[mapping.x] || ''; });
             
             // Basit tek serili veri hazırlığı
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
      } else {
        container.innerHTML = '<div style="color:red">Highcharts kütüphanesi yüklenemedi.</div>';
      }
    } catch(e) {
      console.error('Grafik çizim hatası:', e);
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
               window.renderSavedCharts('chat_content_container'); 
               window.renderSavedCharts('chat_content_wrapper'); // Yedek kapsayıcı
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