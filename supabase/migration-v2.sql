-- MIGRASI V2 — jalankan SETELAH schema.sql (yang sudah kamu jalankan sebelumnya).
-- Supabase: SQL Editor > New query > tempel seluruh file ini > Run.
-- Aman dijalankan ulang (idempotent).

-- =========================================================
-- 1. PROFIL: branding (warna) & bahasa per akun
-- =========================================================
alter table public.profiles add column if not exists accent text not null default '';
alter table public.profiles add column if not exists bg     text not null default '';
alter table public.profiles add column if not exists lang   text not null default 'id';

alter table public.profiles drop constraint if exists profiles_accent_fmt;
alter table public.profiles add  constraint profiles_accent_fmt check (accent = '' or accent ~ '^#[0-9a-fA-F]{6}$');
alter table public.profiles drop constraint if exists profiles_bg_fmt;
alter table public.profiles add  constraint profiles_bg_fmt     check (bg = ''     or bg     ~ '^#[0-9a-fA-F]{6}$');
alter table public.profiles drop constraint if exists profiles_lang_fmt;
alter table public.profiles add  constraint profiles_lang_fmt   check (lang in ('id','en','ko','ja','su','jv'));

revoke update on public.profiles from anon, authenticated;
grant update (name, job, bio, photo_url, dp, accent, bg, lang) on public.profiles to authenticated;

-- =========================================================
-- 2. POSTINGAN: boleh berisi foto / video
-- =========================================================
alter table public.posts add column if not exists media_url  text;
alter table public.posts add column if not exists media_type text;

alter table public.posts drop constraint if exists posts_title_check;
alter table public.posts drop constraint if exists posts_body_check;
alter table public.posts alter column title set default '';
alter table public.posts alter column body  set default '';

alter table public.posts drop constraint if exists posts_title_len;
alter table public.posts add  constraint posts_title_len check (char_length(title) <= 120);
alter table public.posts drop constraint if exists posts_body_len;
alter table public.posts add  constraint posts_body_len  check (char_length(body) <= 2000);
alter table public.posts drop constraint if exists posts_media_type_chk;
alter table public.posts add  constraint posts_media_type_chk check (media_type is null or media_type in ('image','video'));
alter table public.posts drop constraint if exists posts_content_chk;
alter table public.posts add  constraint posts_content_chk check (char_length(body) > 0 or media_url is not null);

-- Postingan sekarang hanya bisa dibaca yang sudah login
drop policy if exists "berita publik" on public.posts;
drop policy if exists "berita login"  on public.posts;
create policy "berita login" on public.posts for select to authenticated using (true);

-- Penyimpanan foto/video postingan (maks 50 MB per file)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 52428800,
        array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "media publik"        on storage.objects;
drop policy if exists "upload media sendiri" on storage.objects;
drop policy if exists "hapus media sendiri"  on storage.objects;
create policy "media publik" on storage.objects for select using (bucket_id = 'media');
create policy "upload media sendiri" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "hapus media sendiri" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

-- =========================================================
-- 3. LIKE, KOMENTAR, SIMPAN
-- =========================================================
create table if not exists public.likes (
  post_id bigint not null references public.posts(id) on delete cascade,
  user_id uuid   not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.saves (
  post_id bigint not null references public.posts(id) on delete cascade,
  user_id uuid   not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references public.posts(id) on delete cascade,
  user_id uuid   not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments(post_id, created_at);

alter table public.likes    enable row level security;
alter table public.saves    enable row level security;
alter table public.comments enable row level security;

drop policy if exists "lihat like"   on public.likes;
drop policy if exists "like"         on public.likes;
drop policy if exists "unlike"       on public.likes;
create policy "lihat like" on public.likes for select to authenticated using (true);
create policy "like"       on public.likes for insert to authenticated with check (user_id = auth.uid());
create policy "unlike"     on public.likes for delete to authenticated using (user_id = auth.uid());

-- Simpanan bersifat pribadi
drop policy if exists "lihat simpanan sendiri" on public.saves;
drop policy if exists "simpan"                 on public.saves;
drop policy if exists "hapus simpanan"         on public.saves;
create policy "lihat simpanan sendiri" on public.saves for select to authenticated using (user_id = auth.uid());
create policy "simpan"                 on public.saves for insert to authenticated with check (user_id = auth.uid());
create policy "hapus simpanan"         on public.saves for delete to authenticated using (user_id = auth.uid());

drop policy if exists "lihat komentar"  on public.comments;
drop policy if exists "komentar"        on public.comments;
drop policy if exists "hapus komentar"  on public.comments;
create policy "lihat komentar" on public.comments for select to authenticated using (true);
create policy "komentar"       on public.comments for insert to authenticated with check (user_id = auth.uid());
-- boleh dihapus oleh penulis komentar ATAU pemilik postingan
create policy "hapus komentar" on public.comments for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.posts p where p.id = post_id and p.user_id = auth.uid()));

-- =========================================================
-- 4. FOLLOW
-- =========================================================
create table if not exists public.follows (
  follower_id  uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);
create index if not exists follows_following_idx on public.follows(following_id);
alter table public.follows enable row level security;

drop policy if exists "lihat follow"   on public.follows;
drop policy if exists "ikuti"          on public.follows;
drop policy if exists "berhenti ikuti" on public.follows;
create policy "lihat follow"   on public.follows for select to authenticated using (true);
create policy "ikuti"          on public.follows for insert to authenticated with check (follower_id = auth.uid());
create policy "berhenti ikuti" on public.follows for delete to authenticated using (follower_id = auth.uid());

-- =========================================================
-- 5. DIRECT MESSAGE (hanya boleh kirim jika saling follow)
-- =========================================================
create or replace function public.is_mutual(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.follows where follower_id = a and following_id = b)
     and exists (select 1 from public.follows where follower_id = b and following_id = a);
$$;

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  sender_id   uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender_id <> receiver_id)
);
create index if not exists messages_pair_idx on public.messages(sender_id, receiver_id, created_at);
create index if not exists messages_rcv_idx  on public.messages(receiver_id, read_at);
alter table public.messages enable row level security;

drop policy if exists "baca pesan sendiri" on public.messages;
drop policy if exists "kirim pesan"        on public.messages;
drop policy if exists "tandai dibaca"      on public.messages;
create policy "baca pesan sendiri" on public.messages for select to authenticated
  using (sender_id = auth.uid() or receiver_id = auth.uid());
create policy "kirim pesan" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_mutual(sender_id, receiver_id));
create policy "tandai dibaca" on public.messages for update to authenticated
  using (receiver_id = auth.uid()) with check (receiver_id = auth.uid());
revoke update on public.messages from anon, authenticated;
grant update (read_at) on public.messages to authenticated;

-- Pesan masuk langsung muncul tanpa refresh
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- Notifikasi "mulai mengikutimu" muncul langsung tanpa refresh
do $$ begin
  alter publication supabase_realtime add table public.follows;
exception when duplicate_object then null; when undefined_object then null; end $$;
