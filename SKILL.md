---
name: fix-my-show
description: Use when media libraries have wrong, missing, mixed-language, mismatched, partially refreshed, or scraper-conflicted metadata; or when NFO titles/summaries need translation to Chinese or bilingual rewriting from Japanese; or when file structure needs auditing against TVDB/TMDB — episodes out of order, Specials misnumbered, files not recognized by scrapers, BD rips unsorted, aired vs DVD order confusion. Covers Plex, tinyMediaManager, Kodi, Jellyfin, Emby, NFO sidecars, anime, TV episodes, movies, seasons, translate/bilingual NFO, and human-reviewed scraping corrections.
---

# fix-my-show

## What This Skill Is

一个 **Agent 驱动的半自动刮削器**，涵盖两大工作流：

**工作流 1：结构审计与重组** — 本地文件 vs TVDB/TMDB 对账，找出缺失/多余/错位/未识别的文件，出修复方案。

**工作流 2：元数据修复与翻译** — 替换已有 NFO 中错误/空白的标题和简介，翻译为目标语言，Plex API / NFO 双通道交付。

**不是**：通用文件管理器；批量重命名工具；TMM/Plex 替代品（是和它们协作的修复工具）。

**不适用**：从头搭建新库（TMM/Plex 内置刮削器更合适）；纯文件批量重命名（用 SubRenamer/Advanced Renamer）；网络翻墙/VPN 问题导致刮削失败的。

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
| M1 | 结构审计必须对比至少两个在线源（TVDB + TMDB）后才能下判断 |
| M2 | 每条映射记录 `match_method` 和 `match_score`，不能事后编造 |
| M3 | `needs_review=true` 的行数 > 0 时必须生成 HTML 审核页 |
| M4 | 写 NFO 前先备份已有 .nfo（排除之前的备份目录） |
| M5 | 写 NFO 后 XML 解析验证并统计根标签数 |
| M6 | 修正数据必须持久化到文件（CSV/JSON/替换表），确保可重跑 |

### Agent 行为约束

| # | 规则 |
|---|---|
| C0 | **用户指令不明确时必须询问，不自行假设。** 覆盖范围包括但不限于：选择工作流 A 还是 B（用户只给路径时必问）、目标语言、译名偏好、NFO 写入模式（编辑/生成）、Plex 交付方式（NFO/API）、源优先级。不可替用户做决定。 |
| C1 | 匹配搜索范围不超过预期位置 ±3 集 |
| C2 | 批量偏离预期时回退到步 2 重新判断结构，不硬推 |
| C3 | 不确定的匹配宁可标记 `needs_review` 也不强行写入 |
| C4 | 源标题与生成标题分别记录，不覆盖原始数据 |
| C5 | 翻译后全文扫描替换表，确认无残留罗马字名 |
| C6 | 编辑已有 NFO 时只改内容字段（title/plot/outline），不删除、不重写 `<uniqueid>` `<thumb>` `<actor>` `<fileinfo>` |

## Workflow A：结构审计与重组

当用户说"看看库全不全"、"TVDB 还是 TMDB 排序"、"有些文件没扫进去"时触发此工作流。

### A0. 验证刮削器季结构（结构重组前必做）

**在创建/重命名任何季目录之前**，必须验证目标刮削器实际存在的季结构：

1. 搜索 TVDB/TMDB 的剧集页面，**确认每个 Season 是否真实存在**（不是所有源都按官方分季）
2. 输出 `tvdb_has_season_2: true/false`、`tmdb_has_season_2: true/false`
3. **TVDB/TMDB 的 anime split-cour 合并策略**：连续编号的 anime 经常被 TVDB/TMDB 合并为单季（所有集在 S01 下），即使官方分为 S01/S02。这是已知策略，不是数据错误
4. 如果目标刮削器只有单季 → 本地文件也必须按绝对编号（S01E01–E24），不创建 S02 目录
5. 如果源之间存在分歧 → 出对比表让用户选择用哪个源

### A1. 扫描全量文件

递归列出所有视频文件（.mp4/.mkv/.avi 等），从文件名解析 S/E 编号。同时列出已有 NFO、字幕文件、BD 原盘目录等。可用 `scripts/scan.ps1 -RootPath ... -OutputPath scan.json` 自动扫描输出结构化 JSON。

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
| 目录名异常 | Specials 目录名含误导性标签；父目录名含误导性季号/年份（如 `ShowName.S01.2024...` 中的 `S01` 会让 Plex 误判） |

输出 **缺口报告**：缺失集、多余文件、需修复项，逐条标注原因和建议操作。可结合 `scripts/reconcile.ps1` 输入 scan.json + 源 CSV 自动生成缺口 JSON。

### A4. 出修复方案，用户审批后执行

输出一个表格：

| 文件 | 问题 | 建议操作 | 审批 |
|------|------|---------|------|
| `S03/第07話...mp4.mp` | 扩展名截断 | 重命名为 `S03E07.mp4` | ⬜ |

用户审批后，将上表转为 CSV（列：`old_path,new_path,action`），用 `scripts/apply-fix.ps1 -PlanPath fix.csv -RootPath ...` 执行。脚本自动校验、备份日志、执行、验证。支持 `-DryRun` 预览和 `-RollbackLogPath` 回滚。

修复后建议用户跑 tmm 重扫。

---

## Workflow B：元数据修复与翻译

当用户说"NFO 是英文的改成中文"、"简介缺失"、"标题不对"时触发此工作流。

### B1. 扫描目录结构（同 A1）

遍历目标文件夹，列出所有媒体文件（按季/集分组）、已有 .nfo、字幕文件。从实际文件名推断解析规则（不是从在线数据库反推）。输出文件清单 + 解析出的季/集映射。（同 A1，可用 `scripts/scan.ps1`）

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
- **HTML 审核页**：`needs_review=true` 时必生成。提供搜索/筛选、本地 vs 源对比、修正字段可记录、导出 CSV/JSON。行 ID 使用 `season+episode+local_path`。可用 `scripts/review-html.ps1 -MappingCsv preprocess.csv -OutputPath review.html` 生成。

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

**脚本化**：`scripts/write-nfo.ps1` 覆盖模式 A 和 B。模式 A：`-Mode edit -MappingCsv mapping.csv`。模式 B：`-Mode generate -MappingCsv mapping.csv -ShowTitle "..." -TvdbId "..."`。自动备份、XML 验证、UTF-8 无 BOM。

### B8. 验证

- 逐个 XML 解析，统计 `<tvshow>` / `<episodedetails>` / `<season>` 数量
- 确认媒体文件数量未变
- 抽查指定集数和已知问题集
- 对比文件头和时间戳判断最后改写工具

可用 `scripts/verify.ps1 -RootPath ... -ScanJson scan.json -Strict` 自动验证。

### B9. 交付

#### TMM

数据源设为父级文件夹。如不摄入：从 TMM 库移除 → 重新扫描。

#### Plex 方式 A：NFO 代理（PMS ≥ 1.43.1）

使用 "Plex NFO Series" 代理（原生 NFO 支持）。不重复点刷新。

#### Plex 方式 B：API 直接写入（推荐，不依赖 NFO 代理）

适用场景：Plex 已从 TVDB/TMDB 在线刮好结构、只需改内容语言时。避免切代理导致的结构丢失。

**核心**：获取 Token → 定位 Show/Season/Episode 的 `ratingKey` → `PUT /library/metadata/{ratingKey}?title.value=...&title.locked=1&summary.value=...&summary.locked=1`。

**必须**：带 `locked=1`（否则刷新后被在线源覆盖），URL 编码用 `[Uri]::EscapeDataString()`。

完整脚本模板和端点参考：`references/plex-api.md`。

## Content Source Policy

每个字段按优先级取源，高优先级可用则不用低优先级。

| 字段 | 优先级（高 → 低） |
|---|---|
| 结构/顺序 | 本地文件 → 用户已审批映射 → 持久化覆盖表 → 在线源顺序 |
| 剧名 | 用户偏好 → 本地/TMM 已有标题 → 官方中文源标题 → 翻译源标题 |
| 集标题 | 用户修正 → 官方中文集标题 → 源标题翻译归一化 → 文件名推断兜底 |
| 简介 | 用户修正 → 中文源简介 → 日语简介（BD 官方数据）→ 英文源简介翻译归一化 → `本集包含...` 兜底 |
| ID/日期 | TMM/Plex 可读的稳定 ID（选定源） → 确实未知才留空 |

**第一源语言原则**：
- **翻译必须从作品的创作语言出发。** 动画/日剧的翻译源必须是日语原文，电影的翻译源必须是原始对白语言。不允许从英文等中间翻译再转译。
- 如果 TVDB/TMDB 只拉了英文简介、没有日语原文，必须要求用户先用 tmm 切换日语刮削器重拉（日语 TVDB/TMDB 数据通常有原文或准原文），或者从文件名中的日语标题推断。
- 英文简介仅作为理解剧情的辅助参考，不得作为翻译源文本。

**混合源规则**：
- 不静默混用不兼容的源结构。拆分/合并时在映射中记录合并方式，标题/简介据此组合。
- **标题可以来自维基/moegirl 等中文百科，简介可以来自日语 NFO（BD 官方）——允许标题和简介来自不同语言源，关键是用步 B5 术语表保证一致性。**
- 日语源简介通常比英文源更准确（动画 BD 官方数据），优先于英文源。

**术语一致性**：
- 翻译前必建术语表（步 B5），逐字段翻译时对照术语表。
- 术语表包含：角色名（日/中/罗马字）、季标题、地名、口头禅。
- C5：翻译后全文扫描替换表，确认无残留罗马字名。

## Red Flags — STOP 并回到检查点

执行过程中出现以下信号时，暂停当前操作、回退：

| 信号 | 含义 | 回退到 |
|------|------|--------|
| 源显示有 S02，但重组后 Plex 刮不到 | TVDB/TMDB 可能合并了 split-cour | 步 A0 |
| 用户只给了路径没说要做什么 | 工作流未确定 | 询问 C0 |
| 大部分集的 `match_method` 不是 `order_assumed` | 结构判断可能错误 | 步 B2 |
| 翻译完后发现同一角色有多个中文名 | 术语表未建或未遵守 | 步 B5 |
| NFO 写完后 Plex 刷新变回英文 | 未加 `locked=1` | `references/plex-api.md` |
| "这个看起来明显是对的" | 跳过审核的前兆 | 步 B4 生成 HTML |
| "我先改这几个，其他的之后再说" | 违反 H4（临时修正未持久化） | 步 B4 写入 CSV |

## Common Mistakes

| 错误 | 后果 | 正确做法 |
|------|------|---------|
| 不建术语表直接翻译 | 同一角色在 S01 和 S03 名字不同 | 步 B5 先建表，用户确认后再翻 |
| Plex API 写入不加 `locked=1` | 刷新元数据后被在线源覆盖 | PUT 时必须带 `title.locked=1&summary.locked=1` |
| NFO 编辑时重新生成整个文件 | `<uniqueid>` `<actor>` 等结构数据丢失 | 模式 A 只替换 title/plot 节点 |
| 集数对不上就硬推在线源顺序 | 本地 Specials 可能被错误重新编号 | 出缺口报告让用户决定，不自行修改 |
| 中文简介为空就保留日文不翻译 | 用户看到中英日三语混杂 | 日语简介翻译为中文，术语表保一致性 |
| 用英文简介做翻译源 | 二次翻译失真：「日语→英文→中文」比「日语→中文」多一层信息损失 | 必须用创作第一语言做翻译源（动画=日语），英文仅作辅助理解 |
| PowerShell 中文引号 `""` 放在双引号字符串中 | 语法错误 | 写脚本文件用 `@''@` here-string |
| 不验证刮削器季结构就创建 S02 目录 | Plex 刮不到元数据（TVDB/TMDB 可能把 split-cour 合并在 S01） | 步 A0 先输出 `tvdb_has_season_2: true/false` 再决定结构 |

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

## Scripts（自动化执行）

每个脚本均有 `--help` 级参数文档（`Get-Help .\script.ps1`），SKILL.md 只写触发时机和一行调用。详细用法见脚本文件头注释。

| 脚本 | 覆盖 | 触发时机 | 一行调用 |
|------|------|---------|---------|
| `scripts/scan.ps1` | A1, B1 | 任何工作流第一步 | `.\scan.ps1 -RootPath "..." -OutputPath scan.json` |
| `scripts/reconcile.ps1` | A3 | scan.json 就绪 + 拉取到源 CSV 后 | `.\reconcile.ps1 -ScanJson scan.json -SourceCsv tvdb_s01.csv -SourceName TVDB` |
| `scripts/apply-fix.ps1` | A4 | 用户审批修复表格后 | `.\apply-fix.ps1 -PlanPath fix.csv -RootPath "..."` （先 `-DryRun` 预览） |
| `scripts/review-html.ps1` | B4 | B3 映射 CSV 就绪后 | `.\review-html.ps1 -MappingCsv preprocess.csv -OutputPath review.html` |
| `scripts/write-nfo.ps1` | B7 | B6 元数据生成完毕 | `.\write-nfo.ps1 -Mode edit\|generate -MappingCsv final.csv -RootPath "..."` |
| `scripts/verify.ps1` | B8 | NFO 写入后 | `.\verify.ps1 -RootPath "..." -ScanJson scan.json -Strict` |
