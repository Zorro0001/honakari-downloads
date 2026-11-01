"""Download only the six customer installers selected by the release operator."""
import hashlib,json,os,re,urllib.request,urllib.parse
from pathlib import Path
manifest=json.loads(os.environ['PROMOTION_MANIFEST'])
assert manifest['version']=='14.2.2'
expected={f'Honakari-{edition}-Setup-v14.2.2.exe' for edition in ['Free','Premium']}|{f'Honakari-{edition}-macOS-15-{arch}-v14.2.2.dmg' for edition in ['Free','Premium'] for arch in ['arm64','x86_64']}
assert len(manifest['assets'])==6 and {a['name'] for a in manifest['assets']}==expected
root=Path('release');root.mkdir(exist_ok=True)
checks=[]
for item in manifest['assets']:
 url=item['url'];print('::add-mask::'+url,flush=True)
 parsed=urllib.parse.urlparse(url)
 assert parsed.scheme=='https' and parsed.hostname=='release-assets.githubusercontent.com' and not parsed.username
 assert re.fullmatch('[0-9a-f]{64}',item['sha256'])
 assert 1_000_000<int(item['size'])<300_000_000
 path=root/item['name'];digest=hashlib.sha256();size=0
 with urllib.request.urlopen(url,timeout=120) as response,path.open('wb') as target:
  assert urllib.parse.urlparse(response.url).hostname=='release-assets.githubusercontent.com'
  while chunk:=response.read(1024*1024):
   size+=len(chunk)
   if size>item['size']:raise ValueError('Unexpected asset size')
   target.write(chunk);digest.update(chunk)
 assert size==item['size'] and digest.hexdigest()==item['sha256'],item['name']
 checks.append(item['sha256']+'  '+item['name'])
 print('Verified',item['name'],size,flush=True)
(root/'SHA256SUMS.txt').write_text('\n'.join(sorted(checks))+'\n')
notes='''Honakari 14.2.2 adds the Listening Room with optional podcast RSS, six original synthesized soundscapes, a listening timer, and local speed/reverb presets. Opening Podcasts is quiet. Playback starts at gentle defaults. Imported audio files are unchanged.

Midnight Strawberry uses black and bright neon pink. Companion reader portraits are aligned. The opaque wallpaper option has been removed. Original PDF images and text layers retain their document colours across all five interface palettes.

Idle activity is reduced: interface sound engines suspend when finished, Normal playback bypasses reverb processing, idle timer/theme DOM writes are avoided, decorative artwork no longer loops continuously, and the artwork carousel starts paused with manual controls available.

Free and Premium Windows installers and both Mac architectures are validated from source, packaged app and installed copy. Idle CPU checks include embedded browser workers on disposable CI machines. Physical fan noise depends on hardware, cooling and other applications; silence on every laptop is not guaranteed.

Windows: 64-bit Intel/AMD, Python included, WebView2 required. macOS: 15 or later, choose Apple Silicon (arm64) or Intel (x86_64). Downloads are unsigned; Mac previews are not Developer ID signed or notarized. Keep system security protections enabled. Hands-on Windows 11 verification remains pending.

Back up your library before upgrading. Existing files, notes, progress and licence identity are retained. SHA256SUMS.txt lists the exact installer bytes published here.
'''
(root/'RELEASE-NOTES.md').write_text(notes+'\nValidation run: '+str(manifest['validation_run'])+'.\n')
