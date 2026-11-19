# Parcel website

Interactive React/Vite product site for the proprietary Parcel macOS app. The browser demo accepts local drag/drop and paste input without uploading files and includes the live da.gd link-shortening flow. Clean demo recordings are generated headlessly, so no personal desktop content appears on the public site.

```bash
cd /Users/jimishakansara/FirstVentures/parcel/website
npm install
npm run dev
```

Open <http://localhost:4173>. To validate the production build and browser interactions:

```bash
npm run lint
npm run build
npm test
npm run record:demos
```

For a temporary public tunnel, run `npx localtunnel --port 4173`, then restart Vite with the assigned host allowed:

```bash
__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=your-subdomain.loca.lt npm run dev
```

The `/pricing` page lists one-time launch licences at $2.49 for one Mac, $4.99 for two Macs, and $9.99 for five Macs. Checkout is not connected; each plan opens the waitlist.

The waitlist endpoint is server-side and uses Resend Contacts plus a transactional confirmation email. Configure these only in the server environment—never in Vite client variables:

```bash
RESEND_API_KEY=re_...
RESEND_FROM='Parcel <hello@your-verified-domain.com>'
RESEND_REPLY_TO=hello@your-domain.com # optional
```

Create a Resend string contact property named `parcel_plan` before launch. Without the server variables, the form fails safely and no address is accepted. The public website contains no source-repository links.
