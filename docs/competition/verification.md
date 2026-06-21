# 参赛版本验证记录

验证日期：2026-06-21

## 项目规模

- 有效 MoonBit 代码：4523 行。统计口径为非空且非 `///` 文档注释行，包含实现与测试。
- 自动化测试：100 项。
- 核心依赖：无第三方 MoonBit 包。
- 开发提交：13 个按功能阶段拆分的提交。

## 本地验证

以下命令均在仓库根目录执行：

```text
moon info
moon fmt
moon check --warn-list +73
moon test
moon run cmd/main
moon coverage analyze
```

`moon test` 结果为 100 passed、0 failed。CLI 完成短暂故障恢复和固定窗口限流示例。

## 材料验证

- `MoonResilience项目申报书.pdf` 为 A4 单页。
- PDF 包含 GitLink 与 GitHub 的可点击链接。
- PDF 渲染图无乱码、截断和重叠。
- 非白色内容像素高度约占整页 79.9%，保留底部安全空白。
- PDF 和 DOCX 均不包含旧项目名称。

## 仓库检查

- `README.md` 为普通文件，Git 模式 `100644`。
- 仓库不跟踪 `_build`、`tmp`、`__pycache__` 和预览图片。
- GitLink 与 GitHub 最终文件树应一致；两边历史分别使用平台创建者身份生成。
