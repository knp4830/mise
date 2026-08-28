-- 'portion' is how the mockup measures fresh ramen noodles. It is a count unit,
-- so a NULL conversion factor is correct rather than missing: portions do not
-- convert to millilitres. The units_factor_matches_kind constraint enforces that.
insert into units (name, kind, to_base_factor)
values ('portion', 'count', null)
on conflict (name) do nothing;
