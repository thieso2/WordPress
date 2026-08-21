---
name: reversa-image-prompt-json
description: Creates structured JSON prompts for image generation with a luxurious, cinematic aesthetic (product, food, cosmetic, jewelry, fashion photography).
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  team: shared-skills
  role: image-prompt-builder
---

# Image Prompt Builder

A skill for building structured JSON prompts for generating product images with a
cinematic, luxurious aesthetic — optimized for **Nano Banana 2 (Gemini 3.1 Flash Image)**
via **Google Antigravity**, supporting every native parameter of the model.

---

## Mandatory flow

When activated, this skill must **ALWAYS** follow these steps in order:

1. **A guided interview** — collect information from the user in blocks
2. **Confirmation** — show a summary and ask for approval
3. **Generating the JSON** — assemble the final structured prompt

---

## STEP 1 — A guided interview in blocks

Collect the information in **3 rounds of questions**, never all at once.

---

### Round 1 — The product and the scene

Ask the user:

> "Let's build your image prompt! I need to understand the product first. Tell me:"

1. **Product type**: what is the product? (e.g. a chocolate cake, a perfume bottle, a sneaker, a shake, a piece of jewelry...)
2. **Brand name**: is there visible branding? If so, what is the name?
3. **The product's appearance**: describe the color, texture, finish and shape. The more detail, the better.
4. **Extra elements**: are there any accompaniments? (fruit, ice, flowers, leaves, reflections...)
5. **Scene type**: what is the image's overall mood?
   - Suggested options: luxurious and cinematic / clean and minimalist / dramatic and high-contrast / warm and cozy / futuristic and technological

---

### Round 2 — Composition and action

> "Great! Now tell me about the image's dynamic look:"

6. **The main action**: is the product static or in motion? (e.g. liquid exploding, particles suspended, smoke, a splash, a cut revealing the inside...)
7. **Elements suspended in the air**: which elements fly around the product? (e.g. droplets, powder, fragments, leaves, crystals, bubbles...)
8. **The supporting surface**: where is the product? (e.g. polished white marble, matte black stone, rustic wood, clear glass, an abstract surface...)
9. **The camera angle**: how does the camera shoot the product?
   - Options: low angle (dominance) / eye level / slightly above / extreme macro / a 3/4 angle

---

### Round 3 — Lighting, colors and technical specs

> "Almost there! Now the visual and technical part:"

10. **Lighting style**: how do you want the light?
    - Options: clean bright studio / dramatic with shadows / soft natural light / luxury product light with a rim light / colored neon light

11. **The background's color palette**: which color/gradient dominates the background? (e.g. charcoal black with amber bokeh, a pink-to-champagne gradient, dark blue to white...)

12. **Accent colors**: which colors appear in the surrounding elements? (e.g. gold, silver, vivid red, pastel tones...)

13. **Resolution**: what quality level do you need?
    - `512px` — quick iteration / tests
    - `1K` — social media and digital use
    - `2K` — professional content
    - `4K` — maximum production / print

14. **Aspect ratio**: what proportion should the image have? (default: `16:9`)
    - `16:9` — widescreen (the default) ✅
    - `1:1` — square (the Instagram feed)
    - `9:16` — vertical (Stories, Reels, TikTok)
    - `4:3` — classic
    - `3:4` — portrait
    - `4:1` / `1:4` — a horizontal / vertical banner
    - `8:1` / `1:8` — a super banner

15. **Rendering style**: ultra-detailed photorealistic / illustration / 3D render / analog photo / something else?

16. **Anything else?**: any special detail you want guaranteed in the image?

---

## STEP 2 — Confirmation

Once you have collected every answer, show a **summary in bullet points** for the user to confirm:

📋 PROMPT SUMMARY:
- Product: [type] — [brand]
- Scene: [type]
- Appearance: [description]
- Suspended elements: [list]
- Action: [description]
- Suspended elements: [list]
- Surface: [description]
- Angle: [angle]
- Lighting: [style]
- Background: [colors]
- Accents: [colors]
- Resolution: [e.g. 2K]
- Aspect ratio: [e.g. 1:1]
- Rendering: [e.g. ultra-photorealistic]

Is that right? Shall I build the JSON prompt now?
```

Only move on to Step 3 after the user confirms.

---

## STEP 3 — Generating the JSON

With the answers confirmed, build the prompt following **exactly** this schema:

```json
{
    "scene_type": "[speed/style] [niche] photography",
    "scene_type": "[velocidade/estilo] [nicho] photography",
    "product": {
      "type": "[a rich, adjective-laden description of the product]",
      "brand_name": "[the brand's name, or 'no visible branding']",
      "appearance": "[detailed color, texture, shape and finish]",
      "accompaniments": [
        "[element 1 with a sensory description]",
        "[element 2 with a sensory description]"
      ]
    },
    "composition": {
      "action": "[the central dramatic action, captured in motion]",
      "surrounding_elements": [
        "[suspended element 1 with a motion detail]",
        "[suspended element 2 with a motion detail]",
        "[suspended element 3 with a motion detail]"
      ],
      "placement": "[a centered hero placement on the specified surface]"
    },
    "lighting": {
      "style": "[the complete lighting style]",
      "effects": [
        "[a rim light effect]",
        "[a key light effect]",
        "[a backlight or top light effect]",
        "[an extra effect if needed]"
      ]
    },
    "color_palette": {
      "background": "[the background's gradient/bokeh, describing the transition]",
      "accents": "[a comma-separated list of accent colors]"
    },
    "technical_specs": {
      "camera": "[lens type], [the chosen angle]",
      "shutter": "[capture type — freeze-motion, long exposure, etc.]",
      "depth_of_field": "[the main focus], [a description of the blur]",
      "rendering_style": "[photorealistic / illustration / 3D render / analog photo / etc.]"
    },
    "output_specs": {
      "resolution": "[512px | 1K | 2K | 4K]",
      "aspect_ratio": "16:9",
      "model": "nano-banana-2",
      "synthid_watermark": true
    }
  }
}
```

---

## JSON quality rules

- **Luxury and premium adjectives** are mandatory in every descriptive field
- **Frozen motion** must always be present in `action` and `surrounding_elements`
- **Reflective surfaces** must be mentioned in `placement`
- The product is always the scene's **centered hero**
- `surrounding_elements` must have **at least 3 and at most 6 items**
- `lighting.effects` must **always have 3 or 4 effects** (rim, key, back/top + an optional extra)
- `scene_type` must follow the pattern: `"[speed/style adjective] [niche] photography"`
- `output_specs.resolution` must use Nano Banana 2's native values: `512px`, `1K`, `2K` or `4K`
- `output_specs.aspect_ratio` must use the values the model natively supports
- `output_specs.model` must always be `"nano-banana-2"`
- `output_specs.synthid_watermark` must always be `true` (Google's mandatory default)

---

## After generating the JSON

Present the formatted JSON in a code block and add:

> 💡 **Usage tip for Antigravity:** paste this JSON straight into Nano Banana 2's prompt field in Google Antigravity. The `output_specs` fields are interpreted natively by the model — no additional prefix is needed.

Ask whether the user wants to adjust a field, change the aspect ratio, or generate variations.

---

## Reference examples

For inspiration on the language patterns, consult `/mnt/skills/user/image-prompt-builder/references/examples.md` if it is available.
