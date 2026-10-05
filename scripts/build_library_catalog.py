"""Bake original, parametric PawSync wearables. No Paw-Paw item artwork is copied."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# Each silhouette is drawn by LibraryAccessoryArt, not an emoji or placeholder.
styles=[('leaf','Plants',['Mint leaf','Tea leaf','Autumn leaf','Sage leaf','Lime leaf','Willow leaf']),('flower','Plants',['Daisy','Cherry blossom','Bluebell','Sunflower','Lavender','Poppy']),('mushroom','Plants',['Forest mushroom','Rosy mushroom','Moon mushroom','Golden mushroom','Moss mushroom','Snow mushroom']),('fruit','Food',['Peach','Apple','Orange','Pear','Plum','Lemon']),('berry','Food',['Strawberry','Blueberry','Raspberry','Blackberry','Cloudberry','Gooseberry']),('donut','Food',['Strawberry donut','Sugar donut','Lavender donut','Honey donut','Mint donut','Chocolate donut']),('cupcake','Food',['Peach cupcake','Vanilla cupcake','Blueberry cupcake','Caramel cupcake','Pistachio cupcake','Cocoa cupcake']),('dumpling','Food',['Cozy dumpling','Steamed bun','Sesame bun','Peach bao','Herby dumpling','Moon bun']),('toast','Food',['Berry toast','Butter toast','Honey toast','Cocoa toast','Mint toast','Peach toast']),('cup','Food',['Matcha cup','Berry tea','Cloud cocoa','Honey latte','Peach tea','Moon milk']),('bow','Accessories',['Rose ribbon','Cream ribbon','Lilac ribbon','Amber ribbon','Mint ribbon','Velvet ribbon']),('beanie','Accessories',['Rose knit','Oat knit','Lilac knit','Honey knit','Sage knit','Cocoa knit']),('beret','Accessories',['Rose beret','Cloud beret','Lavender beret','Amber beret','Mint beret','Mocha beret']),('crown','Accessories',['Rose crown','Pearl crown','Amethyst crown','Honey crown','Emerald crown','Copper crown']),('star','Curios',['Rose star','Cloud star','Twilight star','Honey star','Mint star','Bronze star']),('moon','Curios',['Rose moon','Pearl moon','Lilac moon','Golden moon','Sage moon','Cocoa moon']),('cloud','Curios',['Pink cloud','Little cloud','Twilight cloud','Sunset cloud','Mint cloud','Rain cloud']),('rainbow','Curios',['Peach rainbow','Cloud rainbow','Lilac rainbow','Honey rainbow','Mint rainbow','Dusk rainbow']),('bird','Animals',['Peach chick','Snow chick','Lilac chick','Honey chick','Mint chick','Mocha chick']),('butterfly','Animals',['Rose butterfly','Pearl butterfly','Lilac butterfly','Amber butterfly','Mint butterfly','Dusk butterfly'])]
colors=['F6A9B8','F5E5C3','B6A2DE','EDC26B','A9CBA0','BDA18C']
legacy={'leaf':[], 'flower':['Daisy'], 'bow':['Rose ribbon'], 'beanie':['Lilac knit'], 'crown':['Honey crown'], 'star':['Honey star']}
items=[]
# 114 new Season 1 designs + six legacy items = 120.
for kind,category,names in styles:
    for i,name in enumerate(names):
        if name in legacy.get(kind,[]): continue
        items.append(dict(id='free.s1.'+kind+'.'+str(i),name=name,rarity=['Common','Common','Uncommon','Rare','Epic','Legendary'][i],weight=[70,70,35,20,8,2][i],category=category,season='season1',kind=kind,color=colors[i]))
# Exclude one extra leaf so the first season contains exactly 120 including legacy.
items=[p for p in items if p['id']!='free.s1.leaf.5']
for kind,category,names in styles[:18]:
    for i,name in enumerate(names):
        items.append(dict(id='free.s2.'+kind+'.'+str(i),name=['Dewdrop','Daydream','Starlight','Sunbeam','Meadow','Moonlit'][i]+' '+name.lower(),rarity=['Common','Common','Uncommon','Rare','Epic','Legendary'][i],weight=[70,70,35,20,8,2][i],category=category,season='season2',kind=kind,color=colors[(i+2)%6]))
assert len(items)==222 and sum(p['season']=='season2' for p in items)==108
payload=dict(version=1,items=items,lines=['One tiny step, then a little rest.','Your next good idea might be one sip away.','I’m cheering for you, paws and all.','You and me? A pretty good team.','Small wins deserve soft landings.','Let’s hop into the next little thing.','A gentler pace is still progress.','Thanks for keeping me company.'])
(ROOT/'macos/Resources/Library/catalog.json').write_text(json.dumps(payload,indent=2)+'\n')
print('Baked 222 new vector wearables + six legacy items; 108 Season 2 items.')
