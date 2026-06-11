<#
.SYNOPSIS
    扫描媒体目录，解析季/集结构，检测 NFO 和字幕文件。
    覆盖 fix-my-show 工作流 A1 + B1。

.DESCRIPTION
    递归扫描指定目录下的所有媒体文件，从文件名解析 Season/Episode 编号，
    检测配套的 NFO 和字幕文件，标记命名异常，输出结构化 JSON。

.PARAMETER RootPath
    要扫描的剧集根目录路径。

.PARAMETER OutputPath
    JSON 输出文件路径。不指定则输出到 stdout。

.PARAMETER ExcludePatterns
    要排除的目录名正则模式数组。默认排除 @('backup','archive','\.metadata_archive','\.git','\$RECYCLE\.BIN','System Volume Information')。

.EXAMPLE
    .\scan.ps1 -RootPath "\\Nas\share\Anime\ShowName" -OutputPath "scan_result.json"

.NOTES
    鲁棒性设计：
    - 支持 UNC 路径和长路径（自动添加 \\?\ 前缀）
    - 处理 ½ 等 Unicode 字符
    - 容忍文件名中无季/集编号的文件（标记为 unrecognized）
    - 检测 BD 原盘目录（BDMV/CERTIFICATE）
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RootPath,

    [string]$OutputPath,

    [string[]]$ExcludePatterns = @('backup','archive','\.metadata_archive','\.git','\$RECYCLE\.BIN','System Volume Information')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- 辅助函数 ---

function Resolve-FullPath {
    param([string]$Path)
    # 自动添加长路径前缀
    if ($Path.Length -ge 260 -and -not $Path.StartsWith('\\?\')){
        if ($Path.StartsWith('\\')) {
            return "\\?\UNC\$($Path.Substring(2))"
        } else {
            return "\\?\$Path"
        }
    }
    return $Path
}

function Test-Excluded {
    param([string]$DirName)
    foreach ($pat in $ExcludePatterns) {
        if ($DirName -match $pat) { return $true }
    }
    return $false
}

function Parse-SeasonEpisode {
    param([string]$FileName)

    # 支持的命名模式（按优先级）
    $patterns = @(
        @{Regex='[Ss](\d{1,4})\s*[Ee]\s*(\d{1,4})';   SeasonGroup=1; EpisodeGroup=2},  # S01E07 / s1e07
        @{Regex='[Ss](\d{1,4})\s*[Ee][Pp]\s*(\d{1,4})'; SeasonGroup=1; EpisodeGroup=2}, # S01EP07
        @{Regex='(\d{1,2})[xX](\d{1,4})';               SeasonGroup=1; EpisodeGroup=2},  # 1x07
        @{Regex='[Ss]eason\s*(\d{1,2}).*?[Ee]pisode\s*(\d{1,4})'; SeasonGroup=1; EpisodeGroup=2}, # Season 1 Episode 7
        @{Regex='[Ee][Pp]\.?\s*(\d{1,4})';               SeasonGroup=0; EpisodeGroup=1},  # EP07 (season=0 表示需要推断)
        @{Regex='\#(\d{1,4})';                           SeasonGroup=0; EpisodeGroup=1},  # #007 (absolute)
        @{Regex='\b(\d{1,3})\b';                         SeasonGroup=0; EpisodeGroup=1}   # 纯数字（最后匹配）
    )

    foreach ($p in $patterns) {
        if ($FileName -match $p.Regex) {
            $season = if ($p.SeasonGroup -eq 0) { 0 } else { [int]$Matches[$p.SeasonGroup] }
            $episode = [int]$Matches[$p.EpisodeGroup]
            return @{ Season = $season; Episode = $episode; Pattern = $p.Regex }
        }
    }
    return $null
}

function Get-MediaFiles {
    param([string]$Path)

    $extensions = @('.mkv','.mp4','.avi','.m2ts','.ts','.wmv','.mov','.flv','.webm','.m4v','.divx','.ogm','.rmvb')
    $mediaFiles = @()

    try {
        $fullPath = Resolve-FullPath -Path $Path
        $allFiles = Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force -ErrorAction SilentlyContinue

        foreach ($file in $allFiles) {
            if ($file.Extension -and $extensions -contains $file.Extension.ToLower()) {
                # 检查是否在排除目录中
                $parentDir = Split-Path -Parent $file.FullName
                $dirName = Split-Path -Leaf $parentDir
                if (-not (Test-Excluded -DirName $dirName)) {
                    $mediaFiles += $file
                }
            }
        }
    } catch {
        Write-Warning "扫描路径出错: $Path — $_"
    }

    return $mediaFiles
}

function Get-CompanionFile {
    param([string]$BaseName, [string]$Directory, [string[]]$Extensions)

    foreach ($ext in $Extensions) {
        $candidate = Join-Path $Directory "$BaseName$ext"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Test-BDRipStructure {
    param([string]$Path)
    return ((Test-Path -LiteralPath (Join-Path $Path 'BDMV')) -and
            (Test-Path -LiteralPath (Join-Path $Path 'CERTIFICATE')))
}

# --- 主逻辑 ---

Write-Verbose "扫描目录: $RootPath"

# 验证输入
if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "目录不存在: $RootPath"
    exit 1
}

# 获取所有媒体文件
$mediaFiles = Get-MediaFiles -Path $RootPath
Write-Verbose "发现 $($mediaFiles.Count) 个媒体文件"

# 构建文件清单
$files = @()
$stats = @{
    total_media   = $mediaFiles.Count
    with_nfo      = 0
    with_subtitle = 0
    orphan_nfo    = 0
    unrecognized  = 0
    bd_rips       = 0
    naming_issues = 0
}

foreach ($f in $mediaFiles) {
    $parsed = Parse-SeasonEpisode -FileName $f.Name
    $baseName = $f.BaseName
    $dir = Split-Path -Parent $f.FullName

    # 检测配套文件
    $nfoFile = Get-CompanionFile -BaseName $baseName -Directory $dir -Extensions @('.nfo')
    $subExtensions = @('.ass','.srt','.ssa','.sub','.idx','.vtt','.sup','.pgs')
    $subFiles = @()
    foreach ($subExt in $subExtensions) {
        $subPath = Get-CompanionFile -BaseName $baseName -Directory $dir -Extensions @($subExt)
        if ($subPath) { $subFiles += $subPath }

        # 也检查带语言后缀的: basename.chi.ass, basename.jpn.ass
        $subPathLang = Get-CompanionFile -BaseName "$baseName.*" -Directory $dir -Extensions @($subExt)
        # 简化：只检查同 baseName 开头的文件
    }
    # 更全面的字幕检测
    $allSubs = Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq $baseName -and $subExtensions -contains $_.Extension.ToLower() }
    $subFiles = @($allSubs | ForEach-Object { $_.FullName })

    # 命名异常检测
    $namingIssues = @()
    if ($f.Name.Length -gt 200) {
        $namingIssues += "PATH_TOO_LONG"
    }
    if ($f.Name -match '\.\w{1,2}$' -and $f.Name -notmatch '\.(mkv|mp4|avi|m2ts|ts|wmv|mov|flv|webm|m4v)$') {
        $namingIssues += "TRUNCATED_EXTENSION"
    }
    # 检测纯数字文件名（可能没有 structured naming）
    if ($f.BaseName -match '^\d+$') {
        $namingIssues += "NUMERIC_ONLY_NAME"
    }
    # 检测文件名含两段式集号（可能的合并集）
    if ($f.BaseName -match '(?:\b|E)[Pp]?\d{1,4}[-\&\+]\d{1,4}\b') {
        $namingIssues += "POSSIBLE_MERGED_EPISODE"
    }

    if ($namingIssues.Count -gt 0) { $stats.naming_issues++ }

    $fileEntry = @{
        path             = $f.FullName
        relative_path    = $f.FullName.Replace($RootPath, '').TrimStart('\','/')
        name             = $f.Name
        size_bytes       = $f.Length
        extension        = $f.Extension.ToLower()
        season           = if ($parsed) { $parsed.Season } else { $null }
        episode          = if ($parsed) { $parsed.Episode } else { $null }
        parse_pattern    = if ($parsed) { $parsed.Pattern } else { $null }
        has_nfo          = ($nfoFile -ne $null)
        nfo_path         = $nfoFile
        subtitle_files   = $subFiles
        naming_issues    = $namingIssues
        parent_directory = Split-Path -Leaf $dir
    }

    if ($fileEntry.has_nfo) { $stats.with_nfo++ }
    if ($subFiles.Count -gt 0) { $stats.with_subtitle++ }
    if (-not $parsed) { $stats.unrecognized++ }

    $files += $fileEntry
}

# 检测孤立 NFO（有 NFO 但无对应媒体文件）
$allNfos = Get-ChildItem -LiteralPath (Resolve-FullPath -Path $RootPath) -Recurse -Filter '*.nfo' -Force -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-Excluded -DirName (Split-Path -Leaf (Split-Path -Parent $_.FullName))) }

$mediaBaseNames = $files | ForEach-Object {
    [System.IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $_.path))
}

foreach ($nfo in $allNfos) {
    $nfoBaseName = $nfo.BaseName
    # 排除 tvshow, season, series 等特殊 NFO
    if ($nfoBaseName -notin @('tvshow','season','series','index') -and
        $nfoBaseName -notin $mediaBaseNames) {
        $stats.orphan_nfo++
        $files += @{
            path             = $null
            relative_path    = $nfo.FullName.Replace($RootPath, '').TrimStart('\','/')
            name             = $nfo.Name
            size_bytes       = $nfo.Length
            extension        = '.nfo'
            season           = $null
            episode          = $null
            parse_pattern    = $null
            has_nfo          = $false
            nfo_path         = $nfo.FullName
            subtitle_files   = @()
            naming_issues    = @('ORPHAN_NFO')
            parent_directory = Split-Path -Leaf (Split-Path -Parent $nfo.FullName)
            is_orphan_nfo    = $true
        }
    }
}

# 检测 BD 原盘
$subDirs = Get-ChildItem -LiteralPath (Resolve-FullPath -Path $RootPath) -Directory -Force -ErrorAction SilentlyContinue
foreach ($sd in $subDirs) {
    if (Test-BDRipStructure -Path $sd.FullName) {
        $stats.bd_rips++
        $files += @{
            path             = $sd.FullName
            relative_path    = $sd.FullName.Replace($RootPath, '').TrimStart('\','/')
            name             = $sd.Name
            size_bytes       = 0
            extension        = ''
            season           = $null
            episode          = $null
            parse_pattern    = null
            has_nfo          = $false
            nfo_path         = $null
            subtitle_files   = @()
            naming_issues    = @()
            parent_directory = Split-Path -Leaf $RootPath
            is_bd_rip        = $true
        }
    }
}

# 构建输出
$result = @{
    scan_time    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    root_path    = $RootPath
    stats        = $stats
    files        = $files
}

$json = $result | ConvertTo-Json -Depth 4 -Compress

if ($OutputPath) {
    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $json | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "scan: $($stats.total_media) media, $($stats.with_nfo) with NFO, $($stats.unrecognized) unrecognized → $OutputPath"
} else {
    Write-Output $json
}
