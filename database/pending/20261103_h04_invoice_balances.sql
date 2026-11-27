-- ALKHUBARA H-04: SINGLE-SOURCE INVOICE BALANCES
-- DRAFT: NOT APPLIED. Validate on isolated staging with synthetic paid, partially-paid,
-- reversed and unapplied receipts before making any grants or replacing UI calculations.
-- PostgreSQL 15+ security_invoker view ensures the caller's underlying RLS policies are enforced.
CREATE OR REPLACE VIEW public.invoice_balances
WITH (security_invoker = true)
AS
SELECT
 i.id AS invoice_id, i.student_id, i.lesson_id, i.service_id, i.invoice_no,
 i.amount::numeric(14,2) AS invoiced_amount, i.issued_at,
 COALESCE(SUM(a.amount) FILTER (WHERE f.entry_type = 'receipt' AND
       NOT EXISTS (
         SELECT 1 FROM public.financial_entries reversal
         WHERE reversal.reverses_entry_id = f.id
       )),0)::numeric(14,2) AS allocated_amount,
 (i.amount - COALESCE(SUM(a.amount) FILTER (WHERE f.entry_type = 'receipt' AND
       NOT EXISTS (
         SELECT 1 FROM public.financial_entries reversal
         WHERE reversal.reverses_entry_id = f.id
       )),0))::numeric(14,2) AS outstanding_amount
FROM public.invoices i
LEFT JOIN public.receipt_allocations a ON a.invoice_id = i.id
LEFT JOIN public.financial_entries f ON f.id = a.receipt_id
GROUP BY i.id, i.student_id, i.lesson_id, i.service_id, i.invoice_no, i.amount, i.issued_at;

-- A positive student invoice balance excludes unapplied cash by definition.
-- Display unapplied receipts as a separate customer credit, not as a negative invoice.
CREATE OR REPLACE VIEW public.student_invoice_balances
WITH (security_invoker = true)
AS
SELECT student_id,
       COALESCE(SUM(invoiced_amount),0)::numeric(14,2) AS invoice_total,
       COALESCE(SUM(allocated_amount),0)::numeric(14,2) AS allocated_total,
       COALESCE(SUM(outstanding_amount),0)::numeric(14,2) AS outstanding_total
FROM public.invoice_balances
GROUP BY student_id;

-- Keep these views unexposed until reviewed: grant SELECT only to authenticated
-- after checking how RLS behaves for accountant/secretary/teacher roles.
-- DO NOT create unrestricted SECURITY DEFINER views for student financial data.

-- STAGING ACCEPTANCE ASSERTIONS:
-- 1. FULL payment outstanding=0; partial payment outstanding>0.
-- 2. Reversal restores outstanding; unrelated/unallocated receipt does not reduce invoice.
-- 3. Different user JWTs cannot read invoice rows outside permissions.
-- 4. Sum of all student outstanding = sum invoice - valid allocations.
-- 5. No change to any production invoice or receipt.
