# ALKHUBARA — Remediation execution register
Date: 2026-11-02
Source: Claude handoff dated 2026-11-02. Authorization: owner requested execution.
**State: PARTIAL IMPLEMENTATION. Latest Vercel preview READY. No production deployment of this batch.**

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

## Additional execution — 2026-11-03
- H-09: invoices.html and reports.html now fetch successive stable ID-ordered pages instead of failing on fixed 500/1000-row ceilings. This is a bridge; server-side aggregates and filtered pagination remain required.
- Vercel preview deployment: dpl_DswFxHE1trUm1o9Rtwx5gDfWRZ37, READY. Preview URL: https://alkhubara-i76vvrwqg-mohkhalil.vercel.app — may be protected by Vercel Authentication. It uses the production database configuration, thus no write-side synthetic tests were run.
- Static JavaScript compilation check passed for people, finance, invoices, operations, reports, account-statements, teacher-subjects-report. This is not an end-to-end test.
- No database migration / production deployment in this continuation.

## Additional execution — 2026-11-03 (second pass)
- H-09: balances.html, account-statements.html, executive.html now fetch id-ordered complete result batches, removing their prior hard ceilings and unstable offset ordering. Still a transitional client-side read approach, not indexed server-side aggregates or keyset UI pagination.
- H-10/H-17: account-statements.html converts invoice timestamps to Asia/Qatar date; finance.html defaults and overdue status use Qatar date; invoices.html shows issue timestamp using Qatar date.
- Verified via read-only SQL: financial_entries/invoices/receipt_allocations/students/lessons/lesson_rates have active RLS with role permissions evaluated via experts_private.has_permission. This does not prove privilege matrix tests yet.
- Checked modified HTML embedded script syntax (7 pages PASS). Preview deployment dpl_3kjbzqsLj4XjtG9yPcsTThaZzG7Q READY at https://alkhubara-m9pejtjts-mohkhalil.vercel.app. No financial writes or migrations on production.
- Pending: browser-based role E2E tests, staging database isolation, atomic receipts/ledger single truth, immutable invoiced pricing, invoice lifecycle, secure server-side delete, import atomicity, academic hierarchy and other handoff items.

## Confirmed server finding — H-03
Read-only examination of public.delete_person_safely showed that it performs hard DELETE for unlinked students/teachers after checking students.edit or teachers.edit, and writes prior JSON to audit_logs. Although the destructive UI button is removed, the authenticated RPC remains executable by authorized editors. Proposed server fix (not applied): revoke EXECUTE from authenticated, preserve archiving UI; reintroduce a tightly scoped audited deletion process only if explicitly required after role tests. Do not treat UI removal as full security remediation.

## 2026-11-03 continuation
- teacher.html: lesson submission now calls only teacher_lessons_submit; existing lesson price displays read-only. Lesson creation pricing policy still needs review.
- database/pending/20261103_h03_lockdown_delete_person.sql: pending draft, not applied.
- Verified existing trigger guards for source pricing and receipt allocation, and verified pending_review is set by teacher_lessons_submit.
- Vercel preview READY: dpl_5NFZ4p7ik7uaDHJrEKAhcZGShYhH. No production deployment or database migration.
