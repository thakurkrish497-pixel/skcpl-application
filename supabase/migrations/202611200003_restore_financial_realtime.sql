begin;
set local lock_timeout='2s';
do $$
declare relation text;
begin
 if not exists(select 1 from pg_publication where pubname='supabase_realtime') then
  raise exception 'Realtime publication missing; stop for review';
 end if;
 if not exists(select 1 from pg_publication where pubname='supabase_realtime' and puballtables) then
  foreach relation in array array['cash_transactions','stock_transactions','sites'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=relation) then
    execute format('alter publication supabase_realtime add table public.%I',relation);
   end if;
  end loop;
 end if;
end;$$;
commit;
select tablename from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' order by tablename;
