const R=require('./harness.js');const DT=1/60;
function jointsOf(P){const W=R.fk(P);const o={};for(const k in W)o[k]=W[k].p;return o;}
function runSeq(seq,stopAt){const c=new R.Controller();let f=0;const out=[];for(const [mode,n] of seq){if(stopAt!==undefined&&f===stopAt)return {c,f};c.set(mode);for(let i=0;i<n;i++){if(stopAt!==undefined&&f===stopAt)return {c,f};const P=c.step(DT);out.push(P);f++;}}return {c,f,out};}
function scenario(seqS,label){const seq=seqS.map(([m,s])=>[m,Math.round(s/DT)]);
 // slide + flight
 const {c,out}=runSeq(seq);const anc={};let worst=[0,'',0],airW=0,nW=0,f=0;
 const c2=new R.Controller();let t=0;
 for(const [mode,n] of seq){c2.set(mode);for(let i=0;i<n;i++){const P=c2.step(DT);t+=DT;const W=R.fk(P);for(const S of ['L','R']){const cc=P.contact[S];const pts=cc==='heel'?['heel']:cc==='ball'?['toe']:cc==='flat'?['heel','toe']:[];for(const k of ['heel','toe']){const key=k+S;if(!pts.includes(k)){delete anc[key];continue;}const g=[W[key].p[0],W[key].p[2]+c2.travel];if(!anc[key])anc[key]=g;else{const d=Math.hypot(g[0]-anc[key][0],g[1]-anc[key][1]);if(d>worst[0])worst=[d,key+':'+cc,t.toFixed(2)];}}}
  if(c2.cur==='walk'&&!c2.settled&&c2.v>0.3){nW++;if(!P.contact.L&&!P.contact.R)airW++;}}}
 // tap kicks: deviation of the tapped frame from the untapped continuation
 let kick=[0,''];let fr=0;for(let k=1;k<seq.length;k++){fr+=seq[k-1][1];const A=runSeq(seq,fr).c;const PA=A.step(DT);/* untapped */const B=runSeq(seq,fr).c;B.set(seq[k][0]);const PB=B.step(DT);const ja=jointsOf(PA),jb=jointsOf(PB);for(const n in ja){const d=Math.hypot(...[0,1,2].map(j=>ja[n][j]-jb[n][j]));if(d>kick[0])kick=[d,n+'@'+seq[k][0]];}}
 // smoothness: max per-frame world joint move vs steady reference (walk 26 mm.. run 94) — report max joint dv (accel) in mm/frame^2
 let prev=null,pv=null,maxdv=[0,''];for(const P of out){const j=jointsOf(P);if(prev){const vel={};for(const n in j){vel[n]=[0,1,2].map(i=>j[n][i]-prev[n][i]);if(pv){const dv=Math.hypot(...[0,1,2].map(i=>vel[n][i]-pv[n][i]));if(dv>maxdv[0])maxdv=[dv,n];}}pv=vel;}prev=j;}
 console.log(label.padEnd(30),'slide',(worst[0]*1000).toFixed(1).padStart(5),'mm',worst[1].padEnd(10),'t',worst[2],'| kick',(kick[0]*1000).toFixed(1).padStart(5),'mm',kick[1].padEnd(14),'| max dv',(maxdv[0]*1000).toFixed(1),'mm/f²',maxdv[1],'| walk air',nW?(100*airW/nW).toFixed(1)+'%':'-');}
const S=[
[[['walk',3]],'steady walk'],[[['run',3]],'walk->run'],[[['run',2],['idle',2]],'run->idle'],[[['idle',2],['walk',2]],'idle->walk'],[[['idle',2],['run',2]],'idle->run'],[[['run',2],['walk',2]],'run->walk'],
[[['walk',1],['idle',1.5],['attack',3]],'walk->idle->attack'],[[['idle',1.5],['attack',2.5],['walk',2]],'attack->walk'],[[['idle',1.5],['attack',2.5],['idle',2]],'attack->idle'],[[['run',1.5],['attack',3]],'run->attack'],
[[['idle',1.5],['walk',0.2],['run',2]],'idle>walk>run 0.2s'],[[['walk',1],['idle',0.2],['walk',2]],'walk>idle>walk 0.2s'],[[['idle',1.5],['attack',0.5],['walk',0.2],['run',2]],'attack>walk>run'],
[[['run',1],['idle',0.1],['run',0.1],['idle',0.1],['run',2]],'mash run/idle 0.1s'],[[['walk',1],['attack',0.3],['idle',0.3],['walk',0.3],['attack',0.3],['run',2]],'mash 5 taps 0.3s'],[[['walk',1],['idle',0.05],['walk',0.05],['idle',0.05],['walk',0.05],['idle',0.05],['walk',2]],'mash 0.05s']];
S.push([[['idle',1.5],['attack',6]],'steady attack (ref)']);S.push([[['run',4]],'steady run (ref)']);for(const [q,l] of S)scenario(q,l);
