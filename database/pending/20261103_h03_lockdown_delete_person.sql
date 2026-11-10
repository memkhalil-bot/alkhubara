-- ALKHUBARA H-03: HARD DELETE LOCKDOWN (STAGING MIGRATION DRAFT)
-- Pending validation in an isolated staging database. DO NOT execute against production
-- until role matrix tests and a recovery plan are approved.
-- This preserves the existing function for forensic/audit purposes,
-- but prevents regular client roles from invoking it directly.
REVOKE EXECUTE ON FUNCTION public.delete_person_safely(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_person_safely(text, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_person_safely(text, uuid) FROM authenticated;

-- Read-only verification after application:
-- SELECT has_function_privilege('anon', 'public.delete_person_safely(text,uuid)', 'EXECUTE') AS anon_can_delete,
--        has_function_privilege('authenticated', 'public.delete_person_safely(text,uuid)', 'EXECUTE') AS authenticated_can_delete;
--
-- Undo only in isolated staging (never reopen hard delete on production as routine rollback):
-- GRANT EXECUTE ON FUNCTION public.delete_person_safely(text, uuid) TO authenticated;
