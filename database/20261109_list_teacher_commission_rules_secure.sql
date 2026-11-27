create or replace function public.list_teacher_commission_rules()
returns jsonb language plpgsql security definer set search_path='' as $fn$
begin
 if auth.uid() is null or not (experts_private.has_permission('teacher_commissions.view') or experts_private.has_permission('teacher_commissions.edit')) then
 raise exception 'Commission view permission required';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.full_name,'code',t.teacher_code,'lesson',l.center_percent,'homework',h.center_percent) order by t.full_name),'[]'::jsonb)
 from public.teachers t left join public.teacher_commission_rules l on l.teacher_id=t.id and l.category='lesson'
 left join public.teacher_commission_rules h on h.teacher_id=t.id and h.category='homework'
 where not t.is_archived);
end $fn$;
revoke all on function public.list_teacher_commission_rules() from public,anon;
grant execute on function public.list_teacher_commission_rules() to authenticated;