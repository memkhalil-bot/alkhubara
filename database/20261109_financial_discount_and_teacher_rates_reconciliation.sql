-- Applied to Supabase project alkhubara on 2026-11-09.
-- Allows first teacher-rate configuration after invoicing, and bases payment status/collection on invoice net amounts.
CREATE OR REPLACE FUNCTION experts_private.lock_invoiced_lesson_rates()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 IF EXISTS (SELECT 1 FROM public.invoices i WHERE i.lesson_id = OLD.lesson_id) THEN
   IF TG_OP = 'DELETE' THEN
     RAISE EXCEPTION 'Invoiced lesson rates cannot be deleted';
   END IF;
   IF NEW.student_hourly_rate IS DISTINCT FROM OLD.student_hourly_rate
      OR (NEW.teacher_hourly_rate IS DISTINCT FROM OLD.teacher_hourly_rate AND NOT (
        OLD.teacher_hourly_rate = 0 AND NEW.teacher_hourly_rate > 0
        AND experts_private.has_permission('pricing.edit')
      )) THEN
     RAISE EXCEPTION 'Invoiced lesson rates cannot be changed without an approved adjustment';
   END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION experts_private.enforce_lesson_receipt_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare due numeric;paid numeric;expected text;
begin
 if TG_OP='INSERT' and new.payment_status<>'unpaid' then raise exception 'Payment must start unpaid';end if;
 if TG_OP='UPDATE' and new.payment_status is distinct from old.payment_status then
  select coalesce(sum(coalesce(i.amount,lp.price)),0) into due
  from public.lesson_participants lp left join public.invoices i on i.lesson_id=lp.lesson_id and i.student_id=lp.student_id
  where lp.lesson_id=new.id;
  if due<=0 then raise exception 'Lesson needs participants and prices';end if;
  select coalesce(sum(a.amount),0) into paid from public.receipt_allocations a
  join public.financial_entries f on f.id=a.receipt_id and f.entry_type='receipt'
  join public.invoices i on i.id=a.invoice_id
  where i.lesson_id=new.id and not exists(select 1 from public.financial_entries rev where rev.reverses_entry_id=f.id);
  expected:=case when paid<=0 then 'unpaid' when paid>=due then 'paid' else 'partial' end;
  if new.payment_status<>expected then raise exception 'Payment status inconsistent with total student receivables';end if;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.collect_group_lesson_payment(p_lesson_id uuid, p_student_id uuid, p_amount numeric, p_method text, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid:=auth.uid();lesson public.lessons%rowtype;bill public.invoices%rowtype;rate numeric;prior numeric;receipt uuid;paid_total integer;members_total integer;
begin
 if actor is null or not(experts_private.has_permission('finance.edit') and experts_private.has_permission('invoices.create') and experts_private.has_permission('invoices.allocate')) then raise exception 'Finance permissions required';end if;
 if p_amount is null or p_amount<=0 or p_method not in ('cash','card','bank','cheque','other') then raise exception 'Invalid receipt';end if;
 select * into lesson from public.lessons where id=p_lesson_id for update;
 if not found or lesson.status<>'completed' or lesson.is_archived then raise exception 'Only completed lessons may be collected';end if;
 select price into rate from public.lesson_participants where lesson_id=p_lesson_id and student_id=p_student_id;
 if rate is null then raise exception 'Student is not part of lesson';end if;
 select * into bill from public.invoices where lesson_id=p_lesson_id and student_id=p_student_id for update;
 if not found then
 insert into public.invoices(student_id,lesson_id,amount,created_by)
 values(p_student_id,p_lesson_id,rate,actor) returning * into bill;
 end if;
 select coalesce(sum(a.amount),0) into prior from public.receipt_allocations a
 join public.financial_entries f on f.id=a.receipt_id where a.invoice_id=bill.id and f.entry_type='receipt'
 and not exists(select 1 from public.financial_entries rev where rev.reverses_entry_id=f.id);
 if p_amount>bill.amount-prior then raise exception 'Payment exceeds outstanding balance';end if;
 insert into public.financial_entries(entry_date,entry_type,student_id,amount,payment_method,category,description,reference_number,created_by)
 values(current_date,'receipt',p_student_id,p_amount,p_method,'تحصيل حصة','تحصيل حصة جماعية / فردية',nullif(trim(p_reference),''),actor) returning id into receipt;
 insert into public.receipt_allocations(receipt_id,invoice_id,amount,created_by) values(receipt,bill.id,p_amount,actor);
 select count(*) into members_total from public.lesson_participants where lesson_id=p_lesson_id;
 select count(*) into paid_total from public.lesson_participants lp where lp.lesson_id=p_lesson_id and
 (select coalesce(sum(a.amount),0) from public.invoices i join public.receipt_allocations a on a.invoice_id=i.id join public.financial_entries f on f.id=a.receipt_id
 where i.lesson_id=p_lesson_id and i.student_id=lp.student_id and f.entry_type='receipt'
 and not exists(select 1 from public.financial_entries rev where rev.reverses_entry_id=f.id)) >= coalesce((select i.amount from public.invoices i where i.lesson_id=p_lesson_id and i.student_id=lp.student_id),lp.price);
 perform set_config('experts.approved_receipt','yes',true);
 update public.lessons set payment_status=case when paid_total=members_total then 'paid' else 'partial' end,updated_by=actor where id=p_lesson_id;
 return jsonb_build_object('invoice_id',bill.id,'receipt_id',receipt,'remaining',bill.amount-prior-p_amount);
end $function$;
