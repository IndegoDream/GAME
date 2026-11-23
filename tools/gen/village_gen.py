#!/usr/bin/env python3
"""Eliet, rebuilt as a country village: wide green, spread farmsteads, orchards, a mill, a river, a market lane. Idempotent (keeps levels/village.json.bak-country)."""
import json, random, shutil, os, math
P='levels/village.json'
if not os.path.exists(P+'.bak-country'): shutil.copy(P,P+'.bak-country')
src=json.load(open(P+'.bak-country'))
W,H=140,108
rng=random.Random(1282)
g=[[' ']*W for _ in range(H)]
cx,cy=70,54
# land: a soft oval
for y in range(H):
    for x in range(W):
        dx=(x-cx)/66.0; dy=(y-cy)/50.0
        n=0.04*math.sin(x*0.31)+0.04*math.sin(y*0.27+1)
        if dx*dx+dy*dy < 1.0+n: g[y][x]='.'
def inside(x,y): return 0<=x<W and 0<=y<H
def put(x,y,c):
    if inside(x,y) and g[y][x]!=' ': g[y][x]=c
def at(x,y): return g[y][x] if inside(x,y) else ' '
# edge: trees ring 3 deep (woods feel)
for y in range(H):
    for x in range(W):
        if g[y][x]=='.':
            d=min(1 if at(x+dx,y+dy)==' ' else 99 for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])
    pass
def edge_dist(x,y):
    best=99
    for r in range(1,7):
        for dx in range(-r,r+1):
            for dy in range(-r,r+1):
                if max(abs(dx),abs(dy))==r and at(x+dx,y+dy)==' ': return r
    return best
for y in range(H):
    for x in range(W):
        if g[y][x]=='.':
            e=edge_dist(x,y)
            if e<=2 or (e<=5 and rng.random()<0.5): g[y][x]='t'
# river: from west edge, winding south of centre, to east edge
def river():
    y=cy+22.0
    pts=[]
    for x in range(0,W):
        y+= 0.6*math.sin(x*0.09)+rng.uniform(-0.25,0.25)
        yy=int(y)
        for w in range(-1,2): pts.append((x,yy+w))
    for x,yy in pts:
        if at(x,yy) in '.t': g[yy][x]='~'
river()
# roads
def road(x0,y0,x1,y1,wd=1):
    x,y=x0,y0
    while (x,y)!=(x1,y1):
        for ox in range(wd):
            for oy in range(wd):
                if at(x+ox,y+oy) in '.t~': g[y+oy][x+ox]=','
        if x!=x1 and (y==y1 or rng.random()<0.5): x+=1 if x1>x else -1
        else: y+=1 if y1>y else -1
    put(x1,y1,',')
def clear(x,y,rx,ry,c='.'):
    for yy in range(y-ry,y+ry+1):
        for xx in range(x-rx,x+rx+1):
            if at(xx,yy)!=' ': g[yy][xx]=c
# ---- plaza and fountain
clear(cx,cy,9,6)
for yy in range(cy-6,cy+7):
    for xx in range(cx-9,cx+10):
        if ((xx-cx)/9.0)**2+((yy-cy)/6.0)**2<=1.0 and at(xx,yy)!=' ': g[yy][xx]=','
g[cy][cx]='f'
# north: dungeon stairs plaza
clear(cx,18,6,4); 
for yy in range(15,23):
    for xx in range(cx-6,cx+7): put(xx,yy,',') if abs(xx-cx)<=3 else None
put(cx,14,'D')
road(cx,22,cx,cy-6,3)
# south: main road across a bridge to the valley road (south edge)
PX,PY=cx,cy+9
road(cx,cy+6,cx,H-6,3)
# bridge is just road over water already carved by road(); keep a lantern pair
# east / west cross road
road(cx+9,cy,W-14,cy+1,2)
road(cx-9,cy,14,cy+1,2)
# ---- buildings
def building(x,y,w,h):
    for yy in range(y-1,y+h+1):
        for xx in range(x-1,x+w+1):
            if at(xx,yy) in 't~': g[yy][xx]='.'
    for yy in range(y,y+h):
        for xx in range(x,x+w): put(xx,yy,'H')
def free(x,y,w,h,m=2):
    for yy in range(y-m,y+h+m):
        for xx in range(x-m,x+w+m):
            if at(xx,yy) not in '.': return False
    return True
def farmstead(x,y):
    if not free(x,y,6,3,3): return False
    building(x,y,4,3); building(x+5,y+1,2,2)
    for k in range(rng.randint(2,5)): put(x+rng.randint(-2,8),y+rng.randint(4,7),'h') if rng.random()<0.5 else None
    # a yard of trees (orchard) behind
    for i in range(3):
        for j in range(2): put(x-2+i*3,y-4-j*3,'t') if at(x-2+i*3,y-4-j*3)=='.' else None
    return True
spots=[]
tries=0
while len(spots)<22 and tries<4000:
    tries+=1
    x=rng.randint(10,W-16); y=rng.randint(10,H-14)
    if abs(x-cx)<16 and abs(y-cy)<12: continue
    if abs(x-cx)<5: continue
    if any(abs(x-a)<13 and abs(y-b)<9 for a,b in spots): continue
    if farmstead(x,y): spots.append((x,y))
# ---- named places (reserved clearings), connected to roads
places={}
def place(name,x,y,w,h):
    clear(x+w//2,y+h//2,w//2+3,h//2+3)
    building(x,y,w,h); places[name]=(x,y,w,h)
    cxx,cyy=x+w//2,y+h+2
    road(cxx,cyy,cx if abs(cxx-cx)<30 else cxx,cy+1 if cyy<cy else cy-1,1)
# market lane east of plaza: M merchant stall row
clear(cx+22,cy-3,10,4)
for xx in range(cx+12,cx+33): put(xx,cy-3,',')
# NPC letters on open ground near plaza & lanes
npc_spots={'E':(cx-3,cy-3),'V':(cx+3,cy+3),'R':(cx-4,cy+3),'Y':(cx+5,cy-3),'Q':(cx-2,cy-9),
 'M':(cx+16,cy-5),'A':(cx-17,cy-5),'F':(cx+27,cy-5),'N':(cx-26,cy-5),'W':(cx+5,cy+20)}
# make clearings for them with a small building behind
for k,(x,y) in npc_spots.items():
    clear(x,y,2,2)
    g[y][x]=k
# shops behind M F A N (building behind each)
for k in 'MFAN':
    x,y=npc_spots[k]; building(x-2,y-6,5,3)
    for yy in range(y-3,y+1): put(x,yy,',')
    g[y][x]=k
# W (gatherers) cottage near the river bank, farm side
x,y=npc_spots['W']; clear(x,y,3,2); building(x+2,y-4,4,3); g[y][x]='W'
# connect W with road from plaza south... main road passes at x=cx so link
road(x,y-1,cx,y-1,1)
# ---- shrine on a hill NE with trees around
sx,sy=cx+38,cy-28
clear(sx,sy,6,5); g[sy][sx]='Z'
for a in range(0,360,40):
    px=int(sx+8*math.cos(math.radians(a))); py=int(sy+6*math.sin(math.radians(a)))
    if at(px,py)=='.': put(px,py,'t')
road(sx,sy+3,cx+12,cy-3,1)
# ---- mill by the river (west) & fishing spots
mx,my=cx-40,cy+14
clear(mx,my,5,3); building(mx-2,my-1,4,3)
road(mx,my+3,cx-9,cy+1,1)
for i in range(6):
    xx=cx-30+i*11
    for yy in range(H):
        if at(xx,yy)=='~': 
            if at(xx,yy-1)=='.': g[yy-1][xx]='&'
            break
# herb garden by apothecary
nx,ny=npc_spots['N']
for i in range(-3,4): 
    if at(nx+i,ny-9)=='.': g[ny-9][nx+i]='h'
# ---- lamps along roads every ~9 cells
for y in range(1,H-1):
    for x in range(1,W-1):
        if g[y][x]==',' and (x*7+y*13)%11==0 and any(at(x+dx,y+dy)=='.' for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]):
            for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                if at(x+dx,y+dy)=='.': g[y+dy][x+dx]='L'; break
# scattered trees & herbs in meadows
for y in range(6,H-6):
    for x in range(6,W-6):
        if g[y][x]=='.':
            r=rng.random()
            if r<0.012: g[y][x]='t'
            elif r<0.016: g[y][x]='h'
# 2026-11-06: the east road ends at the way to the Common City
for xx in range(W-14, W-9):
    if at(xx,cy+1)!=' ': g[cy+1][xx]=','
g[cy+1][W-10]='C'
# player start
g[PY][PX]='P'
# re-assert key chars
g[cy][cx]='f'
put(cx,14,'D')
# lore stones
rows=[''.join(r).rstrip() for r in g]
ex=dict(src['exits']); ex['C']={'to':'city','arrive':'E','label':'The east road -- the Common City'}
d={'id':'village','name':src['name'],'theme':'village','depth':0,'notes':src['notes'],'map':rows,'npcs':src['npcs'],'exits':ex,'lore':src['lore']}
json.dump(d,open(P,'w'),indent=1,ensure_ascii=False)
# reachability check from P
from collections import deque
WALK='.,PLoh=Z^&'
start=(PX,PY); seen={start}; q=deque([start])
while q:
    x,y=q.popleft()
    for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
        n=(x+dx,y+dy)
        if n in seen or not inside(*n): continue
        if g[n[1]][n[0]] in WALK+'MFAWNEVRYQD': seen.add(n); q.append(n)
miss=[]
for k in 'MFAWNEVRYQDZfC':
    pos=[(x,y) for y in range(H) for x in range(W) if g[y][x]==k]
    if not pos: miss.append(k+':absent'); continue
    ok=any(any((x+dx,y+dy) in seen for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]) for x,y in pos)
    if not ok: miss.append(k+':unreachable')
print('size',W,H,'farms',len(spots),'unreachable/absent:',miss)
