
create table if not exists public.academic_subject_services(
 subject_id uuid not null references public.academic_subjects(id) on delete restrict,
 service_type text not null check(service_type in ('lesson','homework','research','project')),
 primary key(subject_id,service_type)
);
alter table public.academic_subject_services enable row level security;
create policy "staff read academic subject services" on public.academic_subject_services for select to authenticated
using(exists(select 1 from public.staff_profiles p where p.user_id=(select auth.uid()) and p.is_active and p.deleted_at is null));
revoke all on public.academic_subject_services from anon,authenticated;
grant select on public.academic_subject_services to authenticated;

create or replace function public.manage_academic_directory(p_action text,p_kind text,p_id text,p_value text default null,p_subject uuid default null,p_service_type text default null)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare actor uuid:=auth.uid(); olddata jsonb; affected integer; item_name text;
begin
 if actor is null or not exists(select 1 from public.staff_profiles p where p.user_id=actor and p.role='super_admin' and p.is_active and p.deleted_at is null) then
 raise exception 'Academic directory management requires super admin';end if;
 if p_action='delete' and p_kind in ('university','college','major') then
   select to_jsonb(h) into olddata from public.academic_hierarchy h where h.id=p_id::bigint and h.level=p_kind for update;
   if olddata is null then raise exception 'Record not found';end if;
   if exists(select 1 from public.academic_hierarchy where parent_id=p_id::bigint) then raise exception 'Remove colleges or majors within this record first';end if;
   if exists(select 1 from public.academic_major_subjects where major_id=p_id::bigint) then raise exception 'Unlink the subjects from this major first';end if;
   delete from public.academic_hierarchy where id=p_id::bigint and level=p_kind;
 elseif p_action='delete' and p_kind='subject' then
   select to_jsonb(s) into olddata from public.academic_subjects s where s.id=p_id::uuid for update;
   if olddata is null then raise exception 'Record not found';end if;
   select olddata->>'subject_name' into item_name;
   if exists(select 1 from public.academic_major_subjects where subject_id=p_id::uuid)
     or exists(select 1 from public.person_subjects where subject_id=p_id::uuid)
     or exists(select 1 from public.study_groups where subject_id=p_id::uuid)
     or exists(select 1 from public.academic_subject_services where subject_id=p_id::uuid)
     or exists(select 1 from public.lessons where subject=item_name) then
      raise exception 'Subject is referenced by existing records; unlink related entries before deletion';
   end if;
   delete from public.academic_subjects where id=p_id::uuid;
 elseif p_kind='service' and p_action in ('link','unlink') then
   if p_subject is null or p_service_type not in ('lesson','homework','research','project') then raise exception 'Choose a subject and valid service type';end if;
   olddata:=jsonb_build_object('subject_id',p_subject,'service_type',p_service_type);
   if p_action='link' then
     insert into public.academic_subject_services(subject_id,service_type) values(p_subject,p_service_type) on conflict do nothing;
   else
     delete from public.academic_subject_services where subject_id=p_subject and service_type=p_service_type;
   end if;
 else raise exception 'Unsupported academic directory action';end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,before_data,after_data)
 values(actor,p_action,'academic_directory',coalesce(p_id,p_subject::text),olddata,jsonb_build_object('kind',p_kind,'value',p_value,'service_type',p_service_type));
 return jsonb_build_object('ok',true);
end $fn$;
revoke all on function public.manage_academic_directory(text,text,text,text,uuid,text) from public,anon;
grant execute on function public.manage_academic_directory(text,text,text,text,uuid,text) to authenticated;
do $$
declare n bigint;
begin
 select id into n from public.academic_hierarchy where level='university' and name='مقرر أوراق تجارية';
 if n is not null then
 if exists(select 1 from public.academic_hierarchy where parent_id=n) then raise exception 'Misclassified university has children; review manually';end if;
 insert into public.academic_subjects(subject_name) select 'مقرر أوراق تجارية'
 where not exists(select 1 from public.academic_subjects where subject_name='مقرر أوراق تجارية');
 delete from public.academic_hierarchy where id=n;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
 values(null,'correct_academic_classification','academic_directory',n::text,jsonb_build_object('former_level','university','new_level','subject','name','مقرر أوراق تجارية'));
 end if;
end $$;