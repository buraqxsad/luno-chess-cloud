from pathlib import Path
import json,hashlib
root=Path('/workspace/luno-review/bug-audit-round2/runtime');out=root/'sdk-proof-final'
s=json.loads((out/'results.json').read_text());code=(out/'run-exit.txt').read_text().strip()
expected='5c6800410e05ff020a8e576b67b2419eaad5f56f44a912d8d48ceace7c85b486'
passed=(code=='0' and s.get('local_sdk_acceptance')=='PASS' and s.get('counts')=={'tests':4,'pass':4,'fail':0,'skipped':0,'cancelled':0} and len(s.get('observations',[]))==4 and s.get('source_commit')=='9d41c5055006907ee2dafdf8e5daf70bb9f2c7a3' and s.get('source_index_sha256')==expected)
status='PASS' if passed else 'FAIL / NOT COMPLETE'
original_sdk=Path(s.get('transport_provenance',{}).get('standalone_module','/missing-sdk-path'))
sdk_unchanged=original_sdk.is_file() and hashlib.sha256(original_sdk.read_bytes()).hexdigest()==s.get('transport_provenance',{}).get('original_sha256')
if passed:assert sdk_unchanged and s['port19000_closed_after_cleanup'] and s['private_logs_remaining']==0
report=f'''# Final source — four-case local Billing SDK proof

**{status}.** Captured commit `{s.get('source_commit')}`, index SHA-256 `{s.get('source_index_sha256')}`. This is a scoped local SDK/data result, not production Firebase/Auth/AppCheck/Play acceptance.

The earlier three-case baseline under `../sdk-proof/` remains unchanged. Repeated cases overlap and must not be added as seven independent tests. Earlier two incomplete attempts remain under `/workspace/luno-review/system-bug-hunt/economy/sdk-proof/`.

The final run waits for root backend and Dart/TypeScript differential completion. It first requires a three-second seed/read smoke, then runs exactly four cases with actual Firebase Admin SDK/RTDB transactions and independent-connection durable verification:

1. Confirmed pre-grant refund blocks a suspended currency grant.
2. ON_HOLD fences a suspended profile grant.
3. ON_HOLD fences a suspended granted-claim write.
4. A subscription is first granted through the actual fulfillment entry point; a subsequent owned verification sees fresh ON_HOLD without RTDN, returns purchase-not-active409, commits inactive claim/profile0 and equal revision/fence, and preserves unrelated gold.

Google provider responses are fake; no memoryDatabase fixture is used. Only a single exact-loopback proxy-selection condition in the actual bundled standalone transport is compiled differently in memory. Disk SDK/repo files, headers, proxy environment, all data/transaction code and server responses are unchanged. `standalone-transport.patch`, `transport-provenance.json` and `transport-audit.json` retain this limitation explicitly; unmodified-transport acceptance is not claimed.

Observed counts: `{s.get('counts')}`. Durable observations: `{len(s.get('observations',[]))}`. Total elapsed: `{s.get('elapsed_seconds')}` seconds; combined Java+Node peak RSS `{s.get('peak_combined_rss_kib')}`KiB. SDK disk hash reverified: `{sdk_unchanged}`. Port19000 closed: `{s.get('port19000_closed_after_cleanup')}`; private logs remaining `{s.get('private_logs_remaining')}`.

Results/data are in `results.json` and `observations.json`; filtered logs in `fixed.log`/`emulator.log`. No Android runtime, physical performance or16KB test was run. The historical native raster SIGSEGV remains unresolved; RELEASE HOLD and real-service gates remain separate.
'''
(out/'REPORT.md').write_text(report)
(out/'PENDING.md').write_text('# Final proof status\n\n'+status+'; see REPORT.md and results.json. No longer pending.\n')
(out/'STATUS.json').write_text(json.dumps({'status':status,'target_commit':s.get('source_commit'),'target_index_sha256':s.get('source_index_sha256'),'actual_cases':s.get('counts'),'sdk_disk_unchanged':sdk_unchanged,'emulator_running':False,'port_closed':s.get('port19000_closed_after_cleanup')},indent=2)+'\n')
main=json.loads((root/'result.json').read_text());main['latest_final_sdk']=s;main['latest_final_sdk_acceptance']=status;main['overlapping_sdk_runs_not_summed']=True;(root/'result.json').write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n')
p=root/'REPORT.md';text=p.read_text();marker='## Final kaynak takip doğrulaması'
if marker in text:text=text.split(marker)[0]
text+=f'''\n{marker}\n\nSon commit `{s.get('source_commit')}` /index `{s.get('source_index_sha256')}` üzerinde dört gerçek yerel SDK vakası: **{status}**, `{s.get('counts')}`. Yeni dördüncü vaka önce owned active grant, sonra RTDN olmadan fresh ON_HOLD→inactive claim/Premium0/private fence eşitliğini doğrular. Ayrı SDK bağlantısı kalıcı veriyi okur. Önceki3PASS ile örtüşür; sayılar toplanmaz. [Final kapsam ve kanıt](sdk-proof-final/REPORT.md). Disk SDK/repo değişmedi; üretim/Play/native kabulleri açık kalır.\n'''
p.write_text(text)
print(json.dumps({'latest_final_sdk':status,'counts':s.get('counts'),'source_commit':s.get('source_commit'),'elapsed_seconds':s.get('elapsed_seconds'),'sdk_disk_unchanged':sdk_unchanged,'port_closed':s.get('port19000_closed_after_cleanup')}))
