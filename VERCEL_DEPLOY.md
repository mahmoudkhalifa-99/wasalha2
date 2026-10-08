# Wasalha Flutter Web -> Vercel

1. Push this repository to GitHub.
2. Import the repository into Vercel.
3. Vercel will use `vercel.json` and run `scripts/vercel-build.sh`.
4. Output directory: `build/web`.
5. Firebase Web configuration is in `lib/firebase_options.dart`.

Important: the Android build is unchanged. Web uses a conditional notification implementation and browser APIs.
