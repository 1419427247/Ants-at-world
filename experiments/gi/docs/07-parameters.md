# 2D GI 参数调优指南

> 版本: 1.0 | 更新日期: 2026-06-24

本文档整理 Godot 4 的 2D GI 系统中各 Compute Pass 的可调参数。所有“代码默认值”均来自 `experiments/gi/` 目录下各 `*_pass.gd` 脚本中的 `@export` 声明，已与代码核对一致（修正了早期 `GI_ANALYSIS.md` 中的旧值）。

> **说明**：`gi.tscn` 场景中可能对部分参数进行覆盖。如未覆盖，运行时使用代码默认值。

---

## RaymarchPass（`raymarch_pass.gd`）

距离场加速光线步进，收集直接光照。

| 参数名 | 数据类型 | 代码默认值 | 推荐范围 | 说明 |
|--------|----------|------------|----------|------|
| `raymarch_num_samples` | `int` | 4 | 4–16 | 每像素光线数。接入 `IndirectPass` 后可降至 4；接入时间累积后低采样+高累积更优 |
| `raymarch_attenuation` | `float` | 3.0 | 1.0–5.0 | 衰减系数，越大光衰减越快，场景越暗 |
| `raymarch_max_distance` | `float` | 0.8 | 0.3–0.9 | 最大搜索距离（归一化 0–1），降低可提升性能但减少远处光照 |
| `raymarch_max_steps` | `int` | 32 | 16–64 | 最大步进次数，距离场加速下 32 步通常足够 |
| `raymarch_emissive_threshold` | `float` | 0.01 | 0.01–1.0 | 发光阈值，任意通道 ≥ 此值视为发光体（纯白=1.0，HDR 可更大） |
| `raymarch_step_safety` | `float` | 0.8 | 0.5–0.95 | 步进安全系数，<1.0 防止步进越过薄壁导致漏光 |
| `raymarch_rotation_offset` | `float` | 0.0 | 0–2π | 射线初始旋转偏移（弧度），控制所有射线整体旋转的起始角度 |
| `raymarch_rotation_speed` | `float` | 0.0 | 0–2.0 | 旋转速度（弧度/秒），每帧自动累加到 `rotation_offset`，利用视觉暂留产生动态万花筒/流光效果，0=静止 |

---

## AOPass（`ao_pass.gd`）

距离场引导采样计算环境光遮蔽。

| 参数名 | 数据类型 | 代码默认值 | 推荐范围 | 说明 |
|--------|----------|------------|----------|------|
| `ao_num_samples` | `int` | 8 | 8–32 | 每像素采样点数，接入 `TemporalPass` 后可保持 8 |
| `ao_radius` | `float` | 0.05 | 0.02–0.1 | 采样半径（归一化 0–1），越大遮蔽范围越广但性能越低 |
| `ao_intensity` | `float` | 1.0 | 0.5–2.0 | 遮蔽强度系数，越大越暗 |
| `ao_falloff` | `float` | 1.0 | 0.5–2.0 | 遮蔽衰减指数 |
| `ao_bias` | `float` | 0.01 | 0.005–0.02 | 高度偏移，防止平面自遮挡 |
| `ao_df_guide_weight` | `float` | 0.5 | 0.0–1.0 | 距离场引导权重，0=纯黄金角度分布，1=纯距离场方向引导 |

---

## TemporalPass（`temporal_pass.gd`）

帧间指数移动平均（EMA），等效数千次采样。

| 参数名 | 数据类型 | 代码默认值 | 推荐范围 | 说明 |
|--------|----------|------------|----------|------|
| `temporal_blend_factor` | `float` | 0.1 | 0.05–0.3 | 当前帧混合权重。越低越平滑但延迟越大；首帧自动设为 1.0 直接用当前帧 |

---

## BlurPass（`blur_pass.gd`）

可分离高斯模糊，`BlurH`（水平）与 `BlurV`（垂直）串联替代 `ATrousPass`。

| 参数名 | 数据类型 | 代码默认值 | 推荐范围 | 说明 |
|--------|----------|------------|----------|------|
| `blur_radius` | `int` | 4 | 2–8 | 模糊核半径（像素） |
| `blur_sigma` | `float` | 3.0 | 1.0–5.0 | 高斯标准差，越大模糊越强 |
| `blur_r` | `bool` | `true` | — | 是否模糊 R 通道 |
| `blur_g` | `bool` | `true` | — | 是否模糊 G 通道 |
| `blur_b` | `bool` | `true` | — | 是否模糊 B 通道 |
| `blur_a` | `bool` | `false` | — | 是否模糊 A 通道 |
| `blur_direction` | `int` | 0 | 0–1 | 模糊方向：0=水平，1=垂直。`BlurH` 用 0，`BlurV` 用 1 |

---

## DirectionalLightPass（`directional_light_pass.gd`）

沿固定方向投射平行光，带高度场阴影。

| 参数名 | 数据类型 | 代码默认值 | 推荐范围 | 说明 |
|--------|----------|------------|----------|------|
| `light_direction` | `Vector2` | `Vector2(-1.0, 0.0)` | 任意归一化向量 | 平行光传播方向（2D 归一化方向），如 `(-1, 0)` = 从右照来 |
| `light_height` | `float` | 5.0 | 1.0–20.0 | 平行光高度（类似太阳仰角），越高越不容易被遮挡 |
| `light_brightness` | `float` | 1.0 | 0.0–3.0 | 亮度（R 通道明暗值，单通道灰度平行光） |
| `light_max_distance` | `float` | 0.8 | 0.3–0.9 | 最大搜索距离（归一化 0–1） |
| `light_step_safety` | `float` | 0.8 | 0.5–0.95 | 步进安全系数 |
| `light_max_steps` | `int` | 32 | 16–64 | 最大步进次数 |

---

## SeedPass（`seed_pass.gd`）

初始化 Jump Flood 种子，固体 UV 写入 RG，空区 UV 写入 BA；含形态学腐蚀使距离场从物体内部开始计算。

| 参数名 | 数据类型 | 代码默认值 | 推荐范围 | 说明 |
|--------|----------|------------|----------|------|
| `seed_erosion_radius` | `int` | 1 | 0–3 | 腐蚀半径（像素单位，1=3×3 核内缩 1 圈），使障碍物/光源整体内缩 |

---

## NormalPass（`normal_pass.gd`）

从场景纹理 Alpha 通道计算障碍物表面法线（Sobel 算子）。

| 参数名 | 数据类型 | 代码默认值 | 推荐范围 | 说明 |
|--------|----------|------------|----------|------|
| `normal_blur_radius` | `int` | 1 | 1–2 | Sobel 采样半径，1=3×3 核，2=5×5 核，越大法线越平滑 |

---

## 调优场景

以下为四种典型调优场景的推荐参数组合。所有数值均基于上述代码默认值调整，可根据实际场景进一步微调。

### 1. 高质量模式（高采样 + 高累积）

适用于静态或慢速场景，追求最佳视觉质量。代价是较高的 GPU 开销。

| Pass | 参数 | 推荐值 | 说明 |
|------|------|--------|------|
| RaymarchPass | `raymarch_num_samples` | 16 | 高光线数，配合间接光获得丰富反弹 |
| RaymarchPass | `raymarch_attenuation` | 3.0 | 保持默认衰减 |
| RaymarchPass | `raymarch_max_distance` | 0.9 | 扩大搜索范围，捕获远处光照 |
| RaymarchPass | `raymarch_max_steps` | 64 | 提高步进精度 |
| RaymarchPass | `raymarch_rotation_speed` | 0.0 | 静止场景关闭旋转，依赖时间累积降噪 |
| AOPass | `ao_num_samples` | 32 | 高 AO 采样，遮蔽更精细 |
| AOPass | `ao_radius` | 0.08 | 扩大遮蔽范围 |
| AOPass | `ao_df_guide_weight` | 0.7 | 偏向距离场引导，提升复杂几何精度 |
| TemporalPass | `temporal_blend_factor` | 0.05 | 低混合权重，最大程度平滑噪声 |
| BlurPass | `blur_radius` | 4 | 保持默认 |
| BlurPass | `blur_sigma` | 2.0 | 适度降低模糊强度，避免过度模糊 |
| NormalPass | `normal_blur_radius` | 2 | 5×5 核，法线更平滑 |

### 2. 性能模式（低采样 + 低分辨率）

适用于移动端或低端设备，优先保证帧率。依赖时间累积与模糊恢复质量。

| Pass | 参数 | 推荐值 | 说明 |
|------|------|--------|------|
| RaymarchPass | `raymarch_num_samples` | 4 | 最低光线数，依赖时间累积补偿 |
| RaymarchPass | `raymarch_max_distance` | 0.5 | 缩小搜索范围提升性能 |
| RaymarchPass | `raymarch_max_steps` | 16 | 减少步进次数 |
| RaymarchPass | `raymarch_rotation_speed` | 0.5 | 启用旋转，低采样下等效提升覆盖 |
| AOPass | `ao_num_samples` | 8 | 最低 AO 采样 |
| AOPass | `ao_radius` | 0.03 | 缩小遮蔽范围 |
| AOPass | `ao_df_guide_weight` | 0.5 | 保持默认折中 |
| TemporalPass | `temporal_blend_factor` | 0.1 | 默认混合权重 |
| BlurPass | `blur_radius` | 6 | 增大模糊半径，强力降噪 |
| BlurPass | `blur_sigma` | 4.0 | 增大标准差，补偿低采样噪声 |
| NormalPass | `normal_blur_radius` | 1 | 3×3 核，性能优先 |
| GILightViewport | `size` | 512×512 | 降低 GI 视口分辨率（需在 `gi.tscn` 中修改） |

### 3. 万花筒效果模式（低射线 + 旋转动画）

适用于艺术化/风格化场景，利用视觉暂留产生动态流光效果。

| Pass | 参数 | 推荐值 | 说明 |
|------|------|--------|------|
| RaymarchPass | `raymarch_num_samples` | 3 | 极低光线数，制造规律性光影扭曲 |
| RaymarchPass | `raymarch_rotation_offset` | 0.0 | 从 0 起始 |
| RaymarchPass | `raymarch_rotation_speed` | 1.0 | 中等旋转速度，产生持续流光 |
| RaymarchPass | `raymarch_attenuation` | 2.0 | 降低衰减，使光影更明显 |
| RaymarchPass | `raymarch_max_distance` | 0.8 | 保持默认搜索范围 |
| TemporalPass | `temporal_blend_factor` | 0.15 | 略高混合权重，保留动态感避免过度拖尾 |
| BlurPass | `blur_radius` | 3 | 较小模糊半径，保留光影细节 |
| BlurPass | `blur_sigma` | 2.0 | 适度模糊，平衡噪声与流光清晰度 |
| AOPass | `ao_intensity` | 0.5 | 降低 AO 强度，避免遮蔽干扰流光效果 |

### 4. 调试模式（各 Pass 单独预览）

适用于开发调试，通过 `gi.tscn` 中 `GridContainer` 的 `TextureRect` 单独查看各 Pass 输出。以下参数便于暴露问题。

| Pass | 参数 | 推荐值 | 说明 |
|------|------|--------|------|
| RaymarchPass | `raymarch_num_samples` | 1 | 单条光线，便于观察单射线轨迹与噪声分布 |
| RaymarchPass | `raymarch_emissive_threshold` | 0.5 | 提高阈值，便于确认发光体识别是否正确 |
| RaymarchPass | `raymarch_step_safety` | 0.5 | 降低安全系数，便于检测漏光问题 |
| AOPass | `ao_intensity` | 2.0 | 提高强度，放大遮蔽效果便于观察 |
| AOPass | `ao_df_guide_weight` | 1.0 | 纯距离场引导，便于验证引导方向是否正确 |
| AOPass | `ao_bias` | 0.005 | 降低偏移，暴露自遮挡问题 |
| TemporalPass | `temporal_blend_factor` | 1.0 | 关闭时间累积（每帧用当前帧），便于观察原始噪声 |
| BlurPass | `blur_radius` | 0 | 关闭模糊，查看降噪前原始输出 |
| NormalPass | `normal_blur_radius` | 1 | 3×3 核，观察原始法线梯度 |
| SeedPass | `seed_erosion_radius` | 0 | 关闭腐蚀，对比腐蚀前后距离场差异 |

> **调试提示**：`gi.tscn` 的 `GridContainer` 已为每个 Pass 挂载 `TextureRect` 预览（通过 `texture_from_pass.gd`）。调试时可对照查看 `PassSeed`→`PassJF1`…`PassJF8`→`PassDF` 链路的中间结果，定位距离场异常。
