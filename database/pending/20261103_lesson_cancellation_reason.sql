ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS cancellation_reason text;
CREATE OR REPLACE FUNCTION experts_private.require_lesson_cancellation_reason()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
 IF NEW.status='cancelled' THEN
   IF length(btrim(coalesce(NEW.cancellation_reason,''))) < 5 THEN
     RAISE EXCEPTION 'Cancellation reason is required (at least 5 characters)';
   END IF;
   IF NEW.status IS DISTINCT FROM OLD.status AND EXISTS(
     SELECT 1 FROM public.invoices i WHERE i.lesson_id=OLD.id
   ) THEN RAISE EXCEPTION 'Invoiced lesson requires an approved financial adjustment before cancellation'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER require_lesson_cancellation_reason BEFORE UPDATE ON public.lessons
FOR EACH ROW EXECUTE FUNCTION experts_private.require_lesson_cancellation_reason();
CREATE OR REPLACE FUNCTION public.cancel_lesson_with_reason(p_lesson_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE actor uuid:=auth.uid(); l public.lessons%ROWTYPE; tname text;
BEGIN
 IF actor IS NULL OR NOT experts_private.has_permission('lessons.edit') THEN
   RAISE EXCEPTION 'Only authorized management may cancel a lesson';
 END IF;
 IF length(btrim(coalesce(p_reason,''))) NOT BETWEEN 5 AND 1000
 THEN RAISE EXCEPTION 'Provide a cancellation reason of 5-1000 characters'; END IF;
 SELECT * INTO l FROM public.lessons WHERE id=p_lesson_id AND NOT is_archived FOR UPDATE;
 IF NOT FOUND OR l.status='cancelled' THEN RAISE EXCEPTION 'Lesson is unavailable or already cancelled'; END IF;
 IF EXISTS(SELECT 1 FROM public.invoices WHERE lesson_id=p_lesson_id)
 OR EXISTS(SELECT 1 FROM public.financial_entries WHERE student_id=l.student_id AND category='تحصيل' AND description ILIKE '%'||p_lesson_id::text||'%')
 THEN RAISE EXCEPTION 'Financially linked lesson requires a documented adjustment before cancellation'; END IF;
 UPDATE public.lessons SET status='cancelled',cancellation_reason=btrim(p_reason),updated_by=actor WHERE id=p_lesson_id;
 INSERT INTO public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
 VALUES(actor,'cancel','lessons',p_lesson_id::text,jsonb_build_object('reason',btrim(p_reason),'lesson_date',l.lesson_date));
 INSERT INTO public.notifications(recipient_id,actor_id,event_type,title,message,target_path,related_id)
 SELECT sp.user_id,actor,'lesson.cancelled','تم إلغاء حصة دراسية',
 l.lesson_date::text||' · '||l.subject||' · السبب: '||left(btrim(p_reason),300),
 'teacher.html',p_lesson_id::text FROM public.staff_profiles sp
 WHERE sp.teacher_id=l.teacher_id AND sp.is_active AND sp.deleted_at IS NULL AND sp.user_id<>actor;
 RETURN jsonb_build_object('status','cancelled','lesson_id',p_lesson_id);
END $$;
REVOKE ALL ON FUNCTION public.cancel_lesson_with_reason(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_lesson_with_reason(uuid,text) TO authenticated;