CREATE OR REPLACE FUNCTION public.invoice_discount_approver_names()
RETURNS TABLE(user_id uuid,full_name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (
   experts_private.has_permission('invoices.view')
   OR experts_private.has_permission('invoices.create')
   OR experts_private.has_permission('finance.view')
   OR experts_private.has_permission('finance.edit')
 ) THEN RAISE EXCEPTION 'Invoice view permission required'; END IF;
 RETURN QUERY SELECT DISTINCT sp.user_id,sp.full_name
 FROM public.staff_profiles sp JOIN public.invoices i ON i.discount_approved_by=sp.user_id
 WHERE i.discount_approved_by IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.invoice_discount_approver_names() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.invoice_discount_approver_names() TO authenticated;