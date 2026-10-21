-- Organisations, branches, territories, warehouses, people and relationships.
-- Composite foreign keys on (id, org_id) / (id, kind) make cross-tenant references impossible by construction.

create table public.organisations (
  id                uuid primary key default gen_random_uuid(),
  kind              public.org_kind not null,
  name              text not null check (length(btrim(name)) > 0),
  slug              text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  status            public.record_status not null default 'pending',
  location          extensions.geography(Point, 4326),
  split_threshold_m integer check (split_threshold_m is null or split_threshold_m >= 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (id, kind),
  constraint organisations_retailer_has_location check (kind <> 'retailer' or location is not null),
  constraint organisations_split_threshold_distributor_only check (kind = 'distributor' or split_threshold_m is null)
);
create unique index organisations_single_platform on public.organisations (kind) where kind = 'platform';
create index organisations_location_gix on public.organisations using gist (location);

create table public.branches (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null,
  org_kind   public.org_kind not null default 'distributor' check (org_kind = 'distributor'),
  name       text not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default now(),
  foreign key (org_id, org_kind) references public.organisations (id, kind),
  unique (id, org_id),
  unique (org_id, name)
);

create table public.territories (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null,
  branch_id  uuid not null,
  name       text not null check (length(btrim(name)) > 0),
  boundary   extensions.geography(MultiPolygon, 4326),
  created_at timestamptz not null default now(),
  foreign key (branch_id, org_id) references public.branches (id, org_id),
  unique (id, org_id),
  unique (id, branch_id),
  unique (org_id, name)
);
create index territories_branch_idx on public.territories (branch_id);

create table public.warehouses (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null,
  branch_id  uuid not null,
  name       text not null check (length(btrim(name)) > 0),
  location   extensions.geography(Point, 4326) not null,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (branch_id, org_id) references public.branches (id, org_id),
  unique (id, org_id),
  unique (org_id, name)
);
create index warehouses_branch_idx on public.warehouses (branch_id);
create index warehouses_location_gix on public.warehouses using gist (location);

-- Minimal personal data (NDPA s.24(1)(c)): name + phone for OTP delivery. No BVN/NIN here, ever.
create table public.profiles (
  user_id    uuid primary key references auth.users (id) on delete restrict,
  full_name  text not null check (length(btrim(full_name)) > 0),
  phone_e164 text check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (user_id),
  org_id       uuid not null,
  org_kind     public.org_kind not null,
  role         public.member_role not null,
  branch_id    uuid,
  territory_id uuid,
  status       public.record_status not null default 'pending',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  foreign key (org_id, org_kind) references public.organisations (id, kind),
  foreign key (branch_id, org_id) references public.branches (id, org_id),
  foreign key (territory_id, branch_id) references public.territories (id, branch_id),
  unique (user_id, org_id, role),
  constraint memberships_role_matches_org_kind check (
       (role = 'platform_admin' and org_kind = 'platform')
    or (role = 'manufacturer_admin' and org_kind = 'manufacturer')
    or (role in ('distributor_admin', 'branch_manager', 'warehouse_staff', 'driver', 'agent')
        and org_kind = 'distributor')
    or (role = 'retailer' and org_kind = 'retailer')
  ),
  constraint memberships_branch_roles_have_branch check (
    (role in ('branch_manager', 'warehouse_staff', 'driver', 'agent')) = (branch_id is not null)
  ),
  constraint memberships_agents_have_territory check ((role = 'agent') = (territory_id is not null))
);
create index memberships_user_idx on public.memberships (user_id);
create index memberships_org_idx on public.memberships (org_id);
create index memberships_branch_idx on public.memberships (branch_id);
create index memberships_territory_idx on public.memberships (territory_id);

-- Which distributors a retailer buys from, in which territory, with what distributor-extended credit limit.
create table public.customer_relationships (
  id                 uuid primary key default gen_random_uuid(),
  distributor_org_id uuid not null,
  distributor_kind   public.org_kind not null default 'distributor' check (distributor_kind = 'distributor'),
  retailer_org_id    uuid not null,
  retailer_kind      public.org_kind not null default 'retailer' check (retailer_kind = 'retailer'),
  territory_id       uuid not null,
  credit_limit_kobo  bigint not null default 0 check (credit_limit_kobo >= 0),
  status             public.record_status not null default 'pending',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  foreign key (distributor_org_id, distributor_kind) references public.organisations (id, kind),
  foreign key (retailer_org_id, retailer_kind) references public.organisations (id, kind),
  foreign key (territory_id, distributor_org_id) references public.territories (id, org_id),
  unique (distributor_org_id, retailer_org_id)
);
create index customer_relationships_retailer_idx on public.customer_relationships (retailer_org_id);
create index customer_relationships_territory_idx on public.customer_relationships (territory_id);

create table public.supply_relationships (
  manufacturer_org_id uuid not null,
  manufacturer_kind   public.org_kind not null default 'manufacturer' check (manufacturer_kind = 'manufacturer'),
  distributor_org_id  uuid not null,
  distributor_kind    public.org_kind not null default 'distributor' check (distributor_kind = 'distributor'),
  created_at          timestamptz not null default now(),
  primary key (manufacturer_org_id, distributor_org_id),
  foreign key (manufacturer_org_id, manufacturer_kind) references public.organisations (id, kind),
  foreign key (distributor_org_id, distributor_kind) references public.organisations (id, kind)
);
create index supply_relationships_distributor_idx on public.supply_relationships (distributor_org_id);

create trigger organisations_updated_at before update on public.organisations
  for each row execute function app.tg_set_updated_at();
create trigger profiles_updated_at before update on public.profiles
  for each row execute function app.tg_set_updated_at();
create trigger memberships_updated_at before update on public.memberships
  for each row execute function app.tg_set_updated_at();
create trigger customer_relationships_updated_at before update on public.customer_relationships
  for each row execute function app.tg_set_updated_at();
