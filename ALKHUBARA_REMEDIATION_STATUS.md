# ALKHUBARA — Remediation execution register
Date: 2026-11-02
Source: Claude handoff dated 2026-11-02. Authorization: owner requested execution.
**State: PARTIAL IMPLEMENTATION. No production deployment of this batch.**

## Changes staged in GitHub branch
- H-03: Remove destructive delete button from people.html; archive and restore remain. Server RPC still exists and requires separate security review.
- H-08: Correct invoices.html manual source lookup to use sourceKey instead of id.
- H-09: finance.html loads all entries through stable sorted pagination for totals; details still show latest 500, so full server-side pagination and aggregation remains open.
- H-10: operations.html preserves saved due dates on edit; initial date uses Asia/Qatar. Date-policy enforcement is not yet implemented at the database layer.
- H-20: CSV formula neutralization in reports.html, account-statements.html, teacher-subjects-report.html. Additional export endpoints still require review.
- H-19: conservative security headers added to vercel.json; CSP rollout and dependency audit still pending.

## Findings confirmed by read-only SQL
- RLS enabled on students, teachers, lessons, lesson_rates, invoices, financial_entries, receipt_allocations.
- Six inspected sensitive RPCs: SECURITY DEFINER with fixed empty search_path; anon EXECUTE denied, authenticated EXECUTE allowed. Internal role checks still need complete audit.
- UNIQUE index invoice_student_per_lesson exists on (lesson_id,student_id), invoice service_id UNIQUE exists. Do NOT recreate indexes.
- At review time: students 38; lessons 0, educational services 0, invoices 0, financial_entries 0, receipt_allocations 0. No historical transaction data available to test reconciliation.
- academic_subjects 14; academic_major_subjects 0.

## NOT yet done / not asserted completed
H-01 schema baseline + staging rebuild; H-02 full policy/RPC permission test matrix; H-03 backend deletion control and 40013 audit; H-04 financial ledger read model; H-05 atomic receipt/idempotency; H-06 immutable invoiced pricing and teacher rate snapshots; H-07 invoice void/credit lifecycle; H-08 server invoice route consolidation; H-09 complete server-side table pagination for all pages; H-10 server date rules; H-11 teacher workflow audit and approval; H-12 collections against invoice balances; H-13 anti-duplicate lesson and conflict checks; H-14 academic foreign keys and group merge; H-15 transactional import; H-16 data minimization; H-17 status vocabulary consolidation; H-18 password/Auth events; H-19 CSP and dependency updates; H-20 shared print and full mobile QA.

## Production release gate
1. Provision staging with synthetic data. A new paid cloud resource must not be created without separately acknowledging costs.
2. Run HTML/JS syntax checks, privileged role API tests, and full end-to-end workflows for financial records.
3. Verify changes with a second independent review and owner signoff.
4. Only then deploy to production, ensuring rollback is safe and does not restore known vulnerable financial paths.
