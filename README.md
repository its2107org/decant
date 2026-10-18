# Decant

Ian's wine app for iPhone.

- **Cellar**: bottles he owns but hasn't opened. "Opened it" moves a bottle to Tasted with his score.
- **Tasted**: every wine he's drunk, with his score out of 100, date and notes.
- **Scan**: photograph a label in a shop to see what the wine is, what New York shops charge for it (with a good / fair / high verdict on the shelf price) and its Vinous score.

Sort and filter by grape, region, country, vintage, price, score or type.

## How it works

- **Labels**: the photo goes to Claude Sonnet 5.5, which returns a standard record (producer, wine, vintage, grapes, country, region, appellation, classification…) using structured outputs.
- **New York prices**: Claude Sonnet 5.5 with web search, located in New York, reads NYC shop listings and returns shop prices. Decant works out the typical price and the verdict on the phone.
- **Vinous**: Vinous has no public API. Ian signs in once in Decant's built-in browser; Decant finds the wine's Vinous page with a web search limited to vinous.com, opens it in a hidden browser that shares his sign-in, and Claude Haiku 5.5 picks out the score, critic and drinking window. "Open on Vinous" shows the page, with a button to take the score from whatever page is on screen.
- **Vivino and Wine-Searcher**: links only (Vivino doesn't allow apps to read its data; Wine-Searcher's data service is sold to businesses).
- Ian's Claude key is kept in the phone's keychain. Calls go straight from the phone to Claude; there's no server. Settings shows a running total of this month's spend.
- Wines are stored on the phone with SwiftData (included in his iCloud phone backup).
- Native SwiftUI, iOS 26+, iPhone only. The Xcode project is generated from `project.yml` with XcodeGen.

## Workflows

1. **Set up with Apple**: `check` the secrets, create the `identifiers`, then `certificates`, then `testers`.
2. **Check build and screenshots**: runs on every push; builds for the simulator, runs the self-check (`-DecantSelfTest`) and saves screenshots to the `screenshots` branch.
3. **Build Decant**: builds and uploads to TestFlight. Runs on every push to `main`, monthly (so it never expires) and on demand. Uses the same Apple secrets and `Match-Secrets` certificate store as Ian's other apps.
