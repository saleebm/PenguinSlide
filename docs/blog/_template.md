# Post template

Each post in this series follows the same five-section shape. Keep posts tight — 600 to 1,200 words. Code blocks should be real (copy from the repo, never invent) and short (15-30 lines is the sweet spot; link to the file for the rest).

---

## 1. Hook

One paragraph. A concrete scene from the game or a moment from development. What does the player see? What broke? What surprised us? Earn the reader's attention with specifics, not a thesis statement.

## 2. The decision (or the bug)

What we picked or what surprised us. State the problem in one sentence. State the constraint in one sentence. State the resolution in one sentence. Then expand.

## 3. The code

Pull a short, real excerpt from the repo. Always cite `file_path:line_number`. If the snippet runs over ~30 lines, cut it in half and link to the file. Never invent or paraphrase code.

```swift
// Real code from PenguinSlide/SomeFile.swift:NN
```

## 4. Trade-offs

Three to five bullets. What does this cost? What did we give up? What breaks if you copy this verbatim into a different project?

- Cost: ...
- Cost: ...
- Cost: ...

## 5. Generalization

Two to four sentences. What's the broader pattern? When should a reader reach for this? When should they reach for something else? End with a sentence the reader could remember a week later.

---

## Voice rules

- Specific over abstract. "Two arcs and a V" beats "geometric primitives."
- Past tense for what we did. Present tense for what the code does.
- Numbers when you have them. `2-3 icicles/sec` beats `lots of icicles`.
- No filler openers ("Let's dive in", "Buckle up", "In this post we'll explore").
- No hedging closer ("Hopefully this was useful"). If it was useful, the reader knows.
- Cite repo files inline as `path/to/File.swift:NN`. Link to commits sparingly — the repo history was reset, so only commits after `1c253ac` will resolve.
- One image, max, if at all. Code is the visual.

## Frontmatter (optional)

If publishing through a static site that respects YAML frontmatter:

```yaml
---
title: "Post title"
date: 2026-MM-DD
tags: [spritekit, ios, game-dev]
draft: false
---
```

For raw markdown reading, the H1 at the top of the post is enough.
