# Shiny ve worker yaşam döngüsü denetimi

8 Ekim denetiminin tarihsel main anlık görüntüsü: `09b26d8aa28d8dfeae6d85a5ff605b5014950ea4` (8 Ekim 2026).
Denetimdeki on bulgu giderildi: sonuçlar istek/sohbet/sahip sınırlarında korunur; Yolaç devam bağları sahip değişiminde temizlenir. Takip üretimi, büyük DOCX kodlaması ve indeks kilidi işçilere taşınır; işçi hataları ana süreçte yeniden yürütülmez. Çalışan Yolaç kayıt kimliği görünümden bağımsız saklanır; LLM işçi ayarları canlı Shiny oturumu taşımaz.

İnceleme düzeltmeleri aynı kullanıcının yetki değişimini de kimlik nesline bağlar. SSE, normal yanıt ve TTS sahip kancaları eski isteğin gönderme durumunu temizler; erken SSE kapanışı kancaları kaldırıp işçi bitene kadar durdurma dosyasını korur. TTS takipleri ortak asenkron dağıtıcıyı kullanır. Devre dışı takipler işçi veya API anahtarı istemez; sahip, sohbet, istek ve oturum değişiminde çalışan takip HTTP aktarımı durdurma jetonuyla kesilir.

İndeks yazımı başarısızsa yükleme başarılı sayılmaz. İndeks kilidi hatasında sahipliği doğrulanamayan kopyalar silinmez; ikinci işçinin gönderim veya çalışma hatasında bağımsız geri alma işçisi dosyaları temizlemeden alım kotası bırakılmaz. DOCX yol çözümleme, varlık/üstveri yoklaması ve kodlama işçide yürür; önbellek anahtarı da orada doğrulanır. Senkron gönderim hataları ile promise hataları aynı sahip/önizleme kapısından bildirilir. Kalıcı PK altyapı eksikleri geçici yoğunluktan ayrı bildirilir. Windows zamanlama testi üç saniyelik işçiyle iki saniyelik bloklamama sınırını ve tamamlanma bekleyişini korur. Bayat SSE ve benzetimli akışlar yalnız kendi yarım mesajını kaldırır; daha yeni isteğin mesajı ve gönderimi korunur. PK gönderim hatası çağırana terminal eylem döndürür. Geri alma işçisi kurulamaz veya çökerse indeks kilidine girmeyen son hedef temizliği denenir; kaynak ve başarısız kopyalar korunur. CodeMirror çizim denetimi ilk renk ölçümünden önce yazı tipi ve çizim karelerinin tamamlanmasını bekler; renk/kontrast sınırları korunur.

Kalıcı işçi şeridi iki veya daha fazla fiziksel yuvada en az bir yuva bulur; tek fiziksel yuvada kalıcı ve etkileşimli işler öncelik sırasıyla aynı yuvayı paylaşır. Fiziksel süreç, kuyruk ve yürütme sınırları artırılmaz. Alımın senkron başlangıç hatası da ortak iş bırakma yolunu kullanır.

İndeks kararı kimliksiz yeniden kayıt dahil her girdiye aittir. Reddedilen kayıt başarılı yükleme ya da kayıp dosya sayılmaz. Commit sonrasında değişen UI nesli yalnız ilerleme bildirimini kapatır; kalıcı dosya geri alınmaz ve yeni nesle dosya ayrıntısı taşınmaz.

Belirsiz sahiplik sınırlı yeniden okumayla doğrulanır; yabancı veya hâlâ okunamayan jeton hedef temizleme yetkisi vermez. İndeks kilidi bırakılırken de jeton aynı geri kazanım muteksi altında doğrulanır.

Yolaç bildirimleri yakalanan oturuma gönderilir ve bildirim hatası hazırlanmış işi düşürmez. Oturumsuz yoklama hatası yalnız ilgili çalıştırmayı başarısız kılar; reaktif sessiz koşullar korunur. Çıktı işçisinin sahipliği istek ve süre kurulumu tamamlanmadan devralınmaz.


## Sonraki düzeltme kaydı — 21 Ekim 2026

Bu bölüm 8 Ekim anlık görüntüsüne ait değildir. Alım kararları [`c4321dd73`](https://github.com/mokaradag/MERGEN-Bilge/commit/c4321dd73), terfi ve işçi bütçesi değişiklikleri [`a8ec76510`](https://github.com/mokaradag/MERGEN-Bilge/commit/a8ec76510), o turun sınırları [`608d9ecd1`](https://github.com/mokaradag/MERGEN-Bilge/commit/608d9ecd1) kaynak durumunu anlatır; güncel çalışma zamanı veya Windows VM doğrulaması iddiası taşımaz.

21 Ekim yakınsama turunda alım çakışması talep zamanıyla değil, indeks kilidi altında saklanan commit zamanı ile yeni kopyanın aynı uygulama saatinden alınan başlangıcı karşılaştırılarak belirlenir; paylaşımın marker saati kullanılmaz. İlk başlangıç işlem günlüğünde korunur ve native yol yeniden bağlamasında yenilenmez. Aynı parti içinde son geçerli eş adlı girdi kazanır; kabul bayrakları ve temizlik yalnız bu sonuca göre belirlenir. Aynı yolun kimliksiz yeniden kaydı yapıt kimliğini ve commit zamanını korur. Reddedilen kardeşin temizliği başarısızsa işlem günlükleri tutulur ve mevcut bağımsız geri alma işçisiyle sınırlı yeniden deneme yapılır; başarılı kardeşin commit'i korunur.

Yükleme terfisi ve rezervasyon devralması dizin başına tek kalıcı geri kazanım muteksi kullanır; terfi işçisi çekişmede en fazla beş saniye bekler. Yalnız muteksin tam gizli adı listelemeden ayıklanır; benzer sonekli kullanıcı belgeleri korunur, etkin kilit dosyası silinmez. Uzun hedeflerin sahiplik adları sınırlı hash kullanır; Windows çıktı hash'i harf karşılaştırmasına göre oluşturulur. Doküman özeti HTTP isteği süreç başlatma ve hazırlama sonrası kalan toplam işçi bütçesini alır. Yeni isteğin köken nesli, eski TTS sonucunu LLM sahipliği değişmeden de engeller. Yoklama hatasının özgün nedeni ortak gizli-değer maskelemesinden geçirilerek kaydedilir; sabit DB havuzu kapasite hatası altyapı sonucu sayılır.

Kalan sınırlar: sabit bağlantı kurulamayan geçici yüklemenin güvenli, bloklamayan sahiplik devri ve okunamayan rezervasyonun bağımsız sahiplik kanıtıyla kurtarılması bu turda uygulanmadı. Yaş tek başına okunamayan canlı sahibi devralma yetkisi vermez. Windows soğuk süreç gecikmesi VM ölçümü gerektirir; ölçüm olmadan havuz yeniden tasarlanmadı. Profil okuma belirsizliğinde eski yetki kapsamı korunmadı; iki ve üzeri işçide kalıcı şeridin ayrılmış yuvası kaldırılmadı. Ratchet eşikleri değiştirilmedi.


## Sonraki düzeltme kaydı — 23 Ekim 2026

Doküman özeti zaman aşımı işçi kabulünden önce sayısal ve sonlu pozitif tek değere dönüştürülür; geçersiz ayarda 600 saniye kullanılır, geçerli uzun süreler korunur. HTTP isteği yine kalan toplam işçi bütçesine uyar. Hazırlık işçisi `fs` ve `ps` bağımlılıklarını açıkça bildirir; `ps` uygulama paket manifestinde de doğrulanır. İzole akış testleri sahip korumasını kendi ortamından çağırır; bayat görsel/özet başarı ve hata testleri yeni istek kimliğinin korunduğunu doğrular. Ratchet eşikleri değiştirilmedi.

## Sonraki düzeltme kaydı — 24 Ekim 2026

Doküman özeti promise geri çağrılarında UI sonlandırma hatası kalıcı sonuç ve geçmiş kaydını kesmez; başarı, hata ve reddedilme yolları aynı sınırı korur. Kapanış yarışı mevcut davranış testinde zorlanır. Dizin listeleme kullanılabilirlik testi kendi işçi desteği stub'ını kullanır. Ratchet eşikleri değiştirilmedi.

Alım kuyruğunda bekleyen yüklemeler de işçi şeritlerinin kapasite kararına katılır. İki ve üzeri fiziksel işçide sohbetler havuzu doldurduğunda sonraki boş yuva alım pompası için korunur. Alım talebi bitince sohbet boş kapasiteyi yeniden kullanır. Davranış testi 2–4 fiziksel işçide gerçek alım kuyruğu ve işçi yoklamasıyla bu devri doğrular; tek işçideki mevcut öncelik sözleşmesi, kapasite ve ratchet sınırları değişmez.

- [`R/server_handler_true_streaming.R:379`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/server_handler_true_streaming.R#L379)
- [`R/module_claude_code.R:207`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_claude_code.R#L207)
- [`R/helpers_stream_load_control.R:127`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_stream_load_control.R#L127)
- [`R/module_file_preview.R:428`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_file_preview.R#L428)
- [`R/module_ai_processing.R:169`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_ai_processing.R#L169)
- [`R/server_handler_pk_async.R:47`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/server_handler_pk_async.R#L47)
- [`R/helpers_claude_code_session_persistence.R:370`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_claude_code_session_persistence.R#L370)
- [`R/helpers_file_ingestion_runtime.R:135`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_file_ingestion_runtime.R#L135)
- [`R/helpers_claude_code_server_setup.R:463`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/helpers_claude_code_server_setup.R#L463)
- [`R/module_ai_processing.R:113`](https://github.com/mokaradag/MERGEN-Bilge/blob/09b26d8aa28d8dfeae6d85a5ff605b5014950ea4/R/module_ai_processing.R#L113)
