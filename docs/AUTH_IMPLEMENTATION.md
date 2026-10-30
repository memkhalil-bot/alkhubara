# Experts Center — Authentication & Audit implementation plan

## Existing app
- Preserve the existing `index.html` UI and all current business workflows.
- Existing data uses `localStorage`, which is **not** shared or secure.
- Existing role selector is **demo only**; it must not be used for production authorization.

## Roles
| Role | Student/teacher registration | Lessons | Financial operations | Staff management | Audit |
| --- | --- | --- | --- | --- | --- |
| secretary | create/edit/import | create/edit | payment status only, never monetary amounts | no | no |
| accountant | read | read | yes | no | no |
| admin | full operational | full | full | manage secretary/accountant (trusted API) | read |
| super_admin | full | full | full | full, including role assignment | read |

## Backend requirements before enabling real accounts
1. Create a **dedicated** Supabase project for Experts Center. Do not reuse CARZIX, TERKA, or SOLO projects.
2. Apply/review `database/001_staff_auth_audit.sql` after confirming the project and security policies.
3. Add a trusted server-side endpoint for user invitations and role assignment using the Auth Admin API. Store authorization role in `app_metadata` and staff profile; never trust `user_metadata` for authorization.
4. Configure Supabase Auth email/password, invite/reset-password flows, session revocation and rate limiting.
5. Implement secure per-table RLS and separate sensitive financial tables. Never send amounts to secretary clients.
6. Move students, teachers, lessons, services, payments, expenses from browser storage to server-backed tables. Include `created_by`, `updated_by`, timestamps; record audit server-side, not client-side.
7. Add login history with server-authenticated event collection. Failed login attempts cannot be trusted if logged from browser alone; use Auth logs/hooks as supported.
8. Build management pages: users, roles, audit history, last activity, and a near-real-time dashboard.
9. Add Excel imports with preview, validation, deduplication and audit; archive/restore; conditional deletion where there are no dependencies.
10. Verify secretary cannot access financial values via network requests or CSV exports. Test account suspension, role changes, session expiry, concurrent edits and restore.

## Rollout
- Use this branch for preview builds.
- Do not merge or deploy to production until secure backend exists and acceptance tests pass.
- Migrate browser-local demo data only via explicit reviewed import; no automatic silent migration.
