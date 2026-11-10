#!/usr/bin/env python3
import json,pathlib,shutil,subprocess
out=pathlib.Path('artifacts/rust-licenses');out.mkdir(parents=True,exist_ok=True)
metadata=json.loads(subprocess.check_output(['cargo','metadata','--format-version','1','--locked'],text=True))
index=[]
missing=[]
for package in metadata['packages']:
 if package.get('source') is None:continue
 root=pathlib.Path(package['manifest_path']).parent
 target=out/(package['name']+'-'+package['version']);target.mkdir(exist_ok=True)
 files=[p for p in root.iterdir() if p.is_file() and p.name.upper().startswith(('LICENSE','COPYING','NOTICE','UNLICENSE'))]
 for file in files:shutil.copyfile(file,target/file.name)
 if not files:
  upstream=pathlib.Path('licenses/rust-upstream')/(package['name']+'-'+package['version'])
  if (upstream/'source.json').exists():
   source=json.loads((upstream/'source.json').read_text())
   for name in source.get('notices',[]):
    src=upstream/name;dest=target/'upstream'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest);files.append(dest)
   shutil.copyfile(upstream/'source.json',target/'upstream-source.json')
 if not files:
  missing.append({'name':package['name'],'version':package['version'],'license':package.get('license'),'repository':package.get('repository')})
  shutil.copyfile(root/'Cargo.toml',target/'published-Cargo.toml')
  for readme in root.glob('README*'):
   if readme.is_file():shutil.copyfile(readme,target/readme.name)
 index.append({'name':package['name'],'version':package['version'],'license':package.get('license'),'notices':[str(p.relative_to(target)) if p.is_relative_to(target) else p.name for p in files]})
(out/'REQUIRES_NOTICE_REVIEW.json').write_text(json.dumps(missing,indent=2))
(out/'index.json').write_text(json.dumps(index,indent=2))
print(f'Collected notices for {len(index)} resolved dependencies; {len(missing)} packages still require notice review before redistribution.')
