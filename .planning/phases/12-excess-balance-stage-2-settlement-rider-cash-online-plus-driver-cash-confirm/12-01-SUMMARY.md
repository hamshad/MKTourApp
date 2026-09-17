---
phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm
plan: 01
subsystem: payments
tags: [excess-balance, stage2-settlement, socket, contract-tests, outstanding-balance]

# Dependency graph
requires:
  - phase: 11-upfront-payments
    provides: OutstandingBalance tolerant parsing + never-throws _postRequest pattern + deleted arrival select-payment boundary
provides:
  - selectBalanceMethod + confirmDriverCash ApiService methods via _postRequest
  - ApiConstants select-method + confirm-driver-cash URL builders
  - OutstandingBalance.fromSelectMethodEnvelope tolerant parser
  - SocketService excess-cash requested/cancelled passthroughs
  - excess_settlement_contract_test.dart envelope-tolerance tests
affects: [12-02-rider-settlement-sheet, 12-03-driver-cash-modal, 13-suspension-safeguard]

# Tech tracking
tech-stack:
  added: []
  patterns: [never-throws _postRequest envelope, tolerant select-method parsing, colon-camelCase socket passthroughs with off-symmetry]

key-files:
  created: [test/excess_settlement_contract_test.dart]
  modified: [lib/core/constants/api_constants.dart, lib/core/api_service.dart, lib/core/models/outstanding_balance.dart, lib/core/services/socket_service.dart]

key-decisions:
  - "fromSelectMethodEnvelope also tolerates flat top-level envelope (no data wrapper) since live shape unverified"
  - "Socket passthroughs use exact colon-camelCase strings only, no snake_case variants"
  - "Deprecated selectPaymentMethod left untouched per plan"

patterns-established:
  - "Select-method transport: ApiConstants builder + ApiService _postRequest thin wrapper"
  - "Settlement parsing: fromSelectMethodEnvelope mirrors fromBalanceEnvelope tolerance"

requirements-completed: [STAGE2-02, STAGE2-05]

# Metrics
duration: 2min
completed: 2026-09-17
---

# Phase 12 Plan 01: Settlement Transport Foundation Summary

**Stage 2 transport wired: select-method + confirm-driver-cash endpoints, tolerant select-method parser, four excess-cash socket passthroughs, 9 contract tests green**

## Performance

- **Duration:** 2 min
- **Started:** 2026-09-17T13:40:57Z
- **Completed:** 2026-09-17T13:42:14Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- selectBalanceMethod(rideId, paymentMethod) + confirmDriverCash(rideId) callable from ApiService via _postRequest (never throws, token + 401 hook inherited)
- ApiConstants.selectBalanceMethod/confirmDriverCash URL builders next to paymentBalance
- OutstandingBalance.fromSelectMethodEnvelope tolerates flat + nested paymentUrl, 3 amount keys, flat top-level envelope, list envelope, cash-no-URL, succeeded-as-paid
- SocketService on/offExcessCashRequested + on/offExcessCashCancelled with exact colon-camelCase strings
- 9 contract tests pinning every envelope shape, all green

## Task Commits

Each task was committed atomically:

1. **Task 1: Endpoint URLs + ApiService methods** - `54f9154` (feat)
2. **Task 2: Tolerant parser + socket passthroughs + contract tests** - `c29981b` (feat)

**Plan metadata:** pending final docs commit

## Files Created/Modified

- `lib/core/constants/api_constants.dart` - selectBalanceMethod + confirmDriverCash URL builders
- `lib/core/api_service.dart` - selectBalanceMethod + confirmDriverCash via _postRequest
- `lib/core/models/outstanding_balance.dart` - fromSelectMethodEnvelope tolerant parser
- `lib/core/services/socket_service.dart` - 4 excess-cash socket passthroughs
- `test/excess_settlement_contract_test.dart` - 9 select-method envelope parsing tests (152 lines)

## Decisions Made

- fromSelectMethodEnvelope also tolerates flat top-level envelope (keys without `data` wrapper, minus `success`) since live select-method shape unverified (research open question 1); falls back to envelope-level rideId/paymentUrl/clientSecret/message/status
- Socket passthroughs registered with exact `payment:excessCashRequested` / `payment:excessCashCancelled` strings only, no snake_case variants (per pitfall 6)
- Deprecated `selectPaymentMethod` (rides/:id/select-payment) left untouched per plan; rg confirms zero new select-payment references

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. `flutter analyze` on touched files reports only 2 pre-existing infos (IO library prefix, unused _isAppInBackground field) on untouched lines; no new issues introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 12-02 (rider settlement sheet on receipt: Cash/Online + waiting state + WebView + succeeded close-out)
- Ready for 12-03 (driver cash modal: Collect-Cash request + confirm wiring + cancelled auto-close)
- Live-envelope pinning still open: first device test should log actual select-method response and confirm parser coverage

---
*Phase: 12-excess-balance-stage-2-settlement-rider-cash-online-plus-driver-cash-confirm*
*Completed: 2026-09-17*

## Self-Check: PASSED
