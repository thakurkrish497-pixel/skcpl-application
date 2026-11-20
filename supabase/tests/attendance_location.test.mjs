const {PGlite} = await import(process.env.SKCPL_PGLITE_MODULE ?? '@electric-sql/pglite');
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const repository = process.env.SKCPL_REPO ?? new URL('../../', import.meta.url).pathname;
const sql=await fs.readFile(repository+'/supabase/migrations/202611200001_attendance_session_expiry.sql','utf8');
const results=[];
for(const primary of [false,true]) {
 const db=new PGlite();await db.waitReady;
 await db.exec(`create role anon;create role authenticated;create role service_role;
 create table public.tasks(id text primary key,title text,description text,created_at timestamptz default now(),updated_at timestamptz default now());
 ${primary?`create table public.attendance(id text primary key,site_id text,staff_id text,date date,punch_in_time timestamptz,punch_out_time timestamptz,status text,late_minutes integer,created_at timestamptz default now(),updated_at timestamptz default now());create table public.site_shift_policies(site_id text primary key,shift_start_time text,shift_end_time text,updated_at timestamptz default now());`:''}`);
 await db.exec(sql);
 await db.exec(await fs.readFile(repository+'/supabase/migrations/202611200004_legacy_attendance_timezone.sql','utf8'));
 await db.exec(await fs.readFile(repository+'/supabase/migrations/202611200005_legacy_shift_time_format.sql','utf8'));
 assert.equal((await db.query("select public.skcpl_attendance_instant('2026-11-20T09:00:00') as instant")).rows[0].instant.toISOString(),'2026-11-20T03:30:00.000Z');
 async function policy(site,start,end) {
  if(primary)await db.query('insert into public.site_shift_policies values($1,$2,$3,now()) on conflict(site_id) do update set shift_start_time=$2,shift_end_time=$3,updated_at=now()',[site,start,end]);
  else await db.query("insert into public.tasks values($1,$2,$3,now(),now()) on conflict(id) do update set description=$3,updated_at=now()",['policy-'+site,'SHIFT_POLICY:'+site,JSON.stringify({site_id:site,shift_start_time:start,shift_end_time:end})]);
 }
 async function record(id,site,entered,day,{out=null,legacy=false,created='2026-11-20T04:00:00Z'}={}) {
  const data={id,site_id:site,staff_id:'staff-'+id,date:day,punch_in_time:entered,punch_out_time:out,status:'presentLate',late_minutes:25,created_at:created,updated_at:created};
  if(primary && !legacy)await db.query('insert into public.attendance values($1,$2,$3,$4,$5,$6,$7,$8,$9,$9)',[id,site,data.staff_id,day,entered,out,data.status,25,created]);
  else await db.query('insert into public.tasks values($1,$2,$3,$4,$4)',['row-'+id,'ATTENDANCE:'+day+':'+site+':'+data.staff_id,JSON.stringify(data),created]);
 }
 async function digest() {
  const legacy=(await db.query("select id,title,description,created_at,updated_at from public.tasks where title like 'ATTENDANCE:%' order by id")).rows;
  const rows=primary?(await db.query('select * from public.attendance order by id')).rows:[];
  return JSON.stringify({legacy,rows});
 }
 const job=async(now)=>(await db.query('select public.skcpl_close_expired_attendance($1::timestamptz) result',[now])).rows[0].result;
 await policy('day','09.00','18.00');await policy('night','20.00','06.00');
 await record('day-one','day','2026-11-20T04:00:00Z','2026-11-20');
 await record('night-one','night','2026-11-20T14:30:00Z','2026-11-20');
 await record('completed','day','2026-11-20T04:00:00Z','2026-11-20',{out:'2026-11-20T12:30:00Z'});
 await record('historical-open','day','2026-11-18T04:00:00Z','2026-11-18',{created:'2026-11-18T04:00:00Z'});
 assert.equal((await job('2026-11-20T18:30:00Z')).enabled,false);
 await db.exec("update public.skcpl_attendance_reset_config set enabled=true,activated_at='2026-11-20T04:00:00Z';");
 const before=await digest();
 assert.equal((await job('2026-11-20T18:29:59Z')).closed,0);
 assert.equal((await job('2026-11-20T18:30:00Z')).closed,1);
 assert.equal((await job('2026-11-20T18:30:00Z')).closed,0);
 assert.equal((await db.query("select count(*)::int n from public.skcpl_attendance_sessions where attendance_id='historical-open'")).rows[0].n,0);
 assert.equal((await db.query("select count(*)::int n from public.skcpl_attendance_closures where attendance_id='completed'")).rows[0].n,0);
 assert.equal((await db.query("select cutoff_at,estimated from public.skcpl_attendance_closures where attendance_id='day-one'")).rows[0].estimated,true);
 // An Admin timing change must not shorten an overnight session already captured.
 await policy('night','20:00','05:00');
 assert.equal((await job('2026-11-21T00:00:00Z')).closed,0);
 assert.equal((await job('2026-11-21T00:30:00Z')).closed,1);
 assert.equal(await digest(),before);
 // Fresh overnight punches after midnight belong to the previous shift day.
 await policy('night','20:00','06:00');
 await record('night-after-midnight','night','2026-11-21T19:30:00+05:30','2026-11-21');
 await record('early-night','night',primary?'2026-11-21T01:00:00+05:30':'2026-11-21T01:00:00','2026-11-21');
 assert.equal(String((await db.query("select work_day::text from public.skcpl_attendance_sessions where attendance_id='early-night'")).rows[0].work_day).slice(0,10),'2026-11-20');
 assert.equal((await job('2026-11-21T00:30:00Z')).closed,1);
 const postInsert=await digest();await job('2026-11-22T04:00:00Z');assert.equal(await digest(),postInsert);
 // A broken policy cannot roll back a staff member's successful source insert.
 await policy('invalid','bogus','18:00');
 await record('bad-policy','invalid','2026-11-21T04:00:00Z','2026-11-21');
 assert.equal((await db.query("select count(*)::int n from public.skcpl_attendance_reset_errors where attendance_id='bad-policy'")).rows[0].n,1);
 // Metadata read privileges are separate from private capture/close authority.
 await db.exec('begin;set local role anon;select * from public.skcpl_attendance_closures;rollback;');
 for(const statement of ['select public.skcpl_close_expired_attendance()',"insert into public.skcpl_attendance_closures(attendance_id,punch_in_time,cutoff_at) values('x',now(),now())"]) {
  await db.exec('begin;set local role anon;');let denied=false;
  try{await db.exec(statement);}catch(error){denied=error.code==='42501';}
  await db.exec('rollback');assert.equal(denied,true);
 }
 const beforeGPS=await digest();
 // Isolated GPS schema checks: freshness, monotonic writes and least privilege.
 await db.exec(await fs.readFile(repository+'/supabase/migrations/202611200002_live_staff_location.sql','utf8'));
 await db.exec(`begin;set local role anon;
 insert into public.staff_live_locations(staff_id,staff_name,staff_role,site_id,site_name,latitude,longitude,accuracy_meters,is_within_site,distance_meters,timestamp)
 values('worker','Worker','Worker','site','Site',22.7,75.8,10,true,5,now()-interval '10 seconds');commit;`);
 const original=(await db.query('select timestamp::text from public.staff_live_locations')).rows[0].timestamp;
 await db.exec("update public.staff_live_locations set latitude=24,timestamp=now()-interval '15 seconds';");
 assert.equal((await db.query('select timestamp::text from public.staff_live_locations')).rows[0].timestamp,original);
 await db.exec("update public.staff_live_locations set latitude=22.71,timestamp=now();");
 assert.equal((await db.query('select latitude from public.staff_live_locations')).rows[0].latitude,22.71);
 for(const expression of ['accuracy_meters=999','latitude=91',"latitude='NaN'::float8","timestamp=now()+interval '1 hour'","timestamp=now()-interval '1 hour'"]) {
  await db.exec('begin;');let invalid=false;
  try{await db.exec(`insert into public.staff_live_locations select 'bad','Worker','Worker','site','Site',22.7,75.8,10,true,5,now(),null;update public.staff_live_locations set ${expression}${expression.startsWith('timestamp')?'':",timestamp=now()+interval '1 second'"} where staff_id='bad';`);}catch(error){invalid=error.code==='23514';}
  // Old updates are deliberately ignored by the monotonic guard, also safe.
  if(expression.includes("-interval"))invalid=(await db.query("select count(*)::int n from public.staff_live_locations where staff_id='bad' and timestamp>now()-interval '1 minute'")).rows[0].n===1;
  await db.exec('rollback');assert.equal(invalid,true,expression);
 }
 await db.exec('begin;set local role anon;');let deletionDenied=false;
 try{await db.exec('delete from public.staff_live_locations');}catch(error){deletionDenied=error.code==='42501';}
 await db.exec('rollback');assert.equal(deletionDenied,true);
 assert.equal(await digest(),beforeGPS);
 results.push({storage:primary?'primary attendance':'legacy task attendance',passed:true,attendanceChecks:14,gpsChecks:9});
 await db.close();
}
if(process.env.SKCPL_TEST_RESULTS) await fs.writeFile(process.env.SKCPL_TEST_RESULTS,JSON.stringify(results,null,2));
console.log(JSON.stringify(results));
