# Themes

A theme is a folder under `themes/` with up to three files. No code runs from a theme,
so they are safe to share and drop in.

```
themes/<name>/
  theme.css     required  colour/typography tokens (and any CSS overrides)
  scene.svg     optional  static artwork behind everything, 2560 x 720
  theme.json    optional  animated particles (petals, snow, leaves…) and metadata
```

Pick a theme with `./install.sh --theme=<name>` (or `./edge-dash.sh --theme=<name>` by
hand), or tap the hidden top-left corner of the panel for the picker. The default is
`tokyo`. `themes/minimal` is the smallest working theme: copy it, rename it, start editing.

**Register it** by adding the folder name to `themes/themes.json` so the picker lists it,
and give `theme.json` a `swatch` of two or three colours for the picker's tile:

```json
{ "name": "My Theme", "swatch": ["#101418", "#ff6ec7", "#5ee7ff"], "particles": { "count": 0 } }
```

## 1. `theme.css` — the tokens

`base.css` draws everything from CSS custom properties with neutral grey defaults.
A theme redefines them on `:root`:

| Token | Used for |
|-------|----------|
| `--bg`, `--bg-2` | page background gradient, top to bottom |
| `--text` | clock digits, event times and titles |
| `--text-2` | date line, year, held-day date |
| `--accent` | colon, weekday name, month, Mon–Fri headers, "+N more" |
| `--accent-2` | seconds, weekend headers, padded-month tags |
| `--muted`, `--dim`, `--line` | secondary text, padded-month days, borders |
| `--card-bg`, `--card-edge`, `--card-text`, `--card-shadow` | day cards (edge = the thick bottom border) |
| `--card-weekend-bg`, `--card-weekend-edge`, `--card-weekend-line`, `--card-weekend-text` | Saturday/Sunday cards |
| `--today-bg`, `--today-text`, `--today-edge`, `--today-shadow` | today's card (`--today-bg` may be a gradient) |
| `--panel-bg` | the held-day panel over the clock; fade it to transparent on the right |
| `--ev-bg` | event rows in that panel |
| `--scene-dim` | opacity of scene + particles while a day is held (default `.18`) |
| `--font` | font stack |
| `--clock-w`, `--clock-pad` | width of the clock column, its padding |

Anything the tokens don't cover can be overridden with ordinary CSS; the element
contract is the IDs and classes in `base.css` (`#time`, `#date`, `#grid .day`,
`.today`, `.weekend`, `.other`, `.past`, `#sched .ev`, …). Those names are stable.

## 2. `scene.svg` — artwork

One SVG with `viewBox="0 0 2560 720"`. It is injected inline, so it can use the
theme's CSS variables (`style="fill: var(--accent)"`) and it is drawn behind the clock
and calendar. Things to know about the layout it sits under:

- Clock digits occupy roughly x 110–830, y 130–330; the date lines x 110–720,
  y 470–590. Keep focal artwork out of there or it will be covered.
- Day cards fill x 1200–2510, y 170–700, mostly opaque. Artwork behind them reads
  only in the 6 px gaps and in the padded "other month" cells, which are transparent.
- The bottom strip below y ≈ 600 is a good place for ground, water or hills: cards
  float over it and it shows fully under the clock.
- Everything in the scene dims to `--scene-dim` while a day is held.
- The SVG may animate itself with SMIL (`<animate>`, `<animateTransform>`,
  `<animateMotion>` + `<mpath>`), which keeps themes script-free. `themes/tron` uses
  it for passing light cycles and `themes/circuit` for pulses that travel the traces;
  `begin="3s; id.end+11s"` is the idiom for "every so often".

## 3. `theme.json` — particles

```json
{
  "name": "Tokyo",
  "particles": {
    "count": 22,
    "viewBox": "0 0 32 32",
    "path": "M16 2 C 22 6, 28 12, 26 20 … Z",
    "colors": [["#fbd3e0", "#f1a7c1"], ["#f8c4d6", "#e995b4"]],
    "size": [18, 40],
    "opacity": [0.45, 0.85],
    "fall": [18, 34],
    "sway": [3, 6],
    "spin": [6, 14]
  }
}
```

`name` is shown in the picker and `swatch` colours its tile. `count` particles are spawned, each a single SVG `path` (in `viewBox` units) filled
and stroked with one of the `[fill, stroke]` pairs, sized between `size[0]` and
`size[1]` px. They fall for `fall` seconds, sway sideways on a `sway`-second cycle and
rotate once per `spin` seconds; every range is `[min, max]` and picked per particle.
`"count": 0` or no `theme.json` disables the layer.

## Checking your work

```sh
./edge-dash.sh --theme=<name> --shot                       # screenshot.png after 4 s
./edge-dash.sh --theme=<name> --shot --hold=2026-10-14     # with the day panel pinned open
```

Check both: the held-day panel is where low-contrast `--text`/`--muted` choices show.
