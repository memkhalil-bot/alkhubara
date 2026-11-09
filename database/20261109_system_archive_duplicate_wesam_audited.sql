do $$
declare source uuid:='c65a3d68-5cfb-4cec-a0e3-a6a31748a274'; target uuid:='c0ec3fd8-7e21-4fa6-ad55-b551d93bf2a6'; before_row jsonb; after_row jsonb;
begin
 if not exists(select 1 from public.teachers where id=source and teacher_code=20010 and not is_archived)
 or not exists(select 1 from public.teachers where id=target and teacher_code=20005 and not is_archived)
 then raise exception 'Expected teacher codes not found';end if;
 if exists(select 1 from public.lessons where teacher_id=source)
 or exists(select 1 from public.financial_entries where teacher_id=source)
 or exists(select 1 from public.staff_profiles where teacher_id=source)
 or exists(select 1 from public.study_groups where teacher_id=source)
 or exists(select 1 from public.educational_services where teacher_id=source)
 or exists(select 1 from public.teacher_commission_rules where teacher_id=source)
 or exists(select 1 from public.teacher_commission_earnings where teacher_id=source) then
 raise exception 'Unexpected financial or personnel dependencies';end if;
 select to_jsonb(t) into before_row from public.teachers t where id=source;
 insert into public.person_subjects(person_kind,person_id,subject_id)
 select 'teachers',target,ps.subject_id from public.person_subjects ps where ps.person_kind='teachers' and ps.person_id=source
 on conflict do nothing;
 delete from public.person_subjects where person_kind='teachers' and person_id=source;
 alter table public.teachers disable trigger teachers_audit;
 update public.teachers set is_archived=true,updated_at=now() where id=source;
 alter table public.teachers enable trigger teachers_audit;
 select to_jsonb(t) into after_row from public.teachers t where id=source;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,before_data,after_data)
 values(null,'system_archive_duplicate_teacher','teachers',source::text,before_row,after_row||jsonb_build_object('retained_teacher_id',target,'transfer','2 subject assignments','reason','One-off verified administrative deduplication'));
end $$;