> 版本: 1.0 | 更新日期: 2026-06-24

# 2D GI 系统文档

基于 Godot 4 RenderingDevice Compute Shader 的 2D 全局光照系统。

## 快速入门

### 运行场景

1. 在 Godot 编辑器中打开 `experiments/gi/gi.tscn`
2. 按 F6 运行当前场景
3. 移动鼠标可控制发光小球（MouseBall），观察动态光照效果

### 管线概览

```
场景视口 → 种子 → 跳洪×8 → 距离场 → 光线步进 → 合成 → 屏幕
                                    ↘ 平行光 ↗
                                    ↘ AO ↗
```

核心流程：场景纹理经 Jump Flood 算法生成有向距离场，距离场加速光线步进收集直接光照，与平行光阴影、环境光遮蔽在 `gi_display.gdshader` 中合成最终画面。

### 关键概念

- **ComputePass**: 自驱动 compute shader 节点，挂载到场景树即自动执行
- **距离场 (DF)**: R=到最近异质点距离，GB=指向最近异质点的方向向量
- **兄弟链式连接**: 未指定 `primary_input` 的 Pass 自动取前一个兄弟 Pass 的输出
- **帧计数防重复**: Pass 仅在输入有新输出时执行，避免重复计算

---

## 文档索引

| 文档 | 内容 | 适用读者 |
|------|------|---------|
| [01-architecture.md](01-architecture.md) | 架构设计：ComputePass 基类、binding 布局、自驱动机制、数据流图 | 需要理解管线原理的开发者 |
| [02-pass-reference.md](02-pass-reference.md) | Pass 参考手册：全部 15 个 Pass 的参数、push constant 布局、输入输出 | 查阅特定 Pass 详情 |
| [03-shader-reference.md](03-shader-reference.md) | Shader 参考手册：全部 17 个 shader 的 binding、算法、输出格式 | 修改/编写 shader |
| [04-scene-setup.md](04-scene-setup.md) | 场景配置：gi.tscn 节点树、属性配置、添加新 Pass | 配置/扩展场景 |
| [05-optimization.md](05-optimization.md) | 优化分析：效果优化 + 性能优化（含状态标注） | 优化性能或效果 |
| [06-roadmap.md](06-roadmap.md) | 未来计划：4 个阶段的任务清单（含实现状态） | 了解开发方向 |
| [07-parameters.md](07-parameters.md) | 参数调优指南：7 个 Pass 参数表 + 4 种调优场景 | 调整视觉效果 |
| [08-troubleshooting.md](08-troubleshooting.md) | 故障排查：7 个常见错误 + 7 个 FAQ | 解决问题 |
| [CHANGELOG.md](CHANGELOG.md) | 变更日志 | 追踪文档版本 |

---

## 文件结构

```
experiments/gi/
├── docs/                        # 本文档目录
├── compute_pass.gd              # ComputePass 抽象基类
├── *_pass.gd                    # 15 个 ComputePass 子类
├── *.glsl                       # 15 个 compute shader
├── gi_display.gdshader          # 最终合成 canvas shader
├── soil.gdshader                # 泥土背景 canvas shader
├── gi.tscn                      # GI 测试场景
├── gi_element.gd                # GI 场景元素容器
├── gi_light_viewport.gd         # GI 光照视口
├── mouse_ball.gd                # 鼠标跟随测试光源
├── texture_from_pass.gd         # Pass 输出预览辅助类
└── GI_ANALYSIS.md               # 旧版分析文档（已归档，见 docs/）
```

---

## 常用操作

### 调整 GI 分辨率

修改 `GILightViewport` 节点的 `size` 属性（默认 1024×1024）。所有 Pass 自动适配。

### 启用降噪链路

当前 Composite 的 `gi_texture` 取自 `PassRM`（未降噪）。如需接入降噪：

1. 选中 `Composite` 节点
2. 将 `pass_gi` 属性从 `PassRM` 改为 `BlurV`
3. 降噪链路: PassRM → PassTemporal → BlurH → BlurV → Composite

### 万花筒效果

1. 选中 `PassRM` 节点
2. 设置 `raymarch_num_samples = 3`（少量射线）
3. 设置 `raymarch_rotation_speed = 1.0`（弧度/秒）
4. 运行场景，观察动态光影扭曲

### 查看中间结果

GridContainer 中已为每个 Pass 添加预览 TextureRect，运行时自动显示中间输出。

---

## 技术栈

- **引擎**: Godot 4.x
- **API**: RenderingDevice (Vulkan)
- **着色器**: GLSL compute shader (#version 450) + GDShader (canvas_item)
- **算法**: Jump Flood Algorithm, 有向距离场, 光线步进, 时间累积降噪, 可分离高斯模糊
