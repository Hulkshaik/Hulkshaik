# MY TOWN TAXI – Architecture

```
            One Android App                 One Admin Web Dashboard
   ┌──────────────────────────────┐      ┌──────────────────────────┐
   │ Rent a Car │ List Your Car   │      │ Owners · Customers       │
   │ (same account, mode switch)  │      │ Vehicles · Bookings      │
   └───────────────┬──────────────┘      │ Inspection & Gallery     │
                   │                     │ Payments · Disputes      │
                   ▼                     │ Commission · Reports     │
        Shared Backend API  ◄────────────┴──────────────────────────┘
   Users • Vehicles • Bookings • Payments • Gallery
        │                         │
   PostgreSQL            Private object storage (originals, immutable)
```

## Booking lifecycle with inspection gates

```
requested → confirmed → pickup_inspection → handed_over → on_trip
          → return_inspection → completed
                         ↘ (authorized exception recorded) ↗
```

- `handed_over` requires a `completed` BEFORE_PICKUP inspection with
  both owner and renter acknowledgements (or an open dispute on file).
- `completed` requires a `completed` AFTER_RETURN inspection, or a
  documented exception approved by an admin.

## Photo handling rules

- Originals are write-once in private storage; store SHA-256 at upload.
  Thumbnails/enlargements are derived copies.
- Every photo row: booking, inspection, stage, shot type, uploader,
  server timestamp (client capture time kept separately), hash.
- Access via short-lived signed URLs, only for the booking's owner,
  renter and admins. All views/exports are written to `audit_log`.
- Damage is only ever declared by a human (a `damage_reports` row filed by a
  party or admin). AI comparison may suggest regions to look at, never decide.

## Suggested stack (adjust as needed)

Android: Kotlin + Jetpack Compose · Backend: Node/TypeScript or Kotlin,
REST + JWT · DB: PostgreSQL · Storage: S3-compatible bucket · Admin: React.

See `backend/db/schema.sql` for the data model.
