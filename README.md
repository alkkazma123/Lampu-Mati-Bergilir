# Lampu Mati Bergilir 🔦

Game Roblox horror ringan — lampu kota mati-nyala secara acak, entitas misterius muncul di kegelapan, dan kamu harus bertahan!

## Fitur Utama

| Fitur | Keterangan |
|---|---|
| **Multi-Lobby (4 Lobby)** | Setiap server memiliki 4 lobby independen. Host menentukan jumlah pemain (1-8). |
| **Waiting Area + Countdown** | 15 detik countdown sebelum game dimulai. Lobby penuh/sedang bermain → UI "Game In Progress" + opsi Spectate. |
| **Kota Gelap Prosedural** | Map kota sederhana di-generate otomatis saat runtime (bangunan, jalan, lampu jalan). |
| **Sistem Lampu Mati-Nyala** | Lampu mati & nyala secara acak. Saat gelap, entitas misterius muncul & mengejar pemain. |
| **Saklar Mechanic** | Cari saklar tersembunyi untuk menyalakan lampu dan mengusir entitas. |
| **Entitas Misterius** | NPC yang muncul di kegelapan, mengejar pemain, jumpscare ringan (tanpa gore). |
| **Coin & XP/Level** | Dapatkan coin & XP setiap bertahan. Leaderboard di lobby. |
| **Overhead UI** | Nama + Level di atas kepala setiap pemain. |
| **Sound Design** | Backsound horror ambient, efek lampu mati, langkah kaki, jumpscare SFX. |
| **Camera Shake** | Efek kamera goyang saat lampu mati. |
| **Loading Screen** | Loading screen real saat pertama masuk. |
| **Rules UI** | Panel aturan main muncul sekali saat pertama join, dengan tombol close. |
| **Dark Theme UI** | Semua UI modern minimalis dark theme, dibuat 100% via script. |
| **PC & Mobile** | Support keyboard/mouse dan touch controls. |

## Tech Stack

- **Rojo** — sync project ke Roblox Studio
- **Luau** — scripting language

## Setup

```powershell
# 1. Install Rojo (jika belum)
#    https://rojo.space/docs/v7/getting-started/installation/

# 2. Clone repo
git clone https://github.com/alkkazma123/Lampu-Mati-Bergilir.git
cd Lampu-Mati-Bergilir

# 3. Build file .rbxlx
rojo build -o game.rbxlx

# 4. Atau jalankan live-sync
rojo serve
```

Buka Roblox Studio → Install Rojo Plugin → Connect ke `localhost:34872`.

## Struktur Project

```
src/
├── ServerScriptService/
│   └── MainServer.server.lua      -- Server: map gen, lobby, game, entity, economy
├── StarterPlayerScripts/
│   └── MainClient.client.lua      -- Client: semua UI, camera FX, sound, input
├── ReplicatedStorage/
│   └── GameConfig.lua             -- Shared config & constants
├── StarterGui/                    -- (kosong, UI dibuat via script)
├── SoundService/                  -- Sound config
└── Lighting/                      -- Lighting config
```

## Lisensi

MIT
