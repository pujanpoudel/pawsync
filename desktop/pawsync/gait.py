"""Bounded, on-demand walking cache using the same anatomical mesh as macOS."""
from __future__ import annotations
import json, math
from PIL import Image
from PySide6.QtGui import QImage
from .assets import RESOURCES

GAITS=json.loads((RESOURCES/'Locomotion/gaits.json').read_text())

def limb_motion(gait,limb,phase):
    t=(phase+limb['phase'])%1;swing=t>=.6;q=(t-.6)/.4 if swing else t/.6
    stride=-math.cos(q*math.pi) if swing else 1-2*q
    forward=stride*limb['stride']*gait['facing'];lift=math.sin(q*math.pi)*limb['lift'] if swing else 0
    wave=math.sin((phase+limb['phase'])*2*math.pi)
    if limb['role']=='arm':forward=wave*limb['stride'];lift=0
    if gait['kind']=='hop':forward=wave*limb['stride'];lift=max(0,wave)*limb['lift']
    if gait['kind'] in ('fly','swim'):forward=wave*limb['stride'];lift=wave*(9 if gait['kind']=='fly' else 3)
    px,py=limb['pivot'];tx,ty=limb['tip'];angle=forward/max(14,math.hypot(tx-px,ty-py))
    return math.cos(angle)-1,math.sin(angle),lift


def influence(limb,x,y):
    px,py=limb['pivot'];tx,ty=limb['tip'];rx=12 if limb['role']=='arm' else 10
    progress=max(0,min(1,(y-py)/max(10,ty-py)));center=px+(tx-px)*progress
    weight=math.exp(-((x-center)/rx)**2*.5)*progress*max(0,min(1,(ty+16-y)/16))
    return x-px,y-py,weight


def displacement(gait,x,y,phase):
    dx=dy=0.
    for limb in gait['limbs']:
        c,s,lift=limb_motion(gait,limb,phase);vx,vy,weight=influence(limb,x,y)
        dx+=(vx*c+vy*s)*weight;dy+=(-vx*s+vy*c-lift)*weight
    return dx,dy

class WalkingFrames:
    def __init__(self,pet):
        self.gait=GAITS.get(pet.id);self.cache={};self.basis=None
    def inverse_vertices(self,phase):
        points=[(x,y) for y in range(0,209,8) for x in range(0,193,8)]
        if self.basis is None:
            self.basis=[[influence(limb,x,y) for x,y in points] for limb in self.gait['limbs']]
        delta=[[0.,0.] for _ in points]
        for limb,basis in zip(self.gait['limbs'],self.basis):
            c,s,lift=limb_motion(self.gait,limb,phase)
            for result,(vx,vy,weight) in zip(delta,basis):
                result[0]+=(vx*c+vy*s)*weight;result[1]+=(-vx*s+vy*c-lift)*weight
        return {(x,y):(x-dx,y-dy) for (x,y),(dx,dy) in zip(points,delta)}
    @property
    def procedural(self):return self.gait is not None and self.gait['kind'] not in ('authored',)
    def frame(self,base,phase):
        index=int(phase*24)%24
        if index in self.cache:return self.cache[index]
        rgba=base.convertToFormat(QImage.Format_RGBA8888)
        source=Image.frombytes('RGBA',(192,208),bytes(rgba.constBits()))
        # Basis weights are cached once. Each frame only updates joint angles;
        # no per-frame Gaussian analysis or background rendering loop is needed.
        vertices=self.inverse_vertices(index/24)
        mesh=[]
        for y in range(0,208,8):
            for x in range(0,192,8):
                box=(x,y,min(192,x+8),min(208,y+8));a,b,c,d=box
                quad=(*vertices[a,b],*vertices[a,d],*vertices[c,d],*vertices[c,b]);mesh.append((box,quad))
        result=source.transform((192,208),Image.Transform.MESH,mesh,Image.Resampling.BICUBIC)
        image=QImage(result.tobytes(),192,208,192*4,QImage.Format_RGBA8888).copy()
        self.cache[index]=image
        return image
