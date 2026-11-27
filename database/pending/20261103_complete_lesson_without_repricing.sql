CREATE OR REPLACE FUNCTION public.complete_lesson_record(p_lesson uuid,p_payment_terms text,p_due_date date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE actor uuid:=auth.uid(); l public.lessons%ROWTYPE;
BEGIN
 IF actor IS NULL OR NOT experts_private.has_permission('lessons.edit') THEN
   RAISE EXCEPTION 'Authorized lesson editor required';
 END IF;
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson AND NOT is_archived FOR UPDATE;
 IF NOT FOUND OR l.status NOT IN ('scheduled','confirmed','pending_review','completed') THEN
   RAISE EXCEPTION 'Lesson cannot be completed in its current state';
 END IF;
 IF p_payment_terms NOT IN ('credit','immediate') THEN
   RAISE EXCEPTION 'Choose valid payment terms';
 END IF;
 IF p_payment_terms='credit' AND (p_due_date IS NULL OR p_due_date<l.lesson_date OR p_due_date>l.lesson_date+30)
 THEN RAISE EXCEPTION 'Expected due date must be within 30 days of the lesson'; END IF;
 UPDATE public.lessons SET status='completed',payment_terms=p_payment_terms,
 due_date=CASE WHEN p_payment_terms='credit' THEN p_due_date ELSE NULL END,updated_by=actor
 WHERE id=p_lesson;
 INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
 VALUES(actor,'complete','lessons',p_lesson::text,jsonb_build_object('payment_terms',p_payment_terms,'due_date',p_due_date));
 RETURN jsonb_build_object('lesson_id',p_lesson,'status','completed');
END $$;
REVOKE ALL ON FUNCTION public.complete_lesson_record(uuid,text,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.complete_lesson_record(uuid,text,date) TO authenticated;