import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

const SCHOOL = 'https://ecykt.gdbtu.edu.cn';
const WATER = 'https://isv.lxt6.cn/';
const DAY = 86400000;
class Problem extends Error { constructor(code,status=400){super(code);this.code=code;this.status=status;} }
const demand=(ok,code='invalid_request',status=400)=>{if(!ok)throw new Problem(code,status);};
const digest=s=>createHash('sha256').update(s).digest('hex');
const seal=(secret,text)=>createHmac('sha256',secret).update(text).digest('base64url');
const scalar=(v,max=128)=>typeof v==='string' && v.length>0 && v.length<=max && !/[\x00-\x1f\x7f]/.test(v);
const id=v=>scalar(v,64)&&/^[A-Za-z0-9.-]+$/.test(v);
const encode=s=>encodeURIComponent(s).replace(/%20/g,'+').replace(/[!'()~]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());
const json=(data,status=200)=>Response.json(data,{status,headers:{'cache-control':'no-store','x-content-type-options':'nosniff'}});
const random=()=>randomBytes(4).toString('hex').toUpperCase().slice(0,6);

export function createAccessService({fetch:send=globalThis.fetch,now=()=>Date.now()}={}) {
  // Cache only the school's location catalogue, never sessions or personal data.
  const catalogue=new Map();
  async function body(request){
    demand((request.headers.get('content-type')||'').startsWith('application/json'),'json_required',415);
    const length=Number(request.headers.get('content-length')||0);demand(length<=8192,'request_too_large',413);
    const bytes=await request.arrayBuffer();demand(bytes.byteLength<=8192,'request_too_large',413);
    let value;try{value=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new Problem('invalid_json');}
    demand(value && !Array.isArray(value) && typeof value==='object');return value;
  }
  async function upstream(url,options){
    const source=new URL(url).hostname===new URL(SCHOOL).hostname?'school':'water';
    // Workers supports manual redirects. Reject every non-2xx response below,
    // so credentials are never forwarded to a redirect target.
    let response;try{response=await send(url,{...options,redirect:'manual',signal:AbortSignal.timeout(15000)});}catch{throw new Problem(source+'_unavailable',502);}
    demand(response.ok,source+'_http_'+response.status,502);
    const bytes=await response.arrayBuffer();demand(bytes.byteLength<=1048576,source+'_invalid',502);
    try{let value=JSON.parse(new TextDecoder().decode(bytes));if(typeof value==='string')value=JSON.parse(value);return value;}catch{throw new Problem(source+'_invalid',502);}
  }
  async function school(config){
    demand(config.areacode==='450010' && scalar(config.syscustid) && scalar(config.acc_token,2048) && scalar(config.custid),'school_login_required',401);
    const fields={syscustid:config.syscustid,acc_token:config.acc_token,custid:config.custid};
    if(config.timestamp) {demand(scalar(config.timestamp,128));fields.timestamp=config.timestamp;}
    const root=await upstream(SCHOOL+'/ykt-mini/api/customer/getSignData',{method:'POST',headers:{'content-type':'application/json',acc_token:config.acc_token,origin:SCHOOL,referer:SCHOOL+'/ykt-view/wallet/transaction'},body:JSON.stringify(fields)});
    demand(root.code===0 && root.data,'school_login_expired',401);
    let data=root.data;if(typeof data==='string'){try{data=JSON.parse(data);}catch{throw new Problem('upstream_invalid',502);}}
    let own=data.appdata;if(typeof own==='string'){try{own=JSON.parse(own);}catch{throw new Problem('upstream_invalid',502);}}
    demand(own && typeof own==='object','school_identity_missing',502);
    const result=[];
    for(const key of ['vsuppid','appid','userId','deptId','username','phone']) {demand(scalar(own[key],2048),'school_identity_missing',502);result.push([key,own[key]]);}
    return result;
  }
  async function provider(env,path,fields,{method='GET',requestType=false}={}){
    const wxcode=fields.map(([k,v])=>`${k}=${v}`).join('*_');
    const sign=createHash('md5').update(env.WATER_SECRET+encode(wxcode)).digest('hex');
    const form=new URLSearchParams({wxcode,sign,sid:env.WATER_SID});if(requestType)form.set('requestType','1');
    const url=new URL(path,WATER);let options={method,headers:{'content-type':'application/x-www-form-urlencoded'}};
    if(method==='GET')url.search=form.toString();else options.body=form.toString();
    const root=await upstream(url,options);
    demand((root.code??root.Code)===0,'water_provider_rejected',502);
    return root;
  }
  async function limit(env,scope,key,max,period){
    const bucket=Math.floor(now()/period),name=digest(scope+':'+key+':'+bucket);
    const row=await env.DB.prepare('INSERT INTO access_limits(id,count,expires) VALUES (?,1,?) ON CONFLICT(id) DO UPDATE SET count=count+1 WHERE count<? RETURNING count').bind(name,now()+2*period,max).first();
    demand(row,'rate_limited',429);
  }
  function cursor(env,session,node,level){
    const payload=Buffer.from(JSON.stringify({a:session.account,n:node,l:level,e:session.expires})).toString('base64url');return payload+'.'+seal(env.STATE_SECRET,payload);
  }
  function readCursor(env,session,text,level){
    demand(scalar(text,1024),'invalid_location');
    const parts=text.split('.');demand(parts.length===2,'invalid_location');
    const signature=seal(env.STATE_SECRET,parts[0]),a=Buffer.from(parts[1]),b=Buffer.from(signature);
    demand(a.length===b.length && timingSafeEqual(a,b),'invalid_location');
    let result;try{result=JSON.parse(Buffer.from(parts[0],'base64url').toString());}catch{throw new Problem('invalid_location');}
    demand(result.a===session.account && result.e>now() && Number.isInteger(result.l) && result.l>=0 && result.l<=3 && scalar(result.n),'invalid_location');
    if(level!==undefined)demand(result.l===level,'invalid_location');return result;
  }
  async function authenticated(request,env,allowExpired=false){
    const value=request.headers.get('authorization')||'';demand(/^Bearer [A-Za-z0-9_-]{43}$/.test(value),'login_required',401);
    const session=await env.DB.prepare('SELECT * FROM access_sessions WHERE id=?').bind(digest(value.slice(7))).first();
    demand(session && (session.expires>now() || allowExpired && session.expires+30*DAY>now()),'access_expired',401);
    return session;
  }
  async function locationOptions(env,s,parent){
    let node,level;
    if(parent===s.school){node=s.school;level=0;}
    else {const prior=readCursor(env,s,parent);demand(prior.l<3,'invalid_location');node=prior.n;level=prior.l+1;}
    const route=level===3?'zk_areainfo_api/areaInfo/getAreaForRoomApplests':'zk_areainfo_api/areaInfo/getAreaInfoForApplests';
    const key=JSON.stringify([s.school,level,node]);let cached=catalogue.get(key);
    if(!cached || cached.expires<=now()){
      const root=await provider(env,route,[['id',node]]);demand(Array.isArray(root.data)&&root.data.length<=1000,'upstream_invalid',502);
      const rows=root.data.map(x=>{const id=String(x.id??'');demand(scalar(id)&&scalar(x.name),'upstream_invalid',502);return {id,name:x.name};});
      demand(new Set(rows.map(x=>x.id)).size===rows.length,'upstream_invalid',502);
      if(catalogue.size>=200)catalogue.delete(catalogue.keys().next().value);
      cached={rows,expires:now()+600000};catalogue.set(key,cached);
    }
    // Always mint cursors for this account, even when the raw catalogue is cached.
    return cached.rows.map(x=>({id:cursor(env,s,x.id,level),name:x.name}));
  }
  function residence(raw){
    if(typeof raw!=='string' || raw.length>128)return null;
    const text=raw.replace(/\s/g,''),m=/^(.{1,32}校区)([A-Za-z]?[0-9]{1,3})(?:栋|幢)(?:([0-9]{1,3})号)?([0-9]{1,2})(?:层|楼)([0-9]{2,6}[A-Za-z]?)(?:房|室)$/.exec(text);
    if(!m || Number(m[4])<1)return null;
    const cn=['零','一','二','三','四','五','六','七','八','九','十','十一','十二','十三','十四','十五','十六','十七','十八','十九','二十'];
    const floor=Number(m[4]),number=cn[floor]??String(floor);
    return [[m[1]],[m[2]+'栋',m[2]+'幢',m[2]+'号楼'],[floor+'楼',floor+'层',number+'楼',number+'层'],[m[5],m[5]+'房',m[5]+'室']];
  }
  async function machines(env,s,room){
    const node=readCursor(env,s,room,3);
    const root=await provider(env,'ZK_BSRS/bathe/getMachineMacAddress',[['typeId',String(env.WATER_TYPE_ID)],['schoolId',s.school],['roomId',node.n]]);
    const list=root.data?.objList;demand(Array.isArray(list)&&list.length<=100,'upstream_invalid',502);
    return list.map(x=>{demand(typeof x.machineId==='string' && /^[0-9A-Fa-f]{8}$/.test(x.machineId) && scalar(x.machineName) && scalar(x.Mac),'upstream_invalid',502);return {id:x.machineId.toUpperCase(),name:x.machineName,mac:x.Mac};});
  }
  function frame(value,machine){demand(typeof value==='string' && /^55[0-9A-Fa-f]{38}$/.test(value),'invalid_frame');demand(value.slice(2,10).toUpperCase()===machine,'wrong_device');return value.toUpperCase();}
  function operationFields(env,s,machine,value){return [['studentId',s.student],['schoolId',s.school],['machineid',machine],['machinedata',value],['typeId',String(env.WATER_TYPE_ID)],['alleywaytype','0'],['rand',random()],['version',String(env.WATER_VERSION)]];}
  return {
    async fetch(request,env){
      try{
        const path=new URL(request.url).pathname;
        if(path==='/health' && request.method==='GET')return json({service:'campus-daily-access',protocol:1,configured:!!(env.DB&&env.WATER_SECRET&&env.WATER_SID&&env.STATE_SECRET),transactions:env.TRANSACTIONS_ENABLED==='true'});
        demand(path.startsWith('/v1/') && request.method==='POST','not_found',404);
        demand(env.DB&&env.WATER_SECRET&&env.WATER_SID&&env.STATE_SECRET,'service_not_configured',503);
        demand(['connect','bootstrap','options','machines','bind','authorize','settle','status'].some(x=>path==='/v1/'+x),'not_found',404);
        const input=await body(request);
        if(path==='/v1/connect'){
          const ip=request.headers.get('cf-connecting-ip')||'local';await limit(env,'connect-ip',seal(env.STATE_SECRET,ip),12,60000);
          const fields=await school(input);
          const root=await provider(env,'AECC/GDBusinessSchool/getUserMsg',[['schoolid','20021'],...fields,['random',random()]],{requestType:true});
          demand(id(root.Data?.studentid),'water_identity_missing',502);
          const schoolID=String(root.Data.schoolid??'');demand(id(schoolID),'water_identity_missing',502);
          const account=seal(env.STATE_SECRET,input.areacode+'\0'+input.syscustid),token=randomBytes(32).toString('base64url'),expires=now()+7*DAY;
          // Reauthentication of the same school identity retains only its own prior binding.
          const previous=await env.DB.prepare('SELECT binding FROM access_sessions WHERE account=? AND binding IS NOT NULL ORDER BY expires DESC LIMIT 1').bind(account).first();
          await env.DB.prepare('INSERT INTO access_sessions(id,account,student,school,expires,binding) VALUES (?,?,?,?,?,?)').bind(digest(token),account,root.Data.studentid,schoolID,expires,previous?.binding??null).run();
          await env.DB.prepare('DELETE FROM access_limits WHERE expires<?').bind(now()).run();
          return json({token,expiresAt:expires,campusOwner:digest(input.areacode+'\0'+input.syscustid),studentID:root.Data.studentid,schoolID,bleName:env.WATER_BLE_NAME,typeID:Number(env.WATER_TYPE_ID),version:Number(env.WATER_VERSION)});
        }
        const s=await authenticated(request,env,path==='/v1/settle'||path==='/v1/status');
        await limit(env,'session',s.account,60,60000);
        if(path==='/v1/bootstrap'){
          const address=residence(input.residence),levels=[],selected=[];let parent=s.school;
          for(let level=0;level<4;level++){
            const rows=await locationOptions(env,s,parent);levels.push(rows);
            const matching=address?rows.filter(x=>address[level].includes(x.name.replace(/\s/g,''))):[];
            if(matching.length!==1)break;
            selected.push(matching[0]);parent=matching[0].id;
          }
          const matched=selected.length===4;
          return json({levels,path:selected,matched,machines:matched?await machines(env,s,parent):[],transactionsEnabled:env.TRANSACTIONS_ENABLED==='true'});
        }
        if(path==='/v1/options')return json({options:await locationOptions(env,s,input.parent)});
        if(path==='/v1/machines')return json({machines:await machines(env,s,input.room)});
        if(path==='/v1/bind'){
          demand(!await env.DB.prepare('SELECT operation FROM water_locks WHERE account=?').bind(s.account).first(),'water_unresolved',409);
          const values=await machines(env,s,input.room),selected=values.filter(x=>x.id===input.machineID);
          demand(selected.length===1,'wrong_device');
          await env.DB.prepare('UPDATE access_sessions SET binding=? WHERE id=?').bind(JSON.stringify({machine:selected[0].id}),s.id).run();return json({bound:true,machineID:selected[0].id});
        }
        if(path==='/v1/status'){
          const row=await env.DB.prepare('SELECT o.state,o.machine,o.updated FROM water_operations o JOIN water_locks l ON l.operation=o.id WHERE l.account=?').bind(s.account).first();
          return json({operation:row??null,transactionsEnabled:env.TRANSACTIONS_ENABLED==='true'});
        }
        demand(env.TRANSACTIONS_ENABLED==='true','transactions_not_enabled',503);
        let binding;try{binding=JSON.parse(s.binding||'null');}catch{throw new Problem('bind_required',409);}
        demand(binding && /^[0-9A-F]{8}$/.test(binding.machine),'bind_required',409);
        const value=frame(input.frame,binding.machine);
        if(path==='/v1/authorize'){
          demand(typeof input.operationID==='string' && /^[A-Za-z0-9-]{16,64}$/.test(input.operationID));
          // Reserve before contacting the water provider. Never repeat an uncertain request.
          try{await env.DB.batch([
            env.DB.prepare('INSERT INTO water_locks(account,operation) VALUES (?,?)').bind(s.account,input.operationID),
            env.DB.prepare('INSERT INTO water_operations(id,account,machine,state,authorization_frame,updated) VALUES (?,?,?,?,?,?)').bind(input.operationID,s.account,binding.machine,'authorization-pending',value,now())
          ]);}catch{throw new Problem('water_unresolved',409);}
          try{
            const root=await provider(env,'ZK_BSRS/GDBusinessSchool/bathingConsumptionAuthorization',operationFields(env,s,binding.machine,value),{method:'POST'});
            const data=root.data;demand(data&&data.machineid?.toUpperCase()===binding.machine && /^[0-9A-Fa-f]{8}$/.test(data.studentId) && typeof data.systemData==='string' && /^[0-9A-Fa-f]{30}$/.test(data.systemData),'authorization_invalid',502);
            await env.DB.prepare('UPDATE water_operations SET state=?,authorization=?,updated=? WHERE id=?').bind('authorized',data.studentId.toUpperCase(),now(),input.operationID).run();
            return json({machineID:binding.machine,studentID:data.studentId.toUpperCase(),payload:data.systemData.toUpperCase()});
          }catch{
            await env.DB.prepare('UPDATE water_operations SET state=?,updated=? WHERE id=?').bind('authorization-uncertain',now(),input.operationID).run();throw new Problem('authorization_uncertain',503);
          }
        }
        const row=await env.DB.prepare('SELECT o.* FROM water_operations o JOIN water_locks l ON l.operation=o.id WHERE l.account=?').bind(s.account).first();
        demand(row && row.machine===binding.machine && row.state==='authorized','water_unresolved',409);
        const update=await env.DB.prepare('UPDATE water_operations SET state=?,consumption_frame=?,updated=? WHERE id=? AND state=?').bind('settlement-pending',value,now(),row.id,'authorized').run();
        demand(update.meta?.changes===1,'water_unresolved',409);
        try{
          const root=await provider(env,'ZK_BSRS/GDBusinessSchool/analysisOfBathingConsumptionData',operationFields(env,s,binding.machine,value),{method:'POST'});
          const pay=root.data?.pay;const payFen=(typeof pay==='number'&&Number.isSafeInteger(pay)||typeof pay==='string'&&/^\d+$/.test(pay))&&Number(pay)>=0&&Number(pay)<=100000000000?Number(pay):null;
          await env.DB.batch([
            env.DB.prepare('UPDATE water_operations SET state=?,receipt=?,updated=? WHERE id=?').bind('settled',JSON.stringify({payFen}),now(),row.id),
            env.DB.prepare('DELETE FROM water_locks WHERE account=? AND operation=?').bind(s.account,row.id)
          ]);return json({settled:true,payFen});
        }catch{
          await env.DB.prepare('UPDATE water_operations SET state=?,updated=? WHERE id=?').bind('settlement-uncertain',now(),row.id).run();throw new Problem('settlement_uncertain',503);
        }
      }catch(error){return json({error:error instanceof Problem?error.code:'service_unavailable'},error instanceof Problem?error.status:503);}
    }
  };
}
export default createAccessService();
