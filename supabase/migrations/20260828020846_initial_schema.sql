-- Mise — initial schema (M1.2)
-- Implements docs/SCHEMA-NOTES.md. Read that file for the rationale behind every
-- choice here, including the ones that look wrong at a glance (see the note on
-- recipe_ingredients below).

create extension if not exists citext;      -- case-insensitive text: 'Scallion' = 'scallion'
create extension if not exists pg_trgm;     -- trigram search: "green oni" -> scallion

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

-- 'in_review' exists now because M1.5.6 needs an admin review queue. Adding an
-- enum value later is a migration; adding it today is free.
create type recipe_status as enum ('draft', 'in_review', 'published');

create type unit_kind as enum ('mass', 'volume', 'count');

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------

create table profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     citext unique,
  display_name text,
  created_at   timestamptz not null default now()
);

comment on table profiles is
  'Mirrors auth.users, which Supabase owns. FKs point here, never into the auth schema.';

-- ---------------------------------------------------------------------------
-- Lookup vocabularies
-- Four separate tables rather than one generic `tags` table: the four facets
-- behave differently (cuisine is single-valued; allergens are an EXCLUSION
-- filter). See SCHEMA-NOTES.md Decision 1.
-- ---------------------------------------------------------------------------

create table cuisines (
  id   integer generated always as identity primary key,
  name text not null unique,
  slug text not null unique
);

create table diets (
  id   integer generated always as identity primary key,
  name text not null unique,
  slug text not null unique
);

create table cookware (
  id   integer generated always as identity primary key,
  name text not null unique,
  slug text not null unique
);

create table allergens (
  id   integer generated always as identity primary key,
  name text not null unique,
  slug text not null unique
);

-- A NULL to_base_factor is correct, not missing data: cloves do not convert to
-- millilitres. Callers must treat count units as un-summable across unit types.
create table units (
  id             integer generated always as identity primary key,
  name           citext not null unique,
  kind           unit_kind not null,
  to_base_factor numeric,
  constraint units_factor_matches_kind check (
    (kind = 'count' and to_base_factor is null) or
    (kind <> 'count' and to_base_factor is not null and to_base_factor > 0)
  )
);

comment on column units.to_base_factor is
  'Multiply by this to reach the base unit of `kind` (ml for volume, g for mass).';

-- ---------------------------------------------------------------------------
-- Ingredients — the canonical list. CLAUDE.md: every recipe ingredient must
-- resolve to a row here. Free text lives only in recipe_ingredients.prep_note.
-- ---------------------------------------------------------------------------

create table ingredients (
  id               integer generated always as identity primary key,
  canonical_name   citext not null unique,
  slug             text   not null unique,
  aisle_category   text   not null check (
    aisle_category in ('Produce', 'Pantry', 'Dairy', 'Protein', 'Spices', 'Other')
  ),
  -- Salt, pepper, water, oil, butter, sugar, flour. Never counted as "missing".
  -- Forgetting this makes every pantry match report missing items.
  is_pantry_staple boolean not null default false,
  fdc_id           integer,                          -- USDA FoodData Central, M1.5.4
  density_g_per_ml numeric check (density_g_per_ml > 0),
  created_at       timestamptz not null default now()
);

comment on column ingredients.density_g_per_ml is
  'Bridges volume to mass. A tbsp of honey and a tbsp of flour weigh different '
  'amounts, so unit factors alone cannot cross kinds. NULL means refuse the '
  'conversion rather than guess.';

create table ingredient_aliases (
  id            integer generated always as identity primary key,
  ingredient_id integer not null references ingredients (id) on delete cascade,
  alias         citext  not null unique
);

comment on table ingredient_aliases is
  'green onion -> scallion. Unresolved aliases do not error, they silently '
  'shrink the match rate, which is why M1.5.1 precedes every importer.';

-- Source of truth for allergens. Tagging `soy sauce` once as {soy, gluten}
-- makes every recipe using it correct forever. See SCHEMA-NOTES.md Decision 2.
create table ingredient_allergens (
  ingredient_id integer not null references ingredients (id) on delete cascade,
  allergen_id   integer not null references allergens   (id) on delete cascade,
  primary key (ingredient_id, allergen_id)
);

-- ---------------------------------------------------------------------------
-- Recipes
-- ---------------------------------------------------------------------------

create table recipes (
  id               uuid primary key default gen_random_uuid(),
  slug             text not null unique,
  title            text not null,
  description      text,
  cuisine_id       integer references cuisines (id) on delete set null,
  -- NULL = imported (USDA / Mise-authored). Load-bearing for RLS: the M1.3 rule
  -- `author_id = auth.uid()` is never true for NULL, so nobody can edit imports.
  author_id        uuid    references profiles (id) on delete set null,
  status           recipe_status not null default 'draft',

  -- Stored separately even though the mockup shows one number: "20 min prep,
  -- 4 min cook" and the reverse are different weeknight propositions.
  prep_time_min    integer check (prep_time_min >= 0),
  cook_time_min    integer check (cook_time_min >= 0),
  total_time_min   integer generated always as (
                     coalesce(prep_time_min, 0) + coalesce(cook_time_min, 0)
                   ) stored,

  servings         integer  not null check (servings > 0),
  spice_level      smallint check (spice_level between 0 and 4),
  cost_per_serving numeric(8, 2) check (cost_per_serving >= 0),

  -- Nutrition PER SERVING, not per recipe. Every filter the user sets means
  -- per serving. Six columns rather than a join table because macro range
  -- filters are the hot path. See SCHEMA-NOTES.md Decision 4.
  calories         numeric check (calories  >= 0),
  protein_g        numeric check (protein_g >= 0),
  carbs_g          numeric check (carbs_g   >= 0),
  fat_g            numeric check (fat_g     >= 0),
  sodium_mg        numeric check (sodium_mg >= 0),
  fiber_g          numeric check (fiber_g   >= 0),

  image_url        text,
  notes            text,

  -- CLAUDE.md forbids importing without a confirmed licence. Per-recipe
  -- provenance is what makes that auditable after the fact.
  source_name      text,
  source_url       text,
  source_license   text,

  -- Trigger-maintained, NOT generated: a generated column may only reference
  -- its own row, and this needs ingredient names from two other tables.
  search_vector    tsvector,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  published_at     timestamptz,

  constraint recipes_published_has_date
    check (status <> 'published' or published_at is not null)
);

create table recipe_steps (
  id          bigint generated always as identity primary key,
  recipe_id   uuid    not null references recipes (id) on delete cascade,
  sort_order  integer not null,
  instruction text    not null,
  unique (recipe_id, sort_order)
);

-- NOTE: there is deliberately NO unique constraint on (recipe_id, ingredient_id).
-- "1 tbsp oil for the pan, 2 tbsp for the dressing" is two legitimate rows for
-- the same ingredient. Adding that constraint looks obviously correct and would
-- reject real recipes. The consequence: ranking queries must use
-- count(DISTINCT ingredient_id), never count(*).
create table recipe_ingredients (
  id            bigint  generated always as identity primary key,
  recipe_id     uuid    not null references recipes     (id) on delete cascade,
  ingredient_id integer not null references ingredients (id) on delete restrict,
  quantity      numeric check (quantity > 0),         -- NULL = "to taste"
  unit_id       integer references units (id) on delete restrict,
  prep_note     text,                                 -- the ONLY free text
  is_optional   boolean not null default false,
  sort_order    integer not null,
  unique (recipe_id, sort_order)
);

create table recipe_diets (
  recipe_id uuid    not null references recipes (id) on delete cascade,
  diet_id   integer not null references diets   (id) on delete cascade,
  primary key (recipe_id, diet_id)
);

create table recipe_cookware (
  recipe_id   uuid    not null references recipes  (id) on delete cascade,
  cookware_id integer not null references cookware (id) on delete cascade,
  primary key (recipe_id, cookware_id)
);

-- DERIVED CACHE. Never write to this by hand; it is rebuilt from
-- ingredient_allergens by trigger. Present for query speed on the hot path.
create table recipe_allergens (
  recipe_id   uuid    not null references recipes   (id) on delete cascade,
  allergen_id integer not null references allergens (id) on delete cascade,
  primary key (recipe_id, allergen_id)
);

create table favorites (
  user_id    uuid not null references profiles (id) on delete cascade,
  recipe_id  uuid not null references recipes  (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

-- ---------------------------------------------------------------------------
-- Derived data: allergen cache
-- ---------------------------------------------------------------------------

create or replace function refresh_recipe_allergens(p_recipe_id uuid)
returns void
language sql
as $$
  delete from recipe_allergens where recipe_id = p_recipe_id;

  insert into recipe_allergens (recipe_id, allergen_id)
  select distinct ri.recipe_id, ia.allergen_id
  from   recipe_ingredients ri
  join   ingredient_allergens ia on ia.ingredient_id = ri.ingredient_id
  where  ri.recipe_id = p_recipe_id;
$$;

-- Recipe's ingredient list changed -> its allergens may have changed.
create or replace function trg_sync_allergens_from_recipe_ingredients()
returns trigger
language plpgsql
as $$
declare
  target uuid;
begin
  -- NEW is unassigned on DELETE and OLD is unassigned on INSERT; referencing
  -- the wrong one raises "record is not assigned yet". coalesce() does NOT
  -- save you here, because the field access itself is what fails.
  if tg_op = 'DELETE' then
    target := old.recipe_id;
  else
    target := new.recipe_id;
  end if;

  perform refresh_recipe_allergens(target);
  return null;
end;
$$;

create trigger recipe_ingredients_sync_allergens
after insert or update or delete on recipe_ingredients
for each row execute function trg_sync_allergens_from_recipe_ingredients();

-- An ingredient's allergens changed -> every recipe using it is now stale.
-- This is the case per-recipe tagging cannot handle at all.
create or replace function trg_sync_allergens_from_ingredient()
returns trigger
language plpgsql
as $$
declare
  r      uuid;
  target integer;
begin
  if tg_op = 'DELETE' then
    target := old.ingredient_id;
  else
    target := new.ingredient_id;
  end if;

  for r in
    select distinct recipe_id
    from   recipe_ingredients
    where  ingredient_id = target
  loop
    perform refresh_recipe_allergens(r);
  end loop;
  return null;
end;
$$;

create trigger ingredient_allergens_sync_recipes
after insert or update or delete on ingredient_allergens
for each row execute function trg_sync_allergens_from_ingredient();

-- ---------------------------------------------------------------------------
-- Derived data: search vector, updated_at, published_at
--
-- Computed in a BEFORE trigger on `recipes` rather than an AFTER trigger that
-- UPDATEs the row, which would recurse infinitely.
-- ---------------------------------------------------------------------------

create or replace function trg_recipes_before_write()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();

  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;

  new.search_vector :=
       setweight(to_tsvector('english', coalesce(new.title, '')), 'A')
    || setweight(to_tsvector('english', coalesce((
         select string_agg(i.canonical_name::text, ' ')
         from   recipe_ingredients ri
         join   ingredients i on i.id = ri.ingredient_id
         where  ri.recipe_id = new.id
       ), '')), 'B')
    || setweight(to_tsvector('english', concat_ws(' ',
         (select c.name from cuisines c where c.id = new.cuisine_id),
         (select string_agg(d.name, ' ')
          from   recipe_diets rd
          join   diets d on d.id = rd.diet_id
          where  rd.recipe_id = new.id)
       )), 'C');

  return new;
end;
$$;

create trigger recipes_before_write
before insert or update on recipes
for each row execute function trg_recipes_before_write();

-- Ingredients and diet tags are inserted AFTER the recipe row exists, so the
-- vector computed at insert time is incomplete. Touching the recipe re-runs the
-- BEFORE trigger, which recomputes it. One mechanism, not two.
create or replace function trg_touch_parent_recipe()
returns trigger
language plpgsql
as $$
declare
  target uuid;
begin
  if tg_op = 'DELETE' then
    target := old.recipe_id;
  else
    target := new.recipe_id;
  end if;

  update recipes set updated_at = now() where id = target;
  return null;
end;
$$;

create trigger recipe_ingredients_touch_recipe
after insert or update or delete on recipe_ingredients
for each row execute function trg_touch_parent_recipe();

create trigger recipe_diets_touch_recipe
after insert or update or delete on recipe_diets
for each row execute function trg_touch_parent_recipe();

-- ---------------------------------------------------------------------------
-- Indexes. Each one serves a named query; see SCHEMA-NOTES.md.
-- ---------------------------------------------------------------------------

-- The single hottest lookup in the product: the pantry matcher.
create index recipe_ingredients_ingredient_idx on recipe_ingredients (ingredient_id);
create index recipe_ingredients_recipe_idx     on recipe_ingredients (recipe_id);

create index recipe_steps_recipe_idx           on recipe_steps        (recipe_id);
create index recipe_allergens_allergen_idx     on recipe_allergens    (allergen_id);
create index recipe_diets_diet_idx             on recipe_diets        (diet_id);
create index recipe_cookware_cookware_idx      on recipe_cookware     (cookware_id);
create index ingredient_aliases_ingredient_idx on ingredient_aliases  (ingredient_id);
create index favorites_recipe_idx              on favorites           (recipe_id);

-- M3.5 full-text search.
create index recipes_search_idx on recipes using gin (search_vector);

-- M3.3 autocomplete: typing "green oni" must offer "scallion".
create index ingredients_name_trgm_idx  on ingredients        using gin (canonical_name gin_trgm_ops);
create index ingredient_aliases_trgm_idx on ingredient_aliases using gin (alias gin_trgm_ops);

-- Browse + cursor pagination, published rows only. CLAUDE.md mandates cursor
-- pagination, which needs a unique tiebreak column -- hence the trailing id.
create index recipes_browse_idx on recipes (published_at desc, id)
  where status = 'published';

create index recipes_cuisine_idx on recipes (cuisine_id);
create index recipes_author_idx  on recipes (author_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- Enabled here with NO policies, which denies everything to the publishable
-- key. Policies are M1.3. RLS-off plus a public key would mean the whole
-- database is readable and writable by anyone in the window between the two
-- milestones -- so the safe default goes in now.
-- ---------------------------------------------------------------------------

alter table profiles            enable row level security;
alter table cuisines            enable row level security;
alter table diets               enable row level security;
alter table cookware            enable row level security;
alter table allergens           enable row level security;
alter table units               enable row level security;
alter table ingredients         enable row level security;
alter table ingredient_aliases  enable row level security;
alter table ingredient_allergens enable row level security;
alter table recipes             enable row level security;
alter table recipe_steps        enable row level security;
alter table recipe_ingredients  enable row level security;
alter table recipe_diets        enable row level security;
alter table recipe_cookware     enable row level security;
alter table recipe_allergens    enable row level security;
alter table favorites           enable row level security;

-- ---------------------------------------------------------------------------
-- Reference vocabularies. Fixed lists taken from design/Mise.dc.html.
-- Idempotent so re-running the migration is safe.
-- ---------------------------------------------------------------------------

insert into cuisines (name, slug) values
  ('Korean', 'korean'), ('Indian', 'indian'), ('Italian', 'italian'),
  ('Japanese', 'japanese'), ('North African', 'north-african'),
  ('Tunisian', 'tunisian'), ('Middle Eastern', 'middle-eastern')
on conflict (name) do nothing;

insert into diets (name, slug) values
  ('Vegan', 'vegan'), ('Vegetarian', 'vegetarian'),
  ('Pescatarian', 'pescatarian'), ('Gluten-free', 'gluten-free')
on conflict (name) do nothing;

insert into cookware (name, slug) values
  ('Sheet pan', 'sheet-pan'), ('Skillet', 'skillet'), ('Dutch oven', 'dutch-oven'),
  ('Pot', 'pot'), ('Saucepan', 'saucepan'), ('Small saucepan', 'small-saucepan')
on conflict (name) do nothing;

insert into allergens (name, slug) values
  ('Gluten', 'gluten'), ('Dairy', 'dairy'), ('Egg', 'egg'),
  ('Fish', 'fish'), ('Soy', 'soy'), ('Nuts', 'nuts'),
  ('Shellfish', 'shellfish'), ('Sesame', 'sesame')
on conflict (name) do nothing;

insert into units (name, kind, to_base_factor) values
  ('g',      'mass',   1),
  ('kg',     'mass',   1000),
  ('oz',     'mass',   28.3495),
  ('lb',     'mass',   453.592),
  ('ml',     'volume', 1),
  ('l',      'volume', 1000),
  ('tsp',    'volume', 4.92892),
  ('tbsp',   'volume', 14.7868),
  ('cup',    'volume', 236.588),
  ('clove',  'count',  null),
  ('head',   'count',  null),
  ('stalk',  'count',  null),
  ('fillet', 'count',  null),
  ('can',    'count',  null),
  ('bunch',  'count',  null),
  ('piece',  'count',  null)
on conflict (name) do nothing;
