# DuoUp: setup guide (all free)

Files: `index.html` (the app), `assets/` (logo, icon, background music), `schema.sql` (database, security rules, storage, chat).
Stack: Supabase free tier (login, database, photo storage, realtime chat) + Vercel free tier (hosting).

## 1. Create the backend (5 min)
1. Go to supabase.com, sign up, click **New project**. Pick a region close to India (Mumbai) and save the database password.
2. Open **SQL Editor > New query**, paste all of `schema.sql`, press **Run**. It should finish with "Success".

## 2. Auth settings
- **Authentication > Providers > Email**: for quick testing turn **off** "Confirm email". (Turn it back on before public launch.)
- **Authentication > URL Configuration**: set **Site URL** to your Vercel link once you have it (step 4). This makes password-reset emails work.

## 3. Connect the app
1. In Supabase: **Project Settings > API**. Copy **Project URL** and the **anon public** key.
2. Open `index.html`, find `const CFG=` near the top of the script, and paste both values.
3. Never put the `service_role` key in this file. The anon key is meant to be public; the security rules in `schema.sql` protect the data.

## 4. Deploy on Vercel (free)
- Upload the **whole folder** (index.html AND the assets folder with logo and music) to a new GitHub repo: Add file > Upload files.
- vercel.com > **Add New > Project** > import that repo > Deploy. (Vercel's dashboard has no folder drag-and-drop. Without GitHub, app.netlify.com/drop works.)
- Open the link on your phone and test.

## Signup email not arriving?
Supabase's built-in email sender only delivers to your own team members and allows 2 emails per hour for the whole project, so real users never get the link. Fix:
- **For testing:** Authentication > Sign In / Providers > Email > turn **off** "Confirm email". Signup then works instantly with no email.
- **For launch:** Authentication > SMTP Settings > enable custom SMTP (Brevo, Resend or similar free plans), then turn "Confirm email" back on and raise Authentication > Rate Limits.
- Also check Spam, and set Site URL (Authentication > URL Configuration) to your Vercel link so links don't point to localhost.

## 5. Make yourself admin
Sign up in the app first, then run this in the SQL Editor (use your email):
```sql
update public.profiles set is_admin = true where id = (select id from auth.users where email = 'you@example.com');
```
Reopen the app: the menu now shows **Admin panel** (users, ban/verify, reports, upgrade requests).

## 6. Test checklist
- Sign up with two accounts (use two browsers). Under-13 DOB should be rejected.
- Complete onboarding on both. Like each other: a match appears in Inbox and chat is live.
- Upload, replace and delete photos. Report a user, then see it in the admin Reports tab.
- Like 20 profiles on a free account: paywall appears (limit is enforced on the server).
- Under-18 accounts only see under-18 players and cannot keep the "Dating" intent (enforced in the database).

## What is built in
Age bands and the 20 likes/day limit are enforced by the database, not just the screen. In-game IDs are only readable by matched users. Users cannot make themselves premium, verified, admin or change their date of birth.

## Not done yet (be honest with users)
- **Payments:** Premium buttons send an upgrade request that you approve in Admin > Upgrades after you receive money. Real automatic payments need Razorpay (needs a business account, takes a fee per payment).
- **Phone OTP / age verification:** DOB is self-declared. Phone OTP costs money, so email login is used.
- **Moderation:** read reports daily. Add a lawyer-reviewed Privacy Policy and Terms before launch; the text in the app is a draft. India's DPDP Act applies, and extra rules apply to children's data.
- **Free-tier limits:** Supabase free pauses projects after 1 week of no activity and has storage/bandwidth caps. Photos are compressed in the browser to save space.
- **Reviews on the landing page** are preview text. Replace them with real ones and delete the small preview note.

- **Music:** make sure you have the right to use the song on a public website. A popular song can get your site taken down; royalty-free tracks are safe.
