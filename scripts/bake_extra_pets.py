import json, pathlib, shutil
from PIL import Image
ROOT=pathlib.Path(__file__).resolve().parents[1]
for item in json.loads((ROOT/'scripts/extra_pet_art_sources.json').read_text()):
    image=Image.open(item['path']); assert image.size==(1536,1024)
    alpha=image.getchannel('A'); assert alpha.getextrema()[0]==0
    # Read-only alpha analysis. The original generated PNG is copied without pixel changes.
    cells=[(0,0),(512,0),(1024,0),(0,512),(512,512),(1024,512)]
    rects=[]
    for x,y in cells:
        pixels=alpha.crop((x,y,x+512,y+512)).tobytes()
        seen=bytearray(512*512); components=[]
        for start,value in enumerate(pixels):
            if value <= 96 or seen[start]: continue
            todo=[start];seen[start]=1; area=0;minx=miny=512;maxx=maxy=0
            while todo:
                i=todo.pop();px=i%512;py=i//512;area+=1
                minx=min(minx,px);maxx=max(maxx,px);miny=min(miny,py);maxy=max(maxy,py)
                for ni in (i-512,i+512,i-1,i+1):
                    if 0<=ni<512*512 and abs(ni%512-px)<=1 and not seen[ni] and pixels[ni]>96: seen[ni]=1;todo.append(ni)
            components.append((area,(minx,miny,maxx+1,maxy+1)))
        box=max(components)[1]; assert box
        rects.append([box[0]+x,box[1]+y,box[2]-box[0],box[3]-box[1]])
    parts={}
    for key,index,size,anchor,offset in [('head',0,[154,130],[.5,.1],[0,54]),('body',1,[132,98],[.5,.2],None),('left_paw',2,[28,35],[.5,.85],[-34,42]),('right_paw',3,[28,35],[.5,.85],[34,42]),('tail',4,[65,45],[.12,.5],[-45,12])]:
        parts[key]={'file':'illustration.png','texture_rect':rects[index],'display_size':size,'anchor':anchor}
        if offset: parts[key]['parent_offset']=offset
        if key=='head': parts[key]['eyes']=[[.21,.54],[.80,.54]] if item['id']=='capybara' else [[.33,.55],[.67,.55]]
    target=ROOT/'macos/Resources/Pets'/item['id'];target.mkdir(exist_ok=True)
    shutil.copy2(item['path'],target/'illustration.png')
    (target/'atlas.json').write_text(json.dumps({'id':item['id'],'name':item['name'],'parts':parts,'preview_rect':rects[5]},indent=2)+'\n')
    print(item['id'],rects)
