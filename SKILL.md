---
name: curating-media-metadata
description: Use when media libraries have wrong, missing, mixed-language, mismatched, partially refreshed, or scraper-conflicted metadata for Plex, tinyMediaManager, Kodi, Jellyfin, Emby, NFO sidecars, anime, TV episodes, movies, seasons, aired order, DVD order, merged stories, or human-reviewed scraping corrections.
---

# Curating Media Metadata

## Overview

Build metadata as an auditable pipeline: discover the local media structure, map it to trustworthy sources, let the agent generate candidates, get human review where uncertain, then write standard sidecars that media tools can ingest.

## Core Rule

Treat filenames and media files as source-of-truth unless the user explicitly authorizes renaming. Never delete, move, or rename video/subtitle files during metadata work. Prefer sidecar outputs: CSV, HTML review pages, cache files, `.nfo`, and backups.

## Quick Reference

| Situation | Action |
| --- | --- |
| Files parse oddly | Inspect filenames and count structure before searching online |
| Source order conflicts with files | Keep local grouping/order authoritative |
| Match is uncertain | Generate CSV/HTML review before writing NFO |
| User corrects rows | Store overrides durably in script/data |
| TMM/Plex ignores NFO | Validate XML, timestamps, agent/cache/locked fields, and rescan strategy |
| Subtitles or seed paths depend on names | Do not rename media |

## Content Source Policy

Make source trust explicit before generating final NFO. Title and summary are separate fields and may use different trust ladders.

| Field | Trust order |
| --- | --- |
| Structural order | Local files, existing user-approved mapping, durable override table, then online source order |
| Show title | User preference, local/TMM existing canonical title, official Chinese title source, then translated source title |
| Episode title | User correction, official Chinese episode/story title, source title translated and normalized, then local filename-derived fallback |
| Summary/plot | User correction, Chinese source summary, English source summary translated and normalized, then neutral `本集包含...` fallback |
| IDs and dates | TMM/Plex-readable stable IDs from selected source, then blank only if unknown and non-critical |

Never silently mix incompatible source structures. If titles come from a split-story source but files are merged, document the merge in the mapping and combine titles/summaries according to local files.

## Responsibility Split

| Owner | Responsibilities |
| --- | --- |
| Fixed scripts | Enumerate files, parse structural episode tokens, count media/NFO, cache source responses, compute match scores, generate CSV/HTML review artifacts, apply approved overrides, write sidecar files, back up existing NFO, validate XML and counts |
| AI agent | Choose candidate sources, reason about source-order conflicts, design matching heuristics for the specific library, generate titles/summaries/translations, normalize names, flag uncertainty, explain TMM/Plex behavior, adapt scripts to the library |
| Human reviewer | Approve ambiguous mappings, correct titles/summaries, decide preferred translation names, authorize final writes, authorize any rename/delete/move if ever needed |

Keep deterministic work in scripts once a pattern appears more than once. Keep judgment-heavy choices in the agent, but make the agent's choices visible in review artifacts.

## HTML Review Gate

The HTML review page is a first-class artifact, not optional decoration. Use it whenever more than a trivial number of rows are generated or when any mapping is uncertain.

The review page should show, at minimum:

- Local path, season/episode, and parsed local title.
- Expected source item and selected source item.
- Match score, match rule, and uncertainty flag.
- Generated title and generated summary.
- Source title/summary snippets for comparison.
- Editable or clearly recordable correction fields, with corrections saved to CSV/JSON/script data before final writing.

Do not write final NFO from memory or chat-only corrections. Convert human decisions into a durable correction file or override table, rerun generation, and archive the reviewed output.

## Workflow

1. **Discover the library shape**
   - List the target folder, season folders, video files, existing `.nfo`, subtitles, and hidden/archive folders.
   - Count files by type and by season. Detect confusing title numbers such as `1x18` inside an episode title.
   - Infer parser rules from actual video names, not from online databases first.

2. **Identify metadata structure**
   - Determine whether files are movie, TV aired order, DVD order, absolute order, specials, split segments, or merged stories.
   - Compare local episode count and grouping with likely sources: TheTVDB, TMDB, AniDB, Fandom/wiki pages, local subtitles, and existing TMM/Plex data.
   - Use the local media structure as the final ordering authority. Online sources are evidence, not the boss.

3. **Build a candidate mapping**
   - Search or scrape source metadata only as needed. Cache raw responses.
   - Match only within a narrow neighborhood around the local expected episode/global index unless the filename strongly proves a swap.
   - Record: local path, season/episode, local title, expected source item, matched source item, match score, source title, generated title, generated summary, and review flag.

4. **Generate an audit artifact**
   - Produce a CSV for data safety and an HTML review page as the default correction interface when there are swaps, low scores, missing summaries, merged/split episodes, or uncertain source conflicts.
   - Do not write final NFO until the user has reviewed uncertain rows or explicitly accepts the proposed mapping.

5. **Agent-assisted metadata generation**
   - Apply the content source policy for every title and summary.
   - Normalize recurring names to the user's preferred official translations. Keep a replacement table and verify no old romanized names remain.

6. **Write standard sidecar files**
   - Back up existing `.nfo` first, excluding previous backup/archive directories from the new backup.
   - Write:
     - `tvshow.nfo` in the show root for TV shows.
     - `<episode filename>.nfo` next to each episode file.
     - Optional `season.nfo` in season folders when TMM/Plex workflows benefit from it.
   - Standardize XML roots and critical fields so scanners can ingest them: `<tvshow>` for show, `<season>` for season, `<episodedetails>` for episodes; non-empty `title`, `year` when known, `season`, `episode`, `plot`, and stable IDs where available.
   - Preserve existing episode `fileinfo` blocks when rewriting NFO so media stream details are not lost.

7. **Validate before claiming success**
   - Parse every written `.nfo` as XML.
   - Count `tvshow`, `season`, and `episodedetails` roots.
   - Verify media file counts did not change.
   - Spot-check user-specified episodes and known problematic swaps.
   - Compare timestamps and file headers to confirm whether TMM, Codex, or another tool last rewrote a file.

8. **Hand off to TMM/Plex safely**
   - In TMM, ensure the data source is the parent library folder, not the show folder itself.
   - If TMM does not ingest updated NFO, remove the show from TMM's database without deleting files, then rescan the data source.
   - In Plex, avoid repeated refresh clicks while a refresh is still running. Stop/cancel current activity or restart Plex Media Server if the queue appears stuck.
   - If Plex partially updates, check locked fields, stale agent cache, matching state, and whether the server is reading the intended NFO agent.

## Output Pattern

For substantial jobs, create these artifacts in the workspace or beside the target media:

- `*_preprocess.csv`: full proposed mapping before final writing.
- `*_review.html`: human-friendly audit page for uncertain rows.
- `*_after_rewrite.csv`: mapping actually used for final NFO.
- `.metadata_archive/` or a project-specific hidden archive folder containing previous NFO and final scripts.

## When To Read More

Read [references/nfo-practices.md](references/nfo-practices.md) when implementing or debugging exact NFO compatibility, TMM/Plex refresh behavior, or validation commands.

## Common Mistakes

- Treating online scraper order as truth when local files are merged/split differently.
- Letting episode-looking text inside a title override the actual structural episode token.
- Writing final NFO before the user reviews low-confidence matches.
- Repeatedly refreshing Plex while previous metadata jobs are still queued.
- Backing up recursively into previous backup folders and multiplying stale NFO.
