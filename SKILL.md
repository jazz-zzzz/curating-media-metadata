---
name: fix-my-show
description: Use when media libraries have wrong, missing, mixed-language, mismatched, partially refreshed, or scraper-conflicted metadata for Plex, tinyMediaManager, Kodi, Jellyfin, Emby, NFO sidecars, anime, TV episodes, movies, seasons, aired order, DVD order, merged stories, or human-reviewed scraping corrections.
---

# Curating Media Metadata

## What This Skill Is

一个 **Agent 驱动的半自动刮削器**，涵盖两大工作流：

**工作流 1：结构审计与重组** — 本地文件 vs TVDB/TMDB 对账，找出缺失/多余/错位/未识别的文件，出修复方案。

**工作流 2：元数据修复与翻译** — 替换已有 NFO 中错误/空白的标题和简介，翻译为目标语言，Plex API / NFO 双通道交付。

**前置条件**：媒体文件已存在；用户有可信的在线元数据源。

**不是**：通用文件管理器；批量重命名工具；TMM/Plex 替代品（是和它们协作的修复工具）。

## Hard Rules

### 绝对禁止

| # | 规则 |
|---|---|
| H1 | 不重命名、不移动、不删除媒体文件和字幕文件，**除非**用户审批了结构修复方案（见工作流 A 步 A4）且操作前备份 |
| H2 | 不在审核关卡通过前写最终 NFO |
| H3 | 不把在线源顺序当作权威来改写本地文件分组——但协助用户发现本地 vs 源的差异，让用户决定是否修正 |
| H4 | 不基于聊天中临时修正写 NFO — 修正必须存入 CSV/JSON/替换表后才可重现 |

### 强制行为

| # | 规则 |
|---|---|
| M1 | 工作流 A 必须对比至少两个在线源（TVDB + TMDB）后才能下结构判断 |
| M2 | 每条映射记录 `match_method` 和 `match_score`，不能事后编造 |
| M3 | `needs_review=true` 的行数 > 0 时必须生成 HTML 审核页 |
| M4 | 写 NFO 前先备份已有 .nfo（排除之前的备份目录） |
| M5 | 写 NFO 后 XML 解析验证并统计根标签数 |
| M6 | 修正数据必须持久化到文件（CSV/JSON/替换表），确保可重跑 |

### Agent 行为约束

| # | 规则 |
|---|---|
| C0 | **用户指令不明确时必须询问，不自行假设。** 覆盖范围包括但不限于：目标语言、译名偏好、NFO 写入模式（编辑/生成）、Plex 交付方式（NFO/API）、源优先级。不可替用户做决定。 |
| C1 | 匹配搜索范围不超过预期位置 ±3 集 |
| C2 | 批量偏离预期时回退到步 2 重新判断结构，不硬推 |
| C3 | 不确定的匹配宁可标记 `needs_review` 也不强行写入 |
| C4 | 源标题与生成标题分别记录，不覆盖原始数据 |
| C5 | 翻译后全文扫描替换表，确认无残留罗马字名 |
| C6 | 编辑已有 NFO 时只改内容字段（title/plot/outline），不删除、不重写 `<uniqueid>` `<thumb>` `<actor>` `<fileinfo>` |

## Workflow A：结构审计与重组

当用户说"看看库全不全"、"TVDB 还是 TMDB 排序"、"有些文件没扫进去"时触发此工作流。

### A1. 扫描全量文件

递归列出所有视频文件（.mp4/.mkv/.avi 等），从文件名解析 S/E 编号。同时列出已有 NFO、字幕文件、BD 原盘目录等。

### A2. 拉取在线源集数列表

搜索 TVDB 和 TMDB 的完整集数表（所有季 + Specials + OVA），对比两者的差异点（Special 编号、拆分/合并、DVD order vs Aired order）。明确输出两者的差异清单。

### A3. 对账：本地 vs 在线源

逐季、逐 Special 对比：

| 检查项 | 说明 |
|--------|------|
| 集数匹配 | 本地每季的 mp4 数量 vs 源预期集数 |
| 编号连续 | 检查 SxxExx 是否有跳号 |
| 未识别文件 | 有视频但无 NFO（tmm 没扫到） |
| 孤立 NFO | 有 NFO 但无对应视频 |
| 命名异常 | 文件扩展名截断、非标准前缀、路径过长 |
| 目录名异常 | Specials 目录名含误导性标签 |

输出 **缺口报告**：缺失集、多余文件、需修复项，逐条标注原因和建议操作。

### A4. 出修复方案，用户审批后执行

输出一个表格：

| 文件 | 问题 | 建议操作 | 审批 |
|------|------|---------|------|
| `S03/第07話...mp4.mp` | 扩展名截断 | 重命名为 `S03E07.mp4` | ⬜ |

用户审批后，执行文件重命名/移动（有 H1 豁免）。修复后建议用户跑 tmm 重扫。

---

## Workflow B：元数据修复与翻译

当用户说"NFO 是英文的改成中文"、"简介缺失"、"标题不对"时触发此工作流。

### B1. 扫描目录结构（同 A1）

遍历目标文件夹，列出所有媒体文件（按季/集分组）、已有 .nfo、字幕文件。从实际文件名推断解析规则（不是从在线数据库反推）。输出文件清单 + 解析出的季/集映射。

### B2. 确定元数据结构（Agent 密集）

1. 列出本地结构特征：总集数、每季集数、命名模式（S01E01 / 1x01 / #001 / EP01）、特殊文件夹（Specials/OVA）。
2. 搜索至少两个在线源（TVDB/TMDB/AniDB/wiki），拉取 aired order、DVD order、absolute order、特别篇列表。
3. 逐季对比集数，判断本地文件对应哪个源的哪个顺序。明确写出判断依据。
4. 不一致时本地文件为最终权威。判断不了则标记 `structure_uncertain`。

需输出：选定的源 + 顺序类型 + 依据 + 不一致清单。

### B3. 构建候选映射（Agent 密集）

以步 B2 确定的源顺序为基准，逐文件匹配。默认本地顺序 = 源顺序。

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

### B4. 生成审核产物

- **CSV**：步 B3 所有映射字段，一行一条。
- **HTML 审核页**：`needs_review=true` 时必生成。提供搜索/筛选、本地 vs 源对比、修正字段可记录、导出 CSV/JSON。行 ID 使用 `season+episode+local_path`。

### B5. 建立术语表（翻译前必做）

生成非源语言元数据前，必须先建术语对照表并经用户确认。涵盖：

1. **角色名**：日语 → 中文标准译名 + 罗马字
2. **季/作品名**：各季标题的中文译名
3. **关键名词**：地名、口头禅、作品中特有的概念
4. **命名冲突**：记录与其他版本/翻译可能冲突的译名选择

输出格式：表格（日语原文 | 中文译名 | 罗马字 | 备注）。用户审核后才进入翻译。参考本文档 [Content Source Policy](#content-source-policy) 中关于术语一致性的规则。

### B6. Agent 生成元数据

按内容来源策略（见下）逐字段填充。使用步 B5 确认的术语表进行翻译，确保人地名全库一致。写入替换表后全文扫描复查。

### B7. 写入 NFO

**两种模式**：

#### 模式 A：编辑已有 NFO（推荐，TMM 已生成时）

TMM/Plex 已生成 NFO 但内容是错误语言的场景。**只替换内容字段**（`<title>`、`<plot>`、`<outline>`），保留 `<uniqueid>`、`<thumb>`、`<actor>`、`<fileinfo>` 等所有结构元数据。

- 遍历已有 .nfo，XML 解析 → 替换目标节点 → 写回
- 不改文件名、不重新生成、不碰 `<fileinfo>`
- PowerShell 注意：使用 `[System.IO.File]::ReadAllText` + `[System.Xml.XmlWriter]` 避免编码丢失

#### 模式 B：全新生成

- 先备份已有 .nfo（排除之前的备份目录）
- 写入 `tvshow.nfo` + 每集 `.nfo` + 可选 `season.nfo`
- NFO 格式参考：`references/nfo-spec.md`

两种模式都必须遵循 M4（备份）、M5（XML 验证）。

### B8. 验证

- 逐个 XML 解析，统计 `<tvshow>` / `<episodedetails>` / `<season>` 数量
- 确认媒体文件数量未变
- 抽查指定集数和已知问题集
- 对比文件头和时间戳判断最后改写工具

### B9. 交付

#### TMM

数据源设为父级文件夹。如不摄入：从 TMM 库移除 → 重新扫描。

#### Plex 方式 A：NFO 代理（PMS ≥ 1.43.1）

使用 "Plex NFO Series" 代理（原生 NFO 支持）。不重复点刷新。

#### Plex 方式 B：API 直接写入（推荐，不依赖 NFO 代理）

适用场景：Plex 已从 TVDB/TMDB 在线刮好结构、只需改内容语言时。避免切代理导致的结构丢失。

**步骤**：

1. **发现 Plex Token**：Windows 注册表 `HKCU\Software\Plex, Inc.\Plex Media Server` → `PlexOnlineToken`
2. **定位 Show Key**：`GET /library/sections/{id}/all` 或 `GET /search?query=xxx` 找到目标剧集的 `ratingKey`
3. **获取剧集列表**：`GET /library/metadata/{showKey}/allLeaves` → 解析 XML 获取每集的 `ratingKey`、`parentIndex`（季）、`index`（集号）
4. **PUT 元数据**：`PUT /library/metadata/{ratingKey}?title.value=XXX&title.locked=1&summary.value=XXX&summary.locked=1`
5. **更新季级**：`GET /library/metadata/{showKey}/children` → 各 Season 的 `ratingKey` → PUT title + summary + lock
6. **更新剧级**：PUT show 的 `ratingKey` 更新 title + summary + lock

**关键要点**：

- `title.locked=1&summary.locked=1` 是必须的——不加锁 Plex 刷新元数据时会从在线源覆盖
- URL 编码用 `[Uri]::EscapeDataString()`
- 请求需要 `X-Plex-Token` 头或 query string 参数
- 写入后用户刷新 Plex 即可看到中文内容，且不会被覆盖
- 参考：`references/plex-api.md`

## Content Source Policy

每个字段按优先级取源，高优先级可用则不用低优先级。

| 字段 | 优先级（高 → 低） |
|---|---|
| 结构/顺序 | 本地文件 → 用户已审批映射 → 持久化覆盖表 → 在线源顺序 |
| 剧名 | 用户偏好 → 本地/TMM 已有标题 → 官方中文源标题 → 翻译源标题 |
| 集标题 | 用户修正 → 官方中文集标题 → 源标题翻译归一化 → 文件名推断兜底 |
| 简介 | 用户修正 → 中文源简介 → 日语简介（BD 官方数据）→ 英文源简介翻译归一化 → `本集包含...` 兜底 |
| ID/日期 | TMM/Plex 可读的稳定 ID（选定源） → 确实未知才留空 |

**混合源规则**：
- 不静默混用不兼容的源结构。拆分/合并时在映射中记录合并方式，标题/简介据此组合。
- **标题可以来自维基/moegirl 等中文百科，简介可以来自日语 NFO（BD 官方）——允许标题和简介来自不同语言源，关键是用步 5 术语表保证一致性。**
- 日语源简介通常比英文源更准确（动画 BD 官方数据），优先于英文源。

**术语一致性**：
- 翻译前必建术语表（步 5），逐字段翻译时对照术语表。
- 术语表包含：角色名（日/中/罗马字）、季标题、地名、口头禅。
- C5：翻译后全文扫描替换表，确认无残留罗马字名。

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
| `references/nfo-spec.md` | 步 B7 写 NFO — XML 模板、字段表、兼容性备忘、`<fileinfo>` 保留 |
| `references/verification.md` | 步 B8/B9 — 验证命令、TMM/Plex 排错 |
| `references/source-matching.md` | 步 B2/B3 — 匹配算法、`match_method` 定义、多源对比 |
| `references/user-correction-format.md` | 步 B4/B5 — CSV 覆盖表格式、JSON 替换表、审核页导出 |
| `references/plex-api.md` | 步 B9 方式 B — Plex Token 获取、端点、field locking、完整脚本模板 |
