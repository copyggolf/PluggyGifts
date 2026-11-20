import {api,configured} from './analytics.js?v=28';
import {games} from './game-config.js?v=28';
import {paths,images,ready} from './visuals.js?v=28';
import {displayFields,cleanDisplay,escapeText} from './display-schema.js?v=28';
const originals={paths:{...paths},games:JSON.parse(JSON.stringify(games))};
let documentConfig={},lastApply=0;
export const isDisplayPreview=()=>new URLSearchParams(location.search).get('display-preview')==='1'&&window.parent!==window;
export function displayValue(key,fallback=''){return Object.hasOwn(documentConfig,key)?documentConfig[key]:displayFields.find(f=>f.key===key)?.value||fallback}
export const displayText=(key,fallback='')=>escapeText(displayValue(key,fallback));
export function defaultValue(field){if(field.key.startsWith('game.')){const [,id,key]=field.key.split('.'),g=originals.games.find(g=>g.id===id);return key==='steps'?g.steps.join('\n'):key==='rules'?g.rules.replaceAll('<br>','\n'):g[key]||''}return field.value}
export function cachedDisplay(){try{return cleanDisplay(JSON.parse(localStorage.getItem('pluggy-display-cache')||'{}'))}catch{return {}}}
export async function fetchDisplay(){let old={};try{old=JSON.parse(localStorage.getItem('pluggy-display-cache')||'{}')}catch{}if(!configured)return old;let requestTimer;try{const data=await Promise.race([api('/rest/v1/rpc/pluggy_display_public',{}),new Promise((_,reject)=>{requestTimer=setTimeout(()=>reject(Error('timeout')),6000)})]);const doc=cleanDisplay(data?.document||{});try{localStorage.setItem('pluggy-display-cache',JSON.stringify(doc))}catch{}return doc}catch{try{return cleanDisplay(old)}catch{return {}}}finally{clearTimeout(requestTimer)}}
export async function applyDisplay(raw){const doc=cleanDisplay(raw),ticket=++lastApply;if(ticket!==lastApply)return;for(const [key,old,next] of [['home.playButton','เล่นภารกิจนี้ →','เริ่มเกม'],['home.nameLabel','พร้อมผจญภัย? บอกชื่อให้ปลั๊กกี้รู้จักหน่อย','ใส่ชื่อเล่นเพื่อรับคูปองส่วนลด'],['home.startButton','เริ่มผจญภัย →','เลือกเกมเลย']])if(doc[key]===old)doc[key]=next;documentConfig=doc;Object.assign(paths,originals.paths);for(let i=0;i<games.length;i++)Object.assign(games[i],originals.games[i]);
 paths.hero=displayValue('home.banner',originals.paths.hero)||originals.paths.hero;for(const key of ['catcher','hammer','guide','celebrate','appLogo'])paths[key]=displayValue('mascot.'+key,originals.paths[key])||originals.paths[key];
 for(const g of games)for(const key of ['name','thai','desc','cover','background','steps','rules']){const value=doc[`game.${g.id}.${key}`];if(value===undefined)continue;g[key]=key==='steps'?value.split('\n').filter(Boolean):key==='rules'?escapeText(value).replaceAll('\n','<br>'):value||originals.games.find(x=>x.id===g.id)[key]}
 for(const key of ['background','accent','panel'])document.documentElement.style.setProperty('--display-'+key,displayValue('theme.'+key));document.documentElement.style.setProperty('--display-cover-fit',displayValue('theme.coverFit'));document.documentElement.style.setProperty('--display-cover-position',displayValue('theme.coverPosition'));document.documentElement.style.setProperty('--display-bg-shade',+displayValue('theme.bgShade')/100);
 const brand=document.querySelector('.brand');if(brand){const im=brand.querySelector('img');im.src=displayValue('brand.icon')||'assets/festive/santa-icon.png';const span=brand.querySelector('span');if(span)span.innerHTML=`${displayText('brand.name')}<small>${displayText('brand.tagline')}</small>`}

}
export const previewAnalytics=()=>({queue:[],visitor:null,visit:null,secret:null,run:null,publicRank:false,start(){},end(){},activity(){},begin(){},finish(){},setPlayer(){},track(){}});
