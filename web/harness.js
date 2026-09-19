const fs=require('fs');const s=fs.readFileSync(process.argv[2]||'rig-v4.html','utf8');
const a=s.indexOf('// ==RIG-BEGIN=='),b=s.indexOf('// ==RIG-END==');
const R=new Function(s.slice(a,b)+';return SKRIG;')();
module.exports=R;
if(require.main===module){
const c=new R.Controller();const DT=1/60;
function run(n,f){for(let i=0;i<n;i++){const P=c.step(DT);if(f)f(i,P);}}
// steady walk: planted-foot slide in ground space
function slideProbe(){const anc={};let mx=0;return {tick(P){const W=R.fk(P);for(const S of ['L','R']){const cc=P.contact[S];const pts=cc==='heel'?['heel']:cc==='ball'?['toe']:cc==='flat'?['heel','toe']:[];for(const k of ['heel','toe']){const key=k+S;if(!pts.includes(k)){delete anc[key];continue;}const g=[W[key].p[0],W[key].p[2]+c.travel];if(!anc[key])anc[key]=g;else mx=Math.max(mx,Math.hypot(g[0]-anc[key][0],g[1]-anc[key][1]));}}},max(){return mx;}};}
let sp=slideProbe();run(240,(i,P)=>sp.tick(P));console.log('steady walk slide mm',(sp.max()*1000).toFixed(2));
c.set('run');sp=slideProbe();let vs=[];run(120,(i,P)=>{sp.tick(P);vs.push(c.v);});console.log('walk->run slide mm',(sp.max()*1000).toFixed(2),'v max',Math.max(...vs).toFixed(3),'monotonic',vs.every((v,i)=>i==0||v>=vs[i-1]-1e-9));
sp=slideProbe();run(240,(i,P)=>sp.tick(P));console.log('steady run slide mm',(sp.max()*1000).toFixed(2));
c.set('idle');sp=slideProbe();vs=[];let t0=null;run(120,(i,P)=>{sp.tick(P);vs.push(c.v);if(t0===null&&c.settled)t0=i*DT;});
console.log('run->idle slide mm',(sp.max()*1000).toFixed(2),'v monotonic down',vs.every((v,i)=>i==0||v<=vs[i-1]+1e-9),'settled at s',t0,'L',c.L.a.map(x=>x.toFixed(2)),'R',c.R.a.map(x=>x.toFixed(2)));
c.set('attack');let ph=[];run(200,(i,P)=>{if(i%20==0)ph.push([c.seq,c.atk,c.wa.toFixed(2),P.phase]);});console.log('idle->attack',JSON.stringify(ph));
c.set('walk');vs=[];sp=slideProbe();run(120,(i,P)=>{sp.tick(P);vs.push(c.v);});console.log('attack->walk slide mm',(sp.max()*1000).toFixed(2),'v',vs.filter((_,i)=>i%10==0).map(v=>v.toFixed(2)).join(' '));
// NaN check
let nan=0;run(60,(i,P)=>{for(const n in P.q)for(const x of P.q[n])if(!isFinite(x))nan++;});console.log('nan',nan);
}
