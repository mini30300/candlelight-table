const fs=require('fs');
const s=fs.readFileSync(require('path').join(__dirname,'..','app','src','main','assets','battle-table.html'),'utf8');
const a=s.indexOf('// ==MODULES-BEGIN=='), b=s.indexOf('// ==MODULES-END==');
const R=new Function(s.slice(a,b)+';return SKRIG;')();
const DT=1/60;
function scen(list, label){
  const c=new R.Controller(); let sync=0, n=0, slide=0, air=0, nm=0, minSep=9;
  const anc={};
  for (const [m,secs] of list){ c.set(m);
    for (let i=0;i<Math.round(secs/DT);i++){
      const P=c.step(DT), W=R.fk(P);
      const dz = Math.abs(W.ankleL.p[2]-W.ankleR.p[2]);
      if (m!=='attack' && c.v>0.5){ nm++; if (dz < 0.06) sync++; minSep = Math.min(minSep, dz);
        if (!P.contact.L && !P.contact.R) air++; }
      for (const Sd of ['L','R']){ const cc=P.contact[Sd], pts = cc==='heel'?['heel']:cc==='ball'?['toe']:cc==='flat'?['heel','toe']:[];
        for (const k of ['heel','toe']){ const key=k+Sd; if(!pts.includes(k)){ delete anc[key]; continue; }
          const g=[W[key].p[0], W[key].p[2]+c.travel]; if(!anc[key]) anc[key]=g; else slide=Math.max(slide, Math.hypot(g[0]-anc[key][0], g[1]-anc[key][1])); } }
      n++;
    } }
  console.log(label.padEnd(26), 'legs-in-sync', nm?(100*sync/nm).toFixed(1).padStart(5)+'%':'   -',
    '| min |zL-zR|', minSep.toFixed(3), '| airborne', nm?(100*air/nm).toFixed(1)+'%':'-', '| slide', (slide*1000).toFixed(2), 'mm');
}
scen([['run',4]], 'steady run');
scen([['walk',4]], 'steady walk');
scen([['idle',1.2],['attack',1.6],['run',3.5]], 'attack -> run');
scen([['idle',1.2],['attack',1.6],['walk',3.5]], 'attack -> walk');
scen([['run',1.5],['attack',2.2],['run',3]], 'run -> attack -> run');
scen([['idle',1],['walk',1.5],['run',1.5],['walk',1.5],['idle',1.5]], 'idle>walk>run>walk>idle');
scen([['walk',1],['idle',0.05],['walk',0.05],['idle',0.05],['walk',2.5]], 'mash 0.05s');
scen([['run',1],['idle',0.1],['run',0.1],['idle',0.1],['run',2.5]], 'mash run/idle');
