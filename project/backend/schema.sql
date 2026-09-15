-- Structural Vision AR — schema (run in Supabase SQL editor)
-- Two tables per session-context.md. RLS scopes rows to the authenticated user.

create table if not exists scans (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references auth.users(id),
    status        text not null default 'pending'
                    check (status in ('pending','done','error')),
    -- Set from the user's pre-capture selection; null if the client sent none.
    -- wall = brick/masonry (BRE Digest 251), rc_wall = reinforced concrete (JBDPA).
    component_type text check (component_type in ('wall','rc_wall','beam','column','slab','ceiling')),
    component_confidence real,   -- legacy: from the removed component classifier
    risk_level    text check (risk_level in ('HIGH','MEDIUM','LOW')),
    -- preliminary = pixel-area heuristic at scan time; measured = graded from
    -- AR-measured crack width against a published standard.
    risk_source   text not null default 'preliminary'
                    check (risk_source in ('preliminary','measured')),
    crack_width_mm        real,
    damage_standard       text check (damage_standard in ('JBDPA','BRE251')),
    damage_class          text,   -- JBDPA I-IV or BRE 251 category 0-5
    damage_rating         text,   -- Slight/Light/Moderate/Heavy or Aesthetic/Serviceability/Stability
    residual_capacity_pct real,   -- JBDPA R = 100*eta; null for BRE 251
    crack_count   int,
    crack_area_ratio real,
    error         text,
    image_url     text,
    created_at    timestamptz not null default now()
);

create table if not exists crack_detections (
    id            uuid primary key default gen_random_uuid(),
    scan_id       uuid not null references scans(id) on delete cascade,
    bbox          jsonb not null,   -- [x1,y1,x2,y2]
    polygon       jsonb not null,   -- [[x,y],...]
    confidence    real not null,
    area_ratio    real not null,
    crack_type    text,             -- structural | paint
    length_px     double precision,
    width_px      double precision,
    growth_status text,             -- new | grown | stable (re-scan only)
    area_delta    double precision
);

create index if not exists idx_crack_detections_scan on crack_detections(scan_id);
create index if not exists idx_scans_user on scans(user_id);

alter table scans enable row level security;
alter table crack_detections enable row level security;

create policy "own scans" on scans
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own detections" on crack_detections
    for all using (exists (
        select 1 from scans s where s.id = scan_id and s.user_id = auth.uid()
    ));

-- Migration 2026-09-13 for existing databases (measured risk + rc_wall):
-- alter table scans drop constraint if exists scans_component_type_check;
-- alter table scans add constraint scans_component_type_check
--     check (component_type in ('wall','rc_wall','beam','column','slab','ceiling'));
-- alter table scans
--     add column if not exists risk_source text not null default 'preliminary'
--         check (risk_source in ('preliminary','measured')),
--     add column if not exists crack_width_mm real,
--     add column if not exists damage_standard text check (damage_standard in ('JBDPA','BRE251')),
--     add column if not exists damage_class text,
--     add column if not exists damage_rating text,
--     add column if not exists residual_capacity_pct real;
