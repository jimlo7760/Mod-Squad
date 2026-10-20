# Mod Squad

Mod Squad is a web application in which users describe a car and a "vibe", an AI designs a complete modification build for it, and the community votes on which builds deserve to exist. It was developed for the Columbia course *Design for GenAI*.

A build consists of a title, a tagline, and four to six parts, each with a category, a specific part, a short description, and an estimated cost in US dollars. Every build is shown with a real, openly licensed photograph of the car and is open to up-votes and down-votes from other signed-in users.

## Table of Contents

1. [Features](#features)
2. [Technology Stack](#technology-stack)
3. [Getting Started](#getting-started)
4. [Configuration](#configuration)
5. [Database Setup](#database-setup)
6. [Application Routes](#application-routes)
7. [Project Structure](#project-structure)
8. [Security and Usage Limits](#security-and-usage-limits)
9. [Deployment](#deployment)
10. [Development Notes](#development-notes)
11. [Acknowledgements](#acknowledgements)
12. [License](#license)

## Features

- **AI build generation.** The user selects a brand, model, and optional chassis code, writes a vibe of up to 200 characters, and may upload a photo of their own car (JPG, PNG, or WebP, up to 4 MB). The AI works from that photo when one is supplied. The prompt and the model that answered are stored with every build.
- **Car catalogue.** A built-in catalogue covers 21 brands, 89 models, and 214 model and chassis combinations, with production years shown next to each chassis code. Rows added to the Supabase `Car` table are merged into the catalogue.
- **Reference photographs.** Each catalogue car has a hand-vetted photograph from Wikimedia Commons, displayed with its photographer, licence, and a link to its source. Cars outside the catalogue fall back to a live Commons search.
- **Voting.** Signed-in users up-vote or down-vote builds. The feed can be sorted by newest, top of the last 24 hours, or all time. Users cannot vote on their own builds and have one vote per build.
- **Judge mode.** Presents one build at a time with large vote buttons and hides the score until the user has voted.
- **Daily challenge.** A themed prompt, identical for all users on a given UTC day, is shown on the home page and pre-fills the generator.
- **Editable parts list.** The owner of a build can remove parts, add parts found through an AI part search (each result is labelled `confirmed`, `likely`, or `check` for fitment), and reset the list to the AI's original.
- **Build renders.** The owner can ask an image model to edit the car's reference photo so that it shows the modifications. Each build may carry one render.
- **Accounts and profiles.** Sign-in is with Google through Supabase Auth. Users supply a first and last name and may upload an avatar. A personal dashboard shows the user's builds, upvotes, and total score, and builds can be deleted by their owner.
- **Sharing.** Each build has its own page with a shareable link.

## Technology Stack

| Layer | Technology |
| --- | --- |
| Framework | [Next.js](https://nextjs.org/) 16 (App Router, Server Actions, Turbopack) and React 19 |
| Authentication and database | [Supabase](https://supabase.com/): Google OAuth, Postgres with Row Level Security, Storage |
| Supabase clients | `@supabase/supabase-js` and `@supabase/ssr` |
| Text generation | Google Gemini REST API (no AI SDK dependency) |
| Image generation | Google Gemini image models ("Nano Banana") |
| Car photographs | Wikimedia Commons API |
| Hosting | [Vercel](https://vercel.com/) |
| Language and styling | JavaScript and a single global stylesheet (`app/globals.css`) |

## Getting Started

### Prerequisites

- Node.js 20.9 or later and npm
- A [Supabase](https://supabase.com/) project with the Google provider enabled
- A Google Gemini API key, which is free and requires no card: <https://aistudio.google.com/apikey>

### Installation

```bash
git clone git@github.com:jimlo7760/MOD-SQUAD.git
cd MOD-SQUAD
npm install
```

### Environment variables

Copy the example file and fill in the values described under [Configuration](#configuration).

```bash
cp .env.example .env.local
```

### Database

Apply the SQL files in `supabase/` as described under [Database Setup](#database-setup), then enable Google sign-in in the Supabase dashboard (see [Google sign-in](#google-sign-in)).

### Run the development server

```bash
npm run dev
```

The application is served at <http://localhost:3000>. If that port is taken, Next.js selects the next free one.

### Scripts

| Command | Description |
| --- | --- |
| `npm run dev` | Start the development server |
| `npm run build` | Create a production build |
| `npm run start` | Serve the production build |

## Configuration

Environment variables are read from `.env.local`, which is excluded from version control.

| Variable | Required | Description |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Yes | The URL of the Supabase project. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Yes | The Supabase anon (public) key. Access is restricted by Row Level Security. |
| `GEMINI_API_KEY` | Yes | Gemini API key. Server-only: it has no `NEXT_PUBLIC_` prefix and must never be exposed to the browser. |
| `GEMINI_MODEL` | No | Text model to try first. The default is `gemini-3.8-flash`. If it is overloaded or unavailable, the application falls back to `gemini-3.5-flash-lite` and then `gemini-3.1-flash-lite`. |
| `GEMINI_IMAGE_MODEL` | No | Image model for "Render this build". The default is `gemini-nano-banana-2.1`, at roughly $0.034 per image. Image generation requires billing to be enabled on the Google project, because the free tier has no image quota. |

### Google sign-in

1. In the Supabase dashboard, open **Authentication > Providers**, enable **Google**, and supply the OAuth client ID and secret created in Google Cloud.
2. In Google Cloud, add Supabase's callback address (`https://<project-ref>.supabase.co/auth/v1/callback`) as an authorised redirect URI of that OAuth client.
3. In Supabase, under **Authentication > URL Configuration**, add `http://localhost:3000/auth/callback` and the production equivalent (`https://<your-domain>/auth/callback`) to the allowed redirect URLs. The application requests exactly `/auth/callback`, with no extra path or query parameters.

## Database Setup

The SQL files in `supabase/` are intended to be run in the Supabase dashboard (**SQL Editor > New query > paste > Run**). Each file is safe to re-run on its own, subject to the warning below.

| Order | File | Purpose |
| --- | --- | --- |
| 1 | `profiles.sql` | `profiles` table, a trigger that creates a profile on first sign-in, and the `avatars` storage bucket. |
| 2 | `assignment4.sql` | `builds` and `build_votes` tables, vote-counting trigger, daily generation limit, Row Level Security policies, and the `car-photos` storage bucket. |
| 3 | `assignment4_photos.sql` | Columns for the Wikimedia photograph, its credit, and its licence. |
| 4 | `assignment4_render.sql` | Columns, policies, and the `build-renders` storage bucket for AI renders. |
| 5 | `assignment4_edit.sql` | Functions that let owners edit a build's parts, the `part_searches` rate-limit table, and the stored copy of the AI's original list. |

The site continues to work if `assignment4_edit.sql` has not yet been run, but editing and part search remain switched off until it has.

> **Warning.** `assignment4.sql` revokes all privileges on `builds` and grants them again, which removes the column grants made by the photos and render files. After re-running `assignment4.sql`, run `assignment4_photos.sql` and `assignment4_render.sql` again, in order. To apply everything at once on macOS:
>
> ```bash
> cat supabase/assignment4.sql supabase/assignment4_photos.sql supabase/assignment4_render.sql supabase/assignment4_edit.sql | pbcopy
> ```

**The `Car` table.** `assignment4.sql` configures access to a table named `public."Car"` but does not create it; it originates from an earlier assignment. The application reads only its `"Brand"` and `"Model"` columns, and the table may be empty because the built-in catalogue is always available. If your project does not have it, create it before running `assignment4.sql`:

```sql
create table if not exists public."Car" ("Brand" text, "Model" text);
```

## Application Routes

All routes except `/login` and `/auth/*` require a signed-in user; other visitors are redirected to `/login`. Signed-in users who have not yet saved a first and last name are redirected to `/profile`.

| Route | Description |
| --- | --- |
| `/login` | Landing page with an example build and Google sign-in (public) |
| `/` | Feed of builds, today's challenge, and sort tabs |
| `/generate` | Build generator |
| `/builds/[id]` | A single build, with a share link |
| `/judge` | Judge mode |
| `/dashboard` | The user's builds and statistics |
| `/profile` | Name and avatar |
| `/auth/callback` | OAuth code exchange (public) |
| `/auth/signout` | Sign-out, accepts `POST` only |
| `/api/car-photo` | `GET`: Commons photo lookup for the generator preview |
| `/api/part-research` | `POST`: AI part search for the owner of a build |

## Project Structure

```
app/                     Routes (App Router), Server Actions in actions.js, global styles
  api/                   Route handlers: car-photo, part-research
  auth/                  OAuth callback and sign-out
  builds/ dashboard/ generate/ judge/ login/ profile/
components/              Shared UI: build cards, vote buttons, brand picker, mod editor, ...
lib/
  ai.js                  Gemini text generation and part research (server-only)
  render.js              Gemini image rendering (server-only)
  carCatalog.js          Brand, model, and chassis catalogue
  carYears.js            Production years per chassis
  carPhotos.js           Hand-vetted Commons photographs for the catalogue
  carPhoto.js            Live Commons photo search
  builds.js, mods.js     Build queries and validation of the parts list
  challenges.js          Daily challenge themes
  auth.js                Session and profile helpers
  supabase/              Browser, server, and session-refresh clients
proxy.js                 Redirects signed-out visitors and refreshes sessions
public/brands/           Brand logos for the brand picker
supabase/                SQL for the database, policies, and storage
```

## Security and Usage Limits

Access control is enforced in two places: each page and Server Action re-checks the caller, and the database applies Row Level Security as a second layer.

- Every table has Row Level Security enabled. Logged-out visitors can read only the `Car` catalogue.
- Signed-in users can read all builds and profiles, but may create, delete, and edit only their own.
- Vote counters cannot be written by clients; they are maintained by a database trigger.
- Votes are visible only to their author, and a user cannot vote on their own build.
- Database constraints restrict a build's Commons photograph links to Wikimedia addresses and its render link to the application's own storage bucket.
- The Gemini key is used only in server code.

The AI features consume quota or money, so they are rate-limited per user in the database:

| Action | Limit |
| --- | --- |
| Generate a build | 10 per 24 hours |
| Render a build | 5 per 24 hours, and one render per build |
| Part search | 40 per 24 hours |

## Deployment

The application is designed for Vercel.

1. Import the repository into Vercel.
2. Add the environment variables listed under [Configuration](#configuration) to the project.
3. Add the production URL to the allowed redirect URLs in Supabase (see [Google sign-in](#google-sign-in)).

Several pages and routes that call AI models request a function duration of 60 to 90 seconds (`maxDuration`). Confirm that your Vercel plan permits this. Uploaded photographs are limited to 4 MB to stay beneath Vercel's request size limit.

## Development Notes

- Next.js 16 differs from earlier releases. For example, `proxy.js` replaces `middleware.js`, and `cookies()` and `searchParams` are asynchronous. The documentation for the installed version is in `node_modules/next/dist/docs/`. See `AGENTS.md`.
- `@supabase/ssr` is pinned to `0.12.0` for compatibility with Node.js 20.
- The project has no automated test suite. Changes are verified by running the application.
- Cars in the catalogue are photographed from Wikimedia Commons by hotlinking, not by copying. To change a car's photograph, edit its entry in `lib/carPhotos.js`.

## Acknowledgements

- Car photographs are provided by their authors through [Wikimedia Commons](https://commons.wikimedia.org/) under free licences, and each is shown with its credit.
- Brand names and logos are trademarks of their respective owners and are used only to identify vehicle makes.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Jim Lu.
