<!--
  オーナー向けメモ（Web 版の頁には出ない）
  - 本文は、Web 版 main（3fd364f）の src/components/legal/privacy-{ja,en,zh-tw}.tsx に
    docs/web-changes/ のパッチ（0001 が前の legal.patch、0002 が MiniMax・Tripo3D と 3D の機能の削除）を当てた後の文言と同じです（TSX から機械的に書き出した）。
    公開されるのは Web 版の頁（https://catchwords.lovable.app/privacy）で、表示言語に合わせて3言語のどれかが出ます。
    直すときは TSX（patch）とこのファイルを同じ日に、3言語とも直す。
  - 〔 〕の所は、Web 版が表示するときに設定（Lovable の Secrets の LEGAL_* など。src/lib/legal-config.ts）
    から差し込む値です。本文に手で書き込まないでください。設定する値は checklist.ja.md 1章。
  - 第5条の所在国は、コードと各社の公開情報で確かめられた物だけを書いた。TypeSafe（Jev）の所在国と、
    Supabase のデータの保存地域はオーナーが確かめる（checklist.ja.md 1章）。
-->

# Privacy Policy

Last updated: 26 October 2026

〔Operator name = LEGAL_SELLER_NAME〕(“the operator”) handles information about users of CatchWords (the iPhone app and the web version; “the Service”) as described below, in accordance with Japan's Act on the Protection of Personal Information and other applicable laws. This is a translation; if it differs from the Japanese version, the Japanese version prevails.

## 1. Information we collect

- Account information: email address, display name and profile photo (if you set one). If you sign in with Google or Apple, the email address and similar details we receive from that service
- Photos: photos you take or choose, the selfie after a capture (if you turn on “Selfie mode” in Settings) and photos you add to your diary. The iPhone app reads only the images you pick from the Photos app. If you turn on “Save to Camera Roll” in Settings, photos are added to the Photos app on your device (the app does not read your library)
- Voice (“Search by voice” in the iPhone app): the microphone and Apple's speech recognition turn what you say into text. Languages that can be recognised on the device are handled on the device; others are processed on Apple's servers (Apple's privacy policy applies). The operator never receives or stores the audio itself; the Service uses only the resulting text. The microphone and speech recognition are used only if you allow them on your device
- Words and study records: the words you catch, cards with meanings, examples and explanations, your collection, diary text, your review answers and results, and your review schedule
- Usage: when you open the app, which screens you use, how many captures, scans and reviews you do and how long they take, and how often AI is used and fails
- Location: your device's location (latitude and longitude) when you take a photo, only if you allow location access on your device. If you turn on “Location reminders” in Settings, your current location when you open the app is compared with saved places (that current location is not stored). In the iPhone app, “Location reminders” are triggered by the device (iOS) when you come near a saved place; your current location is not sent to the operator
- Language and settings: display language, native and study languages, your browser's language (to choose the first display language), and settings such as theme and sound
- Paid plan information: whether you are on Pro. Payments are processed by Stripe; the operator never receives your card number. If in-app purchases start in the iPhone app, we receive the purchase record (product, period and transaction identifiers) from Apple to check that it is valid (not your payment details)
- Error reports: what you send when you report an error in a word
- Technical information: to deliver the Service, your IP address, browser type and similar details are processed on the servers of the providers listed below
- Advertising (iPhone app): when a video ad is shown, Google (AdMob) receives device information (model, OS, IP address and similar) and a record of the ad being shown and watched. The advertising identifier (IDFA) is not used

## 2. How we use it

- To provide and operate the Service (sign-in, saving, syncing between devices)
- To analyse objects and text in your photos and to generate word cards, explanations, examples and quizzes with AI
- To generate pronunciation audio
- To turn words you say into text and look them up (iPhone app)
- To find or generate images that match a word
- To show maps and place names, and to send location reminders
- To schedule reviews (including memory predictions)
- To provide paid plans and manage payments and cancellations
- To prevent abuse, investigate bugs and improve the Service. The operator views and analyses per-user usage figures (such as the number of captures and reviews, active days and screen usage). To investigate bugs and answer your enquiries, the operator may also view the photos you capture and the place names where they were taken. Your email address, exact location (coordinates) and diary text are not included
- To produce overall statistics (such as the number of users and how many keep using the app), handled in a form that does not identify individuals
- To show ads (see section 6)
- To respond to enquiries

## 3. Sharing with third parties

The operator does not provide your personal information to third parties without your consent, except where required by law. This includes cases where it is needed to protect a person's life, body or property and your consent is hard to obtain, and cooperating with government bodies performing duties set by law. If the Service is taken over through a merger or business transfer, your information will be handled to the same standard as this policy. Providing information to the providers in section 4 is done to entrust them with work needed to run the Service. The operator does not sell your information.

## 4. Service providers, by purpose

Which providers are used depends on the feature and on the operator's settings. This list also includes providers that are not in use now but would be used if the settings were switched.

- **Hosting, database and sign-in**: Lovable (publishing and running the app, relaying AI and map requests), Supabase (database, authentication, photo storage), Cloudflare (the infrastructure the app runs on), and Google or Apple (if you sign in with that account). All information in the Service is stored or processed here
- **AI analysis and generation**: photos, words, native and study languages, diary text and review results are sent to one of the following, chosen by the operator: Lovable AI Gateway (and, through it, Google Gemini, OpenAI and others), Google (Gemini), OpenAI, Anthropic, DeepSeek, Moonshot AI (Kimi), OpenRouter (including the AI providers behind it), or a provider of an OpenAI-compatible API. Words, example sentences, candidate words and review results are also sent to TypeSafe (Jev) for judgements and memory predictions
- **Pronunciation audio**: only the text to be read aloud (words and example sentences) is sent: Microsoft (Azure AI Speech), Google (Gemini speech, Cloud Text-to-Speech), ElevenLabs, Lovable AI Gateway or an OpenAI-compatible API. The audio is stored as shared audio that is not linked to you
- **Images**: only the word (search term) is sent: Unsplash, Wikimedia Commons, Higgsfield and Lovable AI Gateway (image generation)
- **Maps**: Google (Google Maps). When a map is shown on the web version, your device loads it from Google. To look up a place name on the web version, the photo's coordinates are sent to Google through Lovable's relay. In the iPhone app, place names are looked up by sending the coordinates from your device to Apple's geocoding service (not through the operator's servers)
- **Apple (iPhone app)**: sign-in with Apple, speech recognition for search by voice (audio, when it cannot be recognised on the device), place-name lookup (coordinates), and in-app purchases (the purchase record, once they start)
- **Payments**: Stripe (payments, invoices, and the subscription management page). Your email address, user ID and payment details are provided to Stripe
- **Advertising**: Google (AdMob in the iPhone app; AdSense on the web version, only when advertising is enabled). Device information and a record of the ad being shown and watched go to Google (see section 6)

**Consent to sending data to AI**: before you use an AI feature for the first time, the iPhone app shows a screen explaining what is sent (photos, images picked from Photos, scan frames, words, text you enter, words you said as text, and settings such as your study language), where it goes and what it is used for, and asks for your consent. If you do not consent, AI features (the camera, scanning, card creation, diary correction and so on) are unavailable and nothing is sent; browsing your words and reviews still work. You can withdraw consent at any time in Settings → Privacy → “Consent to send data to AI”. Your email address and name are never sent to AI providers. The operator itself does not use your photos or diary to train AI.

## 5. Transfers outside Japan

Many of these providers are located outside Japan, and your information may be processed and stored on servers outside Japan. The main countries of the providers that receive personal information are:

- United States: Supabase, Cloudflare, Google, Apple, OpenAI, Anthropic, OpenRouter, Microsoft, ElevenLabs, Stripe
- Sweden (EU) and the United States: Lovable
- China: DeepSeek, Moonshot AI (only if the settings use them)

Their systems: the United States has no comprehensive federal privacy law, but has sector-specific federal laws and state laws such as the California Consumer Privacy Act (CCPA). The EU has the General Data Protection Regulation (GDPR), and Japan's Personal Information Protection Commission recognises the EU as providing an equivalent level of protection. China has a Personal Information Protection Law, but also laws that broadly allow government access to data (such as the National Intelligence Law). For details, see the survey of foreign systems published by Japan's Personal Information Protection Commission.

The operator uses each provider after confirming that, through its terms or data processing agreements, it takes measures equivalent to those required by Japan's Act on the Protection of Personal Information (such as security measures and no use beyond the purpose). Providers that receive only the text of a word (such as image search) receive nothing that identifies you. For the country of a provider not listed above, or for more about the measures providers take, contact us (section 12) and we will tell you without delay. By agreeing to this policy and using the Service, you consent to your information being provided to providers in these countries.

## 6. Advertising

When you have used up the free captures, the iPhone app shows a video ad from Google AdMob only if you choose to (watching it to the end gives you one more capture). The app never shows ads on its own, at launch or during a capture. Google uses device information (model, OS, IP address and similar) and the record of the ad being watched to deliver ads, measure them and prevent fraud, and may show ads personalised to your interests. The iPhone app does not use the advertising identifier (IDFA) and does not ask for App Tracking Transparency permission. Users in the European Economic Area, the UK and Switzerland are asked for consent through Google's consent message, and can change it at any time in the app's Settings → “Legal” → “Ad privacy choices”.

When advertising is enabled, the web version of the Service shows ads served by Google AdSense. Google may use cookies and device identifiers to show ads, including ads personalised to your interests. To learn how Google uses information, see [ How Google uses information from sites or apps that use our services ](https://policies.google.com/technologies/partner-sites) . You can turn off personalised ads in [ Google's ad settings ](https://adssettings.google.com) . Users in the European Economic Area, the UK and Switzerland are asked for consent through Google's consent message. Pro users do not see ads.

## 7. Retention and deletion

We keep your information while you have an account. You can delete it yourself at any time from “Delete account” in Settings. Deletion cannot be undone. It erases: your profile and sign-in account, your photos (captured photos and profile photo), word cards, collection and review records, diary, scan and usage records, AI usage records and error reports.

The following remain after deletion:

- Dictionary entries you added (headwords, meanings and so on). They are part of the dictionary shared with other learners, so they are kept, but unlinked from you
- Cached pronunciation audio, made from the text of words and shared; it is not linked to you
- Payment and invoice records held by Stripe (under the law and Stripe's terms)
- Copies in database backups and server logs, which are erased when each provider's retention period ends
- Information already sent to providers, which they handle under their own terms

When you delete your account in the iPhone app, the app also erases the information stored on your device (section 10). Deleting the app also removes it from your device.

**Deleting your account does not cancel a paid plan automatically.**Before deleting, cancel it from “Manage subscription” in Settings. If you bought it with an in-app purchase on iPhone, cancel it in the iPhone Settings app → your name → Subscriptions.

## 8. Your rights

You may ask for disclosure of the information the operator holds about you, for its correction, addition or deletion, for its use to stop or for it to be erased, and for its provision to third parties to stop. You can edit your display name, photos and words in the app, and delete your account and its data from “Delete account” in Settings. For other requests (including notice of the purposes of use and disclosure of records of provision to third parties), use the contact in section 12. We will respond without delay in accordance with the law after confirming that you (or your agent) are making the request. There is no fee. If the law does not allow us to comply, we will tell you why.

## 9. Children

The Service is not directed at children under 13, and children under 13 may not use it (Terms of Service, section 2). If you are under 18, please get your parent's or guardian's consent before using the Service (including buying a paid plan). If we learn that we have collected information from a child under 13, we will delete it.

## 10. Cookies and storage on your device

The Service uses your browser's local storage and IndexedDB to keep you signed in, to remember settings such as the display language, to hold data waiting to be saved while offline, and to cache images and audio. The Service itself does not use cookies for tracking or advertising. However, when advertising is enabled Google uses cookies (section 6); when the iPhone app shows an ad, Google's AdMob component stores on your device the information it needs to deliver ads and to remember your consent; and Google (when a map is shown) and Stripe (on the payment page) may use their own cookies and similar technologies.

The iPhone app stores the following on your device: what keeps you signed in (the Keychain), display and sound settings, the state of your consent to sending data to AI (date and version), the words, small photo thumbnails and review count shown in home screen widgets (a storage area shared by the app and its widgets), scheduled notifications (review reminders and location reminders), photos waiting to be sent while offline (“Photo waiting to be analyzed”) and unsaved diary drafts, and cached images and audio. None of this is sent to the operator's servers, except photos and diary entries that are sent once you are back online.

## 11. Security

The operator takes the following measures to prevent leaks, loss or damage of personal information.

- Basic policy: we set out this policy and follow the relevant laws and guidelines
- Handling rules: for each stage (collection, use, storage, provision and deletion) we set how information is handled and who is responsible
- Organisational measures: a responsible person is appointed, with procedures for reporting and responding to handling that breaks the law or this policy, or to signs of a leak
- Personnel measures: anyone handling personal information is required to keep it confidential and handle it properly
- Physical measures: devices that handle personal information are protected against theft and loss, with screen locks and encrypted storage
- Technical measures: connections are encrypted (HTTPS), and the database restricts access per user so that only you can read and write your own information. Keys for external services are held only on the server, never in the app, and when the operator looks at usage, the scope is limited as described in section 2
- Understanding the external environment: before using providers in other countries, we check those countries' systems (section 5) and take security measures accordingly

## 12. Operator and contact

Questions about this policy or how we handle personal information, requests for disclosure and similar, and complaints are received at the operator's contact below.

- **Operator**: 〔LEGAL_SELLER_NAME〕
- **Representative**: 〔LEGAL_REPRESENTATIVE, shown only if set〕
- **Address**: 〔LEGAL_ADDRESS; with ON_REQUEST: “Disclosed without delay upon request (please request it at the email address below)”〕
- **Phone**: 〔LEGAL_PHONE; with ON_REQUEST: as above〕
- **Email**: 〔LEGAL_EMAIL〕

(While LEGAL_EMAIL is not set, the page shows “The operator's contact details are being prepared. …” instead of the table.)

## 13. Changes to this policy

We will announce changes to this policy in the Service. For significant changes that add new purposes of use, we will ask for your consent again before you continue using the Service.

## 14. Additional information by region

### Users in Taiwan

Under Article 8 of Taiwan's Personal Data Protection Act: the collector is the operator (section 12). The purposes are those in section 2, mainly falling under Taiwan's categories of performance of contractual relationships, consumer and customer management and services, education and learning services, information (communication) services and e-commerce services. The types of personal data are listed in section 1. The period of use is as in section 7; the regions are Japan and the countries in section 5; the users are the operator and the providers in section 4; the method is electronic storage, processing and transmission. You may request to inquire into and review your data, receive copies, supplement or correct it, stop its collection, processing or use, and delete it (section 8). Without required information such as an email address you cannot create an account, and without photos, location or voice the related features cannot be used.

### Users in the European Economic Area, the UK and Switzerland

Where the GDPR or the UK GDPR applies, the operator processes personal data on these legal bases: performance of a contract (providing the Service, accounts and the paid plan); consent (location, microphone and photo access, sending data to AI providers, and personalised ads; you can withdraw consent at any time); legitimate interests (preventing abuse, security, improving the Service and statistics); and legal obligations (such as keeping transaction records). You have the rights of access, rectification, erasure, restriction of processing, data portability and objection, and may complain to the supervisory authority in your country. Transfers outside the EEA and the UK rely on appropriate safeguards such as the European Commission's standard contractual clauses.

### Users in California, United States

The operator does not sell personal information for money. When the iPhone app shows an ad, and when advertising is enabled on the web version, Google may collect information with cookies and similar technologies and use it for interest-based ads (section 6), which may count as “sharing” under state law. You can turn this off in Google's ad settings, or ask us at the contact in section 12. You have the rights to know, to delete, to correct and to opt out of sale or sharing, and you will not be treated unfavourably for using them.
