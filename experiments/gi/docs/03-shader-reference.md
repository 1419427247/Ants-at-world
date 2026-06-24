# Shader 参考手册

> 版本: 1.0 | 更新日期: 2026-06-24

本文档对 `experiments/gi/` 目录下全部着色器进行逐文件说明，涵盖 Compute Shader（`.glsl`）与 Canvas Shader（`.gdshader`）两大类。所有内容基于实际源码整理，可作为管线调试与参数调优的查阅依据。

---

## 通用约定（适用于所有 Compute Shader）

为避免在每个小节重复，以下约定适用于本目录下全部 `.glsl` compute shader：

- **着色器版本**：统一使用 `#version 450`，文件首行带 Godot 的 `#[compute]` 标记。
- **线程组大小**：统一为 `layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;`，即每个工作组 16×16×1 = 256 个线程。Dispatch 分组数由 `ComputePass` 基类按 `ceili(width/16) × ceili(height/16)` 自动计算。
- **输入采样**：输入纹理统一声明为 `uniform sampler2D`，通过 `texture(sampler, uv)` 采样（只读）。采样器由 `ComputePass` 创建为最近邻过滤（`SAMPLER_FILTER_NEAREST`）。
- **输出写入**：输出纹理统一声明为 `uniform restrict writeonly image2D`（格式多为 `rgba16f`），通过 `imageStore(image, ivec2, vec4)` 写入。
- **统一 binding 布局**（由 `compute_pass.gd` 基类强制约定）：
  - `binding 0`：主输入（`sampler2D`，只读）
  - `binding 1`：输出（`image2D`，可写）
  - `binding 2+`：额外输入（`sampler2D`，只读），按 `extra_input_sources` 数组顺序依次绑定
- **坐标约定**：UV 计算统一为 `(vec2(pixel) + 0.5) / vec2(size)`（像素中心采样），边界判断使用 `gl_GlobalInvocationID.xy` 与 `imageSize` 比较。
- **Push Constant**：统一声明为 `layout(push_constant, std430) uniform UniformParameters { ... } uniform_parameters;`，由各 Pass 子类的 `_get_push_data()` 序列化为 `PackedByteArray` 下发。

---

## 一、Compute Shader（.glsl）

### 1.1 seed.glsl — JF 种子生成

- **文件路径**：`experiments/gi/seed.glsl`
- **作用**：Jump Flood 算法的初始化步骤。读取缩放后的场景纹理，根据 Alpha 通道区分固体/空区，并对固体边缘做形态学腐蚀，输出每个像素的初始种子（最近固体 UV 与最近空区 UV）。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D input_image` | 只读 | 来自 ScalePass 的输入（rgba16f），用 alpha 判断可见性 |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 种子图输出 |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    int erosion_radius; // 腐蚀半径（像素单位，1=3×3 核内缩1圈）
} uniform_parameters;
```

**核心算法**：
1. 空区像素（`alpha <= 0`）：直接输出 `RG=(-1,-1)`（固体哨兵），`BA=自身UV`（空区种子）。
2. 固体像素：在 `(2r+1)×(2r+1)` 邻域内扫描，若存在空区像素（或超出边界），则当前像素被腐蚀为空区种子；否则保持为固体种子（`RG=自身UV`）。
3. 哨兵值为 `-1.0`（`x<0` 表示无固体种子，`z<0` 表示无空区种子）。

**输出格式**：RGBA16F
- `RG` = 最近固体种子 UV（哨兵 `-1.0`）
- `BA` = 最近空区种子 UV（哨兵 `-1.0`）

---

### 1.2 jump_flood.glsl — Jump Flood 传播

- **文件路径**：`experiments/gi/jump_flood.glsl`
- **作用**：Jump Flood 算法的单次传播步骤。通过大步长邻域查找，逐步收敛每个像素到最近固体/空区种子的 UV，构建 Voronoi 图。场景中串联 8 个本 Pass（divisor=2,4,8,16,32,64,128,256）完成完整传播。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D input_image` | 只读 | 上一帧/上一步的种子图（RGBA16F） |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 传播后的种子图 |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    int step_x; // X 方向步长（像素）
    int step_y; // Y 方向步长（像素）
} uniform_parameters;
```

**核心算法**：
1. 读取当前像素已有的最近固体/空区种子 UV 及其距离。
2. 检查 3×3 邻域（偏移按 `step_x`/`step_y` 缩放），对每个邻居的固体种子和空区种子分别比较距离，保留更近者。
3. 步长由 `JumpFloodPass` 根据 `jump_flood_step_divisor` 自动计算 `step = max(1, size / divisor)`。

**输出格式**：RGBA16F（与输入同结构）
- `RG` = 最近固体种子 UV（哨兵 `x<0`）
- `BA` = 最近空区种子 UV（哨兵 `z<0`）

---

### 1.3 distance_field.glsl — 有向距离场

- **文件路径**：`experiments/gi/distance_field.glsl`
- **作用**：消费 Jump Flood 输出的 Voronoi 图，计算每个像素到最近异质点（固体↔空区边界）的距离与方向，供后续光线步进、AO、平行光 Pass 加速。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D voronoi_image` | 只读 | Voronoi 结果（RGBA16F） |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 距离场输出 |

**Push Constant 结构**：无（本 Pass 不使用 push constant）。

**核心算法**：
1. 通过比较 `voronoi.xy` 与自身 UV（距离 `< 0.001`）判断当前像素是固体还是空区。
2. 固体像素取最近空区种子（`voronoi.zw`），空区像素取最近固体种子（`voronoi.xy`）。
3. 计算到该异质点的距离（UV 空间）与归一化方向向量。

**输出格式**：RGBA16F
- `R` = 到最近异质点的距离（UV 空间）
- `GB` = 指向最近异质点的方向向量（归一化）
- `A` = `1.0`

---

### 1.4 raymarch.glsl — 光线步进直接光照

- **文件路径**：`experiments/gi/raymarch.glsl`
- **作用**：核心 GI Pass。对每个空区像素发射多条光线，利用距离场加速步进，收集可见发光体的直接光照，输出间接光累积结果。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D scene_image` | 只读 | 场景纹理（发光体颜色） |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 光照输出 |
| 2 | `sampler2D distance_image` | 只读 | 有向距离场（额外输入） |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    int   number_samples;       // 每像素光线数
    float attenuation;          // 衰减系数
    float maximum_distance;     // 最大搜索距离（归一化）
    int   maximum_steps;        // 主步进最大步数
    float emissive_threshold;   // 发光阈值
    float step_safety;          // 步进安全系数（<1.0）
    float rotation_offset;      // 射线初始旋转偏移（弧度）
} uniform_parameters;
```

**核心算法**：
1. **早退优化**：自身是发光体（亮度 ≥ `emissive_threshold`）直接输出自身颜色；自身是障碍物（`alpha > 0` 且非发光）直接输出黑色。
2. **光线发射**：按 `number_samples` 条光线均匀角度分布（间隔 `2π/N`），整体旋转 `rotation_offset`（支持万花筒/流光效果）。
3. **距离场加速步进**（`march_ray`）：每步读取距离场 `R` 通道，按 `step_dist * step_safety` 步进；当 `step_dist < 0.01` 时判定接近表面：
   - 若表面亮度 ≥ `emissive_threshold`：收集光照（`1/(1+d*attenuation)` 衰减）并终止该光线；
   - 若表面 `alpha < 0.001`（空区表面）：按距离场精细步进继续；
   - 否则（非发光固体）：视为障碍物，光线被阻挡终止。
4. 累积所有光线结果后除以 `number_samples` 取平均。

**输出格式**：RGBA16F
- `RGB` = 累积光照颜色
- `A` = `1.0`

---

### 1.5 directional_light_pass.glsl — 平行光阴影

- **文件路径**：`experiments/gi/directional_light_pass.glsl`
- **作用**：模拟平行光（如太阳光）的 2D 阴影。沿光源反方向步进，利用高度场线性抬升光线高度判断是否被遮挡，输出可见性与遮挡距离。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D luminance_texture` | 只读 | 亮度纹理（Alpha 通道存地面高度） |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 阴影输出 |
| 2 | `sampler2D distance_image` | 只读 | 有向距离场（额外输入） |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    vec2  direction;      // 平行光 2D 方向（光传播方向，归一化）
    float height;         // 平行光高度（仰角）
    float max_distance;   // 最大搜索距离（归一化）
    float step_safety;    // 步进安全系数
    int   max_steps;      // 最大步进次数
} uniform_parameters;
```

**核心算法**（`directional_light_visibility`）：
1. 沿光源反方向（`-direction`）步进。
2. 每步读取距离场 `R` 通道加速；当 `step_dist < 0.01` 时接近表面，读取该处地面高度。
3. **线性高度抬升**：`ray_height = mix(origin_height, height, t)`，其中 `t = total_distance / max_distance`。
4. 若 `ground_height > ray_height + 0.001`：判定被遮挡，记录遮挡距离并返回可见性 `0.0`。
5. 超过 `max_distance` 未被遮挡则返回可见性 `1.0`。

**输出格式**：RGBA16F
- `R` = 可见性（`0.0`=被遮挡，`1.0`=可见）
- `G` = 遮挡距离 / 最大距离（归一化）
- `B` = `0.0`
- `A` = `1.0`

---

### 1.6 ao_pass.glsl — 环境光遮蔽

- **文件路径**：`experiments/gi/ao_pass.glsl`
- **作用**：基于距离场引导的黄金角度采样计算环境光遮蔽（AO）。利用距离场方向分量优先在可能有遮挡的方向采样，基于高度差累积遮蔽。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D scene_texture` | 只读 | 场景纹理（Alpha 通道存地面高度） |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | AO 输出 |
| 2 | `sampler2D distance_image` | 只读 | 有向距离场（额外输入） |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    int   num_samples;        // 每像素采样点数
    float radius;             // 采样半径（归一化）
    float intensity;          // 遮蔽强度系数
    float falloff;            // 遮蔽衰减指数
    float bias;               // 高度偏移，防止自遮挡
    float df_guide_weight;    // 距离场引导权重（0=纯黄金角度, 1=纯距离场引导）
} uniform_parameters;
```

**核心算法**：
1. **黄金螺旋采样分布**：`radius_factor = sqrt((i+0.5)/N)`，角度按黄金角度 `2.399963` 递增。
2. **距离场引导**：在采样路径中点查询距离场方向（`GB` 通道），与黄金角度方向按 `df_guide_weight` 混合，优先朝向附近表面采样。
3. **随机旋转**：用 PCG 哈希（`hash12`）生成每像素随机旋转角，消除规律性噪声。
4. **遮蔽判定**：采样点距离场 `< radius * radius_factor * 0.5`（在物体内部或表面附近）且采样点高度高于中心点（`height_diff > 0`）时累积遮蔽，按距离衰减 `1 - smoothstep(0, radius, dist)`。
5. 最终除以采样数，应用 `falloff` 衰减指数并 clamp 到 `[0,1]`。

**输出格式**：RGBA16F
- `R` = AO 因子（`1.0`=完全遮挡，`0.0`=无遮挡）
- `G` = `0.0`
- `B` = `0.0`
- `A` = `1.0`

---

### 1.7 temporal.glsl — 时间累积

- **文件路径**：`experiments/gi/temporal.glsl`
- **作用**：帧间指数移动平均（EMA）累积，平滑时域噪声。配合 AABB Clamp 消除运动残影（ghosting）。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D current_frame_image` | 只读 | 当前帧 GI（主输入） |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 累积输出 |
| 2 | `sampler2D history_image` | 只读 | 历史累积结果（内部额外输入） |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    float blend_factor; // 当前帧权重（0.0=全历史，1.0=全当前）
} uniform_parameters;
```

**核心算法**：
1. **AABB Clamp**：计算当前帧 3×3 邻域的 RGB min/max（AABB 包围盒），将历史值 `clamp` 到此范围，消除运动时的拖尾残影。
2. **指数移动平均**：`final = mix(history_clamped, current, blend_factor)`。

> 注：历史纹理由 `TemporalPass`（`temporal_pass.gd`）在 dispatch 后将输出复制到内部历史纹理（binding 2），首帧 `blend=1.0` 直接用当前帧。

**输出格式**：RGBA16F
- `RGB` = 混合结果
- `A` = `1.0`

---

### 1.8 blur.glsl — 可分离高斯模糊

- **文件路径**：`experiments/gi/blur.glsl`
- **作用**：可分离高斯模糊，用于 GI 降噪。通过水平+垂直两次串联（BlurH→BlurV）将 O(N²) 降为 O(2N)。支持通道掩码，可选择性模糊部分通道。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D input_image` | 只读 | 输入纹理 |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 模糊输出 |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    int   radius;       // 模糊核半径
    float sigma;        // 高斯标准差
    int   channel_mask; // 通道掩码：bit 0=R, bit 1=G, bit 2=B, bit 3=A
    int   direction;    // 方向：0=水平, 1=垂直
} uniform_parameters;
```

**核心算法**：
1. 根据 `direction` 选择水平或垂直方向，在 `[-radius, radius]` 范围内一维采样。
2. 高斯权重：`weight = norm_factor * exp(-dist² / (2σ²))`，`norm_factor = 1/√(π·2σ²)`。
3. **通道掩码混合**：启用的通道（按位与判断）用模糊结果，禁用的通道保留原中心像素值。

**输出格式**：RGBA16F
- 启用通道 = 模糊结果
- 禁用通道 = 原值

---

### 1.9 normal_pass.glsl — 法线生成

- **文件路径**：`experiments/gi/normal_pass.glsl`
- **作用**：从场景纹理 Alpha 通道表示的高度场，通过 Sobel 算子计算表面法线，输出法线图。当前主要用于调试预览。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D scene_image` | 只读 | 场景纹理（Alpha = 表面高度） |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 法线图输出 |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    int blur_radius; // Sobel 采样半径（1=3×3, 2=5×5）
} uniform_parameters;
```

**核心算法**：
1. **空区**（`alpha < 0.001`）：法线指向正面 `(0, 0, 1)`。
2. **固体表面**：在 `(2r+1)×(2r+1)` 邻域内用 Sobel 算子计算高度梯度 `(gx, gy)`（梯度方向 = 高度增加最快方向）。
3. **法线构造**：`normal = normalize(vec3(-gx, -gy, 1.0))`，`z=1` 确保法线指向观察者。
4. 编码到 `[0,1]` 范围：`n * 0.5 + 0.5`。

**输出格式**：RGBA16F
- `RGB` = 法线向量（编码到 0-1：`n*0.5+0.5`）
- `A` = `1.0`

---

### 1.10 scale.glsl — 纹理缩放

- **文件路径**：`experiments/gi/scale.glsl`
- **作用**：纹理缩放 Pass，支持双线性与 Catmull-Rom bicubic 两种插值模式。用于分辨率分层（下采样/上采样）。

**Binding 布局**：

| Binding | 类型 | 限定符 | 说明 |
|---------|------|--------|------|
| 0 | `sampler2D input_image` | 只读 | 输入纹理 |
| 1 | `image2D output_image` | `rgba16f, restrict, writeonly` | 目标尺寸输出 |

**Push Constant 结构**：

```glsl
layout(push_constant, std430) uniform UniformParameters {
    int mode; // 0=双线性（下采样友好），1=bicubic（上采样更锐利）
} uniform_parameters;
```

**核心算法**：
1. 输出像素中心 → 归一化 UV → 输入像素坐标（`uv * input_size - 0.5`）。
2. **双线性模式**（`mode=0`）：取 2×2 邻域四点，按小数部分双线性插值，速度快，下采样友好。
3. **bicubic 模式**（`mode=1`）：Catmull-Rom 三次插值（B-spline 族），取 4×4 邻域，用 `cubic_weights` 计算权重，上采样更锐利，保留 GI 边缘。

**输出格式**：RGBA16F（采样颜色，原样透传）

---

## 二、Canvas Shader（.gdshader）

Canvas Shader 用于 Godot 的 2D 渲染管线（`shader_type canvas_item`），通过 `ShaderMaterial` 挂载到 `CanvasItem` 派生节点（如 `ColorRect`、`Sprite2D`）。

### 2.1 gi_display.gdshader — GI 合成输出

- **文件路径**：`experiments/gi/gi_display.gdshader`
- **作用**：最终合成着色器。将原始场景图、间接光（GI）、平行光阴影、AO 四张纹理合成为最终屏幕输出，并完成色调映射与色彩空间转换。挂载在 `Composite` 节点的 `ShaderMaterial` 上。

**Uniform 声明**：

```glsl
shader_type canvas_item;

// 输入纹理
uniform sampler2D screen_texture : hint_screen_texture; // 原始场景图
uniform sampler2D gi_texture;                           // 间接光（GI）
uniform sampler2D directional_texture;                  // 平行光
uniform sampler2D ao_texture;                           // 环境光遮蔽

// 合成参数
uniform float indirect_strength : hint_range(0.0, 4.0) = 1.0;
uniform float ao_strength       : hint_range(0.0, 1.0) = 1.0;
uniform vec4  dir_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4  shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.0627);
```

**核心算法（fragment 函数）**：

1. **采样四张纹理**：场景图（`screen_texture`）、间接光（`gi_texture`）、平行光（`directional_texture`，取 `rrr`）、AO（`ao_texture`，取 `r`）。
2. **AO 因子**：`ao_factor = mix(1.0, 1.0 - ao, ao_strength)`，`0`=完全遮挡（黑），`1`=无遮挡（亮）。
3. **平行光着色**：
   - 阴影贡献：`shadow_color.rgb * (1 - directional.r) * shadow_color.a`
   - 光照贡献：`dir_color.rgb * directional.r * dir_color.a`
   - 按 `directional.g`（遮挡距离）在阴影与光照间混合。
4. **光照层合成**：`lighting = (indirect.rgb * indirect_strength + directional_contribution) * ao_factor`，AO 仅影响光照层，不影响原始场景。
5. **Alpha 混合**：`result = mix(vec3(0.0), scene + lighting, scene_alpha)`，用场景 alpha 区分空区（光照不叠加到无几何体像素）。

**合成逻辑特别说明（ACES 色调映射 + sRGB 转换 + alpha 混合）**：

最终输出阶段对间接光单独做色调映射与色彩空间转换：

```glsl
// ACES Filmic 色调映射 — 压缩 HDR 动态范围，保留高光细节
vec3 tonemapped = aces_tonemap(indirect.rgb);
// 线性 → sRGB 转换
COLOR = vec4(lin_to_srgb(tonemapped), indirect.a);
```

- **ACES Filmic 色调映射**（`aces_tonemap`）：使用 Narkowicz 近似公式 `(x(2.51x+0.03))/(x(2.43x+0.59)+0.14)`，将 HDR 高动态范围压缩到 `[0,1]`，保留高光细节，避免过曝截断。
- **sRGB 转换**（`lin_to_srgb`）：分段转换，`< 0.0031308` 用线性 `c*12.92`，否则用幂函数 `1.055·c^(1/2.4) - 0.055`，将线性颜色转换为显示器 sRGB 空间。
- **Alpha 混合**：最终 `COLOR` 的 alpha 取自 `indirect.a`，控制合成结果与背景的混合。

> 注：当前实现中 `result`（含场景+光照合成）变量计算后未直接用于最终输出，最终 `COLOR` 输出的是经 ACES + sRGB 处理的间接光。如需将完整合成结果输出，需将 `tonemapped` 的输入由 `indirect.rgb` 改为 `result`。

**辅助函数**：
- `lin_to_srgb(vec3)`：线性 → sRGB 分段转换。
- `aces_tonemap(vec3)`：ACES Filmic 色调映射。

**输出**：`COLOR`（`vec4`），经色调映射与 sRGB 转换的最终像素颜色。

---

### 2.2 soil.gdshader — 泥土材质

- **文件路径**：`experiments/gi/soil.gdshader`
- **作用**：程序化泥土材质着色器，通过 FBM 分形噪声生成泥土纹理，包含基础颜色混合、粗糙度纹理、小石子、有机斑点等细节。挂载在场景根 `ColorRect` 节点作为背景地面材质。

**Uniform 声明**：

```glsl
shader_type canvas_item;

uniform vec3  dirt_color    : source_color = vec3(0.42, 0.28, 0.15);
uniform vec3  dark_color    : source_color = vec3(0.30, 0.18, 0.08);
uniform vec3  light_color   : source_color = vec3(0.55, 0.38, 0.22);
uniform float noise_scale   : hint_range(0.5, 8.0) = 3.0;
uniform float roughness     : hint_range(0.0, 1.0) = 0.6;
uniform float pebble_amount : hint_range(0.0, 0.3) = 0.08;
```

**核心算法（fragment 函数）**：

1. **FBM 分形噪声**（`fbm`）：4 层迭代，每层振幅减半、频率加倍，叠加生成大尺度地形变化。
2. **基础颜色混合**：`mix(dark_color, light_color, base_noise + detail_noise)`，叠加 4 倍频细节噪声。
3. **粗糙度纹理**：用 6 倍频噪声调制颜色明度 `(0.9 + 0.2*rough)`。
4. **小石子**：12 倍频噪声 `smoothstep(1-pebble_amount, 1.0, ...)` 生成石子斑点，混合石子色 `(0.5,0.4,0.3)`。
5. **有机斑点**：2 倍频偏移噪声生成深色腐殖质斑点，混合 `dark_color*0.8`。

**辅助函数**：
- `hash(vec2)`：简化哈希噪声。
- `noise(vec2)`：2D 值噪声（双线性插值 + smoothstep 平滑）。
- `fbm(vec2)`：4 层 FBM 分形噪声。

**输出**：`COLOR = vec4(color, 1.0)`，不透明泥土颜色。

---

## 三、Shader 依赖关系速查

下表汇总各 Compute Shader 间的数据依赖（binding 2+ 的额外输入来源）：

| Shader | 主输入（binding 0）来源 | 额外输入（binding 2+） |
|--------|------------------------|----------------------|
| seed.glsl | ScalePass 输出 | — |
| jump_flood.glsl | 上一个 JF Pass / SeedPass 输出 | — |
| distance_field.glsl | 最后一个 JF Pass 输出 | — |
| raymarch.glsl | GILightViewport 场景纹理 | distance_field 输出 |
| directional_light_pass.glsl | GILightViewport 场景纹理 | distance_field 输出 |
| ao_pass.glsl | GILightViewport 场景纹理 | distance_field 输出 |
| temporal.glsl | 上游 Pass（Raymarch）输出 | 内部历史纹理 |
| blur.glsl | 上游 Pass 输出 | — |
| normal_pass.glsl | GILightViewport 场景纹理 | — |
| scale.glsl | GILightViewport 场景纹理 | — |

> Canvas Shader `gi_display.gdshader` 的 `gi_texture`/`directional_texture`/`ao_texture` 由 `GDScript_composite` 脚本每帧从 `PassRM`/`PassDirectionalLight`/`PassAO` 的输出 RID 动态注入。
