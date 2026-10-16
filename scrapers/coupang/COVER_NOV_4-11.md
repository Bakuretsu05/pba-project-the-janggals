# Covering Coupang, Nov 4–11

Marvin is away from Nov 4 to Nov 11. During that time a teammate collects Coupang on their own
Windows laptop: from the **Nov 4 10:07** run to the **Nov 11 23:07** run, Taiwan time. Marvin
takes over again from Nov 12 10:07. [README.md](README.md) explains how the collection works.
Delete this file after Nov 12.

Who | Before | Steps
---|---|---
Teammate | any time before Nov 4 | [1. Set up and test](#1-set-up-and-test-teammate)
Marvin | Nov 3, after the 10:07 run | [2. Hand over](#2-hand-over-marvin-nov-3)
Teammate | Nov 4, 00:00–10:00 | [3. Switch on](#3-switch-on-teammate-nov-4)
Teammate | Nov 4–11 | [4. Each day](#4-each-day-teammate)
Teammate | Nov 12, 00:00–10:00 | [5. Switch off and send the runs](#5-switch-off-and-send-the-runs-teammate-nov-12)
Marvin | Nov 12, 00:00–10:00 | [6. Take back](#6-take-back-marvin-nov-12)

> **The one rule.** Between Oct 19 and Nov 25, turn the extension on, or load it, **only between
> 00:00 and 10:00 Taiwan time**. Turned on later in the day, it immediately makes up that day's
> 10:07 run if this computer has not done it. That duplicates the run on Marvin's laptop.
> Turning it off is safe at any time when no run is going.

Only one laptop may be collecting at a time. Otherwise every run is saved twice, under different
stamps.

## 1. Set up and test (teammate)

You need: Windows, time zone *Taipei*, Google Chrome, a Taiwanese home connection (no VPN), and
a copy of this repository (`git clone`, or `git pull` on `main`). Pick a time between 00:00 and
10:00, or any time before Oct 19 10:07.

1. **Chrome settings.**
   - `chrome://settings/downloads`: *Ask where to save each file before downloading* is **off**.
   - `chrome://settings/system`: *Continue running background apps when Google Chrome is
     closed* is **on**.
   - Sign out of Coupang in this Chrome. Signed-in shoppers see different prices from the
     visitor prices the study records (first-purchase prices, see README).
2. **Load the extension.** `chrome://extensions` → *Developer mode* on → *Load unpacked* → pick
   `scrapers\coupang\extension` in your copy of the repository. Pin it to the toolbar. Chrome
   loads it from that folder, so don't move or delete the folder, and stay on `main`.
3. **Test run.** Click the extension's icon, then *Test run*. After about a minute, *Recent
   runs* should show this line in green:

   `<date>_<time> (test): 4 products | product page 3, other page 1, bad input 1 | finished`

   `Downloads\coupang-snapshots-test\<date>_<time>\` should hold `products.csv`, four
   `.html.gz` files and `run.json`. No Save dialog should appear.
   - If the line says `blocked`, Coupang refuses your connection. Tell Marvin before Nov 4.
4. **Turn the extension off**, before 10:07: on `chrome://extensions`, switch *Coupang snapshots*
   off. Do not remove it.
5. Delete `Downloads\coupang-snapshots-test\` and tell Marvin how the test went.

## 2. Hand over (Marvin, Nov 3)

After the Nov 3 10:07 run has finished:

1. Switch the extension off on `chrome://extensions`.
2. Turn off the wake task, in PowerShell:
   `Disable-ScheduledTask -TaskName 'Coupang snapshots wake'`
3. Send the teammate the Healthchecks ping URL(s) privately, never through the repository.
4. In Healthchecks.io, *Integrations* → *Email*: add the teammate's address so they also get
   the alerts. They confirm it from the email they receive.

## 3. Switch on (teammate, Nov 4)

Between 00:00 and 10:00 on Nov 4:

1. **Turn the extension on** on `chrome://extensions`.
2. **Settings.** Click the extension's icon → *Settings*: paste Marvin's ping URL into
   *Healthchecks.io ping URL*, and the second one, if Marvin sent one, into the second field.
   Click *Save settings*.
3. **Check the next run.** The popup should say `Next run: 2026-11-04 10:07 (Taiwan time)`. If it
   says *No more scheduled runs*, quit Chrome completely (⋮ menu → *Exit*), start it again, and
   check again.
4. **Wake task.** From the root of the repository, in PowerShell:

   ```
   powershell -ExecutionPolicy Bypass -File scrapers\coupang\windows\install_wake_task.ps1
   ```

   It prints the task's next run time. It wakes the laptop one minute before each run and keeps
   it awake until the run is saved.

## 4. Each day (teammate)

The runs are at **10:07** every day, plus **18:07 and 23:07 on Nov 10 and 11**.

- At those times the laptop must be **plugged in**, signed in to Windows (a locked screen is
  fine) and on or asleep, **not shut down**. Waking from sleep hasn't been tested on every
  laptop, so if you can, leave it awake at run times.
- A run takes about 10 minutes. Chrome doesn't need to be open; a minimised window appears and
  closes by itself.
- **After each run**, open the extension's popup. The newest line under *Recent runs* should be
  green and say `finished`, with about as many products as `products/products.csv` has rows.
- **When something goes wrong**, Healthchecks emails you and the extension's icon shows a red
  `!`. Click *Run now* **on the same day**. Then tell Marvin which run it was. A run can't be
  made up on a later day.
- If many products come back `blocked`, don't retry more than once that day. Repeated tries
  make Coupang more suspicious of the connection.

## 5. Switch off and send the runs (teammate, Nov 12)

After the Nov 11 23:07 run has finished (about 23:20), and before Nov 12 10:00:

1. Remove the extension: `chrome://extensions` → *Coupang snapshots* → *Remove*.
2. Remove the wake task, in PowerShell:
   `Unregister-ScheduledTask -TaskName 'Coupang snapshots wake' -Confirm:$false`
3. Zip `Downloads\coupang-snapshots\` (one folder per run, plus `wake.log`) and share it with
   Marvin. You don't need R; Marvin converts the runs.

## 6. Take back (Marvin, Nov 12)

Between 00:00 and 10:00 on Nov 12:

1. Switch the extension on and check the popup says `Next run: 2026-11-12 10:07`. If it says *No
   more scheduled runs*, exit and restart Chrome.
2. Turn the wake task back on: `Enable-ScheduledTask -TaskName 'Coupang snapshots wake'`.
3. In Healthchecks.io, remove the teammate's email integration.

Then, any time:

4. Copy the run folders (`2026-11-04_1007` …, not `wake.log`) from the teammate's zip into your own
   `Downloads\coupang-snapshots\`, and run from the project root:
   `Rscript scrapers/coupang/scrape_coupang.R --saved`
5. Copy `output/` and `raw/` to the team's storage (Q6), and delete this file.
