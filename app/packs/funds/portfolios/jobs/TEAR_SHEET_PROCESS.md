# Tear Sheet Generation Process

This document describes the end-to-end technical workflow for generating "2026 Modern Minimalist" slide decks from portfolio company data extracts.

## Overview

The process is a hybrid of AI-driven content structuring and deterministic template rendering, optimized for high-impact investor presentations.

---

## 1. Trigger & Data Input

- **Source**: `PortfolioReportExtract` models contain raw company data in the `data` field (JSON/Hash).
- **Entry Point**: A user triggers generation via `PortfolioReportExtractsController#generate_tear_sheet`.
- **Backgrounding**: To prevent UI timeouts, the process is offloaded to `GenerateTearSheetJob`.

## 2. AI Blueprint Generation

The core of the "storytelling" logic resides in `TearSheetGeneratorService`.

1. **Transcript Preparation**: The raw extract data is converted into a pretty-printed JSON transcript.
2. **LLM Synthesis**: The service calls an LLM (typically Gemini 2.0) with a specialized `SYSTEM_PROMPT`.
   - **Instructions**: The prompt enforces "2026 Modern Minimalist" principles: 12-column asymmetric grids, glassmorphism, 8% breathable margins, and Tabler icon mapping.
   - **Output**: The AI returns a "Blueprint"—a JSON array of slide objects.
3. **Blueprint Schema**:
   ```json
   { "template": "key_metrics", "title": "...", "metrics": [...] }
   ```

## 3. Template Rendering (Rails Side)

Rather than letting the AI generate raw HTML (which is fragile), the system uses local ERB templates for consistency and performance.

- **Renderer**: The service uses `ApplicationController.renderer` to perform out-of-controller rendering.
- **Partials**: Each slide in the blueprint is mapped to a partial in `app/packs/funds/portfolios/views/tear_sheet_presentations/templates/`:
  - `_cover.html.erb`: Open Canvas layout.
  - `_key_metrics.html.erb`: Bento Box grid.
  - `_strategic_highlights.html.erb`: Vertical timeline.
  - `_investment_thesis.html.erb`: 2/3 asymmetric split.
  - `_risks.html.erb`: Categorized risk grid with impact badges.

## 4. Persistence & Delivery

- **Storage**: The generated HTML and the original JSON blueprint are stored in the `TearSheetPresentation` model.
- **Real-time Delivery**: `GenerateTearSheetJob` uses **Turbo Streams** to broadcast the HTML directly to the user's `slides_container` without a page refresh.

## 5. Frontend & Aesthetics

The frontend is powered by **Reveal.js** and the `presentation.html.erb` layout.

- **Grid System**: Implements a 12-column CSS Grid (`grid-cols-12`) for asymmetric layouts.
- **Glassmorphism**: Utility classes (`.glass-card`, `.glass-border`) provide backdrop blur and 24px rounded corners.
- **Typography**: Optimized weights (800 for headers, 300 for body) to match the minimalist aesthetic.
- **Icons**: Global integration with **Tabler Icons** webfont for consistent, bold iconography.

## 6. Exporting

- **Resolution**: Designed for 1920x1080 (HD) displays.
- **Print Fidelity**: Updated `@media print` styles ensure that "Export PDF" via the browser produces high-fidelity, slide-per-page documents with preserved gradients and backgrounds.

---

_Last Updated: January 2026_
