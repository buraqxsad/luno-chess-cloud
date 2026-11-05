import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LunoFontLicenses {
  static bool _registered = false;
  static const sources = {
    'Nunito': 'assets/fonts/nunito/OFL.txt',
    'Cinzel / CinzelTurkish': 'assets/licenses/cinzel-OFL.txt',
    'Spectral / SpectralTurkish': 'assets/licenses/spectral-OFL.txt',
  };

  static void register() {
    if (_registered) return;
    _registered = true;
    LicenseRegistry.addLicense(entries);
  }

  static Stream<LicenseEntry> entries() async* {
    for (final source in sources.entries) {
      yield LicenseEntryWithLineBreaks([
        source.key,
      ], await rootBundle.loadString(source.value));
    }
  }
}
