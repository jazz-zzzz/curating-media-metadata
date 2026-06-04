# Plex API 参考

Plex Media Server (PMS) 的 REST API。基础 URL：`http://{host}:32400`。所有请求需要 `X-Plex-Token` 参数。

## 鉴权

### 获取 Token（Windows）
```powershell
$token = (Get-ItemProperty "HKCU:\Software\Plex, Inc.\Plex Media Server").PlexOnlineToken
```

其他平台：`Preferences.xml` 中 `PlexOnlineToken` 属性。

### 请求头
```http
X-Plex-Token: {token}
X-Plex-Client-Identifier: {unique-id}
Accept: application/json
```

或使用 query string：`?X-Plex-Token={token}`。

## 核心端点

### 列出资料库
```
GET /library/sections
```
返回所有资料库，`type=show` 为 TV/动画库。记录目标库的 `key`。

### 搜索剧集
```
GET /search?query={keyword}
```
返回 `Metadata` 数组，`type=show` 的条目即为目标剧集。记录 `ratingKey`。

### 获取剧集全部集数
```
GET /library/metadata/{showKey}/allLeaves
```
返回 XML：`<Video ratingKey="..." parentIndex="S" index="E" title="..." summary="..."/>`

- `parentIndex` = 季号
- `index` = 集号
- `ratingKey` = 用于 PUT 更新

### 获取季列表
```
GET /library/metadata/{showKey}/children
```
返回 `<Directory ratingKey="..." index="0|1|2|3" title="..."/>`

## 写入元数据

### 更新集/季/剧的 title 和 summary
```
PUT /library/metadata/{ratingKey}?title.value={URL_ENCODED}&title.locked=1&summary.value={URL_ENCODED}&summary.locked=1
```

**必须加 `locked=1`**，否则 Plex 刷新元数据时会从在线源覆盖。

### URL 编码
```powershell
$t = [Uri]::EscapeDataString("中文标题")
```

**不能用 `[System.Web.HttpUtility]::UrlEncode`**（PowerShell 5.1 不可用）。

## 锁定字段（防止在线源覆盖）

| 参数 | 作用 |
|------|------|
| `title.locked=1` | 锁定标题 |
| `summary.locked=1` | 锁定简介 |
| `title.locked=0` | 解锁标题 |
| `summary.locked=0` | 解锁简介 |

**行为差异**：
- 不带 locked → 写入成功，但用户 "Refresh Metadata" 后数据被在线源覆盖
- 带 locked=1 → 锁定后刷新不会覆盖

## 完整工作流

```powershell
# 1. 鉴权
$token = (Get-ItemProperty "HKCU:\Software\Plex, Inc.\Plex Media Server").PlexOnlineToken
$plex = "http://{host}:32400"

# 2. 找剧集
$search = Invoke-RestMethod "$plex/search?query=keyword&X-Plex-Token=$token"
$showKey = ($search.MediaContainer.Metadata | Where type -eq show).ratingKey

# 3. 获取全部集
$eps = Invoke-RestMethod "$plex/library/metadata/$showKey/allLeaves?X-Plex-Token=$token"
[xml]$xml = $eps

# 4. 逐集 PUT
foreach ($v in $xml.MediaContainer.Video) {
    $rk = $v.ratingKey
    $t = [Uri]::EscapeDataString("中文标题")
    $s = [Uri]::EscapeDataString("中文简介")
    Invoke-WebRequest "$plex/library/metadata/$rk?title.value=$t&title.locked=1&summary.value=$s&summary.locked=1&X-Plex-Token=$token" -Method Put -UseBasicParsing
}

# 5. 更新季级
$children = Invoke-RestMethod "$plex/library/metadata/$showKey/children?X-Plex-Token=$token"
[xml]$cxml = $children
foreach ($d in $cxml.MediaContainer.Directory) {
    # PUT season title + summary (skip "All episodes" if key is empty)
    if ($d.ratingKey) { ... }
}

# 6. 更新剧级
# PUT show title + summary to $showKey
```

## 故障排查

| 问题 | 原因 | 解决 |
|------|------|------|
| PUT 200 但刷新后变回英文 | 未加 `locked=1` | 重新 PUT + locked=1，再刷新 |
| 404 Not Found | ratingKey 错误或 URL 格式不对 | 检查 ratingKey，确认 `?` 前没有多余空格 |
| 返回乱码 | PowerShell 编码 | 设置 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` |
| 引号冲突 | 中文引号 `""` 被解析为 PowerShell 语法 | 写脚本文件用 `@''@` 单引号 here-string |
| 路径过长 | Windows MAX_PATH (260 char) | UNC 路径用 `\\?\UNC\host\share\...` 前缀 |
