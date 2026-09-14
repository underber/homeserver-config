import io, json, os, time, zipfile
from pathlib import Path
from PIL import Image, ImageFilter, ImageStat, ImageChops
INBOX=Path(os.environ.get("MOIRE_INBOX","/data/incoming")); OUT=Path(os.environ.get("MOIRE_PROCESSED","/data/processed")); REVIEW=Path(os.environ.get("MOIRE_REVIEW","/data/review"))
POLL=float(os.environ.get("MOIRE_POLL_SECONDS","20")); LIGHT=float(os.environ.get("MOIRE_LIGHT_BLUR","0.35")); HEAVY=float(os.environ.get("MOIRE_HEAVY_BLUR","0.70")); THRESH=float(os.environ.get("MOIRE_SCORE_THRESHOLD","7.0")); HEAVY_T=float(os.environ.get("MOIRE_HEAVY_THRESHOLD","15.0"))
EXT={".jpg",".jpeg",".png",".webp"}
def score(im):
 g=im.convert("L").resize((256,256)); b=g.filter(ImageFilter.GaussianBlur(1.2)); return ImageStat.Stat(ImageChops.difference(g,b)).mean[0]
def classify(im):
 # High-frequency energy is a conservative local proxy for screen-tone/JPEG noise.
 from PIL import ImageChops
 s=score(im)
 return ("skip",s) if s<THRESH else (("heavy",s) if s>=HEAVY_T else ("light",s))
def fix(src):
 target=OUT/f"{src.stem} [moire-fixed].cbz"; tmp=OUT/f".{src.stem}.tmp.cbz"; manifest=[]
 with zipfile.ZipFile(src) as zin, zipfile.ZipFile(tmp,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as zout:
  infos=zin.infolist(); images=[i for i in infos if Path(i.filename).suffix.lower() in EXT]; names={i.filename for i in images}
  if not images: raise ValueError("CBZ contains no supported images")
  sample=images[len(images)//2].filename
  for info in infos:
   data=zin.read(info); mode="copy"; s=0.0
   if info.filename in names:
    with Image.open(io.BytesIO(data)) as im:
     mode,s=classify(im); fixed=im.convert("RGB")
     if mode!="skip": fixed=fixed.filter(ImageFilter.GaussianBlur(LIGHT if mode=="light" else HEAVY)).filter(ImageFilter.UnsharpMask(.7,115 if mode=="light" else 105,3))
     buf=io.BytesIO(); ext=Path(info.filename).suffix.lower()
     if mode!="skip":
      if ext in {".jpg",".jpeg"}: fixed.save(buf,"JPEG",quality=95,optimize=True,subsampling=0)
      elif ext==".png": fixed.save(buf,"PNG",optimize=True)
      else: fixed.save(buf,"JPEG",quality=95,optimize=True,subsampling=0)
      data=buf.getvalue()
     if info.filename==sample:
      fixed.thumbnail((1400,2000)); fixed.save(REVIEW/f"{src.stem} [after].jpg","JPEG",quality=92)
     manifest.append({"page":info.filename,"action":mode,"score":round(s,2)})
   zout.writestr(info,data)
 with zipfile.ZipFile(tmp) as check:
  if check.testzip() is not None: raise ValueError("generated CBZ failed integrity check")
 tmp.replace(target); (REVIEW/f"{src.stem} [manifest].json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)); return target
def main():
 for p in (INBOX,OUT,REVIEW): p.mkdir(parents=True,exist_ok=True)
 print(f"watching {INBOX}; threshold={THRESH}",flush=True)
 while True:
  for src in sorted(INBOX.glob("*.cbz")):
   target=OUT/f"{src.stem} [moire-fixed].cbz"
   if target.exists() and target.stat().st_mtime>=src.stat().st_mtime: continue
   try: print(f"completed {fix(src).name}",flush=True)
   except Exception as e: print(f"ERROR {src.name}: {e}",flush=True)
  time.sleep(POLL)
if __name__=="__main__": main()
