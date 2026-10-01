import {spawn} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';

const chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const base='http://127.0.0.1:8767/website/';
const port=9234;
const browser=spawn(chrome,[
  '--headless','--disable-gpu','--disable-background-networking','--disable-extensions',
  '--no-first-run','--no-default-browser-check','--remote-allow-origins=*',
  `--remote-debugging-port=${port}`,'--user-data-dir=/tmp/pawsync-website-cdp','about:blank'
],{stdio:'ignore'});
let socket;
try {
  let target;
  for(let attempt=0;attempt<80;attempt++){
    try { const tabs=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();target=tabs.find(tab=>tab.type==='page');if(target)break; } catch {}
    await delay(100);
  }
  if(!target)throw Error('Could not attach to headless Chrome');
  socket=new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
  let next=1;
  const pending=new Map(),errors=[];
  socket.addEventListener('message',event=>{
    const message=JSON.parse(event.data);
    if(message.method==='Runtime.exceptionThrown')errors.push(message.params.exceptionDetails.text);
    if(message.id&&pending.has(message.id)){
      const {resolve,reject}=pending.get(message.id);pending.delete(message.id);
      message.error?reject(Error(message.error.message)):resolve(message.result);
    }
  });
  function call(method,params={}){const id=next++;return new Promise((resolve,reject)=>{pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params}));});}
  await call('Page.enable');await call('Runtime.enable');
  await call('Page.navigate',{url:base});await delay(1500);
  await call('Runtime.evaluate',{expression:`localStorage.removeItem('pawsync.preview.v2')`});
  for(const [name,width,height,mobile] of [['desktop',1440,1000,false],['mobile',390,844,true]]){
    await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile});
    if(name==='desktop')await call('Page.reload',{ignoreCache:true});
    for(let attempt=0;attempt<40;attempt++){
      const ready=await call('Runtime.evaluate',{expression:`document.querySelectorAll('.pet-card img').length===15&&[...document.querySelectorAll('.pet-card img')].every(img=>img.complete&&img.naturalWidth>0)`,returnByValue:true});
      if(ready.result.value)break;
      await delay(200);
    }
    const result=await call('Runtime.evaluate',{expression:`({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,pets:document.querySelectorAll('.pet-card').length,features:document.querySelectorAll('.feature-card').length,thumbs:document.querySelectorAll('.pet-card img').length,brokenThumbs:[...document.querySelectorAll('.pet-card img')].filter(img=>!img.complete||img.naturalWidth===0).map(img=>({src:img.src,complete:img.complete,width:img.naturalWidth})),frame:getComputedStyle(document.querySelector('#stage-sprite')).backgroundImage,heroColumns:getComputedStyle(document.querySelector('.hero')).gridTemplateColumns,studioColumns:getComputedStyle(document.querySelector('.studio-layout')).gridTemplateColumns,favicon:document.querySelector('link[rel="icon"]')?.getAttribute('href')})`,returnByValue:true});
    const state=result.result.value;
    if(state.pets!==15||state.features!==3||state.thumbs!==15||state.brokenThumbs.length!==0||!state.frame.includes('shibe.webp')||state.favicon!=='assets/favicon.svg'||state.scrollWidth>state.width+1||(mobile&&(state.heroColumns.includes(' ')||state.studioColumns.includes(' '))))throw Error(`${name} layout failed: ${JSON.stringify(state)}`);
    const shot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
    await writeFile(`build/landing-${name}-verified.png`,Buffer.from(shot.data,'base64'));
    if(name==='desktop'){
      const full=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});
      await writeFile('build/landing-full-verified.png',Buffer.from(full.data,'base64'));
      await call('Runtime.evaluate',{expression:`document.querySelector('#features').scrollIntoView({behavior:'instant',block:'start'})`});
      await delay(180);
      const corner=await call('Runtime.evaluate',{expression:`({shown:document.body.classList.contains('show-corner'),display:getComputedStyle(document.querySelector('#corner-buddy')).display,scrollY,hero:document.querySelector('#top').getBoundingClientRect().toJSON(),studio:document.querySelector('#customize').getBoundingClientRect().toJSON()})`,returnByValue:true});
      if(!corner.result.value.shown||corner.result.value.display==='none')throw Error(`The corner pet did not appear after the hero: ${JSON.stringify(corner.result.value)}`);
      const cornerShot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
      await writeFile('build/landing-corner-preview.png',Buffer.from(cornerShot.data,'base64'));
    }
    console.log(`${name}: ${state.width}px viewport, ${state.pets} bundled pets, ${state.features} feature cards, no horizontal overflow`);
  }
  const interaction=await call('Runtime.evaluate',{expression:`(()=>{
    document.querySelector('[data-filter="OpenPets"]').click();
    const filtered=[...document.querySelectorAll('.pet-card')].filter(card=>!card.hidden).length===6;
    document.querySelector('[data-pet="openpets-default"]').click();
    document.querySelector('[data-hat="beanie"]').click();
    const size=document.querySelector('#pet-size');size.value='140';size.dispatchEvent(new Event('input',{bubbles:true}));
    document.querySelector('[data-scene="lavender"]').click();
    document.querySelector('[data-action="jump"]').click();
    const checks={filtered,pet:document.querySelector('#pet-name').textContent==='OpenPets Buddy',
      hat:document.querySelector('.accessory-card[data-hat="beanie"]').getAttribute('aria-pressed')==='true',
      size:document.querySelector('#size-output').textContent==='140%',
      scene:document.querySelector('#pet-stage').classList.contains('scene-lavender'),
      frame:getComputedStyle(document.querySelector('#stage-sprite')).backgroundImage.includes('openpets-default.webp'),
      art:document.querySelector('#stage-hat svg')!==null,
      jump:document.querySelector('#stage-sprite').style.backgroundPosition.includes('-832px')};
    return {checks};
  })()`,returnByValue:true});
  if(!Object.values(interaction.result.value.checks).every(Boolean))throw Error(`Interactive preview failed: ${JSON.stringify(interaction.result.value)}`);
  await call('Runtime.evaluate',{expression:`document.querySelector('#pet-stage').scrollIntoView({behavior:'instant',block:'center'})`});
  await delay(150);
  const bubble=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
  await writeFile('build/landing-bubbly-message.png',Buffer.from(bubble.data,'base64'));
  await call('Runtime.evaluate',{expression:`document.querySelector('#speech').hidden=true;document.querySelector('#pet-stage').scrollIntoView({behavior:'instant',block:'center'})`});
  await delay(150);
  const dressed=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
  await writeFile('build/landing-wardrobe-preview.png',Buffer.from(dressed.data,'base64'));
  const removal=await call('Runtime.evaluate',{expression:`(()=>{document.querySelector('[data-hat="none"]').click();return document.querySelector('#stage-hat').children.length===0;})()`,returnByValue:true});
  if(!removal.result.value)throw Error('Wardrobe removal failed');
  for(const id of ['default','snoopy','clippit','tux','wall-e','dobby']){
    await call('Runtime.evaluate',{expression:`(()=>{document.querySelector('[data-pet="openpets-${id}"]').click();document.querySelector('[data-hat="beanie"]').click();const size=document.querySelector('#pet-size');size.value='100';size.dispatchEvent(new Event('input',{bubbles:true}));document.querySelector('[data-action="jump"]').click();document.querySelector('#speech').hidden=true;document.querySelector('#pet-stage').scrollIntoView({behavior:'instant',block:'center'});})()`});
    await delay(220);
    const proof=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
    await writeFile(`build/landing-openpets-${id}.png`,Buffer.from(proof.data,'base64'));
  }
  console.log('Interactive studio: OpenPets filter and selection, accessory fitting/removal, size, scene, and jump passed');
  if(errors.length)throw Error(`Browser exceptions: ${errors.join('; ')}`);
} finally {
  socket?.close();browser.kill('SIGTERM');
}
