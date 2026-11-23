-- Round 124: the cloud save tables for Dungeon Crawl Elite.
-- Run once in a Supabase project (SQL editor, or `supabase db push`). Then put the project's address and its
-- PUBLIC anon key in the game's Cloud save window (or in data/cloud.json). Nothing here is readable by anyone
-- but the signed-in owner of a row.

create table if not exists public.game_saves (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  game       text not null,
  slot       int  not null check (slot between 1 and 9),
  saved_at   double precision not null default 0,     -- the save's own clock (unix seconds), not the server's
  device     text,
  summary    text,
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, game, slot)
);

alter table public.game_saves enable row level security;

drop policy if exists "own saves: read"   on public.game_saves;
drop policy if exists "own saves: add"    on public.game_saves;
drop policy if exists "own saves: change" on public.game_saves;
drop policy if exists "own saves: remove" on public.game_saves;
create policy "own saves: read"   on public.game_saves for select to authenticated using (auth.uid() = user_id);
create policy "own saves: add"    on public.game_saves for insert to authenticated with check (auth.uid() = user_id);
create policy "own saves: change" on public.game_saves for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own saves: remove" on public.game_saves for delete to authenticated using (auth.uid() = user_id);

-- the last five versions of every slot are kept, so a bad sync can be undone by hand
create table if not exists public.game_saves_history (
  id         bigint generated always as identity primary key,
  user_id    uuid not null,
  game       text not null,
  slot       int  not null,
  saved_at   double precision not null,
  device     text,
  summary    text,
  data       jsonb not null,
  archived_at timestamptz not null default now()
);
alter table public.game_saves_history enable row level security;
drop policy if exists "own history: read" on public.game_saves_history;
create policy "own history: read" on public.game_saves_history for select to authenticated using (auth.uid() = user_id);

create or replace function public.game_saves_archive() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.game_saves_history (user_id, game, slot, saved_at, device, summary, data)
  values (old.user_id, old.game, old.slot, old.saved_at, old.device, old.summary, old.data);
  delete from public.game_saves_history h
   where h.user_id = old.user_id and h.game = old.game and h.slot = old.slot
     and h.id not in (select id from public.game_saves_history
                       where user_id = old.user_id and game = old.game and slot = old.slot
                       order by id desc limit 5);
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists game_saves_archive on public.game_saves;
create trigger game_saves_archive before update on public.game_saves
  for each row execute function public.game_saves_archive();
