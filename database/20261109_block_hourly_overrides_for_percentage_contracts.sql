CREATE OR REPLACE FUNCTION experts_private.pricing_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid; rowid text;
begin
 actor:=auth.uid();
 if actor is null then raise exception 'Authenticated actor required'; end if;
 if TG_TABLE_NAME='lesson_rates' then
   rowid:=new.lesson_id::text;
   if TG_OP='UPDATE' and new.lesson_id is distinct from old.lesson_id then raise exception 'Immutable lesson ID'; end if;
   if TG_OP='UPDATE' and new.teacher_hourly_rate is distinct from old.teacher_hourly_rate and exists(
      select 1 from public.lessons l join public.teacher_commission_rules cr on cr.teacher_id=l.teacher_id and cr.category='lesson'
      where l.id=new.lesson_id
   ) then raise exception 'Teacher earnings use center percentage rules. Do not override the hourly rate';end if;
 elsif TG_TABLE_NAME='service_prices' then
   rowid:=new.service_id::text;
   if TG_OP='UPDATE' and new.service_id is distinct from old.service_id then raise exception 'Immutable service ID'; end if;
 else raise exception 'Unsupported pricing table'; end if;
 if TG_OP='UPDATE' then
   if new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then raise exception 'Immutable pricing fields'; end if;
 end if;
 new.updated_at:=now();new.updated_by:=actor;
 if TG_OP='INSERT' then
   new.created_by:=actor;
   insert into public.audit_logs(actor_id,action,entity_type,entity_id,after_data) values(actor,'create',TG_TABLE_NAME,rowid,to_jsonb(new));
 else
   insert into public.audit_logs(actor_id,action,entity_type,entity_id,before_data,after_data) values(actor,'update',TG_TABLE_NAME,rowid,to_jsonb(old),to_jsonb(new));
 end if;
 return new;
end $function$
;