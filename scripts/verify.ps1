<#
.SYNOPSIS
    验证 NFO 文件完整性和格式正确性。
    覆盖 fix-my-show 工作流 B8。

.DESCRIPTION
    遍历所有 NFO 文件（排除备份目录），XML 解析验证，
    统计根标签数量，对比媒体文件数，标记解析失败的文件。

.PARAMETER RootPath
    剧集根目录路径。

.PARAMETER ScanJson
    scan.ps1 输出的 JSON 文件路径。如果提供，则对比媒体文件数 vs NFO 文件数。

.PARAMETER Strict
    严格模式：检查 <title> 非空；对 tvshow/episodedetails 检查 <uniqueid> default=true。

.EXAMPLE
    .\verify.ps1 -RootPath "\\Nas\share\Anime\Show" -ScanJson "scan_result.json"

.EXAMPLE
    .\verify.ps1 -RootPath "\\Nas\share\Anime\Show" -Strict

.NOTES
    鲁棒性设计：
    - 自动跳过 .metadata_archive/ 等备份目录
    - 逐文件 try/catch 防止单文件损坏中断全量验证
    - 支持 UNC 和长路径
    - 检查 <fileinfo> 保留情况
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RootPath,

    [string]$ScanJson,

    [switch]$Strict
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Resolve-FullPath {
    param([string]$Path)
    if ($Path.Length -ge 260 -and -not $Path.StartsWith('\\?\')){
        if ($Path.StartsWith('\\')) { return "\\?\UNC\$($Path.Substring(2))" }
        else { return "\\?\$Path" }
    }
    return $Path
}

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "目录不存在: $RootPath"
    exit 1
}

$fullRoot = Resolve-FullPath -Path $RootPath

# --- 收集 NFO ---

$excludeDirs = @('\.metadata_archive','backup','archive','\.git')
$nfos = Get-ChildItem -LiteralPath $fullRoot -Recurse -Filter '*.nfo' -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $parent = $_.DirectoryName
        $excluded = $false
        foreach ($pat in $excludeDirs) {
            if ($parent -match $pat) { $excluded = $true; break }
        }
        -not $excluded
    } |
    Sort-Object FullName

Write-Host "发现 $($nfos.Count) 个 NFO 文件"

if ($nfos.Count -eq 0) {
    Write-Host "没有 NFO 文件要验证。"
    exit 0
}

# --- 验证 ---

$counts = @{}
$bad = @()
$warnings = @()
$hasFileinfo = 0
$hasUniqueidDefault = 0
$emptyTitle = @()

foreach ($nfo in $nfos) {
    try {
        $content = [System.IO.File]::ReadAllText($nfo.FullName, [System.Text.Encoding]::UTF8)
        $xml = [xml]$content
        $tag = $xml.DocumentElement.Name
        $currentCount = if ($counts.ContainsKey($tag)) { [int]$counts[$tag] } else { 0 }
        $counts[$tag] = $currentCount + 1

        # Strict 检查
        if ($Strict) {
            # title 非空检查
            $titleNode = $xml.DocumentElement.SelectSingleNode('title')
            if (-not $titleNode -or [string]::IsNullOrWhiteSpace($titleNode.InnerText)) {
                $emptyTitle += $nfo.Name
            }

            # tvshow/episodedetails 需要至少一个 default=true 的 uniqueid；season.nfo 不强制。
            if ($tag -in @('tvshow','episodedetails')) {
                $uidNodes = $xml.DocumentElement.SelectNodes('uniqueid')
                $hasDefault = $false
                foreach ($uid in $uidNodes) {
                    if ($uid.GetAttribute('default') -eq 'true') { $hasDefault = $true; break }
                }
                if ($hasDefault) { $hasUniqueidDefault++ }
                else { $warnings += "$($nfo.Name): 缺少 default=true 的 <uniqueid>" }
            }
        }

        # fileinfo 保留检查
        $fiNode = $xml.DocumentElement.SelectSingleNode('fileinfo')
        if ($fiNode) { $hasFileinfo++ }

        # episode/season 编号合理性检查
        if ($tag -eq 'episodedetails') {
            $sNode = $xml.DocumentElement.SelectSingleNode('season')
            $eNode = $xml.DocumentElement.SelectSingleNode('episode')
            if ($sNode -and $eNode) {
                $s = [int]$sNode.InnerText
                $e = [int]$eNode.InnerText
                if ($s -gt 50) { $warnings += "$($nfo.Name): season=$s 可能异常" }
                if ($e -gt 200) { $warnings += "$($nfo.Name): episode=$e 可能异常" }
            }
        }

    } catch {
        $bad += @{ file = $nfo.Name; error = $_.Exception.Message }
    }
}

# --- 对比媒体文件数 ---

$mediaCount = $null
if ($ScanJson -and (Test-Path -LiteralPath $ScanJson)) {
    $scanData = Get-Content -LiteralPath $ScanJson -Encoding UTF8 | ConvertFrom-Json
    $mediaCount = $scanData.stats.total_media
    $epNfoCount = if ($counts.ContainsKey('episodedetails')) { [int]$counts['episodedetails'] } else { 0 }
    if ($mediaCount -ne $epNfoCount) {
        $warnings += "媒体文件 ($mediaCount) ≠ episode NFO ($epNfoCount)"
    }
}

# --- 输出报告 ---

Write-Host "`n=== 根标签统计 ==="
$counts.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host "  <$($_.Key)>: $($_.Value)"
}

Write-Host "`n=== 结构检查 ==="
Write-Host "  含 <fileinfo>: $hasFileinfo"
if ($Strict) {
    Write-Host "  含 default=true <uniqueid>: $hasUniqueidDefault"
    if ($emptyTitle.Count -gt 0) {
        Write-Host "  空 <title>: $($emptyTitle.Count) 个 — $($emptyTitle -join ', ')" -ForegroundColor Yellow
    }
}
if ($null -ne $mediaCount) {
    Write-Host "  媒体文件总数: $mediaCount"
    $epNfoCount = if ($counts.ContainsKey('episodedetails')) { [int]$counts['episodedetails'] } else { 0 }
    Write-Host "  Episode NFO 总数: $epNfoCount"
}

if ($bad.Count -gt 0) {
    Write-Host "`n=== XML 解析失败 ($($bad.Count)) ===" -ForegroundColor Red
    foreach ($b in $bad) {
        Write-Host "  $($b.file): $($b.error)" -ForegroundColor Red
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "`n=== 警告 ($($warnings.Count)) ===" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  $w" -ForegroundColor Yellow
    }
}

# 汇总
$status = "通过"
if ($bad.Count -gt 0) { $status = "失败 ($($bad.Count) 个 XML 错误)" }
elseif ($warnings.Count -gt 0) { $status = "通过（$($warnings.Count) 个警告）" }

Write-Host "`n验证结果: $status"

# 输出机器可读的 JSON
$result = @{
    status       = if ($bad.Count -gt 0) { 'failed' } elseif ($warnings.Count -gt 0) { 'pass_with_warnings' } else { 'pass' }
    nfo_count    = $nfos.Count
    tag_counts   = $counts
    has_fileinfo = $hasFileinfo
    xml_errors   = $bad
    warnings     = $warnings
    media_count  = $mediaCount
}
$result | ConvertTo-Json -Depth 3 -Compress
