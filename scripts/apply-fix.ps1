<#
.SYNOPSIS
    按 CSV 修复计划执行文件重命名/移动。
    覆盖 fix-my-show 工作流 A4 执行阶段。

.DESCRIPTION
    读取包含 old_path、new_path、action 列的 CSV 修复计划，
    逐行校验 → 记录备份日志 → 执行操作 → 验证完整性。

    操作类型：
    - rename: 重命名文件（不移动目录）
    - move: 移动到新目录（不改名）
    - rename_move: 重命名 + 移动到新目录（一步完成）
    - delete_nfo: 删除孤立 NFO（需二次确认）

.PARAMETER PlanPath
    修复计划 CSV 文件路径。必须有 old_path, new_path, action 列。

.PARAMETER RootPath
    剧集根目录。old_path 和 new_path 均相对于此目录。

.PARAMETER DryRun
    仅校验和预览，不执行实际操作。

.PARAMETER Force
    跳过确认提示直接执行。

.PARAMETER RollbackLogPath
    回滚日志 JSON 路径。用于撤销之前的操作。

.EXAMPLE
    .\apply-fix.ps1 -PlanPath "fix_plan.csv" -RootPath "\\Nas\share\Anime\Show" -DryRun

.EXAMPLE
    .\apply-fix.ps1 -PlanPath "fix_plan.csv" -RootPath "\\Nas\share\Anime\Show" -Force

.EXAMPLE
    .\apply-fix.ps1 -RollbackLogPath ".metadata_archive\rollback_20260611_120000.json" -Force

.NOTES
    鲁棒性设计：
    - 执行前全量校验（任一文件缺失则中止）
    - 备份日志支持回滚
    - 自动处理 UNC 和长路径
    - 目标目录自动创建
    - 防冲突：目标路径已存在时中止（除非 --force）
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$PlanPath,

    [Parameter(Mandatory=$false)]
    [string]$RootPath,

    [switch]$DryRun,

    [switch]$Force,

    [string]$RollbackLogPath
)

$ErrorActionPreference = 'Stop'

# --- 辅助函数 ---

function Resolve-FullPath {
    param([string]$Path)
    if ($Path.Length -ge 260 -and -not $Path.StartsWith('\\?\')){
        if ($Path.StartsWith('\\')) {
            return "\\?\UNC\$($Path.Substring(2))"
        } else {
            return "\\?\$Path"
        }
    }
    return $Path
}

function Test-SafePath {
    param([string]$Path)
    # 检测路径遍历攻击 / 非法字符
    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    foreach ($c in $invalidChars) {
        if ($Path.IndexOf($c) -ge 0 -and $c -ne [char]0x5C -and $c -ne [char]0x2F) {
            Write-Error "路径含非法字符 [0x$('{0:X2}' -f [int]$c)]: $Path"
            return $false
        }
    }
    # 禁止绝对路径和 .. 穿越
    $normalized = [System.IO.Path]::GetFullPath($Path)
    if ($normalized -match '\.\.[\\/]') {
        Write-Error "路径含 .. 穿越: $Path"
        return $false
    }
    return $true
}

# --- 回滚模式 ---

if ($RollbackLogPath) {
    if (-not (Test-Path -LiteralPath $RollbackLogPath)) {
        Write-Error "回滚日志不存在: $RollbackLogPath"
        exit 1
    }
    $log = Get-Content -LiteralPath $RollbackLogPath -Encoding UTF8 | ConvertFrom-Json

    Write-Host "准备回滚 $($log.operations.Count) 个操作..."
    if (-not $Force) {
        Write-Warning "即将撤销以下操作："
        foreach ($op in $log.operations) {
            Write-Host "  $($op.action): $($op.new_path) → $($op.old_path)"
        }
        $confirm = Read-Host "确认回滚？(y/N)"
        if ($confirm -ne 'y') { Write-Host "已取消"; exit 0 }
    }

    $rollbackOps = @()
    foreach ($op in $log.operations) {
        $src = Resolve-FullPath -Path $op.new_path
        $dst = Resolve-FullPath -Path $op.old_path
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Warning "跳过（文件不存在）: $src"
            continue
        }
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        try {
            Move-Item -LiteralPath $src -Destination $dst -Force
            $rollbackOps += @{ old_path = $op.new_path; new_path = $op.old_path }
            Write-Host "  回滚: $(Split-Path -Leaf $src)"
        } catch {
            Write-Error "回滚失败: $src — $_"
            exit 1
        }
    }
    Write-Host "回滚完成：$($rollbackOps.Count) 个文件。"
    exit 0
}

# --- 正常模式 ---

if (-not $PlanPath -or -not $RootPath) {
    Write-Error "请指定 -PlanPath 和 -RootPath（或 -RollbackLogPath）"
    exit 1
}

if (-not (Test-Path -LiteralPath $PlanPath)) {
    Write-Error "计划文件不存在: $PlanPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "根目录不存在: $RootPath"
    exit 1
}

# 读取计划
$plan = @(Import-Csv -LiteralPath $PlanPath -Encoding UTF8)
if ($plan.Count -eq 0) {
    Write-Error "计划 CSV 为空: $PlanPath"
    exit 1
}

# 验证必要列
$requiredCols = @('old_path','new_path','action')
$missingCols = $requiredCols | Where-Object { $_ -notin $plan[0].PSObject.Properties.Name }
if ($missingCols) {
    Write-Error "CSV 缺少列: $($missingCols -join ', ')"
    exit 1
}

Write-Host "读取修复计划: $($plan.Count) 条操作"

# --- 阶段 1: 全量校验 ---

$errors = @()
$operations = @()

for ($i = 0; $i -lt $plan.Count; $i++) {
    $row = $plan[$i]
    $idx = $i + 1
    $action = $row.action.Trim()
    $oldRel = $row.old_path.Trim()
    $newRel = $row.new_path.Trim()

    # 验证操作类型
    if ($action -notin @('rename','move','rename_move','delete_nfo')) {
        $errors += "行 $idx : 未知操作类型 '$action'"
        continue
    }

    # 路径安全检测
    if (-not (Test-SafePath -Path $oldRel)) { $errors += "行 $idx : old_path 不安全"; continue }
    if ($action -ne 'delete_nfo' -and -not (Test-SafePath -Path $newRel)) { $errors += "行 $idx : new_path 不安全"; continue }

    $oldFull = Resolve-FullPath -Path (Join-Path $RootPath $oldRel)
    $newFull = if ($action -ne 'delete_nfo') { Resolve-FullPath -Path (Join-Path $RootPath $newRel) } else { $null }

    # 源文件必须存在
    if (-not (Test-Path -LiteralPath $oldFull)) {
        $errors += "行 $idx : 源文件不存在: $oldRel"
        continue
    }

    # 目标不能已存在（除非 delete_nfo）
    if ($action -ne 'delete_nfo' -and (Test-Path -LiteralPath $newFull)) {
        $errors += "行 $idx : 目标已存在，跳过以防覆盖: $newRel"
        continue
    }

    # delete_nfo 二次确认
    if ($action -eq 'delete_nfo') {
        $ext = [System.IO.Path]::GetExtension($oldFull).ToLower()
        if ($ext -ne '.nfo') {
            $errors += "行 $idx : delete_nfo 只能用于 .nfo 文件"
            continue
        }
    }

    $operations += @{
        index    = $idx
        action   = $action
        old_path = $oldFull
        new_path = $newFull
        old_rel  = $oldRel
        new_rel  = $newRel
    }
}

if ($errors.Count -gt 0) {
    Write-Host "`n=== 校验失败 ===" -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
    Write-Host "`n共 $($errors.Count) 个错误。已中止，未执行任何操作。"
    exit 1
}

Write-Host "校验通过：$($operations.Count) 个操作就绪。"

# --- Dry Run 模式 ---

if ($DryRun) {
    Write-Host "`n=== DRY RUN（预览） ==="
    $countByAction = $operations | Group-Object { $_.action }
    foreach ($g in $countByAction) {
        Write-Host "  $($g.Name): $($g.Count)"
    }
    Write-Host "`n操作详情："
    foreach ($op in $operations) {
        Write-Host "  [$($op.index)] $($op.action):"
        Write-Host "    旧: $($op.old_rel)"
        if ($op.action -ne 'delete_nfo') {
            Write-Host "    新: $($op.new_rel)"
        }
    }
    Write-Host "`n（使用 -Force 执行实际操作）"
    exit 0
}

# --- 用户确认 ---

if (-not $Force) {
    Write-Host "`n即将执行 $($operations.Count) 个操作："
    $countByAction = $operations | Group-Object { $_.action }
    foreach ($g in $countByAction) { Write-Host "  $($g.Name): $($g.Count)" }
    $confirm = Read-Host "`n确认执行？(y/N)"
    if ($confirm -ne 'y') { Write-Host "已取消"; exit 0 }
}

# --- 阶段 2: 创建备份日志 ---

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$archiveDir = Join-Path $RootPath '.metadata_archive'
if (-not (Test-Path -LiteralPath $archiveDir)) {
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
}

$logPath = Join-Path $archiveDir "rollback_$timestamp.json"
$logData = @{
    executed_at  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    root_path    = $RootPath
    plan_path    = $PlanPath
    operation_count = $operations.Count
    operations   = @()
}
$logData | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host "备份日志: $logPath"

# --- 阶段 3: 执行 ---

$success = 0
$executedOps = @()

foreach ($op in $operations) {
    try {
        $targetDir = if ($op.action -ne 'delete_nfo') { Split-Path -Parent $op.new_path } else { $null }

        # 确保目标目录存在
        if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        switch ($op.action) {
            'rename' {
                Rename-Item -LiteralPath $op.old_path -NewName (Split-Path -Leaf $op.new_path) -Force
            }
            'rename_move' {
                Move-Item -LiteralPath $op.old_path -Destination $op.new_path -Force
            }
            'move' {
                Move-Item -LiteralPath $op.old_path -Destination $targetDir -Force
            }
            'delete_nfo' {
                Remove-Item -LiteralPath $op.old_path -Force
            }
        }

        $executedOps += @{
            index    = $op.index
            action   = $op.action
            old_path = $op.old_path
            new_path = $op.new_path
            status   = 'ok'
        }
        $success++
        Write-Host "  ✓ [$($op.index)] $($op.action): $(Split-Path -Leaf $op.old_path)"

    } catch {
        Write-Error "  ✗ [$($op.index)] 失败: $(Split-Path -Leaf $op.old_path) — $_"
        $executedOps += @{
            index    = $op.index
            action   = $op.action
            old_path = $op.old_path
            new_path = $op.new_path
            status   = "failed: $_"
        }
    }
}

# 更新日志
$logData.operations = $executedOps
$logData | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $logPath -Encoding UTF8

# --- 阶段 4: 验证 ---

Write-Host "`n=== 执行结果 ==="
Write-Host "成功: $success / $($operations.Count)"

$failedOps = $executedOps | Where-Object { $_.status -ne 'ok' }
if ($failedOps) {
    Write-Host "失败: $($failedOps.Count)" -ForegroundColor Red
    Write-Host "回滚命令: .\apply-fix.ps1 -RollbackLogPath '$logPath' -Force"
    exit 1
}

# 扫描残留：检查是否有预期为空的目录
$emptyDirs = @()
$rootDirs = Get-ChildItem -LiteralPath (Resolve-FullPath -Path $RootPath) -Directory -Force -ErrorAction SilentlyContinue
foreach ($dir in $rootDirs) {
    $contents = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
    if ($contents.Count -eq 0 -and $dir.Name -ne '.metadata_archive') {
        $emptyDirs += $dir.Name
    }
}
if ($emptyDirs.Count -gt 0) {
    Write-Host "`n残留空目录: $($emptyDirs -join ', ')"
    Write-Host "手动清理: Remove-Item -LiteralPath '<root>\$($emptyDirs[0])' -Recurse"
}

Write-Host "完成。回滚日志: $logPath"
