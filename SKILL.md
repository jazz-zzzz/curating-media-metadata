---
name: curating-media-metadata
description: Use when media libraries have wrong, missing, mixed-language, mismatched, partially refreshed, or scraper-conflicted metadata for Plex, tinyMediaManager, Kodi, Jellyfin, Emby, NFO sidecars, anime, TV episodes, movies, seasons, aired order, DVD order, merged stories, or human-reviewed scraping corrections.
---

# Curating Media Metadata

## What This Skill Is

一个 **Agent 驱动的半自动刮削器**，专门对付常规刮削器搞不定的疑难杂症媒体目录。

常规刮削器（TMM/Plex 自带）刮烂了 → Agent 理解文件结构 → 生成候选映射 → 人审核拍板 → 写入标准 NFO sidecar。

**前置条件**：媒体文件已存在且结构已知；文件命名遵循可解析模式（不要求完美）；用户有可信的在线元数据源。

**不是**：常规刮削器替代品；媒体重命名/移动工具；通用数据查询工具。

## Hard Rules

### 绝对禁止

| # | 规则 |
|---|---|
| H1 | 不重命名、不移动、不删除媒体文件和字幕文件 |
| H2 | 不在审核关卡通过前写最终 NFO |
| H3 | 不把在线源顺序当作权威来改写本地文件分组 |
| H4 | 不基于聊天中临时修正写 NFO — 修正必须存入 CSV/JSON/替换表后才可重现 |

### 强制行为

| # | 规则 |
|---|---|
| M1 | 步 2 必须对比至少两个在线源后才能下结构判断 |
| M2 | 每条映射记录 `match_method` 和 `match_score`，不能事后编造 |
| M3 | `needs_review=true` 的行数 > 0 时必须生成 HTML 审核页 |
| M4 | 写 NFO 前先备份已有 .nfo（排除之前的备份目录） |
| M5 | 写 NFO 后 XML 解析验证并统计根标签数 |
| M6 | 修正数据必须持久化到文件（CSV/JSON/替换表），确保可重跑 |

### Agent 行为约束

| # | 规则 |
|---|---|
| C1 | 匹配搜索范围不超过预期位置 ±3 集 |
| C2 | 批量偏离预期时回退到步 2 重新判断结构，不硬推 |
| C3 | 不确定的匹配宁可标记 `needs_review` 也不强行写入 |
| C4 | 源标题与生成标题分别记录，不覆盖原始数据 |
| C5 | 翻译后全文扫描替换表，确认无残留罗马字名 |

## Workflow

### 1. 扫描目录结构

遍历目标文件夹，列出所有媒体文件（按季/集分组）、已有 .nfo、字幕文件。从实际文件名推断解析规则（不是从在线数据库反推）。输出文件清单 + 解析出的季/集映射。

### 2. 确定元数据结构（Agent 密集）

1. 列出本地结构特征：总集数、每季集数、命名模式（S01E01 / 1x01 / #001 / EP01）、特殊文件夹（Specials/OVA）。
2. 搜索至少两个在线源（TVDB/TMDB/AniDB/wiki），拉取 aired order、DVD order、absolute order、特别篇列表。
3. 逐季对比集数，判断本地文件对应哪个源的哪个顺序。明确写出判断依据。
4. 不一致时本地文件为最终权威。判断不了则标记 `structure_uncertain`。

需输出：选定的源 + 顺序类型 + 依据 + 不一致清单。

### 3. 构建候选映射（Agent 密集）

以步 2 确定的源顺序为基准，逐文件匹配。默认本地顺序 = 源顺序。

每条映射记录：

| 字段 | 说明 |
|---|---|
| `local_path` | 文件路径 |
| `local_season`, `local_episode` | 从文件名解析 |
| `expected_source_item` | 按顺序假设应匹配的源条目 |
| `matched_source_item` | Agent 实际匹配的源条目 |
| `match_score` | 0-1 |
| `match_method` | `order_assumed` / `title_fuzzy` / `title_exact` / `manual` |
| `source_title` | 源标题原文 |
| `source_summary` | 源简介原文 |
| `generated_title` | Agent 生成的中文标题 |
| `generated_summary` | Agent 生成的中文简介 |
| `needs_review` | bool |

`needs_review=true` 触发条件：`match_score<0.7`、`match_method!=order_assumed`、源缺标题/简介、拆分/合并、语言不一致无法自动翻译。

### 4. 生成审核产物

- **CSV**：步 3 所有映射字段，一行一条。
- **HTML 审核页**：`needs_review=true` 时必生成。提供搜索/筛选、本地 vs 源对比、修正字段可记录、导出 CSV/JSON。行 ID 使用 `season+episode+local_path`。

### 5. Agent 生成元数据

按内容来源策略（见下）逐字段填充。归一化人名/术语为用户偏好翻译，写入替换表后全文扫描复查。

### 6. 写入 NFO

- 先备份已有 .nfo（排除之前的备份目录）
- 写入 `tvshow.nfo` + 每集 `.nfo` + 可选 `season.nfo`
- 保留已有 `<fileinfo>` 块
- NFO 格式参考：`references/nfo-spec.md`

### 7. 验证

- 逐个 XML 解析，统计 `<tvshow>` / `<episodedetails>` / `<season>` 数量
- 确认媒体文件数量未变
- 抽查指定集数和已知问题集
- 对比文件头和时间戳判断最后改写工具

### 8. 交付 TMM/Plex

- **TMM**：数据源设为父级文件夹。如不摄入：从 TMM 库移除 → 重新扫描。
- **Plex**：PMS ≥ 1.43.1 使用 "Plex NFO Series" 代理（原生 NFO 支持）。不重复点刷新。检查锁定字段、agent 缓存。

## Content Source Policy

每个字段按优先级取源，高优先级可用则不用低优先级。

| 字段 | 优先级（高 → 低） |
|---|---|
| 结构/顺序 | 本地文件 → 用户已审批映射 → 持久化覆盖表 → 在线源顺序 |
| 剧名 | 用户偏好 → 本地/TMM 已有标题 → 官方中文源标题 → 翻译源标题 |
| 集标题 | 用户修正 → 官方中文集标题 → 源标题翻译归一化 → 文件名推断兜底 |
| 简介 | 用户修正 → 中文源简介 → 英文源简介翻译归一化 → `本集包含...` 兜底 |
| ID/日期 | TMM/Plex 可读的稳定 ID（选定源） → 确实未知才留空 |

**混合源规则**：不静默混用不兼容的源结构。拆分/合并时在映射中记录合并方式，标题/简介据此组合。

## Output Pattern

| 产物 | 说明 |
|---|---|
| `*_preprocess.csv` | 写入 NFO 前的完整候选映射 |
| `*_review.html` | 审核页面（不确定行） |
| `*_after_rewrite.csv` | 最终写入的映射 |
| `.metadata_archive/` | 旧 NFO 备份 + 最终脚本 |

## Reference Files (按需读取)

| 文件 | 何时读 |
|---|---|
| `references/nfo-spec.md` | 步 6 写 NFO — XML 模板、字段表、兼容性备忘、`<fileinfo>` 保留 |
| `references/verification.md` | 步 7/8 — 验证命令、TMM/Plex 排错 |
| `references/source-matching.md` | 步 2/3 — 匹配算法、`match_method` 定义、多源对比 |
| `references/user-correction-format.md` | 步 4/5 — CSV 覆盖表格式、JSON 替换表、审核页导出 |
