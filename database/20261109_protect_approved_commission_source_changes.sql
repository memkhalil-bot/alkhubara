create or replace function experts_private.protect_teacher_commission_source()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare source_kind text;
begin
 source_kind:=case when tg_table_name='lessons' then 'lesson' else 'homework' end;
 if exists(select 1 from public.teacher_commission_earnings e where e.source_type=source_kind and e.source_id=old.id) then
  if new.teacher_id is distinct from old.teacher_id or new.status<>'completed' or new.is_archived
   or (source_kind='homework' and (new.service_type is distinct from old.service_type or new.student_id is distinct from old.student_id))
  then raise exception 'Approved teacher commission is locked; use a documented financial adjustment';end if;
 end if;
 return new;
end $fn$;
drop trigger if exists protect_lesson_commission_snapshot on public.lessons;
create trigger protect_lesson_commission_snapshot before update on public.lessons
for each row execute function experts_private.protect_teacher_commission_source();
drop trigger if exists protect_homework_commission_snapshot on public.educational_services;
create trigger protect_homework_commission_snapshot before update on public.educational_services
for each row execute function experts_private.protect_teacher_commission_source();