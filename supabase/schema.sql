-- =====================================================================
-- HandyMatch database schema (Supabase / PostgreSQL)
--
-- How to run: Supabase dashboard -> your project -> SQL Editor ->
-- New query -> paste this whole file -> Run. Safe to run once on a new
-- project. Money is stored in cents (integers) to avoid rounding errors.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Fixed lists (enums)
-- ---------------------------------------------------------------------
create type public.service_type as enum (
  'handyman', 'tv_mounting', 'drywall', 'furniture_assembly',
  'garage_door', 'appliance_repair'
);

create type public.request_timing as enum ('asap', 'this_week', 'flexible');

create type public.request_status as enum (
  'new',          -- just submitted
  'verified',     -- phone code confirmed, in service area, not a duplicate
  'assigned',     -- sent to one pro
  'unsold',       -- verified but no pro available
  'rejected'      -- failed verification
);

create type public.pro_status as enum ('pending', 'active', 'paused', 'removed');

create type public.check_status as enum ('not_required', 'pending', 'verified', 'failed');

create type public.lead_product as enum ('form_lead', 'call', 'premium_call');

create type public.assignment_status as enum ('new', 'contacted', 'won', 'lost', 'credited');

create type public.ledger_kind as enum ('top_up', 'free_lead', 'lead_charge', 'credit', 'adjustment');

create type public.credit_reason as enum (
  'wrong_number', 'out_of_area', 'wrong_trade', 'duplicate',
  'unreachable_48h', 'goodwill'
);

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------

-- Homeowners. auth_user_id is filled only if they create a login later;
-- most homeowners just submit the request form.
create table public.homeowners (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique references auth.users (id) on delete set null,
  name          text not null,
  phone         text not null,
  email         text,
  zip           text not null check (zip ~ '^[0-9]{5}$'),
  created_at    timestamptz not null default now()
);
create index homeowners_phone_idx on public.homeowners (phone);

-- Pros (contractors who buy leads). Each pro signs in with Supabase Auth.
create table public.pros (
  id                 uuid primary key default gen_random_uuid(),
  auth_user_id       uuid not null unique references auth.users (id) on delete cascade,
  business_name      text not null,
  contact_name       text not null,
  phone              text not null,
  email              text not null,
  trades             public.service_type[] not null default '{}',
  zip_codes          text[] not null default '{}',
  license_number     text,
  license_status     public.check_status not null default 'pending',
  insurance_status   public.check_status not null default 'pending',
  status             public.pro_status not null default 'pending',
  weekly_budget_cents integer check (weekly_budget_cents >= 0),
  free_leads_left    integer not null default 3 check (free_leads_left >= 0),
  price_locked_until date,
  created_at         timestamptz not null default now()
);
create index pros_zip_codes_idx on public.pros using gin (zip_codes);
create index pros_trades_idx on public.pros using gin (trades);

-- Prices per product and service (e.g. handyman form lead = 3500 cents).
create table public.price_list (
  id            uuid primary key default gen_random_uuid(),
  service       public.service_type not null,
  product       public.lead_product not null,
  price_cents   integer not null check (price_cents > 0),
  effective_from date not null default current_date,
  unique (service, product, effective_from)
);

-- Homeowner job requests, with the TCPA consent proof stored on each one.
create table public.requests (
  id                  uuid primary key default gen_random_uuid(),
  homeowner_id        uuid not null references public.homeowners (id) on delete restrict,
  service             public.service_type not null,
  details             text,
  zip                 text not null check (zip ~ '^[0-9]{5}$'),
  timing              public.request_timing not null default 'flexible',
  status              public.request_status not null default 'new',
  phone_verified_at   timestamptz,
  source              text,               -- e.g. 'google_ads', 'seo', 'facebook'
  -- consent proof (never delete these columns)
  consent_text        text not null,      -- exact disclosure shown on the form
  consent_at          timestamptz not null default now(),
  consent_ip          inet,
  consent_user_agent  text,
  consent_certificate text,               -- TrustedForm / Jornaya certificate ID or URL
  created_at          timestamptz not null default now()
);
create index requests_status_idx on public.requests (status, created_at desc);
create index requests_homeowner_idx on public.requests (homeowner_id);

-- Which pro got which request. UNIQUE (request_id) is what guarantees
-- that a lead can never be sold to two pros.
create table public.lead_assignments (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid not null unique references public.requests (id) on delete restrict,
  pro_id        uuid not null references public.pros (id) on delete restrict,
  product       public.lead_product not null default 'form_lead',
  price_cents   integer not null check (price_cents >= 0),
  status        public.assignment_status not null default 'new',
  assigned_at   timestamptz not null default now(),
  contacted_at  timestamptz,
  closed_at     timestamptz
);
create index lead_assignments_pro_idx on public.lead_assignments (pro_id, assigned_at desc);

-- Credits for bad leads. One credit per assignment at most.
create table public.credits (
  id                  uuid primary key default gen_random_uuid(),
  lead_assignment_id  uuid not null unique references public.lead_assignments (id) on delete restrict,
  reason              public.credit_reason not null,
  automatic           boolean not null default true,
  note                text,
  created_at          timestamptz not null default now()
);

-- Every money movement for a pro, one row each. A pro's balance is the
-- SUM of amount_cents; rows are never edited, only added.
-- Positive = money in (top-up, credit). Negative = money out (lead charge).
create table public.ledger_entries (
  id                  uuid primary key default gen_random_uuid(),
  pro_id              uuid not null references public.pros (id) on delete restrict,
  kind                public.ledger_kind not null,
  amount_cents        integer not null,
  lead_assignment_id  uuid references public.lead_assignments (id) on delete restrict,
  credit_id           uuid unique references public.credits (id) on delete restrict,
  payment_reference   text unique,         -- e.g. Stripe payment intent ID for top-ups
  note                text,
  created_at          timestamptz not null default now(),
  constraint ledger_sign_matches_kind check (
    (kind = 'top_up'      and amount_cents > 0) or
    (kind = 'credit'      and amount_cents > 0) or
    (kind = 'lead_charge' and amount_cents < 0) or
    (kind = 'free_lead'   and amount_cents = 0) or
    (kind = 'adjustment')
  )
);
create index ledger_entries_pro_idx on public.ledger_entries (pro_id, created_at desc);
-- A lead can be charged only once.
create unique index ledger_one_charge_per_lead
  on public.ledger_entries (lead_assignment_id)
  where kind in ('lead_charge', 'free_lead');

-- Phone calls from call tracking (Ringba, CallRail, etc.).
create table public.calls (
  id                 uuid primary key default gen_random_uuid(),
  provider_call_id   text not null unique,   -- the call tracker's own ID
  pro_id             uuid references public.pros (id) on delete restrict,
  request_id         uuid references public.requests (id) on delete set null,
  lead_assignment_id uuid references public.lead_assignments (id) on delete set null,
  tracking_number    text,
  caller_phone       text,
  started_at         timestamptz not null,
  duration_seconds   integer not null default 0 check (duration_seconds >= 0),
  billable           boolean generated always as (duration_seconds >= 60) stored,
  recording_url      text,
  created_at         timestamptz not null default now()
);
create index calls_pro_idx on public.calls (pro_id, started_at desc);

-- License and insurance documents (files live in Supabase Storage).
create table public.pro_documents (
  id            uuid primary key default gen_random_uuid(),
  pro_id        uuid not null references public.pros (id) on delete cascade,
  kind          text not null check (kind in ('license', 'insurance', 'other')),
  storage_path  text not null,               -- path in the 'pro-documents' bucket
  expires_on    date,
  status        public.check_status not null default 'pending',
  uploaded_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. Balance view
-- ---------------------------------------------------------------------
create view public.pro_balances
with (security_invoker = true) as
select p.id as pro_id,
       coalesce(sum(l.amount_cents), 0)::integer as balance_cents
from public.pros p
left join public.ledger_entries l on l.pro_id = p.id
group by p.id;

-- ---------------------------------------------------------------------
-- 4. Business actions (each runs as one all-or-nothing transaction)
--    Called from your server / Edge Functions with the service role key.
-- ---------------------------------------------------------------------

-- Assign a verified request to one pro and charge them (or use a free lead).
create or replace function public.assign_lead(
  p_request_id uuid,
  p_pro_id     uuid,
  p_product    public.lead_product default 'form_lead'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request    public.requests;
  v_pro        public.pros;
  v_price      integer;
  v_balance    integer;
  v_assignment uuid;
begin
  select * into v_request from public.requests where id = p_request_id for update;
  if not found then raise exception 'Request % not found', p_request_id; end if;
  if v_request.status <> 'verified' then
    raise exception 'Request % is %, only verified requests can be assigned', p_request_id, v_request.status;
  end if;

  select * into v_pro from public.pros where id = p_pro_id for update;
  if not found or v_pro.status <> 'active' then
    raise exception 'Pro % is not active', p_pro_id;
  end if;

  select price_cents into v_price
  from public.price_list
  where service = v_request.service and product = p_product and effective_from <= current_date
  order by effective_from desc
  limit 1;
  if v_price is null then
    raise exception 'No price set for % / %', v_request.service, p_product;
  end if;

  insert into public.lead_assignments (request_id, pro_id, product, price_cents)
  values (p_request_id, p_pro_id, p_product, v_price)
  returning id into v_assignment;

  if v_pro.free_leads_left > 0 then
    update public.pros set free_leads_left = free_leads_left - 1 where id = p_pro_id;
    insert into public.ledger_entries (pro_id, kind, amount_cents, lead_assignment_id, note)
    values (p_pro_id, 'free_lead', 0, v_assignment, 'Free trial lead');
  else
    select balance_cents into v_balance from public.pro_balances where pro_id = p_pro_id;
    if v_balance < v_price then
      raise exception 'Pro % balance (% cents) is below the lead price (% cents)', p_pro_id, v_balance, v_price;
    end if;
    insert into public.ledger_entries (pro_id, kind, amount_cents, lead_assignment_id)
    values (p_pro_id, 'lead_charge', -v_price, v_assignment);
  end if;

  update public.requests set status = 'assigned' where id = p_request_id;
  return v_assignment;
end;
$$;

-- Credit a bad lead back to the pro's balance.
create or replace function public.issue_credit(
  p_assignment_id uuid,
  p_reason        public.credit_reason,
  p_automatic     boolean default true,
  p_note          text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.lead_assignments;
  v_charged    integer;
  v_credit     uuid;
begin
  select * into v_assignment from public.lead_assignments where id = p_assignment_id for update;
  if not found then raise exception 'Assignment % not found', p_assignment_id; end if;

  select -amount_cents into v_charged
  from public.ledger_entries
  where lead_assignment_id = p_assignment_id and kind = 'lead_charge';

  insert into public.credits (lead_assignment_id, reason, automatic, note)
  values (p_assignment_id, p_reason, p_automatic, p_note)
  returning id into v_credit;

  -- Free leads cost nothing, so only paid leads get money back.
  if v_charged is not null and v_charged > 0 then
    insert into public.ledger_entries (pro_id, kind, amount_cents, lead_assignment_id, credit_id, note)
    values (v_assignment.pro_id, 'credit', v_charged, p_assignment_id, v_credit, p_reason::text);
  end if;

  update public.lead_assignments set status = 'credited' where id = p_assignment_id;
  return v_credit;
end;
$$;

revoke all on function public.assign_lead(uuid, uuid, public.lead_product) from public, anon, authenticated;
revoke all on function public.issue_credit(uuid, public.credit_reason, boolean, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Row-level security: pros see only their own data.
--    The website form and lead routing write through the service role,
--    which bypasses these rules, so the public can't read anything.
-- ---------------------------------------------------------------------
alter table public.homeowners       enable row level security;
alter table public.pros             enable row level security;
alter table public.price_list       enable row level security;
alter table public.requests         enable row level security;
alter table public.lead_assignments enable row level security;
alter table public.credits          enable row level security;
alter table public.ledger_entries   enable row level security;
alter table public.calls            enable row level security;
alter table public.pro_documents    enable row level security;

-- Helpers used by the rules below. They live in a 'private' schema so
-- they can't be called from the public web API.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- Helper: the pro row for whoever is signed in.
create or replace function private.current_pro_id() returns uuid
language sql stable security definer set search_path = public
as $$ select id from public.pros where auth_user_id = auth.uid() $$;

-- Pros: read and edit their own profile (not their status or checks).
create policy "pro reads own profile" on public.pros
  for select to authenticated using (auth_user_id = auth.uid());
create policy "pro updates own profile" on public.pros
  for update to authenticated using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());
revoke update on public.pros from authenticated;
grant update (business_name, contact_name, phone, email, trades, zip_codes,
              license_number, weekly_budget_cents) on public.pros to authenticated;

-- Prices are public to signed-in pros.
create policy "pros read prices" on public.price_list
  for select to authenticated using (true);

-- Lead assignments: a pro sees and updates (status only) their own.
create policy "pro reads own leads" on public.lead_assignments
  for select to authenticated using (pro_id = private.current_pro_id());
create policy "pro updates own lead status" on public.lead_assignments
  for update to authenticated using (pro_id = private.current_pro_id())
  with check (pro_id = private.current_pro_id());
revoke update on public.lead_assignments from authenticated;
grant update (status, contacted_at, closed_at) on public.lead_assignments to authenticated;

-- Helpers that check access without re-triggering these same rules
-- (policies that query each other directly would loop forever).
create or replace function private.current_homeowner_id() returns uuid
language sql stable security definer set search_path = public
as $$ select id from public.homeowners where auth_user_id = auth.uid() $$;

create or replace function private.pro_has_request(p_request_id uuid) returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.lead_assignments
                     where request_id = p_request_id and pro_id = private.current_pro_id()) $$;

create or replace function private.pro_has_homeowner(p_homeowner_id uuid) returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.requests r
                     join public.lead_assignments a on a.request_id = r.id
                     where r.homeowner_id = p_homeowner_id and a.pro_id = private.current_pro_id()) $$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- Requests and homeowner contact details: only for the pro the lead was assigned to.
create policy "pro reads assigned requests" on public.requests
  for select to authenticated using (private.pro_has_request(id));
create policy "pro reads assigned homeowners" on public.homeowners
  for select to authenticated using (private.pro_has_homeowner(id));

-- Homeowners who sign in can see their own profile and requests.
create policy "homeowner reads own profile" on public.homeowners
  for select to authenticated using (auth_user_id = auth.uid());
create policy "homeowner reads own requests" on public.requests
  for select to authenticated using (homeowner_id = private.current_homeowner_id());

-- Money, credits, calls, documents: read-only, own rows.
create policy "pro reads own ledger" on public.ledger_entries
  for select to authenticated using (pro_id = private.current_pro_id());
create policy "pro reads own credits" on public.credits
  for select to authenticated using (
    exists (select 1 from public.lead_assignments a
            where a.id = credits.lead_assignment_id and a.pro_id = private.current_pro_id()));
create policy "pro reads own calls" on public.calls
  for select to authenticated using (pro_id = private.current_pro_id());
create policy "pro reads own documents" on public.pro_documents
  for select to authenticated using (pro_id = private.current_pro_id());

-- Table access. New Supabase projects don't grant these automatically.
-- Server-side code (Edge Functions with the service role key) gets full access.
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on function public.assign_lead(uuid, uuid, public.lead_product) to service_role;
grant execute on function public.issue_credit(uuid, public.credit_reason, boolean, text) to service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to service_role;
-- Signed-in users can read; row-level security still limits them to their own rows.
grant select on public.pros, public.price_list, public.lead_assignments, public.requests,
  public.homeowners, public.ledger_entries, public.credits, public.calls,
  public.pro_documents, public.pro_balances to authenticated;
-- The public (anon) gets nothing: the website form goes through the server function.

-- ---------------------------------------------------------------------
-- 6. Starting prices (placeholders from the business plan; edit freely)
-- ---------------------------------------------------------------------
insert into public.price_list (service, product, price_cents) values
  ('handyman',           'form_lead',    3500),
  ('tv_mounting',        'form_lead',    3500),
  ('drywall',            'form_lead',    3500),
  ('furniture_assembly', 'form_lead',    3500),
  ('handyman',           'call',         5000),
  ('tv_mounting',        'call',         5000),
  ('drywall',            'call',         5000),
  ('furniture_assembly', 'call',         5000),
  ('garage_door',        'premium_call', 6500),
  ('appliance_repair',   'premium_call', 6500);
