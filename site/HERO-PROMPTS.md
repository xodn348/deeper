# GPT Image 2 — hero prompt pack for the deeper landing page

The landing page ships with a **CSS/SVG animated drill** as its centerpiece — it always
works, on-brand, zero dependencies. These prompts are an **optional visual upgrade**: drop
generated renders into `site/assets/` and swap them behind the hero `.stage` or as a
full-bleed background.

- Model: `gpt-image-2` (OpenAI, released 2026-04-21). Use ChatGPT (Plus/Team), the API
  (`v1/images/generations`), or fal.ai (`openai/gpt-image-2`).
- Aspect: hero `1024x1024` or `1024x1536`; full-bleed background `1536x1024`.
- Palette to keep consistent with the page: near-black `#08080a`, warm gold
  `#f0d49a → #c7923f`, faint violet ambient. Cinematic, premium, editorial — the
  "exploded luxury watch caliber" energy, but abstract.

---

## 1 — Hero centerpiece (the drill to bedrock)
> A cinematic, ultra-premium 3D render on a near-black background (#08080a). A single
> luminous vertical shaft of warm gold light (#f0d49a to #c7923f) descending through
> layered translucent geological strata, each layer thinner and denser than the one above,
> terminating in a glowing crystalline bedrock core at the bottom. Faint parallel branches
> fan out at each layer then dim, leaving one bright path descending. Volumetric light,
> shallow depth of field, fine film grain, editorial product-photography lighting. No text,
> no UI. Negative space at top. 8k, hyper-detailed.

## 2 — Abstract fan-out / judge (mechanism section)
> Macro 3D render, near-black studio backdrop. Three identical translucent glass nodes
> suspended in a row, soft volumetric haze; the center one ignites with warm gold inner
> light (#f0d49a) while the outer two fade to cool grey, a thin gold filament connecting it
> downward to a node below. Depth-first descent visualized as a chain of light. Cinematic,
> premium, minimal, fine grain, shallow DOF. No text.

## 3 — Full-bleed ambient background (optional, behind hero)
> Extremely dark cinematic gradient field (#08080a) with a faint warm gold glow blooming
> from the top-right and a subtle violet haze lower-left. Suspended fine particles, gentle
> volumetric god-rays descending vertically, like dust in a deep shaft. Abstract, luxurious,
> almost black, very low contrast so white text reads cleanly on top. No subject, no text.

## 4 — Social / Reel cover frame (9:16)
> Vertical 9:16 cinematic poster on near-black. Centered: a single column of gold light
> drilling down through dark translucent layers into a glowing bedrock crystal. Ample empty
> space top and bottom for caption overlays. Premium, editorial, film grain, volumetric
> lighting, warm gold (#c7923f) on black. No text, no logos.

---

### Wiring a render into the page
1. Save as e.g. `site/assets/hero.png`.
2. In `index.html`, inside `.stage`, set a background or place an `<img>` *behind* the
   `<svg>` drill (keep the animated drill on top, or fade it out). For a full-bleed look,
   add the render as a fixed background layer with the existing `body::before` glow over it.
3. Keep file size reasonable (<500KB) — export at 1x for web, the page is dark so JPEG/WebP
   at q80 is plenty.
