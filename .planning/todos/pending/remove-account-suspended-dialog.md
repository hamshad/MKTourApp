---
title: Remove Account Temporarily Suspended dialog
area: ui
status: completed
created: 2026-09-19
updated: 2026-09-19
completed_at: 2026-09-19
commit: e626d04
---

## Description

Remove the "Account Temporarily Suspended" dialog. We are removing the temporary suspension concept entirely — instead, we'll just take the excessive unpaid balance when the user books another ride (backend already handles this silently per Phase 15 / 13 contract).

## Context

- Phase 13 added startup suspension gate (`accountSuspended:true + allowCash:false` → lock Book/Schedule, pay-online-only modal)
- Phase 15 backend contract: outstanding balance no longer 403-blocks create/schedule; Stripe auto-covers combined total
- The "temporary suspension" UX is now obsolete — no hard block, just transparent balance inclusion at booking

## Acceptance Criteria

- [x] Remove `OutstandingBalanceScreen` suspend-banner/dialog path (if any)
- [x] Remove any `accountSuspended` / `allowCash` UI branching in `HomeScreen` startup gate
- [x] Ensure booking with debt shows only the transparency banner (Phase 15), never a suspension modal
- [x] `flutter analyze` clean; `flutter test` green

## Related Files

- `lib/features/ride/outstanding_balance_screen.dart`
- `lib/features/home/home_screen.dart` (startup gate from Phase 13-02)
- `lib/core/models/outstanding_balance.dart` (model has `isSuspended` getter)

## Notes

Backend contract changed: no more `accountSuspended` hard-block on booking. The suspension gate was for *startup* (pre-booking); booking itself now succeeds silently with balance included. Remove the dialog/UX entirely.

**Completed**: Commit e626d04 removed all suspension UX from HomeScreen and set `OutstandingBalance.isSuspended` to always return `false` (backend flags retained for compat). All 65 tests pass.