# 发布检查

## 代码

- [x] `moon info` 已更新公开接口文件。
- [x] `moon fmt --check` 无未格式化文件。
- [x] `moon check --deny-warn --target all` 无错误和警告。
- [x] `moon test --deny-warn --target all` 全部通过。
- [x] `moon build --target all` 全部通过。
- [x] `moon run cmd/main` 输出完整示例。
- [x] `moon coverage analyze` 已生成覆盖信息（985/1118 行，约 88.1%）。

## 仓库

- [x] `README.md` 是普通文件，模式为 `100644`。
- [x] 不包含 `_build`、缓存、预览文件和本地凭据。
- [x] GitLink 与 GitHub 的最终文件树一致。
- [x] 两个平台各自只显示仓库创建者一名提交作者。
- [x] 每个平台至少包含 13 次有实际内容变化的提交。
- [ ] 公开工单与合并请求能够反映后续开发过程；当前以提交记录、CHANGELOG 和 ROADMAP 作为公开开发记录。

## 报名材料

- [x] 项目名称、简介和仓库链接一致。
- [x] GitLink 与 GitHub 链接可公开访问。
- [x] PDF 恰好一页，文字无乱码、截断和重叠。
- [x] PDF 页面正文占用约 80% 至 90% 高度。
- [x] DOCX 与 PDF 的项目事实一致。
- [x] Mooncakes 包 `liying-han/moonresilience@0.2.0` 已发布。
