# User Correction Format

## CSV 覆盖表格式

用于存储用户修正的映射。表头：

```csv
season,episode,local_path,source_id,original_title,corrected_title,original_summary,corrected_summary,reviewed_by,reviewed_at
```

- `season`/`episode`: 从文件名解析的结构位置（不是源位置）
- `source_id`: 在线源的集合 ID
- `original_*`: 自动生成的值
- `corrected_*`: 用户修正后的值（为空表示用户接受原始值）
- `reviewed_by`: 审核人标识

## JSON 替换表

用于人名/术语归一化：

```json
{
  "replacements": [
    {"from": "Lum", "to": "拉姆"},
    {"from": "Ataru", "to": "阿当"},
    {"from": "Mendou", "to": "面堂"}
  ]
}
```

步 5 和步 7 之间必须全文扫描确认无残留旧名。

## HTML 审核页规范

当 `needs_review=true` 的行数 > 0 时必须生成。

**功能要求**：

- 搜索/筛选控件：按 `needs_review`、匹配分数、来源、季、标题文本
- 本地文件和生成元数据与源元数据并排对比
- 稳定行 ID：使用 `season` + `episode` + `local_path` + `source_id`，不依赖显示顺序
- 修正界面：每条可编辑标题和简介，可标记 "已审核-无修改"

**导出**：

- 审核完成的修正导出为 CSV/JSON
- 保留原始值、修正值、最终值的区分
- "无修改" 是一个明确的审核决定（行被标记为不确定但用户认可自动生成值）
