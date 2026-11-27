
CREATE TABLE IF NOT EXISTS public.lesson_reminder_deliveries (
 lesson_id uuid NOT NULL REFERENCES public.lessons(id) ON DELETE CASCADE,
 recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 scheduled_for timestamptz NOT NULL,
 delivered_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(lesson_id,recipient_id,scheduled_for)
);
ALTER TABLE public.lesson_reminder_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lesson_reminder_deliveries FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_lesson_reminders()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE delivered_count integer;
BEGIN
 WITH candidates AS (
   SELECT l.id AS lesson_id, sp.user_id AS recipient_id, l.lesson_date,l.start_time,l.subject,
          ((l.lesson_date+l.start_time) AT TIME ZONE 'Asia/Qatar') AS begins_at
   FROM public.lessons l
   JOIN public.staff_profiles sp ON sp.teacher_id=l.teacher_id
   WHERE l.status IN ('scheduled','confirmed') AND NOT l.is_archived
     AND sp.is_active AND sp.deleted_at IS NULL
 ),
 due AS (
   SELECT * FROM candidates WHERE begins_at>now() AND begins_at<=now()+interval '24 hours'
 ),
 new_deliveries AS (
   INSERT INTO public.lesson_reminder_deliveries(lesson_id,recipient_id,scheduled_for)
   SELECT lesson_id,recipient_id,begins_at FROM due
   ON CONFLICT DO NOTHING
   RETURNING lesson_id,recipient_id,scheduled_for
 ),
 actual AS (
   INSERT INTO public.notifications(recipient_id,event_type,title,message,target_path,related_id)
   SELECT nd.recipient_id,'lesson.reminder','تذكير: لديك حصة دراسية',
     'الحصة يوم '||to_char(d.lesson_date,'YYYY-MM-DD')||' الساعة '||
      to_char(d.start_time,'HH24:MI')||' بتوقيت قطر · المادة: '||d.subject,
     'teacher.html',nd.lesson_id::text
   FROM new_deliveries nd
   JOIN due d ON d.lesson_id=nd.lesson_id AND d.recipient_id=nd.recipient_id AND d.begins_at=nd.scheduled_for
   RETURNING id
 )
 SELECT count(*) INTO delivered_count FROM actual;
 RETURN delivered_count;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_lesson_reminders() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION experts_private.invalidate_stale_lesson_reminder()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF OLD.lesson_date IS DISTINCT FROM NEW.lesson_date
   OR OLD.start_time IS DISTINCT FROM NEW.start_time
   OR OLD.teacher_id IS DISTINCT FROM NEW.teacher_id
   OR NEW.status IN ('cancelled','completed')
 THEN
   UPDATE public.notifications
   SET dismissed_at=now()
   WHERE related_id=OLD.id::text AND event_type='lesson.reminder'
     AND dismissed_at IS NULL;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER invalidate_stale_lesson_reminder
AFTER UPDATE ON public.lessons
FOR EACH ROW EXECUTE FUNCTION experts_private.invalidate_stale_lesson_reminder();
