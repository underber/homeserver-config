import io, os, time, zipfile
from pathlib import Path
from PIL import Image, ImageFilter
INBOX=Path(os.environ.get("MOIRE_INBOX","/data/incoming")); OUT=Path(os.environ.get("MOIRE_PROCESSED","/data/processed")); REVIEW=Path(os.environ.get("MOIRE_REVIEW","/data/review"))
POLL=float(os.environ.get("MOIRE_POLL_SECONDS","20")); BLUR=float(os.environ.get("MOIRE_BLUR_RADIUS","0.55")); SHARPEN=int(os.environ.get("MOIRE_SHARPEN_PERCENT","115"))
def fix(src):
 target=OUT/f"{src.stem} [moire-fixed].cbz"; tmp=OUT/f".{src.stem}.tmp.cbz"
 with zipfile.ZipFile(src) as zin, zipfile.ZipFile(tmp,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as zout:
  infos=zin.infolist(); images=[i for i in infos if Path(i.filename).suffix.lower() in {".jpg",".jpeg",".png",".webp"}]; names={i.filename for i in images}
  if not images: raise ValueError("CBZ contains no supported images")
  sample=images[len(images)//2].filename
  for info in infos:
   data=zin.read(info)
   if info.filename in names:
    with Image.open(io.BytesIO(data)) as im:
     fixed=im.convert("RGB").filter(ImageFilter.GaussianBlur(BLUR)).filter(ImageFilter.UnsharpMask(.7,SHARPEN,3)); buf=io.BytesIO(); ext=Path(info.filename).suffix.lower()
     if ext in {".jpg",".jpeg"}: fixed.save(buf,"JPEG",quality=95,optimize=True,subsampling=0)
     elif ext==".png": fixed.save(buf,"PNG",optimize=True)
     else: fixed.save(buf,"JPEG",quality=95,optimize=True,subsampling=0)
     data=buf.getvalue()
     if info.filename==sample: fixed.thumbnail((1400,2000)); fixed.save(REVIEW/f"{src.stem} [after].jpg","JPEG",quality=92)
   zout.writestr(info,data)
 with zipfile.ZipFile(tmp) as check:
  if check.testzip() is not None: raise ValueError("generated CBZ failed integrity check")
 tmp.replace(target); return target
def main():
 for p in (INBOX,OUT,REVIEW): p.mkdir(parents=True,exist_ok=True)
 print(f"watching {INBOX}",flush=True)
 while True:
  for src in sorted(INBOX.glob("*.cbz")):
   target=OUT/f"{src.stem} [moire-fixed].cbz"
   if target.exists() and target.stat().st_mtime>=src.stat().st_mtime: continue
   try: print(f"completed {fix(src).name}",flush=True)
   except Exception as e: print(f"ERROR {src.name}: {e}",flush=True)
  time.sleep(POLL)
if __name__=="__main__": main()
