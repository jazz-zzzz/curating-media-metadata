# Example: TV Show with Merged Stories

场景：动画/电视剧，本地文件按 aired order 分组，但在线源按内嵌故事拆分。一个本地文件包含两个源故事。

## 步 1: 扫描目录

```
<ShowName>/
  tvshow.nfo
  Season 1/
    <ShowName> - 1x07 - Story A & Story B.mkv
    <ShowName> - 1x07 - Story A & Story B.nfo       ← 已有但可能不完整
    <ShowName> - 1x18 - Story C & Story D.mkv
    ...
  Season 2/
    ...
```

解析规则：文件名格式 `<ShowName> - <S>x<EE> - <title1> & <title2>.mkv` → `{season: S, episode: EE, episodes_in_file: 2}`

## 步 2: 确定结构

- 本地 S01 有 54 个 mkv 文件
- TheTVDB aired order: S01 有 54 集 — 但有些集号对应两个短故事
- TMDB: S01 有 108 集 — 每个故事单独编号
- 判断：本地文件对应 TheTVDB Aired Order。TheTVDB 将两个短故事合并为一个播出集号。TMDB 将每个故事独立编号。

## 步 3: 构建映射

Ep 7 示例：

| 字段 | 值 |
|---|---|
| `local_season` | 1 |
| `local_episode` | 7 |
| `expected_source_item` | TheTVDB S01E07 |
| `matched_source_item` | TheTVDB S01E07 |
| `match_score` | 1.0 |
| `match_method` | `order_assumed` |
| `source_title` | Story A / Story B |
| `generated_title` | 故事甲 / 故事乙 |
| `generated_summary` | A 段：中文故事甲简介。B 段：中文故事乙简介。 |
| `needs_review` | true（合并集） |

## 步 4: 审核产物

生成 `showname_preprocess.csv` + `showname_review.html`。审核页显示合并标记。

## 步 5: 生成元数据

合并集标题格式：`故事甲 / 故事乙`。简介格式：`A 段：... B 段：...`。替换表确保人物名一致。

## 步 6: 写入 NFO

单 `<episodedetails>` 根，`<title>故事甲 / 故事乙</title>`，`<plot>` 包含分段。格式参考 `references/nfo-spec.md` 第 4 节。

## 步 7/8: 验证 + 交付

验证合并集 NFO 可被 XML 解析。TMM 扫描父文件夹。Plex "Plex NFO Series" agent。
