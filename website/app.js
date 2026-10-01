"use strict";

const $ = id => document.getElementById(id);
const spriteViews = [$("hero-sprite"), $("stage-sprite"), $("corner-sprite")];
const hatViews = [$("hero-hat"), $("stage-hat"), $("corner-hat")];
const stage = $("pet-stage"), figure = $("pet-figure");
const prefersReducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const STORAGE_KEY = "pawsync.preview.v2";
let saved = {};
try { saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}"); } catch {}

let pets = [], activePet = null, activeHat = saved.hat || "none";
let activeScene = saved.scene || "cream", size = Math.min(180, Math.max(40, Number(saved.size) || 100));
let frameTimer, actionTimer, bubbleTimer, walkAnimation, dragStart, currentRow = 0, currentColumn = 0;

const accessories = [
  {id:"none",name:"No accessory",kind:"free",svg:""},
  {id:"sprout",name:"Sprout",kind:"free",svg:'<path d="M50 62V31" stroke="#5b8b59" stroke-width="5" fill="none" stroke-linecap="round"/><path d="M49 39C18 44 19 11 23 13c24-4 32 8 26 26Z" fill="#a4cc80" stroke="#62875b" stroke-width="2"/><path d="M52 32C48 8 75 6 79 12c-2 20-14 27-27 20Z" fill="#c4dda0" stroke="#62875b" stroke-width="2"/>'},
  {id:"bow",name:"Peach bow",kind:"free",svg:'<path d="M47 31C5 3 8 75 46 48l10 0c40 30 40-45 0-17Z" fill="#f49bb4" stroke="#b86483" stroke-width="3"/><ellipse cx="51" cy="40" rx="9" ry="12" fill="#e47498" stroke="#b86483" stroke-width="3"/><path d="M25 26h12M63 26h12" stroke="#ffdbe4" stroke-width="4" stroke-linecap="round"/>'},
  {id:"beanie",name:"Beanie",kind:"free",svg:'<path d="M18 50C14 1 85 1 82 50Z" fill="#b4a0cb" stroke="#816d9d" stroke-width="3"/><rect x="13" y="44" width="74" height="17" rx="6" fill="#d5c2e3" stroke="#816d9d" stroke-width="3"/><circle cx="50" cy="9" r="9" fill="#edc0d1" stroke="#816d9d" stroke-width="2"/>'},
  {id:"flower",name:"Daisy",kind:"free",svg:'<g fill="#fff9e9" stroke="#d5bf9e" stroke-width="2"><ellipse cx="50" cy="25" rx="10" ry="17"/><ellipse cx="50" cy="55" rx="10" ry="17"/><ellipse cx="35" cy="40" rx="17" ry="10"/><ellipse cx="65" cy="40" rx="17" ry="10"/><ellipse cx="39" cy="29" rx="10" ry="13" transform="rotate(-45 39 29)"/><ellipse cx="61" cy="51" rx="10" ry="13" transform="rotate(-45 61 51)"/></g><circle cx="50" cy="40" r="12" fill="#f0bf70" stroke="#c69a55" stroke-width="2"/>'},
  {id:"star",name:"Star",kind:"free",svg:'<path d="m50 7 9 20 22 3-16 16 4 23-19-11-20 11 4-23-16-16 22-3Z" fill="#f7cf68" stroke="#b68749" stroke-width="3" stroke-linejoin="round"/><path d="m44 25 3-6" stroke="#fff9db" stroke-width="5" stroke-linecap="round"/>'},
  {id:"crown",name:"Crown",kind:"free",svg:'<path d="m15 58-6-37 23 16L50 12l18 25 24-16-8 37Z" fill="#f5c56d" stroke="#ae8146" stroke-width="3" stroke-linejoin="round"/><path d="M15 60h68" stroke="#b18449" stroke-width="5"/><circle cx="50" cy="48" r="4" fill="#eb86a4"/><circle cx="25" cy="47" r="3" fill="#96c8d6"/><circle cx="74" cy="47" r="3" fill="#96c8d6"/>'},
  {id:"top-hat",name:"Top hat",kind:"paid",svg:'<ellipse cx="50" cy="59" rx="42" ry="9" fill="#493c52" stroke="#342d42" stroke-width="3"/><rect x="26" y="15" width="48" height="43" rx="6" fill="#493c52" stroke="#342d42" stroke-width="3"/><path d="M27 47h46" stroke="#ba96c7" stroke-width="10"/><path d="M37 20v17" stroke="#ffffff44" stroke-width="5" stroke-linecap="round"/>'},
  {id:"glasses",name:"Glasses",kind:"paid",svg:'<g fill="#deedf0" fill-opacity=".16" stroke="#795c66" stroke-width="4"><rect x="7" y="29" width="38" height="28" rx="11"/><rect x="55" y="29" width="38" height="28" rx="11"/></g><path d="M45 39q5-4 10 0M6 38-2 34M94 38l8-4" fill="none" stroke="#795c66" stroke-width="4" stroke-linecap="round"/>'},
  {id:"headphones",name:"Headphones",kind:"system",svg:'<path d="M20 57V39a30 30 0 0 1 60 0v18" stroke="#8e76a5" stroke-width="11" fill="none"/><rect x="11" y="38" width="18" height="31" rx="8" fill="#b18dc7" stroke="#715b84" stroke-width="3"/><rect x="71" y="38" width="18" height="31" rx="8" fill="#b18dc7" stroke="#715b84" stroke-width="3"/>'}
];

const hatSVG = hat => hat?.svg ? `<svg viewBox="0 0 100 80" aria-hidden="true">${hat.svg}</svg>` : "";
function currentAccessory() { return accessories.find(item => item.id === activeHat) || accessories[0]; }
function saveChoice() { try { localStorage.setItem(STORAGE_KEY, JSON.stringify({pet:activePet?.id,hat:activeHat,scene:activeScene,size})); } catch {} }

function fitForFrame() {
  if (!activePet) return {x:0,y:170,scale:1};
  const id = activePet.id;
  const originals = {
    "pixel-cat":[171,1.12,151],shibe:[170,1.16,153],fox:[171,1.1,154],
    bunny:[170,.96,151],bear:[172,1.1,164],panda:[172,1.12,164],
    hamster:[171,1.14,151],otter:[171,1.12,153],capybara:[172,1.13,153]
  };
  const imported = {
    "openpets-default":[-5,176,.98],"openpets-snoopy":[-18,170,1.05],
    "openpets-clippit":[-22,150,.7],"openpets-tux":[-4,177,1.05],
    "openpets-wall-e":[-4,184,.78],"openpets-dobby":[0,174,1.04]
  };
  let x=0,y=170,scale=1;
  if (originals[id]) {
    [y,scale] = originals[id];
    if (currentRow === 1) {x=38;y=originals[id][2];}
    if (currentRow === 2) {x=-38;y=originals[id][2];}
    if (currentRow === 4) {x=currentColumn===0?-31:-10;y=currentColumn===0?120:currentColumn<4?190:175;}
    if (currentRow === 5) {x=-28;y=125;}
    if (id === "bunny" && ["beanie","crown","top-hat"].includes(activeHat)) y -= 15;
  } else if (imported[id]) {
    [x,y,scale] = imported[id];
    if (currentRow === 4 && id === "openpets-default") y=155;
  }
  return {x,y,scale};
}

function positionHats() {
  const hat = currentAccessory();
  const visible = currentRow === 3 && document.body.classList.contains("dancing") ? accessories.at(-1) : hat;
  const fit = fitForFrame();
  let left = 120 + fit.x - 43, top = 236 - fit.y - 53;
  if (visible.id === "glasses") top += 37;
  if (visible.id === "headphones") top += 15;
  for (const view of hatViews) {
    view.innerHTML = hatSVG(visible);
    view.style.left = `${left}px`;
    view.style.top = `${top}px`;
    view.style.transform = `scale(${fit.scale})`;
  }
}

function showFrame(row=0,column=0) {
  currentRow=row; currentColumn=column;
  for (const view of spriteViews) view.style.backgroundPosition=`-${column*192}px -${row*208}px`;
  positionHats();
}
function showPet(pet,announce=true) {
  if (!pet) return;
  stopAction(); activePet=pet;
  for (const view of spriteViews) {
    view.style.backgroundImage=`url("${pet.sheet}")`;
    view.style.backgroundSize=`1536px ${pet.rows*208}px`;
    view.style.imageRendering=pet.group==="OpenPets"&&pet.id!=="openpets-default"?"pixelated":"auto";
  }
  $("pet-name").textContent=pet.name;
  $("pet-origin").textContent=pet.group==="PawSync"?"PawSync original":"Bundled OpenPets companion";
  $("corner-pet").setAttribute("aria-label",`Wave to ${pet.name}`);
  document.querySelectorAll(".pet-card").forEach(button=>button.setAttribute("aria-pressed",String(button.dataset.pet===pet.id)));
  showFrame(0,pet.idleColumn);
  saveChoice();
  if (announce) say(`Hi! I'm ${pet.name.split(" the ")[0]}. ♡`);
}

function say(message,duration=3400) {
  clearTimeout(bubbleTimer);
  $("speech-text").textContent=message;
  $("speech").hidden=false;
  $("corner-bubble").textContent=message;
  bubbleTimer=setTimeout(()=>{$("speech").hidden=true;$("corner-bubble").textContent="Click for a hello ♡";},duration);
}
function stopAction() {
  clearInterval(frameTimer); clearTimeout(actionTimer);
  frameTimer=null; actionTimer=null;
  walkAnimation?.cancel(); walkAnimation=null;
  figure.style.left="50%";
  document.body.classList.remove("dancing");
  if (activePet) showFrame(0,activePet.idleColumn);
}
function play(action) {
  if (!activePet) return;
  stopAction();
  const clips={wave:[3,4,700,1050],jump:[4,5,840,1020],work:[7,6,820,850],nap:[5,1,900,3000],dance:[3,4,700,3600],pet:[8,6,1030,1350],walk:[1,8,1060,1850]};
  const clip=clips[action]||clips.wave;
  const messages={wave:"Oh, hi! I'm glad you're here. ♡",jump:"Look at me go!",work:"Tiny paws, big focus.",nap:"Just a little snooze… z z z",dance:"A happy dance just for you! ♫",pet:"More pats, please. ♡",walk:"A tiny adventure!"};
  say(messages[action]||messages.wave);
  if (action==="dance") document.body.classList.add("dancing");
  if (action==="walk"&&!prefersReducedMotion) {
    walkAnimation=figure.animate([{left:"50%"},{left:"65%"}],{duration:clip[3],easing:"ease-in-out",fill:"forwards"});
  }
  showFrame(clip[0],0);
  if (!prefersReducedMotion && clip[1]>1) {
    const started=performance.now();
    frameTimer=setInterval(()=>{
      const elapsed=performance.now()-started;
      const column=Math.floor((elapsed%clip[2])/(clip[2]/clip[1]));
      showFrame(clip[0],Math.min(clip[1]-1,column));
    },Math.max(75,clip[2]/clip[1]));
  }
  actionTimer=setTimeout(stopAction,clip[3]);
}

function renderPets() {
  const grid=$("pet-grid"); grid.replaceChildren();
  for (const pet of pets) {
    const button=document.createElement("button");
    button.type="button"; button.className="pet-card"; button.dataset.pet=pet.id; button.dataset.group=pet.group;
    button.setAttribute("aria-label",`Choose ${pet.name}`);
    button.setAttribute("aria-pressed",String(activePet?.id===pet.id));
    const image=document.createElement("img"); image.src=pet.thumbnail; image.alt="";
    const name=document.createElement("strong"); name.textContent=pet.name.split(" the ")[0];
    const group=document.createElement("span"); group.textContent=pet.group;
    button.append(image,name,group);
    button.addEventListener("click",()=>showPet(pet));
    grid.append(button);
  }
}
function renderAccessories() {
  const grid=$("accessory-grid"); grid.replaceChildren();
  for (const item of accessories.filter(item=>item.kind!=="system")) {
    const button=document.createElement("button");button.type="button";button.className="accessory-card";
    button.dataset.hat=item.id;button.setAttribute("aria-label",`${item.name}${item.kind==="paid"?", paid item preview":""}`);
    button.setAttribute("aria-pressed",String(activeHat===item.id));
    button.innerHTML=item.id==="none"?'<span class="none-icon" aria-hidden="true"></span>':hatSVG(item);
    const label=document.createElement("span");label.textContent=item.name;button.append(label);
    button.addEventListener("click",()=>{
      activeHat=item.id;
      document.querySelectorAll(".accessory-card").forEach(card=>card.setAttribute("aria-pressed",String(card.dataset.hat===item.id)));
      positionHats(); saveChoice();
      say(item.id==="none"?"Back to my beautiful bare ears. ♡":`${item.name}? I love it!`);
    });
    grid.append(button);
  }
}
function selectScene(scene) {
  if (!["cream","lavender","mint","sky"].includes(scene)) scene="cream";
  activeScene=scene;stage.className=`pet-stage scene-${scene}`;
  document.querySelectorAll("[data-scene]").forEach(button=>button.setAttribute("aria-pressed",String(button.dataset.scene===scene)));
  saveChoice();
}
function selectSize(value) {
  size=Math.min(180,Math.max(40,Number(value)||100));
  figure.style.setProperty("--pet-scale",String(size/100));
  $("pet-size").value=String(size);$("size-output").textContent=`${size}%`;saveChoice();
}

document.querySelectorAll("[data-filter]").forEach(button=>button.addEventListener("click",()=>{
  const filter=button.dataset.filter;
  document.querySelectorAll("[data-filter]").forEach(item=>item.setAttribute("aria-pressed",String(item===button)));
  document.querySelectorAll(".pet-card").forEach(card=>card.hidden=filter!=="All"&&card.dataset.group!==filter);
}));
document.querySelectorAll("[data-scene]").forEach(button=>button.addEventListener("click",()=>selectScene(button.dataset.scene)));
document.querySelectorAll("[data-action]").forEach(button=>button.addEventListener("click",()=>play(button.dataset.action)));
$("pet-size").addEventListener("input",event=>selectSize(event.target.value));
$("dismiss-speech").addEventListener("click",()=>{$("speech").hidden=true;});
$("corner-pet").addEventListener("click",()=>play("wave"));
figure.addEventListener("pointerdown",event=>{if(event.button!==0)return;dragStart={x:event.clientX,y:event.clientY,moved:false};figure.setPointerCapture(event.pointerId);});
figure.addEventListener("pointermove",event=>{if(!dragStart)return;if(Math.hypot(event.clientX-dragStart.x,event.clientY-dragStart.y)>7)dragStart.moved=true;});
figure.addEventListener("pointerup",()=>{if(!dragStart)return;const moved=dragStart.moved;dragStart=null;play(moved?"pet":"wave");});
figure.addEventListener("pointercancel",()=>{dragStart=null;});
// Binary trigger only: this preview never reads or stores key contents.
document.addEventListener("keydown",event=>{if(document.hidden||!activePet||(event.target instanceof Element&&event.target.closest("input,textarea,button,a")))return;play("work");});
$("copy-app-path").addEventListener("click",async()=>{try{await navigator.clipboard.writeText($("app-path").textContent);$("copy-status").textContent="Copied!";}catch{$("copy-status").textContent="Select and copy the path above.";}});
document.addEventListener("visibilitychange",()=>{if(document.hidden)stopAction();});

function updateCorner() {
  const hero=$("top").getBoundingClientRect(),studio=$("customize").getBoundingClientRect();
  const heroVisible=hero.bottom>96&&hero.top<innerHeight*.88;
  const studioVisible=studio.bottom>96&&studio.top<innerHeight*.55;
  document.body.classList.toggle("show-corner",!heroVisible&&!studioVisible);
}
addEventListener("scroll",updateCorner,{passive:true});
addEventListener("resize",updateCorner);
requestAnimationFrame(updateCorner);

renderAccessories(); selectScene(activeScene); selectSize(size);
fetch("assets/catalog.json",{cache:"no-store"}).then(response=>{if(!response.ok)throw Error("Pet catalog unavailable");return response.json();}).then(catalog=>{
  pets=catalog;renderPets();
  showPet(pets.find(pet=>pet.id===saved.pet)||pets.find(pet=>pet.id==="shibe")||pets[0],false);
}).catch(()=>{$("pet-name").textContent="Pet preview could not load";$("pet-origin").textContent="Reload this page to try again.";});
