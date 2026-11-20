const {PGlite}=await import(process.env.SKCPL_PGLITE_MODULE??'@electric-sql/pglite');
import {fileURLToPath} from 'node:url';
import fs from 'node:fs/promises';import assert from 'node:assert/strict';
const repository=process.env.SKCPL_REPO??fileURLToPath(new URL('../../',import.meta.url));
const sql=await fs.readFile(repository+'/supabase/migrations/202611210001_rejected_entry_actions.sql','utf8');
for(const legacy of [false,true]){
 const db=new PGlite();await db.waitReady;
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create function auth.uid()returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create table users(id uuid primary key,role text,is_active boolean default true);
 create table tasks(id uuid primary key default gen_random_uuid(),title text,description text);
 create table skcpl_management_state(singleton boolean,settings jsonb);
 insert into skcpl_management_state values(true,'{"project_head_can_approve_cash":true,"accounts_can_approve_cash":true,"project_head_can_approve_stock":true,"accounts_can_approve_stock":true}');
 create function skcpl_require_management_session()returns void language sql as $$select$$;
 create function skcpl_attendance_safe_json(value text)returns jsonb language plpgsql immutable as $$begin return value::jsonb;exception when others then return null;end;$$;
 create table cash_transactions(id uuid primary key,site_id uuid,submitted_by uuid,date date,expense_type_id uuid,expense_amount numeric,amount_received numeric,cash_in_hand numeric,remarks text,photo_urls text[],status text,rejection_note text,reviewed_by uuid,reviewed_at timestamptz,approved_by uuid,approved_at timestamptz,created_at timestamptz default now(),updated_at timestamptz default now());
 create table stock_transactions(id uuid primary key,site_id uuid,submitted_by uuid,date date,type text,vendor_id uuid,product_id uuid,metric_unit_id uuid,quantity numeric,rate numeric,sgst numeric,igst numeric,final_amount numeric,remarks text,unregistered_vendor text,photo_urls text[],status text,rejection_note text,reviewed_by uuid,reviewed_at timestamptz,approved_by uuid,approved_at timestamptz,created_at timestamptz default now(),updated_at timestamptz default now());
 alter table cash_transactions enable row level security;alter table stock_transactions enable row level security;
 grant usage on schema public,auth to anon,authenticated;grant select,insert,update,delete on cash_transactions,stock_transactions to anon,authenticated;
 create policy old_read on cash_transactions for all to anon,authenticated using(true)with check(true);create policy old_read on stock_transactions for all to anon,authenticated using(true)with check(true);
 ${legacy?'':"create table site_staff(id text,site_id uuid,name text,role text,designation text,pin text,is_active boolean,modules jsonb);"}`);
 await db.exec(sql);
 const site='00000000-0000-4000-8000-000000000011',admin='00000000-0000-4000-8000-000000000001',account='00000000-0000-4000-8000-000000000002';
 await db.query('insert into users values($1,\'admin\',true),($2,\'accounts\',true)',[admin,account]);
 async function staff(id,name,pin){const d={id,site_id:site,name,role:'worker',designation:'Engineer',pin,is_active:true,modules:['cashbook','stock']};
 if(legacy)await db.query("insert into tasks(title,description)values($1,$2)",['STAFF:'+site+':'+id,JSON.stringify(d)]);
 else await db.query("insert into site_staff values($1,$2,$3,'worker','Engineer',$4,true,'[\"cashbook\",\"stock\"]')",[id,site,name,pin]);}
 await staff('worker','Ramesh','pin-worker');await staff('other','Other','pin-other');
 async function seed(module,id,status='rejected'){const table=module==='cash'?'cash_transactions':'stock_transactions';await db.query(`insert into ${table}(id,site_id,date,status,remarks,rejection_note,photo_urls,${module==='cash'?'expense_amount,amount_received,cash_in_hand':'quantity,rate,sgst,igst,final_amount'})values($1,$2,current_date,$3,'[By: Ramesh (Engineer)] [Project Head: Rejected] Site work','Wrong bill',array['old-photo'],${module==='cash'?'100,0,0':'10,2,0,0,20'})`,[id,site,status]);}
 async function actor(role,uid=null){await db.exec('reset role;');await db.query("select set_config('test.uid',$1,false)",[uid??'']);await db.exec('set role '+role);}
 async function action(module,id,kind,newid=null,payload=null,staffid='worker',pin='pin-worker',stamp=null){return(await db.query('select public.skcpl_rejected_entry_action($1,$2,$3,$4,$5,$6,$7,$8) result',[module,id,kind,newid,payload,staffid,pin,stamp])).rows[0].result;}
 async function denied(fn){let failed=false;try{await fn();}catch(e){failed=true;}assert.equal(failed,true);}
 // Shared anonymous worker cleanup is OFF by default, pending a separate access review.
 await seed('cash','30000000-0000-4000-8000-000000000001');await actor('anon');
 await denied(()=>action('cash','30000000-0000-4000-8000-000000000001','dismiss',null,null,'worker','pin-worker',null));
 await db.exec('reset role;');
 const owner='00000000-0000-4000-8000-000000000003';
 await db.query("insert into users values($1,'worker',true)",[owner]);
 await db.query('update cash_transactions set submitted_by=$1 where id=$2',[owner,'30000000-0000-4000-8000-000000000001']);
 await actor('authenticated',owner);
 await denied(()=>action('cash','30000000-0000-4000-8000-000000000001','dismiss'));
 await actor('authenticated',admin);
 const gateStamp=(await db.query("select updated_at::text stamp from cash_transactions where id='30000000-0000-4000-8000-000000000001'")).rows[0].stamp;
 await action('cash','30000000-0000-4000-8000-000000000001','dismiss',null,null,null,null,gateStamp);
 assert.equal((await db.query("select * from cash_transactions where id='30000000-0000-4000-8000-000000000001'")).rows.length,0);
 await db.exec('reset role;update skcpl_rejected_action_config set worker_actions_enabled=true,legacy_worker_actions_enabled=true;');
 for(const module of ['cash','stock']){
  const table=module==='cash'?'cash_transactions':'stock_transactions',a=module==='cash'?'10000000-0000-4000-8000-000000000001':'20000000-0000-4000-8000-000000000001',fresh=a.replace(/1$/,'2'),b=a.replace(/1$/,'3');
  await actor('authenticated',admin);await seed(module,a);await seed(module,b,'approved');
  const original=(await db.query(`select to_jsonb(t) d from ${table} t where id=$1`,[a])).rows[0].d;
  const stamp=original.updated_at;
  await actor('anon');assert.equal((await db.query(`select * from ${table} where id=$1`,[a])).rows.length,1);
  await db.query(`delete from ${table} where id=$1`,[a]);assert.equal((await db.query(`select * from ${table} where id=$1`,[a])).rows.length,1);
  await db.query(`update ${table} set status='pending_accounts' where id=$1`,[a]);assert.equal((await db.query(`select status from ${table} where id=$1`,[a])).rows[0].status,'rejected');
  await denied(()=>db.query('select * from skcpl_rejected_actions'));
  await denied(()=>db.query("insert into skcpl_rejected_events(module,source_id,action)values('cash',$1,'dismiss')",[a]));
  await denied(()=>action(module,a,'dismiss',null,null,'other','pin-other',stamp));
  await denied(()=>action(module,a,'dismiss',null,null,'worker','wrong',stamp));
  await denied(()=>action(module,b,'dismiss',null,null,'worker','pin-worker',stamp));
  await actor('authenticated',account);await denied(()=>action(module,a,'dismiss',null,null,'worker','pin-worker',stamp));
  await actor('anon');await denied(()=>action(module,a,'resubmit',fresh,{date:'2099-01-01'},'worker','pin-worker',stamp));
  assert.equal((await db.query(`select * from ${table} where id=$1`,[a])).rows.length,1);
  const payload=module==='cash'?{expense_amount:125,amount_received:0,remarks:'Corrected bill',status:'approved',site_id:'00000000-0000-4000-8000-000000000099'}:{quantity:12,remarks:'Corrected delivery'};
  const result=await action(module,a,'resubmit',fresh,payload,'worker','pin-worker',stamp);assert.equal(result.entry.status,'pending_accounts');assert.equal(result.entry.site_id,site);assert.equal(result.entry.rejection_note,null);assert.match(result.entry.remarks,/Review: Pending/);assert.deepEqual(result.entry.photo_urls,['old-photo']);
  assert.equal((await db.query(`select * from ${table} where id=$1`,[a])).rows.length,0);
  for(const uid of [account,admin]){await actor('authenticated',uid);assert.equal((await db.query(`select * from ${table} where id=$1`,[a])).rows.length,0);}
  await actor('anon');assert.equal((await action(module,a,'resubmit',fresh,payload,'worker','pin-worker',stamp)).already_saved,true);
  await denied(()=>action(module,a,'resubmit',fresh,{...payload,remarks:'Different correction'},'worker','pin-worker',stamp));
  await db.exec('reset role');assert.deepEqual((await db.query(`select to_jsonb(t) d from ${table} t where id=$1`,[a])).rows[0].d,original);
  const c=a.replace(/1$/,'4');await seed(module,c);const cstamp=(await db.query(`select updated_at::text stamp from ${table} where id=$1`,[c])).rows[0].stamp;
  await actor('authenticated',admin);await action(module,c,'dismiss',null,null,null,null,cstamp);assert.equal((await db.query(`select * from ${table} where id=$1`,[c])).rows.length,0);
  await db.exec('reset role');assert.equal((await db.query(`select count(*)::int n from ${table} where id=$1`,[c])).rows[0].n,1);
  const d=a.replace(/1$/,'5'),e=a.replace(/1$/,'6');await seed(module,d);const dstamp=(await db.query(`select updated_at::text stamp from ${table} where id=$1`,[d])).rows[0].stamp;
  await db.exec(`update skcpl_management_state set settings=jsonb_build_object('project_head_can_approve_${module}',false,'accounts_can_approve_${module}',false)`);
  await actor('anon');const bypass=await action(module,d,'resubmit',e,payload,'worker','pin-worker',dstamp);assert.equal(bypass.entry.status,'pending_admin');assert.doesNotMatch(bypass.entry.remarks,/Review: Pending/);
  await db.exec('reset role');

 }
 await db.close();console.log('PASS: '+(legacy?'legacy staff':'primary staff')+'; own-worker restrictions, Admin, all-role visibility, atomicity, fresh review stages, idempotency and source preservation');
}
