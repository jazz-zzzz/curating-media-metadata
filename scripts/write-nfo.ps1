<#
.SYNOPSIS
    写入/编辑 NFO 元数据文件。
    覆盖 fix-my-show 工作流 B7。

.DESCRIPTION
    两种模式：
    - 模式 A（edit）：编辑已有 NFO — 只替换 <title> <plot> <outline>，
      保留 <uniqueid> <thumb> <actor> <fileinfo> 等所有结构元数据。
    - 模式 B（generate）：全新生成 tvshow.nfo + episode NFO + season NFO。

    输入为 CSV 映射文件（B3/B4 产出），包含每集的标题和简介。

.PARAMETER Mode
    edit 或 generate。

.PARAMETER MappingCsv
    B3 产出的映射 CSV 路径。必须列：local_path, season, episode, generated_title, generated_summary。
    可选列：show_title, original_title, premiered, aired, runtime, genre, studio, poster_url, fanart_url。

.PARAMETER RootPath
    剧集根目录。NFO 写入此目录及其子目录。

.PARAMETER ShowTitle
    剧集标题（generate 模式必填）。

.PARAMETER TvdbId
    TVDB ID（generate 模式必填）。

.PARAMETER Year
    年份（generate 模式）。

.PARAMETER OriginalTitle
    原始语言标题（generate 模式）。

.PARAMETER DryRun
    仅预览，不写入文件。

.EXAMPLE
    # 编辑已有 NFO（TMM 已生成，只改语言）
    .\write-nfo.ps1 -Mode edit -MappingCsv "mapping.csv" -RootPath "\\Nas\share\Anime\Show"

.EXAMPLE
    # 全新生成
    .\write-nfo.ps1 -Mode generate -MappingCsv "mapping.csv" -RootPath "\\Nas\share\Anime\Show" `
        -ShowTitle "乱马½" -TvdbId "455906" -Year 2024 -OriginalTitle "らんま½"

.NOTES
    鲁棒性设计：
    - 写入前备份到 .metadata_archive/（跳过已备份的）
    - XML 解析验证每个写入的文件
    - UTF-8 无 BOM 编码（Kodi 要求）
    - PowerShell 5.1 兼容（使用 XmlWriter 而非 Write-Xml）
    - 处理 ½ 等 Unicode 字符
    - 保留现有 <fileinfo> 和 TMM 兼容注释块
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('edit','generate')]
    [string]$Mode,

    [Parameter(Mandatory=$true)]
    [string]$MappingCsv,

    [Parameter(Mandatory=$true)]
    [string]$RootPath,

    # generate 模式参数
    [string]$ShowTitle,
    [string]$TvdbId,
    [string]$Year,
    [string]$OriginalTitle,
    [string]$Status = 'Continuing',
    [string]$Runtime = '25',
    [string]$Genre = '动画',
    [string]$Studio = '',
    [string]$Country = '日本',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- 辅助函数 ---

function Resolve-FullPath {
    param([string]$Path)
    if ($Path.Length -ge 260 -and -not $Path.StartsWith('\\?\')){
        if ($Path.StartsWith('\\')) { return "\\?\UNC\$($Path.Substring(2))" }
        else { return "\\?\$Path" }
    }
    return $Path
}

function Backup-Nfo {
    param([string]$NfoPath, [string]$ArchiveRoot)

    $relPath = $NfoPath.Replace($RootPath, '').TrimStart('\','/')
    $backupPath = Join-Path $ArchiveRoot $relPath
    $backupDir = Split-Path -Parent $backupPath

    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    # 如果已备份过同名文件，加时间戳后缀
    if (Test-Path -LiteralPath $backupPath) {
        $ts = Get-Date -Format 'HHmmss'
        $backupPath = $backupPath -replace '\.nfo$', "_$ts.nfo"
    }

    Copy-Item -LiteralPath $NfoPath -Destination $backupPath -Force
    return $backupPath
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)

    # 使用 UTF-8 无 BOM（Kodi 要求）
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Escape-Xml {
    param([string]$Text)
    if (-not $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function Test-XmlWellFormed {
    param([string]$Path)
    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($Path)
        return @{ valid = $true; root = $xml.DocumentElement.Name }
    } catch {
        return @{ valid = $false; error = $_.Exception.Message }
    }
}

# --- 模式 A: 编辑已有 NFO ---

function Edit-NfoFile {
    param([string]$NfoPath, [string]$NewTitle, [string]$NewPlot, [string]$NewOutline)

    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($NfoPath)

    $root = $xml.DocumentElement

    # 替换 title
    $titleNode = $root.SelectSingleNode('title')
    if ($titleNode) {
        $titleNode.InnerText = $NewTitle
    } else {
        # title 不存在则创建
        $titleNode = $xml.CreateElement('title')
        $titleNode.InnerText = $NewTitle
        $root.PrependChild($titleNode) | Out-Null
    }

    # 替换 plot
    $plotNode = $root.SelectSingleNode('plot')
    if ($plotNode) {
        $plotNode.InnerText = $NewPlot
    } elseif ($NewPlot) {
        $plotNode = $xml.CreateElement('plot')
        $plotNode.InnerText = $NewPlot
        $root.AppendChild($plotNode) | Out-Null
    }

    # 替换 outline
    $outlineNode = $root.SelectSingleNode('outline')
    if ($outlineNode) {
        $outlineNode.InnerText = if ($NewOutline) { $NewOutline } else { '' }
    } elseif ($NewOutline) {
        $outlineNode = $xml.CreateElement('outline')
        $outlineNode.InnerText = $NewOutline
        $root.AppendChild($outlineNode) | Out-Null
    }

    # 保存 — 使用 XmlWriter 保持编码正确
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding $false
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.OmitXmlDeclaration = $false

    $writer = [System.Xml.XmlWriter]::Create($NfoPath, $settings)
    $xml.Save($writer)
    $writer.Close()
}

# --- 模式 B: 全新生成 ---

function New-TvshowNfo {
    param([string]$Path, [hashtable]$Data)

    $xml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<tvshow>
  <title>$(Escape-Xml $Data.ShowTitle)</title>
  <originaltitle>$(Escape-Xml $Data.OriginalTitle)</originaltitle>
  <showtitle>$(Escape-Xml $Data.ShowTitle)</showtitle>
  <sorttitle />
  <year>$($Data.Year)</year>
  <ratings />
  <userrating>0</userrating>
  <outline />
  <plot>$(Escape-Xml $Data.Plot)</plot>
  <tagline />
  <runtime>$($Data.Runtime)</runtime>
  $(if ($Data.PosterUrl) { "<thumb aspect=`"poster`">$(Escape-Xml $Data.PosterUrl)</thumb>" } else { '' })
  $(if ($Data.FanartUrl) { "<fanart><thumb>$(Escape-Xml $Data.FanartUrl)</thumb></fanart>" } else { '' })
  <mpaa />
  <certification />
  <episodeguide>{"tvdb":"$($Data.TvdbId)"}</episodeguide>
  <id>$($Data.TvdbId)</id>
  <imdbid />
  <tmdbid />
  <uniqueid type="tvdb" default="true">$($Data.TvdbId)</uniqueid>
  <premiered>$($Data.Premiered)</premiered>
  <status>$($Data.Status)</status>
  <watched>false</watched>
  <playcount />
  <genre>$(Escape-Xml $Data.Genre)</genre>
  $(if ($Data.Studio) { "<studio>$(Escape-Xml $Data.Studio)</studio>" } else { '' })
  <country>$(Escape-Xml $Data.Country)</country>
  $(if ($Data.SeasonTitles) { $Data.SeasonTitles } else { '' })
  <tag />
  <trailer />
  <dateadded />
  <!--tinyMediaManager meta data-->
  <user_note />
  <episode_groups>
    <group active="true" id="AIRED" name="" />
    <group id="DISPLAY" name="" />
  </episode_groups>
  <english_title />
  <tmm_locked />
</tvshow>
"@
    Write-Utf8NoBom -Path $Path -Content $xml
}

function New-EpisodeNfo {
    param([string]$Path, [hashtable]$Data)

    $xml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<episodedetails>
  <title>$(Escape-Xml $Data.Title)</title>
  <originaltitle />
  <showtitle>$(Escape-Xml $Data.ShowTitle)</showtitle>
  <season>$($Data.Season)</season>
  <episode>$($Data.Episode)</episode>
  <id />
  <ratings />
  <userrating>0</userrating>
  <plot>$(Escape-Xml $Data.Plot)</plot>
  <runtime>$($Data.Runtime)</runtime>
  <mpaa />
  <premiered>$($Data.Premiered)</premiered>
  <aired>$($Data.Aired)</aired>
  <watched>false</watched>
  <playcount>0</playcount>
  $(if ($Data.Studio) { "<studio>$(Escape-Xml $Data.Studio)</studio>" } else { '' })
  $(if ($Data.Genre) { "<genre>$(Escape-Xml $Data.Genre)</genre>" } else { '' })
  $(if ($Data.Credits) { "<credits>$(Escape-Xml $Data.Credits)</credits>" } else { '' })
  $(if ($Data.Director) { "<director>$(Escape-Xml $Data.Director)</director>" } else { '' })
  <dateadded />
  <epbookmark />
  <code />
  <!--tinyMediaManager compatible meta data-->
  <source>UNKNOWN</source>
  <edition>NONE</edition>
  <original_filename />
  <user_note />
  <episode_groups>
    <group episode="$($Data.Episode)" id="AIRED" name="" season="$($Data.Season)" />
    <group episode="-1" id="DISPLAY" name="" season="-1" />
  </episode_groups>
</episodedetails>
"@
    Write-Utf8NoBom -Path $Path -Content $xml
}

function New-SeasonNfo {
    param([string]$Path, [hashtable]$Data)

    $xml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<season>
  <seasonnumber>$($Data.SeasonNumber)</seasonnumber>
  <title>$(Escape-Xml $Data.Title)</title>
  <showtitle>$(Escape-Xml $Data.ShowTitle)</showtitle>
  <sorttitle>季 $('{0:D2}' -f [int]$Data.SeasonNumber)</sorttitle>
  <year>$($Data.Year)</year>
  <plot>$(Escape-Xml $Data.Plot)</plot>
  $(if ($Data.PosterUrl) { "<thumb aspect=`"poster`">$(Escape-Xml $Data.PosterUrl)</thumb>" } else { '' })
  <tvdbid>$($Data.TvdbId)</tvdbid>
  <imdbid />
  <tmdbid />
  <uniqueid type="tvdb">$($Data.TvdbId)</uniqueid>
  <premiered>$($Data.Premiered)</premiered>
  <!--tinyMediaManager meta data-->
  <user_note />
</season>
"@
    Write-Utf8NoBom -Path $Path -Content $xml
}

# --- 主逻辑 ---

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "根目录不存在: $RootPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $MappingCsv)) {
    Write-Error "映射 CSV 不存在: $MappingCsv"
    exit 1
}

$mapping = Import-Csv -LiteralPath $MappingCsv -Encoding UTF8

# 验证必要列
$epRequiredCols = @('local_path','season','episode','generated_title','generated_summary')
$missing = $epRequiredCols | Where-Object { $_ -notin $mapping[0].PSObject.Properties.Name }
if ($missing) {
    Write-Error "CSV 缺少列: $($missing -join ', ')"
    exit 1
}

# 准备备份目录
$archiveRoot = Join-Path $RootPath '.metadata_archive'
if (-not $DryRun -and -not (Test-Path -LiteralPath $archiveRoot)) {
    New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
}

$stats = @{ backed_up = 0; written = 0; edited = 0; validated = 0; validation_failed = 0 }
$showSeasonSet = @{}

# --- 模式 A: 编辑 ---

if ($Mode -eq 'edit') {
    Write-Host "模式: 编辑已有 NFO"

    foreach ($row in $mapping) {
        $localPath = $row.local_path
        if (-not $localPath) { continue }

        # 找到对应的 NFO 文件
        $mediaDir = Split-Path -Parent (Join-Path $RootPath $localPath)
        $mediaBase = [System.IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $localPath))
        $nfoPath = Join-Path $mediaDir "$mediaBase.nfo"

        if (-not (Test-Path -LiteralPath $nfoPath)) {
            Write-Warning "跳过（无 NFO）: $localPath"
            continue
        }

        $title = $row.generated_title
        $summary = $row.generated_summary
        $outline = if ($row.PSObject.Properties.Name -contains 'outline') { $row.outline } else { '' }

        if (-not $DryRun) {
            # 备份
            Backup-Nfo -NfoPath $nfoPath -ArchiveRoot $archiveRoot | Out-Null
            $stats.backed_up++

            # 编辑
            Edit-NfoFile -NfoPath $nfoPath -NewTitle $title -NewPlot $summary -NewOutline $outline
            $stats.edited++

            # 验证
            $result = Test-XmlWellFormed -Path $nfoPath
            if ($result.valid) { $stats.validated++ }
            else { $stats.validation_failed++; Write-Warning "XML 无效: $nfoPath — $($result.error)" }
        }

        Write-Host "  $(if ($DryRun) { '[DRY RUN] ' } else { '' })编辑: S$($row.season)E$($row.episode) — $title"
    }
}

# --- 模式 B: 全新生成 ---

if ($Mode -eq 'generate') {
    Write-Host "模式: 全新生成 NFO"

    if (-not $ShowTitle -or -not $TvdbId) {
        Write-Error "generate 模式必须指定 -ShowTitle 和 -TvdbId"
        exit 1
    }

    # 备份已有 NFO（跳过之前的备份目录）
    if (-not $DryRun) {
        $existingNfos = Get-ChildItem -LiteralPath (Resolve-FullPath -Path $RootPath) -Recurse -Filter '*.nfo' -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -notmatch '\.metadata_archive' }

        foreach ($nfo in $existingNfos) {
            Backup-Nfo -NfoPath $nfo.FullName -ArchiveRoot $archiveRoot | Out-Null
            $stats.backed_up++
        }
        Write-Host "备份: $($stats.backed_up) 个已有 NFO"
    }

    # 1. 写 tvshow.nfo
    $tvshowPath = Join-Path $RootPath 'tvshow.nfo'
    $tvshowData = @{
        ShowTitle    = $ShowTitle
        OriginalTitle = $OriginalTitle
        Year         = $Year
        TvdbId       = $TvdbId
        Status       = $Status
        Runtime      = $Runtime
        Genre        = $Genre
        Studio       = $Studio
        Country      = $Country
        Plot         = $mapping[0].PSObject.Properties.Name -contains 'show_summary' ? $mapping[0].show_summary : ''
        Premiered    = $mapping[0].PSObject.Properties.Name -contains 'premiered' ? $mapping[0].premiered : ''
        PosterUrl    = $mapping[0].PSObject.Properties.Name -contains 'poster_url' ? $mapping[0].poster_url : ''
        FanartUrl    = $mapping[0].PSObject.Properties.Name -contains 'fanart_url' ? $mapping[0].fanart_url : ''
        SeasonTitles = ''
    }

    if (-not $DryRun) {
        New-TvshowNfo -Path $tvshowPath -Data $tvshowData
        $stats.written++
        $result = Test-XmlWellFormed -Path $tvshowPath
        if ($result.valid) { $stats.validated++ }
        else { $stats.validation_failed++; Write-Warning "XML 无效 tvshow.nfo: $($result.error)" }
    }
    Write-Host "  $(if ($DryRun) { '[DRY RUN] ' } else { '' })tvshow.nfo"

    # 2. 汇总季信息
    $seasons = $mapping | Select-Object season -Unique | ForEach-Object { $_.season } | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ }

    # 3. 写 season NFO
    foreach ($s in $seasons) {
        $seasonDir = Join-Path $RootPath "Season $('{0:D2}' -f [int]$s)"
        if (-not $DryRun -and -not (Test-Path -LiteralPath $seasonDir)) {
            New-Item -ItemType Directory -Path $seasonDir -Force | Out-Null
        }

        $seasonNfoPath = Join-Path $seasonDir 'season.nfo'
        $seasonData = @{
            SeasonNumber = $s
            Title        = "第 $s 季"
            ShowTitle    = $ShowTitle
            Year         = $Year
            TvdbId       = $TvdbId
            Plot         = "《$ShowTitle》第 $s 季。"
            Premiered    = ''
            PosterUrl    = ''
        }

        if (-not $DryRun) {
            New-SeasonNfo -Path $seasonNfoPath -Data $seasonData
            $stats.written++
            $result = Test-XmlWellFormed -Path $seasonNfoPath
            if ($result.valid) { $stats.validated++ }
            else { $stats.validation_failed++; Write-Warning "XML 无效 season $s : $($result.error)" }
        }
        Write-Host "  $(if ($DryRun) { '[DRY RUN] ' } else { '' })season.nfo (S$s)"
    }

    # 4. 写 episode NFO
    foreach ($row in $mapping) {
        $localPath = $row.local_path
        if (-not $localPath) { continue }

        $s = $row.season
        $e = $row.episode
        $seasonDir = Join-Path $RootPath "Season $('{0:D2}' -f [int]$s)"
        $mediaBase = [System.IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $localPath))
        $epNfoPath = Join-Path $seasonDir "$mediaBase.nfo"

        $epData = @{
            Title     = $row.generated_title
            ShowTitle = $ShowTitle
            Season    = $s
            Episode   = $e
            Plot      = $row.generated_summary
            Runtime   = $Runtime
            Premiered = if ($row.PSObject.Properties.Name -contains 'aired') { $row.aired } else { '' }
            Aired     = if ($row.PSObject.Properties.Name -contains 'aired') { $row.aired } else { '' }
            Studio    = $Studio
            Genre     = $Genre
            Credits   = ''
            Director  = ''
        }

        if (-not $DryRun) {
            if (-not (Test-Path -LiteralPath $seasonDir)) {
                New-Item -ItemType Directory -Path $seasonDir -Force | Out-Null
            }
            New-EpisodeNfo -Path $epNfoPath -Data $epData
            $stats.written++
            $result = Test-XmlWellFormed -Path $epNfoPath
            if ($result.valid) { $stats.validated++ }
            else { $stats.validation_failed++; Write-Warning "XML 无效 S${s}E${e}: $($result.error)" }
        }
        Write-Host "  $(if ($DryRun) { '[DRY RUN] ' } else { '' })S${s}E${e}: $($row.generated_title)"
    }
}

# --- 最终统计 ---

if ($DryRun) {
    Write-Host "`n=== DRY RUN 完成（未写入任何文件） ==="
} else {
    Write-Host "`n=== NFO 写入完成 ==="
    Write-Host "备份: $($stats.backed_up)  写入: $($stats.written)  编辑: $($stats.edited)  验证通过: $($stats.validated)"
    if ($stats.validation_failed -gt 0) {
        Write-Host "验证失败: $($stats.validation_failed) — 请检查上述警告" -ForegroundColor Red
    }
}
