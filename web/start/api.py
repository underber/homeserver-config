#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import json, os, shutil, sqlite3, subprocess, time

ROOT = Path('/srv/www/start')
LINKS = ROOT / 'links.json'
BG = ROOT / 'background.txt'
CHAT_DB = Path('/srv/data/chatgpt/search.db')
MAX_BODY = 256 * 1024
SERVICES = [
    ('Nextcloud', 'nextcloud-app-1', 'https://cloud.ts'),
    ('Jellyfin', 'jellyfin', 'https://jellyfin.ts'),
    ('Navidrome', 'navidrome', 'https://navidrome.ts'),
    ('Kavita', 'kavita', 'https://kavita.ts'),
    ('Komga', 'komga', 'https://komga.ts'),
    ('FreshRSS', 'freshrss', 'https://freshrss.ts'),
    ('Vaultwarden', 'vaultwarden', 'https://vault.ts'),
    ('Syncthing', 'syncthing', 'https://sync.ts'),
    ('Portainer', 'portainer', 'https://portainer.ts'),
    ('SearXNG', 'searxng', 'https://searxng.ts'),
]

def run(*cmd):
    try:
        return subprocess.run(cmd, text=True, capture_output=True, timeout=5, check=False).stdout.strip()
    except Exception:
        return ''

def disk(path):
    try:
        total, used, free = shutil.disk_usage(path)
        return {'total': total, 'used': used, 'free': free, 'percent': round(used * 100 / total, 1)}
    except OSError:
        return None

def memory():
    values={}
    try:
        for line in Path('/proc/meminfo').read_text().splitlines():
            key, value = line.split(':', 1)
            values[key] = int(value.strip().split()[0]) * 1024
        total=values['MemTotal']; available=values['MemAvailable']; used=total-available
        return {'total': total, 'used': used, 'available': available, 'percent': round(used*100/total,1)}
    except Exception:
        return None

def status_payload():
    running=set(run('docker','ps','--format','{{.Names}}').splitlines())
    services=[{'name': n, 'container': c, 'url': u, 'up': c in running} for n,c,u in SERVICES]
    backup=run('systemctl','show','homeserver-backup.service','-p','Result','-p','ExecMainExitTimestamp','--value').splitlines()
    try: uptime=float(Path('/proc/uptime').read_text().split()[0])
    except Exception: uptime=0
    return {
        'generated_at': int(time.time()), 'hostname': os.uname().nodename,
        'uptime_seconds': int(uptime), 'load': list(os.getloadavg()),
        'memory': memory(), 'root_disk': disk('/'), 'media_disk': disk('/srv/media'),
        'backup': {'result': backup[0] if backup else 'unknown', 'last': backup[1] if len(backup)>1 else ''},
        'services': services,
    }

def atomic_json(path, value):
    tmp=path.with_suffix(path.suffix+'.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    tmp.replace(path)

class Handler(BaseHTTPRequestHandler):
    def send_headers(self, code=200, content_type='application/json; charset=utf-8'):
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.end_headers()
    def send_json(self, value, code=200):
        self.send_headers(code)
        self.wfile.write(json.dumps(value, ensure_ascii=False).encode())
    def do_GET(self):
        path=urlparse(self.path).path
        if path.startswith('/api/'):
            path=path[4:]
        static = {'/': ('index.html','text/html; charset=utf-8'), '/index.html': ('index.html','text/html; charset=utf-8'), '/manifest.webmanifest': ('manifest.webmanifest','application/manifest+json'), '/sw.js': ('sw.js','text/javascript; charset=utf-8')}
        if path in static:
            name, content_type = static[path]
            try:
                payload=(ROOT/name).read_bytes()
                self.send_headers(200, content_type)
                self.wfile.write(payload)
            except OSError as e:
                self.send_json({'error':str(e)},500)
            return
        if path == '/status': return self.send_json(status_payload())
        if path == '/search':
            query=parse_qs(urlparse(self.path).query).get('q',[''])[0].strip()[:200]
            if not query or not CHAT_DB.exists(): return self.send_json([])
            try:
                con=sqlite3.connect(f'file:{CHAT_DB}?mode=ro',uri=True)
                rows=con.execute("SELECT c.title,c.created,c.filename,snippet(search,1,'<mark>','</mark>',' … ',24) FROM search JOIN conversations c ON c.rowid=search.rowid WHERE search MATCH ? ORDER BY rank LIMIT 30",(query,)).fetchall(); con.close()
                return self.send_json([{'title':r[0],'created':r[1],'filename':r[2],'snippet':r[3]} for r in rows])
            except Exception as e: return self.send_json({'error':str(e)},400)
        if path == '/links':
            try: return self.send_json(json.loads(LINKS.read_text(encoding='utf-8')))
            except Exception as e: return self.send_json({'error': str(e)}, 500)
        if path == '/bg':
            self.send_headers(200, 'text/plain; charset=utf-8')
            self.wfile.write((BG.read_text(encoding='utf-8') if BG.exists() else '').encode())
            return
        self.send_json({'error':'not found'},404)
    def read_body(self):
        length=int(self.headers.get('Content-Length','0'))
        if length<0 or length>MAX_BODY: raise ValueError('body too large')
        return self.rfile.read(length)
        if path.startswith('/api/'):
            path=path[4:]
    def do_POST(self):
        path=urlparse(self.path).path
        try:
            body=self.read_body()
            if path == '/links':
                data=json.loads(body)
                if not isinstance(data,list) or len(data)>100: raise ValueError('invalid links')
                clean=[]
                for item in data:
                    if not isinstance(item,dict): raise ValueError('invalid link')
                    name=str(item.get('name',''))[:80].strip(); url=str(item.get('url',''))[:2048].strip()
                    if not name or urlparse(url).scheme not in ('http','https'): raise ValueError('invalid URL')
                    clean.append({'name':name,'url':url,'iconMode':str(item.get('iconMode','auto'))[:10],'icon':str(item.get('icon',''))[:2048]})
                atomic_json(LINKS,clean); return self.send_json({'ok':True})
            if path == '/bg':
                value=body.decode('utf-8').strip()[:2048]
                if value and urlparse(value).scheme not in ('http','https'): raise ValueError('invalid URL')
                BG.write_text(value,encoding='utf-8'); return self.send_json({'ok':True})
            return self.send_json({'error':'not found'},404)
        except Exception as e: return self.send_json({'error':str(e)},400)
    def log_message(self, fmt, *args):
        print('%s - %s' % (self.address_string(), fmt % args))

ThreadingHTTPServer(('127.0.0.1',5000),Handler).serve_forever()
