// Original vector illustrations; independent of device emoji fonts.
export const appliances=[
['ทีวี','<rect x="10" y="13" width="60" height="43" rx="6" fill="#6254aa"/><rect x="15" y="18" width="50" height="31" rx="3" fill="#acdfea"/><path d="M26 65h28M40 56v9"/><path d="m20 39 12-12 10 10 17-12" stroke="#fff"/>'],
['ตู้เย็น','<rect x="21" y="6" width="38" height="66" rx="7" fill="#a2ded7"/><path d="M21 31h38M29 16v7M29 40v14"/><path d="M27 72v3M53 72v3"/>'],
['เครื่องเล่นเกม','<path d="M19 25h42c12 0 18 31 8 34-7 3-13-12-20-12H31c-7 0-13 15-20 12-10-3-4-34 8-34Z" fill="#ac99e5"/><path d="M21 31v17M13 39h16"/><circle cx="58" cy="35" r="4" fill="#ffb144"/><circle cx="64" cy="43" r="4" fill="#ee717f"/>'],
['มือถือ','<rect x="23" y="5" width="34" height="70" rx="8" fill="#7960b5"/><rect x="27" y="14" width="26" height="49" rx="3" fill="#ffd286"/><path d="M35 10h10"/><circle cx="40" cy="69" r="2" fill="#fff"/>'],
['เครื่องซักผ้า','<rect x="15" y="7" width="50" height="66" rx="7" fill="#9fcbec"/><path d="M15 22h50"/><circle cx="40" cy="46" r="18" fill="#6e69b6"/><circle cx="40" cy="46" r="12" fill="#cceefa"/><path d="M29 48q11-9 22 0" stroke="#7abacc"/><circle cx="55" cy="15" r="3" fill="#fff"/>'],
['เตารีด','<path d="M12 58 32 32h27l10 26Z" fill="#ef9eae"/><path d="M29 32v-9q0-12 16-12h12v21M10 64h61" fill="none"/><path d="M68 52q13-8 2-21"/>'],
['เครื่องเสียง','<rect x="6" y="18" width="68" height="46" rx="6" fill="#b9a8e8"/><circle cx="21" cy="43" r="11" fill="#635497"/><circle cx="59" cy="43" r="11" fill="#635497"/><rect x="34" y="29" width="12" height="15" rx="2" fill="#fae5ad"/><path d="M34 50h12"/>'],
['หูฟัง','<path d="M14 45V34a26 26 0 0 1 52 0v11" fill="none" stroke="#6954b4" stroke-width="9"/><rect x="9" y="36" width="17" height="30" rx="8" fill="#ffad85"/><rect x="54" y="36" width="17" height="30" rx="8" fill="#ffad85"/>'],
['หม้ออบลมร้อน','<rect x="17" y="9" width="46" height="62" rx="15" fill="#c8b1e8"/><path d="M17 35h46"/><rect x="26" y="18" width="28" height="10" rx="4" fill="#ffe6a5"/><path d="M34 46h12v14H34Z" fill="#7c62ae"/>'],
['ที่ม้วนผม','<path d="m22 63 28-40" stroke="#e3a7c7" stroke-width="15"/><path d="m48 23 12-17" stroke="#9c93ac" stroke-width="11"/><path d="M17 69q-12 4-7-10"/><path d="m39 30 8 5"/>'],
['ที่หนีบผม','<path d="m22 69 6-57M22 69l33-47" stroke="#b399df" stroke-width="12"/><path d="m28 14-4 31m30-21-18 26" stroke="#f1c8e2" stroke-width="6"/><path d="M22 72v6"/>'],
['พัดลม','<circle cx="40" cy="30" r="25" fill="#ade0dc"/><path d="M40 55v14M25 72h30" stroke-width="6"/><path d="M40 30q-15-28-18-6t18 6q30-12 16-23t-16 23q-3 32 13 22t-13-22" fill="#78c9c1"/><circle cx="40" cy="30" r="5" fill="#ffe6b4"/>'],
['แอร์','<rect x="5" y="16" width="70" height="32" rx="8" fill="#c2dcec"/><path d="M10 38h60M25 54v10M40 54v15M55 54v10" stroke="#89b9ca"/><circle cx="64" cy="24" r="2" fill="#7faac3"/>']
].map(([name,body],i)=>{const image=new Image();image.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 80 80"><g stroke="#564165" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">${body}</g></svg>`);return {name,image,id:i}});
