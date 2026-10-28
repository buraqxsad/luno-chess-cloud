#!/usr/bin/env python3
"""Read-only local configuration checks; never grants release acceptance."""

import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


PACKAGE = "com.luno.chess"
PROJECT = "luno-chess"
ANDROID = "{http://schemas.android.com/apk/res/android}"
EMULATOR_VARIABLES = (
    "FIREBASE_AUTH_EMULATOR_HOST",
    "FIREBASE_DATABASE_EMULATOR_HOST",
    "FIRESTORE_EMULATOR_HOST",
    "FUNCTIONS_EMULATOR",
    "LUNO_DB_EMULATOR_NAMESPACE",
    "FIREBASE_APPCHECK_DEBUG_TOKEN",
)


def credential_filename(path):
    """Inspect index names only. Never open any matching file."""
    name = Path(path).name.lower()
    if name in (".env.example", "key.properties.example", "keystore.properties.example"):
        return False
    return (
        name == ".env"
        or name.startswith(".env.")
        or name == "key.properties"
        or name.startswith("key.properties.")
        or name == "keystore.properties"
        or name.startswith("keystore.properties.")
        or any(fnmatch.fnmatch(name, pattern) for pattern in (
            "*.jks", "*.jks.*", "*.keystore", "*.keystore.*",
            "*.p12", "*.p12.*", "*.pfx", "*.pfx.*", "*.pem", "*.key",
            "*service-account*.json", "*serviceaccount*.json",
        ))
        or any(part.lower() in ("credentials", "release-credentials") for part in Path(path).parts)
    )


def inspect(repo):
    checks = []
    hashes = {}

    def check(name, passed):
        checks.append({"id": name, "passed": bool(passed)})

    def source(relative):
        # Every call site below names a public source/configuration input.
        # In particular, no signing properties, keystore or environment file
        # is ever passed to this function.
        data = (repo / relative).read_bytes()
        hashes[relative] = hashlib.sha256(data).hexdigest()
        return data.decode("utf-8")

    pubspec = source("luno_chess/pubspec.yaml")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec, re.MULTILINE)
    check("pubspec_android_version", match is not None and 0 < int(match[2]) <= 2100000000)
    version = {"name": match[1], "code": int(match[2])} if match else None

    gradle = source("luno_chess/android/app/build.gradle.kts")
    application_ids = re.findall(r'\bapplicationId\s*=\s*"([^"]+)"', gradle)
    check("android_application_id", application_ids == [PACKAGE])
    # Source wiring only. The signed artifact manifest must be inspected later.
    check("android_uses_flutter_version", all(re.search(pattern, gradle) for pattern in (
        r"\bversionCode\s*=\s*flutter\.versionCode\b",
        r"\bversionName\s*=\s*flutter\.versionName\b",
    )))

    for variant in ("main", "debug", "profile"):
        manifest = ET.fromstring(source(f"luno_chess/android/app/src/{variant}/AndroidManifest.xml"))
        applications = manifest.findall("application")
        check(f"{variant}_source_manifest_no_unsafe_override", all(
            app.get(ANDROID + name) not in ("true", "1")
            for app in applications for name in ("debuggable", "testOnly", "usesCleartextTraffic")
        ))
        if variant == "main":
            check("main_manifest_native_launcher", len(applications) == 1 and any(
                activity.get(ANDROID + "name") == PACKAGE + ".MainActivity"
                for activity in applications[0].findall("activity")
            ))

    firebase = json.loads(source("firebase.json"))
    projects = json.loads(source(".firebaserc"))
    package = json.loads(source("functions/package.json"))
    check("firebase_project", projects.get("projects", {}).get("default") == PROJECT)
    check("firebase_functions_runtime", firebase.get("functions", {}).get("source") == "functions"
          and firebase["functions"].get("runtime") == "nodejs" + package.get("engines", {}).get("node", ""))
    check("firebase_production_rules_selected", firebase.get("database", {}).get("rules") == "database.rules.production.json")
    rules = json.loads(source("database.rules.production.json")).get("rules", {})
    check("database_root_denies_direct_access", rules.get(".read") is False and rules.get(".write") is False)

    # google-services.json is public Firebase client metadata, as documented in
    # DEVAM.md. Output is restricted to identity comparisons; no API/OAuth keys.
    client = json.loads(source("luno_chess/android/app/google-services.json"))
    check("firebase_client_project", client.get("project_info", {}).get("project_id") == PROJECT)
    clients = [entry for entry in client.get("client", [])
               if entry.get("client_info", {}).get("android_client_info", {}).get("package_name") == PACKAGE]
    check("firebase_exactly_one_android_client", len(clients) == 1)
    policy = source("functions/lib/app-check-policy.js")
    allowed = re.search(r"\bTRUSTED_ANDROID_APP_ID\s*=\s*'([^']+)'", policy)
    check("firebase_client_matches_app_check_allowlist", len(clients) == 1 and allowed is not None
          and clients[0].get("client_info", {}).get("mobilesdk_app_id") == allowed[1])

    tracked = subprocess.run(["git", "ls-files", "-z", "--cached"], cwd=repo,
                             capture_output=True, check=False)
    check("git_index_available", tracked.returncode == 0)
    credential_count = sum(credential_filename(path) for path in
                           tracked.stdout.decode("utf-8", errors="replace").split("\0") if path)
    check("no_tracked_credential_filenames", tracked.returncode == 0 and credential_count == 0)
    contaminated = [name for name in EMULATOR_VARIABLES if name in os.environ]
    check("no_emulator_or_debug_token_environment", not contaminated)

    return {
        "recordedUtc": datetime.now(timezone.utc).isoformat(),
        "scope": "read-only local source/configuration; no build, network, signing or device operation",
        "localConfigurationPassed": all(row["passed"] for row in checks),
        "releaseDecision": "HOLD",
        "versionFromSource": version,
        "checks": checks,
        "trackedCredentialFilenameCount": credential_count,
        "contaminatingEnvironmentVariableNames": contaminated,
        "defaultSigningPropertiesPresent": (repo / "luno_chess/android/key.properties").is_file(),
        "signingPropertiesContentRead": False,
        "signingOrUploadCertificateVerified": False,
        "artifactOrDeviceInspected": False,
        "unverifiedAcceptanceGates": [
            "Play Console latest versionCode and proposed code availability",
            "Final signed release AAB identity, upload certificate, merged permissions and native 16 KB alignment",
            "Play-delivered release, Play App Signing identity and actual 16 KB runtime",
            "Healthy physical Android onboarding/game/lifecycle/TalkBack and release FPS/RAM/thermal/audio session",
            "Native Google restore and production Play Integrity/App Check",
            "Deployed backend/rules parity and two-account/two-device online recovery",
            "Play license purchase/restore/ack/consume/subscription/refund/RTDN flows",
        ],
        "publicConfigurationInputSha256": hashes,
        "limits": [
            "Exit 0 means these local configuration checks passed; releaseDecision remains HOLD.",
            "Missing signing files are reported without reading them; alternate Gradle signing paths are not resolved.",
            "Source checks do not evaluate Gradle overrides, merge manifests, verify security behavior or prove deployment.",
            "Tracked filename screening does not scan file contents and is not a complete secret scan.",
            "No historical test result is counted as a new run.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    try:
        result = inspect(repo)
    except (OSError, ValueError, TypeError, AttributeError, KeyError, ET.ParseError):
        # Provider/parser exceptions may contain raw configuration. Keep errors
        # authored here and fixed; do not echo file contents or exception text.
        result = {"localConfigurationPassed": False, "releaseDecision": "HOLD",
                  "error": "Local preflight input unavailable or malformed; inspect the named public source files."}
    print(json.dumps(result, indent=2))
    return 0 if result["localConfigurationPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
