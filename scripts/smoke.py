#!/usr/bin/env python3
"""Runs real local gateway/registry processes; never starts or fakes a WireGuard helper."""
import base64, ctypes, json, os, pathlib, subprocess, tempfile, time, urllib.request, urllib.error
ROOT=pathlib.Path(__file__).resolve().parents[1]
BIN=ROOT/'target/release'
if not (BIN/'ductctl').exists(): BIN=ROOT/'target/debug'
lib=ctypes.CDLL(str(BIN / ('libduct_bridge.dylib' if __import__('sys').platform == 'darwin' else 'libduct_bridge.so')))
lib.duct_call.argtypes=[ctypes.c_char_p];lib.duct_call.restype=ctypes.c_void_p;lib.duct_free.argtypes=[ctypes.c_void_p]
def core(v):
    p=lib.duct_call(json.dumps(v).encode())
    try:r=json.loads(ctypes.string_at(p))
    finally:lib.duct_free(p)
    assert 'ok' in r,r
    return r['ok']
def b64(v):return base64.urlsafe_b64encode(v).decode().rstrip('=')
def command(*args):return subprocess.check_output([str(BIN/'ductctl'),*map(str,args)],text=True)
def post(port,path,value):
    req=urllib.request.Request(f'http://127.0.0.1:{port}{path}',data=json.dumps(value).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=5) as r:return json.load(r)
checks=[]
def check(name,value):assert value,name;checks.append(name);print('PASS',name)
processes=[]
with tempfile.TemporaryDirectory(prefix='dtvpn-smoke-') as temp:
    d=pathlib.Path(temp);os.chmod(d,0o700)
    try:
        command('keys','--directory',d/'owner')
        server_wg=core({'op':'keys'})['wireguard_key']
        output=command('bootstrap','--database',d/'registry.db','--identity',d/'server.key','--owner-public',d/'owner/public.json','--server-wireguard',server_wg,'--endpoint','vpn.example.org:51820')
        server_key=output.strip().split('server_key=')[1]
        config={'database':str(d/'registry.db'),'identity':str(d/'server.key'),'public_socket':str(d/'public.sock'),'admin_socket':str(d/'admin.sock'),'helper_socket':str(d/'absent-helper.sock')}
        (d/'config.json').write_text(json.dumps(config))
        processes.append(subprocess.Popen([str(BIN/'duct-registry'),'--config',str(d/'config.json')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
        for _ in range(100):
            if (d/'admin.sock').exists():break
            time.sleep(.02)
        import socket
        with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
        processes.append(subprocess.Popen([str(BIN/'duct-gateway'),'--socket',str(d/'public.sock'),'--listen',f'127.0.0.1:{port}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
        for _ in range(100):
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.1):break
            except OSError:time.sleep(.02)
        def admin(op):
            (d/'op.json').write_text(json.dumps(op))
            return json.loads(command('admin','--socket',d/'admin.sock','--identity',d/'owner/signing.key','--server-key',server_key,'--operation',d/'op.json'))['payload']['result']
        try:post(port,'/v1/admin',{})
        except urllib.error.HTTPError as e:check('public gateway has no administration route',e.code==404)
        else:raise AssertionError('public admin exposed')
        try:post(port,'/v1/challenge',{'padding':'x'*9000})
        except urllib.error.HTTPError as e:check('oversized request rejected',e.code==413)
        else:raise AssertionError('oversized request accepted')
        invitation=admin({'type':'invite','ttl_seconds':300})
        keys=core({'op':'keys'})
        enrollment={'server_id':core({'op':'server_id','server_key':server_key})['server_id'],'invitation':invitation['token'],'name':'Smoke phone','platform':'android','signing_key':keys['signing_key'],'wireguard_key':keys['wireguard_key']}
        challenge=post(port,'/v1/challenge',enrollment)
        answer=core({'op':'answer','challenge':challenge,'enrollment':enrollment,'server_key':server_key,'wireguard_private':keys['wireguard_private'],'signing_private':keys['signing_private'],'now':int(time.time())})
        result=post(port,'/v1/claim',answer['claim'])
        check('HPKE key-possession enrollment through real gateway',result['payload']['status']=='pending')
        check('pending device recorded for Owner review',len(admin({'type':'list'})['devices'])==2)
        admin({'type':'approve','id':answer['claim']['id'],'fingerprint':answer['fingerprint']})
        auth={'server_id':enrollment['server_id'],'id':answer['claim']['id'],'nonce':b64(os.urandom(32)),'expires_at':int(time.time())+30}
        signature=core({'op':'sign','domain':'poll','payload':auth,'signing_private':keys['signing_private']})['signature']
        poll={k:v for k,v in auth.items() if k!='server_id'};poll['signature']=signature
        r=post(port,'/v1/poll',poll)
        check('unavailable helper prevents ready/configuration claim',r['payload']['result']['status']=='provisioning')
        admin({'type':'revoke','id':answer['claim']['id']})
        check('revocation persists in authenticated registry',any(x['status']=='revoked' for x in admin({'type':'list'})['devices']))
        generated=command('generate','--database',d/'registry.db','--identity',d/'server.key','--origin','https://vpn.example.org')
        code=generated.split('Activation code: ')[1].splitlines()[0]
        activation=post(port,'/v1/activate',{'code':code})
        check('console-generated code resolves through public gateway',activation['server_key']==server_key)
        keys=core({'op':'keys'})
        enrollment.update(invitation=activation['token'], signing_key=keys['signing_key'], wireguard_key=keys['wireguard_key'])
        challenge=post(port,'/v1/challenge',enrollment)
        answer=core({'op':'answer','challenge':challenge,'enrollment':enrollment,'server_key':server_key,'wireguard_private':keys['wireguard_private'],'signing_private':keys['signing_private'],'now':int(time.time())})
        post(port,'/v1/claim',answer['claim'])
        check('activation authorizes ordinary client without another approval',any(x['id']==answer['claim']['id'] and x['status']=='active' and x['role']=='client' for x in admin({'type':'list'})['devices']))
        try:post(port,'/v1/activate',{'code':code})
        except urllib.error.HTTPError as e:check('activation cannot be redeemed twice',e.code==400)
        else:raise AssertionError('activation reused')
        check('generate remembers server origin', 'Server: https://vpn.example.org' in command('generate','--database',d/'registry.db','--identity',d/'server.key'))
        (d/'pass').write_text('temporary fixture passphrase with strong random '+b64(os.urandom(24)))
        os.chmod(d/'pass',0o600)
        command('backup','--database',d/'registry.db','--identity',d/'server.key','--passphrase-file',d/'pass','--output',d/'backup.age')
        command('restore','--input',d/'backup.age','--passphrase-file',d/'pass','--directory',d/'restored')
        check('encrypted backup restores into offline quarantine',(d/'restored/QUARANTINED').exists())
        command('check','--database',d/'restored/registry.db','--identity',d/'restored/server.key')
        check('restored registry integrity and server identity verified',True)
    finally:
        for p in processes:p.terminate()
        for p in processes:p.wait(timeout=10)
print(json.dumps({'passed':checks,'not_tested':['TLS ingress','native clients','home server traffic']}))
