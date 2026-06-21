# 参与开发

## 开发环境

安装 MoonBit 稳定工具链，克隆仓库后运行：

```bash
moon check
moon test
moon run cmd/main
```

## 提交要求

1. 一个提交处理一个明确问题，提交信息说明行为变化。
2. 公共接口变化同时更新测试、README 或 `docs/API.md`。
3. 不提交 `_build`、缓存、预览文件和编辑器临时文件。
4. 新功能应覆盖成功路径、拒绝路径和边界值。
5. 不通过真实 sleep 测试时间行为，使用显式时间或 `VirtualClock`。

提交前执行：

```bash
moon info
moon fmt
moon check --warn-list +73
moon test
moon run cmd/main
```

## 工单与合并请求

功能开发先建立工单，说明问题、接口范围和验收方式。功能分支使用简短名称，例如 `feature/latency-export`。合并请求应列出已运行的命令和可能影响的公共接口。

## 兼容性

在 `0.x` 阶段仍可能调整接口，但应在 `CHANGELOG.md` 中记录。已发布函数若需替换，优先提供迁移说明，不直接静默改变语义。
