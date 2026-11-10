#!/usr/bin/env python3
"""Ephemeral local HTTPS TUF repository; fixture keys never enter product trust stores."""
import base64,ctypes,datetime,hashlib,http.server,json,os,pathlib,ssl,subprocess,tempfile,threading
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding,PublicFormat
ROOT=pathlib.Path(__file__).resolve().parents[1];BIN=ROOT/'target/release'
lib=ctypes.CDLL(str(BIN/'libduct_bridge.so'));lib.duct_call.argtypes=[ctypes.c_char_p];lib.duct_call.restype=ctypes.c_void_p;lib.duct_free.argtypes=[ctypes.c_void_p]
def core(v):
 p=lib.duct_call(json.dumps(v).encode())
 try:r=json.loads(ctypes.string_at(p))
 finally:lib.duct_free(p)
 assert 'ok' in r,r
 return r['ok']
def canonical(v):return json.dumps(v,sort_keys=True,separators=(',',':')).encode()
def digest(v):return hashlib.sha256(v).hexdigest()
checks=[]
with tempfile.TemporaryDirectory(prefix='dtvpn-tuf-') as temp:
 d=pathlib.Path(temp);(d/'metadata').mkdir();(d/'targets').mkdir()
 key=Ed25519PrivateKey.generate();pub=key.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw).hex()
 k={'keytype':'ed25519','scheme':'ed25519','keyval':{'public':pub}};keyid=digest(canonical(k))
 expiry=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%SZ')
 def signed(v):return {'signed':v,'signatures':[{'keyid':keyid,'sig':key.sign(canonical(v)).hex()}]}
 def write(name,v):data=canonical(signed(v));(d/'metadata'/name).write_bytes(data);return {'version':v['version'],'length':len(data),'hashes':{'sha256':digest(data)}}
 root={'_type':'root','spec_version':'1.0.0','version':1,'expires':expiry,'consistent_snapshot':False,'keys':{keyid:k},'roles':{role:{'keyids':[keyid],'threshold':1} for role in ['root','timestamp','snapshot','targets']}}
 write('1.root.json',root);(d/'root.json').write_bytes((d/'metadata/1.root.json').read_bytes())
 artifact=b'fixture artifact, never executable';(d/'targets/fixture.bin').write_bytes(artifact)
 manifest={'version':2,'platform':'fixture','protocol_min':1,'protocol_max':1,'artifact':'fixture.bin','sha256':digest(artifact),'length':len(artifact)}
 def metadata(expire=expiry,version=1):
  (d/'targets/fixture.manifest.json').write_bytes(canonical(manifest))
  targets={}
  for p in (d/'targets').iterdir():
   if p.is_file():b=p.read_bytes();targets[p.name]={'length':len(b),'hashes':{'sha256':digest(b)}}
  t=write('targets.json',{'_type':'targets','spec_version':'1.0.0','version':version,'expires':expiry,'targets':targets})
  s=write('snapshot.json',{'_type':'snapshot','spec_version':'1.0.0','version':version,'expires':expiry,'meta':{'targets.json':t}})
  write('timestamp.json',{'_type':'timestamp','spec_version':'1.0.0','version':version,'expires':expire,'meta':{'snapshot.json':s}})
 metadata()
 keys=core({'op':'keys'});payload={'nonce':'fixture','result':{'approved_release':2,'sha256':digest(artifact)}}
 signature=core({'op':'sign','domain':'admin-result','payload':payload,'signing_private':keys['signing_private']})['signature'];(d/'approval.json').write_text(json.dumps({'payload':payload,'signature':signature}))
 def openssl(*args):subprocess.run(['openssl',*map(str,args)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',d/'ca.key','-out',d/'ca.crt','-days','1','-subj','/CN=Fixture CA','-addext','basicConstraints=critical,CA:TRUE')
 openssl('req','-new','-newkey','rsa:2048','-nodes','-keyout',d/'tls.key','-out',d/'tls.csr','-subj','/CN=localhost')
 (d/'extensions').write_text('subjectAltName=DNS:localhost\nbasicConstraints=critical,CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n')
 openssl('x509','-req','-in',d/'tls.csr','-CA',d/'ca.crt','-CAkey',d/'ca.key','-CAcreateserial','-out',d/'tls.crt','-days','1','-extfile',d/'extensions')

 class Handler(http.server.SimpleHTTPRequestHandler):
  def __init__(self,*a,**kw):super().__init__(*a,directory=str(d),**kw)
  def log_message(self,*args):pass
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(str(d/'tls.crt'),str(d/'tls.key'));server.socket=ctx.wrap_socket(server.socket,server_side=True);threading.Thread(target=server.serve_forever,daemon=True).start();port=server.server_port
 def test(name,success=True,current=1,cache=None):
  out=d/(name+'.artifact');env=os.environ.copy();env['SSL_CERT_FILE']=str(d/'ca.crt');env['SSL_CERT_DIR']=str(d/'no-extra-roots')
  cmd=[str(BIN/'duct-update'),'--root',str(d/'root.json'),'--metadata-url',f'https://localhost:{port}/metadata/','--targets-url',f'https://localhost:{port}/targets/','--cache',str(d/((cache or name)+'-cache')),'--approval',str(d/'approval.json'),'--server-key',keys['signing_key'],'--platform','fixture','--current-version',str(current),'--output',str(out)]
  p=subprocess.run(cmd,env=env,text=True,capture_output=True,timeout=30)
  assert (p.returncode==0)==success,(name,p.stdout,p.stderr)
  assert out.exists()==success,(name,'output was not fail-closed')
  if success:assert out.read_bytes()==artifact
  checks.append(name);print('PASS',name)
 try:
  test('valid_TUF_and_Owner_approval')
  test('client_version_rollback_rejected',False,current=3)
  metadata(version=2);test('persistent_metadata_advance',cache='persistent')
  metadata();test('persistent_metadata_rollback_rejected',False,cache='persistent')
  (d/'targets/fixture.bin').write_bytes(b'corrupted artifact')
  test('tampered_artifact_rejected',False)
  (d/'targets/fixture.bin').write_bytes(artifact)
  timestamp=d/'metadata/timestamp.json';saved=timestamp.read_bytes();v=json.loads(saved);v['signatures'][0]['sig']='00'*64;timestamp.write_bytes(canonical(v))
  test('bad_metadata_signature_rejected',False);timestamp.write_bytes(saved)
  metadata('2020-01-01T00:00:00Z');test('expired_metadata_rejected',False);metadata()
  approval=d/'approval.json';saved=approval.read_bytes();v=json.loads(saved);v['payload']['result']['sha256']='00'*32;approval.write_bytes(canonical(v))
  test('tampered_Owner_approval_rejected',False);approval.write_bytes(saved)
  manifest['protocol_min']=2;metadata();test('protocol_incompatibility_rejected',False)
 finally:server.shutdown();server.server_close()
print(json.dumps({'passed':checks,'not_tested':['production_root_ceremony','platform_installer','release_publication']}))
