# 参赛版本验证记录

验证日期：2026-08-16

## 项目规模

- 有效 MoonBit 代码：约 4865 行（27 个 `.mbt` 文件）。统计口径为仓库中非构建目录的 MoonBit 源码行，包含实现与测试。
- 自动化测试：110 项。
- 核心依赖：无第三方 MoonBit 包。
- 开发提交：18 个按功能阶段拆分的有意义提交；GitHub 与 GitLink 默认分支均为 `master`，两边文件树保持一致。

## 本地验证

以下命令均在仓库根目录执行：

```text
moon info
moon fmt
moon check --deny-warn --target all
moon test --deny-warn --target all
moon build --target all
moon run cmd/main
moon coverage analyze
```

`moon check --deny-warn --target all`、`moon test --deny-warn --target all` 和 `moon build --target all` 均通过；测试结果为 110 passed、0 failed。CLI 完成短暂故障恢复和固定窗口限流示例。

覆盖率检查生成 985/1118 行覆盖（约 88.1%）。未覆盖部分主要是 CLI 主函数、部分策略组合分支和内部清理辅助函数，不影响当前功能测试通过。

## 材料验证

- `MoonResilience项目申报书.pdf` 为 A4 单页。
- PDF 包含 GitLink 与 GitHub 的可点击链接。
- PDF 渲染图无乱码、截断和重叠。
- 非白色内容像素高度约占整页 79.9%，保留底部安全空白。
- PDF 和 DOCX 均不包含旧项目名称。

## 仓库检查

- `README.md` 为普通文件，Git 模式 `100644`。
- 仓库不跟踪 `_build`、`tmp`、`__pycache__` 和预览图片。
- GitLink 与 GitHub 最终文件树一致；两边历史分别使用对应平台创建者身份生成。
- Mooncakes 包 `liying-han/moonresilience` 版本 `0.2.0` 已发布。
