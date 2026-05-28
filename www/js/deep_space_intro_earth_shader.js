// ==============================================================================
// Dosya Yolu: www/js/deep_space_intro_earth_shader.js
// Açıklama: Derin uzay giriş sahnesindeki Dünya materyali shader düzeltmelerini
// ana deep_space_intro.js dosyasından ayırır. Gündüz/gece geçişi, gece ışığı
// maskesi ve çöl parlaklığı sıkıştırması burada yönetilir.
// ==============================================================================

window.DeepSpaceIntroEarthShader = (function() {
  'use strict';

  function apply(THREE, globeMat) {
    if (!THREE || !globeMat) return;

    globeMat.onBeforeCompile = function(shader) {
      shader.uniforms.uSunDirWorld = { value: new THREE.Vector3(0, 0, 1) };
      globeMat.userData.shader = shader;

      shader.vertexShader = shader.vertexShader.replace(
        'varying vec3 vViewPosition;',
        'varying vec3 vViewPosition;\nvarying vec3 vWorldNormalCustom;'
      ).replace(
        '#include <defaultnormal_vertex>',
        '#include <defaultnormal_vertex>\nvWorldNormalCustom = normalize( ( modelMatrix * vec4( objectNormal, 0.0 ) ).xyz );'
      );

      shader.fragmentShader = shader.fragmentShader.replace(
        'varying vec3 vViewPosition;',
        'varying vec3 vViewPosition;\nvarying vec3 vWorldNormalCustom;\nuniform vec3 uSunDirWorld;'
      );

      // Çöl parlaklığı sıkıştırması:
      // Sahara/Arabistan gibi sıcak ve yüksek luma bölgeleri gündüz tarafında
      // aşırı parlamasın. Okyanus, orman ve gece ışığı dokusu korunur.
      shader.fragmentShader = shader.fragmentShader.replace(
        '#include <map_fragment>',
        [
          '#ifdef USE_MAP',
          '  vec4 sampledDiffuseColor = texture2D( map, vUv );',
          '  float texLuma = dot(sampledDiffuseColor.rgb, vec3(0.299, 0.587, 0.114));',
          '  float redDominance = smoothstep(0.04, 0.24, sampledDiffuseColor.r - sampledDiffuseColor.b);',
          '  float warmMask = smoothstep(0.46, 0.74, sampledDiffuseColor.r) *',
          '                   smoothstep(0.38, 0.64, sampledDiffuseColor.g) *',
          '                   (1.0 - smoothstep(0.24, 0.50, sampledDiffuseColor.b)) *',
          '                   redDominance;',
          '  float desertMask = warmMask * smoothstep(0.46, 0.76, texLuma);',
          '  vec3 desertCompressed = sampledDiffuseColor.rgb * vec3(0.56, 0.64, 0.82);',
          '  sampledDiffuseColor.rgb = mix(',
          '    sampledDiffuseColor.rgb,',
          '    desertCompressed,',
          '    clamp(desertMask * 0.62, 0.0, 0.62)',
          '  );',
          '  float compressedLuma = dot(sampledDiffuseColor.rgb, vec3(0.299, 0.587, 0.114));',
          '  float lumaLimiter = min(1.0, 0.62 / max(compressedLuma, 0.001));',
          '  sampledDiffuseColor.rgb *= mix(1.0, lumaLimiter, clamp(desertMask * 0.55, 0.0, 0.55));',
          '  diffuseColor *= sampledDiffuseColor;',
          '#endif'
        ].join('\n')
      );

      // Gece ışıkları yalnızca gece tarafında görünür. Geniş geçiş bandı,
      // terminator çizgisindeki pikselli/geçişli görünümü yumuşatır.
      shader.fragmentShader = shader.fragmentShader.replace(
        '#include <emissivemap_fragment>',
        [
          '#ifdef USE_EMISSIVEMAP',
          '  vec4 emissiveColor = texture2D( emissiveMap, vUv );',
          '  float sunDot = dot(normalize(vWorldNormalCustom), normalize(uSunDirWorld));',
          '  float nightMask = 1.0 - smoothstep(-0.38, 0.14, sunDot);',
          '  nightMask = pow(clamp(nightMask, 0.0, 1.0), 1.10);',
          '  emissiveColor.rgb *= nightMask;',
          '  totalEmissiveRadiance *= emissiveColor.rgb;',
          '#endif'
        ].join('\n')
      );
    };
  }

  return {
    apply: apply
  };
})();