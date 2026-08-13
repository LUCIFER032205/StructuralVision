-- Structural Vision AR — schema (run in Supabase SQL editor)
-- Two tables per session-context.md. RLS scopes rows to the authenticated user.

create table if not exists scans (
    id            uuid primary key default gen_random_uuid(),
    user_id       uuid not null references auth.users(id),
    status        text not null default 'pending'
                    check (status in ('pending','done','error')),
    component_type text check (component_type in ('wall','beam','column','slab','ceiling')),
    component_confidence real,
    risk_level    text check (risk_level in ('HIGH','MEDIUM','LOW')),
    crack_count   int,
    crack_area_ratio real,
    error         text,
    image_url     text,
    created_at    timestamptz not null default now()
);

create table if not exists crack_detections (
    id          uuid primary key default gen_random_uuid(),
    scan_id     uuid not null references scans(id) on delete cascade,
    bbox        jsonb not null,   -- [x1,y1,x2,y2]
    polygon     jsonb not null,   -- [[x,y],...]
    confidence  real not null,
    area_ratio  real not null
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
