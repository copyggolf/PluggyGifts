// Original procedural festive soundtrack; no external music licences or downloads.
const read=k=>{try{return JSON.parse(localStorage.getItem(k))??true}catch{return true}};
export class GameAudio{
 constructor(){this.music=read('pluggy-music');this.sfx=read('pluggy-sfx');this.ctx=null;this.timer=null;this.step=0;this.next=0;this.hidden=false;this.voices=new Set()}
 async unlock(){try{this.ctx??=new (window.AudioContext||window.webkitAudioContext)();await this.ctx.resume();if(this.music&&!this.hidden)this.schedule()}catch{}}
 tone(freq,time,duration,volume=.04,type='sine',channel='sfx'){
  if(!this.ctx||this.ctx.state!=='running')return;const o=this.ctx.createOscillator(),g=this.ctx.createGain();o.type=type;o.frequency.setValueAtTime(freq,time);g.gain.setValueAtTime(0,time);g.gain.linearRampToValueAtTime(volume,time+.008);g.gain.exponentialRampToValueAtTime(.0001,time+duration);o.connect(g);g.connect(this.ctx.destination);const v={o,g,channel};this.voices.add(v);o.onended=()=>{this.voices.delete(v);o.disconnect();g.disconnect()};o.start(time);o.stop(time+duration+.02)
 }
 schedule(){if(this.timer||!this.ctx||this.ctx.state!=='running')return;this.next=this.ctx.currentTime+.05;this.timer=setInterval(()=>{if(!this.music||this.hidden||this.ctx.state!=='running')return;if(this.next<this.ctx.currentTime-.3)this.next=this.ctx.currentTime+.02;while(this.next<this.ctx.currentTime+.16){this.note(this.step++,this.next);this.next+=.225}},50)}
 note(step,t){const tune=[72,76,79,76,74,77,81,77,72,76,79,84,81,79,76,74,69,72,76,72,71,74,79,74,72,76,79,76,74,71,72,null];const n=tune[step%32],hz=m=>440*2**((m-69)/12);if(n!==null){this.tone(hz(n),t,.32,.035,'sine','music');this.tone(hz(n+12),t,.12,.009,'sine','music')}if(step%4===0)this.tone(hz([48,53,45,55][Math.floor(step/8)%4]),t,.55,.03,'triangle','music')}
 stopMusic(){clearInterval(this.timer);this.timer=null;for(const v of this.voices)if(v.channel==='music'){try{v.o.stop()}catch{}}}
 toggle(channel){this[channel]=!this[channel];try{localStorage.setItem('pluggy-'+channel,JSON.stringify(this[channel]))}catch{}if(channel==='music'){this.stopMusic();if(this.music)this.unlock()}else if(this.sfx){this.unlock().then(()=>this.effect('good'))}return this[channel]}
 effect(kind='good'){if(!this.sfx||this.hidden||!this.ctx||this.ctx.state!=='running')return;const t=this.ctx.currentTime;if(kind==='bad'){this.tone(180,t,.2,.07,'sawtooth');this.tone(95,t+.08,.28,.06,'triangle')}else if(kind==='hit'){this.tone(110,t,.07,.1,'triangle');this.tone(880,t+.035,.18,.06);this.tone(1174,t+.08,.22,.04)}else if(kind==='bonus'||kind==='win'){[523,659,784,1047].forEach((f,i)=>this.tone(f,t+i*.09,.33,.055))}else if(kind==='shuffle'){this.tone(410,t,.055,.012,'triangle')}else{this.tone(784,t,.14,.045);this.tone(1047,t+.055,.18,.025)}}
 visibility(hidden){this.hidden=hidden;if(hidden)this.stopMusic();else if(this.music)this.unlock()}
}
