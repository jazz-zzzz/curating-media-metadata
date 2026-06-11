# fix-my-show

Plex/tMM/Kodi/Jellyfin 媒体库修整技能——Agent 驱动的半自动刮削器。

## 两大工作流

### A. 结构审计与重组

本地文件 vs TVDB/TMDB 全量对账：
- 找出缺失/多余/错位的集数
- 识别 tMM 漏扫的文件（扩展名截断、非标准命名、路径过长）
- 确认 Specials/OVA 的 TVDB vs TMDB 编号是否匹配
- 出缺口报告，用户审批后执行修复

### B. 元数据修复与翻译

替换已有 NFO 中错误/空白的内容：
- 标题和简介翻译为中文（日语 BD 官方数据优先于英文源）
- 翻译前先建术语表确保人地名一致
- 支持编辑已有 NFO（保留 ID/thumb/actor）或全新生成
- 支持 Plex API 直接写入 + 字段锁定（防止刷新覆盖）

## 触发场景

```
"看看这个库全不全"          → Workflow A
"TVDB 还是 TMDB 排序"      → Workflow A
"有些文件没扫进去"          → Workflow A
"NFO 是英文的改成中文"      → Workflow B
"简介缺失/标题不对"         → Workflow B
```

## 交付方式

| 方式 | 适用 |
|------|------|
| 编辑 NFO 文件 | tMM/Jellyfin/Emby/Kodi |
| Plex API 写入 + lock | Plex（不切代理，不丢结构） |

## 前置条件

媒体文件已存在 + 有可信在线元数据源（TVDB/TMDB/AniDB/wiki）。
不是 TMM/Plex 替代品，是和它们协作的修复工具。

## 安装

```bash
git clone https://github.com/jazz-zzzz/fix-my-show.git
# Codex: 软链/复制到 ~/.agents/skills/fix-my-show
# Claude Code: 软链/复制到 ~/.claude/skills/fix-my-show
```
