---
name: hallmark-anti-slop-text-and-design
description: "Strictly enforces Hallmark anti-AI-slop design, text, copywriting, and typography rules for all generated content, UI, and text in this workspace."
trigger: always_on
---

# Hallmark Anti-AI-Slop Standard (Mandatory For All Text & UI)

In this project/workspace, all generated text, copy, titles, headings, UI components, documentation, and user interfaces **must strictly and exclusively follow the Hallmark Anti-AI-Slop skill guidelines** (`skills/hallmark`).

---

## 1. Honest Copy & Zero Fabricated Content
- **Never fabricate metrics or claims**: Do not invent fake conversion percentages (`"+47% conversion"`), fake scale (`"trusted by 50,000+ teams"`, `"over 1M users"`), or fictional performance benchmarks (`"10x faster"`).
- **No fake social proof**: Never generate fake testimonials, fake client quotes, or fake partner logos.
- **Handling missing data**: Use honest placeholders (e.g., `—` or `[Metric to confirm]`) or rewrite the copy/macrostructure so it does not rely on unverified claims.

---

## 2. No AI Clichés & Buzzword Slop
- **Strictly ban AI clichés and generic filler**:
  - ❌ *"Seamlessly integrate..."*, *"Supercharge your workflow..."*, *"Unlock the full potential of..."*
  - ❌ *"Game-changing platform..."*, *"Revolutionize the way you..."*, *"In today's fast-paced digital world..."*
  - ❌ *"Elevate your experience..."*, *"Empower your team..."*, *"All-in-one solution..."*
  - ❌ *"Delve into..."*, *"Tailored to your needs..."*, *"A testament to..."*
- **Tone & Style**: Write concrete, concise, direct, human, and domain-precise copy. Say what the software actually does, plainly and accurately.

---

## 3. Typography & Heading Rules
- **No Italic Headers**: Display titles, headings (`h1`–`h6`), and prominent banners must **always be roman (`font-style: normal`)**.
  - ❌ Never use all-italic display headings.
  - ❌ Never use italicized emphasis words inside headings (e.g., `Built to <em>think</em>` or `Ready to <i>scale</i>` is a banned AI tell).
  - ✅ Express emphasis in headings using weight contrast, accent color, or a drawn underline. Reserve italics solely for occasional *body-copy* emphasis within running paragraphs.
- **Punctuation & Typographic Discipline**:
  - Use real typographic smart quotes (`“ ”` and `‘ ’`) in rendered copy.
  - Use real em-dashes `—` (or en-dashes `–`) instead of double hyphens `--`.
  - Use proper ellipsis `…` instead of three dots `...`.
  - **No two-line wrapped clickable text**: CTA buttons, primary nav links, tabs, chips, and badges must fit on a single line (e.g., *"Start free"* instead of *"Get started with your 14-day free trial today"*).

---

## 4. UI & Frontend Anti-Slop Disciplines
- **No AI Default Visuals**:
  - ❌ No purple-to-blue / purple-to-pink gradient background meshes.
  - ❌ No `background-clip: text` gradient headlines.
  - ❌ No generic 3-card grids with an icon inside a rounded colored square + 2 lines of generic copy.
  - ❌ No faked browser/phone/IDE window chrome with decorative colored dots.
- **Locked Design Tokens**: All colors and font families in UI code must reference named tokens (`var(--color-...)`, `var(--font-...)`), never improvising raw inline hex/OKLCH values mid-generation.
- **8-State Interactive Discipline**: Interactive elements must define all required states (`default`, `hover`, `:focus-visible`, `:active`, `disabled`, `loading`, `error`, `success`).

---

## 5. Pre-Emit Self-Critique
Before completing any text, UI component, or page generation, verify the output against the 6 Hallmark axes:
1. **Philosophy**: Distinct aesthetic point of view, not LLM baseline template.
2. **Hierarchy**: Clear visual and typographic rhythm.
3. **Execution**: Clean tokens, responsive, accessible, zero layout overflow.
4. **Specificity**: Authentic copy and concrete facts with zero generic filler.
5. **Restraint**: Purposeful elements; no gratuitous decor or fake chrome.
6. **Variety**: Structural novelty and appropriate macrostructure.
