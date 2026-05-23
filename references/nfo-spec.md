# NFO Format Reference

Kodi/XBMC NFO 格式 + TMM 扩展 + Plex (PMS ≥ 1.43.1) 原生 NFO 兼容参考。
PMS ≥ 1.43.1 需在库级别选择 "Plex NFO Series" 代理。

Sources: [Kodi NFO files/TV shows](https://kodi.wiki/view/NFO_files/TV_shows), [Kodi NFO files/Episodes](https://kodi.wiki/view/NFO_files/Episodes), [Plex NFO metadata](https://support.plex.tv/articles/using-nfo-metadata-files-with-plex/)

## Encoding & XML

```
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
```

- 必须是 UTF-8（无 BOM）
- `standalone="yes"` 是 Kodi 解析要求
- TMM 生成时会在第 2 行加 `<!--created on YYYY-MM-DD HH:MM:SS by <tool> for <target>-->` 注释，调试时有用但非必需

---

## 1. tvshow.nfo (剧集级)

根标签：`<tvshow>`

放置位置：剧集根目录（如 `Anime/ShowName/tvshow.nfo`）

### 必填（Kodi 不扫描将拒绝）

| 标签 | 说明 | 示例 |
|---|---|---|
| `<title>` | 显示标题 | `<title>福星小子</title>` |
| `<uniqueid type="" default="true">` | 刮削源 ID，必须有一个 `default="true"` | `<uniqueid type="tvdb" default="true">75113</uniqueid>` |

### ID 区 — 必须完整且一致

```xml
<id>75113</id>                                          <!-- 废弃但 TMM/Plex 仍读 -->
<tmdbid></tmdbid>
<imdbid></imdbid>
<uniqueid type="tvdb" default="true">75113</uniqueid>   <!-- 至少一个，type: tvdb/tmdb/imdb -->
<episodeguide>{"tvdb":"75113"}</episodeguide>            <!-- Kodi v19+ JSON 格式，必填 -->
```

`<episodeguide>` JSON 支持的 key：`tmdb` `tvdb` `imdb` `tvmaze`。ID 均为字符串。

### 推荐字段

| 标签 | 说明 | 示例 |
|---|---|---|
| `<originaltitle>` | 原始语言标题 | `<originaltitle>うる星やつら</originaltitle>` |
| `<showtitle>` | 显示标题（与 title 一致即可） | `<showtitle>福星小子</showtitle>` |
| `<sorttitle>` | 排序用标题（可为空） | `<sorttitle />` |
| `<year>` | 年份（Kodi v20+ 废弃，由 `<premiered>` 推导，但 TMM/Plex 仍读） | `<year>1981</year>` |
| `<premiered>` | 首播日期 YYYY-MM-DD | `<premiered>1981-10-14</premiered>` |
| `<status>` | `Continuing` 或 `Ended` | `<status>Ended</status>` |
| `<plot>` | 剧集简介 | `<plot>中文简介</plot>` |
| `<outline>` | 短简介 | `<outline />` |
| `<tagline>` | 标语 | `<tagline />` |
| `<runtime>` | 单集时长（分钟） | `<runtime>25</runtime>` |
| `<mpaa>` | 分级 | `<mpaa />` |
| `<certification>` | 认证 | `<certification />` |
| `<genre>` | 类型（可多个） | `<genre>动画</genre>` |
| `<studio>` | 制作公司（可多个） | `<studio>Fuji TV</studio>` |
| `<country>` | 国家 | `<country>日本</country>` |
| `<tag>` | 标签（可多个） | `<tag>anime</tag>` |
| `<trailer>` | 预告片 | `<trailer />` |

### 评分

```xml
<ratings>
  <rating name="themoviedb" max="10" default="true">
    <value>7.5</value>
    <votes>42</votes>
  </rating>
</ratings>
<userrating>0</userrating>
```

`name` 取值：`imdb` `themoviedb` `trakt` `tvmaze` `metacritic` `tomatometerallcritics` `tomatometerallaudience`。注意不是 `default`。

### 图片

```xml
<thumb aspect="poster">https://artworks.thetvdb.com/banners/posters/75113-1.jpg</thumb>
<thumb aspect="poster" season="1" type="season">https://image.tmdb.org/t/p/original/xxx.jpg</thumb>
<fanart>
  <thumb>https://artworks.thetvdb.com/banners/fanart/original/75113-1.jpg</thumb>
</fanart>
```

- `<thumb>` 属性：`aspect="poster"` ／ `aspect="banner"` 等
- Season 海报：加 `season="N"` `type="season"`
- 不是必填，但没有会导致 Plex/TMM/Kodi 无封面

### 季信息（TMM 扩展）

```xml
<namedseason number="1">第 1 季</namedseason>
<seasonplot number="1">《剧名》第 1 季，按 TheTVDB Aired Order 排列。</seasonplot>
```

### TMM 元数据块（TMM 重写后产出）

```xml
<!--tinyMediaManager meta data-->
<user_note />
<episode_groups>
  <group active="true" id="AIRED" name="" />
  <group id="DISPLAY" name="" />
</episode_groups>
<english_title />
<tmm_locked />
```

此块对 TMM 管理是关键的。`episode_groups` 决定剧集显示顺序。

### 状态字段

```xml
<watched>false</watched>
<playcount />
<dateadded>2026-05-23 23:29:17</dateadded>
```

### 完整 tvshow.nfo 模板

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<tvshow>
  <title>中文剧名</title>
  <originaltitle>原始语言标题</originaltitle>
  <showtitle>中文剧名</showtitle>
  <sorttitle />
  <year>1981</year>
  <ratings />
  <userrating>0</userrating>
  <outline />
  <plot>中文简介</plot>
  <tagline />
  <runtime>25</runtime>
  <thumb aspect="poster">poster-url</thumb>
  <namedseason number="1">第 1 季</namedseason>
  <seasonplot number="1">第 1 季简介</seasonplot>
  <fanart>
    <thumb>fanart-url</thumb>
  </fanart>
  <mpaa />
  <certification />
  <episodeguide>{"tvdb":"75113"}</episodeguide>
  <id>75113</id>
  <imdbid />
  <tmdbid />
  <uniqueid type="tvdb" default="true">75113</uniqueid>
  <premiered>1981-10-14</premiered>
  <status>Ended</status>
  <watched>false</watched>
  <playcount />
  <genre>动画</genre>
  <studio>Fuji TV</studio>
  <country>日本</country>
  <tag>anime</tag>
  <trailer />
  <dateadded>TIMESTAMP</dateadded>
</tvshow>
```

---

## 2. Episode NFO (集级)

根标签：`<episodedetails>`

放置位置：与视频文件同目录、同 basename。如 `Show - S01E01 - Title.nfo` 对应 `Show - S01E01 - Title.mkv`

### 必填（Kodi）

| 标签 | 说明 |
|---|---|
| `<episodedetails>` | 根元素 |
| `<title>` | 集标题（非空） |
| `<uniqueid>` | 至少一个 `default="true"` 的刮削 ID |

### 结构定位

| 标签 | 说明 |
|---|---|
| `<season>` | 季号。Kodi 扫描时从文件名读取，但 TMM 和多集文件需要此字段 |
| `<episode>` | 集号。同上 |
| `<displayseason>` | Specials 用于排序到普通季中（-1 表示不适用） |
| `<displayepisode>` | Specials 用于排序位置（-1 表示不适用） |

### 推荐字段

| 标签 | 说明 |
|---|---|
| `<showtitle>` | 剧名 |
| `<originaltitle>` | 原始标题（可为空） |
| `<plot>` | 简介 |
| `<runtime>` | 时长（分钟） |
| `<aired>` | 播出日期 YYYY-MM-DD |
| `<premiered>` | 首播日期（通常与 aired 相同） |
| `<mpaa>` | 分级 |
| `<studio>` | 制作公司 |
| `<credits>` | 编剧（可多个） |
| `<director>` | 导演（可多个） |
| `<genre>` | 类型（可多个，支持 `clear` 属性) |
| `<ratings>` | 评分块 |
| `<userrating>` | 用户评分 |

### 评分

```xml
<ratings />
<userrating>0</userrating>
```

### `<fileinfo>` — 媒体流信息（TMM/Kodi 产出，不可丢）

```xml
<fileinfo>
  <streamdetails>
    <video>
      <codec>h264</codec>
      <aspect>1.777778</aspect>
      <width>1920</width>
      <height>1080</height>
      <durationinseconds>1500</durationinseconds>
      <stereomode />
    </video>
    <audio>
      <codec>aac</codec>
      <language>jpn</language>
      <channels>2</channels>
    </audio>
    <subtitle>
      <language>chi</language>
    </subtitle>
  </streamdetails>
</fileinfo>
```

**关键规则**：重写 NFO 时必须保留已有 `<fileinfo>` 块。Kodi v18+ 不会覆盖 NFO 中已有的 streamdetails。

### TMM 兼容块

```xml
<!--tinyMediaManager compatible meta data-->
<source>UNKNOWN</source>
<edition>NONE</edition>
<original_filename />
<user_note />
<episode_groups>
  <group episode="7" id="AIRED" name="" season="1" />
  <group episode="-1" id="DISPLAY" name="" season="-1" />
</episode_groups>
```

Plex NFO Series agent 可能忽略此块但 TMM 依赖它来正确管理文件。

### 状态字段

```xml
<watched>false</watched>
<playcount>0</playcount>
<epbookmark />
<code />
<dateadded>2026-05-23 23:29:13</dateadded>
```

### 完整 Episode NFO 模板

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<episodedetails>
  <title>中文集标题</title>
  <originaltitle />
  <showtitle>中文剧名</showtitle>
  <season>1</season>
  <episode>7</episode>
  <id />
  <ratings />
  <userrating>0</userrating>
  <plot>中文简介</plot>
  <runtime>25</runtime>
  <mpaa />
  <premiered />
  <aired />
  <watched>false</watched>
  <playcount>0</playcount>
  <studio>Fuji TV</studio>
  <dateadded>TIMESTAMP</dateadded>
  <epbookmark />
  <code />
  <!--tinyMediaManager compatible meta data-->
  <source>UNKNOWN</source>
  <edition>NONE</edition>
  <original_filename />
  <user_note />
  <episode_groups>
    <group episode="7" id="AIRED" name="" season="1" />
    <group episode="-1" id="DISPLAY" name="" season="-1" />
  </episode_groups>
</episodedetails>
```

---

## 3. Season NFO（TMM 扩展，Kodi 非官方支持）

根标签：`<season>`

放置位置：`Season N/season.nfo`

### 模板

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<season>
  <seasonnumber>1</seasonnumber>
  <title>第 1 季</title>
  <showtitle>中文剧名</showtitle>
  <sorttitle>季 01</sorttitle>
  <year />
  <plot>季简介</plot>
  <thumb aspect="poster">season-poster-url</thumb>
  <tvdbid>75113</tvdbid>
  <imdbid />
  <tmdbid />
  <uniqueid type="tvdb">75113</uniqueid>
  <premiered />
  <!--tinyMediaManager meta data-->
  <user_note />
</season>
```

TMM 会重写此文件。如果用户不需要季级元数据，可跳过。

---

## 4. 多集/合并集处理

**Kodi v21 及之前**：一个 NFO 文件中包含多个 `<episodedetails>` 块。

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<episodedetails>
  <title>故事 A</title>
  <season>1</season>
  <episode>18</episode>
  <!-- ... -->
</episodedetails>
<episodedetails>
  <title>故事 B</title>
  <season>1</season>
  <episode>19</episode>
  <!-- ... -->
</episodedetails>
```

**Kodi v22+**：每个 episode 单独 NFO，用 `-SxxEyy` 后缀。

**TMM/Plex 路径**：合并集的 NFO 通常写为单 `<episodedetails>`，`<title>` 用 `故事 A / 故事 B` 格式，`<plot>` 用 `A 段：... B 段：...` 格式。这是实际做法，不跟随 Kodi 多集规范。

---

## 5. 关键兼容性备忘

| 规则 | 原因 |
|---|---|
| `<episodeguide>` 用 JSON 不用 URL | Kodi v19+ |
| `<uniqueid>` 必须至少一个 `default="true"` | Kodi 扫描要求 |
| 保留 `<fileinfo>` | Kodi v18+ 写入后不覆盖流详情 |
| TMM 兼容注释块 | TMM 重写时依赖这些标记 |
| `<title>` 非空 | Kodi 将以 "Missing Title" 显示 |
| `<year>` 非空（tvshow） | TMM 对空 `<year>` 敏感 |
| 非空 `<premiered>` | TMM 识别剧集所需 |
| `<episode_groups>` | TMM aired/display 顺序关键 |
| Plex: "Plex NFO Series" agent | PMS ≥ 1.43.1 内置，替代废弃的 XBMCnfoTVImporter |
