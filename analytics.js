import {backend} from './config.js?v=5';
export const configured=Boolean(backend.url&&backend.publishableKey);
export async function api(path,body,token){const r=await fetch(backend.url.replace(/\/$/,'')+path,{method:'POST',headers:{'Content-Type':'application/json',apikey:backend.publishableKey,...((token||backend.publishableKey.startsWith('eyJ'))?{Authorization:'Bearer '+(token||backend.publishableKey)}:{})},body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw new Error(data.message||data.error_description||'เชื่อมระบบสถิติไม่สำเร็จ');return data}
const storage=(area,key,fallback)=>{try{let v=area.getItem(key);if(!v){v=fallback();area.setItem(key,v)}return v}catch{return fallback()}};
export class Analytics{
 constructor(){this.name='';this.game=null;this.playing=false;this.run=null;this.visitor=storage(localStorage,'pluggy-visitor',()=>crypto.randomUUID());this.visit=storage(sessionStorage,'pluggy-visit',()=>crypto.randomUUID());this.secret=storage(sessionStorage,'pluggy-visit-secret',()=>crypto.randomUUID());this.queue=[];try{this.queue=JSON.parse(localStorage.getItem('pluggy-pending')||'[]')}catch{}this.busy=false;this.timer=null;this.status=configured?'connecting':'disabled'}
 start(){if(!configured)return;this.beat();this.timer=setInterval(()=>this.beat(),20000);document.addEventListener('visibilitychange',()=>this.beat());window.addEventListener('online',()=>this.beat());window.addEventListener('pagehide',()=>this.beat(true))}
 async beat(leaving=false){if(!configured||this.busy)return;this.busy=true;try{await api('/rest/v1/rpc/pluggy_touch',{p_visit:this.visit,p_secret:this.secret,p_visitor:this.visitor,p_name:this.name,p_game:this.game,p_playing:this.playing&&!document.hidden&&!leaving,p_visible:!document.hidden&&!leaving,p_device:matchMedia('(max-width:720px)').matches?'mobile':'desktop'});this.status='connected';await this.flush()}catch{this.status='offline'}finally{this.busy=false}}
 setPlayer(name){this.name=name;this.beat()}
 begin(game){this.game=game;this.run=crypto.randomUUID();this.playing=false;this.beat();return this.run}
 activity(playing){this.playing=playing;this.beat()}
 end(){this.game=null;this.playing=false;this.beat()}
 finish(game,score,rounds){if(configured){this.queue.push({visitor:this.visitor,device:matchMedia('(max-width:720px)').matches?'mobile':'desktop',p_run:this.run,p_visit:this.visit,p_secret:this.secret,p_name:this.name,p_game:game,p_score:score,p_rounds:rounds});this.queue=this.queue.slice(-30);this.persist()}this.end()}
 persist(){try{localStorage.setItem('pluggy-pending',JSON.stringify(this.queue))}catch{}}
 async flush(){while(this.queue.length){const {visitor,device,...result}=this.queue[0];if(result.p_visit!==this.visit)await api('/rest/v1/rpc/pluggy_touch',{p_visit:result.p_visit,p_secret:result.p_secret,p_visitor:visitor,p_name:result.p_name,p_game:null,p_playing:false,p_visible:false,p_device:device});await api('/rest/v1/rpc/pluggy_result',result);this.queue.shift();this.persist()}}
}
