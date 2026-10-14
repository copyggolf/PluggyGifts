export function createShuffle(count,random=Math.random){
 const slots=Array.from({length:count},(_,i)=>i);const target=Math.min(count-1,Math.floor(random()*count));
 return {count,slots,target,phase:'reveal',elapsed:0,completed:0,pair:null,answered:false};
}
export function beginSwap(state,random=Math.random){
 const a=Math.min(state.count-1,Math.floor(random()*state.count));
 const offset=1+Math.min(state.count-2,Math.floor(random()*(state.count-1)));
 const b=(a+offset)%state.count;
 state.pair={a,b,fromA:state.slots[a],fromB:state.slots[b]};state.elapsed=0;state.phase='swapping';return state.pair;
}
export function settleSwap(state){if(!state.pair)return;const {a,b}=state.pair;[state.slots[a],state.slots[b]]=[state.slots[b],state.slots[a]];state.pair=null;state.completed++;state.elapsed=0;state.phase='between';}
export function chooseBox(state,id){if(state.phase!=='choose'||state.answered||!Number.isInteger(id)||id<0||id>=state.count)return null;state.answered=true;state.phase='answer';state.elapsed=0;return {correct:id===state.target,delta:id===state.target?400:-160,target:state.target,slot:state.slots[state.target]};}

export function shuffleLayout(count,width,height){
 const cols=width<550?Math.min(count,4):count,rows=Math.ceil(count/cols);
 const size=Math.min(width<550?88:116,(width-30)/cols-5),slots=[];
 for(let r=0;r<rows;r++){
  const n=Math.min(cols,count-r*cols),gap=size+8,start=(width-(n*gap-8))/2;
  for(let c=0;c<n;c++)slots.push({x:start+c*gap,y:Math.min(height*(rows===1?.57:.44),height-(rows*size+(rows-1)*35+25)-14)+r*(size+35)});
 }
 return {size,slots};
}
