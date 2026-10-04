# StructuralVision AR: Deploy Guide (free, no PC, no ngrok)

How to run the backend on a free cloud server so the app works for anyone, any time,
without your PC being on. Also covers signup emails and getting the app onto people's phones.

**What runs where after this guide:**

```
Login + database + photos  →  Supabase (free)                    already set up
Crack detection API        →  Oracle Cloud Always Free VM        §1–§4
HTTPS address for the API  →  DuckDNS subdomain + Caddy          §2, §4
Signup / reset emails      →  Gmail SMTP plugged into Supabase   §6
The APK                    →  GitHub Releases / Google Play      §7
```

Total cost: **$0**. Google Play is optional and costs **$25 once**.

---

## 1. Create the Oracle Cloud server

1. Sign up at **cloud.oracle.com** ("Start for free").
   - A card is needed for identity checks only. Always Free resources are never charged.
   - **Pick your home region carefully.** It can't be changed later, and free ARM capacity varies by region.
     Choose one near your users (e.g. Mumbai or Hyderabad for India).
2. Console → **Compute → Instances → Create instance**:
   - **Image:** Canonical Ubuntu 24.04
   - **Shape:** Change shape → Ampere → **VM.Standard.A1.Flex**, **2 OCPU, 12 GB memory** (the Always Free limit)
   - **Networking:** keep "Assign a public IPv4 address" ticked
   - **SSH keys:** "Generate a key pair for me" → **download the private key** (you can't get it again)
   - Boot volume: default (~47 GB, free up to 200 GB)
3. **"Out of capacity" error?** Free ARM servers run out in busy regions. Try another availability domain, or retry later
   (early morning usually works).
4. Note the instance's **Public IP address**.

**Open ports 80 and 443** (needed for HTTPS). Oracle has *two* firewalls; open both:

- **Cloud firewall:** Instance → Subnet → Default Security List → **Add Ingress Rules**:
  Source `0.0.0.0/0`, TCP, destination port `80`. Add another rule for `443`.
- **Ubuntu's firewall:** SSH in (below) and run:
  ```bash
  sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
  sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
  sudo netfilter-persistent save
  ```

**SSH in** from Windows PowerShell:
```powershell
ssh -i C:\path\to\ssh-key.key ubuntu@<PUBLIC_IP>
```
(If it complains the key is too open: right-click the key → Properties → Security → leave only your user.)

> **Idle reclaim:** Oracle may *stop* an Always Free VM that stays almost completely idle for 7 days.
> It isn't deleted. If the app stops answering, check the instance in the console and press **Start**.
> Upgrading the account to Pay As You Go removes this and keeps Always Free resources at $0, but then
> anything *beyond* the free limits would be billed, so only do it if you're careful.

---

## 2. Get a free web address (DuckDNS)

Phones need an HTTPS address, and HTTPS needs a name rather than a bare IP.

1. Go to **duckdns.org**, sign in with Google or GitHub.
2. Add a subdomain, e.g. `structuralvision` → you get `structuralvision.duckdns.org`.
3. Put the VM's public IP in the **current ip** box → **update ip**.

---

## 3. Put the code, keys and model on the server

On the VM:

```bash
# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
exit        # log out and back in so the docker group applies
```

```bash
# Code. For a private repo, GitHub asks for a username + a personal access token
# (GitHub → Settings → Developer settings → Fine-grained tokens, read-only on this repo).
git clone https://github.com/LUCIFER032205/StructuralVision.git
mkdir -p StructuralVision/project/models
```

From **your PC** (PowerShell), copy the files that are deliberately not in git:

```powershell
scp -i C:\path\to\ssh-key.key F:\StructuralVision\project\models\crack_seg.pt ubuntu@<PUBLIC_IP>:~/StructuralVision/project/models/
scp -i C:\path\to\ssh-key.key F:\StructuralVision\project\backend\.env        ubuntu@<PUBLIC_IP>:~/StructuralVision/project/backend/
```

Back on the VM, tell Caddy your address:

```bash
cd ~/StructuralVision/project/deploy
cp .env.example .env
nano .env          # DOMAIN=structuralvision.duckdns.org  (your subdomain)
```

---

## 4. Start it

```bash
cd ~/StructuralVision/project/deploy
docker compose up -d --build       # first build: ~10 min (downloads PyTorch)
docker compose logs -f api         # wait for "Supabase: connected OK"; Ctrl+C to stop watching
```

Check from any browser: **`https://<your-subdomain>.duckdns.org/docs`** should show the Swagger page
with a padlock. The certificate is issued and renewed automatically.

Both containers restart by themselves after a crash or a VM reboot.

**Updating later:**

| Change | On the VM |
|---|---|
| Backend code | `cd ~/StructuralVision && git pull && cd project/deploy && docker compose up -d --build` |
| New model weights | `scp` the new `crack_seg.pt` as in §3, then `docker compose restart api` |
| `.env` values | Edit `project/backend/.env`, then `docker compose up -d` |

---

## 5. Point the app at the server

- **Phones that already have the app:** login screen → ⚙ → `https://<your-subdomain>.duckdns.org` → Save.
- **New builds:** set `DEFAULT_API_BASE=https://<your-subdomain>.duckdns.org` in `project/app/dart_defines.env`
  and rebuild the APK once (RUN_GUIDE §4). New installs then work with no setup.

You no longer need ngrok or your PC on.

### Supabase stays awake on its own

Free Supabase projects pause after 7 days without database activity, which takes logins down.
The backend now makes one tiny query every 12 hours (`KEEPALIVE_HOURS` in `backend/.env`; `0` turns it off),
so as long as the server runs, the project never counts as inactive.

---

## 6. Signup emails: Gmail SMTP (fixes the "2 emails per hour" limit)

Supabase's built-in email sender is for testing only: roughly **2 emails per hour** for the whole project.
Plugging in Gmail raises that to about **500 per day**, free, no domain needed.

### 6a. Make a dedicated Google account

Use a new account just for the app, not your personal Gmail. The app password is stored in Supabase,
and users see this address as the sender.

1. Open **accounts.google.com/signup** (in a private/incognito window so it doesn't mix with your own account).
2. Name: `StructuralVision`. Username: e.g. `structuralvision.app` → `structuralvision.app@gmail.com`
   (pick any free variant).
3. Google may ask for a phone number to verify. Your own number is fine; one number can verify several accounts.
4. Turn on **2-Step Verification**: myaccount.google.com → Security → 2-Step Verification.
   (App passwords don't exist without it.)
5. Create an **app password**: go to **myaccount.google.com/apppasswords**, name it `Supabase`,
   copy the 16-character code. It's shown once.

### 6b. Plug it into Supabase

Supabase dashboard → your project → **Authentication**:

1. **SMTP Settings → Enable custom SMTP:**

   | Field | Value |
   |---|---|
   | Sender email | `structuralvision.app@gmail.com` |
   | Sender name | `StructuralVision` |
   | Host | `smtp.gmail.com` |
   | Port | `587` |
   | Username | `structuralvision.app@gmail.com` |
   | Password | the 16-character app password (no spaces) |

2. **Rate Limits →** raise **"Rate limit for sending emails"** (e.g. `30` per hour).
   It's a separate cap from the SMTP one.
3. **URL Configuration → Site URL:** `https://<your-subdomain>.duckdns.org/static/confirmed.html`
   That's where the confirmation link lands. Without it, users end on a broken `localhost` page,
   even though their account *is* confirmed.
4. Test: sign up in the app with a fresh address → the email arrives from `StructuralVision` →
   tap the link → "Email confirmed" page → sign in.

> **Later, with your own domain:** Resend (3,000 emails/month free) looks more professional
> (`noreply@yourdomain.com`), but it only sends to other people once you've verified a domain you own.

---

## 7. Getting the app to users

### Now: direct APK download (free)

1. Build the APK (RUN_GUIDE §4).
2. GitHub → this repo → **Releases → Draft a new release** → tag e.g. `v1.0` → attach
   `app-release.apk` → Publish.
   - The download link only works for the public if the **repo is public**. For a private repo,
     upload the APK to a Google Drive folder shared as "Anyone with the link" instead.
3. Users open the link on their phone → allow "install unknown apps" → install.
   Play Protect may warn about an unknown app; they tap **Install anyway**.

No auto-updates: users install new versions from the new link.

### Later: Google Play ($25 once)

One **$25 one-time** fee registers a developer account. It covers every app and every release track forever.

| Track | Who can install | What's required |
|---|---|---|
| **Internal testing** | Up to 100 people you add by email | Available as soon as the account is set up |
| **Closed testing** | People you invite | Needed before going public (below) |
| **Production** | Anyone on the Play Store | New personal accounts first need a closed test with **12+ testers opted in for 14 days in a row** |

Path: create the account at **play.google.com/console** → upload a signed **App Bundle** (`flutter build appbundle`)
to **Internal testing** for your team → start a **Closed test** with 12+ friends → after 14 days, apply for **Production**.

> **Sideloading rules are tightening.** From 2027 Google requires apps installed outside the Play Store to come
> from identity-verified developers (already enforced in Brazil, Indonesia, Singapore and Thailand since Sept 2026).
> A Play developer account covers that, which is another reason to register one before then.

---

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `docker compose up` says `required variable DOMAIN is missing` | Create `project/deploy/.env` from `.env.example` (§3) |
| `https://…duckdns.org` doesn't load at all | Ports 80/443 not open in **both** firewalls (§1), or DuckDNS points at the wrong IP (§2) |
| Browser shows a certificate error | Caddy couldn't get a certificate: same causes as above. `docker compose logs caddy` says why |
| Logs show `!!! SUPABASE NOT CONNECTED` | `backend/.env` missing or wrong on the VM, or the project is paused (restore it once; the keep-alive takes over from then) |
| `api` keeps restarting, log mentions `crack_seg.pt` | Model file not copied to `project/models/` on the VM (§3) |
| App worked, then stopped days later | Oracle idle reclaim stopped the VM: console → Instance → **Start** (§1). Containers come back by themselves |
| Signup says "check your email" but nothing arrives | Check the Gmail account's **Sent** folder. Nothing there → re-check the SMTP settings and the app password (§6b) |
