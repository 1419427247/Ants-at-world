> 版本: 1.0 | 更新日期: 2026-06-24

# Pass 参考手册

本文档详细描述所有 ComputePass 子类，包括导出参数、push constant 内存布局、输入输出格式。

**状态标识:**
- ✅ 场景已使用 — 在 `gi.tscn` 中实例化
- 📦 备用 — 代码完整但场景未使用

---

## 一、场景已使用的 Pass

### 1.1 ScalePass

**文件**: [scale_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/scale_pass.gd) → [scale.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/scale.glsl)
**状态**: ✅ 场景实例: ScalePassHalf, ScalePassQuarter
**作用**: 将输入纹理缩放到指定尺寸，支持双线性/bicubic 插值

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `scale_target_width` | int | 0 | 目标宽度（0=保持源宽度） |
| `scale_target_height` | int | 0 | 目标高度（0=保持源高度） |
| `scale_mode` | int | 0 | 0=双线性, 1=bicubic (Catmull-Rom) |

#### Push Constant (4 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | mode |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 源纹理（sampler2D） |
| 输出 (binding 1) | 缩放后纹理（image2D） |
| 输出尺寸 | 由 `_get_output_dimensions()` 返回目标尺寸 |
| 输出格式 | 继承源格式 |

---

### 1.2 SeedPass

**文件**: [seed_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/seed_pass.gd) → [seed.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/seed.glsl)
**状态**: ✅ 场景实例: PassSeed
**作用**: 初始化 Jump Flood 种子。固体像素写自身 UV 到 RG，空区像素写自身 UV 到 BA。带形态学腐蚀（障碍物/光源整体内缩）

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `seed_erosion_radius` | int | 1 | 腐蚀半径（像素单位，1=3×3 核内缩1圈） |

#### Push Constant (4 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | erosion_radius |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 场景纹理（sampler2D，读 alpha 判断固体/空区） |
| 输出 (binding 1) | 种子纹理（image2D） |
| 输出格式 | `RGBA16F`（RG=最近固体UV, BA=最近空区UV，哨兵 -1） |

#### 算法说明

1. 空区像素（alpha ≤ 0）: 直接输出 `vec4(-1, -1, uv)`
2. 固体像素: 3×3 邻域检查，若有空区像素则腐蚀为空区种子
3. 贴边像素（超出边界）视为空区，强制腐蚀
4. 内核固体像素: 输出 `vec4(uv, -1, -1)`

---

### 1.3 JumpFloodPass

**文件**: [jump_flood_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/jump_flood_pass.gd) → [jump_flood.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/jump_flood.glsl)
**状态**: ✅ 场景实例: PassJF1~PassJF8
**作用**: 跳洪泛洪，同时传播最近固体 UV 和最近空区 UV，3×3 邻域采样

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `jump_flood_step_divisor` | int | 2 | 步长除数（step = max(1, size/divisor)） |
| `use_square_step` | bool | true | 方形步长（取 max(step_x, step_y)）防各向异性条纹 |

#### Push Constant (8 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | step_x |
| 4 | int32 | step_y |

#### `_before_dispatch` 逻辑

```gdscript
var step = maxi(1, int(source_width) / jump_flood_step_divisor)
# 方形步长
step = maxi(step, maxi(1, int(source_height) / jump_flood_step_divisor))
```

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 前一级 JF 输出或 SeedPass 输出（sampler2D） |
| 输出 (binding 1) | 更新后的种子纹理（image2D） |
| 输出格式 | `RGBA16F` |

#### 场景配置

| 节点 | divisor | 步长 (1024px) |
|------|---------|--------------|
| PassJF1 | 2 | 512 |
| PassJF2 | 4 | 256 |
| PassJF3 | 8 | 128 |
| PassJF4 | 16 | 64 |
| PassJF5 | 32 | 32 |
| PassJF6 | 64 | 16 |
| PassJF7 | 128 | 8 |
| PassJF8 | 256 | 4 |

---

### 1.4 DistanceFieldPass

**文件**: [distance_field_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/distance_field_pass.gd) → [distance_field.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/distance_field.glsl)
**状态**: ✅ 场景实例: PassDF
**作用**: Voronoi 结果转有向距离场。固体找最近空区，空区找最近固体

#### 导出参数

无

#### Push Constant

无（0 字节）

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | JF8 输出（sampler2D，含最近固体UV和最近空区UV） |
| 输出 (binding 1) | 距离场（image2D） |
| 输出格式 | `RGBA16F` |

#### 输出含义

| 通道 | 含义 |
|------|------|
| R | 到最近异质点的距离（归一化 0-1） |
| GB | 指向最近异质点的方向向量（归一化） |
| A | 1.0 |

**注意**: GB 是方向向量，不是 UV 坐标。

---

### 1.5 RaymarchPass

**文件**: [raymarch_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/raymarch_pass.gd) → [raymarch.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/raymarch.glsl)
**状态**: ✅ 场景实例: PassRM
**作用**: 距离场加速光线步进，收集直接光照（可见发光体）。均匀角度分布 + 旋转偏移

#### 导出参数

| 参数名 | 类型 | 默认值 | 场景值 | 说明 |
|--------|------|--------|--------|------|
| `raymarch_num_samples` | int | 4 | 32 | 每像素光线数 |
| `raymarch_attenuation` | float | 3.0 | — | 衰减系数 |
| `raymarch_max_distance` | float | 0.8 | — | 最大搜索距离（归一化） |
| `raymarch_max_steps` | int | 32 | — | 最大步进次数 |
| `raymarch_emissive_threshold` | float | 0.01 | — | 发光阈值 |
| `raymarch_step_safety` | float | 0.8 | — | 步进安全系数（<1.0 防漏光） |
| `raymarch_rotation_offset` | float | 0.0 | — | 射线初始旋转偏移（弧度） |
| `raymarch_rotation_speed` | float | 0.0 | — | 旋转速度（弧度/秒），视觉暂留动态效果 |

#### Push Constant (28 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | number_samples |
| 4 | float32 | attenuation |
| 8 | float32 | maximum_distance |
| 12 | int32 | maximum_steps |
| 16 | float32 | emissive_threshold |
| 20 | float32 | step_safety |
| 24 | float32 | rotation_offset |

#### 特殊行为

`_process()` 中每帧累加旋转偏移：
```gdscript
raymarch_rotation_offset += raymarch_rotation_speed * delta
super._process(delta)
```

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 场景纹理（sampler2D，发光体颜色） |
| 额外输入 (binding 2) | 距离场（sampler2D） |
| 输出 (binding 1) | 直接光照（image2D） |
| 输出格式 | 继承源格式（RGBA16F） |

#### 算法说明

1. 自身发光（亮度 ≥ 阈值）: 直接输出自身颜色
2. 自身固体（alpha > 0 且不发光）: 输出黑色
3. 空区: 发射 `num_samples` 条均匀角度光线（带 rotation_offset 整体旋转）
4. 每条光线: 距离场加速步进（`step = max(dist*safety, min_step)`）
5. 命中发光体: 收集 `color * 1/(1+d*att)`
6. 命中非发光固体: 光线被阻挡
7. 输出: 所有光线平均值

---

### 1.6 DirectionalLightPass

**文件**: [directional_light_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/directional_light_pass.gd) → [directional_light_pass.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/directional_light_pass.glsl)
**状态**: ✅ 场景实例: PassDirectionalLight
**作用**: 平行光沿固定方向投射，带高度场阴影

#### 导出参数

| 参数名 | 类型 | 默认值 | 场景值 | 说明 |
|--------|------|--------|--------|------|
| `light_direction` | Vector2 | (-1, 0) | (-1, 1) | 光线方向 |
| `light_height` | float | 5.0 | — | 光源高度 |
| `light_brightness` | float | 1.0 | — | 光照亮度 |
| `light_max_distance` | float | 0.8 | — | 最大搜索距离 |
| `light_step_safety` | float | 0.8 | — | 步进安全系数 |
| `light_max_steps` | int | 32 | — | 最大步进次数 |

#### Push Constant (24 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | float32 | direction.x |
| 4 | float32 | direction.y |
| 8 | float32 | height |
| 12 | float32 | max_distance |
| 16 | float32 | step_safety |
| 20 | int32 | max_steps |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 场景纹理（sampler2D） |
| 额外输入 (binding 2) | 距离场（sampler2D） |
| 输出 (binding 1) | 平行光阴影图（image2D） |
| 输出格式 | 继承源格式 |

#### 输出含义

| 通道 | 含义 |
|------|------|
| R | 可见性（0=阴影, 1=光照） |
| G | 遮挡距离 / max_distance |

---

### 1.7 AOPass

**文件**: [ao_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/ao_pass.gd) → [ao_pass.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/ao_pass.glsl)
**状态**: ✅ 场景实例: PassAO
**作用**: 距离场引导采样计算环境光遮蔽。黄金螺旋采样 + 距离场方向引导 + 随机旋转

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `ao_num_samples` | int | 8 | 每像素采样点数 |
| `ao_radius` | float | 0.05 | 采样半径（归一化 0-1） |
| `ao_intensity` | float | 1.0 | 遮蔽强度系数 |
| `ao_falloff` | float | 1.0 | 遮蔽衰减指数 |
| `ao_bias` | float | 0.01 | 高度偏移，防止自遮挡 |
| `ao_df_guide_weight` | float | 0.5 | 距离场引导权重（0=纯黄金角度, 1=纯距离场引导） |

#### Push Constant (24 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | num_samples |
| 4 | float32 | radius |
| 8 | float32 | intensity |
| 12 | float32 | falloff |
| 16 | float32 | bias |
| 20 | float32 | df_guide_weight |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 场景纹理（sampler2D） |
| 额外输入 (binding 2) | 距离场（sampler2D） |
| 输出 (binding 1) | AO 因子图（image2D） |
| 输出格式 | 继承源格式 |

#### 输出含义

| 通道 | 含义 |
|------|------|
| R | AO 因子（0=完全遮蔽, 1=无遮蔽） |

---

### 1.8 TemporalPass

**文件**: [temporal_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/temporal_pass.gd) → [temporal.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/temporal.glsl)
**状态**: ✅ 场景实例: PassTemporal
**作用**: 帧间指数移动平均 (EMA) + AABB Clamp 防拖尾

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `temporal_blend_factor` | float | 0.1 | 混合因子（越低越平滑但延迟越大） |

#### Push Constant (4 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | float32 | blend_factor（首帧=1.0，之后=temporal_blend_factor） |

#### 内部纹理管理

- `_history_texture`: 历史帧纹理，通过 `_get_internal_extra_resource_ids()` 绑定到 binding 2
- `_on_output_texture_created()`: 输出纹理创建/重建时同步重建历史纹理
- `_after_dispatch()`: dispatch 后把输出复制到历史纹理供下帧使用
- `_ready()`: 先创建 1×1 占位历史纹理，避免首帧阻塞

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 当前帧（sampler2D，通常来自 RaymarchPass） |
| 内部输入 (binding 2) | 历史帧（sampler2D） |
| 输出 (binding 1) | 时间累积结果（image2D） |
| 输出格式 | 继承源格式 |

#### 算法说明

1. 当前帧 3×3 邻域求 AABB min/max
2. 历史值 clamp 到 AABB 范围（防拖尾）
3. `result = mix(history_clamped, current, blend_factor)`
4. 首帧 blend_factor = 1.0（完全使用当前帧）

---

### 1.9 BlurPass

**文件**: [blur_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/blur_pass.gd) → [blur.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/blur.glsl)
**状态**: ✅ 场景实例: BlurH, BlurV
**作用**: 可分离高斯模糊，支持通道掩码和方向选择

#### 导出参数

| 参数名 | 类型 | 默认值 | 场景值(BlurH) | 场景值(BlurV) | 说明 |
|--------|------|--------|---------------|---------------|------|
| `blur_radius` | int | 4 | 8 | 8 | 模糊半径（像素） |
| `blur_sigma` | float | 3.0 | 16.0 | 16.0 | 高斯标准差 |
| `blur_r` | bool | true | — | — | 模糊 R 通道 |
| `blur_g` | bool | true | — | — | 模糊 G 通道 |
| `blur_b` | bool | true | — | — | 模糊 B 通道 |
| `blur_a` | bool | false | — | — | 模糊 A 通道 |
| `blur_direction` | int | 0 | 0 | 1 | 0=水平, 1=垂直 |

#### Push Constant (16 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | radius |
| 4 | float32 | sigma |
| 8 | int32 | channel_mask (bit0=R, bit1=G, bit2=B, bit3=A) |
| 12 | int32 | direction |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 源纹理（sampler2D） |
| 输出 (binding 1) | 模糊后纹理（image2D） |
| 输出格式 | 继承源格式 |

#### 使用方式

两个 BlurPass 串联实现二维模糊: BlurH（水平）→ BlurV（垂直）。第二个 Pass 从第一个的输出采样。

---

### 1.10 NormalPass

**文件**: [normal_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/normal_pass.gd) → [normal_pass.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/normal_pass.glsl)
**状态**: ✅ 场景实例: PassNormal
**作用**: 从场景 Alpha（高度场）用 Sobel 算子计算表面法线

#### 导出参数

| 参数名 | 类型 | 默认值 | 场景值 | 说明 |
|--------|------|--------|--------|------|
| `normal_blur_radius` | int | 1 | 2 | Sobel 核半径（1=3×3, 2=5×5） |

#### Push Constant (4 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | blur_radius |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 场景纹理（sampler2D，读 alpha 作为高度） |
| 输出 (binding 1) | 法线图（image2D） |
| 输出格式 | `RGBA16F` |

#### 输出含义

| 通道 | 含义 |
|------|------|
| RGB | 法线编码 `n * 0.5 + 0.5` |
| A | 1.0 |

- 空区（alpha=0）: 法线 = (0, 0, 1) 向上
- 障碍物（alpha>0）: Sobel 计算高度梯度 (gx, gy)，法线 = `normalize(-gx, -gy, 1)`

---

## 二、备用 Pass（已实现未使用）

### 2.1 IndirectPass

**文件**: [indirect_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/indirect_pass.gd) → [indirect_pass.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/indirect_pass.glsl)
**状态**: 📦 备用
**作用**: 多跳间接光照（2-bounce GI）。对被照亮的非发光表面追踪次级光线收集间接光

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `indirect_num_samples` | int | 4 | 次级光线数 |
| `indirect_attenuation` | float | 5.0 | 衰减系数 |
| `indirect_max_distance` | float | 0.5 | 最大搜索距离 |
| `indirect_max_steps` | int | 24 | 最大步进次数 |
| `indirect_emissive_threshold` | float | 1.0 | 发光阈值 |
| `indirect_step_safety` | float | 0.8 | 步进安全系数 |
| `indirect_strength` | float | 0.5 | 间接光强度 |

#### Push Constant (28 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | num_samples |
| 4 | float32 | attenuation |
| 8 | float32 | maximum_distance |
| 12 | int32 | maximum_steps |
| 16 | float32 | emissive_threshold |
| 20 | float32 | step_safety |
| 24 | float32 | indirect_strength |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 直接光照结果（sampler2D，来自 RaymarchPass） |
| 额外输入 (binding 2) | 场景纹理（sampler2D） |
| 额外输入 (binding 3) | 距离场（sampler2D） |
| 输出 (binding 1) | 直接光照 + 间接光照（image2D） |

---

### 2.2 ATrousPass

**文件**: [atrous_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/atrous_pass.gd) → [atrous.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/atrous.glsl)
**状态**: 📦 备用
**作用**: A-Trous 小波滤波，5×5 核 B3 样条，颜色+深度双边权重

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `atrous_step_size` | int | 1 | 采样步长（每次迭代翻倍: 1,2,4） |
| `atrous_color_sigma` | float | 0.2 | 颜色双边权重 sigma |
| `atrous_depth_sigma` | float | 0.05 | 深度双边权重 sigma |

#### Push Constant (12 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | step_size |
| 4 | float32 | color_sigma |
| 8 | float32 | depth_sigma |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 源纹理（sampler2D） |
| 额外输入 (binding 2) | 距离场（sampler2D，深度引导） |
| 输出 (binding 1) | 降噪后纹理（image2D） |
| 输出格式 | 继承源格式 |

---

### 2.3 CompositePass

**文件**: [composite_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/composite_pass.gd) → [composite_pass.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/composite_pass.glsl)
**状态**: 📦 备用（场景改用 gi_display.gdshader）
**作用**: compute shader 版本的最终合成

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `composite_indirect_strength` | float | 1.0 | 间接光强度 |
| `composite_ao_strength` | float | 1.0 | AO 强度 |
| `composite_dir_color` | Color | — | 平行光颜色 |
| `composite_shadow_color` | Color | — | 阴影颜色 |

#### Push Constant (48 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | float32 | indirect_strength |
| 4 | float32 | ao_strength |
| 8-15 | (padding) | std430 对齐填充 |
| 16 | vec4 (float32×4) | dir_color |
| 32 | vec4 (float32×4) | shadow_color |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 屏幕纹理（sampler2D，`_ready` 中设 `source_viewport = get_viewport()`） |
| 额外输入 (binding 2) | 平行光（sampler2D） |
| 额外输入 (binding 3) | AO（sampler2D） |
| 输出 (binding 1) | 合成结果（image2D） |

---

### 2.4 DenoisePass

**文件**: [denoise_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/denoise_pass.gd) → [denoise.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/denoise.glsl)
**状态**: 📦 备用
**作用**: 标准双边滤波降噪（高斯空间权重 + 颜色权重）

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `denoise_radius` | int | 3 | 降噪半径 |
| `denoise_spatial_sigma` | float | 2.0 | 空间权重 sigma |
| `denoise_color_sigma` | float | 0.15 | 颜色权重 sigma |

#### Push Constant (12 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | int32 | radius |
| 4 | float32 | spatial_sigma |
| 8 | float32 | color_sigma |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 源纹理（sampler2D） |
| 输出 (binding 1) | 降噪后纹理（image2D） |
| 输出格式 | `RGBA8`（注意：8 位，可能损失 HDR 精度） |

---

### 2.5 SharpenPass

**文件**: [sharpen_pass.gd](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/sharpen_pass.gd) → [sharpen.glsl](file:///c:/Users/14194/Documents/Ants-at-world/experiments/gi/sharpen.glsl)
**状态**: 📦 备用
**作用**: Unsharp Mask 锐化，补偿降噪后的模糊

#### 导出参数

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `sharpen_strength` | float | 0.5 | 锐化强度 |
| `sharpen_blur_radius` | int | 2 | 模糊半径 |
| `sharpen_sigma` | float | 2.0 | 高斯 sigma |

#### Push Constant (16 字节)

| 偏移 | 类型 | 字段 |
|------|------|------|
| 0 | float32 | strength |
| 4 | int32 | radius |
| 8 | float32 | sigma |
| 12 | int32 | _pad（对齐填充） |

#### 输入输出

| 项 | 说明 |
|----|------|
| 输入 (binding 0) | 源纹理（sampler2D） |
| 输出 (binding 1) | 锐化后纹理（image2D） |
| 输出格式 | 继承源格式 |

#### 算法说明

```
low_freq = gaussian_blur(input, radius, sigma)
result = input + (input - low_freq) * strength
```

---

## 三、Pass 速查表

### 按场景使用状态

| Pass | 场景节点 | 主输入 | 额外输入 | 输出格式 |
|------|---------|--------|---------|---------|
| ScalePass | ScalePassHalf, ScalePassQuarter | source_viewport | — | 继承源 |
| SeedPass | PassSeed | source_viewport | — | RGBA16F |
| JumpFloodPass | PassJF1~8 | 前一兄弟 | — | RGBA16F |
| DistanceFieldPass | PassDF | 前一兄弟(PassJF8) | — | RGBA16F |
| RaymarchPass | PassRM | source_viewport | PassDF | 继承源 |
| DirectionalLightPass | PassDirectionalLight | source_viewport | PassDF | 继承源 |
| AOPass | PassAO | source_viewport | PassDF | 继承源 |
| TemporalPass | PassTemporal | 前一兄弟(PassRM) | 内部历史纹理 | 继承源 |
| BlurPass | BlurH, BlurV | 前一兄弟 | — | 继承源 |
| NormalPass | PassNormal | source_viewport | — | RGBA16F |
| IndirectPass | 📦 未使用 | 直接光照 | 场景+距离场 | 继承源 |
| ATrousPass | 📦 未使用 | 源纹理 | 距离场 | 继承源 |
| CompositePass | 📦 未使用 | 屏幕纹理 | 平行光+AO | 继承源 |
| DenoisePass | 📦 未使用 | 源纹理 | — | RGBA8 |
| SharpenPass | 📦 未使用 | 源纹理 | — | 继承源 |

### 按输出格式

| 格式 | Pass |
|------|------|
| RGBA16F (强制) | SeedPass, JumpFloodPass, DistanceFieldPass, NormalPass |
| 继承源格式 | ScalePass, RaymarchPass, DirectionalLightPass, AOPass, TemporalPass, BlurPass, IndirectPass, ATrousPass, CompositePass, SharpenPass |
| RGBA8 (强制) | DenoisePass |
