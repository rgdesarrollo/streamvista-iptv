# StreamVista pairing portal

This is a Firebase Hosting site plus a Firebase Cloud Function. It lets an authenticated administrator send an authorised Xtream or M3U source to a device using a generated device ID and six-digit pairing PIN. It deliberately does **not** use a MAC address: current Android, iOS and browser privacy models do not expose a reliable one.

## Deploy

1. Create a Firebase project and enable **Authentication > Email/Password**. Visitors can create their own account from the portal before managing their paired devices.
2. Install the Firebase CLI and log in: `npm install -g firebase-tools`, then `firebase login`.
3. In this directory, run `firebase use --add` and `firebase init hosting functions firestore`. Keep the existing `firebase.json` and select Node 20 for Functions.
4. In **Project settings > Your apps**, register a Web app and copy its complete `firebaseConfig` object into `public/firebase-config.js`. Set `STREAMVISTA_PAIRING_API` to the URL printed for the deployed `pairing` function. Do not invent or substitute an API key from another Google service.
5. Deploy with `firebase deploy`.
6. In the StreamVista app, open **Pair device**, paste the pairing function URL, then enter the displayed Device ID and PIN in this portal.

The browser is authenticated through Firebase. Firestore rules deny direct client access; only the function reads or writes pairing records. A queued configuration expires after 10 minutes and is deleted immediately after the device receives it. Firebase still stores the queued credentials server-side for that brief period, so use a Firebase project you control.
