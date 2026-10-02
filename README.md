# AI-IZ

Open [ai-iz.html](ai-iz.html) in Edge or Chrome to present the current 59-slide workshop. Keep the `assets` folder beside the HTML file. The deck uses its local fonts and exact tokenizer offline; if the tokenizer file is missing, token counts are marked as estimates.

Presenter keys: **→ / Space** next, **←** back, **M** slide menu, **N** notes, **P** presenter window, **T** pause or resume the timer, **B** blackout, **F** full screen, **?** help. Press **E** to edit slide text and **Ctrl+S** to download a copy with those edits. Edits are saved in the browser on that device.

`ai-iz-legacy.html` is the earlier version. The current deck is `ai-iz.html`.

The [organizer brief](organizer-brief.html) is also available as a [PDF](AI-IZ-Organizer-Brief.pdf).

Before the live Canva exercise, connect the presenting account and check that the classroom's Canva team settings allow the AI connector. Canva's [Claude setup](https://www.canva.com/help/connect-claude-to-canva/) and [ChatGPT setup](https://www.canva.com/help/connect-chatgpt-to-canva/) describe the current menus.

## Live quiz (phones + leaderboard)

Students scan the QR code on the Quizzies slide, enter a name on [play/](play/index.html) and answer on their phones. The deck opens and closes each question, shows how many have answered, and the Champions slide shows the top 10 from Supabase. Without internet, or with `live-config.js` left blank, the quiz runs on screen as before.

One-time setup:

1. Create a free Supabase project.
2. Paste the whole of [supabase/quiz.sql](supabase/quiz.sql), unchanged, into Supabase → SQL Editor and run it. Then set the presenter PIN (6+ characters) in a new query: `update quiz_secret set pin = 'your-pin-here';`. Running the script again later is safe and keeps the PIN.
3. Put the project URL and the anon / publishable key (Project Settings → API) into [live-config.js](live-config.js), and copy that file into `ai-iz-site/` too. Never use the `service_role` key.
4. Turn on GitHub Pages (Settings → Pages → deploy from `main`, root). The phone page lives at `https://amjadh23.github.io/AI-IZ/play/`, which is what the QR code points to.

On the day: open the deck, go to the Quizzies slide, type the PIN once (the laptop remembers it) and click **New game** to clear rehearsal players. Click a name on the Quizzies or Champions slide to remove it. Phones need internet, and so does the presenting laptop.
