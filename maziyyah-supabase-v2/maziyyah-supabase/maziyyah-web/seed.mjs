// Membuat 96 akun alumni (password awal 123456) + profil + tanggal lahir privat.
// Jalankan SEKALI di laptop lo:
//   npm i @supabase/supabase-js
//   SUPABASE_URL=https://xxxx.supabase.co SERVICE_KEY=eyJ... node seed.mjs
// SERVICE_KEY (service_role) BERSIFAT RAHASIA. Jangan masuk index.html, jangan di-commit ke GitHub.
import { createClient } from "@supabase/supabase-js";
import { readFileSync } from "node:fs";

const { SUPABASE_URL, SERVICE_KEY } = process.env;
if (!SUPABASE_URL || !SERVICE_KEY) { console.error("Isi SUPABASE_URL dan SERVICE_KEY dulu."); process.exit(1); }
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
const alumni = JSON.parse(readFileSync(new URL("./alumni.json", import.meta.url)));

let ok = 0, gagal = 0;
for (const a of alumni) {
  const { data, error } = await sb.auth.admin.createUser({
    email: `${a.kode}@maziyyah.app`, password: "123456", email_confirm: true,
  });
  if (error) { console.log("GAGAL", a.kode, a.name, "-", error.message); gagal++; continue; }
  const id = data.user.id;
  const p = await sb.from("profiles").insert({ id, kode: a.kode, name: a.name });
  const t = await sb.from("private_data").insert({ id, ttl: a.ttl });
  if (p.error || t.error) { console.log("GAGAL profil", a.kode, p.error?.message || t.error?.message); gagal++; continue; }
  console.log("OK", a.kode, a.name); ok++;
}
console.log(`Selesai. Berhasil ${ok}, gagal ${gagal}.`);
