// www/js/bilge_savunmasi_uygulama.js
// Bilge Savunması sayfa orkestratörü: tembel başlatma (yalnızca sayfa
// açıldığında bs-init ile), menü/oyun görünümü geçişleri, koşu yaşam döngüsü
// (başlat -> dalga döngüsü -> kontrol noktası -> sonuçlandırma), duraklatma,
// sekmeden ayrılınca motoru durdurma ve kaynakları serbest bırakma.
// Uygulama açılışında HİÇBİR oyun işi yapılmaz; bu dosya yalnızca olay
// dinleyicilerini kaydeder.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};

  var uygulama = {
    kok: null,
    modulId: "bilge_savunmasi_module",
    hazir: false,
    sayfadaMi: false,    // kullanıcı şu anda oyun sekmesinde mi
    kosu: null,          // aktif koşu bağlamı
    ayarZamanlayici: null,
    geriSayim: null
  };
  BS.uygulama = uygulama;

  function el(id) {
    return document.getElementById(uygulama.modulId + "-" + id);
  }

  // ── Görünüm geçişleri ───────────────────────────────────────────────────────
  function menuGoster() {
    var menu = el("menu_gorunumu");
    var oyun = el("oyun_gorunumu");
    if (menu) menu.classList.remove("bs-gizli");
    if (oyun) oyun.classList.add("bs-gizli");
  }

  function oyunGoster() {
    var menu = el("menu_gorunumu");
    var oyun = el("oyun_gorunumu");
    if (menu) menu.classList.add("bs-gizli");
    if (oyun) oyun.classList.remove("bs-gizli");
  }

  // ── Başlangıç verisi ────────────────────────────────────────────────────────
  BS.olaylar.ekle("sunucu-init", function(veri) {
    uygulama.kok = document.querySelector(".bs-sayfa");
    if (!uygulama.kok) return;

    var bekleme = el("motor_bekleniyor");
    if (bekleme) bekleme.classList.add("bs-gizli");

    if (!veri || veri.etkin === false) return;

    BS.veri.init = veri;
    BS.cizim.portreleriYukle(veri.personalar);
    BS.menu.profilOzetiCiz(uygulama.kok);
    // Oyun müzik listeleri (menü + seviye grupları) sunucudan gelir.
    BS.ses.muzikListesiAyarla(veri.muzik);

    // Kalıcılık rozeti ve açıklaması.
    var rozet = el("kalicilik_rozeti");
    var not = el("kalicilik_notu");
    if (rozet) {
      rozet.textContent = veri.kalicilik ? "İlerleme kaydediliyor" : "Kalıcılık kapalı";
      rozet.className = "bs-kalicilik-rozeti " +
        (veri.kalicilik ? "bs-rozet-acik" : "bs-rozet-kapali");
    }
    if (not) {
      not.innerHTML = veri.kalicilik ? "" :
        '<div class="bs-uyari-karti"><i class="fa fa-circle-info" ' +
        'aria-hidden="true"></i> Oyun tabloları henüz kurulmadığı için ilerleme, ' +
        'liderlik ve planlar kaydedilmiyor. Oyun serbest modda oynanabilir; ' +
        'kurulum için yöneticinize başvurun.</div>';
    }

    // Profil ayarlarını uygula (ses/kalite).
    if (veri.profil && veri.profil.ayarlar) {
      BS.ses.ayarla(veri.profil.ayarlar);
      if (veri.profil.ayarlar.kalite) BS.kalite.ayarla(veri.profil.ayarlar.kalite);
    }

    // Devam edilebilir koşu: menüde bant göster.
    if (veri.devam && veri.devam.kosu_id && !uygulama.kosu) {
      var harita = veri.haritalar[veri.devam.harita] || { ad: veri.devam.harita };
      if (not) {
        not.innerHTML +=
          '<div class="bs-devam-karti"><span><i class="fa fa-circle-play" ' +
          'aria-hidden="true"></i> Yarım kalmış koşun var: <b>' +
          BS.yardimci.htmlKacis(harita.ad) + '</b>' +
          (veri.devam.kontrol_dalga
            ? " · Dalga " + veri.devam.kontrol_dalga + " sonrası" : "") +
          '</span><span class="bs-devam-dugmeler">' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                  'data-bs-eylem="devam-et">Devam Et</button>' +
          '<button type="button" class="bs-yan-dugme" ' +
                  'data-bs-eylem="devam-birak">Bırak</button></span></div>';
      }
    }

    uygulama.hazir = true;
    uygulama.sayfadaMi = true;
    if (!uygulama.kosu) {
      menuGoster();
      // Menü teması: ilk kullanıcı etkileşiminde başlar (autoplay kuralı).
      BS.sahne.menuMuzigi();
    }
    // Oyun sayfası açıkken MERGEN Bilge arka fon müziği tamamen susturulur.
    BS.ses.uygulamaMuzigiKis();
  });

  // ── Menü etkileşimi (tek delege dinleyici) ──────────────────────────────────
  document.addEventListener("click", function(e) {
    // Oyun sayfasındaki HER tıklama etkileşim sayılır: autoplay engeline
    // takılıp bekleyen menü/seviye müziği ilk gerçek tıklamada başlar.
    if (uygulama.sayfadaMi && uygulama.hazir &&
        e.target.closest && e.target.closest(".bs-sayfa")) {
      BS.ses.etkilesimIsaretle();
    }

    // Bilge Yolaç karşılama kartından oyuna geçiş.
    var acDugme = e.target.closest("[data-bs-ac]");
    if (acDugme) {
      e.preventDefault();
      var sekme = document.querySelector(
        '.sidebar-menu a[href="#shiny-tab-bilge_savunmasi"]'
      );
      if (sekme) sekme.click();
      return;
    }

    var eylemDugme = e.target.closest("[data-bs-eylem]");
    if (eylemDugme && uygulama.hazir) {
      e.preventDefault();
      BS.ses.etkilesimIsaretle();
      eylemIsle(eylemDugme.getAttribute("data-bs-eylem"));
      return;
    }

    var komutDugme = e.target.closest(".bs-panel [data-bs-komut]");
    if (komutDugme && uygulama.hazir) {
      e.preventDefault();
      BS.ses.etkilesimIsaretle();
      panelKomutIsle(komutDugme.getAttribute("data-bs-komut"),
                     komutDugme.getAttribute("data-bs-arg"));
    }
  });

  function eylemIsle(eylem) {
    if (eylem === "devam-et") {
      kosuBaslat({ mod: BS.veri.init.devam.mod || "kampanya",
                   devam: BS.veri.init.devam });
      return;
    }
    if (eylem === "devam-birak") {
      if (BS.veri.init.devam) BS.kopru.kosuBirak(BS.veri.init.devam.kosu_id);
      BS.veri.init.devam = null;
      var not = el("kalicilik_notu");
      if (not) {
        var kart = not.querySelector(".bs-devam-karti");
        if (kart) kart.remove();
      }
      return;
    }

    BS.menu.panelGoster(uygulama.kok, eylem);
    if (eylem === "haftalik") BS.kopru.liderlikIste();
    else if (eylem === "topluluk") BS.kopru.toplulukIste();
    else if (eylem === "planlar") BS.kopru.planListesiIste();
  }

  function panelKomutIsle(komut, arg) {
    if (komut === "harita-baslat") {
      var parcalar = String(arg || "").split(":");
      kosuBaslat({ mod: "kampanya", harita: parcalar[0], zorluk: parcalar[1] });
    } else if (komut === "haftalik-baslat") {
      kosuBaslat({ mod: "haftalik" });
    } else if (komut === "plan-dene") {
      BS.kopru.planDene(parseInt(arg, 10));
    } else if (komut === "plan-sil") {
      BS.kopru.planSil(parseInt(arg, 10));
    }
  }

  // ── Ayar değişiklikleri: uygulama ve kalıcılaştırma menü katmanındadır ─────
  document.addEventListener("change", function(e) {
    if (e.target && e.target.hasAttribute &&
        e.target.hasAttribute("data-bs-ayar")) BS.menu.ayarIsle(e.target);
  });

  // ── Sunucu yanıtları: panel verileri ────────────────────────────────────────
  BS.olaylar.ekle("sunucu-liderlik", function(veri) {
    BS.veri.liderlik = veri;
    if (panelAcikMi("haftalik")) BS.menu.panelGoster(uygulama.kok, "haftalik");
  });
  BS.olaylar.ekle("sunucu-topluluk", function(veri) {
    BS.veri.topluluk = veri;
    if (panelAcikMi("topluluk")) BS.menu.panelGoster(uygulama.kok, "topluluk");
  });
  BS.olaylar.ekle("sunucu-plan-listesi", function(veri) {
    BS.veri.planlar = (veri && veri.planlar) || [];
    if (panelAcikMi("planlar")) BS.menu.panelGoster(uygulama.kok, "planlar");
  });
  BS.olaylar.ekle("sunucu-plan-yaniti", function(veri) {
    if (veri && veri.silindi) BS.kopru.planListesiIste();
    if (uygulama.kosu && uygulama.kosu.planYayinBekliyor) {
      uygulama.kosu.planYayinBekliyor = false;
      uygulama.kosu.hud.ogreticiGoster(
        veri && veri.tamam
          ? "Savunma planın yayınlandı. Diğer oyuncular artık deneyebilir."
          : "Plan yayınlanamadı; koşu sonucu doğrulanmış olmalı."
      );
    }
  });
  BS.olaylar.ekle("sunucu-plan-config", function(plan) {
    if (!plan || !plan.plan_id) return;
    kosuBaslat({ mod: "plan", plan_id: plan.plan_id, planBilgi: plan });
  });
  BS.olaylar.ekle("sunucu-profil", function(veri) {
    // Kalıcı bir koşu sonuçlandıktan sonra menüye dönüşte istemcinin BAYAT
    // profil/kampanya/kahraman/başarım göstermesini önler (bkz. hud-kaplama
    // "cikis-evet"/"menu-don" -> menuyeDonVeTazele). Tam sayfa açılışı
    // (bs-init) beklemeden ilerleme paketini tazeler.
    if (!veri || !BS.veri.init) return;
    BS.veri.init.profil = veri.profil || null;
    BS.veri.init.kampanya = veri.kampanya || [];
    BS.veri.init.kahraman_ilerlemesi = veri.kahraman_ilerlemesi || [];
    BS.veri.init.basarimlar = veri.basarimlar || [];
    BS.menu.profilOzetiCiz(uygulama.kok);
    var acikPanel = acikPanelAdi();
    if (acikPanel) BS.menu.panelGoster(uygulama.kok, acikPanel);
  });

  BS.olaylar.ekle("sunucu-hata", function(veri) {
    var mesajlar = {
      harita_kilitli: "Bu harita henüz kilitli.",
      plan_bulunamadi: "Plan bulunamadı ya da kaldırılmış.",
      plan_surumu: "Bu plan eski bir sürümle yayınlanmış; denenemiyor.",
      istek_bicimi: "İstek işlenemedi; lütfen tekrar deneyin."
    };
    var not = el("kalicilik_notu");
    if (not && veri) {
      not.innerHTML = '<div class="bs-uyari-karti bs-uyari-hata">' +
        '<i class="fa fa-triangle-exclamation" aria-hidden="true"></i> ' +
        BS.yardimci.htmlKacis(mesajlar[veri.neden] || "İşlem tamamlanamadı.") +
        '</div>';
      setTimeout(function() {
        var kart = not.querySelector(".bs-uyari-hata");
        if (kart) kart.remove();
      }, 6000);
    }
  });

  function panelAcikMi(ad) {
    var alan = uygulama.kok &&
      uygulama.kok.querySelector(".bs-panel-alani");
    return alan && alan.getAttribute("data-bs-acik-panel") === ad;
  }

  function acikPanelAdi() {
    var alan = uygulama.kok &&
      uygulama.kok.querySelector(".bs-panel-alani");
    return (alan && alan.getAttribute("data-bs-acik-panel")) || "";
  }

  // ── Koşu başlatma: önce Öncü Uzman seçim ekranı, sonra sunucu isteği ───────
  function kosuBaslat(istek) {
    if (uygulama.kosu) return;   // aynı anda tek koşu

    // Devam akışı ve aynı yapılandırmayla yeniden başlatma seçimi atlar
    // (öncü zaten bilinir); yeni görevler premium seçim ekranından geçer.
    if (istek.devam || istek.oncu) {
      kosuIstegiGonder(istek);
      return;
    }
    secimEkraniAc(istek);
  }

  function kosuIstegiGonder(istek) {
    uygulama.bekleyenIstek = istek;
    // "Devam Et" akışında harita/zorluk/plan_id üst seviyede DEĞİL,
    // istek.devam altındadır (bkz. sunucu-init "devam" alanı). Bu alanlar
    // düzleştirilmezse sunucu istek çözücüsü harita/zorluk veya plan
    // kimliğini eksik bulur ve devamı reddeder ya da (haftalık modda)
    // sessizce yeni bir koşu başlatır.
    var devam = istek.devam || null;
    BS.kopru.kosuBaslat({
      mod: istek.mod,
      harita: istek.harita || (devam && devam.harita) || null,
      zorluk: istek.zorluk || (devam && devam.zorluk) || null,
      plan_id: istek.plan_id != null ? istek.plan_id :
        ((devam && devam.plan_id != null) ? devam.plan_id : null),
      kosu_id: devam && devam.kosu_id ? devam.kosu_id : null,
      istemci_jetonu: devam && devam.istemci_jetonu ? devam.istemci_jetonu : null
    });
  }

  function secimEkraniAc(istek) {
    // Premium Öncü Uzman seçim ekranı menü katmanındadır; seçim
    // tamamlanınca sunucu isteği buradan gönderilir.
    BS.menu.secimEkraniAc(istek, function(oncu) {
      istek.oncu = oncu;
      kosuIstegiGonder(istek);
    });
  }

  function secimEkraniKapat() {
    BS.menu.secimEkraniKapat();
  }

  BS.olaylar.ekle("sunucu-kosu-basladi", function(veri) {
    if (!veri || uygulama.kosu) return;
    var istek = uygulama.bekleyenIstek || {};
    uygulama.bekleyenIstek = null;

    // Sekmeden ayrılınca gelen gecikmiş yanıt: kullanıcı başlatma isteğini
    // gönderdikten sonra başka bir uygulama sekmesine geçmiş olabilir. Bu
    // durumda hiçbir oyun kaynağı (canvas/klavye dinleyicisi/geri sayım/
    // müzik) oluşturulmaz. Yeni başlatmalarda sunucuda açılan kalıcı koşu
    // hemen bırakılır ki Aktif koşu kilitli kalmasın; Devam Et yanıtlarında
    // ise aynı checkpoint'li koşu kimliği/jetonu yeniden kullanılır, bu yüzden
    // koşuyu bırakmak kullanıcının devam hakkını kaybettirir.
    if (!uygulama.sayfadaMi) {
      if (!istek.devam && veri.kalici && veri.kosu_id) BS.kopru.kosuBirak(veri.kosu_id);
      return;
    }

    var harita = BS.haritalar.haritaAl(veri.harita);
    if (!harita) return;

    // Değiştirici (kimliği) KOŞUNUN KENDİ sezonundan sunucu tarafından
    // çözülüp bu yanıtla birlikte gönderilir (bkz. R/module_bilge_savunmasi.R).
    // İstemcinin "şimdiki" hafta bilgisine (BS.veri.init.haftalik) bakması
    // YANLIŞTIR: hafta dönümünden sonra devam edilen eski bir haftalık koşu,
    // yanlışlıkla yeni haftanın değiştiricisiyle oynanabilir.
    var degistirici = (veri.mod === "haftalik" && veri.degistirici)
      ? veri.degistirici.id : null;

    var sim = BS.sim.olustur({
      haritaId: veri.harita,
      zorluk: veri.zorluk,
      tohum: veri.tohum,
      mod: veri.mod,
      degistirici: degistirici,
      oncu: istek.oncu || null
    });
    if (!sim) return;

    // Devam akışı: varsa son kontrol noktasından durum yükle. "devam" alanı
    // ve menüdeki bant, kontrol noktası olsun ya da olmasın HER ZAMAN
    // temizlenir; aksi halde menüye dönüşte bayat bir "Devam Et" kartı kalır
    // ve tıklanınca ya BS.veri.init.devam.mod'a boş referansla çöker ya da
    // artık kapalı olan bir jetonu yeniden kullanmayı dener.
    if (istek.devam) {
      if (istek.devam.kontrol_durum) {
        try {
          sim.seriYukle(JSON.parse(istek.devam.kontrol_durum));
        } catch (hata) { /* baştan başlar */ }
      }
      BS.veri.init.devam = null;
      var devamNotu = el("kalicilik_notu");
      if (devamNotu) {
        var devamKarti = devamNotu.querySelector(".bs-devam-karti");
        if (devamKarti) devamKarti.remove();
      }
    }

    var personalar = {};
    (BS.veri.init.personalar || []).forEach(function(p) { personalar[p.id] = p; });

    var kap = el("canvas_kabi");
    var cizici = BS.cizim.olustur(kap, harita, {});
    BS.efekt.temizle();

    var arayuz = { seciliKahraman: null, yerlesimKahraman: null,
                   seciliKule: null, yerlesimKule: null,
                   hucre: null, hucreDurumu: null };
    var hud = BS.hud.kur({
      ust: el("hud_ust"), alt: el("hud_alt"),
      yan: el("hud_yan"), kaplama: el("oyun_kaplama")
    }, { sim: sim, arayuz: arayuz, personalar: personalar });

    var girdi = BS.girdi.bagla(cizici, sim, arayuz);

    uygulama.kosu = {
      kosuId: veri.kosu_id || null,
      jeton: veri.istemci_jetonu,
      kalici: !!veri.kalici,
      mod: veri.mod,
      oncu: istek.oncu || null,
      planBilgi: istek.planBilgi || null,
      sim: sim, cizici: cizici, hud: hud, girdi: girdi, arayuz: arayuz,
      hiz: 1, duraklatildi: false, rafId: null, sonKare: 0,
      sonucGonderildi: false, sonKontrolDalga: 0,
      ogreticiAdimi: 0
    };

    oyunGoster();
    cizici.boyutlandir();
    BS.sahne.planRehberiKur(uygulama.kosu, el("hud_yan"));
    BS.sahne.ogreticiIlerlet("baslangic");
    // Tam ekran boyut değişimlerinde tuval yeniden ölçeklenir (tek kurulum).
    BS.sahne.tamEkranDinle(function() {
      if (uygulama.kosu && uygulama.kosu.cizici) {
        uygulama.kosu.cizici.boyutlandir();
      }
    });
    hud.geriSayimGoster(sim.durum.dalgaNo + 1,
                        BS.dalga.patronDalgasiMi(sim.durum.dalgaNo + 1,
                                                 harita.dalgaSayisi));
    geriSayimBaslat();
    BS.sahne.seviyeMuzigi(harita);
    dongulBaslat();
  });

  // ── Geri sayım ──────────────────────────────────────────────────────────────
  function geriSayimBaslat() {
    geriSayimDurdur();
    var kalan = 10;
    uygulama.geriSayim = setInterval(function() {
      kalan -= 1;
      var elGeri = document.getElementById("bs-geri-sayim");
      if (elGeri) elGeri.textContent = String(Math.max(0, kalan));
      if (kalan <= 0) {
        geriSayimDurdur();
        dalgayiBaslat(false);
      }
    }, 1000);
  }

  function geriSayimDurdur() {
    if (uygulama.geriSayim) {
      clearInterval(uygulama.geriSayim);
      uygulama.geriSayim = null;
    }
  }

  function dalgayiBaslat(erken) {
    var kosu = uygulama.kosu;
    if (!kosu || kosu.sim.durum.bitti) return;
    geriSayimDurdur();
    kosu.hud.kaplamaKapat();
    if (kosu.sim.dalgaBaslat(erken)) {
      BS.ses.efekt("dalga");
      if (kosu.sim.durum.dalgaNo === 2) BS.sahne.ogreticiIlerlet("dalga2");
    }
  }

  // ── Oyun döngüsü ────────────────────────────────────────────────────────────
  function dongulBaslat() {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    kosu.sonKare = performance.now();

    function kare(simdi) {
      if (!uygulama.kosu || uygulama.kosu !== kosu) return;
      kosu.rafId = requestAnimationFrame(kare);

      var gercekDt = Math.min(0.1, (simdi - kosu.sonKare) / 1000);
      kosu.sonKare = simdi;

      if (!kosu.duraklatildi && !kosu.sim.durum.bitti) {
        kosu.sim.tick(gercekDt * kosu.hiz);
      }

      BS.efekt.tik(gercekDt);
      olaylariIsle(kosu);
      kosu.cizici.ciz(kosu.sim.durum, kosu.arayuz, gercekDt);
      kosu.hud.guncelle(kosu.sim.durum.sure);
    }
    kosu.rafId = requestAnimationFrame(kare);
  }

  function olaylariIsle(kosu) {
    var olaylar = BS.efekt.kuyrukIsle(kosu.sim.durum);
    olaylar.forEach(function(olay) {
      if (olay.tip === "dalga_bitti") {
        dalgaSonuIsle(kosu, olay.dalga);
      } else if (olay.tip === "kosu_bitti") {
        kosuSonuIsle(kosu, olay.zafer);
      } else if (olay.tip === "patron") {
        kosu.hud.ogreticiGoster("Patron sahada: " + olay.ad + "! Yeteneklerini kullan.");
        BS.ses.efekt("patron");
        setTimeout(function() {
          if (uygulama.kosu === kosu) kosu.hud.ogreticiGoster(null);
        }, 5000);
      } else if (olay.tip === "olum") {
        BS.ses.efekt("vurus");
      } else if (olay.tip === "sizinti") {
        BS.ses.efekt("sizinti");
      }
    });
  }

  function dalgaSonuIsle(kosu, dalgaNo) {
    if (kosu.sim.durum.bitti) return;

    // Kontrol noktası: patron dalgaları ve her 3 dalgada bir.
    var patronMuydu = BS.dalga.patronDalgasiMi(dalgaNo, kosu.sim.durum.harita.dalgaSayisi);
    if (kosu.kosuId && (patronMuydu || dalgaNo % 3 === 0) &&
        dalgaNo > kosu.sonKontrolDalga) {
      kosu.sonKontrolDalga = dalgaNo;
      BS.kopru.kontrolNoktasi(kosu.kosuId, dalgaNo, kosu.sim.seriDurum());
    }

    var sonraki = dalgaNo + 1;
    kosu.hud.geriSayimGoster(sonraki,
      BS.dalga.patronDalgasiMi(sonraki, kosu.sim.durum.harita.dalgaSayisi));
    geriSayimBaslat();
  }

  // ── Koşu sonu ───────────────────────────────────────────────────────────────
  // Doğrulama yaşam döngüsü (zaman aşımı/tekrar dene/bayat yanıt koruması)
  // BS.dogrulama katmanındadır (bilge_savunmasi_dogrulama.js).
  function kosuSonuIsle(kosu, zafer) {
    if (kosu.sonucGonderildi) return;
    kosu.sonucGonderildi = true;
    geriSayimDurdur();
    BS.ses.efekt(zafer ? "zafer" : "yenilgi");
    BS.ses.muzikDurdur();

    var ozet = kosu.sim.ozetPaketi();
    kosu.ozet = ozet;

    if (kosu.kosuId && kosu.kalici) {
      BS.dogrulama.gonder(kosu);
    } else {
      // Kalıcılık yok: yerel gösterim (ödül/kayıt yazılmaz).
      var puan = BS.sonuc.yerelPuan(ozet);
      BS.sonuc.goster(kosu, {
        kabul: true, zafer: zafer, puan: puan.puan, yildiz: puan.yildiz,
        xp: 0, yerel: true
      });
    }
  }

  // ── Girdi/HUD olayları ──────────────────────────────────────────────────────
  BS.olaylar.ekle("girdi-yerlestir", function(veri) {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    var sonucYer = kosu.sim.yerlestir(veri.kahraman, veri.x, veri.y);
    if (sonucYer.tamam) {
      kosu.arayuz.yerlesimKahraman = null;
      kosu.arayuz.seciliKahraman = veri.kahraman;
      kosu.hud.secimGuncelle();
      BS.ses.efekt("yerlestir");
      BS.sahne.ogreticiIlerlet("yerlestirildi");
    } else if (sonucYer.neden === "kaynak") {
      kosu.hud.ogreticiGoster("Yeterli kaynak yok.");
      setTimeout(function() {
        if (uygulama.kosu === kosu) kosu.hud.ogreticiGoster(null);
      }, 2500);
    }
  });

  BS.olaylar.ekle("girdi-kahraman-kisayol", function(veri) {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    var k = kosu.sim.durum.kahramanlar[veri.kahraman];
    if (!k) return;
    kosu.arayuz.yerlesimKule = null;
    kosu.arayuz.seciliKule = null;
    if (k.yerlesik) {
      kosu.arayuz.seciliKahraman = veri.kahraman;
      kosu.arayuz.yerlesimKahraman = null;
    } else {
      kosu.arayuz.yerlesimKahraman =
        kosu.arayuz.yerlesimKahraman === veri.kahraman ? null : veri.kahraman;
      kosu.arayuz.seciliKahraman = null;
    }
    kosu.hud.secimGuncelle();
  });

  // Kule yerleştirme/yükseltme/satış olay bağlayıcıları sahne katmanındadır
  // (BS.sahne.kuleOlaylariniBagla); burada yalnızca kayıt tetiklenir.
  BS.sahne.kuleOlaylariniBagla();

  // Tam ekran: oyun görünümü öğesi hedeflenir; çıkışta da aynı komut.
  BS.olaylar.ekle("hud-tamekran", function() {
    BS.sahne.tamEkranDegistir(el("oyun_gorunumu"));
  });

  BS.olaylar.ekle("girdi-sec", function() {
    if (uygulama.kosu) uygulama.kosu.hud.secimGuncelle();
  });

  BS.olaylar.ekle("girdi-yetenek", function(veri) {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    if (kosu.sim.yetenek(veri.kahraman).tamam) BS.ses.efekt("yetenek");
  });

  BS.olaylar.ekle("girdi-duraklat", function() {
    var kosu = uygulama.kosu;
    if (!kosu || kosu.sim.durum.bitti) return;
    kosu.duraklatildi = !kosu.duraklatildi;
    if (kosu.duraklatildi) {
      geriSayimDurdur();
      kosu.hud.duraklatGoster();
    } else {
      kosu.hud.kaplamaKapat();
      if (kosu.sim.durum.dalgaDurumu === "hazirlik") {
        kosu.hud.geriSayimGoster(kosu.sim.durum.dalgaNo + 1,
          BS.dalga.patronDalgasiMi(kosu.sim.durum.dalgaNo + 1,
                                   kosu.sim.durum.harita.dalgaSayisi));
        geriSayimBaslat();
      }
    }
  });

  BS.olaylar.ekle("girdi-hiz", function() {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    kosu.hiz = kosu.hiz >= 2 ? 1 : 2;
    kosu.hud.hizGoster(kosu.hiz);
  });

  BS.olaylar.ekle("girdi-menu", function() {
    BS.olaylar.yay("girdi-duraklat", {});
  });

  BS.olaylar.ekle("hud-cikis", function() {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    kosu.duraklatildi = true;
    geriSayimDurdur();
    kosu.hud.onayGoster(
      "Koşudan çıkılsın mı? Kaydedilen son kontrol noktasından devam edebilirsin.",
      "cikis-evet"
    );
  });

  BS.olaylar.ekle("hud-yukselt", function(veri) {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    if (kosu.sim.yukselt(veri.kahraman).tamam) {
      BS.ses.efekt("yukselt");
      kosu.hud.secimGuncelle();
    }
  });

  BS.olaylar.ekle("hud-sat", function(veri) {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    if (kosu.sim.sat(veri.kahraman).tamam) {
      kosu.arayuz.seciliKahraman = null;
      kosu.hud.secimGuncelle();
    }
  });

  BS.olaylar.ekle("hud-kaplama", function(veri) {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    var komut = veri.komut;

    if (komut === "dalga-baslat") {
      dalgayiBaslat(true);
    } else if (komut === "devam") {
      kosu.duraklatildi = false;
      kosu.hud.kaplamaKapat();
      if (kosu.sim.durum.dalgaDurumu === "hazirlik" && !kosu.sim.durum.bitti) {
        kosu.hud.geriSayimGoster(kosu.sim.durum.dalgaNo + 1,
          BS.dalga.patronDalgasiMi(kosu.sim.durum.dalgaNo + 1,
                                   kosu.sim.durum.harita.dalgaSayisi));
        geriSayimBaslat();
      }
    } else if (komut === "yeniden") {
      kosu.hud.onayGoster("Koşu baştan başlatılsın mı?", "yeniden-evet");
    } else if (komut === "yeniden-evet") {
      var yeniIstek = {
        mod: kosu.mod,
        harita: kosu.sim.durum.haritaId,
        zorluk: kosu.sim.durum.zorluk,
        plan_id: kosu.planBilgi ? kosu.planBilgi.plan_id : null,
        planBilgi: kosu.planBilgi,
        oncu: kosu.oncu
      };
      if (kosu.kosuId && !kosu.sonucGonderildi) BS.kopru.kosuBirak(kosu.kosuId);
      kosuYokEt();
      kosuBaslat(yeniIstek);
    } else if (komut === "cikis-onay") {
      BS.olaylar.yay("hud-cikis", {});
    } else if (komut === "cikis-evet") {
      // Koşu bitmemiş çıkış: onay metni son kontrol noktasından devam
      // edilebileceğini söyler. Bunu gerçekleştirmek için koşu sunucuda
      // Aktif KALMALIDIR (bs_db_active_run yalnızca Status = Aktif satırları
      // döndürür); bu dalda kasıtlı olarak koşu bırakma isteği GÖNDERİLMEZ.
      // Aksi halde koşu Bırakıldı olur ve kontrol noktası devam edilemez
      // hale gelir.
      menuyeDonVeTazele();
    } else if (komut === "menu-don") {
      if (kosu.kosuId && !kosu.sonucGonderildi) BS.kopru.kosuBirak(kosu.kosuId);
      menuyeDonVeTazele();
    } else if (komut === "plan-yayinla") {
      BS.sonuc.planYayinlaGoster(kosu);
    } else if (komut === "plan-gonder") {
      BS.sonuc.planGonder(kosu);
    } else if (komut === "dogrulama-tekrar") {
      if (kosu.kosuId && kosu.kalici && kosu.ozet && !kosu.sonSonuc) {
        BS.dogrulama.gonder(kosu);
      }
    } else if (komut === "ogretici-kapat") {
      kosu.hud.ogreticiGoster(null);
    }
  });

  // ── Koşu temizliği ──────────────────────────────────────────────────────────
  function kosuYokEt() {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    geriSayimDurdur();
    BS.dogrulama.zamanlayiciDurdur(kosu);
    if (kosu.rafId) cancelAnimationFrame(kosu.rafId);
    if (kosu.girdi) kosu.girdi.coz();
    if (kosu.hud) kosu.hud.temizle();
    if (kosu.cizici) kosu.cizici.yokEt();
    BS.efekt.temizle();
    BS.ses.tumunuDurdur();
    // Koşu tam ekranda yok edildiyse menü normal görünüme döner.
    if (BS.sahne.tamEkranMi()) BS.sahne.tamEkranDegistir(null);
    uygulama.kosu = null;
  }

  // Koşuyu yok edip menüye döner ve menü verilerini tazeler: profil/yıldız/
  // kampanya/kahraman ilerlemesi/liderlik, kalıcı bir sonuçlandırmadan sonra
  // değişmiş olabilir (bkz. "sunucu-profil").
  function menuyeDonVeTazele() {
    kosuYokEt();
    menuGoster();
    BS.sahne.menuMuzigi();
    BS.kopru.liderlikIste();
    BS.kopru.toplulukIste();
    BS.kopru.profilYenileIste();
  }

  // ── Sekme/görünürlük yaşam döngüsü ──────────────────────────────────────────
  function sayfadanAyrildi() {
    var kosu = uygulama.kosu;
    if (!kosu) return;
    // Motor durdurulur; koşu duraklatılmış olarak bekler (dönünce devam).
    kosu.duraklatildi = true;
    geriSayimDurdur();
    if (kosu.rafId) {
      cancelAnimationFrame(kosu.rafId);
      kosu.rafId = null;
    }
    // Belge düzeyinde klavye dinleyicisi (Boşluk/F/Esc/1-5, bkz.
    // bilge_savunmasi_girdi.js) sekmeden ayrılınca ÇÖZÜLMELİDİR; aksi
    // halde bu tuşlar koşu yok edilene kadar diğer uygulama sayfalarında
    // da preventDefault() ile ele geçirilmeye devam eder.
    if (kosu.girdi) {
      kosu.girdi.coz();
      kosu.girdi = null;
    }
    BS.ses.tumunuDurdur();
  }

  function sayfayaDonuldu() {
    BS.ses.uygulamaMuzigiKis();
    // Ayrılırken durdurulan oyun müziği (menü ya da seviye grubu) sürer.
    BS.ses.muzikSurdur();
    var kosu = uygulama.kosu;
    if (!kosu || kosu.rafId) return;
    // sayfadanAyrildi() sırasında çözülen klavye/fare dinleyicisini,
    // aynı canvas/sim/arayuz bağlamıyla yeniden bağla.
    if (!kosu.girdi) {
      kosu.girdi = BS.girdi.bagla(kosu.cizici, kosu.sim, kosu.arayuz);
    }
    kosu.cizici.boyutlandir();
    // Koşu zaten bitmişse sunucu tarafından doğrulanmış sonuç kaplaması
    // (BS.sonuc.goster) gösteriliyor olabilir; duraklatma kaplamasıyla
    // ÜZERİNE YAZILMAZ, aksi halde "Menüye Dön"/"Planı Yayınla" gibi
    // doğrulanmış sonuç eylemleri gizlenir.
    if (!kosu.sim.durum.bitti) {
      kosu.hud.duraklatGoster();
    }
    dongulBaslat();
  }

  if (window.jQuery) {
    window.jQuery(document).on("shiny:inputchanged", function(e) {
      if (e.name !== "tabs") return;
      if (e.value === "bilge_savunmasi") {
        uygulama.sayfadaMi = true;
        BS.ses.uygulamaMuzigiKis();
        setTimeout(sayfayaDonuldu, 250);
      } else {
        uygulama.sayfadaMi = false;
        sayfadanAyrildi();
        // Menü müziği koşu olmasa da durur (sayfadanAyrildi koşuya bağlıdır).
        BS.ses.tumunuDurdur();
        secimEkraniKapat();
        // Sayfadan ayrılınca MERGEN Bilge müziği normale döner.
        BS.ses.uygulamaMuzigiBirak();
      }
    });
  }

  document.addEventListener("visibilitychange", function() {
    // Görünürlük olayları globaldir; yalnızca oyun sekmesindeyken uygulanır.
    if (!uygulama.sayfadaMi) return;
    if (document.hidden) {
      sayfadanAyrildi();
      BS.ses.tumunuDurdur();
    } else {
      // Koşu yoksa da menü müziği sürer (sayfayaDonuldu koşusuz güvenlidir).
      sayfayaDonuldu();
    }
  });

  window.addEventListener("resize", function() {
    if (uygulama.kosu && uygulama.kosu.cizici) {
      uygulama.kosu.cizici.boyutlandir();
    }
  });
})();
