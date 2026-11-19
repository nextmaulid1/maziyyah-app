-- Jalankan seluruh isi file ini di Supabase: SQL Editor > New query > Run

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  kode text unique not null,
  name text not null check (char_length(name) between 1 and 60),
  job text not null default '' check (char_length(job) <= 80),
  bio text not null default '' check (char_length(bio) <= 300),
  photo_url text not null default '',
  dp boolean not null default true,
  created_at timestamptz not null default now()
);

-- Tanggal lahir dipisah supaya TIDAK bisa dibaca publik
create table public.private_data (
  id uuid primary key references public.profiles(id) on delete cascade,
  ttl text
);

create table public.posts (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  author text,
  cat text not null check (cat in ('Pendidikan','Karir','Dunia Kerja','Fakta','Update')),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.private_data enable row level security;
alter table public.posts enable row level security;

-- Profil: semua orang boleh baca, hanya pemilik yang boleh ubah (kolom tertentu saja)
create policy "profil publik" on public.profiles for select using (true);
create policy "ubah profil sendiri" on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);
revoke update on public.profiles from anon, authenticated;
grant update (name, job, bio, photo_url, dp) on public.profiles to authenticated;

-- Data privat: hanya pemilik yang boleh baca
create policy "ttl milik sendiri" on public.private_data for select to authenticated using (auth.uid() = id);

-- Berita: semua boleh baca, yang login boleh posting, hanya pemilik yang boleh hapus
create policy "berita publik" on public.posts for select using (true);
create policy "posting" on public.posts for insert to authenticated with check (user_id = auth.uid());
create policy "hapus postingan sendiri" on public.posts for delete to authenticated using (user_id = auth.uid());

-- Nama penulis diisi server, bukan dari browser
create function public.set_author() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  new.author := (select name from public.profiles where id = auth.uid());
  return new;
end $$;
create trigger posts_author before insert on public.posts
  for each row execute function public.set_author();

-- Penyimpanan foto profil
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "foto publik" on storage.objects for select using (bucket_id = 'avatars');
create policy "upload foto sendiri" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "ganti foto sendiri" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "hapus foto sendiri" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
