# MERGEN Bilge Kullanım Rehberi

Bu belge, **Yardım Merkezi > Yardım Asistanı** için kullanıcıya dönük başvuru kaynağıdır. Son güncelleme: **30 Temmuz 2026**. Sürüm: **v1.0**.

## Yardım Asistanının yanıt ilkeleri

- Yalnızca MERGEN Bilge’nin kullanımı hakkında, bu rehbere dayanarak Türkçe yanıt ver.
- Önce doğrudan yanıtı, gerekirse kısa kullanım adımlarını sun.
- Teknik altyapı, kod, dosya yolları, veritabanı, gizli anahtarlar veya yönetimsel kurulum ayrıntıları verme.
- Bir işlev kullanıcının yetkisine ya da kurum ayarlarına bağlıysa bunu açıkça söyle; görünmeyen bir menünün kesinlikle arızalı olduğunu varsayma.
- Bilgi uydurma. Rehberde bulunmayan veya uygulama dışı sorularda **destek@mergen.ai** ya da **+90 850 123 45 67** kanalına yönlendir.
- Kullanıcıdan parola, API anahtarı veya başka bir gizli bilgi isteme.

## 1. MERGEN Bilge nedir?

MERGEN Bilge; Türkçe söyleşi, belge ve veri analizi, özetleme, görsel oluşturma ve anlama, sesli etkileşim, ortak çalışma, kurumsal süreç rehberliği ve kod odaklı ajan çalışmalarını tek uygulamada birleştiren kurumsal yapay zekâ çalışma alanıdır.

## 2. İlk kullanım

1. Açılışta **Hızlı Başlangıç** ile doğrudan Ana Söyleşi’ye geçin veya **Zengin Deneyim**i seçin.
2. **Ayarlar > Kişiselleştirme** bölümünden asistanı ve deneyim modunu seçip **Ayarları Kaydet** düğmesine basın.
3. **Ana Söyleşi** alanında bir hızlı eylem seçin ya da doğrudan sorunuzu yazın.
4. Belge kullanacaksanız ataç simgesinden, sürükleyip bırakarak veya **Dosya Yönetimi** sayfasından yükleyin; kullanılacak dosyayı **Model Bağlamı**na ekleyin.
5. Yanıt üretimi sürerken gerekirse **Durdur** düğmesini kullanın. Yeni bir çalışma için **Yeni Söyleşi**yi seçin.

Hızlı eylem kartı yalnızca doğru çalışma modunu ve gerekli seçenekleri hazırlar; kullanıcı ilk gerçek isteğini gönderene kadar analiz veya üretim başlamaz.

## 3. Ana Söyleşi ve hızlı eylemler

Ana Söyleşi’de soru sorabilir, model değiştirebilir, dosya ekleyebilir, mikrofonla konuşabilir, yanıtı değerlendirebilir, söyleşiyi kopyalayabilir veya metin dosyası olarak dışa aktarabilirsiniz. Etkinleştirilmişse takip soruları; uygun modellerde akıl yürütme görünümü de sunulabilir.

### Hızlı eylemler

- **Süreç Yönetimi Sistemi:** Kurumsal süreç, yönerge, şablon ve iş akışı soruları içindir. Birden fazla süreç akışı sunulursa sohbet alanındaki listeden uygun olanı seçin.
- **Uygulama Uzmanı:** Kurumda tanımlanmış uygulamalar hakkında kullanım desteği verir.
- **Proje ve Kaynak Analizi:** Proje, bütçe, kaynak ve kurumsal veri soruları içindir. **Derin Düşünme** çoklu inceleme yapar; yanıt ayrıntısı Özet, Standart veya Detaylı seçilebilir.
- **Excel Analizi:** Excel verisini, sütunları, istatistikleri ve uygun grafik isteklerini inceler. Derin Düşünme açılırsa Düşük veya Yüksek seviye seçilebilir. Bu modda aynı anda tek dosya bağlanır.
- **Görsel Oluşturma:** Yazılı betimlemeden kare, yatay veya dikey görsel üretir; Standart ya da HD kalite seçilebilir. Üretilenler **Görsel Galerisi**nde saklanır.
- **Kodlama Desteği:** Kod yazma, açıklama, hata bulma, iyileştirme ve örnek üretme içindir. Derin Düşünme için Düşük veya Yüksek seviye seçilebilir.
- **Özetleme Desteği:** DOC, DOCX, PDF ve TXT belgelerinde çalışır. Kısa, Standart veya Detaylı özet; Genel, Sayısal Veri, Karar & Öneri ya da Karşılaştırma odağı seçilebilir. Birden fazla belge birlikte seçilebilir; Excel dosyaları bu modda özetlenmez.

Bir araç etkin olduğunda diğer özel araçlar kapatılır. Araçtan çıkmak için yeni bir hızlı eylem seçebilir, Yapılandırma’dan aracı kapatabilir veya Yeni Söyleşi başlatabilirsiniz.

## 4. Dosya yükleme, önizleme ve analiz

Normal yüklemede desteklenen türler: **TXT, PDF, DOCX, XLSX, XLS, CSV, JSON, R, PY, MD, LOG, XML, HTML, JPG, JPEG, PNG, GIF, WEBP, BMP ve SVG**. Dosya başına genel sınır **25 MB**’dır. Eski Word **DOC** biçimi yalnızca Özetleme Desteği’nde kullanılabilir; Bilge Yolaç belge çalışmasında DOC yerine DOCX kullanılmalıdır.

**Dosya Yönetimi** sayfasında dosya yükleyebilir, ilerlemeyi izleyebilir, listeyi yenileyebilir, önizleme açabilir ve dosyayı Model Bağlamı’na ekleyip kaldırabilirsiniz. Yükleme sürerken diğer alanları kullanabilirsiniz.

Bir dosyanın yanıtta kullanılabilmesi için yalnızca yüklenmiş olması yetmez; dosyanın Model Bağlamı seçimi açık olmalıdır. Normal kullanımda birden fazla dosya seçilebilir. Excel Analizi gibi tek dosyalı çalışma modlarında yalnızca bir dosya seçilir. Görsel içeriklerin anlaşılması, seçilen modelin bu yeteneği desteklemesine ve kurum ayarlarına bağlıdır.

## 5. Söyleşi Yönetimi

- **Söyleşi Geçmişi:** Önceki kişisel konuşmaları açar. Yeniden kullanılan bir söyleşi son etkinlik sırasına göre yukarı taşınabilir.
- **Kayıtlı Söyleşiler:** Önemli konuşmaları aramak, yeniden açmak ve yönetmek için kişisel çalışma arşividir.
- **Ortak Söyleşiler:** Yalnızca ekipçe paylaşılan normal söyleşileri listeler.
- **Görsel Galerisi:** Daha önce üretilmiş görselleri gösterir ve indirmeye açar.
- Ana Söyleşi karşılama ekranındaki **Son Konuşmalar**, en son etkin üç kişisel söyleşiye hızlı dönüş sağlar.

## 6. Ortak Çalışmalarım

**Ortak Çalışmalarım**, ekip üyelerinin aynı odada yazıştığı, yanıtları ve belgeleri birlikte gördüğü alandır. Kişisel çalışmalar ortak odalardan ayrı tutulur.

- **Ortak Söyleşiler:** Normal yapay zekâ sohbet odalarıdır.
- **Ortak Bilge Yolaç Oturumları:** Ekipçe yürütülen kod ve belge odaklı ajan çalışmalarıdır.
- **Ortak Çalışmalarım:** Tüm ortak odaları, davetleri ve arşivlenmiş odaları gösterir; oda buradan açılır.

### Oda kullanımı

1. Yeni ortak oturum oluşturun veya **Davetlerim** bölümünden daveti kabul edin.
2. **Odaya Yaz**, mesajı yalnızca katılımcılara gönderir; yapay zekâyı çalıştırmaz.
3. **Yapay Zekâya Sor**, soruyu yapay zekâya gönderir ve yanıtı bütün katılımcılar görür.
4. Aynı anda başka bir yanıt üretiliyorsa yeni sorular sıraya alınabilir.
5. **Yeni bağlam başlat**, eski yazışmaları silmeden sonraki yapay zekâ soruları için temiz bir bağlam açar.

Roller **Sahip, Oturum Yöneticisi, Katılımcı ve İzleyici**dir. Sahip ve Oturum Yöneticisi davet ve katılımcı yönetebilir; Katılımcı yazabilir ve yapay zekâya sorabilir; İzleyici yalnızca okuyabilir. Sahip ayrılmadan önce sahipliği devretmeli veya odayı arşivlemelidir.

Çevrim içi kişilere **Mergen İçinden Çağır** ile davet gönderilebilir. Çevrim dışı kişiler için **E-posta Taslağı Hazırla** kullanılır; e-posta otomatik gönderilmez.

**Ortak Belgeler** alanında yetkili katılımcılar belge yükleyebilir, önizleyebilir ve yapay zekâ bağlamına girecek belgeleri seçebilir. Bir ortak belge kişisel alana otomatik kopyalanmaz; isteyen katılımcı **Kendi Dosyalarıma Kaydet** düğmesini kullanır. Ortak Söyleşi’de görsel oluşturma desteklenmez; görsel için Ana Söyleşi kullanılmalıdır.

## 7. Bilge Yolaç

Bilge Yolaç, seçilen bir proje klasörü üzerinde çalışan kod ve dosya odaklı ajan alanıdır.

- **Çalışma Alanı:** Proje klasörü seçme, komut verme, çalışmayı izleme ve durdurma alanıdır.
- **Oturumlar:** Önceki kişisel çalışmaları ve üretilen belgeleri gösterir; uygun oturuma devam edilebilir veya geçmiş salt okunur açılabilir.
- **Ortak Bilge Yolaç Oturumları:** Aynı ajan çalışmasını ekip odasında yürütür; canlı ilerleme, sıra, ortak belgeler ve durdurma eylemi katılımcılarca görülür.

Hızlı, Dengeli ve Güçlü çalışma katmanlarından biri seçilebilir. Senaryolar: Kod İnceleme, Hata Ayıklama, Dokümantasyon, Test Yazımı, Kod Düzenleme ve Serbest Komut. Kapalı gelen **Eklentiler** panelini açarak ek uzmanlıkları görebilirsiniz.

Yerel klasör eylemi seçilen klasörü çalışma alanına aktarır. Üretilen dosyalar yanıtın altında indirilebilir bağlantı olarak görünür. PDF, XLS, XLSX ve DOCX belgeleri okunup özetlenebilir; eski DOC biçimi önce DOCX’e dönüştürülmelidir.

## 8. Bilge Savunması

**Bilge Yolaç > Bilge Savunması**, altı haritalık kampanya, beş kahraman, üç kule, haftalık meydan okuma, liderlik, savunma planları ve topluluk hedefleri içeren oyundur. Sonraki harita önceki tamamlanınca; Gelişmiş zorluk Normal düzey bitince açılır. Oyun duraklatılabilir, hızlandırılabilir, tam ekrana alınabilir ve kayıtlı koşuya devam edilebilir. Menü görünmüyorsa kurum ayarlarında kapalı olabilir.

## 9. Kişiselleştirme, görünüm ve ses

### Asistanlar

- **Emre Onat – Ana Asistan:** Dengeli özet ve uygulanabilir adımlar; varsayılandır.
- **Selin Sezgin – Yapıcı Uzman:** Sorunu çerçeveler, seçenekleri kıyaslar ve çözüm önerir.
- **Deniz Özgün – Stratejist:** Büyük resmi, riskleri ve yol haritasını kurar.
- **Can Yalın – Eleştirel Eş:** Varsayımları, riskleri ve doğrulama gereksinimlerini gösterir.
- **İpek Duru – Rehber:** Karmaşık işleri sade ve küçük adımlarla anlatır.

### Deneyim modları

- **Odak:** Sade, hızlı ve dikkat dağıtıcısı düşük kullanım.
- **Dinamik:** İşlevlerle görsel deneyim arasında denge.
- **Bütünleşik:** Persona, müzik, sesli rehberlik ve proaktif AI Uzman deneyiminin en zengin hâli.

**Ayarlar > Yapılandırma** bölümünde açık/koyu tema, yazı boyutu, zaman damgası, yazma göstergesi, animasyon, geniş ekran, canlı yanıt akışı, araç arka planları ve takip soruları yönetilebilir. Ses bölümünde **Yanıtları Seslendir**, arka fon müziği ve müzik düzeyi bulunur. Bütünleşik modda AI Uzmanın konuşma durumu, uzunluğu, sıklığı ve tarzı ayarlanabilir. Değişikliklerden sonra **Ayarları Kaydet** kullanılmalıdır; **Varsayılana Dön** kişisel tercihleri sıfırlar.

Kurumun kullanım biçimine göre başlangıçta kişisel API anahtarı veya varsayılan kurumsal erişim seçeneği sunulabilir. Anahtar ekleme, güncelleme ya da temizleme işlemi Yapılandırma’daki API Anahtarı alanından yapılır. Anahtarı sohbet mesajına yazmayın.

Sesli giriş için Ana Söyleşi’de mikrofonu açın, konuşun ve metni gönderin. Ses gelmiyorsa Yanıtları Seslendir ayarını, tarayıcı ses iznini ve cihaz sesini kontrol edin. Konuşma sırasında müzik otomatik olarak kısılabilir.

## 10. Destek ve yönetici alanları

- **Yardım Merkezi:** Bu Yardım Asistanı ile uygulama sorularını yanıtlar; sohbet temizlenebilir.
- **Geri Bildirim & Hata:** Memnuniyet, öneri ve hata bildirimi; konu, kategori, öncelik, açıklama ve gerekirse ek dosya gönderimi içindir.
- **Yenilikler:** Sürüm notlarını ve yeni özellikleri gösterir.
- **Hakkında:** Ürünü ve temel sayfaları tanıtır.
- **Yönetici Paneli:** Yalnızca yetkili kullanıcılara görünür. Genel Analiz, Geri Bildirim Analizi, Hata Analizi, Yanıt Geri Bildirimi, Dokümantasyon ve Sistem Durumu bölümlerini içerir.

## 11. Sık karşılaşılan durumlar

- **Dosya yanıtta kullanılmıyor:** Dosya türünü ve 25 MB sınırını kontrol edin; Dosya Yönetimi’nde Model Bağlamı’nı açın ve doğru hızlı eylemi seçin.
- **Excel Analizi başlamıyor:** Tek Excel dosyasının bağlamda seçili olduğundan emin olun ve isteğinizi gönderdikten sonra bekleyin.
- **Özetleme Excel’i kaldırdı:** Bu beklenen davranıştır; Özetleme Desteği DOC, DOCX, PDF ve TXT kullanır.
- **Yanıt üretilemiyor:** Durdurup yeniden deneyin; erişim seçimi sunuluyorsa kişisel/kurumsal seçeneği kontrol edin. Sorun sürerse destek kanallarına başvurun.
- **Menü veya düğme görünmüyor:** Bazı sayfalar rolünüze ve kurum ayarlarına bağlıdır. Sayfayı yenileyin; yine görünmüyorsa yöneticinizle veya destekle görüşün.
- **Ortak oda içeriği görünmüyor:** Daveti kabul ettiğinizden ve doğru odayı açtığınızdan emin olun. İzleyici rolünde yazma düğmeleri görünmez.
- **Bilge Yolaç çalışmıyor:** Geçerli bir proje klasörü seçin, uygun çalışma katmanını belirleyin ve komutu yeniden gönderin. Üretilen dosyaları yanıtın altındaki bağlantılardan indirin.
- **Ses veya müzik yok:** Ses ayarlarını, tarayıcı izinlerini ve cihaz sesini kontrol edin. Bazı sayfalar konuşma veya arka fon müziğini bilinçli olarak susturur.
- **Teknik destek:** **destek@mergen.ai** veya **+90 850 123 45 67**.
