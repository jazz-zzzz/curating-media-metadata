# Verification & Troubleshooting

## Validation Commands

### PowerShell: 计数媒体和 NFO（排除归档目录）

```powershell
$root='<show_root_path>'
$mkv=0; $episodeNfo=0; $seasonNfo=0
foreach($s in 1..4){
  $dir=Join-Path $root "Season $s"
  $mkv += (Get-ChildItem -LiteralPath $dir -Filter '*.mkv' -Force | Measure-Object).Count
  $episodeNfo += (Get-ChildItem -LiteralPath $dir -Filter '*.nfo' -Force | Where-Object Name -ne 'season.nfo' | Measure-Object).Count
  $seasonNfo += (Get-ChildItem -LiteralPath $dir -Filter 'season.nfo' -Force | Measure-Object).Count
}
[pscustomobject]@{Mkv=$mkv; EpisodeNfo=$episodeNfo; SeasonNfo=$seasonNfo; TvshowNfo=(Test-Path -LiteralPath (Join-Path $root 'tvshow.nfo'))}
```

### PowerShell: 解析所有 NFO 并统计根标签

```powershell
$root='<show_root_path>'
$bad=@(); $counts=@{}
Get-ChildItem -LiteralPath $root -Recurse -Filter '*.nfo' -Force | Where-Object {
  $_.DirectoryName -notmatch 'archive|backup|\.metadata_archive'
} | ForEach-Object {
  try {
    $xml = [xml](Get-Content -LiteralPath $_.FullName -Encoding UTF8)
    $tag = $xml.DocumentElement.Name
    $counts[$tag] = ($counts[$tag] -or 0) + 1
  } catch {
    $bad += "$($_.Name): $_"
  }
}
Write-Host "Counts: $($counts | ConvertTo-Json)"; Write-Host "Bad: $($bad.Count)"
```

### Python: 解析 NFO 并统计

```python
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(r"<show_root_path>")
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

- TMM 数据源应设为**父级库文件夹**。每个子文件夹被视为一个剧集。
- 如果 NFO 存在但 TMM 忽略剧集级元数据：从 TMM 数据库移除该剧集（不删除文件），然后重新扫描数据源。
- "Rewrite TV show NFO" 和 "Rewrite episode NFO" 是独立操作。用时间戳和文件头确认。
- TMM 可能只重写 `tvshow.nfo` 和 `season.nfo`，不碰 episode NFO（除非选中剧集）。
- 检查 TMM 是否重写了文件：看第 2 行注释 `<!--created on ... by tinyMediaManager ...-->`。

## Plex Practices

- PMS ≥ 1.43.1 内置 "Plex NFO Series" 代理，可直接读取 Kodi-format NFO。创建/编辑库时在 Agent 下拉中选择。
- PMS < 1.43.1 不使用 NFO（旧版 XBMCnfoTVImporter 已废弃），需通过 TMM 中转。
- 不重复点击刷新。用 Plex Web 活动面板取消当前任务，或在队列卡住时重启 PMS。
- 部分刷新原因：锁定字段、过期 agent 缓存、匹配状态冲突、重叠的刷新任务。
- 如需不碰文件就移除剧集：优先用 `.plexignore` 规则或 Plex 数据库操作，而非移动源文件。
