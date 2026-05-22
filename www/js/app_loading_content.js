// www/js/app_loading_content.js
// Dosya Yolu: www/js/app_loading_content.js
// Açıklama: Açılış yükleme ekranındaki akan içerik katmanı için alan
//   bilgisi havuzu. MERGEN Bilge yalnızca kod üretmez; Primavera P6,
//   Jira, SAP gibi kurumsal araçlar ile radar ve elektronik harp
//   alanlarından örnek soru/yanıt ve bilgi notları da içerir.
//   Bu parçalar dekoratiftir ve www/js/app_loading_snippets.js havuzuna
//   eklenir. Bu dosya R/module_app_loading.R tarafından satır içine gömülür.
//
//   Şema:
//     { tag: "Etiket", lines: [...] }  -> düz metin / soru-yanıt notu
//     { lang: "Dil",  lines: [...] }   -> sözdizimi renklendirmeli kod
//   "Soru:" ve "Yanıt:" gibi kısa önekler ayrı renkle vurgulanır.

(function () {
  "use strict";

  var content = [
    // --- Primavera P6 ---
    { tag: "Primavera P6", lines: [
      "Soru: Kritik yol nasıl belirlenir?",
      "Yanıt: Toplam serbestliği sıfır olan",
      "aktiviteler kritik yolu oluşturur ve",
      "proje bitiş tarihini doğrudan etkiler."
    ] },
    { tag: "Primavera P6", lines: [
      "Temel plan (baseline), gerçekleşen",
      "ilerlemeyi planlanan değerlerle",
      "karşılaştırmak için kaydedilir."
    ] },
    { tag: "Primavera P6", lines: [
      "İş kırılım yapısı (WBS), projeyi",
      "yönetilebilir teslimat paketlerine",
      "hiyerarşik olarak böler."
    ] },
    { tag: "Primavera P6", lines: [
      "Soru: Kaynak çakışması nasıl giderilir?",
      "Yanıt: Kaynak dengeleme ile aşırı",
      "yüklenen kaynakların görevleri uygun",
      "zaman aralığına yayılır."
    ] },
    { tag: "Primavera P6", lines: [
      "Kazanılmış değer analizi; SPI ve CPI",
      "göstergeleriyle takvim ve maliyet",
      "performansını birlikte ölçer."
    ] },

    // --- Jira ---
    { tag: "Jira", lines: [
      "Soru: Sprint kapsamı nasıl belirlenir?",
      "Yanıt: Takımın hız değeri ve öncelikli",
      "backlog öğeleri esas alınır."
    ] },
    { tag: "Jira", lines: [
      "Epik, birden çok kullanıcı hikayesini",
      "kapsayan büyük bir iş kalemidir.",
      "Hikayeler puanlanarak tahminlenir."
    ] },
    { tag: "Jira", lines: [
      "Burndown grafiği, sprint boyunca kalan",
      "işin günlük azalışını gösterir."
    ] },
    { lang: "JQL", lines: [
      "project = REHIS AND status = \"Devam\"",
      "AND assignee = currentUser()",
      "ORDER BY priority DESC, updated ASC"
    ] },
    { lang: "JQL", lines: [
      "project = MERGEN AND issuetype = Hata",
      "AND created >= -7d",
      "ORDER BY created DESC"
    ] },

    // --- SAP ---
    { tag: "SAP", lines: [
      "Soru: Malzeme stoğu nereden görülür?",
      "Yanıt: MM modülünde MMBE işlem kodu",
      "ile stok genel bakışı açılır."
    ] },
    { tag: "SAP", lines: [
      "Satınalma siparişi ME21N, mal girişi",
      "ise MIGO işlem koduyla oluşturulur."
    ] },
    { tag: "SAP", lines: [
      "Ürün ağacı (BOM), bir mamulün",
      "bileşenlerini ve miktarlarını tanımlar."
    ] },
    { lang: "ABAP", lines: [
      "SELECT ebeln ebelp menge",
      "  FROM ekpo INTO TABLE lt_kalem",
      "  WHERE ebeln = lv_siparis.",
      "LOOP AT lt_kalem INTO ls_kalem.",
      "ENDLOOP."
    ] },

    // --- Radar sistemleri ---
    { tag: "Radar Sistemleri", lines: [
      "Radar kesit alanı (RCS), bir hedefin",
      "yansıttığı sinyal gücünün ölçüsüdür."
    ] },
    { tag: "Radar Sistemleri", lines: [
      "Soru: Menzil çözünürlüğü neye bağlıdır?",
      "Yanıt: Darbe bant genişliği arttıkça",
      "menzil çözünürlüğü iyileşir."
    ] },
    { tag: "Radar Sistemleri", lines: [
      "Darbe-Doppler radar; hareketli hedefi",
      "sabit zeminden frekans kaymasıyla ayırır."
    ] },
    { tag: "Radar Sistemleri", lines: [
      "Frekans çevikliği, taşıyıcı frekansı",
      "darbeden darbeye değiştirerek",
      "karıştırmaya dayanıklılığı artırır."
    ] },
    { tag: "Radar Sistemleri", lines: [
      "Faz dizili anten, ışını mekanik hareket",
      "olmadan elektronik olarak yönlendirir."
    ] },

    // --- Elektronik harp ---
    { tag: "Elektronik Harp", lines: [
      "Soru: ECM ile ECCM farkı nedir?",
      "Yanıt: ECM karşı tedbir uygular; ECCM",
      "bu tedbirlere karşı korumayı sağlar."
    ] },
    { tag: "Elektronik Harp", lines: [
      "Tehdit kütüphanesi, bilinen yayın",
      "imzalarını sınıflandırmak için kullanılır."
    ] },
    { tag: "Elektronik Harp", lines: [
      "Radar ikaz alıcısı (RWR), aydınlatan",
      "tehdit radarlarını tespit edip uyarır."
    ] },
    { tag: "Elektronik Harp", lines: [
      "Gürültü karıştırması alıcıyı doyurur;",
      "aldatıcı karıştırma sahte hedef üretir."
    ] },

    // --- Sinyal işleme ---
    { tag: "Sinyal İşleme", lines: [
      "Hızlı Fourier dönüşümü, sinyali zaman",
      "alanından frekans alanına taşır."
    ] },
    { tag: "Sinyal İşleme", lines: [
      "Uyumlu filtre; gürültü içindeki bilinen",
      "darbeyi en yüksek SNR ile öne çıkarır."
    ] },
    { tag: "Sinyal İşleme", lines: [
      "Soru: Örnekleme hızı nasıl seçilir?",
      "Yanıt: Nyquist ölçütü gereği en yüksek",
      "frekansın en az iki katı olmalıdır."
    ] },

    // --- MERGEN Bilge ---
    { tag: "MERGEN Bilge", lines: [
      "Yüklenen PDF, Word ve Excel dosyalarını",
      "çözümleyip sorularınızı yanıtlarım."
    ] },
    { tag: "MERGEN Bilge", lines: [
      "Soru: Söyleşi geçmişim saklanıyor mu?",
      "Yanıt: Evet, tüm söyleşileriniz güvenle",
      "kaydedilir ve istediğinizde açılır."
    ] },
    { tag: "MERGEN Bilge", lines: [
      "Bilge Yolaç ile kod yazma, inceleme ve",
      "belge üretme görevlerini yürütebilirsiniz."
    ] },

    // --- Veri analizi ---
    { tag: "Veri Analizi", lines: [
      "Korelasyon, iki değişkenin birlikte",
      "değişme eğilimini ölçer; tek başına",
      "nedensellik anlamına gelmez."
    ] },
    { tag: "Veri Analizi", lines: [
      "Aykırı değerler, çeyrekler arası",
      "açıklık yöntemiyle tespit edilebilir."
    ] },

    // --- Proje yönetimi ---
    { tag: "Proje Yönetimi", lines: [
      "Kilometre taşı, süresi sıfır olan ve",
      "önemli bir aşamayı işaretleyen olaydır."
    ] },
    { tag: "Proje Yönetimi", lines: [
      "Soru: Risk önceliği nasıl belirlenir?",
      "Yanıt: Olasılık ile etki çarpılarak",
      "risk puanı hesaplanır ve sıralanır."
    ] }
  ];

  window.MergenLoadingSnippets =
    (window.MergenLoadingSnippets || []).concat(content);
})();
