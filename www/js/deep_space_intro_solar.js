// ==============================================================================
// Dosya Yolu: www/js/deep_space_intro_solar.js
// Açıklama: Derin uzay giriş sahnesindeki Güneş, lens parlama, ortam ışığı ve
// bloom kurulumunu yönetir. Ana deep_space_intro.js dosyasını bakım bütçesi
// altında tutmak için ayrı modüle çıkarılmıştır.
// ==============================================================================

window.DeepSpaceIntroSolar = (function() {
  'use strict';

  // Lens parlama dokusu oluştur.
  function createFlareTexture(THREE, r, g, b, size, alpha) {
    var canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;

    var ctx = canvas.getContext('2d');
    var half = size / 2;
    var gradient = ctx.createRadialGradient(half, half, 0, half, half, half);

    gradient.addColorStop(0, 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')');
    gradient.addColorStop(0.4, 'rgba(' + r + ',' + g + ',' + b + ',' + (alpha * 0.34) + ')');
    gradient.addColorStop(1, 'rgba(0,0,0,0)');

    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, size, size);

    var tex = new THREE.CanvasTexture(canvas);
    tex.encoding = THREE.sRGBEncoding;
    return tex;
  }

  function createSunGlowTexture(THREE) {
    var haloCanvas = document.createElement('canvas');
    haloCanvas.width = 256;
    haloCanvas.height = 256;

    var hctx = haloCanvas.getContext('2d');
    var haloGrad = hctx.createRadialGradient(128, 128, 0, 128, 128, 128);

    // Uzaydan bakışta Güneş beyaza yakın görünür. Geniş yarı saydam hale
    // azaltılır; aksi halde yıldız alanı halesinin içinden görünüp "bulut"
    // hissi oluşturur.
    haloGrad.addColorStop(0, 'rgba(255,255,255,1)');
    haloGrad.addColorStop(0.08, 'rgba(255,255,255,0.92)');
    haloGrad.addColorStop(0.22, 'rgba(240,246,255,0.24)');
    haloGrad.addColorStop(0.42, 'rgba(220,232,255,0.05)');
    haloGrad.addColorStop(1, 'rgba(0,0,0,0)');

    hctx.fillStyle = haloGrad;
    hctx.fillRect(0, 0, 256, 256);

    var glowTex = new THREE.CanvasTexture(haloCanvas);
    glowTex.encoding = THREE.sRGBEncoding;
    return glowTex;
  }

  function createComposer(THREE, renderer, scene, camera, container) {
    var hasPostProcessing =
      typeof THREE.EffectComposer === 'function' &&
      typeof THREE.RenderPass === 'function' &&
      typeof THREE.UnrealBloomPass === 'function' &&
      typeof THREE.ShaderPass === 'function' &&
      typeof THREE.CopyShader !== 'undefined' &&
      typeof THREE.LuminosityHighPassShader !== 'undefined';

    if (!hasPostProcessing) {
      console.log('[DeepSpaceIntro] Post-processing bağımlılıkları bulunamadı, doğrudan render kullanılacak.');
      return null;
    }

    try {
      var composer = new THREE.EffectComposer(renderer);
      composer.addPass(new THREE.RenderPass(scene, camera));

      var bloom = new THREE.UnrealBloomPass(
        new THREE.Vector2(container.clientWidth, container.clientHeight),
        1.5,
        0.4,
        0.85
      );

      // Bloom dar tutulur: Güneş beyaz ve parlak kalır, fakat Samanyolu
      // üzerinde geniş sis/bulut etkisi oluşmaz.
      bloom.threshold = 0.97;
      bloom.strength = 0.5;
      bloom.radius = 0.28;

      composer.addPass(bloom);
      return composer;
    } catch (e) {
      console.warn('[DeepSpaceIntro] Post-processing devre dışı bırakıldı:', e.message);
      return null;
    }
  }

  function setup(options) {
    var THREE = options.THREE || window.THREE;
    var scene = options.scene;
    var renderer = options.renderer;
    var camera = options.camera;
    var container = options.container;

    // Fiziksel tutarlılık:
    // Sahnenin yerel Dünya-Ay referans düzlemi XZ düzlemidir. Güneş de bu
    // ekliptik referans düzleminde tutulur. Dünya'nın 23.5° eksen eğimi
    // ayrı olarak yalnızca earthTiltGroup üzerinde uygulanır.
    var sunPos = new THREE.Vector3(1100, 0, 850);

    // Güneş ışığı, yüzey ayrıntısını patlatmadan bir miktar güçlendirilir.
    // Dünya'yı aydınlatan fiziksel ışık ile görünen Güneş parlaması ayrıdır.
    // Bu değer çöl bölgelerinin patlamasını önlemek için kontrollü tutulur.
    var sunLight = new THREE.DirectionalLight(0xffffff, 2.55);
    sunLight.position.copy(sunPos);
    sunLight.castShadow = true;

    // 2048 gölge haritası kalite/bellek dengesini korur.
    sunLight.shadow.mapSize.width = 2048;
    sunLight.shadow.mapSize.height = 2048;
    sunLight.shadow.camera.near = 10;
    sunLight.shadow.camera.far = 5000;
    sunLight.shadow.bias = -0.0005;

    var shadowSize = 100;
    sunLight.shadow.camera.left = -shadowSize;
    sunLight.shadow.camera.right = shadowSize;
    sunLight.shadow.camera.top = shadowSize;
    sunLight.shadow.camera.bottom = -shadowSize;
    scene.add(sunLight);

    if (typeof THREE.Lensflare !== 'undefined') {
      var textureFlare0 = createFlareTexture(THREE, 255, 255, 255, 512, 1.0);
      var textureFlare3 = createFlareTexture(THREE, 225, 235, 255, 128, 0.56);
      var textureFlareHex = createFlareTexture(THREE, 245, 248, 255, 256, 0.16);

      var lensflare = new THREE.Lensflare();
      lensflare.addElement(new THREE.LensflareElement(textureFlare0, 860, 0));
      lensflare.addElement(new THREE.LensflareElement(textureFlareHex, 84, 0.3));
      lensflare.addElement(new THREE.LensflareElement(textureFlare3, 96, 0.5));
      lensflare.addElement(new THREE.LensflareElement(textureFlareHex, 160, 0.4));
      sunLight.add(lensflare);
    }

    // Güneş geometrisi: görünen güneş biraz büyütülür, ancak Dünya ışığı
    // ayrı DirectionalLight ile yönetildiği için kıtalar aşırı parlamaz.
    var sunGeo = new THREE.SphereGeometry(54, 64, 64);
    var sunMat = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      transparent: false
    });
    var sunMesh = new THREE.Mesh(sunGeo, sunMat);
    sunMesh.position.copy(sunPos);
    scene.add(sunMesh);

    var glowMat = new THREE.SpriteMaterial({
      map: createSunGlowTexture(THREE),
      color: 0xffffff,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false
    });

    var sunGlow = new THREE.Sprite(glowMat);
    // Büyük yarı saydam bulut yerine daha dar, yoğun beyaz güneş halesi.
    sunGlow.scale.set(360, 360, 1.0);
    sunMesh.add(sunGlow);

    // Day/night sınırı çok sert görünmesin diye çok düşük ortam ışığı verilir.
    // Bu, geceyi gündüze çevirmeden terminatör geçişini yumuşatır.
    var fillLight = new THREE.AmbientLight(0x404040, 0.012);
    scene.add(fillLight);

    return {
      sunLight: sunLight,
      composer: createComposer(THREE, renderer, scene, camera, container)
    };
  }

  return {
    setup: setup
  };
})();