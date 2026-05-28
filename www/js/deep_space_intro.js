// www/js/deep_space_intro.js
// Dosya Yolu: www/js/deep_space_intro.js
// Açıklama: Derin uzay giriş animasyonu modülü. Three.js ile Dünya, Ay,
// uydu yörüngeleri ve Samanyolu arka planı oluşturur. Tüm işlem istemci
// tarafında (kullanıcının bilgisayarında) gerçekleşir, sunucuya yük bindirmez.
// NOT: Three.js v0.147.0 (UMD yapısı) ile uyumludur.

window.DeepSpaceIntro = (function() {
  'use strict';

  // Durum değişkenleri
  var _active = false;
  var _destroyed = false;
  var _animFrameId = null;
  var _renderer = null;
  var _composer = null;
  var _scene = null;
  var _camera = null;
  var _controls = null;
  var _clock = null;
  var _resizeHandler = null;
  var _resizeRafId = null;
  var _containerEl = null;

  // Performans durumu: renderer piksel oranı yalnızca cihaz DPI üst sınırına
  // göre sabitlenir; çalışma sırasında kalite düşürülmez.
  var _lastPixelRatio = 0;
  var _loadingTimerId = null;

  // Görsel keskinliği korumak için adaptif düşürme yapılmaz. 2.0 üst sınırı,
  // çok yüksek DPI ekranlarda aşırı tuval büyümesini engellerken yörünge
  // izlerinin netliğini korur.
  var MAX_DEVICE_PIXEL_RATIO = 2.0;

  // Sahne nesneleri
  var _globe = null;
  var _clouds = null;
  var _atmosphere = null;
  var _moonPivot = null;
  var _satellites = [];
  var _globeMat = null;
  var _atmoMat = null;
  var _sunLight = null;

  // Fiziksel sabitler
  var EARTH_AXIAL_TILT = 23.5 * (Math.PI / 180);
  var MOON_INCLINATION = 5.14 * (Math.PI / 180);
  var SIMULATION_SPEED = 1.0;
  var EARTH_DAY_SPEED = 0.05;
  var MOON_ORBIT_SPEED = EARTH_DAY_SPEED * 0.15;
  var CLOUD_SPEED_OFFSET = 1.02;

  // Persona renkleri - config_characters.R ile eşleştirilmiş
  var CHARACTER_COLORS = {
    emre:  0x7C4DFF,  // Mor-mavi
    selin: 0x2F6DF6,  // Mavi
    deniz: 0x12A97B,  // Yeşil-turkuaz
    can:   0xB66A2C,  // Amber/bakır
    ipek:  0xE98686   // Mercan/pembe
  };

  // Yardımcı: Kepler hızı
  function getKeplerSpeed(r) {
    var GM = 0.5;
    return Math.sqrt(GM / r) * 0.15;
  }

  // Yardımcı: Güvenli piksel oranı
  // Kalite çalışma sırasında düşürülmez; yalnızca aşırı yüksek DPI üst sınırı
  // uygulanır. Bu, yörünge izlerinin piksel piksel görünmesini engeller.
  function getSafePixelRatio() {
    var dpr = window.devicePixelRatio || 1;
    if (!isFinite(dpr) || dpr < 1) dpr = 1;
    return Math.min(dpr, MAX_DEVICE_PIXEL_RATIO);
  }

  // Yardımcı: Renderer piksel oranını yalnızca gerektiğinde uygula
  function applyRendererPixelRatio(force) {
    if (!_renderer) return;

    var nextPixelRatio = getSafePixelRatio();
    if (force || Math.abs(nextPixelRatio - _lastPixelRatio) > 0.05) {
      _renderer.setPixelRatio(nextPixelRatio);
      _lastPixelRatio = nextPixelRatio;
    }
  }

  // Yardımcı: Konteyner boyutuna güvenli yeniden boyutlandırma
  function resizeRendererToContainer(force) {
    if (!_camera || !_renderer || !_containerEl) return;

    var w = _containerEl.clientWidth;
    var h = _containerEl.clientHeight;
    if (w === 0 || h === 0) return;

    applyRendererPixelRatio(force);

    _camera.aspect = w / h;
    _camera.updateProjectionMatrix();
    _renderer.setSize(w, h);

    if (_composer) {
      _composer.setSize(w, h);
    }
  }

  // Doku yükleme yardımcısı (v0.147.0 uyumlu)
  function loadTex(loader, url, renderer) {
    var tex = loader.load(
      url,
      function() { /* başarılı */ },
      undefined,
      function(err) {
        console.warn('[DeepSpaceIntro] Doku yüklenemedi:', url);
      }
    );
    // v0.147.0: encoding kullanılır (colorSpace yerine)
    tex.encoding = THREE.sRGBEncoding;
    tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
    return tex;
  }

  // Yörünge oluşturma
  function createOrbit(radius, speed, color, incX, incY, incZ) {
    var trailVert = [
      'varying vec2 vUv;',
      'void main() {',
      '  vUv = uv;',
      '  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);',
      '}'
    ].join('\n');

    var trailFrag = [
      'uniform float uTime;',
      'uniform vec3 uColor;',
      'uniform float uSpeed;',
      'varying vec2 vUv;',
      'void main() {',
      '  float progress = fract(vUv.x - uTime * uSpeed);',
      '  float trailStart = 0.75;',
      '  float alpha = smoothstep(trailStart, 1.0, progress);',
      '  float head = smoothstep(0.98, 1.0, progress) * 3.0;',
      '  if((alpha + head) < 0.01) discard;',
      '  gl_FragColor = vec4(uColor, alpha + head);',
      '}'
    ].join('\n');

    var curve = new THREE.EllipseCurve(0, 0, radius, radius, 0, 2 * Math.PI, false, 0);

    // Yörünge izleri çok ince olduğu için düşük piksel oranı veya az segment
    // durumunda piksellenmiş görünebilir. Segment sayısı ve tüp kesiti hafifçe
    // artırılır; görsel kalite artar, sahne yükü belirgin artmaz.
    var orbitSegments = 768;
    var orbitTubeRadius = 0.024;
    var orbitRadialSegments = 24;

    var points = curve.getPoints(orbitSegments);
    var path = new THREE.CatmullRomCurve3(points.map(function(p) {
      return new THREE.Vector3(p.x, 0, p.y);
    }));
    path.closed = true;

    var geometry = new THREE.TubeGeometry(
      path,
      orbitSegments,
      orbitTubeRadius,
      orbitRadialSegments,
      true
    );
    var material = new THREE.ShaderMaterial({
      precision: 'highp',
      uniforms: {
        uTime: { value: 0 },
        uColor: { value: new THREE.Color(color) },
        uSpeed: { value: speed }
      },
      vertexShader: trailVert,
      fragmentShader: trailFrag,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide
    });

    var mesh = new THREE.Mesh(geometry, material);
    var precessionPivot = new THREE.Group();
    var inclinationPivot = new THREE.Group();
    inclinationPivot.add(mesh);
    inclinationPivot.rotation.set(incX, incY, incZ);
    precessionPivot.add(inclinationPivot);

    return { precessionPivot: precessionPivot, material: material, radius: radius };
  }

  // Yükleme göstergesini gizle
  function hideLoadingIndicator() {
    var loadingEl = document.getElementById('deep-space-loading');
    if (!loadingEl) return;

    loadingEl.style.opacity = '0';

    if (_loadingTimerId) {
      clearTimeout(_loadingTimerId);
      _loadingTimerId = null;
    }

    _loadingTimerId = setTimeout(function() {
      loadingEl.style.display = 'none';
      _loadingTimerId = null;
    }, 1000);
  }

  // Ana başlatma fonksiyonu
  function init(containerId, options) {
    if (_active) return;
    _active = true;
    _destroyed = false;

    options = options || {};
    var container = document.getElementById(containerId);
    if (!container) {
      console.error('[DeepSpaceIntro] Konteyner bulunamadı:', containerId);
      return;
    }
    _containerEl = container;

    // Three.js varlığını kontrol et
    if (typeof THREE === 'undefined') {
      console.error('[DeepSpaceIntro] Three.js yüklenmemiş!');
      hideLoadingIndicator();
      return;
    }

    // Sidebar ve header'ı gizle
    document.body.classList.add('deep-space-active');

    // Sahne kurulumu
    _scene = new THREE.Scene();
    _clock = new THREE.Clock();

    // Doku yükleyici
    var textureLoader = new THREE.TextureLoader();
    textureLoader.crossOrigin = 'anonymous';

    // Kamera
    _camera = new THREE.PerspectiveCamera(
      45,
      container.clientWidth / container.clientHeight,
      0.1,
      20000
    );
    _camera.position.set(0, 0, 30);

    // İşleyici (Renderer)
    _renderer = new THREE.WebGLRenderer({
      antialias: true,
      powerPreference: 'high-performance',
      alpha: true
    });
    _renderer.setSize(container.clientWidth, container.clientHeight);

    // Çok yüksek DPI ekranlarda WebGL tuvali aşırı büyüyerek ilk karelerde
    // Chrome "requestAnimationFrame handler took..." uyarılarına yol açabiliyor.
    // Görsel efektleri kapatmadan güvenli üst sınır uygulanır.
    applyRendererPixelRatio(true);
    _renderer.toneMapping = THREE.ACESFilmicToneMapping;

    // Güneşin görünür parlaklığı solar modülde yönetilir. Dünya pozlaması
    // ayrı tutulur ki Sahara/Arabistan gibi açık kara dokuları patlamasın.
    _renderer.toneMappingExposure = 0.72;
    // v0.147.0: outputEncoding kullanılır (outputColorSpace yerine)
    _renderer.outputEncoding = THREE.sRGBEncoding;
    _renderer.shadowMap.enabled = true;
    _renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(_renderer.domElement);

    // Arka plan (Samanyolu)
    var basePath = options.texturePath || 'lib/threejs/textures/';
    var texturesLoaded = 0;
    var totalTextures = 7; // starmap + 4 earth + clouds + moon

    // Doku yükleme sayacı
    function onTextureLoaded() {
      texturesLoaded++;
      if (texturesLoaded >= totalTextures) {
        hideLoadingIndicator();
      }
    }

    // Zaman aşımı: 15 saniye sonra yükleme göstergesini yine de gizle
    setTimeout(function() {
      hideLoadingIndicator();
    }, 15000);

    // Yıldız haritası: Büyük küre geometrisi kullanarak ekran boyutundan
    // bağımsız sabit çözünürlük sağlanır (6000x3000px doku esnemez).
    // EquirectangularReflectionMapping yerine kürenin iç yüzeyine eşlenir.
    var _starSphere = null;
    textureLoader.load(
      basePath + 'starmap.jpg',
      function(tex) {
        // v0.147.0: encoding kullanılır
        tex.encoding = THREE.sRGBEncoding;
        // Bulanıklığı önle: mipmap kullanma, doğrudan lineer filtrele
        tex.minFilter = THREE.LinearFilter;
        tex.magFilter = THREE.LinearFilter;
        tex.generateMipmaps = false;
        tex.anisotropy = _renderer.capabilities.getMaxAnisotropy();

        // Büyük küre: kamera her zaman içinde kalır, doku sabit çözünürlükte kalır
        var starGeo = new THREE.SphereGeometry(9000, 64, 64);
        var starMat = new THREE.MeshBasicMaterial({
          map: tex,
          side: THREE.BackSide, // Kürenin iç yüzeyini göster
          depthWrite: false,
          fog: false
        });
        _starSphere = new THREE.Mesh(starGeo, starMat);
        _scene.add(_starSphere);

        // Ortam ışığı için environment haritası olarak da kullan
        tex.mapping = THREE.EquirectangularReflectionMapping;
        _scene.environment = tex;

        onTextureLoaded();
      },
      undefined,
      function(err) {
        console.warn('[DeepSpaceIntro] Samanyolu dokusu yüklenemedi:', basePath + 'starmap.jpg');
        onTextureLoaded();
      }
    );
    // Sahne arka planını siyah yap (küre yüklenene kadar)
    _scene.background = new THREE.Color(0x000000);

    // Ana grup
    var mainGroup = new THREE.Group();
    _scene.add(mainGroup);

    // Dünya eğim grubu
    var earthTiltGroup = new THREE.Group();
    earthTiltGroup.rotation.z = EARTH_AXIAL_TILT;
    mainGroup.add(earthTiltGroup);

    // Dünya dokuları
    var earthDayMap = loadTex(textureLoader, basePath + 'earth_atmos_2048.jpg', _renderer);
    var earthNormalMap = loadTex(textureLoader, basePath + 'earth_normal_2048.jpg', _renderer);
    var earthSpecularMap = loadTex(textureLoader, basePath + 'earth_specular_2048.jpg', _renderer);
    var earthCloudsMap = loadTex(textureLoader, basePath + 'earth_clouds_1024.png', _renderer);
    var earthLightsMap = loadTex(textureLoader, basePath + 'earth_lights_2048.png', _renderer);
    var moonMap = loadTex(textureLoader, basePath + 'moon_1024.jpg', _renderer);

    // Animasyon, dokular gerçekten hazır olduktan sonra başlatılır.
    // Böylece ilk shader/texture yükü animasyon karesine kalıp rAF violation üretmez.
    var animationStarted = false;

    function startAnimationOnce(reason) {
      if (animationStarted || _destroyed) return;
      animationStarted = true;

      hideLoadingIndicator();
      warmUpRendererOnce();

      requestAnimationFrame(function() {
        animate();
        console.log('[DeepSpaceIntro] Sahne başarıyla oluşturuldu:', reason || 'ready');
      });
    }

    THREE.DefaultLoadingManager.onLoad = function() {
      startAnimationOnce('textures_loaded');
    };

    // Dünya geometrisi ve materyali
    var globeGeo = new THREE.SphereGeometry(3.5, 128, 128);

    _globeMat = new THREE.MeshPhysicalMaterial({
      precision: 'highp',
      map: earthDayMap,
      normalMap: earthNormalMap,
      normalScale: new THREE.Vector2(1.32, 1.32),

      // Gündüz tarafı canlı kalır; çöl/parlak kara bölgeleri shader içinde
      // ayrıca sıkıştırıldığı için Sahara/Arabistan tekrar patlamaz.
      color: new THREE.Color(0xd4dde5),
      roughness: 0.93,
      metalness: 0.0,
      specularIntensity: 0.018,
      ior: 1.333,
      clearcoat: 0.0,
      clearcoatRoughness: 0.82,
      clearcoatMap: earthSpecularMap,
      emissiveMap: earthLightsMap,
      emissive: new THREE.Color(0xfff1c2),
      emissiveIntensity: 0.4,
      sheen: 0.0
    });

    // Dünya shader düzeltmeleri ayrı dosyada tutulur; bu dosya bakım ratchet
    // sınırının altında kalır.
    if (window.DeepSpaceIntroEarthShader &&
        typeof window.DeepSpaceIntroEarthShader.apply === 'function') {
      window.DeepSpaceIntroEarthShader.apply(THREE, _globeMat);
    }

    _globe = new THREE.Mesh(globeGeo, _globeMat);
    _globe.castShadow = true;
    _globe.receiveShadow = true;
    earthTiltGroup.add(_globe);

    // Bulutlar
    var cloudGeo = new THREE.SphereGeometry(3.56, 128, 128);
    var cloudMat = new THREE.MeshStandardMaterial({
      map: earthCloudsMap,
      transparent: true,
      opacity: 0.9,
      bumpMap: earthCloudsMap,
      bumpScale: 0.015,
      roughness: 0.9,
      blending: THREE.NormalBlending,
      side: THREE.DoubleSide,
      depthWrite: false
    });
    _clouds = new THREE.Mesh(cloudGeo, cloudMat);
    var depthMat = new THREE.MeshDepthMaterial({
      depthPacking: THREE.RGBADepthPacking,
      alphaMap: earthCloudsMap,
      alphaTest: 0.05
    });
    _clouds.customDepthMaterial = depthMat;
    _clouds.castShadow = true;
    earthTiltGroup.add(_clouds);

    // Atmosfer shader
    var atmoGeo = new THREE.SphereGeometry(3.7, 128, 128);
    _atmoMat = new THREE.ShaderMaterial({
      uniforms: {
        uSunDirection: { value: new THREE.Vector3(0, 0, 1) },
        uAtmosphereColor: { value: new THREE.Color(0.2, 0.5, 0.9) },
        uSunsetBase: { value: new THREE.Color(0.6, 0.3, 0.1) }
      },
      vertexShader: [
        'varying vec3 vNormal;',
        'varying vec3 vViewPos;',
        'void main() {',
        '  vNormal = normalize(normalMatrix * normal);',
        '  vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);',
        '  vViewPos = -mvPosition.xyz;',
        '  gl_Position = projectionMatrix * mvPosition;',
        '}'
      ].join('\n'),
      fragmentShader: [
        'uniform vec3 uSunDirection;',
        'uniform vec3 uAtmosphereColor;',
        'uniform vec3 uSunsetBase;',
        'varying vec3 vNormal;',
        'varying vec3 vViewPos;',
        '',
        'void main() {',
        '  vec3 viewDir = normalize(vViewPos);',
        '  vec3 normal = normalize(vNormal);',
        '  float NdotV = dot(normal, viewDir);',
        '  float NdotL = dot(normal, uSunDirection);',
        '  float VdotL = max(0.0, dot(viewDir, uSunDirection));',
        '',
        // Fresnel kenar parlaması - atmosferin ince kenarında daha yoğun
        '  float fresnel = pow(clamp(0.65 - NdotV, 0.0, 1.0), 3.5);',
        '',
        // Gündüz/gece geçişi
        '  float daySide = smoothstep(-0.25, 0.25, NdotL);',
        '',
        // Atmosfer rengi: ağırlıklı olarak mavi kalmalı
        '  vec3 finalColor = uAtmosphereColor;',
        '',
        // Gün batımı efekti SADECE güneş-ufuk çizgisine çok yakın dar bölgede
        // Düşük yoğunluk ve yüksek üs ile renklilik bastırılır
        '  float terminator = smoothstep(-0.02, 0.12, NdotL) * smoothstep(0.28, 0.08, NdotL);',
        '  float sunsetMix = terminator * pow(VdotL, 2.5) * 0.3;',
        '  vec3 sunsetColor = mix(vec3(0.9, 0.55, 0.3), vec3(0.95, 0.75, 0.5), VdotL);',
        '  finalColor = mix(finalColor, sunsetColor, sunsetMix);',
        '',
        // Ufuk çizgisi limb parlaması - yalnızca güneş yönünde, beyaz-mavi
        '  float limbFresnel = pow(clamp(1.0 - abs(NdotV), 0.0, 1.0), 6.0);',
        '  float sunAlignment = pow(VdotL, 4.0);',
        '  float limbGlow = limbFresnel * sunAlignment * 1.5;',
        '  vec3 limbColor = mix(vec3(0.7, 0.85, 1.0), vec3(0.9, 0.95, 1.0), pow(VdotL, 6.0));',
        '  finalColor = mix(finalColor, limbColor, clamp(limbGlow, 0.0, 1.0));',
        '',
        // Temel atmosfer saydamlığı
        '  float alpha = fresnel * (daySide * 0.85 + 0.1);',
        '',
        // İleri Mie saçılması (güneşe doğru bakışta parlama halesi)
        '  float mieCore = pow(VdotL, 128.0) * 2.0;',
        '  float mieMid = pow(VdotL, 32.0) * 0.4;',
        '  float mieWide = pow(VdotL, 8.0) * 0.08;',
        '  float mieTot = mieCore + mieMid + mieWide;',
        '  vec3 mieColor = mix(vec3(1.0, 0.95, 0.9), vec3(1.0, 1.0, 1.0), pow(VdotL, 16.0));',
        '  finalColor = mix(finalColor, mieColor, clamp(mieTot, 0.0, 1.0));',
        '  alpha += mieTot;',
        '',
        // Limb parlama saydamlığa katkısı
        '  alpha += limbGlow * 0.25;',
        '',
        '  gl_FragColor = vec4(finalColor, clamp(alpha, 0.0, 1.0));',
        '}'
      ].join('\n'),
      blending: THREE.AdditiveBlending,
      side: THREE.BackSide,
      transparent: true,
      depthWrite: false
    });
    _atmosphere = new THREE.Mesh(atmoGeo, _atmoMat);
    earthTiltGroup.add(_atmosphere);

    // Ay kurulumu
    // Fiziksel not:
    // - mainGroup sahnenin ekliptik düzlemini temsil eder.
    // - Dünya'nın 23.5° eksen eğimi yalnızca earthTiltGroup üzerinde uygulanır.
    // - Ay, Dünya'nın ekvator düzleminde değil; ekliptiğe yaklaşık 5.14°
    //   eğimli kendi yörünge düzleminde dolaşır.
    // Bu yüzden Ay grubu earthTiltGroup içine alınmamalıdır.
    var moonSystemGroup = new THREE.Group();
    moonSystemGroup.rotation.z = MOON_INCLINATION;
    mainGroup.add(moonSystemGroup);

    _moonPivot = new THREE.Group();
    moonSystemGroup.add(_moonPivot);

    var moonGeo = new THREE.SphereGeometry(0.8, 64, 64);
    var moonMat = new THREE.MeshStandardMaterial({
      map: moonMap,
      roughness: 0.9,
      metalness: 0.0
    });
    var moon = new THREE.Mesh(moonGeo, moonMat);
    moon.position.set(60, 0, 0);
    moon.castShadow = true;
    moon.receiveShadow = true;
    _moonPivot.add(moon);

    // Uydu yörüngeleri - karakter renklerini kullan
    var colorKeys = Object.keys(CHARACTER_COLORS);
    var orbitConfigs = [
      { radius: 4.8, incX: Math.PI/2.1, incY: 0,          incZ: 0 },
      { radius: 5.3, incX: Math.PI/3,   incY: Math.PI/6,  incZ: 0 },
      { radius: 5.8, incX: -Math.PI/4,  incY: Math.PI/3,  incZ: 0 },
      { radius: 6.2, incX: Math.PI/2,   incY: Math.PI/4,  incZ: Math.PI/8 },
      { radius: 6.6, incX: 0,           incY: Math.PI/5,  incZ: Math.PI/6 }
    ];

    _satellites = [];
    for (var i = 0; i < orbitConfigs.length; i++) {
      var cfg = orbitConfigs[i];
      var color = CHARACTER_COLORS[colorKeys[i]];
      var sat = createOrbit(cfg.radius, getKeplerSpeed(cfg.radius), color, cfg.incX, cfg.incY, cfg.incZ);
      _satellites.push(sat);
      mainGroup.add(sat.precessionPivot);
    }

    // Güneş, lens parlama, ortam ışığı ve bloom kurulumu ayrı modüldedir.
    // Böylece bu dosya bakım ratchet sınırının altında kalır.
    var solarSetup = window.DeepSpaceIntroSolar.setup({
      THREE: THREE,
      scene: _scene,
      renderer: _renderer,
      camera: _camera,
      container: container
    });

    _sunLight = solarSetup.sunLight;
    _composer = solarSetup.composer;

    // Kamera kontrolleri
    if (typeof THREE.OrbitControls !== 'undefined') {
      _controls = new THREE.OrbitControls(_camera, _renderer.domElement);
      _controls.enableDamping = true;
      _controls.enableZoom = true;
      _controls.enablePan = false;
      _controls.minDistance = 6;
      _controls.maxDistance = 100;
      _controls.autoRotate = true;
      _controls.autoRotateSpeed = 0.2;
      _controls.minPolarAngle = Math.PI * 0.1;
      _controls.maxPolarAngle = Math.PI * 0.9;
    }

    // Animasyon değişkenleri
    var introAnim = true;
    var sunDirView = new THREE.Vector3();
    var sunDirWorld = new THREE.Vector3();
	
    // İlk WebGL render maliyetini animasyon döngüsünden önce ısıt.
    // Shader derleme / texture upload ilk animate karesine kalırsa Chrome
    // requestAnimationFrame violation olarak raporlar.
    function warmUpRendererOnce() {
      try {
        if (_renderer && _scene && _camera) {
          _renderer.compile(_scene, _camera);
          if (_composer) {
            _composer.render();
          } else {
            _renderer.render(_scene, _camera);
          }
        }
      } catch (e) {
        // Isıtma başarısız olursa normal animasyon döngüsü yine çalışır.
      }
    }

    // Animasyon döngüsü
    function animate() {
      if (_destroyed) return;
      _animFrameId = requestAnimationFrame(animate);

      // Sekme görünür değilken sahneyi çizmeyerek gereksiz GPU yükünü önle.
      // Saat delta değeri tüketilir; sekmeye dönünce animasyon sıçramaz.
      if (document.hidden || !_renderer || !_scene || !_camera) {
        if (_clock) _clock.getDelta();
        return;
      }

      // getElapsedTime() ayrıca getDelta() çağırdığı için burada doğrudan
      // elapsedTime okunur. Böylece saat iki kez ilerletilmez.
      var rawDt = _clock.getDelta();
      var dt = Math.min(rawDt, 0.05) * SIMULATION_SPEED;
      var elapsed = _clock.elapsedTime;

      // Açılış animasyonu: kamerayı yaklaştır
      if (introAnim) {
        _camera.position.z += (18 - _camera.position.z) * 0.02;
        if (Math.abs(_camera.position.z - 18) < 0.1) introAnim = false;
      }

      // Dünya dönüşü
      if (_globe) _globe.rotation.y += EARTH_DAY_SPEED * dt;
      if (_clouds) _clouds.rotation.y += EARTH_DAY_SPEED * CLOUD_SPEED_OFFSET * dt;

      // Ay yörüngesi
      if (_moonPivot) _moonPivot.rotation.y += MOON_ORBIT_SPEED * dt;

      // Atmosfer shader güncelleme
      if (_sunLight) {
        sunDirView.copy(_sunLight.position).normalize();
        sunDirWorld.copy(sunDirView);
        sunDirView.applyMatrix4(_camera.matrixWorldInverse).normalize();

        if (_atmoMat) {
          _atmoMat.uniforms.uSunDirection.value.copy(sunDirView);
        }
        if (_globeMat && _globeMat.userData.shader) {
          _globeMat.userData.shader.uniforms.uSunDirWorld.value.copy(sunDirWorld);
        }
      }

      // Uydu dinamikleri
      for (var i = 0; i < _satellites.length; i++) {
        var s = _satellites[i];
        s.material.uniforms.uTime.value = elapsed;
        var precessionRate = 0.005 / (s.radius * s.radius);
        s.precessionPivot.rotation.y -= precessionRate * dt;
      }

      if (_controls) _controls.update();

      if (_composer) {
        _composer.render();
      } else {
        _renderer.render(_scene, _camera);
      }

    }

    // Pencere boyut değişikliği
    _resizeHandler = function() {
      if (_resizeRafId) {
        cancelAnimationFrame(_resizeRafId);
      }

      // Yeniden boyutlandırmayı tarayıcının çizim ritmine bağla.
      // Böylece ardışık resize olayları tek WebGL güncellemesine indirgenir.
      _resizeRafId = requestAnimationFrame(function() {
        _resizeRafId = null;
        resizeRendererToContainer(true);
      });
    };
    window.addEventListener('resize', _resizeHandler);

    // Animasyon burada doğrudan başlatılmaz.
    // THREE.DefaultLoadingManager.onLoad dokular hazır olduğunda startAnimationOnce()
    // çağırır. Emniyet için kısa bir geri dönüş kapısı bırakılır.
    window.setTimeout(function() {
      startAnimationOnce('fallback_timeout');
    }, 3500);
  }

  // Temizleme fonksiyonu
  function destroy() {
    _destroyed = true;
    _active = false;

    // Gövde sınıfını kaldır
    document.body.classList.remove('deep-space-active');
	
    if (_loadingTimerId) {
      clearTimeout(_loadingTimerId);
      _loadingTimerId = null;
    }

    if (_resizeRafId) {
      cancelAnimationFrame(_resizeRafId);
      _resizeRafId = null;
    }

    if (_animFrameId) {
      cancelAnimationFrame(_animFrameId);
      _animFrameId = null;
    }

    if (_resizeHandler) {
      window.removeEventListener('resize', _resizeHandler);
      _resizeHandler = null;
    }

    if (_controls) {
      _controls.dispose();
      _controls = null;
    }

    if (_composer) {
      // v0.147.0: EffectComposer dispose olmayabilir, güvenli kontrol
      if (typeof _composer.dispose === 'function') {
        _composer.dispose();
      }
      _composer = null;
    }

    if (_renderer) {
      _renderer.dispose();
      if (_renderer.domElement && _renderer.domElement.parentNode) {
        _renderer.domElement.parentNode.removeChild(_renderer.domElement);
      }
      _renderer = null;
    }

    // Sahne nesnelerini temizle
    if (_scene) {
      _scene.traverse(function(obj) {
        if (obj.geometry) obj.geometry.dispose();
        if (obj.material) {
          if (Array.isArray(obj.material)) {
            obj.material.forEach(function(m) { m.dispose(); });
          } else {
            obj.material.dispose();
          }
        }
      });
      _scene = null;
    }

    _camera = null;
    _clock = null;
    _globe = null;
    _clouds = null;
    _atmosphere = null;
    _moonPivot = null;
    _satellites = [];
    _globeMat = null;
    _atmoMat = null;
    _sunLight = null;
    _containerEl = null;
    // Yıldız haritası küresini de temizle (animate kapanışında _starSphere erişilemez,
    // ama scene.traverse zaten tüm nesneleri temizler)
  }

  function isActive() {
    return _active;
  }

  return {
    init: init,
    destroy: destroy,
    isActive: isActive
  };
})();

// Otomatik başlatma: Shiny bağlantısını beklemeden uzay animasyonunu hemen başlat.
// localStorage'dan atlama tercihi kontrol edilir; atlama seçilmişse başlatma yapılmaz.
(function() {
  'use strict';
  function autoInitDeepSpace() {
    try {
      var raw = localStorage.getItem('mergen_settings');
      if (raw) {
        var s = JSON.parse(raw);
        if (s.skip_intro === true) return; // Kullanıcı animasyonu atlamayı seçmiş
      }
    } catch(e) {}

    var container = document.getElementById('deep-space-canvas');
    if (container && window.DeepSpaceIntro && !window.DeepSpaceIntro.isActive()) {
      window.DeepSpaceIntro.init('deep-space-canvas', {
        texturePath: 'lib/threejs/textures/'
      });
    }
  }

  function scheduleAutoInitDeepSpace() {
    // WebGL kurulumunu setTimeout/requestIdleCallback içine almak Chrome
    // DevTools'ta yalnızca callback adını "Violation" olarak görünür yapıyor.
    // Bu dosya DOM hazır olduktan sonra yüklendiği için doğrudan başlatılır.
    autoInitDeepSpace();
  }

  // DOM hazır olur olmaz başlat
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scheduleAutoInitDeepSpace, { once: true });
  } else {
    scheduleAutoInitDeepSpace();
  }
})();