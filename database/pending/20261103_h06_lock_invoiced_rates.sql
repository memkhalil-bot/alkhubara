-- ALKHUBARA H-06 / H-11: STAGING-ONLY DRAFT
-- Do not run against production without role tests and snapshot validation.
-- Lock historical teacher rate and student rate once an invoice exists.
CREATE OR REPLACE FUNCTION experts_private.lock_invoiced_lesson_rates()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
BEGIN
 IF EXISTS (SELECT 1 FROM public.invoices i WHERE i.lesson_id = OLD.lesson_id) THEN
   IF TG_OP = 'DELETE' THEN
     RAISE EXCEPTION 'Invoiced lesson rates cannot be deleted';
   END IF;
   IF NEW.student_hourly_rate IS DISTINCT FROM OLD.student_hourly_rate
      OR NEW.teacher_hourly_rate IS DISTINCT FROM OLD.teacher_hourly_rate THEN
     RAISE EXCEPTION 'Invoiced lesson rates cannot be changed without an approved adjustment';
   END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER lock_invoiced_lesson_rates
BEFORE UPDATE OR DELETE ON public.lesson_rates
FOR EACH ROW EXECUTE FUNCTION experts_private.lock_invoiced_lesson_rates();

-- For H-11, update teacher_lessons_submit to accept scheduled lessons ONLY.
-- A confirmed lesson may already be invoiced; resubmitting to pending_review would
-- conflict with protect_invoiced_academic_item. Retain the existing function
-- definition and adjust its status predicate in a separately audited migration.

-- Acceptance in staging: invoiced lesson rate UPDATE rejected via REST and RPC;
-- uninvoiced lesson can be priced by center; teacher cannot resubmit confirmed;
-- completed teacher dues are unchanged by later catalog price edits.
-- Rollback only the new trigger on staging; keep original invoices and rates.
