-- Mise — Row Level Security policies (M1.3)
--
-- RLS was enabled in the initial migration with zero policies, which denies
-- everything. This file grants back exactly what should be allowed.
--
-- Mental model: a policy is a WHERE clause Postgres bolts onto every query
-- against the table, per command, per role. If no policy grants a row, the row
-- does not exist as far as that caller is concerned. There is no error and no
-- warning -- a SELECT simply returns fewer rows. That silence is why the test
-- plan at the bottom of this file matters more than the policies do.
--
-- `(select auth.uid())` rather than a bare `auth.uid()`: wrapping it in a
-- scalar subquery lets Postgres evaluate it ONCE per query instead of once per
-- row. On a 1,500-row scan that is the difference between one call and 1,500.

-- ---------------------------------------------------------------------------
-- Helper: is this recipe visible to the current caller?
--
-- Published recipes are visible to everyone. Drafts and in-review recipes are
-- visible only to their author. Every child table reuses this so the rule lives
-- in exactly one place -- if it changes, it changes once.
--
-- SECURITY DEFINER so the function itself can read `recipes` without being
-- filtered by the very policies it exists to evaluate, which would recurse.
-- search_path is pinned: a SECURITY DEFINER function with a mutable search_path
-- is a privilege-escalation hole.
-- ---------------------------------------------------------------------------

create or replace function public.can_read_recipe(p_recipe_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from   recipes r
    where  r.id = p_recipe_id
      and (r.status = 'published' or r.author_id = (select auth.uid()))
  );
$$;

create or replace function public.owns_recipe(p_recipe_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from   recipes r
    where  r.id = p_recipe_id
      and  r.author_id = (select auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Reference data: cuisines, diets, cookware, allergens, units, ingredients,
-- ingredient_aliases, ingredient_allergens.
--
-- World-readable, including logged out. Browse needs cuisine names, the pantry
-- autocomplete needs ingredient names and aliases, and the allergen filter
-- needs ingredient_allergens -- all before anyone signs in.
--
-- No INSERT/UPDATE/DELETE policy at all, which means nobody can write them
-- through the API. Imports run server-side with the secret key, which bypasses
-- RLS. Omitting a policy is the deny; there is no "deny" statement to write.
-- ---------------------------------------------------------------------------

create policy "reference data is public" on cuisines
  for select using (true);

create policy "reference data is public" on diets
  for select using (true);

create policy "reference data is public" on cookware
  for select using (true);

create policy "reference data is public" on allergens
  for select using (true);

create policy "reference data is public" on units
  for select using (true);

create policy "reference data is public" on ingredients
  for select using (true);

create policy "reference data is public" on ingredient_aliases
  for select using (true);

create policy "reference data is public" on ingredient_allergens
  for select using (true);

-- ---------------------------------------------------------------------------
-- profiles
--
-- Readable by everyone: recipe pages show an author name, and that has to work
-- for logged-out visitors. Only ever store public-facing fields here.
-- A user may update only their own row, and may not change its id.
-- ---------------------------------------------------------------------------

create policy "profiles are publicly readable" on profiles
  for select using (true);

create policy "users insert their own profile" on profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

create policy "users update their own profile" on profiles
  for update to authenticated
  using      (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- recipes
--
-- USING vs WITH CHECK, the distinction that trips everyone:
--   USING      -- which existing rows this command may touch (SELECT/UPDATE/DELETE)
--   WITH CHECK -- what the row is allowed to look like AFTER the write (INSERT/UPDATE)
--
-- UPDATE needs both. With only USING, a user could take a recipe they own and
-- reassign author_id to someone else -- the row they touched was theirs, and
-- nothing checks what it became. WITH CHECK closes that.
-- ---------------------------------------------------------------------------

create policy "published recipes are readable by everyone" on recipes
  for select using (status = 'published');

create policy "authors read their own drafts" on recipes
  for select to authenticated
  using (author_id = (select auth.uid()));

create policy "authors create their own recipes" on recipes
  for insert to authenticated
  with check (author_id = (select auth.uid()));

create policy "authors update their own recipes" on recipes
  for update to authenticated
  using      (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

create policy "authors delete their own recipes" on recipes
  for delete to authenticated
  using (author_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Recipe children: steps, ingredients, diet tags, cookware, allergen cache.
--
-- Visibility follows the parent recipe exactly. Without this, a draft recipe's
-- row would be hidden while its ingredient list stayed world-readable -- the
-- recipe leaks through the back door.
--
-- recipe_allergens is a derived cache maintained by trigger, so it gets SELECT
-- only. The triggers that write it run as the table owner, not the caller.
-- ---------------------------------------------------------------------------

create policy "steps follow recipe visibility" on recipe_steps
  for select using (can_read_recipe(recipe_id));

create policy "authors write their own steps" on recipe_steps
  for all to authenticated
  using      (owns_recipe(recipe_id))
  with check (owns_recipe(recipe_id));

create policy "ingredients follow recipe visibility" on recipe_ingredients
  for select using (can_read_recipe(recipe_id));

create policy "authors write their own recipe ingredients" on recipe_ingredients
  for all to authenticated
  using      (owns_recipe(recipe_id))
  with check (owns_recipe(recipe_id));

create policy "diet tags follow recipe visibility" on recipe_diets
  for select using (can_read_recipe(recipe_id));

create policy "authors write their own diet tags" on recipe_diets
  for all to authenticated
  using      (owns_recipe(recipe_id))
  with check (owns_recipe(recipe_id));

create policy "cookware follows recipe visibility" on recipe_cookware
  for select using (can_read_recipe(recipe_id));

create policy "authors write their own cookware" on recipe_cookware
  for all to authenticated
  using      (owns_recipe(recipe_id))
  with check (owns_recipe(recipe_id));

create policy "allergen cache follows recipe visibility" on recipe_allergens
  for select using (can_read_recipe(recipe_id));

-- ---------------------------------------------------------------------------
-- favorites
--
-- Entirely private. A user sees only their own rows -- not a count, not an
-- existence check, nothing. Note the INSERT policy also requires the recipe to
-- be readable: otherwise favouriting is an oracle that reveals which draft
-- recipe ids exist.
-- ---------------------------------------------------------------------------

create policy "users read their own favorites" on favorites
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "users add their own favorites" on favorites
  for insert to authenticated
  with check (user_id = (select auth.uid()) and can_read_recipe(recipe_id));

create policy "users remove their own favorites" on favorites
  for delete to authenticated
  using (user_id = (select auth.uid()));
