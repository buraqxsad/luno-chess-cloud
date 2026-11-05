from pathlib import Path
import ast
r=Path('/workspace/luno-review/bug-audit-round5');s=(r/'assemble_report.py').read_text()
s=s.replace("'runtime-billing/run-exit.txt',",'')
s=s.replace("assert sdk['local_sdk_acceptance']=='PASS' and sdk['counts']['pass']==9 and sdk['counts']['fail']==0 and sdk['port19000_closed_after_cleanup'] and sdk['private_logs_remaining']==0", "assert sdk['local_sdk_acceptance']=='FAIL/NOT COMPLETE' and sdk['counts']['tests']==9 and sdk['counts']['pass']==7 and sdk['counts']['fail']==2 and sdk['port19000_closed_after_cleanup'] and sdk['private_logs_remaining']==0")
s=s.replace("('Yerel gerçek RTDB/Admin SDK','PASS','9/9:6finansal,1legacy rezervasyon,2yeni silme akışı. Auth/App Check/Google yanıtları fake; istemci kuralları/Admin rolü farklı.')", "('Yerel gerçek RTDB/Admin SDK','FAIL','7 geçti/2 başarısız. İki yeni silme senaryosu enqueueBattleV1/createFriendlyRoom başlangıcında INVALID_ACTION400 ile durdu; erasure kabulü verilmedi. Auth/AppCheck/Google fake; Admin client rules kabulü değildir.')")
s=s.replace("'verified_new_source_defects_open_this_round':0,", "'untriaged_local_sdk_failures':2,")
s=s.replace('Bu turda doğrulanıp açık bırakılan yeni kaynak kusuru0.', 'İki ek yerel SDK başarısızlığı henüz sınıflanmadı; yeni silme entegrasyon kabulü tamamlanmadı.')
s=s.replace('| Yerel gerçek RTDB/Admin SDK |9/9:6 finansal+1 legacy reservation+2 yeni silme akışı |', '| Yerel gerçek RTDB/Admin SDK | **7 geçti / 2 başarısız**; yeni silme akışları başlangıçta INVALID_ACTION400 ile durdu |')
s=s.replace('[Dokuz vaka](local-sdk-summary.json)', '[9 vakanın gerçek sonucu: 7 geçti / 2 başarısız](local-sdk-summary.json)')
s=s.replace("'snapshot_restored_verified':True", "'snapshot_restored_verified':True,'untriaged_local_sdk_failures':2")
s=s.replace('- Yeni güvenlik-agent probe’u otomatik içerik filtresinde BLOCKED;', '- İki yeni yerel SDK senaryosu başlangıç API çağrısında INVALID_ACTION400 ile FAIL; silme adımlarına ulaşmadı ve ürün/harness ayrımı tamamlanmadı.\n- Yeni güvenlik-agent probe’u otomatik içerik filtresinde BLOCKED;')
ast.parse(s)
# Transfer reporting is intentionally separate. Original acceptance/test guards remain untouched.
exec(compile(s,str(r/'assemble_report.py'), 'exec'))
q=Path('/workspace/luno-chess/qa/bug_audit_round5')
import shutil,json
shutil.copy2(r/'assemble_transfer.py',q/'reproduce/assemble_transfer.py')
(q/'HANDOFF-STATUS.json').write_text(json.dumps({'purpose':'Latest-source transfer to local PC, not release acceptance','source_commit':'767ae74314a664f180ad1ca9e279e2c9881989d2','full_Flutter':{'pass':11881,'fail':97,'skip':0},'backend':{'pass':1481,'fail':0,'skip':1},'typescript':{'pass':376,'fail':0},'local_SDK':{'pass':7,'fail':2,'status':'FAIL/NOT COMPLETE'},'original_release_assembler_unchanged':True,'new_tests_or_builds_run_for_transfer':False,'snapshot_restored_verified':True,'release_decision':'HOLD'},ensure_ascii=False,indent=2)+'\n')
print('Transfer snapshot assembled with SDK FAIL preserved; no product/test assertions altered.')
