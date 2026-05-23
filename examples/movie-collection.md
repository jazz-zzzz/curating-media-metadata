# Example: Movie Collection

场景：系列电影分散在同一父文件夹下，命名混乱，多个候选源 ID 可能冲突。

## 步 1: 扫描目录

```
<CollectionName>/
  <Movie1> (2020)/
    <Movie1>.mkv
    <Movie1>.nfo                ← 已有但字段不完整
  <Movie2> (2022)/
    <Movie2>.mkv
  <Movie3> (2024)/
    <Movie3> - Director's Cut.mkv
```

## 步 2: 确定结构

- 3 部电影，各在独立子文件夹
- 无季/集概念，每部独立匹配
- 候选源：TMDB（主要）、IMDb（补充 ID）

## 步 3: 构建映射

按电影名 + 年份搜索 TMDB。

| 字段 | Movie 1 | Movie 2 | Movie 3 |
|---|---|---|---|
| `match_method` | `title_exact` | `title_fuzzy` | `title_fuzzy` |
| `match_score` | 1.0 | 0.85 | 0.72 |
| `needs_review` | false | false | true |

Movie 3 因文件名含 "Director's Cut" 导致模糊匹配分数低，标记审核。

## 步 4-8

- 生成电影级 `movie.nfo`（格式与 episode 不同，根标签为 `<movie>`）
- 审核 Movie 3 的源匹配
- 每部电影写入独立的 `.nfo` 文件（与电影文件同 basename）
- 验证：Plex "Plex NFO Movie" agent
