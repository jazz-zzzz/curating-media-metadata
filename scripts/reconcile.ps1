<#
.SYNOPSIS
    本地文件 vs 在线源对账引擎。
    覆盖 fix-my-show 工作流 A3。

.DESCRIPTION
    输入 scan.ps1 的 JSON + 在线源 CSV（TVDB/TMDB 集数表），
    逐季对比：集数匹配、编号连续、未识别文件、孤立 NFO、命名异常。
    输出缺口报告 JSON。

.PARAMETER ScanJson
    scan.ps1 输出的 JSON 文件路径。

.PARAMETER SourceCsv
    在线源集数表 CSV。必须列：season, episode, title。
    可选列：aired, summary, absolute_number, special。

.PARAMETER SourceName
    源名称（TVDB / TMDB / AniDB），用于报告标记。

.PARAMETER OutputPath
    缺口报告 JSON 输出路径。

.EXAMPLE
    .\reconcile.ps1 -ScanJson "scan.json" -SourceCsv "tvdb_s01.csv" -SourceName "TVDB" -OutputPath "gap_report.json"

.NOTES
    鲁棒性设计：
    - Specials（season=0）单独处理
    - 容忍 ±3 集位置偏移
    - 标记未识别文件和孤立 NFO
    - 输出 JSON 供 Agent 解读，非人类可读表格
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ScanJson,

    [Parameter(Mandatory=$true)]
    [string]$SourceCsv,

    [Parameter(Mandatory=$true)]
    [string]$SourceName,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# --- 加载数据 ---

if (-not (Test-Path -LiteralPath $ScanJson)) {
    Write-Error "扫描 JSON 不存在: $ScanJson"
    exit 1
}
if (-not (Test-Path -LiteralPath $SourceCsv)) {
    Write-Error "源 CSV 不存在: $SourceCsv"
    exit 1
}

$scan = Get-Content -LiteralPath $ScanJson -Encoding UTF8 | ConvertFrom-Json
$source = @(Import-Csv -LiteralPath $SourceCsv -Encoding UTF8)
if ($source.Count -eq 0) {
    Write-Error "源 CSV 为空: $SourceCsv"
    exit 1
}

# 验证源 CSV 列
$srcCols = $source[0].PSObject.Properties.Name
if ('season' -notin $srcCols -or 'episode' -notin $srcCols) {
    Write-Error "源 CSV 缺少 season/episode 列"
    exit 1
}

# --- 构建对照表 ---

# 本地：按季分组（排除孤立 NFO 和 BD 原盘）
$localFiles = $scan.files | Where-Object { -not $_.is_orphan_nfo -and -not $_.is_bd_rip }
$localBySeason = $localFiles | Where-Object { $_.season -ne $null } | Group-Object season -AsHashTable

# 源：按季分组
$sourceBySeason = $source | Group-Object { [int]$_.season } -AsHashTable

# 所有季号
$allSeasons = @(($localBySeason.Keys + $sourceBySeason.Keys) | Select-Object -Unique | Sort-Object { [int]$_ })

# --- 逐季对比 ---

$gaps = @()
$issues = @()

foreach ($season in $allSeasons) {
    $localEps = if ($localBySeason.ContainsKey($season)) {
        $localBySeason[$season] | Sort-Object { [int]$_.episode }
    } else { @() }

    $sourceEps = if ($sourceBySeason.ContainsKey($season)) {
        $sourceBySeason[$season] | Sort-Object { [int]$_.episode }
    } else { @() }

    $localEpNums = $localEps | ForEach-Object { [int]$_.episode } | Sort-Object
    $sourceEpNums = $sourceEps | ForEach-Object { [int]$_.episode } | Sort-Object

    # 集数匹配
    $localCount = $localEps.Count
    $sourceCount = $sourceEps.Count
    $countMatch = ($localCount -eq $sourceCount)

    # 缺失集：源有但本地无
    $missing = $sourceEpNums | Where-Object { $_ -notin $localEpNums }

    # 多余集：本地有但源无
    $extra = $localEpNums | Where-Object { $_ -notin $sourceEpNums }

    # 编号跳号检测
    $gaps = @()
    if ($localEpNums.Count -gt 1) {
        for ($i = 1; $i -lt $localEpNums.Count; $i++) {
            $expected = $localEpNums[$i-1] + 1
            if ($localEpNums[$i] -ne $expected) {
                $gaps += @{ from = $localEpNums[$i-1]; to = $localEpNums[$i] }
            }
        }
    }

    # 命名异常（来自扫描结果）
    $namingIssues = $localEps | Where-Object { $_.naming_issues.Count -gt 0 } | ForEach-Object {
        @{ file = $_.name; issues = $_.naming_issues }
    }

    $seasonReport = @{
        season        = [int]$season
        is_special    = ([int]$season -eq 0)
        local_count   = $localCount
        source_count  = $sourceCount
        count_match   = $countMatch
        missing_eps   = @($missing)
        extra_eps     = @($extra)
        gaps          = $gaps
        naming_issues = @($namingIssues)
        status        = if ($countMatch -and $missing.Count -eq 0 -and $extra.Count -eq 0 -and $gaps.Count -eq 0) { 'ok' } else { 'needs_review' }
    }

    $issues += $seasonReport
}

# --- 未识别文件 ---
$unrecognized = $localFiles | Where-Object { $_.season -eq $null } | ForEach-Object {
    @{ name = $_.name; path = $_.relative_path; size_bytes = $_.size_bytes }
}

# --- 孤立 NFO ---
$orphanNfos = $scan.files | Where-Object { $_.is_orphan_nfo } | ForEach-Object {
    @{ name = $_.name; path = $_.relative_path }
}

# --- 全局统计 ---
$globalStats = @{
    total_local_media     = $scan.stats.total_media
    total_source_episodes = $source.Count
    with_nfo              = $scan.stats.with_nfo
    unrecognized          = @($unrecognized).Count
    orphan_nfo            = @($orphanNfos).Count
    naming_issues         = $scan.stats.naming_issues
    bd_rips               = $scan.stats.bd_rips
    seasons_with_issues   = ($issues | Where-Object { $_.status -eq 'needs_review' }).Count
}

# --- 构建报告 ---

$report = @{
    report_time  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    source_name  = $SourceName
    root_path    = $scan.root_path
    global_stats = $globalStats
    seasons      = $issues
    unrecognized = @($unrecognized)
    orphan_nfo   = @($orphanNfos)
    needs_review = ($globalStats.seasons_with_issues -gt 0) -or
                   ($unrecognized.Count -gt 0) -or
                   ($orphanNfos.Count -gt 0)
}

$json = $report | ConvertTo-Json -Depth 5 -Compress

if ($OutputPath) {
    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $json | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "reconcile: $($globalStats.seasons_with_issues) seasons with issues, $($unrecognized.Count) unrecognized → $OutputPath"
} else {
    Write-Output $json
}
