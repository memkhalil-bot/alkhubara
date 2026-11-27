alter table public.educational_services add column if not exists academic_subject_id uuid references public.academic_subjects(id) on delete restrict;
create index if not exists academic_services_subject_idx on public.educational_services(academic_subject_id);
create or replace function experts_private.validate_service_subject()
returns trigger language plpgsql set search_path='' as $fn$
begin
 if new.academic_subject_id is not null and new.service_type in ('homework','research','project') and not exists (
 select 1 from public.academic_subject_services s where s.subject_id=new.academic_subject_id and s.service_type=new.service_type
 ) then raise exception 'Subject is not enabled for this service type in the academic directory';end if;
 return new;
end $fn$;
drop trigger if exists validate_service_subject on public.educational_services;
create trigger validate_service_subject before insert or update of academic_subject_id,service_type on public.educational_services
for each row execute function experts_private.validate_service_subject();