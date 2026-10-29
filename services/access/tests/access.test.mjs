import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { createAccessService } from '../server/access.mjs';

function database(){
 const db=new DatabaseSync(':memory:');
 db.exec(`CREATE TABLE access_sessions(id TEXT PRIMARY KEY,account TEXT NOT NULL,student TEXT NOT NULL,school TEXT NOT NULL,expires INTEGER NOT NULL,binding TEXT);
 CREATE TABLE water_operations(id TEXT PRIMARY KEY,account TEXT,machine TEXT,state TEXT,authorization TEXT,authorization_frame TEXT,consumption_frame TEXT,receipt TEXT,updated INTEGER);
 CREATE TABLE water_locks(account TEXT PRIMARY KEY,operation TEXT);CREATE TABLE access_limits(id TEXT PRIMARY KEY,count INTEGER,expires INTEGER);`);
 function prepare(sql){let values=[];return {bind(...v){values=v;return this;},async first(){return db.prepare(sql).get(...values)??null;},async run(){const r=db.prepare(sql).run(...values);return {meta:{changes:Number(r.changes)}};},execute(){return db.prepare(sql).run(...values);}};}
 return {raw:db,prepare,async batch(statements){db.exec('BEGIN');try{const r=statements.map(s=>s.execute());db.exec('COMMIT');return r;}catch(e){db.exec('ROLLBACK');throw e;}}};
}
function setup({locations=false,duplicateCampus=false}={}){
 let time=1800000000000,expired=false,authFailure=false,settleFailure=false,schoolRedirect=false;
 const calls=[];
 const env={DB:database(),STATE_SECRET:'fixture-state-key',WATER_SECRET:'fixture-water-key',WATER_SID:'fixture-platform',WATER_BLE_NAME:'fixture-radio',WATER_TYPE_ID:'1',WATER_VERSION:'1',TRANSACTIONS_ENABLED:'true'};
 const send=async(url,options)=>{
  url=new URL(url);calls.push({path:url.pathname,method:options.method});
  assert.equal(options.redirect,'manual');
  if(url.hostname==='ecykt.gdbtu.edu.cn'){
   assert.equal(url.pathname,'/ykt-mini/api/customer/getSignData');const input=JSON.parse(options.body);
   if(schoolRedirect)return new Response(null,{status:302,headers:{location:'https://other.invalid/login'}});
   return Response.json(expired?{code:-1}:{code:0,data:{appdata:{vsuppid:'v',appid:'a',userId:input.syscustid,deptId:'d',username:'fixture-name',phone:'fixture-phone'}}});
  }
  assert.equal(url.hostname,'isv.lxt6.cn');
  const data=options.method==='POST'?new URLSearchParams(options.body):url.searchParams;
  assert.equal(data.get('sid'),env.WATER_SID);
  const code=data.get('wxcode');const encoded=encodeURIComponent(code).replace(/%20/g,'+').replace(/[!'()~]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());
  assert.equal(data.get('sign'),createHash('md5').update(env.WATER_SECRET+encoded).digest('hex'));
  if(url.pathname.endsWith('/getUserMsg'))return Response.json({Code:0,Data:{studentid:code.includes('userId=owner-b')?'student-b':'student-a',schoolid:'school'}});
  if(locations && url.pathname.endsWith('/getAreaInfoForApplests')){const parent=code.split('=')[1];const rows=parent==='school'?[{id:'campus',name:'示例校区'},...(duplicateCampus?[{id:'other-campus',name:'示例校区'}]:[])]:parent==='campus'?[{id:'building',name:'2栋'}]:[{id:'floor',name:'五楼'}];return Response.json({code:0,data:rows});}
  if(locations && url.pathname.endsWith('/getAreaForRoomApplests'))return Response.json({code:0,data:[{id:'room',name:'504'}]});
  if(url.pathname.endsWith('/getAreaInfoForApplests'))return Response.json({code:0,data:[{id:'node'+calls.length,name:'fixture-location'}]});
  if(url.pathname.endsWith('/getAreaForRoomApplests'))return Response.json({code:0,data:[{id:'room',name:'301'}]});
  if(url.pathname.endsWith('/getMachineMacAddress'))return Response.json({code:0,data:{objList:[{machineId:'11223344',machineName:'fixture-room',Mac:'11:22:33:44:55:66'}]}});
  if(url.pathname.endsWith('/bathingConsumptionAuthorization')){if(authFailure)throw Error('fixture timeout');return Response.json({code:0,data:{machineid:'11223344',studentId:'AABBCCDD',systemData:'01'.repeat(15)}});}
  if(url.pathname.endsWith('/analysisOfBathingConsumptionData')){if(settleFailure)throw Error('fixture timeout');return Response.json({code:0,data:{pay:12}});}
  throw Error('Unexpected upstream route');
 };
 const make=()=>createAccessService({fetch:send,now:()=>time});let service=make();
 async function request(path,input={},token){const r=await service.fetch(new Request('https://fixture.test'+path,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(input)}),env);return {status:r.status,data:await r.json()};}
 async function connect(owner='owner-a'){const r=await request('/v1/connect',{areacode:'450010',syscustid:owner,custid:'card',acc_token:'fixture-school-token'});assert.equal(r.status,200);return r.data;}
 async function bind(token){let parent='school';for(let i=0;i<4;i++){const r=await request('/v1/options',{parent},token);assert.equal(r.status,200);parent=r.data.options[0].id;}
  const result=await request('/v1/bind',{room:parent,machineID:'11223344'},token);assert.equal(result.status,200);return parent;
 }
 return {env,calls,request,connect,bind,restart(){service=make();},advance(ms){time+=ms;},expireSchool(){expired=true;},redirectSchool(){schoolRedirect=true;},failAuth(){authFailure=true;},failSettle(){settleFailure=true;}};
}
const frame='5511223344'+'00'.repeat(15);

test('Workers-compatible manual redirects fail closed without forwarding school credentials',async()=>{
 const x=setup();x.redirectSchool();const r=await x.request('/v1/connect',{areacode:'450010',syscustid:'owner-a',custid:'card',acc_token:'fixture-school-token'});
 assert.equal(r.status,502);assert.equal(r.data.error,'school_http_302');assert.equal(x.calls.length,1);
 assert.equal(x.env.DB.raw.prepare('SELECT count(*) n FROM access_sessions').get().n,0);
});

test('invalid school login never produces a water session or forwards a caller identity',async()=>{
 const x=setup();x.expireSchool();const r=await x.request('/v1/connect',{areacode:'450010',syscustid:'owner-a',custid:'card',acc_token:'expired',studentID:'another-student'});
 assert.equal(r.status,401);assert.equal(x.calls.length,1);assert.equal(x.env.DB.raw.prepare('SELECT count(*) n FROM access_sessions').get().n,0);
});
test('verified login returns only a scoped session and public protocol metadata',async()=>{
 const x=setup(),s=await x.connect();assert.equal(s.studentID,'student-a');assert.match(s.token,/^[A-Za-z0-9_-]{43}$/);
 const text=JSON.stringify(s);for(const secret of ['fixture-water-key','fixture-platform','fixture-school-token','fixture-name','fixture-phone'])assert.equal(text.includes(secret),false);
 assert.equal(x.env.DB.raw.prepare('SELECT id FROM access_sessions').get().id.includes(s.token),false);
});
test('location cursors cannot be forged or used by another account',async()=>{
 const x=setup(),a=await x.connect(),b=await x.connect('owner-b');const r=await x.request('/v1/options',{parent:'school'},a.token),cursor=r.data.options[0].id;
 assert.equal((await x.request('/v1/options',{parent:cursor},b.token)).status,400);
 assert.equal((await x.request('/v1/options',{parent:cursor+'x'},a.token)).status,400);
 assert.equal((await x.request('/v1/bind',{room:cursor,machineID:'11223344'},a.token)).status,400);
});
test('no anonymous signing endpoint and physical writes stay disabled until explicitly enabled',async()=>{
 const x=setup();assert.equal((await x.request('/v1/sign',{path:'anything'})).status,404);
 assert.equal((await x.request('/v1/authorize',{frame})).status,401);
 const s=await x.connect();await x.bind(s.token);x.env.TRANSACTIONS_ENABLED='false';const before=x.calls.length;
 assert.equal((await x.request('/v1/authorize',{frame,operationID:'fixture-operation-123'},s.token)).status,503);assert.equal(x.calls.length,before);
});
test('wrong device never reaches provider and unresolved authorization blocks repeats across restart',async()=>{
 const x=setup(),s=await x.connect();await x.bind(s.token);const before=x.calls.length;
 assert.equal((await x.request('/v1/authorize',{frame:frame.replace('11223344','55667788'),operationID:'fixture-operation-123'},s.token)).status,400);assert.equal(x.calls.length,before);
 x.failAuth();assert.equal((await x.request('/v1/authorize',{frame,operationID:'fixture-operation-123'},s.token)).status,503);x.restart();
 assert.equal((await x.request('/v1/authorize',{frame,operationID:'fixture-operation-456'},s.token)).status,409);
 assert.equal(x.calls.filter(c=>c.path.endsWith('/bathingConsumptionAuthorization')).length,1);
 assert.equal((await x.request('/v1/status',{},s.token)).data.operation.state,'authorization-uncertain');
});
test('new login cannot clear an existing account operation lock or change its binding',async()=>{
 const x=setup(),s=await x.connect(),room=await x.bind(s.token);
 assert.equal((await x.request('/v1/authorize',{frame,operationID:'fixture-operation-123'},s.token)).status,200);
 const refreshed=await x.connect();assert.equal((await x.request('/v1/authorize',{frame,operationID:'fixture-operation-456'},refreshed.token)).status,409);
 assert.equal((await x.request('/v1/bind',{room,machineID:'11223344'},s.token)).status,409);
});
test('settlement can finish an own pending operation after session expiry; no repeat billing',async()=>{
 const x=setup(),s=await x.connect();await x.bind(s.token);assert.equal((await x.request('/v1/authorize',{frame,operationID:'fixture-operation-123'},s.token)).status,200);
 x.advance(8*86400000);assert.equal((await x.request('/v1/authorize',{frame,operationID:'fixture-operation-456'},s.token)).status,401);
 const r=await x.request('/v1/settle',{frame},s.token);assert.equal(r.status,200);assert.equal(r.data.payFen,12);
 assert.equal((await x.request('/v1/settle',{frame},s.token)).status,409);assert.equal(x.calls.filter(c=>c.path.endsWith('/analysisOfBathingConsumptionData')).length,1);
});
test('uncertain settlement retains an account lock and refuses replay',async()=>{
 const x=setup(),s=await x.connect();await x.bind(s.token);await x.request('/v1/authorize',{frame,operationID:'fixture-operation-123'},s.token);x.failSettle();
 assert.equal((await x.request('/v1/settle',{frame},s.token)).status,503);x.restart();assert.equal((await x.request('/v1/settle',{frame},s.token)).status,409);
 assert.equal((await x.request('/v1/status',{},s.token)).data.operation.state,'settlement-uncertain');
});


test('one bootstrap reads an exact own residence without binding or authorizing',async()=>{
 const x=setup({locations:true}),s=await x.connect();x.env.TRANSACTIONS_ENABLED='false';
 const r=await x.request('/v1/bootstrap',{residence:'示例校区2栋3号5层504房'},s.token);
 assert.equal(r.status,200);assert.equal(r.data.matched,true);assert.equal(r.data.path.length,4);assert.equal(r.data.levels.length,4);assert.equal(r.data.machines.length,1);assert.equal(r.data.transactionsEnabled,false);
 assert.equal(x.env.DB.raw.prepare('SELECT binding FROM access_sessions').get().binding,null);
 assert.equal(x.calls.some(c=>c.path.endsWith('/bathingConsumptionAuthorization')),false);
});
test('catalogue caching never shares signed room cursors between accounts',async()=>{
 const x=setup({locations:true}),a=await x.connect(),b=await x.connect('owner-b');
 const first=await x.request('/v1/bootstrap',{residence:'示例校区2栋3号5层504房'},a.token);
 const catalogueCalls=()=>x.calls.filter(c=>c.path.includes('/areaInfo/')).length;
 const count=catalogueCalls();const next=await x.request('/v1/bootstrap',{residence:'示例校区2栋3号5层504房'},b.token);
 assert.equal(next.data.matched,true);assert.equal(catalogueCalls(),count);
 assert.notEqual(first.data.path[3].id,next.data.path[3].id);
 assert.equal((await x.request('/v1/machines',{room:first.data.path[3].id},b.token)).status,400);
 x.advance(600001);await x.request('/v1/bootstrap',{residence:'示例校区2栋3号5层504房'},a.token);assert.equal(catalogueCalls(),count+4);
});
test('bootstrap stops at ambiguous or absent residence and never guesses a machine',async()=>{
 const x=setup({locations:true,duplicateCampus:true}),s=await x.connect();
 for(const residence of ['示例校区2栋3号5层504房','2504','其他校区2栋5层504房']){
  const r=await x.request('/v1/bootstrap',{residence},s.token);assert.equal(r.status,200);assert.equal(r.data.matched,false);assert.equal(r.data.path.length,0);assert.equal(r.data.machines.length,0);
 }
 assert.equal(x.calls.some(c=>c.path.endsWith('/getMachineMacAddress')),false);
});
