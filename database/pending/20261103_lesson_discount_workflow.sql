
-- Discount request workflow. Keep lesson_participants.price as original catalog/contract price.
CREATE TABLE IF NOT EXISTS public.lesson_discount_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 lesson_id uuid NOT NULL REFERENCES public.lessons(id) ON DELETE RESTRICT,
 discount_percent numeric(5,2) NOT NULL CHECK(discount_percent>0 AND discount_percent<=99),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 1000),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
 requested_by uuid NOT NULL REFERENCES auth.users(id),
 requested_at timestamptz NOT NULL DEFAULT now(),
 reviewed_by uuid REFERENCES auth.users(id),
 reviewed_at timestamptz,
 review_note text,
 CONSTRAINT discount_review_consistency CHECK (
 (status='pending' AND reviewed_by IS NULL AND reviewed_at IS NULL)
 OR (status<>'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
 )
);
CREATE UNIQUE INDEX IF NOT EXISTS lesson_one_pending_discount
 ON public.lesson_discount_requests(lesson_id) WHERE status='pending';
CREATE UNIQUE INDEX IF NOT EXISTS lesson_one_approved_discount
 ON public.lesson_discount_requests(lesson_id) WHERE status='approved';
CREATE INDEX IF NOT EXISTS lesson_discount_status ON public.lesson_discount_requests(status,requested_at DESC);
ALTER TABLE public.lesson_discount_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lesson_discount_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.lesson_discount_requests TO authenticated;
CREATE POLICY lesson_discount_read ON public.lesson_discount_requests FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.staff_profiles sp WHERE sp.user_id=auth.uid() AND sp.is_active AND sp.deleted_at IS NULL
 AND ((sp.role IN ('admin','super_admin'))
 OR (sp.teacher_id=(SELECT l.teacher_id FROM public.lessons l WHERE l.id=lesson_id))))
);
-- Do not allow direct client INSERT/UPDATE; all changes pass through security-definer RPCs.
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS original_amount numeric(14,2);
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS discount_percent numeric(5,2) NOT NULL DEFAULT 0;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS discount_amount numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS discount_request_id uuid REFERENCES public.lesson_discount_requests(id);
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS discount_approved_by uuid REFERENCES auth.users(id);
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS discount_approved_at timestamptz;
UPDATE public.invoices SET original_amount=amount WHERE original_amount IS NULL;
ALTER TABLE public.invoices ADD CONSTRAINT invoice_discount_totals_valid CHECK (
 original_amount IS NOT NULL AND original_amount>0 AND discount_amount>=0
 AND amount>=0 AND amount=original_amount-discount_amount
 AND discount_percent>=0 AND discount_percent<=99
 AND ((discount_percent=0 AND discount_amount=0 AND discount_approved_by IS NULL AND discount_approved_at IS NULL)
 OR (discount_percent>0 AND discount_approved_by IS NOT NULL AND discount_approved_at IS NOT NULL))
);
CREATE OR REPLACE FUNCTION public.request_lesson_discount(p_lesson_id uuid,p_percent numeric,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE actor uuid:=auth.uid(); teacher uuid; linked uuid; role_name text; rid uuid;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'Login required'; END IF;
 SELECT role,teacher_id INTO role_name,linked FROM public.staff_profiles WHERE user_id=actor AND is_active AND deleted_at IS NULL;
 SELECT teacher_id INTO teacher FROM public.lessons WHERE id=p_lesson_id AND NOT is_archived AND status<>'cancelled' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Lesson is unavailable'; END IF;
 IF NOT (role_name IN ('super_admin','admin') OR (linked=teacher AND experts_private.has_permission('teacher.portal')))
 THEN RAISE EXCEPTION 'Not permitted to request this discount'; END IF;
 IF p_percent IS NULL OR p_percent<=0 OR p_percent>99 OR p_percent<>round(p_percent,2)
 OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 5 AND 1000
 THEN RAISE EXCEPTION 'Invalid discount or missing reason'; END IF;
 IF EXISTS(SELECT 1 FROM public.lesson_discount_requests WHERE lesson_id=p_lesson_id AND status IN ('pending','approved'))
 THEN RAISE EXCEPTION 'An active or approved discount already exists'; END IF;
 INSERT INTO public.lesson_discount_requests(lesson_id,discount_percent,reason,requested_by)
 VALUES(p_lesson_id,p_percent,btrim(p_reason),actor) RETURNING id INTO rid;
 INSERT INTO public.notifications(recipient_id,actor_id,event_type,title,message,target_path,related_id)
 SELECT sp.user_id,actor,'discount.request','طلب خصم حصة بانتظار الاعتماد',
 'خصم مطلوب بنسبة '||p_percent||'% للحصة؛ راجع السبب والسعر الأصلي قبل الاعتماد.',
 'discounts.html',rid::text
 FROM public.staff_profiles sp WHERE sp.role IN ('admin','super_admin') AND sp.is_active AND sp.deleted_at IS NULL AND sp.user_id<>actor;
 INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
 VALUES(actor,'request','lesson_discount_requests',rid::text,jsonb_build_object('lesson_id',p_lesson_id,'percent',p_percent));
 RETURN rid;
END $$;
REVOKE ALL ON FUNCTION public.request_lesson_discount(uuid,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.request_lesson_discount(uuid,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.review_lesson_discount(p_request uuid,p_approve boolean,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE actor uuid:=auth.uid(); r public.lesson_discount_requests%ROWTYPE;
        inv record; net numeric; amount_original numeric; reviewed timestamptz:=now(); changed int:=0;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.staff_profiles
 WHERE user_id=actor AND is_active AND deleted_at IS NULL AND role IN ('admin','super_admin'))
 THEN RAISE EXCEPTION 'Manager approval required'; END IF;
 SELECT * INTO r FROM public.lesson_discount_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR r.status<>'pending' THEN RAISE EXCEPTION 'Discount request is no longer pending'; END IF;
 IF p_approve IS NULL THEN RAISE EXCEPTION 'Decision required'; END IF;
 IF r.requested_by=actor THEN RAISE EXCEPTION 'Discount request needs a different approver'; END IF;
 PERFORM 1 FROM public.lessons WHERE id=r.lesson_id AND NOT is_archived AND status<>'cancelled' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Lesson is cancelled or archived'; END IF;
 IF p_approve THEN
   -- If payments have been allocated, a separate credit-note workflow is required.
   IF EXISTS(SELECT 1 FROM public.invoices i JOIN public.receipt_allocations a ON a.invoice_id=i.id
             WHERE i.lesson_id=r.lesson_id)
   THEN RAISE EXCEPTION 'Invoice already has receipt allocations; financial adjustment is required'; END IF;
   UPDATE public.lesson_discount_requests SET status='approved',reviewed_by=actor,reviewed_at=reviewed,review_note=nullif(btrim(p_note),'') WHERE id=r.id;
   FOR inv IN SELECT i.id,i.student_id,lp.price FROM public.invoices i
     JOIN public.lesson_participants lp ON lp.lesson_id=i.lesson_id AND lp.student_id=i.student_id
     WHERE i.lesson_id=r.lesson_id FOR UPDATE OF i
   LOOP
     amount_original:=round(inv.price,2);
     net:=round(amount_original*(100-r.discount_percent)/100,2);
     UPDATE public.invoices SET original_amount=amount_original,discount_percent=r.discount_percent,
       discount_amount=amount_original-net,amount=net,discount_request_id=r.id,
       discount_approved_by=actor,discount_approved_at=reviewed WHERE id=inv.id;
     INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
     VALUES(actor,'approve_discount','invoices',inv.id::text,
       jsonb_build_object('original',amount_original,'percent',r.discount_percent,'net',net,'request_id',r.id));
     changed:=changed+1;
   END LOOP;
 ELSE
   UPDATE public.lesson_discount_requests SET status='rejected',reviewed_by=actor,
      reviewed_at=reviewed,review_note=nullif(btrim(p_note),'') WHERE id=r.id;
 END IF;
 INSERT INTO public.notifications(recipient_id,actor_id,event_type,title,message,target_path,related_id)
 SELECT sp.user_id,actor,CASE WHEN p_approve THEN 'discount.approved' ELSE 'discount.rejected' END,
 CASE WHEN p_approve THEN 'تم اعتماد الخصم' ELSE 'تم رفض الخصم' END,
 'طلب خصم الحصة بنسبة '||r.discount_percent||'% · '||coalesce(nullif(btrim(p_note),''),'بدون ملاحظات'),
 'discounts.html',r.id::text
 FROM public.staff_profiles sp
 WHERE sp.is_active AND sp.deleted_at IS NULL AND sp.user_id<>actor
 AND (sp.user_id=r.requested_by OR sp.teacher_id=(SELECT teacher_id FROM public.lessons WHERE id=r.lesson_id)
 OR (p_approve AND EXISTS(SELECT 1 FROM public.user_permissions up WHERE up.user_id=sp.user_id AND up.permission IN ('finance.view','finance.edit'))));
 INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
 VALUES(actor,CASE WHEN p_approve THEN 'approve' ELSE 'reject' END,
 'lesson_discount_requests',r.id::text,jsonb_build_object('percent',r.discount_percent,'note',p_note,'invoice_count',changed));
 RETURN jsonb_build_object('status',CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,'affected_invoices',changed);
END $$;
REVOKE ALL ON FUNCTION public.review_lesson_discount(uuid,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.review_lesson_discount(uuid,boolean,text) TO authenticated;

-- Invoice snapshot: original per-student price is retained; net amount is collectible.
CREATE OR REPLACE FUNCTION experts_private.check_invoice_insert() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE source_status text; archived boolean; price numeric; discount_row public.lesson_discount_requests%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NEW.created_by IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Invalid issuer'; END IF;
 IF NEW.lesson_id IS NOT NULL THEN
  SELECT l.status,l.is_archived,lp.price INTO source_status,archived,price
  FROM public.lessons l JOIN public.lesson_participants lp ON lp.lesson_id=l.id AND lp.student_id=NEW.student_id
  WHERE l.id=NEW.lesson_id;
  IF source_status NOT IN ('confirmed','completed') OR archived IS DISTINCT FROM false OR price IS NULL OR price<=0 THEN
    RAISE EXCEPTION 'Only confirmed/completed and priced lessons may be invoiced';
  END IF;
  SELECT * INTO discount_row FROM public.lesson_discount_requests
    WHERE lesson_id=NEW.lesson_id AND status='approved';
 ELSE
  SELECT s.status,s.is_archived,r.amount INTO source_status,archived,price
  FROM public.educational_services s LEFT JOIN public.service_prices r ON r.service_id=s.id
  WHERE s.id=NEW.service_id AND s.student_id=NEW.student_id;
  IF source_status<>'completed' OR archived IS DISTINCT FROM false OR price IS NULL OR price<=0 THEN
    RAISE EXCEPTION 'Only completed and priced services may be invoiced';
  END IF;
 END IF;
 NEW.original_amount:=round(price,2);
 IF NEW.lesson_id IS NOT NULL AND discount_row.id IS NOT NULL THEN
   NEW.discount_percent:=discount_row.discount_percent;
   NEW.amount:=round(NEW.original_amount*(100-discount_row.discount_percent)/100,2);
   NEW.discount_amount:=NEW.original_amount-NEW.amount;
   NEW.discount_request_id:=discount_row.id;
   NEW.discount_approved_by:=discount_row.reviewed_by;
   NEW.discount_approved_at:=discount_row.reviewed_at;
 ELSE
   NEW.amount:=NEW.original_amount;
   NEW.discount_percent:=0; NEW.discount_amount:=0;
   NEW.discount_request_id:=NULL; NEW.discount_approved_by:=NULL; NEW.discount_approved_at:=NULL;
 END IF;
 INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
 VALUES(auth.uid(),'create','invoices',NEW.id::text,to_jsonb(NEW));
 RETURN NEW;
END $$;
