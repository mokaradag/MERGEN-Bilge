# Üretim Log Yolu ve Mojibake Onarımı

Bu belge, `MERGEN_LOG_DIR` çözümleme davranışı için odaklı ve kanonik başvuru kaynağıdır. PR #682 ile üretim başlatıcısı, doğrudan `app.R` başlangıcı ve çok-worker çocuk süreçleri aynı erken log-yolu bootstrap katmanını kullanır.

> `MERGEN_LOG_DIR` için temel kural: yapılandırılmış hedef korunur. Merkezî veya UNC hedef, yalnızca yol adında güçlü mojibake kanıtı bulunduğu için repo içindeki yerel `logs` diziniyle değiştirilmez; bozuk bölüm yerinde onarılır.

## 1. Başlangıç Akışı

Log yapılandırması, normal uygulama kaynakları yüklenmeden önce şu sırayla hazırlanır:

1. `.Renviron` okunur.
2. `R/utils_text_encoding.R`, açık `encoding = "UTF-8"` ile yüklenir.
3. `R/bootstrap_log_path.R` yüklenir.
4. `MERGEN_LOG_DIR` denetlenir ve gerekiyorsa yerinde onarılır.
5. Log yapılandırması ve uygulama başlangıcı devam eder.

Bu akış hem `run_mergen_prod.R` hem de doğrudan `app.R` girişinde uygulanır. Çok-worker başlatıcı çocuk süreçleri `Rscript app.R` ile açtığı için her worker aynı çözümleme sözleşmesine tabidir.

## 2. Hedef Seçim Sözleşmesi

- `MERGEN_LOG_DIR` tanımlı ve temizse değer aynen korunur.
- Değer merkezî bir paylaşımı veya özel bir UNC yolunu gösteriyorsa aynı hedef kullanılmaya devam eder.
- `MERGEN_LOG_DIR` tanımlı değilse uygulama varsayılan olarak çalışma dizini altındaki `logs` klasörünü kullanır.
- Onarım, yolun yalnızca bozulmuş metin parçalarını değiştirir; paylaşım kökü veya hedef dizin politikası değiştirilmez.
- Onarılamayan güçlü mojibake kalırsa uygulama yanlış adla yeni klasör oluşturmak yerine başlangıçta açık hata verir.

`mergen_YYYYMMDD.log` ve `ai_debug_YYYYMMDD.log` aynı çözülmüş hedef altında oluşturulur.

## 3. Güçlü Mojibake Kanıtı

Çözücü, Windows-1252 veya Latin-1 üzerinden yanlış yorumlanmış UTF-8 dizilerini değerlendirir. Tek ve çift kez bozulmuş yollar desteklenir; en fazla iki onarım geçişi yapılır.

| Yapılandırılmış değer | Çözülmüş değer | Sonuç |
|---|---|---|
| `//server/GeliÅŸtirme/logs` | `//server/Geliştirme/logs` | Tek geçişli bozulma yerinde onarılır. |
| `//server/GeliÃ…Å¸tirme/logs` | `//server/Geliştirme/logs` | Çift geçişli bozulma iki adımda onarılır. |
| `//server/Doğru/CafÃ©/logs` | `//server/Doğru/Café/logs` | Yolun yalnız bozuk bölümü düzeltilir. |

Onarım sırasında önceki sürümün yanlış adla oluşturduğu klasörün mevcut olması, güçlü kanıt bulunan yolun düzeltilmesini engellemez.

## 4. Korunan Geçerli Adlar

Tek başına `Ã`, `Ä` veya `Å` karakteri mojibake kanıtı değildir. Çözücü, geçerli Unicode adlarını ve belirsiz dizileri yanlışlıkla değiştirmemelidir.

Aşağıdaki örnekler korunur:

- `//server/Årsrapporter/logs`
- `//server/Ãrea/logs`
- `//server/Doğru/É©/logs`
- `//server/Â©/logs`

`Â©` gibi tek `C2 + sembol` dizileri güçlü kanıt sayılmaz. Özgün ve olası onarılmış hedeflerin ikisi de yoksa yapılandırılmış ad aynen bırakılır; yalnızca onarılmış hedef zaten mevcutken güvenli yön değişikliği yapılabilir.

## 5. Windows ve UNC Yol Yazımı

`.Renviron` içinde Windows/UNC yolları forward-slash biçiminde yazılmalıdır:

```text
MERGEN_LOG_DIR="//server/share/MERGEN Bilge/logs"
```

Kaçış gerektiren ters bölü biçiminden kaçının. Yol boşluk veya Türkçe karakter içerebilir; erken bootstrap katmanı UTF-8 yardımcılarını açık kodlamayla yükler.

`.Renviron` değişikliği yapıldıktan sonra tarayıcı yenilemesi yeterli değildir; tüm R süreci yeniden başlatılmalıdır.

## 6. Operatör Doğrulaması

Etkin log hedefini doğrulamak için öncelikle **Sistem Durumu > Günlük Log Sağlığı** kartındaki gerçek dosya yoluna ve satır sayısına bakın.

Repo kökünden çözülmüş ortam değerini görmek için:

```powershell
Rscript -e "readRenviron('.Renviron'); source('R/utils_text_encoding.R', encoding='UTF-8'); source('R/bootstrap_log_path.R', encoding='UTF-8'); normalize_mergen_log_dir_env(); cat(Sys.getenv('MERGEN_LOG_DIR'))"
```

Beklenen denetimler:

1. Çıktı, amaçlanan merkezî veya yerel hedefi göstermelidir.
2. Güçlü mojibake örneği varsa doğru Unicode yazıma dönüşmelidir.
3. Geçerli `Årsrapporter`, `Ãrea`, `É©` veya `Â©` adları değiştirilmemelidir.
4. `mergen_YYYYMMDD.log` ve `ai_debug_YYYYMMDD.log` aynı çözülmüş dizinde dolmalıdır.

## 7. Canlı İzleyici Notu

`view_latest_mergen_app_log.bat` yalnızca uygulama klasöründeki yerel `logs` dizinini izliyorsa, merkezî `MERGEN_LOG_DIR` kullanan dağıtımda bu izleyici gerçek hedefi göstermeyebilir. Bu durum uygulamanın hedefi yerel dizine çevirmesi gerektiği anlamına gelmez.

Merkezî hedef kullanıldığında:

- Sistem Durumu kartından etkin yolu doğrulayın.
- Merkezî `mergen_YYYYMMDD.log` dosyasını doğrudan açın veya kurumsal log toplayıcısını kullanın.
- Sırf yerel izleyicide dosya boş göründüğü için `MERGEN_LOG_DIR` değerini yerel `logs` dizinine değiştirmeyin.

## 8. Sorun Giderme

### Günlük log boş görünüyor

- Sistem Durumu kartındaki incelenen yol ile operatörün açtığı dosyanın aynı olduğunu doğrulayın.
- Çözülmüş `MERGEN_LOG_DIR` yolunun erişilebilir ve yazılabilir olduğunu kontrol edin.
- UNC paylaşımının uygulama hesabı ve tüm worker süreçleri tarafından erişilebilir olduğunu doğrulayın.
- Başlangıç konsolunda log-yolu onarım hatası olup olmadığına bakın.
- Yerel izleyici yerine yapılandırılmış merkezî hedefteki dosyayı inceleyin.

### Yanlış adla klasör oluşmuş

Önceki sürüm `GeliÅŸtirme` gibi bozuk klasör oluşturmuş olabilir. Yeni başlangıçta güçlü mojibake kanıtı varsa çözülmüş hedef `Geliştirme` olur. Eski klasörü otomatik silmeyin; içerik/retention gereksinimini inceleyip ayrı ve bilinçli bir operasyonla arşivleyin veya kaldırın.

### Başlangıç onarım hatasıyla duruyor

İki geçişten sonra güçlü mojibake kaldığında fail-closed davranış beklenir. `.Renviron` içindeki yolu doğru Unicode yazımıyla düzeltin, erişimi doğrulayın ve tüm R sürecini yeniden başlatın. Hata durumunda repo-yerel `logs` dizinine sessiz fallback yapılmaz.

## 9. Test Sözleşmesi

Davranış aşağıdaki odaklı testlerle korunur:

- `tests/testthat/test-prod-log-path-mojibake-contract.R`
- `tests/testthat/test-prod-log-path-mojibake-review-regressions.R`
- `tests/testthat/test-text-encoding-mojibake-behavior.R`

Kapsam; tek/çift geçişli Türkçe bozulmayı, ISO-8859-1 kontrol karakterli örnekleri, karışık yol onarımını, geçerli Unicode ve belirsiz `C2` dizilerinin korunmasını, eski bozuk klasör mevcutken doğru hedef seçimini, `app.R`/üretim başlatıcısı kaynak sırasını ve çok-worker giriş sözleşmesini içerir.

Windows VM dağıtımında tam kanıt için ilgili testlerin yanında uygulama başlangıcı, gerçek UNC erişimi ve günlük dosyaların çözülmüş hedefte dolduğu ayrıca doğrulanmalıdır.
