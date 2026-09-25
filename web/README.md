# Dr. Pocket — desktop server

Plain Node, zero dependencies. Serves a local dashboard and Nightscout-shaped endpoints.

    npm start     # http://localhost:1337

Starts in demo mode. `PROVIDER=` in `.env` takes `demo` or `carelink`.

## Signing in to CareLink

CareLink's web login is behind a captcha, so this uses the CareLink Connect app's OAuth
flow instead — you sign in once, in your own browser, and the app keeps a refresh token.

1. Pick your region on the dashboard and hit **Sign in to CareLink**.
2. Sign in and solve the captcha in the tab that opens.
3. The page then fails to load, redirecting to `com.medtronic.carepartner:/sso?code=...`.
   That is expected — it is the phone app's redirect. Copy the whole address.
4. Paste it back into Dr. Pocket and hit **Finish**.

Tokens land in `data/tokens.json` and refresh on their own. Set `CARELINK_PATIENT` if you
follow more than one person.

## Data

Readings and treatments live in `data/db.json`; `/api/export` downloads the lot.
Read endpoints: `/api/v1/entries.json`, `/api/v1/treatments.json`, `/api/status`.
