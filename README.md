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
- Form `action` URLs: both forms currently run in demo mode (they show a thank-you message and send nothing). Point them at your lead distribution system or CRM webhook.
- Privacy policy and terms text, and the consent wording under the homeowner form (have a TCPA attorney review it)
