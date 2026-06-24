> 版本: 1.0 | 更新日期: 2026-06-24

# 变更日志

## [1.0] - 2026-06-24

### 新增

- 创建完整文档体系（9 个文件），替代旧版单文件 `GI_ANALYSIS.md`
- **README.md**: 入口与索引，含快速入门、文件结构、常用操作
- **01-architecture.md**: 架构设计，含 ComputePass 基类详解、Mermaid 数据流图、术语表
- **02-pass-reference.md**: Pass 参考手册，覆盖全部 15 个 Pass（10 个已使用 + 5 个备用），含 push constant 内存布局表
- **03-shader-reference.md**: Shader 参考手册，覆盖全部 17 个 shader
- **04-scene-setup.md**: 场景配置，含完整节点树、属性配置、扩展指南
- **05-optimization.md**: 优化分析，含状态标注（已实现/部分实现/未实现）
- **06-roadmap.md**: 未来计划，4 个阶段 30 项任务，含实现状态
- **07-parameters.md**: 参数调优指南，7 个 Pass 参数表 + 4 种调优场景
- **08-troubleshooting.md**: 故障排查，7 个常见错误 + 7 个 FAQ
- **CHANGELOG.md**: 本文件

### 修正（相对于旧版 GI_ANALYSIS.md）

- **数据流图**: 用 Mermaid 替代 ASCII，反映实际场景连线
- **降噪方式**: ATrousPass×3 → BlurH+BlurV（可分离高斯模糊）
- **合成方式**: CompositePass → gi_display.gdshader（canvas_item shader）
- **参数默认值**: raymarch_num_samples 8→4, ao_num_samples 16→8, temporal_blend_factor 0.2→0.1
- **新增 Pass**: 补充 NormalPass、ScalePassHalf/Quarter 文档
- **新增参数**: 补充 raymarch_rotation_offset/rotation_speed 文档
- **备用 Pass**: 标注 IndirectPass/ATrousPass/CompositePass/DenoisePass/SharpenPass 为"已实现未使用"
- **已知问题**: 记录 Composite 的 gi_texture 取自 PassRM 而非降噪链路

### 归档

- `GI_ANALYSIS.md` 保留为历史参考，内容已被 docs/ 体系取代
