-- Listing subcategories + category rename.
--
-- The create-listing form now has a second, category-dependent "Type"
-- dropdown (e.g. Poultry → Chicken / Gamefowl / …) stored in `subcategory`,
-- and the "Aquatics" category was renamed to "Aquaculture" app-wide.
--
-- Idempotent: safe to re-run.

alter table public.listings
  add column if not exists subcategory text;

-- The table's CHECK constraint only allows the legacy category names, which
-- blocks both the rename below and inserts with the new categories — drop
-- it first, then re-add it with the current allow-list.
alter table public.listings
  drop constraint if exists listings_category_check;

-- Rename the category on existing listings so they keep showing up under
-- the renamed browse chip.
update public.listings
   set category = 'Aquaculture'
 where category = 'Aquatics';

-- NOT VALID: enforce the allow-list on new writes only, so a stray legacy
-- category value on an old row can't make this migration fail.
alter table public.listings
  add constraint listings_category_check
  check (category in (
    'Poultry',
    'Small Livestock',
    'Large Livestock',
    'Aquaculture',
    'Ornamental Fish',
    'Hatching & Breeding Products'
  )) not valid;
