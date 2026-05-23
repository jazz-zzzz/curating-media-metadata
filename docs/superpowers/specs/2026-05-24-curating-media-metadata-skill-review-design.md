# Curating Media Metadata Skill — Review & Redesign

Date: 2026-05-24

## Problem Statement

当前 SKILL.md 是从一次成功的元数据修正会话中总结而成，存在三个问题：

1. **Skill 定位模糊**：没有回答 "本 skill 是什么"，description 只列了场景但未定义本体
2. **上下文可能丢失**：从会话提炼为指令文档时，Agent 执行所需的约束可能在概括中淡化
3. **硬编码特定场景**：福星小子示例混入通用指令，结构化的特定数据不应出现在 skill 主体中

## Design

### 1. Skill 定位重定义

**本体**：Agent 驱动的半自动刮削器。常规刮削器（TMM/Plex 自带）搞不定的疑难杂症媒体目录，由 Agent 理解结构 → 生成候选 → 人审核 → 写出标准 NFO。

**前置条件**：
- 媒体文件已存在且结构已知
- 文件命名遵循可解析模式
- 用户有可信的在线元数据源
- 不得用于纯咨询问题（"某剧有多少集"）

**边界**：不是刮削器替代品，是补充。重点在纠错和审计，不在首次刮削。

### 2. 硬规则集中定义

所有硬规则集中在工作流之前，分类为三类：

**绝对禁止**：
- H1: 不重命名/移动/删除媒体文件和字幕文件
- H2: 不在审核关卡通过前写最终 NFO
- H3: 不把在线源顺序当作权威改写本地分组
- H4: 不基于聊天中临时修正写 NFO（修正必须持久化）

**强制行为**：
- M1: 步 2 必须对比至少两个在线源后才能下结构判断
- M2: 每条映射必须记录 match_method 和 match_score
- M3: needs_review=true 的行数 > 0 时必须生成 HTML 审核页
- M4: 写 NFO 前必须先备份已有 .nfo（排除之前的备份目录）
- M5: 写 NFO 后必须 XML 解析验证并统计根标签数
- M6: 修正数据必须持久化到文件（CSV/JSON/替换表）

**Agent 行为约束**：
- C1: 匹配搜索范围不超过预期位置 ±3 集
- C2: 批量偏离预期时回退到步 2 重新判断结构
- C3: 不确定的匹配宁可标记审核也不强行写入
- C4: 源标题与生成标题分别记录，不可覆盖原始数据
- C5: 翻译后全文扫描替换表，确认无残留罗马字名

### 3. 工作流精炼（8 步）

步 1 — 扫描目录结构：从文件名推断解析规则，不是从在线源反推。

步 2 — 确定元数据结构（Agent 密集）：列出本地结构特征，对比至少两个在线源（ aired/DVD/absolute/特别篇），逐季验证集数匹配，做出判断并标注依据。判断不了则标记 structure_uncertain。

步 3 — 构建候选映射（Agent 密集）：逐文件匹配，默认本地顺序 = 源顺序。需要 review 的条件：match_score<0.7、match_method!=order_assumed、源缺标题/简介、拆分/合并、语言不一致。匹配范围 ±3 集。

步 4 — 生成审核产物：CSV 为数据源，HTML 审核页在 needs_review=true 时必生成。

步 5 — Agent 生成元数据：按来源策略填充，归一化人名。

步 6 — 写入 NFO：备份 → 写入 → 保留 fileinfo。

步 7 — 验证：XML 解析、计数、抽查、时间戳比对。

步 8 — 交付 TMM/Plex。

### 4. 内容来源策略（保留，精简）

每个字段有明确优先级排序，高优先级可用时不用低优先级。混合源规则：不静默混用不兼容的源结构；拆分/合并时在映射中记录合并方式。

### 5. 文档结构重组

```
SKILL.md                          ← AI 执行指令（~80 行，精简）
references/
  nfo-spec.md                     ← XML 模板、字段表、兼容性备忘
  verification.md                 ← 验证命令、TMM/Plex 排错
  source-matching.md              ← 匹配算法、match_method 定义、多源对比
  user-correction-format.md       ← CSV/JSON 覆盖表格式、审核页导出格式
examples/
  tv-merged-stories.md            ← 动画/电视剧合并故事全流程示例（通用占位符）
  movie-collection.md             ← 电影系列全流程示例（通用占位符）
```

### 6. 去硬编码

`nfo-practices.md` 中的真实剧集数据（S01E18 标题、福星小子特定示例）替换为通用占位符。examples 目录下的示例同样使用 `<剧集名>` 等占位符。

## Implementation Plan (Sketch)

1. 重写 SKILL.md：按新结构重组，硬规则集中，工作流精炼
2. 拆分 references/：从 nfo-practices.md 和 SKILL.md 提取内容到四个 reference 文件
3. 创建 examples/：撰写两个通用化示例（占位符，非真实数据）
4. 自检：确认无硬编码真实数据、无内部矛盾、规则编号正确
5. 提交 + 推送
