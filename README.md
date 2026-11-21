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

### Local news for signed-in users

`supabase/functions/local-news/index.ts` returns local news for the signed-in user's area:

1. Reads the user's ZIP from their profile (a pro's first service ZIP, or a homeowner's ZIP; pros can pass `?zip=` for another of their own ZIPs).
2. Looks the ZIP up in the separate **zip-zcta** Supabase project (`zip_zcta` table) to get city, state and ZCTA.
3. Returns cached news for that city if it's under 3 hours old; otherwise asks NewsData.io (region filter first, keyword search as a fallback) and caches the result in `local_news_cache`.

Only headlines, short summaries and links are returned. Requires a Supabase login token and the secret `NEWSDATA_API_KEY` (Supabase dashboard → Edge Functions → Secrets). Optional secrets: `NEWS_CACHE_HOURS`, `ZIP_ZCTA_URL`, `ZIP_ZCTA_KEY`.

Call it from the app with the user's session token:

```js
const { data: { session } } = await supabase.auth.getSession();
const res = await fetch('https://qpgwtkvfoenjkvncmtvj.supabase.co/functions/v1/local-news', {
  headers: { Authorization: `Bearer ${session.access_token}` }
});
const { location, articles } = await res.json();
```
