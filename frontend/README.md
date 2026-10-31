# Horizon — Landing Page

Marketing site for Horizon, built with Vite + React. No UI or animation libraries: scroll reveals, parallax and count-up stats are driven by small hooks in `src/hooks/useScroll.js` and plain CSS, and all motion respects `prefers-reduced-motion`.

## Development

```bash
cd frontend
pnpm install
pnpm dev       # http://localhost:5173
pnpm build     # outputs to dist/
pnpm preview   # serve the production build
pnpm lint
```

## Structure

```
frontend/
├── public/               # logo + favicon (from the app's AppIcon)
└── src/
    ├── App.jsx           # section composition
    ├── index.css         # design tokens, layout, animations
    ├── links.js          # GitHub / release URLs
    ├── hooks/useScroll.js
    ├── assets/           # provider logos (from Assets.xcassets)
    └── components/       # Nav, Hero, MenuBarMock, Features, HowItWorks, Benchmarks, QuickStart, Footer
```
