# V240 — yeniden üretim ve paket kimliği

Build kaynağı `831a7ae11f28094c4b54f37415c80031ba1fd029`. Tam regresyon kaynağı `ac0dd98e9924544af12e96fa6c2637eb5b7d8960`; aradaki tek fark DM `.integration.js` fixture’ıdır. Runtime aynı, DM son committe ayrıca tam tekrar edildi. Son QA/devir commit’i uygulama kaynağını değiştirmez.

Bu komutlar kaydedilen koşuları yeniden üretir; teslim aşamasında tekrar çalıştırılmadı. Kurulu bağımlılıklar/kilit dosyaları ve devir notundaki pinler kullanılır. `--update-goldens` kullanılmadı. Erişim gerektiren gerçek cloud/Play adımları bu belgeyle geçmiş sayılmaz.

```bash
source /workspace/toolchains/luno-env.sh
cd /workspace/luno-chess/luno_chess
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --reporter=json
flutter test --no-pub --concurrency=1 test/v240_startup_surface_test.dart
flutter test --no-pub --concurrency=1 test/v239_card_acceptance_test.dart test/v239_atlas_observation_test.dart --reporter expanded
flutter test --no-pub --concurrency=1 test/v239_card_acceptance_test.dart --dart-define=LUNO_V239_LANGUAGE=en
```

PNG yakalama için kart testine `LUNO_V239_CAPTURE_DIRECTORY` Dart define’ı, açılış testine `LUNO_V240_CAPTURE_DIRECTORY` verilir; atlas host ölçümü `LUNO_V239_ASSET_OBSERVATION` JSON yoluna yazılır. Kalıcı kaynak/fixture üzerine yazılmamalıdır.

```bash
cd /workspace/luno-chess/functions
npm test
npm --prefix rules-v1 run typecheck
npm --prefix rules-v1 run build
cd /workspace/luno-chess/luno_chess
dart compile exe tool/battle_json_runner.dart -o /tmp/luno-v240-battle-runner
cd /workspace/luno-chess/functions/rules-v1
LUNO_DART_RUNNER=/tmp/luno-v240-battle-runner node --test dist/test/*.test.js
LUNO_DART_RUNNER=/tmp/luno-v240-battle-runner LUNO_DIFFERENTIAL_QA=/tmp/luno-v240-differential node dist/test/differential.js
```

Gerçek SDK yerel entegrasyonları localhost Auth/RTDB ve kontrollü ortam değişkenleri gerektirir. İlk yerel suite sonuçları ve DM retry, `test-summary.json` içindedir. Functions HTTP servisi veya üretim kabulü değildir.

```bash
cd /workspace/luno-chess/luno_chess
flutter build apk --profile --target-platform android-x64 --build-number 19 --no-pub
flutter build apk --debug --target-platform android-arm64 --build-number 19 --no-pub
cd android
./gradlew :app:validateLunoReleaseSigning --offline
```

Son komut mevcut upload imzası bulunmadığı için exit 1 ile doğru biçimde durdu. Release APK/AAB oluşturulmadı. Sahte imza, SDK yükseltmesi veya debug key ile release geçişi yapılmadı. Gerçek build komutları ve exit kodları `evidence/android/build-commands.json` içindedir.

`artifacts.json` iki test APK’sını, kaynak commit’ini, SHA-256 ve aynı debug sertifikasını kaydeder. 749 source asset hash’i, ELF64 PT_LOAD 16KB ve `zipalign -c -P 16 4` kontrolü doğrulandı. Statik denetim gerçek 16KB kernel veya release AAB kontrolü değildir. APK adındaki ARM64/x64 Flutter engine ABI’sidir; yalnız JNI içeren ek ABI destek sayılmaz.

Native karşılaştırmalar aynı API29 AVD üzerinde, guest dış ağı engellenerek yapıldı. Default launch: `adb shell am start -S -f 0x10008000 -n com.luno.chess/.MainActivity`. Software tanı aynı komuta yalnız `--ez enable-software-rendering true --ez enable-impeller false` ekler; manifest/üretim renderer ayarı değişmedi. V239 ve V240 için 90 saniyelik default karşılaştırmalar sonunda welcome 1/3 ve canlı süreç görüldü. İlk V240 raster SIGSEGV açık kaldı; tutulan son 800 log satırı bütün oturum geçmişi değildir. VM sonradan kapatıldı; ikinci AVD açılmadı, fiziksel cihaz sonucu üretilmedi.
