# HandyMatch website

Static marketing site for HandyMatch (handymatch.us): a homeowner request page and a pro sign-up page. Plain HTML and CSS, no build step.

## Pages

| File | What it is |
| --- | --- |
| `index.html` | Homeowner homepage with the "request a pro" form |
| `pros.html` | Pro (contractor) landing page with pricing and sign-up form |
| `privacy.html`, `terms.html` | Placeholders for attorney-reviewed legal text |
| `assets/styles.css` | All styles (colors are CSS variables at the top) |
| `assets/site.js` | Small enhancements: service tiles pre-fill the form; demo form handling |

## Preview locally

Open `index.html` in a browser, or run `python3 -m http.server` in this folder and visit http://localhost:8000.

## Publish with GitHub Pages

1. In the repo, go to **Settings → Pages**.
2. Under **Build and deployment**, choose **Deploy from a branch**, branch `main`, folder `/ (root)`, and save.
3. The site appears at `https://handymatch-us.github.io/webpages/` within a minute or two.

To use handymatch.us instead, enter it under **Custom domain** on the same page and add the DNS records GitHub shows you at your domain registrar.

## Before launch: placeholders to replace

Search the code for `[` and `TODO`:

- `[CITY]`, `[YOUR PHONE]`, `[PRO SUPPORT PHONE]`, `[LEGAL ENTITY NAME]`, `[CITY, STATE]`
- Prices on `pros.html` (`[$35]`, `[$50]`, `[$65]`)
- The `tel:` link in the homepage header
- The pro sign-up form still runs in demo mode (shows a thank-you, sends nothing). The homeowner form is live: it posts to the Supabase function `submit-request`.
- Privacy policy and terms text, and the consent wording under the homeowner form (have a TCPA attorney review it)

## Database (Supabase)

`supabase/schema.sql` creates the HandyMatch database: homeowners, pros, requests (with TCPA consent proof), lead assignments (one pro per request), a ledger of charges and credits, credits, calls, pro documents, and a starting price list.

To set it up: Supabase dashboard → your project → **SQL Editor** → **New query** → paste the whole file → **Run**. Run it once, on a new project.

Lead routing and credits go through the `assign_lead` and `issue_credit` functions, called from the server with the service role key. Row-level security lets each pro see only their own leads, balance and documents.

### Homeowner form → database

`supabase/functions/submit-request/index.ts` is a Supabase Edge Function that receives the homeowner form, checks the fields (service, name, 5-digit ZIP, US mobile number, consent), blocks other websites and simple spam bots, limits each phone number to 5 requests a day, and saves the homeowner and request (with consent text, time, IP and browser) using the service role key. Requests arrive with status `new`.

If you move the site to another domain, add it to `ALLOWED_ORIGINS` in that file and redeploy.
