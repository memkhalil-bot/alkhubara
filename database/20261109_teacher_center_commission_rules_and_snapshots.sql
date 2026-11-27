
alter table public.educational_services add column if not exists teacher_id uuid references public.teachers(id);
create table if not exists public.teacher_commission_rules (
 teacher_id uuid not null references public.teachers(id),
 category text not null check(category in ('lesson','homework')),
 center_percent numeric(5,2) not null check(center_percent between 0 and 100),
 updated_by uuid references auth.users(id), updated_at timestamptz not null default now(),
 primary key(teacher_id,category)
);
create table if not exists public.teacher_commission_earnings (
 source_type text not null check(source_type in ('lesson','homework')),
 source_id uuid not null,
 teacher_id uuid not null references public.teachers(id),
 gross_amount numeric(14,2) not null check(gross_amount>0),
 center_percent numeric(5,2) not null check(center_percent between 0 and 100),
 teacher_percent numeric(5,2) not null check(teacher_percent between 0 and 100),
 center_amount numeric(14,2) not null check(center_amount>=0),
 teacher_amount numeric(14,2) not null check(teacher_amount>=0),
 earned_at timestamptz not null default now(),
 created_by uuid references auth.users(id),
 primary key(source_type,source_id),
 constraint split_exact check (gross_amount=center_amount+teacher_amount and center_percent+teacher_percent=100)
);
create index if not exists teacher_commission_earnings_teacher_idx on public.teacher_commission_earnings(teacher_id);
alter table public.teacher_commission_rules enable row level security;
alter table public.teacher_commission_earnings enable row level security;
create policy "commission rules authorized read" on public.teacher_commission_rules for select to authenticated
 using (experts_private.has_permission('teacher_commissions.view') or experts_private.has_permission('teacher_commissions.edit'));
create policy "commission earnings authorized read" on public.teacher_commission_earnings for select to authenticated
 using (experts_private.has_permission('teacher_commissions.view') or experts_private.has_permission('teacher_commissions.edit'));
revoke all on public.teacher_commission_rules from anon,authenticated;
revoke all on public.teacher_commission_earnings from anon,authenticated;
grant select on public.teacher_commission_rules,public.teacher_commission_earnings to authenticated;

create or replace function public.set_teacher_commission_rule(p_teacher uuid,p_category text,p_center_percent numeric)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare actor uuid:=auth.uid(); old jsonb; fresh jsonb;
begin
 if actor is null or not experts_private.has_permission('teacher_commissions.edit') then raise exception 'Commission edit permission required';end if;
 if p_category not in ('lesson','homework') or p_center_percent is null or p_center_percent<0 or p_center_percent>100 or p_center_percent<>round(p_center_percent,2) then raise exception 'Invalid category or percentage';end if;
 if not exists(select 1 from public.teachers where id=p_teacher and not is_archived) then raise exception 'Teacher not found';end if;
 select to_jsonb(r) into old from public.teacher_commission_rules r where teacher_id=p_teacher and category=p_category;
 insert into public.teacher_commission_rules(teacher_id,category,center_percent,updated_by)
 values(p_teacher,p_category,p_center_percent,actor)
 on conflict (teacher_id,category) do update set center_percent=excluded.center_percent,updated_by=actor,updated_at=now();
 select to_jsonb(r) into fresh from public.teacher_commission_rules r where teacher_id=p_teacher and category=p_category;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,before_data,after_data)
 values(actor,'update','teacher_commission_rules',p_teacher::text||':'||p_category,old,fresh);
 return fresh;
end $fn$;
revoke all on function public.set_teacher_commission_rule(uuid,text,numeric) from public,anon;
grant execute on function public.set_teacher_commission_rule(uuid,text,numeric) to authenticated;

create or replace function experts_private.capture_teacher_commission()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare actor uuid:=auth.uid(); kind text; entity uuid; teacher uuid; amount numeric; percentage numeric; center_amount numeric;
begin
 if new.status<>'completed' or new.is_archived then return new;end if;
 if tg_table_name='lessons' then
  kind:='lesson';entity:=new.id;teacher:=new.teacher_id;
  select coalesce(sum(i.amount),0) into amount from public.invoices i where i.lesson_id=entity;
 else
  if new.service_type<>'homework' then return new;end if;
  kind:='homework';entity:=new.id;teacher:=new.teacher_id;
  select coalesce(sum(i.amount),0) into amount from public.invoices i where i.service_id=entity;
 end if;
 if exists(select 1 from public.teacher_commission_earnings e where e.source_type=kind and e.source_id=entity) then return new;end if;
 if teacher is null then raise exception 'Assign a teacher before completing homework';end if;
 select r.center_percent into percentage from public.teacher_commission_rules r where r.teacher_id=teacher and r.category=kind;
 if percentage is null then raise exception 'Set the center percentage for this teacher and type before completing';end if;
 if amount<=0 then raise exception 'Issue a positive invoice before completing the lesson or homework';end if;
 center_amount:=round(amount*percentage/100,2);
 insert into public.teacher_commission_earnings(source_type,source_id,teacher_id,gross_amount,center_percent,teacher_percent,center_amount,teacher_amount,created_by)
 values(kind,entity,teacher,round(amount,2),percentage,100-percentage,center_amount,round(amount,2)-center_amount,actor)
 on conflict(source_type,source_id) do nothing;
 return new;
end $fn$;
drop trigger if exists zz_capture_lesson_commission on public.lessons;
create constraint trigger zz_capture_lesson_commission after insert or update on public.lessons deferrable initially deferred
for each row execute function experts_private.capture_teacher_commission();
drop trigger if exists zz_capture_homework_commission on public.educational_services;
create constraint trigger zz_capture_homework_commission after insert or update on public.educational_services deferrable initially deferred
for each row execute function experts_private.capture_teacher_commission();
CREATE OR REPLACE FUNCTION public.manage_staff_permissions(target_user uuid, new_permissions text[], new_full_name text, enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid; previous jsonb; new_data jsonb;
begin
 actor:=auth.uid();
 if actor is null or not exists(select 1 from public.staff_profiles p where p.user_id=actor and p.role='super_admin' and p.is_active) then raise exception 'Unauthorized'; end if;
 if not exists(select 1 from public.staff_profiles p where p.user_id=target_user) then raise exception 'Unknown staff account'; end if;
 if exists(select 1 from public.staff_profiles p where p.user_id=target_user and p.role='super_admin') then raise exception 'Super admin account is protected'; end if;
 if length(trim(new_full_name))<2 or length(trim(new_full_name))>200 then raise exception 'Invalid full name'; end if;
 if new_permissions is null or exists(select 1 from unnest(new_permissions) x where x not in (
 'students.view','students.edit','teachers.view','teachers.edit',
 'lessons.view','lessons.edit','services.view','services.edit',
 'finance.view','finance.edit','pricing.view','pricing.edit',
 'invoices.view','invoices.create','invoices.allocate',
 'reports.view','audit.view','executive.view','groups.view','groups.edit','teacher.portal','contacts.reveal','teacher_commissions.view','teacher_commissions.edit'
 )) then raise exception 'Invalid permission selection';end if;
 select to_jsonb(p) into previous from public.staff_profiles p where p.user_id=target_user for update;
 update public.staff_profiles set full_name=trim(new_full_name),is_active=enabled,updated_at=now() where user_id=target_user;
 delete from public.user_permissions where user_id=target_user;
 insert into public.user_permissions(user_id,permission,granted_by)
 select target_user,distinct_perm,actor from (select distinct unnest(new_permissions) as distinct_perm) keys;
 select jsonb_build_object('profile',(select to_jsonb(p) from public.staff_profiles p where p.user_id=target_user),
 'permissions',(select coalesce(jsonb_agg(permission),'[]'::jsonb) from public.user_permissions where user_id=target_user)) into new_data;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,before_data,after_data)
 values(actor,'update','staff_permissions',target_user::text,previous,new_data);
 return new_data;
end $function$;