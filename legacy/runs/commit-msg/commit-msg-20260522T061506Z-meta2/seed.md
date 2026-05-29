# Diff to summarize

## Files changed

- `src/api/middleware/auth.ts` (new, 84 lines)
- `src/api/server.ts` (modified, +6 -0)

## Summary of change

A new authentication middleware was added and wired into every route under `/api/*`. The middleware validates a JWT in the Authorization header and rejects unauthenticated requests with 401.

## Scope hint

api

## Type hint

feat
