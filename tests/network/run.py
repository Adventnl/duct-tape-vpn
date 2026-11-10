"""Disposable-container kernel routing lab. Never run directly on a personal host."""
import json, os, pathlib, subprocess, tempfile, time, sys
if not pathlib.Path('/.dockerenv').exists():
    raise SystemExit('Run only in the disposable Docker lab')
def run(*args, input=None, ok=True):
    p=subprocess.run(args,input=input,text=True,capture_output=True,timeout=15)
    if ok and p.returncode: raise RuntimeError(f'{args}: {p.stderr}')
    return p

def ns(n,*args,**kwargs):return run('nsenter','--net=/run/netns/'+n,'--',*args,**kwargs)
def link(a,b,aa,ba):
    run('ip','link','add',a+b,'type','veth','peer','name',b+a)
    for name,namespace,addr in [(a+b,a,aa),(b+a,b,ba)]:
        run('ip','link','set',name,'netns',namespace)
        ns(namespace,'ip','addr','add',addr,'dev',name);ns(namespace,'ip','link','set',name,'up')
def http(n):return ns(n,'curl','--noproxy','*','--fail','--silent','--max-time','2','http://198.18.0.2:8080',ok=False)
checks=[]
def check(name,cond):
    if not cond:raise AssertionError(name)
    checks.append(name);print('PASS',name,flush=True)
procs=[]

try:
    for n in ['c','i']:run('ip','netns','add',n);ns(n,'ip','link','set','lo','up')
    run('ip','netns','attach','s',str(os.getpid()))
    link('c','s','192.0.2.2/24','192.0.2.1/24');link('s','i','198.18.0.1/24','198.18.0.2/24')
    ns('c','ip','route','add','default','via','192.0.2.1');ns('i','ip','route','add','default','via','198.18.0.1');check('container-only forwarding enabled',ns('s','sysctl','-n','net.ipv4.ip_forward').stdout.strip()=='1')
    server='''import socket
socket.getfqdn=lambda name: 'fixture.test'
from http.server import BaseHTTPRequestHandler,HTTPServer
class H(BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(200);self.end_headers();self.wfile.write(self.client_address[0].encode())
 def log_message(self,*args): pass
HTTPServer(('198.18.0.2',8080),H).serve_forever()
'''
    procs.append(subprocess.Popen(['nsenter','--net=/run/netns/i','--','python3','-c',server]))
    for _ in range(50):
        if http('i').returncode==0:break
        time.sleep(.1)
    print('fixture listener',ns('i','ss','-lnt').stdout,procs[0].poll(),flush=True)
    baseline=http('c')
    if baseline.stdout!='192.0.2.2':
        print('baseline result',baseline.returncode,baseline.stdout,baseline.stderr,flush=True)
        for n in ['c','s','i']:
            print(n,ns(n,'ip','route').stdout,ns(n,'nft','list','ruleset',ok=False).stdout,flush=True)
    check('OFF baseline ordinary connectivity',baseline.stdout=='192.0.2.2')
    keys={}
    for n in ['s','c']:
        private=run('wg','genkey').stdout.strip();public=run('wg','pubkey',input=private).stdout.strip();keys[n]=(private,public)
        path='/tmp/'+n+'.key';pathlib.Path(path).write_text(private);os.chmod(path,0o600)
        kernel=ns(n,'ip','link','add','wg0','type','wireguard',ok=False)
        if kernel.returncode:
            print('LIMITATION kernel WireGuard unavailable; using official userspace implementation in this lab only',flush=True)
            pathlib.Path('/dev/net').mkdir(exist_ok=True)
            if not pathlib.Path('/dev/net/tun').exists():os.mknod('/dev/net/tun',0o20666,os.makedev(10,200))
            ns(n,'wireguard-go','wg0')
        ns(n,'ip','addr','add','10.77.0.1/24' if n=='s' else '10.77.0.3/32','dev','wg0')
        ns(n,'ip','-6','addr','add','fd77:6474:7670::1/64' if n=='s' else 'fd77:6474:7670::3/128','dev','wg0')
        ns(n,'wg','set','wg0','private-key',path,'listen-port','51820');ns(n,'ip','link','set','wg0','mtu','1280','up')
    ns('s','wg','set','wg0','peer',keys['c'][1],'allowed-ips','10.77.0.3/32,fd77:6474:7670::3/128')
    ns('c','wg','set','wg0','fwmark','51820','peer',keys['s'][1],'allowed-ips','0.0.0.0/0,::/0','endpoint','192.0.2.1:51820','persistent-keepalive','1')
    ns('c','ip','route','add','default','dev','wg0','table','51820');ns('c','ip','rule','add','not','fwmark','51820','table','51820','priority','100')
    ns('c','ip','rule','add','table','main','suppress_prefixlength','0','priority','99')
    ns('c','ip','-6','route','add','default','dev','wg0','table','51820');ns('c','ip','-6','rule','add','not','fwmark','51820','table','51820','priority','100')
    ns('s','nft','-f','-',input='table ip dtvpn_nat { chain post { type nat hook postrouting priority srcnat; ip saddr 10.77.0.0/24 oifname "si" masquerade; } }')
    ns('c','nft','-f','-',input='''table inet dtvpn_client { chain output { type filter hook output priority -10; policy drop;
        oifname "lo" accept; oifname "wg0" accept;
        ip daddr 192.0.2.1 udp dport 51820 meta mark 51820 accept;
    } }''')
    check('ON home-server NAT exit address',http('c').stdout=='198.18.0.1')
    # Actual Unbound answers through the private WG address; deterministic local zone is lab-only.
    pathlib.Path('/tmp/unbound-lab.conf').write_text('''server:
    interface: 10.77.0.1
    port: 53
    username: ""
    chroot: ""
    pidfile: ""
    use-syslog: no
    access-control: 10.77.0.0/24 allow
    local-zone: "fixture.test." static
    local-data: "exit.fixture.test. 60 IN A 198.18.0.2"
''')
    procs.append(subprocess.Popen(['nsenter','--net=/run/netns/s','--','unbound','-d','-c','/tmp/unbound-lab.conf'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL));time.sleep(.4)
    dns=ns('c','dig','+short','+time=1','+tries=1','@10.77.0.1','exit.fixture.test','A')
    check('DNS answered by home-hosted Unbound through WireGuard',dns.stdout.strip()=='198.18.0.2')
    ns('c','ip','route','add','198.18.0.2/32','via','192.0.2.1')
    check('narrow underlying route cannot bypass strict output filter',http('c').returncode!=0)
    ns('c','ip','route','del','198.18.0.2/32')
    ns('s','wg','set','wg0','peer',keys['c'][1],'remove')
    check('revocation removes data-plane access',http('c').returncode!=0)
    ns('s','wg','set','wg0','peer',keys['c'][1],'allowed-ips','10.77.0.3/32,fd77:6474:7670::3/128')
    check('peer reconciliation reconnects',http('c').stdout=='198.18.0.1')
    ns('c','ip','link','delete','wg0')
    check('unexpected tunnel destruction keeps traffic blocked',http('c').returncode!=0)
    ns('c','ip','rule','del','priority','99');ns('c','ip','rule','del','priority','100');ns('c','ip','-6','rule','del','priority','100')
    check('fallback ordinary routes remain blocked until intentional OFF',http('c').returncode!=0)
    ns('c','nft','delete','table','inet','dtvpn_client')
    check('intentional OFF restores ordinary traffic',http('c').stdout=='192.0.2.2')
    run('unbound-checkconf','/production-unbound.conf',ok=False)
    print(json.dumps({'passed':checks,'not_tested':['native OS kill switches','public internet','external DoT/DNSSEC','home router','reboot','IPv6 dual-stack underlay']}))
finally:
    for p in procs:p.terminate()
    for p in procs:p.wait(timeout=5)
    for n in ['c','s','i']:run('ip','netns','delete',n,ok=False)
