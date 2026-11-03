import {prepareMediaBundle} from './score-export.js?v=27';
export async function prepareResultMedia(scoreBlob,card){return prepareMediaBundle([{kind:'score',label:'คะแนน',filename:'Pluggy-'+String(card.score)+'-score.png',blob:scoreBlob}],card,{defaultKind:'score'})}
