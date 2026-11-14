# Google Sign-In: Google Auth Platform setup

Values to paste into console.cloud.google.com > Google Auth Platform. The Client ID is public, not a secret.

## 1. Branding

| Field | Value |
|---|---|
| App name | Per My Last |
| User support email | hello@permylast.app (or your Gmail if that inbox is not live yet) |
| App logo | `website/assets/icon.png` (must be square, 120x120 px or larger, under 1 MB) |
| Application home page | https://permylast.app |
| Application privacy policy link | https://permylast.app/privacy.html (page written, but not live until the website is deployed). Required before publishing. |
| Application terms of service link | Optional. Same gap. |
| Authorized domains | permylast.app |
| Developer contact email | hello@permylast.app |

## 2. Audience

- User type: **External**.
- While testing, keep **Testing** and add iamnoahpm@gmail.com (and any tester) under Test users.
- Before launch, press **Publish app** to move to **In production**. Testing mode only lets listed test users sign in.

## 3. Data Access (scopes)

Add exactly these three, all non-sensitive, so no verification review is normally needed:

- `openid`
- `.../auth/userinfo.email`
- `.../auth/userinfo.profile`

Justification text if asked: "Used only to sign the user in and show their name and email in the app. No other Google data is read."

## 4. Clients

- Create client > Application type: **iOS**
- Name: Per My Last (macOS)
- Bundle ID: `app.permylast`
- Copy the resulting Client ID (`<digits>-<hash>.apps.googleusercontent.com`).

## 5. After you have the Client ID

Same value in two places:

1. `App/PerMyLast/AppConfig.swift`: `googleClientID`. The Google button now shows automatically when this is non-empty.
2. `backend/wrangler.jsonc`: `GOOGLE_CLIENT_ID`, then deploy the backend.

No Info.plist URL scheme is needed: `ASWebAuthenticationSession` handles the redirect (`com.googleusercontent.apps.<prefix>:/oauth2redirect`).

## Launch reminders

- `APPSTORE_ENVIRONMENTS` in `wrangler.jsonc` is `Production,Sandbox`; set it back to `Production` on the launch deploy.
- Do not deploy the website until you say so; preview locally first.
