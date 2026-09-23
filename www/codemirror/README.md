# CodeMirror 5 — çevrimdışı (vendored) dağıtım

Bu klasör, kod bloklarının sözdizimi vurgulaması için kullanılan **gerçek
CodeMirror 5** kütüphanesinin yerel kopyasıdır. Uygulama çalışma zamanında
internete/CDN'e ERİŞMEZ; tüm dosyalar bu klasörden sunulur.

## Kaynak

| Alan | Değer |
|---|---|
| Paket | `codemirror@5.65.21` (npm `version5` etiketi) |
| Tarball | `https://registry.npmjs.org/codemirror/-/codemirror-5.65.21.tgz` |
| npm bütünlüğü | `sha512-6teYk0bA0nR3QP0ihGMoxuKzpl5W80FpnHpBJpgy66NK3cZv5b/d/HY8PnRvfSsCG1MTfr92u2WUl+wT0E40mQ==` |
| Lisans | MIT (`LICENSE`, upstream dosyasının aynısı) |
| JS küçültme | `terser@5.51.2` (`compress`, `mangle`, `ascii_only`; lisans başlığı korunur) |
| CSS küçültme | `clean-css@5.3.3` (`level: 1`; kaynak/lisans satırı eklenir) |

Dosya adları, on-prem kopyadaki düz yerleşimle aynıdır
(`mode/<dil>.min.js`, `addon/fold/*.min.js`). `addon/fold/xml-fold.js`
on-prem adını korur ama diğerleri gibi terser ile küçültülmüştür (upstream
kaynaktaki gereksiz `\-\:\.` kaçışları CodeQL uyarısı üretiyordu; davranış
aynıdır). `LICENSE` değiştirilmeden kopyalanmıştır.

Yükleme sırası ve dil/katlama eşlemesi bu klasörde değil,
`R/config_ui_assets.R` ve `www/js/codemirror-manager.js` içindedir. MERGEN'e
özgü koyu/açık tema renkleri `www/css/codemirror-custom.css` ve
`www/css/theme_light_core.css` dosyalarında tutulur; buradaki dosyalar elle
DÜZENLENMEZ.

## Dosya özetleri (SHA-256)

Windows'ta doğrulama: `Get-FileHash -Algorithm SHA256 <dosya>`.
`tests/testthat/test-codemirror-vendored-assets-contract.R` bu tabloyu gerçek
dosyalarla karşılaştırır.

| Dosya | Upstream kaynak | İşlem | SHA-256 |
|---|---|---|---|
| `codemirror.min.js` | `lib/codemirror.js` | terser | `2f5c1931497eff014e0a09decaf910f1b8ffb99ad9ed4173735cd49496d96bf3` |
| `codemirror.min.css` | `lib/codemirror.css` | clean-css | `0c8fd3bf70777eb746153717c8c1b2e95f881ce2cfe691ff1fdf9e9f47b8e627` |
| `theme/material-darker.min.css` | `theme/material-darker.css` | clean-css | `891ad4ac836699b597c9f8283cbcbc13aabb3b735b010a9227a1e0af7d0b0b8c` |
| `mode/meta.min.js` | `mode/meta.js` | terser | `49858dff01a4a0d60224713bb0d4027bf7baab6e36532bd4f5e5c897ca0ac80d` |
| `mode/r.min.js` | `mode/r/r.js` | terser | `2b96578554d645b3c45c09e8a136ad80c9d484e036e2f69f5c0cbcc2f174a76e` |
| `mode/python.min.js` | `mode/python/python.js` | terser | `9ca93f144bff7c00c3fbc4599ed145b8f2485ca0cf8cc54f4b6eafe4e693bd48` |
| `mode/javascript.min.js` | `mode/javascript/javascript.js` | terser | `5675eb4a9f31e170239d60c53c582b6ce23b92b1e920cf19cad7630676d781d1` |
| `mode/sql.min.js` | `mode/sql/sql.js` | terser | `43975a245042a0d7aedc79bf2a52491061bde708c9f5f8b38e5ff0b1489e9ba8` |
| `mode/shell.min.js` | `mode/shell/shell.js` | terser | `5f4632237c90687f4ee7b1272d98ce19d10b3e635d410f529a3f87c289fe9ee5` |
| `mode/css.min.js` | `mode/css/css.js` | terser | `454b8b2c50a88193658475b9d70dd060e2b5741677847002c37a24ab0c14ebd3` |
| `mode/xml.min.js` | `mode/xml/xml.js` | terser | `0211afd27c4468039ef4c7eb2e9a5679223df4e2ad4f5259e1e5204587189f6f` |
| `mode/htmlmixed.min.js` | `mode/htmlmixed/htmlmixed.js` | terser | `91298fc1f3b939c1c86eb0e0f25fe21117c4423b0451f52f7af0bef10866e10d` |
| `mode/clike.min.js` | `mode/clike/clike.js` | terser | `bfb47ebc6b60c47b84a0f1cf0174c7217b4615c9929507ba8b1419b103e62160` |
| `mode/php.min.js` | `mode/php/php.js` | terser | `57277c56922fde97494d3a30cf459d8ebf67bd5fa6bbafcd1f26ee6a55985095` |
| `mode/ruby.min.js` | `mode/ruby/ruby.js` | terser | `cf9ce9394d46cb8dca917c6c928880b924d242e6adfabe909f65352bd29d756b` |
| `mode/go.min.js` | `mode/go/go.js` | terser | `d3448c969016ea99caed57ee152cbd622aae998373a88861a26cdda4c9ad177f` |
| `mode/swift.min.js` | `mode/swift/swift.js` | terser | `37e6186d74710463a014a1b401021716b5761c75f21f8c4dcaf0814c0edeeb9b` |
| `mode/powershell.min.js` | `mode/powershell/powershell.js` | terser | `63642cd4f34bbba929afabfb1a46159309d2e80ee2e14c0f944734529b70d9e0` |
| `mode/commonlisp.min.js` | `mode/commonlisp/commonlisp.js` | terser | `46a1d588d986f9c77e955f7b116e420f1f3304ce2234a26da7567556e17f8d2b` |
| `mode/vb.min.js` | `mode/vb/vb.js` | terser | `c10ddcd88d4c55e0aa372073a5cf46200d7a5f9e4877dd172b69f2283dd41e4d` |
| `mode/fortran.min.js` | `mode/fortran/fortran.js` | terser | `d7f1ba95f5e49e859c5f8065ca60a6152734ff3ad774720d74bb2680c42d7ccf` |
| `mode/octave.min.js` | `mode/octave/octave.js` | terser | `902a50d65769e1ca52fa3e591ee08884f06cc5f76df2605e68948d8fabb22672` |
| `mode/julia.min.js` | `mode/julia/julia.js` | terser | `81ab2fa898d675863ff7f706331b0b46f9a88c7d77247c6e39cdaf771f802a72` |
| `mode/yaml.min.js` | `mode/yaml/yaml.js` | terser | `1e445ea2dd4e230926f2eaaa5eba6fe36155d1bd39f38c93e8e15e81e3c4cd87` |
| `mode/markdown.min.js` | `mode/markdown/markdown.js` | terser | `eb9a314d035c7b816add40e2db9205f673be93dfc6fd9e35362a6e7a89ae966c` |
| `mode/diff.min.js` | `mode/diff/diff.js` | terser | `b3665cb45fbd94eb6ea9e0f3104b5f29859a1bfb071872cc6f2af51182678676` |
| `mode/dockerfile.min.js` | `mode/dockerfile/dockerfile.js` | terser | `f051325a5b08b500caac2a5fbd95677e414b90190e7842c6bbf8647b239abb01` |
| `mode/rust.min.js` | `mode/rust/rust.js` | terser | `1286b41417ad8e87b5b6953ffce3cb2116bd027e7821b0ee9fc9109dcbc53159` |
| `mode/toml.min.js` | `mode/toml/toml.js` | terser | `e9afd9e89e46ba5bcb4a7748495107d53be68f2c3cfece9651caf739b16afbe1` |
| `mode/properties.min.js` | `mode/properties/properties.js` | terser | `851554da512f8488c83283e5d7b633b3117f405a08d1b662a26f516c43e0c36f` |
| `mode/perl.min.js` | `mode/perl/perl.js` | terser | `5615f44d9ccfe1f324dd37e8b65f60beb6e202f60d2bbd4a3f647df7276fbfe6` |
| `mode/lua.min.js` | `mode/lua/lua.js` | terser | `1600b701269d33aa604cd13d3259446d804b749460b457ea0dd566e9bf997098` |
| `addon/comment/comment.min.js` | `addon/comment/comment.js` | terser | `5de72a4c7be6e5d6ca815ff31e18ba5a4dddc4fa384760082ea13d0fed980f81` |
| `addon/fold/foldcode.min.js` | `addon/fold/foldcode.js` | terser | `1f0be3164645923424dc63a6767a75a241abf739c23dc37476c2bc719acba17a` |
| `addon/fold/foldgutter.min.js` | `addon/fold/foldgutter.js` | terser | `a1f84800aee705dbb6cccc999884bf0cdb4833308ad7488cdc8ae09f839b284c` |
| `addon/fold/foldgutter.min.css` | `addon/fold/foldgutter.css` | clean-css | `4f62c763deb8040b1cf3be1c0fa633ad2e233f6ca066d0616f48c4aac025cac7` |
| `addon/fold/brace-fold.min.js` | `addon/fold/brace-fold.js` | terser | `a6ded3ecaf91ed60bcea9aaa00ee5cc78d81ccb67b28431c4cdd8b8bb4744acf` |
| `addon/fold/comment-fold.min.js` | `addon/fold/comment-fold.js` | terser | `caecb1dcd317ecc5fae3fca140072834c98e4d3fae6cdd2f6fe01917d3e16ea5` |
| `addon/fold/indent-fold.min.js` | `addon/fold/indent-fold.js` | terser | `13f35cf529c8084d1ea9efe0e27bbbf1f4004de134154fb1065b85f10b083cb7` |
| `addon/fold/markdown-fold.min.js` | `addon/fold/markdown-fold.js` | terser | `11f05c21cc782611993fcf4079f9c5c211e80bc538fe59f89384f5ad627b0959` |
| `addon/fold/xml-fold.js` | `addon/fold/xml-fold.js` | terser | `3c60c61f385a506ae9c4710a7c921c8e35b6e13f6c1ae3087797b3a282cf45e3` |
| `addon/mode/simple.min.js` | `addon/mode/simple.js` | terser | `c6e9bb186d15c168715826168fd1b4c1163ad18427a87760ca341e9dabc6614e` |
| `LICENSE` | `LICENSE` | verbatim | `168a4becc968f5001e2ee2e0291b6e4daabafc1894a11ade1e11d56e96096e07` |

## Güncelleme

1. Yeni `codemirror@5.x` tarball'ını npm bütünlük değeriyle doğrulayın.
2. Aynı kaynak → hedef eşlemesiyle dosyaları üretin; tabloyu güncelleyin.
3. Yeni bir dil eklerken: mod dosyasını `R/config_ui_assets.R` içindeki
   `codemirror_modes` grubuna (bağımlılıklarından SONRA) ve dil anahtarını
   `www/js/codemirror-manager.js` eşlemesine ekleyin.
