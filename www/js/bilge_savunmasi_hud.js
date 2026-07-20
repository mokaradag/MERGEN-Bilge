// www/js/bilge_savunmasi_hud.js
// Bilge Savunması HUD katmanı: üst durum çubuğu (çekirdek/kaynak/dalga/hız/
// duraklat), alt kahraman çubuğu (portreli kartlar + yetenek düğmeleri), yan
// panel (seçili kahraman yükseltme/satış + sonraki dalga önizlemesi) ve tam
// ekran kaplamalar (geri sayım, patron uyarısı, zafer/yenilgi, duraklatma,
// öğretici). Tüm dinamik metin BS.yardimci.htmlKacis süzgecinden geçer;
// düğmeler klavye erişilebilirdir ve durum yalnızca renkle anlatılmaz.

(function() {
  "use strict";

  var BS = window.BilgeSavunmasi = window.BilgeSavunmasi || {};
  var kacis = function(m) { return BS.yardimci.htmlKacis(m); };

  BS.hud = {

    kur: function(baglar, baglam) {
      var hud = {
        baglar: baglar,          // { ust, alt, yan, kaplama }
        sim: baglam.sim,
        arayuz: baglam.arayuz,
        personalar: baglam.personalar,   // id -> manifest kaydı
        sonGuncelleme: 0,
        dinleyiciler: []
      };

      function dinle(hedef, islev) {
        var sarici = function(e) {
          var dugme = e.target.closest("[data-bs-komut]");
          if (!dugme) return;
          e.preventDefault();
          islev(dugme.getAttribute("data-bs-komut"),
                dugme.getAttribute("data-bs-arg"), dugme);
        };
        hedef.addEventListener("click", sarici);
        hud.dinleyiciler.push({ hedef: hedef, islev: sarici });
      }

      // ── Üst çubuk ─────────────────────────────────────────────────────────
      hud.baglar.ust.innerHTML =
        '<div class="bs-ust-grup bs-ust-durum">' +
          '<span class="bs-ust-oge" id="bs-ust-cekirdek" role="status" ' +
                'aria-label="Bilgi Çekirdeği sağlığı"></span>' +
          '<span class="bs-ust-oge" id="bs-ust-kaynak" role="status" ' +
                'aria-label="Kaynak"></span>' +
          '<span class="bs-ust-oge" id="bs-ust-dalga" role="status" ' +
                'aria-label="Dalga"></span>' +
        '</div>' +
        '<div class="bs-ust-grup bs-ust-kontroller">' +
          '<button type="button" class="bs-ust-dugme" data-bs-komut="hiz" ' +
                  'id="bs-dugme-hiz" aria-label="Oyun hızını değiştir">1x</button>' +
          '<button type="button" class="bs-ust-dugme" data-bs-komut="duraklat" ' +
                  'id="bs-dugme-duraklat" aria-label="Duraklat">' +
            '<i class="fa fa-pause" aria-hidden="true"></i></button>' +
          '<button type="button" class="bs-ust-dugme" data-bs-komut="tamekran" ' +
                  'id="bs-dugme-tamekran" aria-label="Tam ekran">' +
            '<i class="fa fa-expand" aria-hidden="true"></i></button>' +
          '<button type="button" class="bs-ust-dugme" data-bs-komut="menu" ' +
                  'aria-label="Koşudan çık">' +
            '<i class="fa fa-door-open" aria-hidden="true"></i> Çık</button>' +
        '</div>';

      // ── Kahraman + kule çubuğu ────────────────────────────────────────────
      var kuleIkonlari = {
        gozetleme: "fa-tower-observation",
        veri_topu: "fa-burst",
        kripto_isik: "fa-gem"
      };
      var kuleKartlari = Object.keys(BS.denge.kuleler).map(function(tip) {
        var tanim = BS.denge.kuleAl(tip);
        return (
          '<div class="bs-kule-karti" id="bs-kule-kart-' + kacis(tip) + '">' +
            '<button type="button" class="bs-kule-sec" data-bs-komut="kule" ' +
                    'data-bs-arg="' + kacis(tip) + '" ' +
                    'title="' + kacis(tanim.ad + ": " + tanim.aciklama) + '" ' +
                    'aria-label="' + kacis(tanim.ad) + '">' +
              '<span class="bs-kule-ikon" aria-hidden="true">' +
                '<i class="fa ' + (kuleIkonlari[tip] || "fa-chess-rook") +
                '"></i></span>' +
              '<span class="bs-kule-ad">' + kacis(tanim.ad) + '</span>' +
              '<span class="bs-kule-maliyet" id="bs-kule-maliyet-' + kacis(tip) +
                '">' + tanim.maliyet + '</span>' +
            '</button>' +
          '</div>'
        );
      }).join("");

      var kahramanSirasi = ["emre", "selin", "deniz", "can", "ipek"];
      hud.baglar.alt.innerHTML = kahramanSirasi.map(function(id) {
        var persona = hud.personalar[id] || { ad: id, aksan: "#4cc9f0" };
        var tanim = BS.denge.kahramanAl(id);
        return (
          '<div class="bs-kahraman-karti" id="bs-kart-' + kacis(id) + '" ' +
               'style="--bs-aksan:' + kacis(persona.aksan) + '">' +
            '<button type="button" class="bs-kahraman-sec" data-bs-komut="kahraman" ' +
                    'data-bs-arg="' + kacis(id) + '" ' +
                    'aria-label="' + kacis(persona.ad + " - " + persona.rol) + '">' +
              '<span class="bs-kahraman-portre">' +
                '<img src="' + kacis(persona.portre || persona.avatar || "") + '" ' +
                     'alt="" loading="lazy" ' +
                     "onerror=\"this.style.display='none';" +
                     "this.parentElement.classList.add('bs-portre-yedek');" +
                     "this.parentElement.setAttribute('data-harf','" +
                     kacis((persona.ad || "?").charAt(0)) + "')\">" +
              '</span>' +
              '<span class="bs-kahraman-ad">' + kacis(persona.ad) + '</span>' +
              '<span class="bs-kahraman-alt" id="bs-kart-alt-' + kacis(id) + '">' +
                kacis(String(tanim.maliyet)) + '</span>' +
            '</button>' +
            '<button type="button" class="bs-yetenek-dugme" data-bs-komut="yetenek" ' +
                    'data-bs-arg="' + kacis(id) + '" id="bs-yetenek-' + kacis(id) + '" ' +
                    'aria-label="' + kacis(persona.yetenek_ad || "Yetenek") + '" ' +
                    'title="' + kacis((persona.yetenek_ad || "") + ": " +
                                      (persona.yetenek_aciklama || "")) + '">' +
              '<i class="fa fa-bolt" aria-hidden="true"></i>' +
            '</button>' +
          '</div>'
        );
      }).join("") +
        '<span class="bs-alt-ayrac" aria-hidden="true"></span>' + kuleKartlari;

      // ── Yan panel ─────────────────────────────────────────────────────────
      hud.baglar.yan.innerHTML =
        '<div class="bs-yan-bolum" id="bs-yan-secim">' +
          '<h4 class="bs-yan-baslik">Savunucu</h4>' +
          '<div id="bs-secim-icerik" class="bs-secim-icerik">' +
            '<p class="bs-yan-notu">Bir savunucu seçin veya alttaki kartlardan ' +
            'yerleştirin.</p></div>' +
        '</div>' +
        '<div class="bs-yan-bolum" id="bs-yan-dalga">' +
          '<h4 class="bs-yan-baslik">Sonraki Dalga</h4>' +
          '<div id="bs-dalga-onizleme" class="bs-dalga-onizleme"></div>' +
        '</div>';

      // ── Komut yönlendirme ─────────────────────────────────────────────────
      dinle(hud.baglar.ust, function(komut) {
        if (komut === "hiz") BS.olaylar.yay("girdi-hiz", {});
        else if (komut === "duraklat") BS.olaylar.yay("girdi-duraklat", {});
        else if (komut === "tamekran") BS.olaylar.yay("hud-tamekran", {});
        else if (komut === "menu") BS.olaylar.yay("hud-cikis", {});
      });

      dinle(hud.baglar.alt, function(komut, arg) {
        if (komut === "kahraman") {
          BS.olaylar.yay("girdi-kahraman-kisayol", { kahraman: arg });
        } else if (komut === "yetenek") {
          BS.olaylar.yay("girdi-yetenek", { kahraman: arg });
        } else if (komut === "kule") {
          BS.olaylar.yay("girdi-kule-kisayol", { kule: arg });
        }
      });

      dinle(hud.baglar.yan, function(komut, arg) {
        if (komut === "yukselt") BS.olaylar.yay("hud-yukselt", { kahraman: arg });
        else if (komut === "sat") BS.olaylar.yay("hud-sat", { kahraman: arg });
        else if (komut === "tasi") BS.olaylar.yay("hud-tasi", { kahraman: arg });
        else if (komut === "kule-yukselt") {
          BS.olaylar.yay("hud-kule-yukselt", { kule: parseInt(arg, 10) });
        } else if (komut === "kule-sat") {
          BS.olaylar.yay("hud-kule-sat", { kule: parseInt(arg, 10) });
        }
      });

      dinle(hud.baglar.kaplama, function(komut, arg) {
        BS.olaylar.yay("hud-kaplama", { komut: komut, arg: arg });
      });

      // ── Kare güncellemesi (sayılar ~5 Hz, durum sınıfları her karede) ─────
      hud.guncelle = function(simdikiZaman) {
        var durum = hud.sim.durum;

        if (simdikiZaman - hud.sonGuncelleme > 0.2) {
          hud.sonGuncelleme = simdikiZaman;

          var cekirdekEl = document.getElementById("bs-ust-cekirdek");
          if (cekirdekEl) {
            var kalkanMetni = durum.cekirdekKalkani > 0
              ? ' <span class="bs-kalkan-degeri">+' +
                Math.round(durum.cekirdekKalkani) + '</span>' : "";
            cekirdekEl.innerHTML =
              '<i class="fa fa-shield-halved" aria-hidden="true"></i> ' +
              Math.max(0, Math.round(durum.cekirdek)) + "/" +
              durum.tabanCekirdek + kalkanMetni;
            cekirdekEl.className = "bs-ust-oge " +
              (durum.cekirdek / durum.tabanCekirdek > 0.6 ? "bs-durum-iyi" :
               (durum.cekirdek / durum.tabanCekirdek > 0.3 ? "bs-durum-orta"
                                                           : "bs-durum-kritik"));
          }
          var kaynakEl = document.getElementById("bs-ust-kaynak");
          if (kaynakEl) {
            kaynakEl.innerHTML =
              '<i class="fa fa-database" aria-hidden="true"></i> ' +
              BS.yardimci.sayiBicimle(durum.kaynak);
          }
          var dalgaEl = document.getElementById("bs-ust-dalga");
          if (dalgaEl) {
            dalgaEl.innerHTML =
              '<i class="fa fa-water" aria-hidden="true"></i> Dalga ' +
              durum.dalgaNo + "/" + durum.harita.dalgaSayisi;
          }

          hud.kahramanKartlariGuncelle(durum);
          hud.dalgaOnizlemeGuncelle(durum);
        }
      };

      hud.kahramanKartlariGuncelle = function(durum) {
        Object.keys(durum.kahramanlar).forEach(function(id) {
          var kart = document.getElementById("bs-kart-" + id);
          var altEl = document.getElementById("bs-kart-alt-" + id);
          var yetenekEl = document.getElementById("bs-yetenek-" + id);
          if (!kart) return;
          var k = durum.kahramanlar[id];
          var tanim = BS.denge.kahramanAl(id);
          var maliyet = hud.sim.yerlesimMaliyeti
            ? hud.sim.yerlesimMaliyeti(id) : tanim.maliyet;

          kart.classList.toggle("bs-kart-sahada", k.yerlesik);
          kart.classList.toggle("bs-kart-yetersiz",
                                !k.yerlesik && durum.kaynak < maliyet);
          kart.classList.toggle("bs-kart-yerlesim",
                                hud.arayuz.yerlesimKahraman === id);
          kart.classList.toggle("bs-kart-secili",
                                hud.arayuz.seciliKahraman === id);
          kart.classList.toggle("bs-kart-oncu", durum.oncu === id);

          if (altEl) {
            altEl.textContent = k.yerlesik
              ? "Sahada · K" + (k.seviye + 1)
              : (maliyet === 0 ? "Öncü · Ücretsiz" : String(maliyet));
          }
          if (yetenekEl) {
            var hazir = k.yerlesik && k.yetenekKalan <= 0;
            yetenekEl.disabled = !hazir;
            yetenekEl.classList.toggle("bs-yetenek-hazir", hazir);
            yetenekEl.setAttribute("aria-disabled", hazir ? "false" : "true");
            if (k.yetenekKalan > 0) {
              yetenekEl.innerHTML = Math.ceil(k.yetenekKalan) + "s";
            } else {
              yetenekEl.innerHTML = '<i class="fa fa-bolt" aria-hidden="true"></i>';
            }
          }
        });

        // Kule kartları: karşılanabilirlik ve yerleşim modu vurgusu.
        Object.keys(BS.denge.kuleler).forEach(function(tip) {
          var kart = document.getElementById("bs-kule-kart-" + tip);
          if (!kart) return;
          var tanim = BS.denge.kuleAl(tip);
          kart.classList.toggle("bs-kart-yetersiz", durum.kaynak < tanim.maliyet);
          kart.classList.toggle("bs-kart-yerlesim",
                                hud.arayuz.yerlesimKule === tip);
        });
      };

      // Seçili kule paneli: istatistik + yükselt/sat düğmeleri.
      hud.kuleSecimGuncelle = function(icerik) {
        var durum = hud.sim.durum;
        var kule = hud.sim.kuleNoIleBul
          ? hud.sim.kuleNoIleBul(hud.arayuz.seciliKule) : null;
        if (!kule) return false;

        var tanim = BS.denge.kuleAl(kule.tip);
        var ist = BS.denge.kuleIstatistik(kule.tip, kule.seviye);
        var sonrakiYuk = kule.seviye < tanim.yukseltmeler.length
          ? tanim.yukseltmeler[kule.seviye] : null;
        var iade = Math.round(BS.denge.kuleYatirim(kule.tip, kule.seviye) *
                              BS.denge.ekonomi.satisIadeOrani);

        icerik.innerHTML =
          '<div class="bs-secim-baslik" style="--bs-aksan:#8ecae6">' +
            '<strong>' + kacis(tanim.ad) + '</strong>' +
            '<span>Kule · Kademe ' + (kule.seviye + 1) + '</span></div>' +
          '<ul class="bs-secim-istatistik">' +
            '<li>Hasar <b>' + Math.round(ist.hasar) + '</b></li>' +
            '<li>Menzil <b>' + ist.menzil.toFixed(1) + '</b></li>' +
            '<li>Atış <b>' + ist.atisAraligi.toFixed(2) + 's</b></li>' +
            (ist.alanYaricapi > 0
              ? '<li>Alan <b>' + ist.alanYaricapi.toFixed(1) + '</b></li>' : "") +
            (ist.zirhDelme > 0
              ? '<li>Zırh Delme <b>%' + Math.round(ist.zirhDelme * 100) +
                '</b></li>' : "") +
          '</ul>' +
          (sonrakiYuk
            ? '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
              'data-bs-komut="kule-yukselt" data-bs-arg="' + kule.no + '" ' +
              (durum.kaynak < sonrakiYuk.maliyet ? "disabled " : "") + '>' +
              '<i class="fa fa-arrow-up" aria-hidden="true"></i> Yükselt (' +
              sonrakiYuk.maliyet + ')</button>' +
              '<p class="bs-yan-aciklama">' + kacis(sonrakiYuk.aciklama) + '</p>'
            : '<p class="bs-yan-aciklama">En yüksek kademede.</p>') +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="kule-sat" ' +
                  'data-bs-arg="' + kule.no + '" ' +
                  'title="Kule kaldırılır; yatırımın bir bölümü geri döner">' +
            '<i class="fa fa-rotate-left" aria-hidden="true"></i> Sök (+' +
            iade + ')</button>';
        return true;
      };

      hud.secimGuncelle = function() {
        var icerik = document.getElementById("bs-secim-icerik");
        if (!icerik) return;
        var id = hud.arayuz.seciliKahraman;
        var durum = hud.sim.durum;

        if (!id || !durum.kahramanlar[id] || !durum.kahramanlar[id].yerlesik) {
          if (hud.arayuz.seciliKule && hud.kuleSecimGuncelle(icerik)) return;
          icerik.innerHTML =
            '<p class="bs-yan-notu">Bir savunucu/kule seçin veya alttaki ' +
            'kartlardan yerleştirin.</p>';
          return;
        }

        var k = durum.kahramanlar[id];
        var tanim = BS.denge.kahramanAl(id);
        var persona = hud.personalar[id] || { ad: id };
        var ist = BS.denge.kahramanIstatistik(id, k.seviye);
        var sonrakiYuk = k.seviye < tanim.yukseltmeler.length
          ? tanim.yukseltmeler[k.seviye] : null;
        var iade = Math.round(BS.denge.kahramanYatirim(id, k.seviye) *
                              BS.denge.ekonomi.satisIadeOrani);

        icerik.innerHTML =
          '<div class="bs-secim-baslik" style="--bs-aksan:' +
              kacis(persona.aksan || "#4cc9f0") + '">' +
            '<strong>' + kacis(persona.ad) + '</strong>' +
            '<span>' + kacis(persona.rol || "") + ' · Kademe ' + (k.seviye + 1) +
            '</span></div>' +
          '<ul class="bs-secim-istatistik">' +
            '<li>Hasar <b>' + Math.round(ist.hasar) + '</b></li>' +
            '<li>Menzil <b>' + ist.menzil.toFixed(1) + '</b></li>' +
            '<li>Atış <b>' + ist.atisAraligi.toFixed(2) + 's</b></li>' +
          '</ul>' +
          (sonrakiYuk
            ? '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
              'data-bs-komut="yukselt" data-bs-arg="' + kacis(id) + '" ' +
              (durum.kaynak < sonrakiYuk.maliyet ? "disabled " : "") + '>' +
              '<i class="fa fa-arrow-up" aria-hidden="true"></i> Yükselt (' +
              sonrakiYuk.maliyet + ')</button>' +
              '<p class="bs-yan-aciklama">' + kacis(sonrakiYuk.aciklama) + '</p>'
            : '<p class="bs-yan-aciklama">En yüksek kademede.</p>') +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="sat" ' +
                  'data-bs-arg="' + kacis(id) + '" ' +
                  'title="Satış bir kademe düşürür; savunucu yeniden yerleştirilebilir">' +
            '<i class="fa fa-rotate-left" aria-hidden="true"></i> Geri Çek (+' +
            iade + ')</button>';
      };

      hud.dalgaOnizlemeGuncelle = function(durum) {
        var kutu = document.getElementById("bs-dalga-onizleme");
        if (!kutu) return;
        var sonrakiNo = durum.dalgaNo + 1;
        if (sonrakiNo > durum.harita.dalgaSayisi) {
          kutu.innerHTML = '<p class="bs-yan-notu">Son dalga! Çekirdeği koru.</p>';
          return;
        }
        var kayit = durum.dalgalar[sonrakiNo - 1];
        var ozet = BS.dalga.kompozisyonOzeti(kayit);
        kutu.innerHTML =
          '<div class="bs-onizleme-baslik">Dalga ' + sonrakiNo +
          (kayit.patronMu ? ' · <span class="bs-patron-etiketi">PATRON</span>' : "") +
          '</div>' +
          ozet.map(function(satir) {
            return '<div class="bs-onizleme-satir">' +
              '<span class="bs-onizleme-nokta" style="background:' +
                kacis(satir.renk) + '" aria-hidden="true"></span>' +
              '<span>' + kacis(satir.ad) + '</span>' +
              '<b>×' + satir.adet + '</b></div>';
          }).join("");
      };

      // ── Kaplamalar ────────────────────────────────────────────────────────
      hud.kaplamaGoster = function(icHtml, sinif) {
        hud.baglar.kaplama.classList.remove("bs-geri-sayim-kaplama",
                                            "bs-kaplama-saydam");
        hud.baglar.kaplama.innerHTML =
          '<div class="bs-kaplama-panel ' + (sinif || "") + '">' + icHtml + '</div>';
        hud.baglar.kaplama.classList.add("bs-kaplama-acik");
      };

      hud.kaplamaKapat = function() {
        hud.baglar.kaplama.classList.remove("bs-kaplama-acik",
                                            "bs-geri-sayim-kaplama",
                                            "bs-kaplama-saydam");
        hud.baglar.kaplama.innerHTML = "";
      };

      hud.geriSayimGoster = function(dalgaNo, patronMu) {
        hud.kaplamaGoster(
          '<h3>' + (patronMu ? "PATRON DALGASI" : "Dalga " + dalgaNo) + '</h3>' +
          '<p id="bs-geri-sayim" class="bs-geri-sayim" role="timer">10</p>' +
          (patronMu ? '<p class="bs-kaplama-notu">Büyük bir tehdit yaklaşıyor. ' +
            'Savunucularını ve yeteneklerini hazırla.</p>' : "") +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                  'data-bs-komut="dalga-baslat">' +
            '<i class="fa fa-play" aria-hidden="true"></i> Dalgayı Başlat (+' +
            BS.denge.ekonomi.erkenBaslatmaBonusu + ' kaynak)</button>',
          patronMu ? "bs-kaplama-patron" : ""
        );
        hud.baglar.kaplama.classList.add("bs-geri-sayim-kaplama");
      };

      hud.duraklatGoster = function() {
        hud.kaplamaGoster(
          '<h3>Duraklatıldı</h3>' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-birincil" ' +
                  'data-bs-komut="devam"><i class="fa fa-play" aria-hidden="true"></i> ' +
                  'Devam Et</button>' +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="yeniden">' +
            '<i class="fa fa-rotate-right" aria-hidden="true"></i> Yeniden Başlat</button>' +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="cikis-onay">' +
            '<i class="fa fa-door-open" aria-hidden="true"></i> Koşudan Çık</button>'
        );
      };

      hud.onayGoster = function(mesaj, komut) {
        hud.kaplamaGoster(
          '<h3>Emin misiniz?</h3><p class="bs-kaplama-notu">' + kacis(mesaj) + '</p>' +
          '<button type="button" class="bs-yan-dugme bs-yan-dugme-tehlike" ' +
                  'data-bs-komut="' + kacis(komut) + '">Evet</button>' +
          '<button type="button" class="bs-yan-dugme" data-bs-komut="devam">Vazgeç</button>'
        );
      };

      hud.ogreticiGoster = function(metin) {
        var eski = hud.baglar.kaplama.querySelector(".bs-ogretici");
        if (eski) eski.remove();
        var panelVar = !!hud.baglar.kaplama.querySelector(".bs-kaplama-panel");
        if (!metin) {
          // Panel yoksa kaplama tamamen kapanır; karartma ve tıklama
          // kilidi bilgi balonunun ömrüne bağlıdır, patronun ömrüne değil.
          if (!panelVar) {
            hud.baglar.kaplama.classList.remove("bs-kaplama-acik",
                                                "bs-kaplama-saydam");
          }
          return;
        }
        var kutu = document.createElement("div");
        kutu.className = "bs-ogretici";
        kutu.setAttribute("role", "note");
        kutu.innerHTML = '<i class="fa fa-graduation-cap" aria-hidden="true"></i> ' +
          '<span class="bs-ogretici-metin">' + kacis(metin) + '</span>' +
          '<button type="button" class="bs-ogretici-kapat" ' +
                  'data-bs-komut="ogretici-kapat" aria-label="Bilgiyi kapat">' +
            '<i class="fa fa-xmark" aria-hidden="true"></i></button>';
        hud.baglar.kaplama.appendChild(kutu);
        hud.baglar.kaplama.classList.add("bs-kaplama-acik");
        // Yalnızca bilgi balonu varken sahne kararmaz, tıklamalar engellenmez.
        hud.baglar.kaplama.classList.toggle("bs-kaplama-saydam", !panelVar);
      };

      hud.hizGoster = function(hiz) {
        var dugme = document.getElementById("bs-dugme-hiz");
        if (dugme) dugme.textContent = hiz + "x";
      };

      hud.temizle = function() {
        hud.dinleyiciler.forEach(function(kayit) {
          kayit.hedef.removeEventListener("click", kayit.islev);
        });
        hud.dinleyiciler = [];
        hud.baglar.ust.innerHTML = "";
        hud.baglar.alt.innerHTML = "";
        hud.baglar.yan.innerHTML = "";
        hud.baglar.kaplama.innerHTML = "";
        hud.baglar.kaplama.classList.remove("bs-kaplama-acik",
                                            "bs-geri-sayim-kaplama",
                                            "bs-kaplama-saydam");
      };

      return hud;
    }
  };
})();
