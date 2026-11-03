CREATE OR REPLACE FUNCTION experts_private.invalidate_stale_lesson_reminder()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF OLD.lesson_date IS DISTINCT FROM NEW.lesson_date
   OR OLD.start_time IS DISTINCT FROM NEW.start_time
   OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id
   OR NEW.status IN ('cancelled','completed')
 THEN
   UPDATE public.notifications SET dismissed_at=now()
   WHERE related_id=OLD.id::text AND event_type='lesson.reminder' AND dismissed_at IS NULL;
 END IF;
 IF OLD.lesson_date IS DISTINCT FROM NEW.lesson_date
   OR OLD.start_time IS DISTINCT FROM NEW.start_time
   OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id
 THEN
   DELETE FROM public.lesson_reminder_deliveries WHERE lesson_id=OLD.id;
 END IF;
 RETURN NEW;
END $$;