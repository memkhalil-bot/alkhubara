CREATE OR REPLACE FUNCTION public.save_educational_service_with_price(p_service uuid, p_fields jsonb, p_price numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=auth.uid(); sid uuid; new_status text:=coalesce(p_fields->>'status','new'); old_price numeric; has_invoice boolean;
BEGIN
 IF actor IS NULL OR NOT experts_private.has_permission('services.edit') THEN RAISE EXCEPTION 'Not authorized to manage educational services';END IF;
 IF new_status NOT IN ('new','in_progress','completed','cancelled') THEN RAISE EXCEPTION 'Invalid service status';END IF;
 IF p_price IS NULL OR p_price<=0 OR p_price>1000000 OR p_price<>round(p_price,2) THEN RAISE EXCEPTION 'A valid service price is required';END IF;
 IF p_service IS NULL THEN
  INSERT INTO public.educational_services(student_id,teacher_id,academic_subject_id,service_date,service_type,description,status,payment_terms,due_date,created_by,updated_by)
  VALUES((p_fields->>'student_id')::uuid,nullif(p_fields->>'teacher_id','')::uuid,nullif(p_fields->>'academic_subject_id','')::uuid,(p_fields->>'service_date')::date,p_fields->>'service_type',p_fields->>'description','new',coalesce(p_fields->>'payment_terms','credit'),(p_fields->>'due_date')::date,actor,actor)
  RETURNING id INTO sid;
 ELSE
  sid:=p_service;
  PERFORM 1 FROM public.educational_services WHERE id=sid AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service record not found';END IF;
  SELECT EXISTS(SELECT 1 FROM public.invoices WHERE service_id=sid) INTO has_invoice;
  IF has_invoice THEN
   SELECT amount INTO old_price FROM public.service_prices WHERE service_id=sid;
   IF old_price IS DISTINCT FROM p_price THEN RAISE EXCEPTION 'Invoiced service price cannot be changed';END IF;
  END IF;
  UPDATE public.educational_services SET student_id=(p_fields->>'student_id')::uuid,teacher_id=nullif(p_fields->>'teacher_id','')::uuid,academic_subject_id=nullif(p_fields->>'academic_subject_id','')::uuid,service_date=(p_fields->>'service_date')::date,service_type=p_fields->>'service_type',description=p_fields->>'description',payment_terms=coalesce(p_fields->>'payment_terms','credit'),due_date=(p_fields->>'due_date')::date,updated_by=actor WHERE id=sid;
 END IF;
 INSERT INTO public.service_prices(service_id,amount,created_by,updated_by) VALUES(sid,p_price,actor,actor)
 ON CONFLICT (service_id) DO UPDATE SET amount=EXCLUDED.amount,updated_by=actor,updated_at=now();
 UPDATE public.educational_services SET status=new_status,updated_by=actor WHERE id=sid;
 RETURN jsonb_build_object('service_id',sid,'status',new_status,'price',p_price);
END $function$
;