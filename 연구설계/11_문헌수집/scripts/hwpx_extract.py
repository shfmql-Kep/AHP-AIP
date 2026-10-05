import zipfile,re,sys,html
f=sys.argv[1]; out=sys.argv[2]
z=zipfile.ZipFile(f)
secs=sorted(n for n in z.namelist() if re.match(r'Contents/section\d+\.xml',n))
print(secs,[z.getinfo(n).file_size for n in secs])
txt=[]
for n in secs:
    x=z.read(n).decode('utf8')
    for p in re.findall(r'<hp:p\b.*?</hp:p>',x,flags=re.S):
        t=''.join(re.findall(r'<hp:t>(.*?)</hp:t>',p,flags=re.S))
        t=re.sub(r'<[^>]+>','',t); t=html.unescape(t).strip()
        if t: txt.append(t)
open(out,'w',encoding='utf8').write('\n'.join(txt))
print(len(txt),sum(map(len,txt)))
