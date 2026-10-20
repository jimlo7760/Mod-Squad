-- Assignment 4: AI-generated car builds, votes, and Row Level Security.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run. Run supabase/profiles.sql first (it is already applied if
-- Assignment 3 works).
--
-- WARNING: section 5 revokes every privilege on `builds` and grants them again,
-- which also wipes the column grants made by assignment4_photos.sql and
-- assignment4_render.sql. If you re-run THIS file, re-run those two after it, in
-- order, or saving a build fails with "permission denied for table builds".
-- Easiest: paste all four together (the last one, assignment4_edit.sql, uses functions instead of
-- column grants, so it survives a re-run of this file, but it is safe to paste again):
--   cat supabase/assignment4.sql supabase/assignment4_photos.sql supabase/assignment4_render.sql supabase/assignment4_edit.sql | pbcopy
--
-- Security model, strictest that still lets the app work:
--   * Every table has RLS on. Logged-out visitors (the `anon` role) get nothing,
--     except a read-only look at the "Car" catalogue (last bullet).
--   * builds:      any signed-in user can read; you can only create/delete your own.
--                  Vote counters can't be written by clients (only by a trigger).
--   * build_votes: you can only see and change your own votes; you can't vote
--                  on your own build; one vote per user per build.
--   * profiles:    any signed-in user can read (names/photos show on builds);
--                  you can only create/update your own row.
--   * "Car":       read-only catalogue of brands and models, public reference data.
--                  Signed-in users and anon can read it; nobody can change it from the app.
--                  anon stays ON PURPOSE: the earlier commit-specific deployments (Assignment
--                  2/3) query it with a plain Supabase client that carries no session, and
--                  without this they show "permission denied for table Car".


-- 1. builds: one row per AI generation ---------------------------------------
create table if not exists public.builds (
    id           uuid primary key default gen_random_uuid(),
    -- References profiles (not auth.users) so one query can fetch the creator's name and photo.
    user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,

    -- What the user asked for, and exactly what we sent to the model.
    car_name     text not null check (char_length(car_name) between 1 and 80),
    vibe         text not null check (char_length(vibe) between 1 and 200),
    prompt       text not null,   -- the full prompt sent to the AI
    model        text not null,   -- which AI model answered

    -- What the AI gave back.
    title        text not null,
    tagline      text not null,
    mods         jsonb not null,  -- [{ category, part, detail }]
    est_cost_usd integer,
    photo_url    text,            -- optional photo the user uploaded of the car

    -- Denormalised vote counters, kept in sync by a trigger (section 3).
    upvotes      integer not null default 0,
    downvotes    integer not null default 0,
    score        integer generated always as (upvotes - downvotes) stored,

    created_at   timestamptz not null default now()
);

create index if not exists builds_created_at_idx on public.builds (created_at desc);
create index if not exists builds_score_idx on public.builds (score desc, created_at desc);
create index if not exists builds_user_idx on public.builds (user_id, created_at desc);


-- 2. build_votes: one row per (user, build) ---------------------------------
create table if not exists public.build_votes (
    id         bigint generated always as identity primary key,
    build_id   uuid not null references public.builds (id) on delete cascade,
    user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
    value      smallint not null check (value in (-1, 1)),  -- 1 = upvote, -1 = downvote
    created_at timestamptz not null default now(),
    unique (build_id, user_id)
);

create index if not exists build_votes_user_idx on public.build_votes (user_id);


-- 3. keep builds.upvotes / downvotes in sync ----------------------------------
-- security definer: clients may not update builds, but this trigger may.
create or replace function public.apply_vote_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_op in ('UPDATE', 'DELETE') then
        update public.builds
           set upvotes   = upvotes   - (old.value = 1)::int,
               downvotes = downvotes - (old.value = -1)::int
         where id = old.build_id;
    end if;
    if tg_op in ('INSERT', 'UPDATE') then
        update public.builds
           set upvotes   = upvotes   + (new.value = 1)::int,
               downvotes = downvotes + (new.value = -1)::int
         where id = new.build_id;
    end if;
    return null;
end;
$$;

drop trigger if exists build_votes_count on public.build_votes;
create trigger build_votes_count
    after insert or update of value or delete on public.build_votes
    for each row execute function public.apply_vote_change();


-- 4. daily generation limit (protects the free AI quota) ---------------------
create or replace function public.limit_daily_builds()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if (select count(*) from public.builds
         where user_id = new.user_id
           and created_at > now() - interval '24 hours') >= 10 then
        raise exception 'Daily limit reached: you can generate 10 builds per 24 hours.'
            using errcode = 'P0001';
    end if;
    return new;
end;
$$;

drop trigger if exists builds_daily_limit on public.builds;
create trigger builds_daily_limit
    before insert on public.builds
    for each row execute function public.limit_daily_builds();


-- 5. privileges: start from nothing, grant only what the app uses -------------
revoke all on public.builds      from anon, authenticated;
revoke all on public.build_votes from anon, authenticated;
revoke all on public."Car"       from anon, authenticated;
revoke all on public.profiles    from anon, authenticated;

-- Column-level insert: clients cannot set upvotes/downvotes/score/id/created_at.
grant select on public.builds to authenticated;
grant insert (car_name, vibe, prompt, model, title, tagline, mods, est_cost_usd, photo_url)
    on public.builds to authenticated;
grant delete on public.builds to authenticated;

grant select, delete on public.build_votes to authenticated;
grant insert (build_id, value) on public.build_votes to authenticated;
grant update (value) on public.build_votes to authenticated;

-- "Car" is a public catalogue: anon may read it too (see the header), nobody may write.
grant select on public."Car" to anon, authenticated;
grant select, insert, update on public.profiles to authenticated;


-- 6. Row Level Security -------------------------------------------------------
alter table public.builds      enable row level security;
alter table public.build_votes enable row level security;
alter table public."Car"       enable row level security;
alter table public.profiles    enable row level security;

-- builds
drop policy if exists "Signed-in users can read builds" on public.builds;
create policy "Signed-in users can read builds"
    on public.builds for select to authenticated
    using (true);

drop policy if exists "Users can create their own builds" on public.builds;
create policy "Users can create their own builds"
    on public.builds for insert to authenticated
    with check (user_id = (select auth.uid()));

drop policy if exists "Users can delete their own builds" on public.builds;
create policy "Users can delete their own builds"
    on public.builds for delete to authenticated
    using (user_id = (select auth.uid()));

-- build_votes: you only ever see and touch your own votes, and never on your own build.
drop policy if exists "Users can read their own votes" on public.build_votes;
create policy "Users can read their own votes"
    on public.build_votes for select to authenticated
    using (user_id = (select auth.uid()));

drop policy if exists "Users can vote on other people's builds" on public.build_votes;
create policy "Users can vote on other people's builds"
    on public.build_votes for insert to authenticated
    with check (
        user_id = (select auth.uid())
        and not exists (
            select 1 from public.builds b
             where b.id = build_id and b.user_id = (select auth.uid())
        )
    );

drop policy if exists "Users can change their own votes" on public.build_votes;
create policy "Users can change their own votes"
    on public.build_votes for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

drop policy if exists "Users can remove their own votes" on public.build_votes;
create policy "Users can remove their own votes"
    on public.build_votes for delete to authenticated
    using (user_id = (select auth.uid()));

-- "Car": read-only catalogue. Signed-in users, plus anon for the earlier deployments.
drop policy if exists "Signed-in users can read cars" on public."Car";
create policy "Signed-in users can read cars"
    on public."Car" for select to authenticated
    using (true);

drop policy if exists "Anyone can read cars" on public."Car";
create policy "Anyone can read cars"
    on public."Car" for select to anon
    using (true);

-- profiles: names and photos are shown next to builds, so signed-in users can read all.
drop policy if exists "Signed-in users can read profiles" on public.profiles;
create policy "Signed-in users can read profiles"
    on public.profiles for select to authenticated
    using (true);

drop policy if exists "Users can create their own profile" on public.profiles;
create policy "Users can create their own profile"
    on public.profiles for insert to authenticated
    with check (id = (select auth.uid()));

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
    on public.profiles for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- Anything else in the public schema (tables you made while experimenting) also
-- gets RLS. With no policy, a table with RLS on is closed to everyone but the owner.
do $$
declare t record;
begin
    for t in
        select tablename from pg_tables
         where schemaname = 'public' and not rowsecurity
    loop
        execute format('alter table public.%I enable row level security', t.tablename);
    end loop;
end $$;


-- 7. storage: bucket for the car photos users upload --------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'car-photos', 'car-photos', true,
    4194304,  -- 4 MB (Vercel's request limit is 4.5 MB)
    array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

-- Public buckets serve files by URL without any select policy, so we drop the
-- "anyone can list every avatar" policy from Assignment 3 and replace it with
-- "you can list your own folder" (needed so users can delete their own files).
drop policy if exists "Avatars are publicly readable" on storage.objects;

drop policy if exists "Users can read their own files" on storage.objects;
create policy "Users can read their own files"
    on storage.objects for select to authenticated
    using (
        bucket_id in ('avatars', 'car-photos')
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "Users can upload to their own car photo folder" on storage.objects;
create policy "Users can upload to their own car photo folder"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'car-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

drop policy if exists "Users can delete from their own car photo folder" on storage.objects;
create policy "Users can delete from their own car photo folder"
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'car-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );


-- Optional checks after running:
--   select tablename, rowsecurity from pg_tables where schemaname = 'public';
--   select * from pg_policies where schemaname in ('public', 'storage');
