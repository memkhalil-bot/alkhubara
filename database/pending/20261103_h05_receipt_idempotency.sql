-- ALKHUBARA H-05: DRAFT TRANSACTIONAL RECEIPT + IDEMPOTENCY
-- NOT APPLIED: validate against production schema and existing finance_audit_guard
-- on isolated staging before any migration or frontend switch.
-- Designed for PostgreSQL 15+; Security-definer routines qualify all relations.
CREATE TABLE IF NOT EXISTS public.receipt_requests (
 request_key uuid PRIMARY KEY,
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 student_id uuid NOT NULL REFERENCES public.students(id),
 amount numeric(14,2) NOT NULL CHECK (amount > 0),
 payment_method text NOT NULL,
 reference_number text,
 invoice_id uuid REFERENCES public.invoices(id),
 receipt_id uuid UNIQUE REFERENCES public.financial_entries(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.receipt_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.receipt_requests FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_receipt_v2(
 p_key uuid, p_student uuid, p_amount numeric, p_method text,
 p_reference text DEFAULT NULL, p_invoice uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
 v_actor uuid := auth.uid();
 v_existing public.receipt_requests%ROWTYPE;
 v_invoice public.invoices%ROWTYPE;
 v_receipt uuid;
 v_paid numeric(14,2);
 v_ref text := nullif(btrim(p_reference),'');
BEGIN
 IF v_actor IS NULL OR NOT experts_private.has_permission('finance.edit') THEN
   RAISE EXCEPTION 'Finance edit permission required';
 END IF;
 IF p_key IS NULL OR p_student IS NULL OR p_amount IS NULL
 OR p_amount<=0 OR p_amount<>round(p_amount,2)
 OR p_method NOT IN ('cash','card','bank','cheque','other')
 OR (p_method <> 'cash' AND v_ref IS NULL)
 THEN RAISE EXCEPTION 'Invalid receipt request'; END IF;
 IF p_invoice IS NOT NULL AND
 NOT (experts_private.has_permission('invoices.allocate'))
 THEN RAISE EXCEPTION 'Invoice allocation permission required'; END IF;
 -- Lock identical request, including concurrent retries, via unique request key.
 INSERT INTO public.receipt_requests
   (request_key,actor_id,student_id,amount,payment_method,reference_number,invoice_id)
 VALUES (p_key,v_actor,p_student,p_amount,p_method,v_ref,p_invoice)
 ON CONFLICT (request_key) DO NOTHING;
 SELECT * INTO v_existing FROM public.receipt_requests WHERE request_key=p_key FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Request lock unavailable'; END IF;
 IF v_existing.actor_id IS DISTINCT FROM v_actor
 OR v_existing.student_id IS DISTINCT FROM p_student
 OR v_existing.amount IS DISTINCT FROM p_amount
 OR v_existing.payment_method IS DISTINCT FROM p_method
 OR v_existing.reference_number IS DISTINCT FROM v_ref
 OR v_existing.invoice_id IS DISTINCT FROM p_invoice
 THEN RAISE EXCEPTION 'Idempotency key reused with different receipt details'; END IF;
 IF v_existing.receipt_id IS NOT NULL THEN
   RETURN jsonb_build_object('receipt_id',v_existing.receipt_id,'duplicate',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.students WHERE id=p_student AND NOT is_archived)
 THEN RAISE EXCEPTION 'Invalid student'; END IF;
 IF p_invoice IS NOT NULL THEN
   SELECT * INTO v_invoice FROM public.invoices WHERE id=p_invoice FOR UPDATE;
   IF NOT FOUND OR v_invoice.student_id<>p_student THEN
     RAISE EXCEPTION 'Invoice and student mismatch';
   END IF;
   SELECT COALESCE(SUM(a.amount),0) INTO v_paid
   FROM public.receipt_allocations a
   JOIN public.financial_entries f ON f.id=a.receipt_id
   WHERE a.invoice_id=p_invoice AND f.entry_type='receipt'
    AND NOT EXISTS (SELECT 1 FROM public.financial_entries rev
       WHERE rev.reverses_entry_id=f.id);
   IF p_amount>v_invoice.amount-v_paid THEN
      RAISE EXCEPTION 'Receipt exceeds invoice balance';
   END IF;
 END IF;
 INSERT INTO public.financial_entries
  (entry_date,entry_type,student_id,amount,payment_method,category,description,
   reference_number,created_by)
 VALUES ((now() AT TIME ZONE 'Asia/Qatar')::date,'receipt',p_student,p_amount,
   p_method,'تحصيل','تحصيل مالي مسجل',v_ref,v_actor)
 RETURNING id INTO v_receipt;
 IF p_invoice IS NOT NULL THEN
   INSERT INTO public.receipt_allocations(receipt_id,invoice_id,amount,created_by)
   VALUES (v_receipt,p_invoice,p_amount,v_actor);
 END IF;
 UPDATE public.receipt_requests SET receipt_id=v_receipt WHERE request_key=p_key;
 RETURN jsonb_build_object('receipt_id',v_receipt,'duplicate',false);
END $$;

REVOKE ALL ON FUNCTION public.record_receipt_v2(uuid,uuid,numeric,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_receipt_v2(uuid,uuid,numeric,text,text,uuid) TO authenticated;

-- REQUIRED STAGING TESTS: same-key concurrent requests; same-key altered amount;
-- concurrent different keys targeting same invoice; reversed receipt; partial payment;
-- noncash without reference; anon/teacher role rejection; atomic rollback.
-- NOTE: After acceptance, replace direct finance.html INSERT and operations.html RPC
-- and revoke direct client INSERT on receipt rows by adjusting RLS.
-- Do not use a feature-flag rollback to the unsafe direct INSERT path.
