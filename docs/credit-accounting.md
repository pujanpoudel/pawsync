# Credit transactions

`accounts.balance` is the available balance. `purchases.remaining` identifies unspent credits attributable to each transaction. The sum of remaining purchase lots and the sum of all ledger deltas must both equal the account balance. Accounts are locked with `SELECT … FOR UPDATE` before any mutation. PostgreSQL advisory transaction locks serialize payment deliveries by transaction ID, including refund-before-fulfillment ordering.

Purchase inserts one lot and a positive `purchase` ledger delta. Reservation decrements the account and selected oldest purchase lot together, inserts/updates a durable generation lease, and appends a `reserve` delta of -1. Success appends a zero-delta `spend` entry: the debit already happened on reserve, so it must not be deducted twice. Failure appends `refund` +1 and restores the original lot. Every state change commits in one DB transaction.

Generation IDs are keyed by account plus the client idempotency UUID. Completed requests return the cached result. Pending requests return 409 instead of running twice. Refunded requests can retry under a new attempt number. A late result from an older attempt cannot commit or refund the newer attempt.

Leases last 90 seconds, well beyond the 25-second pipeline deadline. A reaper runs at startup and every 30 seconds in each API worker; account locking makes duplicate reapers harmless. `python -m pawsync.manage recover` offers external scheduled recovery too. When an API process crashes, the reserved credit is recoverable from durable state after expiry; no connection-local rollback assumption spans the GPU work.

Refund/chargeback events revoke the account's license and token epoch immediately. The original lot's remaining credits are reclaimed; credits from other purchases are not clawed back. Pending reservations tied to the refunded lot are cancelled without resurrecting credits. The `chargeback-clawback` ledger entry records requested, reclaimed, already-spent and cancelled-reservation counts, including an explicit zero-delta entry when all credits were already spent. Balances never go negative, and a later purchase starts from the actual available balance.

Approved partial refunds currently use the same conservative full-purchase revocation/clawback policy as full refunds. Chargeback reversals require support reconciliation; they do not automatically regrant a revoked purchase. Confirm this product policy before enabling production payments.

Ledger rows are append-only; initialization installs a trigger rejecting UPDATE/DELETE. Tests check the invariants after success, failure, retries, concurrent requests, rollbacks, and clawbacks. PostgreSQL is required for these guarantees; SQLite test results would not establish them.
