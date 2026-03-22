# POS + KDS Launch Flow

## Core rule

Kitchen progress and payment progress are tracked separately:

- `orderStatus` / lifecycle stage: `pending -> preparing -> prepared -> served -> completed`
- `paymentStatus`: `unpaid -> paid -> refunded`
- Firestore `status` remains the compatibility field used by older screens and Cloud Functions.

An order is only operationally complete when kitchen and payment are both done.

## Dine-in

### Pay later

1. POS places ticket as `pending`, `paymentStatus=unpaid`
2. KDS accepts it into `preparing` or it auto-starts after the kitchen timeout
3. KDS moves it to `prepared`
4. KDS serves it to table with `served`
5. POS collects payment
6. Order closes as `status=paid`, `orderStatus=completed`
7. Table is freed when no other active dine-in tickets remain

### Prepaid before service

1. POS takes payment while ticket is still `pending` / `preparing` / `prepared`
2. Payment is captured, but the ticket stays active for kitchen
3. KDS continues through `prepared -> served`
4. When KDS marks `served`, the order auto-completes
5. Table is freed only after the last active dine-in ticket completes

### Add items after prepayment

1. Already-paid active dine-in tickets stay visible on the table
2. New items do **not** append onto a paid ticket
3. POS opens a fresh add-on ticket for the same table with a new outstanding balance

## Takeaway

### Pay later at counter

1. POS places ticket as `pending`, `paymentStatus=unpaid`
2. KDS accepts it into `preparing` or it auto-starts after the kitchen timeout
3. KDS marks it `prepared`
4. Ticket stays in Ready state until payment is collected
5. POS payment closes the order as `status=paid`, `orderStatus=completed`

### Prepaid takeaway

1. POS captures payment while ticket is still being prepared
2. KDS marks it `prepared`
3. KDS shows `HAND OFF ORDER`
4. Handoff closes the order as `status=paid`, `orderStatus=completed`

## Table settlement

- Outstanding balance only includes unpaid active tickets
- Prepaid active tickets remain on the table but are excluded from payment totals
- `Collect Payment` in table view only charges unpaid tickets
- `Complete & Free Table` is only enabled when every active dine-in ticket is both served and paid

## KDS rules

- Served and recently cancelled tickets are included in the KDS stream
- Fresh POS tickets stay in `pending` until the kitchen accepts or rejects them
- Pending POS tickets auto-transition to `preparing` after the configured timeout
- Prepared actions are order-type aware:
  - Dine-in: `MARK SERVED`
  - Takeaway prepaid: `HAND OFF ORDER`
  - Takeaway unpaid: `AWAITING PAYMENT`
- Cancelled tickets can be dismissed from KDS after visibility window

## Validation

- Single-order table payment is transactional
- Combined payment flow also cleans up tables after served dine-in tickets close
- Lifecycle unit tests cover completed-stage mapping, payment-state mapping, payment finalization, and KDS action selection
