-- MY TOWN TAXI – core schema (PostgreSQL). One account, two modes.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         text UNIQUE NOT NULL,
  email         text UNIQUE,
  full_name     text NOT NULL,
  is_admin      boolean NOT NULL DEFAULT false,
  kyc_status    text NOT NULL DEFAULT 'pending' CHECK (kyc_status IN ('pending','verified','rejected')),
  owner_status  text NOT NULL DEFAULT 'none'    CHECK (owner_status IN ('none','pending','verified','suspended')),
  last_mode     text NOT NULL DEFAULT 'rent'    CHECK (last_mode IN ('rent','list')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vehicles (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id      uuid NOT NULL REFERENCES users(id),
  make          text NOT NULL,
  model         text NOT NULL,
  year          int,
  reg_number    text UNIQUE NOT NULL,
  fuel_type     text NOT NULL CHECK (fuel_type IN ('petrol','diesel','cng','electric','hybrid')),
  daily_rate    numeric(10,2) NOT NULL,
  deposit       numeric(10,2) NOT NULL DEFAULT 0,
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','paused')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE bookings (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id    uuid NOT NULL REFERENCES vehicles(id),
  owner_id      uuid NOT NULL REFERENCES users(id),
  renter_id     uuid NOT NULL REFERENCES users(id),
  start_at      timestamptz NOT NULL,
  end_at        timestamptz NOT NULL,
  total_rent    numeric(10,2) NOT NULL,
  deposit       numeric(10,2) NOT NULL DEFAULT 0,
  commission    numeric(10,2) NOT NULL DEFAULT 0,
  status        text NOT NULL DEFAULT 'requested' CHECK (status IN
                ('requested','confirmed','pickup_inspection','handed_over',
                 'on_trip','return_inspection','completed','cancelled')),
  return_exception_note text,          -- authorized exception for skipping AFTER inspection
  return_exception_by   uuid REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (owner_id <> renter_id),
  CHECK (end_at > start_at)
);

CREATE TABLE payments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  uuid NOT NULL REFERENCES bookings(id),
  kind        text NOT NULL CHECK (kind IN ('rent','deposit','refund','payout','commission')),
  amount      numeric(10,2) NOT NULL,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed','refunded')),
  gateway_ref text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ===================== Inspection & gallery =====================

CREATE TABLE inspection_records (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid NOT NULL REFERENCES bookings(id),
  vehicle_id     uuid NOT NULL REFERENCES vehicles(id),
  owner_id       uuid NOT NULL REFERENCES users(id),
  renter_id      uuid NOT NULL REFERENCES users(id),
  stage          text NOT NULL CHECK (stage IN ('BEFORE_PICKUP','AFTER_RETURN')),
  odometer_km    int  CHECK (odometer_km >= 0),
  fuel_level     text,                     -- e.g. 'FULL','3/4','1/2','1/4','EMPTY' or battery %
  notes          text,
  status         text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','completed','disputed')),
  started_by     uuid NOT NULL REFERENCES users(id),
  started_at     timestamptz NOT NULL DEFAULT now(),
  completed_at   timestamptz,
  UNIQUE (booking_id, stage)
);

CREATE TABLE inspection_photos (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id  uuid NOT NULL REFERENCES inspection_records(id),
  booking_id     uuid NOT NULL REFERENCES bookings(id),
  vehicle_id     uuid NOT NULL REFERENCES vehicles(id),
  stage          text NOT NULL CHECK (stage IN ('BEFORE_PICKUP','AFTER_RETURN')),
  shot_type      text NOT NULL CHECK (shot_type IN
                 ('FRONT','REAR','LEFT','RIGHT','INTERIOR_FRONT','REAR_SEATS',
                  'DASHBOARD_ODOMETER','FUEL_GAUGE','DAMAGE','TYRES','ACCESSORIES','OTHER')),
  storage_key    text NOT NULL,            -- private object-store key of the ORIGINAL
  sha256         text NOT NULL,
  mime_type      text NOT NULL,
  uploaded_by    uuid NOT NULL REFERENCES users(id),
  uploader_role  text NOT NULL CHECK (uploader_role IN ('owner','renter','admin')),
  captured_at    timestamptz,              -- device capture time (untrusted)
  uploaded_at    timestamptz NOT NULL DEFAULT now(),  -- server time (trusted)
  latitude       double precision,
  longitude      double precision,
  caption        text
);
CREATE INDEX ON inspection_photos (booking_id, stage, shot_type);

CREATE TABLE inspection_acknowledgements (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id  uuid NOT NULL REFERENCES inspection_records(id),
  user_id        uuid NOT NULL REFERENCES users(id),
  role           text NOT NULL CHECK (role IN ('owner','renter')),
  decision       text NOT NULL CHECK (decision IN ('agreed','disagreed')),
  comment        text,
  acknowledged_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (inspection_id, role)
);

CREATE TABLE damage_reports (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid NOT NULL REFERENCES bookings(id),
  vehicle_id     uuid NOT NULL REFERENCES vehicles(id),
  reported_by    uuid NOT NULL REFERENCES users(id),   -- always a human
  before_photo_id uuid REFERENCES inspection_photos(id),
  after_photo_id  uuid REFERENCES inspection_photos(id),
  description    text NOT NULL,
  estimated_cost numeric(10,2),
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open','under_review','accepted','rejected','resolved')),
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE dispute_records (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid NOT NULL REFERENCES bookings(id),
  inspection_id  uuid REFERENCES inspection_records(id),
  damage_report_id uuid REFERENCES damage_reports(id),
  raised_by      uuid NOT NULL REFERENCES users(id),
  reason         text NOT NULL,
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open','under_review','resolved','dismissed')),
  resolution     text,
  resolved_by    uuid REFERENCES users(id),
  deposit_deduction numeric(10,2),
  created_at     timestamptz NOT NULL DEFAULT now(),
  resolved_at    timestamptz
);

CREATE TABLE audit_log (
  id          bigserial PRIMARY KEY,
  actor_id    uuid REFERENCES users(id),
  action      text NOT NULL,      -- e.g. photo.upload, photo.view, inspection.export
  entity      text NOT NULL,
  entity_id   uuid,
  meta        jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Photos are evidence: no edits, no deletes.
CREATE FUNCTION forbid_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION '% is append-only', TG_TABLE_NAME; END $$;
CREATE TRIGGER photos_immutable BEFORE UPDATE OR DELETE ON inspection_photos
  FOR EACH ROW EXECUTE FUNCTION forbid_change();
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION forbid_change();

-- Workflow gates on booking status.
CREATE FUNCTION enforce_inspection_gates() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'handed_over' AND OLD.status IS DISTINCT FROM 'handed_over' THEN
    IF NOT EXISTS (SELECT 1 FROM inspection_records
                   WHERE booking_id = NEW.id AND stage = 'BEFORE_PICKUP'
                     AND status = 'completed') THEN
      RAISE EXCEPTION 'Before-pickup inspection must be completed before handover';
    END IF;
  END IF;
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    IF NOT EXISTS (SELECT 1 FROM inspection_records
                   WHERE booking_id = NEW.id AND stage = 'AFTER_RETURN'
                     AND status IN ('completed','disputed'))
       AND (NEW.return_exception_note IS NULL OR NEW.return_exception_by IS NULL) THEN
      RAISE EXCEPTION 'After-return inspection or authorized exception required to close booking';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER booking_inspection_gates BEFORE UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION enforce_inspection_gates();
