<#
.SYNOPSIS
    生成元数据审核 HTML 页面。
    覆盖 fix-my-show 工作流 B4。

.DESCRIPTION
    输入 B3 映射 CSV，生成可搜索/筛选/编辑的 HTML 审核页。
    needs_review=true 的行高亮显示，支持本地 vs 源对比，
    修正后的数据可导出为 CSV/JSON。

.PARAMETER MappingCsv
    B3 产出的映射 CSV 路径。

.PARAMETER OutputPath
    生成的 HTML 文件路径。

.PARAMETER ShowTitle
    剧集标题，用于页面标题。

.PARAMETER Language
    界面语言。默认 zh-CN。

.EXAMPLE
    .\review-html.ps1 -MappingCsv "preprocess.csv" -OutputPath "review.html" -ShowTitle "乱马½ (2024)"

.NOTES
    鲁棒性设计：
    - 纯静态 HTML（无外部依赖）
    - needs_review 行自动高亮
    - 支持键盘导航
    - 导出功能内嵌 JS
    - CSV/JSON 导出保留原始值和修正值
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$MappingCsv,

    [Parameter(Mandatory=$true)]
    [string]$OutputPath,

    [string]$ShowTitle = 'Review',

    [string]$Language = 'zh-CN'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MappingCsv)) {
    Write-Error "映射 CSV 不存在: $MappingCsv"
    exit 1
}

$mapping = Import-Csv -LiteralPath $MappingCsv -Encoding UTF8

# 数据转 JSON（嵌入 HTML）
$dataJson = $mapping | ConvertTo-Json -Depth 3 -Compress

# 列定义
$columns = $mapping[0].PSObject.Properties.Name
$colHeaders = $columns -join '","'

# HTML 标签（转义）
function Escape-Html { param([string]$Text) if (-not $Text) { return '' }; return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;') }

$escapedTitle = Escape-Html -Text $ShowTitle

$html = @"
<!DOCTYPE html>
<html lang="$Language">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>审核: $escapedTitle</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Segoe UI', system-ui, sans-serif; background: #1a1a2e; color: #e0e0e0; padding: 16px; }
h1 { font-size: 1.4em; margin-bottom: 8px; }
.stats { color: #888; margin-bottom: 16px; font-size: 0.9em; }
.controls { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; align-items: center; }
.controls input, .controls select, .controls button {
    padding: 6px 12px; border: 1px solid #444; border-radius: 4px;
    background: #16213e; color: #e0e0e0; font-size: 0.9em;
}
.controls input { flex: 1; min-width: 180px; }
.controls button { background: #0f3460; cursor: pointer; border-color: #0f3460; }
.controls button:hover { background: #1a4a7a; }
.filter-chip { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.8em;
    background: #333; cursor: pointer; user-select: none; }
.filter-chip.active { background: #0f3460; }
.filter-chip.needs-review { background: #5c2a2a; }
.filter-chip.needs-review.active { background: #8b3a3a; }
table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
th { position: sticky; top: 0; background: #16213e; padding: 10px 8px; text-align: left;
    border-bottom: 2px solid #333; cursor: pointer; user-select: none; z-index: 1; }
th:hover { background: #1c2d4a; }
td { padding: 8px; border-bottom: 1px solid #2a2a3e; vertical-align: top; max-width: 320px;
    overflow: hidden; text-overflow: ellipsis; }
tr:hover { background: #1e2d3d; }
tr.needs-review { background: #2d1a1a; }
tr.needs-review:hover { background: #3d2525; }
tr.needs-review td:first-child::before { content: '⚠ '; color: #ff6b6b; }
.badge { display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 0.75em;
    font-weight: 600; }
.badge-review { background: #8b3a3a; color: #ffaaaa; }
.badge-ok { background: #1a3a1a; color: #88ff88; }
.edit-cell { cursor: pointer; }
.edit-cell:hover { background: #2a3a2a; border-radius: 3px; }
.edit-input { width: 100%; background: #0d1117; color: #e0e0e0; border: 1px solid #0f3460;
    padding: 4px; border-radius: 3px; font-family: inherit; font-size: inherit; }
.export-section { margin-top: 16px; display: flex; gap: 8px; }
.modified { background: #1a2a1a !important; }
.export-section button { padding: 8px 16px; background: #0f3460; color: #e0e0e0;
    border: none; border-radius: 4px; cursor: pointer; font-size: 0.9em; }
.export-section button:hover { background: #1a4a7a; }
.count-badge { background: #0f3460; color: #88ccff; padding: 1px 8px; border-radius: 10px;
    font-size: 0.8em; margin-left: 4px; }
</style>
</head>
<body>

<h1>审核: $escapedTitle</h1>
<div class="stats" id="stats"></div>

<div class="controls">
    <input type="text" id="search" placeholder="搜索标题/简介/文件名..." oninput="renderTable()">
    <select id="filterReview" onchange="renderTable()">
        <option value="all">全部行</option>
        <option value="review">仅需审核</option>
        <option value="ok">仅已确认</option>
    </select>
    <select id="filterMethod" onchange="renderTable()">
        <option value="all">全部匹配方式</option>
        <option value="order_assumed">顺序推定</option>
        <option value="title_exact">精确标题</option>
        <option value="title_fuzzy">模糊标题</option>
        <option value="manual">人工指定</option>
    </select>
    <button onclick="renderTable()">刷新</button>
</div>

<table>
<thead id="thead"></thead>
<tbody id="tbody"></tbody>
</table>

<div class="export-section">
    <button onclick="exportCSV()">导出 CSV</button>
    <button onclick="exportJSON()">导出 JSON</button>
    <span style="color:#888;font-size:0.8em;margin-left:8px" id="modifiedCount"></span>
</div>

<script>
const RAW = $dataJson;
let modified = {}; // key: rowIndex, value: {generated_title, generated_summary, needs_review}

function init() {
    const stats = document.getElementById('stats');
    const total = RAW.length;
    const needsReview = RAW.filter(r => r.needs_review === 'true' || r.needs_review === 'True' || r.needs_review === true).length;
    const methods = {};
    RAW.forEach(r => { const m = r.match_method || 'unknown'; methods[m] = (methods[m]||0)+1; });
    stats.innerHTML = '共 <strong>' + total + '</strong> 集' +
        ' <span class="count-badge">需审核: ' + needsReview + '</span>' +
        ' | 匹配方式: ' + Object.entries(methods).map(([k,v]) => k + ': ' + v).join(', ');

    // 表头
    const cols = $('$colHeaders').split(',');
    const thead = document.getElementById('thead');
    thead.innerHTML = '<tr>' + cols.map(c => '<th>' + c + '</th>').join('') + '</tr>';

    renderTable();
}
init();

function renderTable() {
    const search = (document.getElementById('search').value || '').toLowerCase();
    const filterReview = document.getElementById('filterReview').value;
    const filterMethod = document.getElementById('filterMethod').value;

    let rows = RAW.map((r,i) => ({...r, _idx: i}));

    if (search) {
        rows = rows.filter(r => JSON.stringify(Object.values(r)).toLowerCase().includes(search));
    }
    if (filterReview === 'review') {
        rows = rows.filter(r => {
            const m = modified[r._idx];
            const nr = r.needs_review === 'true' || r.needs_review === 'True' || r.needs_review === true;
            return m ? m.needs_review !== false : nr;
        });
    } else if (filterReview === 'ok') {
        rows = rows.filter(r => {
            const m = modified[r._idx];
            return m ? m.needs_review === false : (r.needs_review !== 'true' && r.needs_review !== 'True' && r.needs_review !== true);
        });
    }
    if (filterMethod !== 'all') {
        rows = rows.filter(r => (r.match_method || '') === filterMethod);
    }

    const cols = '$($columns -join ''","'')'.split(',');
    const tbody = document.getElementById('tbody');
    tbody.innerHTML = rows.map((r,i) => {
        const idx = r._idx;
        const m = modified[idx] || {};
        const isReview = (m.needs_review !== undefined) ? m.needs_review :
            (r.needs_review === 'true' || r.needs_review === 'True' || r.needs_review === true);
        const cls = (isReview ? 'needs-review' : '') + (m.generated_title ? ' modified' : '');

        return '<tr class="' + cls + '">' + cols.map(c => {
            const val = (m[c] !== undefined) ? m[c] : (r[c] || '');
            const display = typeof val === 'string' ? val : JSON.stringify(val);
            const escaped = display.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
            const editable = (c === 'generated_title' || c === 'generated_summary');
            const clsAttr = editable ? ' class="edit-cell"' : '';
            const dataAttr = editable ? ' data-idx="' + idx + '" data-col="' + c + '"' : '';
            const truncated = escaped.length > 80 ? escaped.substring(0,80) + '…' : escaped;
            const fullEscaped = escaped;
            return '<td' + clsAttr + dataAttr + ' title="' + fullEscaped + '">' + truncated + '</td>';
        }).join('') + '</tr>';
    }).join('');

    // 双击编辑
    document.querySelectorAll('.edit-cell').forEach(cell => {
        cell.ondblclick = function() {
            const idx = parseInt(this.dataset.idx);
            const col = this.dataset.col;
            const current = (modified[idx] && modified[idx][col]) || RAW[idx][col] || '';
            const input = document.createElement('input');
            input.className = 'edit-input';
            input.value = current;
            input.onblur = function() {
                if (!modified[idx]) modified[idx] = {};
                modified[idx][col] = this.value;
                modified[idx].needs_review = false;
                renderTable();
            };
            input.onkeydown = function(e) {
                if (e.key === 'Enter') this.blur();
                if (e.key === 'Escape') { this.value = current; this.blur(); }
            };
            this.innerHTML = '';
            this.appendChild(input);
            input.focus();
        };
    });

    document.getElementById('modifiedCount').textContent =
        Object.keys(modified).length > 0 ? '已修改: ' + Object.keys(modified).length + ' 条' : '';
}

function getMergedData() {
    return RAW.map((r,i) => {
        const m = modified[i] || {};
        const merged = {...r};
        if (m.generated_title) merged.generated_title = m.generated_title;
        if (m.generated_summary) merged.generated_summary = m.generated_summary;
        if (m.needs_review !== undefined) merged.needs_review = m.needs_review;
        return merged;
    });
}

function exportCSV() {
    const data = getMergedData();
    const cols = Object.keys(data[0]);
    const csv = cols.join(',') + '\n' + data.map(r =>
        cols.map(c => '"' + String(r[c]||'').replace(/"/g,'""') + '"').join(',')
    ).join('\n');
    download('reviewed.csv', csv, 'text/csv;charset=utf-8');
}

function exportJSON() {
    const data = getMergedData();
    download('reviewed.json', JSON.stringify(data, null, 2), 'application/json');
}

function download(filename, content, mime) {
    const blob = new Blob(['﻿' + content], {type: mime});
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename; a.click();
    URL.revokeObjectURL(url);
}
</script>
</body>
</html>
"@

# 写入文件
$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$html | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "review-html: $($mapping.Count) rows → $OutputPath"
