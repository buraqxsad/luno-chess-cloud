from pathlib import Path
import hashlib,json,re,struct,subprocess,sys,zipfile

root=Path('/workspace/luno-review/bug-audit-round3')
app=Path('/workspace/luno-chess/luno_chess')
tools=Path('/workspace/toolchains/android-sdk/build-tools/36.0.0')
apk=Path(sys.argv[1]);name=apk.stem
out=root/'android'/name;out.mkdir(exist_ok=True)
def command(executable,*args):
    result=subprocess.run([str(tools/executable),*args],text=True,capture_output=True)
    (out/(executable+'.log')).write_text(result.stdout+result.stderr)
    assert result.returncode==0,(executable,result.returncode)
    return result.stdout
signature=command('apksigner','verify','--verbose','--print-certs',str(apk))
certificate=re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-f]+)',signature)[1]
previous=json.loads(Path('/workspace/luno-review/v238/apk-verification.json').read_text())
assert certificate==previous['certificate_sha256']
assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in signature
badging=command('aapt','dump','badging',str(apk))
assert "package: name='com.luno.chess' versionCode='19' versionName='1.6.3'" in badging
assert "sdkVersion:'24'" in badging and "targetSdkVersion:'36'" in badging
command('zipalign','-c','-P','16','4',str(apk))
assets=[];native=[]
with zipfile.ZipFile(apk) as archive:
    names=archive.namelist()
    assert len(names)==len(set(names))
    for entry in archive.infolist():
        if entry.filename.startswith('assets/flutter_assets/assets/') and not entry.is_dir():
            relative=entry.filename.removeprefix('assets/flutter_assets/')
            source=app/relative
            assert source.is_file(),relative
            data=source.read_bytes()
            assert archive.read(entry)==data,relative
            assets.append({'asset':relative,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
        if not entry.filename.startswith('lib/') or not entry.filename.endswith('.so'):continue
        abi=entry.filename.split('/')[1]
        with archive.open(entry) as f:
            header=f.read(64)
            assert header[:4]==b'\x7fELF' and header[4] in [1,2] and header[5]==1
            is64=header[4]==2
            machine=struct.unpack_from('<H',header,18)[0]
            assert machine=={'armeabi-v7a':40,'arm64-v8a':183,'x86_64':62}[abi]
            assert is64==(abi!='armeabi-v7a')
            offset=struct.unpack_from('<Q' if is64 else '<I',header,32 if is64 else 28)[0]
            length,count=struct.unpack_from('<HH',header,54 if is64 else 42)
            assert length==(56 if is64 else 32) and count>0 and (64 if is64 else 52)<=offset and offset+length*count<=1024*1024
            f.seek(0);data=f.read(offset+length*count)
        loads=[]
        for i in range(count):
            start=offset+i*length
            if struct.unpack_from('<I',data,start)[0]!=1:continue
            if is64:
                file_offset,address,_,file_size,mem_size,alignment=struct.unpack_from('<QQQQQQ',data,start+8)
            else:
                file_offset,address,_,file_size,mem_size,_,alignment=struct.unpack_from('<IIIIIII',data,start+4)
            assert file_offset+file_size<=entry.file_size and mem_size>=file_size
            assert alignment>0 and alignment&(alignment-1)==0
            if is64:assert alignment>=16384
            assert file_offset%alignment==address%alignment
            loads.append(alignment)
        assert loads
        native.append({'entry':entry.filename,'abi':abi,'elf_bits':64 if is64 else 32,'pt_load_alignment_bytes':loads,'static_16kb_required':is64,'static_16kb_pass':True if is64 else None})
    for atlas in ['v237-arcane-halo','v238-crystal','v238-binding','v238-veil']:
        assert 'assets/flutter_assets/assets/native_art/'+atlas+'-atlas.webp' in names
    assert 'assets/flutter_assets/assets/native_art/tutorial-luno-live-atlas.webp' in names
    assert len(assets)==750
    assert native
    engine_abis=sorted({r['abi'] for r in native if r['entry'].endswith('/libflutter.so')})
    payload_abis=sorted({r['abi'] for r in native})
result={'file':str(apk),'bytes':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),
    'package':'com.luno.chess','version':'1.6.3+19','min_sdk':24,'target_sdk':36,
    'signature_v2_verified':True,'same_previous_debug_certificate':True,'certificate_sha256':certificate,
    'debuggable':'application-debuggable' in badging,'source_asset_files_verified':len(assets),
    'source_assets':assets,'native_libraries':native,'apk_16kb_zip_alignment_check_pass':True,
    'abis_with_flutter_engine':engine_abis,'all_native_payload_abis':payload_abis,
    'partial_native_abis_not_supported_for_testing':sorted(set(payload_abis)-set(engine_abis)),
    'actual_16kb_runtime':'NOT RUN','release_upload_certificate_verified':False,
    'play_or_device_acceptance':False,'release_decision':'HOLD'}
(out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['source_assets','native_libraries']}))
