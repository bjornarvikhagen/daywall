# daywall

A calendar wallpaper for macOS that changes colour with the day and the weather.

![daywall on an ultrawide, rainy day in Bergen](docs/preview.jpg)

I saw a wallpaper like this and wanted one that kept itself up to date, so this redraws itself through the day with the month, the date, the weather, a couple of market prices and whatever meetings I have this week.

On clear days the colour follows the sun, so you get first light in the morning, blue sky while the sun is up, golden hour before sunset and blue hour right after, and it blends between them gradually instead of jumping. The warm colours sit low on the screen like a horizon. Any other weather picks a colour family instead, so cloudy days get soft greys and lilacs and rainy days get teal and indigo, and those still warm up around sunset and darken through dusk. The date picks which colour within the family you get, so two cloudy days in a row don't look the same. Rain shows up as faint streaks, snow as flakes and fog makes everything softer. When it's properly dark it goes dark, and if the northern lights are likely that night it says so and turns green.

Every colour comes with a name, a hex code and three words of questionable meaning, for example "Quiet, depth, patience". The layout stays put for the day and drifts slowly, so the background moves a little without ever jumping around.

The weather comes from [MET Norway](https://api.met.no), which is the data behind yr.no and covers the whole world, and the aurora forecast comes from [NOAA](https://www.swpc.noaa.gov). Sunrise, sunset and how high the sun is are calculated locally.

It is one swift file with no dependencies. It uses Core Image for the gradients, Core Text for the type, and Helvetica Neue because it already ships with macOS.

## Install

You need macOS and the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/bjornarvikhagen/daywall.git
cd daywall
./install.sh
```

This compiles it into `~/Library/Application Support/Daywall` and adds a LaunchAgent that keeps it running in the background. It redraws every 5 minutes, right after your Mac wakes up and when you plug in a display, and puts the current wallpaper back when you switch Space, since macOS otherwise only changes the Space you're on. Most of the time it does nothing, since it only redraws when something on the screen has actually changed.

## Settings

Pass these as environment variables to `install.sh`, and run it again whenever you want to change them.

```sh
DAYWALL_LOCATION="Oslo" \
DAYWALL_ICS="https://outlook.office365.com/owa/calendar/…/calendar.ics" \
DAYWALL_TICKERS="Bitcoin=BTC-USD,Nasdaq 100=^NDX,Gold=GC=F" \
DAYWALL_HERO="digit" \
DAYWALL_LANG="nb" \
DAYWALL_DARK_MODE=1 \
./install.sh
```

- `DAYWALL_LOCATION` is the weather location, any city [wttr.in](https://wttr.in/:help) understands, which is only used to look up where you are. It defaults to locating you by IP, which gets confused if you're on a VPN.
- `DAYWALL_ICS` is the calendar feed for the week agenda. It gets saved to `~/Library/Application Support/Daywall/calendar-url`, which only you can read. When your next meeting is less than 15 minutes away it gets an "in 10 min" next to it, and "now" while it's on.
- `DAYWALL_TICKERS` are `Label=Symbol` pairs using [Yahoo Finance](https://finance.yahoo.com) symbols. It defaults to Bitcoin and the Nasdaq 100.
- `DAYWALL_HERO` is what goes in the second column. Your options are `digit` (the date and weekday, which is the default), `daylight` (hours of daylight and an arc showing where the sun is), `moon` (the moon phase), `next` (your next meeting) and `year` (how much of the year is gone, for when you need motivation).
- `DAYWALL_LANG=nb` switches everything to Norwegian, so it says "onsdag" and "Lettskyet". The colour names stay in English, since "Gyllen halm" doesn't quite work.
- `DAYWALL_DARK_MODE=1` switches macOS to dark mode at sunset and back at sunrise. It only does it when the sun actually crosses, so if you flip it yourself during the day it leaves you alone. The first time, macOS asks whether daywall is allowed to control System Events, and you need to say yes.

## Outlook / Teams calendar

In Outlook on the web, go to Settings → Calendar → Shared calendars → Publish a calendar, pick "Can view all details" and copy the ICS link. Anyone with that link can read your calendar, so don't paste it anywhere public. Your IT department may also have turned publishing off, in which case good luck.

Recurring meetings are handled, including weekly ones, monthly ones like "second Tuesday" or "last Friday", moved and cancelled occurrences and Outlook's Windows time zone names, so it should match what you see in Outlook.

## Previewing

To render to a folder without touching your wallpaper:

```sh
~/Library/Application\ Support/Daywall/daywall --preview ~/Desktop --size 3024x1964 \
  --weather snow --at "2026-12-24 15:30" --hero moon
```

`--at` pretends it's a specific moment, which is handy for seeing what golden hour looks like without waiting for it. `--weather`, `--night`, `--lang nb` and `--kp 6` (a strong aurora forecast) override the rest. `--dump-agenda` prints the meetings it found for the week, and `--force` redraws even when nothing has changed. The log is in `~/Library/Application Support/Daywall/daywall.log`.

## Changing it

Everything is in [`daywall.swift`](daywall.swift). The colours are in `palettes`, each with a name, hex, mood words, a base colour, the colours that get blurred together and which weather it belongs to. The clear sky colours are the `sky…` palettes right below, which also say how high up on the screen each colour sits, and `skyPalette` decides at which sun height each one takes over. The layout is in `render`. Run `./install.sh` again afterwards to recompile.

## Uninstall

```sh
./uninstall.sh
```

This removes the LaunchAgent and the data folder, including the saved calendar link, and opens wallpaper settings so you can pick something else.

## Known issues

Switching to a Space shows the old wallpaper for a moment before daywall puts the current one back. Weather is cached for 30 minutes, prices for 10, the calendar for 15 and the aurora forecast for an hour, and if you're offline it uses whatever it fetched last.

## License

MIT, see [LICENSE](LICENSE).
