-- DuoUp backend schema for Supabase (free tier). Run once in: Supabase dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table public.profiles(
  id uuid primary key references auth.users on delete cascade,
  full_name text not null default '',
  nickname text not null default '',
  dob date,
  gender text, interest text,
  intents text[] not null default '{}',
  primary_lang text, other_langs text[] not null default '{}',
  games text, rank text, role text, city text not null default '',
  bio text not null default '' check (char_length(bio) <= 160),
  photos text[] not null default '{}' check (coalesce(array_length(photos,1),0) <= 6),
  tier text not null default '' check (tier in ('','Premium','Max')),
  status text not null default 'active' check (status in ('active','deactivated','banned')),
  verified boolean not null default false,
  is_admin boolean not null default false,
  onboarded boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.game_ids(
  user_id uuid primary key references public.profiles on delete cascade,
  bgmi_id text not null default '', ff_uid text not null default ''
);
create table public.swipes(
  from_id uuid references public.profiles on delete cascade,
  to_id uuid references public.profiles on delete cascade,
  liked boolean not null, created_at timestamptz not null default now(),
  primary key (from_id, to_id)
);
create index on public.swipes (to_id) where liked;
create table public.matches(
  id uuid primary key default gen_random_uuid(),
  a uuid not null references public.profiles on delete cascade,
  b uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  unique (a, b), check (a < b)
);
create table public.messages(
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches on delete cascade,
  sender_id uuid not null references public.profiles on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index on public.messages (match_id, created_at);
create table public.reports(
  id bigint generated always as identity primary key,
  reporter_id uuid references public.profiles on delete cascade,
  reported_id uuid references public.profiles on delete cascade,
  reason text not null default '', status text not null default 'open',
  created_at timestamptz not null default now()
);
create table public.contact_messages(
  id bigint generated always as identity primary key,
  user_id uuid references public.profiles on delete set null,
  email text check (char_length(email) <= 200),
  message text not null check (char_length(message) between 1 and 2000),
  created_at timestamptz not null default now()
);
create table public.upgrade_requests(
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  tier text not null check (tier in ('Premium','Max')),
  status text not null default 'open',
  created_at timestamptz not null default now()
);

-- helpers
create function public.age_of(d date) returns int language sql immutable as $$
  select date_part('year', age(d))::int $$;
create function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false) $$;
create function public.are_matched(u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from matches where a = least(auth.uid(), u) and b = greatest(auth.uid(), u)) $$;

-- new auth user -> profile row (also blocks under-13 signups on the server)
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare d date := nullif(new.raw_user_meta_data->>'dob','')::date;
begin
  if d is null or age_of(d) < 13 then raise exception 'DuoUp is for ages 13 and up'; end if;
  insert into profiles(id, full_name, dob) values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), d);
  insert into game_ids(user_id) values (new.id);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- users cannot grant themselves premium/admin/verified, edit DOB, or unban themselves; minors never keep "Dating"
create function public.protect_profile() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.dob is not null and age_of(new.dob) < 18 then new.intents := array_remove(new.intents, 'Dating'); end if;
  if auth.uid() is not null and not is_admin() then
    if new.is_admin <> old.is_admin or new.tier <> old.tier or new.verified <> old.verified
       or (new.status = 'banned') <> (old.status = 'banned') then raise exception 'not allowed'; end if;
    if old.dob is not null and new.dob is distinct from old.dob then raise exception 'date of birth cannot be changed'; end if;
  end if;
  return new;
end $$;
create trigger protect_profile before update on public.profiles for each row execute function public.protect_profile();

-- row level security
alter table public.profiles enable row level security;
alter table public.game_ids enable row level security;
alter table public.swipes enable row level security;
alter table public.matches enable row level security;
alter table public.messages enable row level security;
alter table public.reports enable row level security;
alter table public.contact_messages enable row level security;
alter table public.upgrade_requests enable row level security;

create policy "own or admin read" on public.profiles for select to authenticated using (id = auth.uid() or is_admin());
create policy "own update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "admin update" on public.profiles for update to authenticated using (is_admin());
create policy "ids read" on public.game_ids for select to authenticated using (user_id = auth.uid() or is_admin() or are_matched(user_id));
create policy "ids insert" on public.game_ids for insert to authenticated with check (user_id = auth.uid());
create policy "ids update" on public.game_ids for update to authenticated using (user_id = auth.uid());
create policy "own swipes" on public.swipes for select to authenticated using (from_id = auth.uid());
create policy "my matches" on public.matches for select to authenticated using (auth.uid() in (a, b));
create policy "read chat" on public.messages for select to authenticated
  using (exists (select 1 from matches m where m.id = match_id and auth.uid() in (m.a, m.b)));
create policy "send chat" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and exists (select 1 from matches m where m.id = match_id and auth.uid() in (m.a, m.b)));
create policy "admin reads reports" on public.reports for select to authenticated using (is_admin());
create policy "admin updates reports" on public.reports for update to authenticated using (is_admin());
create policy "send contact" on public.contact_messages for insert to anon, authenticated with check (true);
create policy "admin reads contact" on public.contact_messages for select to authenticated using (is_admin());
create policy "request upgrade" on public.upgrade_requests for insert to authenticated with check (user_id = auth.uid());
create policy "read upgrades" on public.upgrade_requests for select to authenticated using (user_id = auth.uid() or is_admin());
create policy "admin updates upgrades" on public.upgrade_requests for update to authenticated using (is_admin());

-- Discover: server enforces age bands (under 18 only sees under 18, adults only see adults)
create function public.discover(p_game text default '', p_gender text default '', p_intent text default '', p_lang text default '', p_rank text default '')
returns table(id uuid, name text, age int, gender text, games text, rank text, role text, city text, bio text, photos text[], intents text[], langs text[], verified boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me profiles; minor boolean; want text;
begin
  select * into me from profiles pr where pr.id = auth.uid();
  if me.id is null or me.status <> 'active' then return; end if;
  minor := age_of(me.dob) < 18;
  want := coalesce(nullif(p_gender,''), me.interest);
  return query
  select p.id, coalesce(nullif(p.nickname,''), split_part(p.full_name,' ',1)), age_of(p.dob), p.gender, p.games, p.rank, p.role, p.city, p.bio,
         p.photos, p.intents, array_prepend(p.primary_lang, p.other_langs), p.verified
  from profiles p
  where p.id <> me.id and p.onboarded and p.status = 'active'
    and (age_of(p.dob) < 18) = minor
    and not exists (select 1 from swipes s where s.from_id = me.id and s.to_id = p.id)
    and (want is null or want in ('','Both') or p.gender = want)
    and (p.interest is null or p.interest in ('','Both') or me.gender = 'Other' or p.interest = me.gender)
    and (p_game = '' or p.games = p_game or p.games = 'Both')
    and (p_intent = '' or p_intent = any(p.intents))
    and (p_lang = '' or p_lang = p.primary_lang or p_lang = any(p.other_langs))
    and (p_rank = '' or p.rank = p_rank)
  order by (case when p.tier = 'Max' then 0 else 1 end), random()
  limit 30;
end $$;

create function public.likes_today() returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from swipes where from_id = auth.uid() and liked
    and created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') $$;

-- like / skip. Free users: 20 likes per day, enforced here. Mutual like creates a match.
create function public.swipe(p_to uuid, p_like boolean) returns json language plpgsql security definer set search_path = public as $$
declare me profiles; oth profiles; used int; va uuid; vb uuid; mt boolean := false;
begin
  select * into me from profiles where id = auth.uid();
  select * into oth from profiles where id = p_to;
  if me.id is null or oth.id is null or me.status <> 'active' then raise exception 'invalid'; end if;
  if (age_of(me.dob) < 18) <> (age_of(oth.dob) < 18) then raise exception 'not allowed'; end if;
  if p_like and me.tier = '' and likes_today() >= 20 then return json_build_object('limit', true); end if;
  insert into swipes(from_id, to_id, liked) values (me.id, p_to, p_like)
    on conflict (from_id, to_id) do update set liked = excluded.liked;
  if p_like and exists (select 1 from swipes where from_id = p_to and to_id = me.id and liked) then
    va := least(me.id, p_to); vb := greatest(me.id, p_to);
    insert into matches(a, b) values (va, vb) on conflict do nothing;
    mt := true;
  end if;
  return json_build_object('matched', mt, 'used', likes_today(), 'limit', false);
end $$;

create function public.my_matches() returns table(match_id uuid, other_id uuid, name text, photo text, created_at timestamptz, last_body text, last_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  return query
  select m.id, o.id, coalesce(nullif(o.nickname,''), split_part(o.full_name,' ',1)), o.photos[1], m.created_at,
         (select x.body from messages x where x.match_id = m.id order by x.created_at desc limit 1),
         (select x.created_at from messages x where x.match_id = m.id order by x.created_at desc limit 1)
  from matches m join profiles o on o.id = case when m.a = auth.uid() then m.b else m.a end
  where auth.uid() in (m.a, m.b) and o.status = 'active';
end $$;

-- "Liked you": everyone sees the count, only Premium/Max get names and photos
create function public.liked_me() returns json language plpgsql stable security definer set search_path = public as $$
declare t text; n int; ppl json;
begin
  select tier into t from profiles where id = auth.uid();
  select count(*) into n from swipes s where s.to_id = auth.uid() and s.liked
    and not exists (select 1 from swipes r where r.from_id = auth.uid() and r.to_id = s.from_id);
  if coalesce(t,'') = '' then return json_build_object('total', n, 'people', '[]'::json); end if;
  select coalesce(json_agg(json_build_object('id', p.id, 'name', coalesce(nullif(p.nickname,''), split_part(p.full_name,' ',1)), 'age', age_of(p.dob), 'photo', p.photos[1])), '[]'::json)
    into ppl from swipes s join profiles p on p.id = s.from_id
    where s.to_id = auth.uid() and s.liked
      and not exists (select 1 from swipes r where r.from_id = auth.uid() and r.to_id = s.from_id);
  return json_build_object('total', n, 'people', ppl);
end $$;

create function public.report_user(p_id uuid, p_reason text default '') returns void language plpgsql security definer set search_path = public as $$
begin
  insert into reports(reporter_id, reported_id, reason) values (auth.uid(), p_id, left(coalesce(p_reason,''), 500));
  insert into swipes(from_id, to_id, liked) values (auth.uid(), p_id, false)
    on conflict (from_id, to_id) do update set liked = false;
end $$;

create function public.admin_stats() returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  return json_build_object(
    'users', (select count(*) from profiles), 'banned', (select count(*) from profiles where status = 'banned'),
    'reports', (select count(*) from reports where status = 'open'), 'premium', (select count(*) from profiles where tier <> ''),
    'matches', (select count(*) from matches), 'messages', (select count(*) from messages),
    'bgmi', (select count(*) from profiles where games in ('BGMI','Both')), 'ff', (select count(*) from profiles where games in ('Free Fire','Both')));
end $$;

create function public.delete_me() returns void language sql security definer set search_path = public, auth as $$
  delete from auth.users where id = auth.uid() $$;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;

-- photo storage (public read, each user writes only to their own folder)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 5242880, array['image/jpeg','image/png','image/webp']) on conflict (id) do nothing;
create policy "photos read" on storage.objects for select using (bucket_id = 'photos');
create policy "photos insert own" on storage.objects for insert to authenticated with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "photos update own" on storage.objects for update to authenticated using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "photos delete own" on storage.objects for delete to authenticated using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- realtime chat
alter publication supabase_realtime add table public.messages, public.matches;
