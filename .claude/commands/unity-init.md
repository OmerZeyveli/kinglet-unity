---
name: unity-init
description: "Use once per project, right after Kinglet is installed — when `CLAUDE.md` still has unfilled `FILL:` markers, or when the user asks to set up or initialise the toolkit for this Unity project."
user-invocable: true
---

# /unity-init — Project Setup

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

Set up this project's `CLAUDE.md`: refresh the half the toolkit owns by running the generator, and
fill the half the user owns by asking them.

## The marker contract — read this before you touch `CLAUDE.md`

`CLAUDE.md` in a Kinglet project is two halves separated by one marker pair:

```
<!-- kinglet:generated:begin — content between these markers is rewritten on re-install. Everything outside is yours. -->
…the generated block…
<!-- kinglet:generated:end -->
```

- **Inside the markers is the toolkit's.** That region is **regenerated in place**: it is replaced
  wholesale, every time, by the output of `.claude/scripts/generate-claude-md.sh`. A **re-install
  rewrites it** — the Kinglet installer refreshes exactly this region on every run that finds a
  well-formed one — and so does this command. Nothing hand-written inside it survives, so do not put
  anything there, and do not read anything found there as the user's.
- **Outside the markers is the user's.** The vision half above it (`FILL:` markers, pillars, scope)
  and anything they add below it are theirs. The generator never writes outside the region and
  neither do you, except where this command's own steps say so and the user has approved it.
- **A well-formed region is exactly one `begin` line and exactly one `end` line, in `CLAUDE.md`, in
  that order.** Confirm that shape yourself before editing the file — the steps below tell you what
  to do for each of the shapes you can find.

This block is the toolkit's most-cited artifact. Every agent, most commands, and the skills that
decide which of `.claude/rules/` actually binds all read it by name; the live list is what
`/usr/bin/grep -rl 'generated block' .claude/` returns, and it is not a number worth writing down
here. Writing a differently-shaped block by hand is how all of those citations start pointing at
prose that is not there.

## Steps

1. **Run the generator. Do not re-derive the block by hand.**

   From the project root (the directory holding `Assets/`):

   ```bash
   bash .claude/scripts/generate-claude-md.sh --facts-only .
   ```

   This is the **one producer of the region's content**, and it is the same script the installer
   runs — so running it is how this command and the installer stay in agreement instead of drifting.
   It writes the document to **stdout** and its log lines to stderr; the caller owns the destination
   file, so nothing is written until you write it in step 2.

   It already does, from the project's own files, most of what a hand pass would do: Unity version,
   render pipeline, assembly definitions, scenes in build settings, the skills that match this
   project, the *"Architecture stack — detected, not assumed"* verdict, and the packages it knows.
   **Do not reproduce any of that by hand, and do not edit its output.** If a fact looks wrong, that
   is a bug in the generator or in the project's files — report it; do not paper over it.

   **Its package table is a fixed list, and it is not exhaustive.** It does not currently carry
   Timeline, Mirror, Photon, Fish-Net or Odin, among others. If you can see from
   `Packages/manifest.json` that the project uses something the block does not mention, **say so in
   your report to the user** — as a gap in the generator's list, named, so it can be closed. Do not
   silently hand-edit the block to add it: the next refresh deletes the addition and the gap comes
   back unrecorded.

   Two things worth knowing about what comes back:

   - The **render pipeline has four states, not three**: URP, HDRP, Built-in, or *both packages
     present*. `.claude/scripts/detect-pipeline.sh` is the one detector, the generator uses it, and
     it reports that fourth state as its own rather than picking a winner. Report it the same way;
     do not resolve it to one pipeline. Package presence is evidence, not the active pipeline —
     Unity records that in `ProjectSettings/GraphicsSettings.asset`, which nothing in this toolkit
     reads.
   - It needs no MCP bridge; it reads files. Run it even if Unity is closed. If the bridge *is* up,
     the MCP **resource** `mcpforunity://project/info` is a useful cross-check on the Unity version
     — **read it as a resource, at that exact URI.** `project_info` is not a tool: calling it
     answers `Unknown tool: 'project_info'` (measured 2026-08-14 against
     `mcp-for-unity-server 3.4.5`), and the server's instructions state that resource names and URIs
     are not interchangeable. But the generated block is what the rest of the toolkit reads, so the
     generator's answer is the one that ships.

2. **Place the output. Which branch you take depends on what `CLAUDE.md` is right now.**

   - **A well-formed region is present** (the normal case — the installer wrote it): replace exactly
     the lines *between* the two marker lines with the step-1 output. Leave both marker lines
     themselves and every byte outside them untouched. This is the whole edit.
   - **`CLAUDE.md` does not exist at all** (a hand-copied `.claude/`, which never produces one): run
     the generator **without** `--facts-only` and write its stdout to `CLAUDE.md`. That form emits
     the vision half, both markers and the region in one document.
     **Check `.claude/scripts/` exists before you try** — a hand-copied `.claude/` has no `scripts/`
     directory either, and that is the same project shape that has no `CLAUDE.md`, so step 1's line
     and this branch's own command both exit 127 with *No such file or directory*. If that directory
     is missing, **stop**: this is the manual-copy path, nothing here can generate anything, and the
     fix is not yours to improvise. Tell the user to re-run the Kinglet installer from the toolkit
     checkout, or to copy the toolkit's repo-root `scripts/` into `.claude/scripts/` themselves —
     the toolkit's Getting Started guide carries that copy loop verbatim, including the one script
     it deliberately leaves out.
   - **`CLAUDE.md` exists but has no markers at all**, or does not have the well-formed shape the
     marker contract above defines: **stop and show the user.** Do not edit the file, do not insert
     markers into prose you did not write, and do not guess where the region was meant to go. Report
     what you found, and offer them the two ways forward: add the marker pair themselves where they
     want the block, or keep their file and let you write the generated document beside it for them
     to merge.

3. **Fill the vision half with the user.** The `FILL:` markers live *outside* the region — elevator
   pitch, core fantasy, unique hook, genre, target platforms, primary input, pillars, scope, MVP
   hypothesis, current milestone. These are the half the generator cannot detect and will never
   overwrite. Ask; do not invent. Leave a marker unfilled rather than filling it with a guess, and
   name the ones still unfilled when you report.

4. **Report** what the generator detected, which branch of step 2 you took, and what you wrote.

## Output

Present the results in a clear summary table showing what was detected and which skills are
recommended — read off the generator's output rather than re-derived. Say plainly which region of
`CLAUDE.md` you rewrote and which you did not.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

Offer `/unity-doctor` to confirm the install, and name the `FILL:` markers still unfilled in `CLAUDE.md`.
