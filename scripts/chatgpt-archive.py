#!/usr/bin/env python3
import json, re, shutil, sqlite3, tempfile, zipfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
SOURCE=Path('/var/lib/docker/volumes/nextcloud_nextcloud_data/_data/data')
DEST=Path('/srv/data/chatgpt'); TEXT=DEST/'text'; DB=DEST/'search.db'; JST=ZoneInfo('Asia/Tokyo')
def part_text(p):
    if isinstance(p,str): return p
    if isinstance(p,dict):
        for k in ('text','result','caption'):
            if isinstance(p.get(k),str): return p[k]
        n=p.get('name') or p.get('filename'); return f'[添付: {n}]' if n else ''
    return ''
def msg_text(m):
    c=m.get('content') or {}; parts=c.get('parts') if isinstance(c,dict) else None
    if isinstance(parts,list): return '\n'.join(filter(None,(part_text(x).strip() for x in parts))).strip()
    return str(c.get('text') or '').strip() if isinstance(c,dict) else ''
def stamp(v):
    try:return datetime.fromtimestamp(float(v),JST).strftime('%Y-%m-%d %H:%M:%S JST')
    except:return ''
def safe(s): return re.sub(r'[\\/:*?"<>|\x00-\x1f]','＿',s).strip()[:90] or '無題'
def latest_export():
    candidates=[]
    if SOURCE.exists():
        for p in SOURCE.rglob('*.zip'):
            try:
                with zipfile.ZipFile(p) as z:
                    if any(n.startswith('conversations') and n.endswith('.json') for n in z.namelist()): candidates.append(p)
            except (OSError,zipfile.BadZipFile): pass
    return max(candidates,key=lambda p:p.stat().st_mtime) if candidates else None
def main():
    src=latest_export()
    if not src: raise SystemExit('ChatGPT export ZIP not found')
    DEST.mkdir(parents=True,exist_ok=True); marker=DEST/'source.json'
    sig={'path':str(src),'size':src.stat().st_size,'mtime_ns':src.stat().st_mtime_ns}
    if marker.exists() and DB.exists() and json.loads(marker.read_text())==sig: return
    conversations=[]
    with zipfile.ZipFile(src) as z:
        for name in sorted(n for n in z.namelist() if n.startswith('conversations') and n.endswith('.json')): conversations.extend(json.loads(z.read(name)))
    conversations.sort(key=lambda c:c.get('create_time') or 0)
    tmpdir=Path(tempfile.mkdtemp(prefix='chatgpt-index-',dir=DEST)); textdir=tmpdir/'text'; textdir.mkdir(); dbpath=tmpdir/'search.db'
    con=sqlite3.connect(dbpath)
    con.executescript("CREATE TABLE conversations(id TEXT PRIMARY KEY,title TEXT,created TEXT,updated TEXT,body TEXT,filename TEXT); CREATE VIRTUAL TABLE search USING fts5(title,body,content='conversations',content_rowid='rowid',tokenize='unicode61');")
    for i,c in enumerate(conversations,1):
        title=str(c.get('title') or '無題'); cid=str(c.get('id') or c.get('conversation_id') or i); created=stamp(c.get('create_time')); updated=stamp(c.get('update_time')); nodes=[]
        for node in (c.get('mapping') or {}).values():
            m=node.get('message') or {}; text=msg_text(m); role=(m.get('author') or {}).get('role')
            if text and role in ('user','assistant'): nodes.append((m.get('create_time') or 0,role,text))
        messages=[f'[{"ユーザー" if role=="user" else "ChatGPT"}] {stamp(when)}\n{text}' for when,role,text in sorted(nodes)]
        body='\n\n'.join(messages); filename=f'{i:03d}_{created[:10] or "0000-00-00"}_{safe(title)}.txt'
        (textdir/filename).write_text(f'タイトル: {title}\n作成日時: {created}\n更新日時: {updated}\n{"="*72}\n\n{body}\n',encoding='utf-8')
        cur=con.execute('INSERT INTO conversations VALUES(?,?,?,?,?,?)',(cid,title,created,updated,body,filename)); con.execute('INSERT INTO search(rowid,title,body) VALUES(?,?,?)',(cur.lastrowid,title,body))
    con.commit(); con.close()
    if TEXT.exists(): shutil.rmtree(TEXT)
    textdir.replace(TEXT); dbpath.replace(DB); tmpdir.rmdir(); marker.write_text(json.dumps(sig,ensure_ascii=False,indent=2)+'\n')
    (DEST/'README.txt').write_text(f'会話数: {len(conversations)}\n更新: {datetime.now(JST).isoformat()}\n',encoding='utf-8')
    print(f'indexed {len(conversations)} conversations')
if __name__=='__main__': main()
