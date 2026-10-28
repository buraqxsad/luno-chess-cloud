# Local release preflight

Run from the repository with Python 3. It uses only the standard library:

```sh
python3 luno_chess/tool/release_preflight.py
```

This command reads public source/configuration and Git index filenames. It does
not use the network, launch Flutter/Gradle/Android, build or install anything,
open signing properties/keystores/tokens, or change an artifact or service.
Firebase `google-services.json` is public client configuration; API/OAuth key
values are never printed. Environment checks inspect variable names only.

Exit 0 means the listed local configuration checks passed. **The output always
retains `releaseDecision: HOLD`.** Exit 1 means a local check/input failed.
The report records source version, configuration hashes, signing-file presence
only, and the independent acceptance gates this script cannot establish.
Source/configuration checks do not replace the existing behavioral security,
release-identity, billing or emulator integration suites.

Luno is preparing its first public release. Before creating a release, inspect
any earlier internal/closed/open test uploads in Play Console. A first public
release may still have used versionCodes on a test track. If the app has no
uploads, code 19 is a candidate; otherwise choose an unused greater code.
`pubspec.yaml` currently records candidate `1.6.3+19`; a first publication does not require
renaming it to 1.0 or resetting the code. Build-time overrides must agree with
the explicit expected version of the final artifact.

The existing `v217_release_bundle_verify.ps1`/`.java` helper performs signed AAB
inspection on an authorized signing machine, including payload signatures,
merged manifest, native ABI and static 16 KB alignment. V239 fixes the historical
build-17 default: expected build and version now come from the current pubspec.
For intentional build overrides, pass `-ExpectedBuild` / `-ExpectedVersion` or
Java `-Dluno.expectedBuild=N` / `-Dluno.expectedVersion=X.Y.Z` explicitly.
Java 21 or newer is required; the PowerShell wrapper resolves `java` on PATH
or accepts an explicit executable. Supply a local classpath file with bundletool,
aapt2-proto, protobuf-java and gson JARs for the intended Android build tools.
The verifier reads default `android/key.properties` or the same alternate path
used by Gradle via wrapper `-SigningPropertiesFile` / Java
`-Dluno.signingPropertiesFile=...`. Relative paths use the Android project root,
matching Gradle. No real signing material is read in `--self-test` mode.
The credential-free preflight does not invoke the signed-bundle verifier.
Do not copy signing material into Git or change the existing signing identity
to satisfy a helper. A successful synthetic self-test is not final-AAB acceptance.

After building the intended release AAB, retain its exact source revision/hash,
build command, version, checksum, signing/upload-certificate checks, merged
manifest/permissions, native alignment and packaged-asset audit. The existing
helper explicitly excludes asset and device/Play acceptance. Its local upload
certificate check does not prove Play App Signing's delivered certificate.
Static 16 KB alignment does not prove actual 16 KB runtime compatibility.

Finally, collect acceptance from a healthy device and the Play test track:
onboarding through completed games, lifecycle/TalkBack, release performance and
long-session audio/VFX, native Google restore, real Play Integrity/App Check,
two-account online recovery, and license billing/restore/refund/RTDN. Confirm
deployed backend/rules parity and rollout state under separate live-service
authorization. Existing debug APK/widget/mock evidence does not clear these
gates. No deploy, upload, store-ready flag change or publication is performed
by this preflight.

For the first publication, also complete the Play listing and app-content
declarations: privacy policy and account-deletion URL, Data safety matching the
actual Firebase/analytics/billing behavior, content rating, audience and ads
declarations, localized screenshots/descriptions, and product availability.
Follow the testing and production-access requirements shown for the actual
developer account in Play Console. A local config check cannot establish that
these console steps are complete.
