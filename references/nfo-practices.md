# NFO Practices For Plex/TMM Pipelines

## Content Generation Constraints

Separate the trust ladder for ordering, titles, and summaries:

| Content | Preferred sources |
| --- | --- |
| Order/grouping | Local media structure, approved manual mapping, then online database structure |
| Show title | User preference, existing local/TMM title, official Chinese title, translated remote title |
| Episode title | User correction, official Chinese story/episode title, translated remote title, filename-derived fallback |
| Summary | User correction, Chinese summary source, translated English summary source, neutral fallback |
| Names/terms | User-approved official translations, then source-native names; avoid mixed romanized leftovers |

Good requirements from the Urusei Yatsura workflow:

- Keep local aired-order files authoritative when remote sources split/merge stories differently.
- Combine merged story titles as `故事 A / 故事 B` only when the local file contains both stories.
- Prefer Chinese source titles even if summaries need translation.
- Translate English summaries only after confirming the mapped episode/story is correct.
- Keep user corrections as data, not memory: e.g. `S01E18 = 泪的明日日记 / 这孩子是谁？`.
- Scan generated plots for unwanted romanized names after replacement.

Bad patterns to avoid:

- Taking TMDB/TVDB order as truth when it does not match local files.
- Applying one merge/split rule to every episode.
- Trusting fuzzy title matches outside the local neighborhood without review.
- Rewriting from chat-only corrections that are not stored in CSV/JSON/script overrides.
- Using translated titles when official Chinese titles are available.

## File Placement

- TV show root: `tvshow.nfo`
- Episode sidecars: same basename as the video, e.g. `Show - S01E01 - Title.nfo` beside `Show - S01E01 - Title.mkv`
- Season sidecars: `Season 1/season.nfo`, optional but useful for TMM-managed season metadata
- Do not rename video files to solve metadata unless the user explicitly approves. Many users have subtitle conversion, seeding, or external indexing tied to current names.

## Minimum TV Show NFO

Use root `<tvshow>`. Include at least:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<tvshow>
  <title>中文剧名</title>
  <originaltitle>原名</originaltitle>
  <showtitle>中文剧名</showtitle>
  <year>1981</year>
  <plot>中文简介</plot>
  <runtime>25</runtime>
  <episodeguide>{"tvdb":"75113"}</episodeguide>
  <id>75113</id>
  <uniqueid default="true" type="tvdb">75113</uniqueid>
  <premiered>1981-10-14</premiered>
  <status>Ended</status>
  <genre>动画</genre>
  <studio>Fuji TV</studio>
</tvshow>
```

Avoid empty critical fields such as `<year/>` when TMM fails to recognize the show-level NFO.

What worked well in practice:

- A real `tvshow.nfo` in the show root, not a show-title `.nfo`.
- Non-empty `<year>`, `<title>`, `<showtitle>`, `<plot>`, `<runtime>`, `<id>`, `<uniqueid>`, and `<premiered>` when known.
- TMM data source set to the parent library folder so the show folder is discovered as one show.
- Confirming TMM rewrote `tvshow.nfo` by checking the file header and timestamp.

What caused or suggested trouble:

- Empty critical fields like `<year/>` and `<runtime>0</runtime>` on the show-level NFO.
- Assuming TMM rewrote all NFO files when it only rewrote `tvshow.nfo` and `season.nfo`.
- Mixing old backup/archive `.nfo` files into validation counts.

## Minimum Episode NFO

Use root `<episodedetails>`. Include:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<episodedetails>
  <title>中文集标题</title>
  <showtitle>中文剧名</showtitle>
  <season>1</season>
  <episode>18</episode>
  <plot>中文简介</plot>
</episodedetails>
```

For TMM/Plex friendliness, also keep:

- `<originaltitle/>`
- `<runtime>`
- `<studio>`
- `<dateadded>`
- `<fileinfo>` from previous TMM output if available
- `<original_filename>` under a TMM metadata block if preserving traceability

What worked well in practice:

- Same basename as the media file, preserving the existing video filename.
- XML declaration with UTF-8 and valid `<episodedetails>` root.
- Explicit `<season>` and `<episode>` derived from the structural filename token.
- Preserving TMM-generated `<fileinfo>` blocks when replacing title/plot.
- Revalidating all episode NFO with an XML parser after writing.

What to avoid:

- Renaming media just to satisfy a parser while subtitles or other workflows depend on current names.
- Parsing later title text such as `... & 1x18 - ...` as the real episode number.
- Writing minimal NFO without validating whether TMM/Plex actually ingests it.

## Matching Rules

- Parse season/episode from the intended structural token, usually the first or canonical `S01E01` or `1x01` slot.
- Do not let later title text like `... & 1x18 - Something...` override the structural episode number.
- For merged stories, store titles as `故事 A / 故事 B` and make summaries explicitly segment-aware.
- For split-source conflicts, keep local media grouping as authoritative and map online source items into it.

## Human Review

Flag a row for review when:

- Match score is low.
- Best source item is outside the expected local neighborhood.
- A source has split episodes but the file is merged, or vice versa.
- The summary is missing and requires translation or fallback text.
- User-provided corrections override automatic matching.

Keep corrections in a durable file or script table so reruns do not regress.

Recommended HTML review behavior:

- Provide search/filter controls for `needs_review`, low score, source, season, and title text.
- Render local filename and generated metadata side by side with source metadata.
- Use stable row IDs such as `season`, `episode`, `local_path`, and `source_id`; do not rely on display order alone.
- Export or read corrections as CSV/JSON so final NFO generation is reproducible.
- Keep the original generated value, human correction, and final value distinguishable.
- Treat "no change" as a review decision when the row was flagged uncertain.

## Validation Commands

Useful Windows/Python checks:

```powershell
# Count media and sidecars without entering archive folders
$root='\\Nas\share\Anime\Show'
$mkv=0; $episodeNfo=0; $seasonNfo=0
foreach($s in 1..4){
  $dir=Join-Path $root "Season $s"
  $mkv += (Get-ChildItem -LiteralPath $dir -Filter '*.mkv' -Force | Measure-Object).Count
  $episodeNfo += (Get-ChildItem -LiteralPath $dir -Filter '*.nfo' -Force | Where-Object Name -ne 'season.nfo' | Measure-Object).Count
  $seasonNfo += (Get-ChildItem -LiteralPath $dir -Filter 'season.nfo' -Force | Measure-Object).Count
}
[pscustomobject]@{Mkv=$mkv; EpisodeNfo=$episodeNfo; SeasonNfo=$seasonNfo; TvshowNfo=(Test-Path -LiteralPath (Join-Path $root 'tvshow.nfo'))}
```

```python
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(r"\\Nas\share\Anime\Show")
files = [root / "tvshow.nfo"]
files += list(root.glob("Season */season.nfo"))
files += [p for p in root.glob("Season */*.nfo") if p.name != "season.nfo"]

bad = []
counts = {}
for path in files:
    try:
        tag = ET.parse(path).getroot().tag
        counts[tag] = counts.get(tag, 0) + 1
    except Exception as exc:
        bad.append((str(path), str(exc)))
print(counts, "bad:", len(bad))
```

## TMM Practices

- TMM data source should normally be the parent library folder. Each child folder is one show.
- If NFO files exist but TMM ignores show-level metadata, remove the show from TMM's database without deleting files, then rescan.
- "Rewrite TV show NFO" and "Rewrite episode NFO" may be separate actions. Confirm with timestamps and file headers.
- TMM may rewrite `tvshow.nfo` and `season.nfo` while leaving episode NFO untouched unless episodes are selected.

## Plex Practices

- Plex official behavior depends on the agent. NFO sidecars require an NFO-capable agent/plugin/workflow; a normal refresh may keep remote metadata.
- Avoid repeatedly clicking refresh while a previous job is running. Use Plex Web activity to cancel, or restart Plex Media Server if the queue is stuck.
- Partial refresh can be caused by locked fields, stale matches, agent cache, or overlapping refresh jobs.
- If a show must be forgotten without touching media files, prefer a temporary `.plexignore` rule or Plex database-level operations over moving/renaming active source files.
