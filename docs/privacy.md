# Privacy policy

*Effective 4 September 2026.*

This page covers two things: the **Peclet documentation website** you are reading, and
**Peclet gallery publisher**, the small command-line tool the project uses to upload its
own example videos to its own YouTube channel.

Contact for anything on this page: open an issue at
<https://github.com/computational-chemical-engineering/peclet/issues>, or write to the
support address shown on the application's Google consent screen.

---

## The website

These pages are static and are served by GitHub Pages from the public
[`peclet`](https://github.com/computational-chemical-engineering/peclet) repository.

* We set **no cookies** and run **no analytics**. There is no tracking script on this site.
* We do not collect, store or process any personal data from visitors.
* GitHub serves the files and may log request data (including IP addresses) for its own
  operational and security purposes, under
  [GitHub's Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-privacy-statement).
  We neither receive nor have access to those logs.
* Pages embed videos from YouTube. Playing one causes your browser to contact Google,
  which is governed by the [Google Privacy Policy](https://policies.google.com/privacy).

## Peclet gallery publisher (the OAuth application)

### What it is

A command-line tool, run by the Peclet maintainers on their own computers, that uploads
the project's example animations to the project's own YouTube channel
([@PecletHPC](https://www.youtube.com/@PecletHPC)) and keeps their titles, descriptions
and playlists in step with the published examples. Its source is public, in the
`youtube_publishing` project.

It is **not a service offered to other people**. There are no accounts, no sign-up, and no
server: it runs locally and talks only to Google's YouTube Data API. In normal use the
only person who ever authorises it is the owner of the channel it publishes to.

### What data it accesses

When you authorise it, the tool asks Google for two permissions:

| Scope | Why it is needed |
|---|---|
| `.../auth/youtube.upload` | to upload a video file to your channel |
| `.../auth/youtube` | to set a video's title, description and tags; to add it to a playlist; to set a thumbnail; and to read back which channel the authorisation applies to, so an upload cannot land on the wrong one |

It reads **no** other Google data. It does not access your email, contacts, files, or
watch history, and it does not read other people's videos or channels.

### What it stores, and where

* An **OAuth refresh token**, written to `~/.config/peclet-youtube/token.json` on the
  machine that runs the tool, readable only by that user account. This is what lets it
  upload without asking again.
* The **video identifiers** it created, in a `published.json` file in the tool's own
  repository, so that re-running it updates an existing video instead of uploading a
  duplicate. These identifiers are already public — they are the id in a YouTube URL.

Everything stays on the operator's machine or in Google's systems. **The tool has no
server, no database and no telemetry**, so there is nowhere else for data to go.

### What it does not do

* It does not transmit your data to anyone other than Google, as required to perform the
  upload you asked for.
* It does not sell, rent, or share your data, and it shows no advertising.
* It does not use your data to train any model.
* It collects nothing about anyone who merely *watches* the published videos; that is
  between the viewer and YouTube.

### Limited Use

Peclet gallery publisher's use of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the **Limited Use** requirements.

### Withdrawing access, and deletion

You can revoke the tool's access at any time at
[myaccount.google.com/permissions](https://myaccount.google.com/permissions); it can then
do nothing at all until it is authorised again. To remove the stored credential from a
machine, delete `~/.config/peclet-youtube/token.json`. Videos already uploaded belong to
the channel and are managed in YouTube Studio like any other.

Since no personal data is held anywhere but that one local file, there is nothing further
for us to erase on request — but if you believe we hold something about you, write to the
address at the top of this page and we will look into it.

## Changes

Any change to this policy will be committed to the public repository, so its full history
is visible in the file's git log. The date at the top marks the current version.
