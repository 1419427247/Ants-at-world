# gi2d 着色器技术评估文档

> 评估范围：`addons/gi2d/shaders/` 目录下全部 13 个着色器文件
> 评估日期：2026-06-26
> 评估目标：从功能完整性、性能优化、代码规范、兼容性四个维度提供量化评分与可实施改进建议

---

## 一、评估维度与评分标准

| 维度 | 满分 | 评分依据 |
|------|------|----------|
| **功能完整性** | 10 | 算法是否正确实现预期效果；边界/异常情况处理是否完备；功能是否覆盖典型用例；是否有缺失的关键特性 |
| **性能优化** | 10 | GPU 资源利用效率（纹理采样数、循环次数、共享内存使用、早退策略、工作量）；是否针对硬件特性优化 |
| **代码规范** | 10 | 命名一致性、注释充分性、结构清晰度、魔法数字处理、可读性、是否存在冗余/遗留代码 |
| **兼容性** | 10 | GLSL 版本与扩展依赖；不同分辨率/宽高比适配；移动端与桌面端适配；Godot 版本兼容性 |

> 评分区间说明：9-10 优秀；7-8 良好；5-6 合格但有改进空间；3-4 存在明显缺陷；1-2 严重问题。

---

## 二、评分总览

| 着色器文件 | 类型 | 功能完整性 | 性能优化 | 代码规范 | 兼容性 | 加权均分 |
|-----------|------|:---------:|:-------:|:-------:|:-----:|:-------:|
| ao_pass.glsl | Compute | 7 | 6 | 7 | 8 | 7.0 |
| atrous.glsl | Compute | 7 | 7 | 8 | 8 | 7.5 |
| blur.glsl | Compute | 8 | 8 | 8 | 8 | 8.0 |
| directional_light_pass.glsl | Compute | 7 | 6 | 7 | 8 | 7.0 |
| distance_field.glsl | Compute | 7 | 8 | 8 | 8 | 7.8 |
| gi_display.gdshader | Canvas | 8 | 8 | 7 | 8 | 7.8 |
| indirect_pass.glsl | Compute | 7 | 6 | 7 | 8 | 7.0 |
| jump_flood.glsl | Compute | 8 | 7 | 8 | 8 | 7.8 |
| normal_pass.glsl | Compute | 8 | 8 | 8 | 8 | 8.0 |
| raymarch.glsl | Compute | 8 | 6 | 7 | 8 | 7.3 |
| seed.glsl | Compute | 8 | 8 | 8 | 8 | 8.0 |
| sharpen.glsl | Compute | 7 | 7 | 8 | 8 | 7.5 |
| temporal.glsl | Compute | 7 | 7 | 8 | 8 | 7.5 |

**整体均分：7.6 / 10** — 整体质量良好，处于「良好且有明确改进方向」水平。

---

## 三、逐文件详细评估

### 1. ao_pass.glsl — 环境光遮蔽

**功能描述**：2D SSAO 实现，融合两层 AO——SDF 直接估算（各向同性基础项 `exp(-sdf*scale)`）与 SDF 引导的 sphere-tracing 射线追踪（方向性细化），取两者最大值。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 7 | 双层 AO 合并思路正确，hash 旋转抖动减少带状伪影。但 SDF 基础项 `exp(-sdf*scale)` 为经验公式，缺乏物理依据；未处理 AO 自身障碍物边界的漏光；`radius` 为 UV 空间参数，不同分辨率下半径不一致。 |
| 性能优化 | 6 | 内层循环固定 16 步且无早退（步进超出 radius 才 break），`num_samples` 与 16 步相乘导致采样量高（如 num_samples=16 则 256 次纹理采样/像素）；`distance_image` 高频被重复访问却未使用共享内存；`hash12` 每像素计算一次（合理）。 |
| 代码规范 | 7 | 注释清晰（中文），push_constant 结构规范。`PI` 在文件内局部定义而非统一头文件；`aspect_vec` 计算正确但缺少注释说明为何只用 x/y 比值。 |
| 兼容性 | 8 | `#version 450` 标准 Vulkan compute，无特殊扩展依赖；宽高比修正已处理。 |

#### 修改建议

**算法优化**：
- SDF 基础项改用更物理化的模型。当前 `exp(-sdf*scale)` 在 sdf=0（贴表面）时 AO=1.0 恒为满遮挡，丢失了近场衰减细节。建议改为带 falloff 的形式：
  ```glsl
  // 近场线性 + 远场指数衰减，避免贴表面过曝
  float sdf_ao = 1.0 - smoothstep(0.0, uniform_parameters.radius, center_sdf);
  sdf_ao *= exp(-center_sdf * uniform_parameters.sdf_scale);
  ```

**性能提升**：
- 内层循环加入基于剩余距离的早退：当 `t > radius` 时已 break（已做），但可进一步在 `dir_occlusion` 已达阈值时提前结束当前方向。
- `radius` 应转换为像素单位传入并在 shader 内除以分辨率，保证不同分辨率下半径一致（当前是 UV 空间，分辨率变化时实际像素半径变化）。

**代码规范**：
- 将 `PI`、`hash12` 提取到公共 include 文件（如 `common.glsl`），减少跨文件重复定义（ao_pass、directional_light_pass、indirect_pass 均重复定义 `hash12`）。

---

### 2. atrous.glsl — À-Trous 双边滤波

**功能描述**：可分离 1D 双边滤波（B3 样条小波），结合颜色权重与深度（距离场）权重保边降噪，用于 GI 噪声消除。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 7 | 标准 À-Trous 实现正确，颜色+深度双边合理。但仅 5 tap（offset -2..2），对大尺度噪声抑制有限；`depth_sigma`/`color_sigma` 为线性空间参数，未考虑 HDR 范围。 |
| 性能优化 | 7 | 可分离设计正确（2.5x 加速注释准确）；5 tap 采样量低。但 `texture()` 而非 `texelFetch()` 在已知整数坐标时多一次插值；未利用共享内存复用邻域（5 tap 较少，影响有限）。 |
| 代码规范 | 8 | 结构清晰，B3 权重常量定义规范，`max(weight_sum, 0.0001)` 防除零。变量命名稍冗长但可读。 |
| 兼容性 | 8 | 标准实现，无兼容性问题。 |

#### 修改建议

**算法优化**：
- `color_sigma` 应根据输入亮度动态归一化。当前在 HDR（rgba16f）下，颜色差异可能远超 1.0，导致 `exp(-color_dist_sq * color_inverse)` 几乎恒为 0（过度保边）或恒为 1（不保边）。建议以中心像素亮度为参考：
  ```glsl
  float lum_center = max(dot(center_pixel.rgb, vec3(0.299, 0.587, 0.114)), 0.001);
  float color_inverse = 1.0 / (2.0 * uniform_parameters.color_sigma * uniform_parameters.color_sigma * lum_center * lum_center);
  ```

**性能提升**：
- 已知整数坐标 `sample_coordinates`，改用 `texelFetch(input_image, sample_coordinates, 0)` 替代 `texture()`，省去硬件插值与 UV 计算。同理 `depth_image` 也可用 `texelFetch`。

---

### 3. blur.glsl — 高斯模糊（可分离 + Mip 优化）

**功能描述**：可分离 1D 高斯模糊，支持通道掩码选择性模糊，大半径时通过 stride + textureLod mip 自动降采样。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 8 | 通道掩码设计灵活，stride/lod 自适应采样数控制优秀。`norm_factor` 计算正确但最终被 `weight_sum` 归一化约掉（冗余但无害）。 |
| 性能优化 | 8 | Mip 预滤波思路正确，`MAX_SAMPLES=17` 限制采样量。但 `log2(float(stride))` 每像素重复计算（可移至 push_constant 预计算）；纹理未生成 mip 时 `textureLod` 的 lod 参数无效（需确保纹理 mipmap 启用）。 |
| 代码规范 | 8 | 注释充分，逻辑清晰。`norm_factor` 冗余计算可移除。 |
| 兼容性 | 8 | 标准实现。需注意 Godot 中 compute texture 的 mip chain 需显式配置。 |

#### 修改建议

**性能提升**：
- `lod` 与 `stride` 在所有线程恒定，应预计算后通过 push_constant 传入，避免每像素 `log2`：
  ```glsl
  // CPU 端预算：stride = max(1, ...); lod = stride > 1 ? log2(stride) : 0;
  ```
- 若纹理未启用 mipmap（compute 输出纹理通常无 mip），`textureLod` 的 lod>0 会失效或返回未定义。应在 GDScript 端确认 `mipmaps = true`，否则退化为 `texture()`。

**代码规范**：
- 移除冗余的 `norm_factor`（已被 `blur_sum / weight_sum` 归一化覆盖），简化为只算 `weight = exp(-dist_sq / two_sigma_sq)`。

---

### 4. directional_light_pass.glsl — 平行光阴影

**功能描述**：SDF 引导的平行光阴影投射，沿光源反方向 sphere-tracing，结合高度判断遮挡，PCF 沿垂直方向抖动柔化边缘。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 7 | 高度插值 `mix(origin_height, light_height, t)` 模拟平行光仰角，思路正确。但 `ray_height + 0.001` 的偏置为硬编码，不同尺度下可能失效；PCF 抖动用固定 `j*137, j*73` 种子，低样本数时分布不均；未处理光源在纹理边缘的渐隐。 |
| 性能优化 | 6 | `hash12` 在 PCF 循环内每次重算（基于 coordinates+j*常量，实际可预生成抖动表）；`directional_light_visibility` 内每步采样 distance_image，重复访问未用共享内存；`aspect_vec` 在主函数和子函数重复计算。 |
| 代码规范 | 7 | 注释充分，函数拆分合理。但 `hash12` 与 ao_pass、indirect_pass 重复定义；`surface_threshold` 计算放在子函数内但每条 PCF 射线重复计算（注释称提到循环外但实现在函数内）。 |
| 兼容性 | 8 | 标准实现，宽高比修正已处理。 |

#### 修改建议

**算法优化**：
- 阴影偏置应基于法线/高度梯度自适应，而非固定 `0.001`：
  ```glsl
  float bias = abs(dFdy(origin_height)) * 2.0 + 0.0005; // 或基于步长
  if (ground_height > ray_height + bias) { ... }
  ```
  注：compute shader 中 `dFdx/dFdy` 不可用，可改用 SDF 梯度或固定步长比例偏置 `min_step_uv * 0.5`。

- PCF 抖动种子改用蓝噪声或低差异序列，提升低样本数质量：
  ```glsl
  // Halton 序列替代固定种子
  float halton(int index, int base) { /* ... */ }
  float jitter = halton(j, 2) - 0.5;
  ```

**性能提升**：
- `surface_threshold` 仅依赖分辨率，应在主函数计算一次后作为参数传入子函数，避免每条 PCF 射线重复计算。
- PCF 抖动 UV 可预计算为数组，减少循环内 `hash12` 调用。

**代码规范**：
- 提取公共 `hash12` 到 include 文件。

---

### 5. distance_field.glsl — 距离场转换

**功能描述**：将 Jump Flood 的 Voronoi 结果转换为距离场（R=距离，GB=方向），区分固体/空区取最近异质点。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 7 | 固体/空区双向距离计算正确，哨兵处理合理。但 `is_solid` 判断用 `dot(diff,diff) < 1e-6` 在 rgba16f 精度下可能误判（种子 UV 存储精度损失）；`nearest_dist = 1.0`（无最近点时）为 UV 空间最大值，但实际应设为极大值避免干扰下游 sphere tracing。 |
| 性能优化 | 8 | 单像素仅 1 次纹理采样 + 少量运算，性能优异。`length()` 用了一次 sqrt（必要）。 |
| 代码规范 | 8 | 清晰简洁，注释说明数据结构。平方距离比较省 sqrt 的注释准确。 |
| 兼容性 | 8 | 标准实现。 |

#### 修改建议

**算法优化**：
- `is_solid` 判断阈值 `1e-6` 对 rgba16f（half float，约 3 位有效十进制）过严，建议放宽至 `1e-3` 或改用直接比较 Voronoi.xy 与像素整数坐标：
  ```glsl
  ivec2 self_coord = coordinates;
  ivec2 solid_coord = ivec2(voronoi.xy * vec2(texture_size));
  bool is_solid = all(equal(self_coord, solid_coord));
  ```

- 无最近点时 `nearest_dist` 应设为远大于 radius 的值，而非 UV 空间的 1.0，以免在 sphere tracing 中产生意外命中：
  ```glsl
  nearest_dist = 1e4; // 远超搜索半径，下游会被 max_distance 截断
  ```

---

### 6. gi_display.gdshader — 最终合成

**功能描述**：Canvas Item 着色器，合成场景图 + 漫反射 + GI + 平行光 + AO，应用 ACES 色调映射与 sRGB 转换。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 8 | GI UV margin 映射设计优秀（向后兼容）；AO 仅影响间接光而非直接光的逻辑正确；ACES + sRGB 流程规范。但 `ao_color` 下限 `0.1` 硬编码导致 AO 永不完全黑；`directional_shadow_color` 默认纯黑可能过暗。 |
| 性能优化 | 8 | Fragment 着色器，5 次纹理采样，开销低。`lin_to_srgb` 用分支而非 mix，可优化。 |
| 代码规范 | 7 | 整体清晰，但残留注释代码 `//COLOR.rgb = gi_color;`；`lin_to_srgb` 分支逐通道判断冗余；无显式 `render_mode` 注释说明为何选 `blend_mix`。 |
| 兼容性 | 8 | Godot 4 canvas_item 语法规范，`hint_screen_texture` 正确。 |

#### 修改建议

**算法优化**：
- `lin_to_srgb` 逐通道分支可用 mix + step 向量化，减少分支：
  ```glsl
  vec3 lin_to_srgb(vec3 color) {
      vec3 threshold = vec3(0.0031308);
      vec3 linear = color * 12.92;
      vec3 srgb = 1.055 * pow(clamp(color, 0.0, 1.0), vec3(0.4166667)) - 0.055;
      return mix(linear, srgb, step(threshold, color));
  }
  ```

- `ao_color` 下限 0.1 应参数化或基于 `ao_strength` 动态调整，避免完全遮挡区域仍残留 10% 亮度。

**代码规范**：
- 删除残留调试代码 `//COLOR.rgb = gi_color;`。

---

### 7. indirect_pass.glsl — 间接光 Pass

**功能描述**：追踪次级光线收集间接光，命中非发光障碍物时从 PassRM 读取反弹颜色作为光源，直接光 + 间接光合并输出。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 7 | 单次反弹间接光收集逻辑正确。但 `step_dist < 0.01` 阈值为 UV 空间硬编码，与 raymarch 的 `surface_threshold`（自适应 4-16 像素）不一致，导致两 pass 检测带宽度不匹配；间接光无距离衰减外的角度/法线项，反弹光照缺乏方向性。 |
| 性能优化 | 6 | `num_samples` × `maximum_steps` 双重循环，采样量大；`march_indirect_ray` 内每步采样 distance_image，未用共享内存；`scene_image` 与 `passrm_image` 重复采样相同位置。 |
| 代码规范 | 7 | 函数拆分清晰，注释充分。`hash12` 重复定义；`0.01` 阈值魔法数字；`6.28318530718` 应定义常量。 |
| 兼容性 | 8 | 标准实现，但缺少宽高比修正（raymarch 有 `aspect_vec`，此 pass 的 `direction` 未做修正，导致非正方形分辨率下光线非各向同性）。 |

#### 修改建议

**算法优化**：
- 统一表面检测阈值，与 raymarch.glsl 保持一致：
  ```glsl
  float surface_threshold = clamp(float(scene_texture_size_vec.x) / 128.0, 4.0, 16.0) * min_step_uv;
  if (step_dist < surface_threshold) { ... }
  ```

- 补充宽高比修正，保证非正方形分辨率下光线各向同性（与 raymarch 一致）：
  ```glsl
  vec2 aspect_vec = vec2(1.0, scene_texture_size_vec.x / scene_texture_size_vec.y);
  vec2 direction = normalize(vec2(cos(angle), sin(angle)) * aspect_vec);
  ```

**性能提升**：
- 命中障碍物时已 `break`，但空区精细步进可加入基于剩余 `maximum_distance` 的早退判断（已有 `if (total_distance_2d > maximum_distance) break`，但放在 step_dist 检查之后，可前移）。

**代码规范**：
- 提取 `hash12`、`PI`/`TWO_PI` 到公共 include。

---

### 8. jump_flood.glsl — Jump Flood 算法

**功能描述**：JFA 单次传播 pass，3x3 邻域更新最近固体/空区种子，平方距离比较省 sqrt。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 8 | 双种子（固体+空区）设计优秀，哨兵 `-1` 处理正确，平方距离比较规范。功能完整。 |
| 性能优化 | 7 | 3x3 = 8 次邻域采样，标准 JFA 开销。但未利用共享内存——JFA 步长大时邻域重叠低，共享内存收益有限，可接受；`texture()` 可改 `texelFetch`。 |
| 代码规范 | 8 | 清晰，注释说明平方距离优化。 |
| 兼容性 | 8 | 标准实现。 |

#### 修改建议

**性能提升**：
- 邻域采样改用 `texelFetch(input_image, nc, 0)`，已知整数坐标省去 UV 计算与插值：
  ```glsl
  vec4 neighbor = texelFetch(input_image, nc, 0);
  ```

**算法优化**：
- JFA 在步长较大时存在「跳跃过近邻」的精度问题，可在最后两 pass 用 step=1 细化（需在 GDScript 调度端配置，非 shader 本身问题，但建议在注释中提示调度策略）。

---

### 9. normal_pass.glsl — 法线 Pass

**功能描述**：从高度场（alpha 通道）用 Sobel 计算法线，共享内存 tile 加载 + barrier 协作。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 8 | 共享内存 tile 加载规范，barrier 同步正确，可变半径 Sobel（1-4）灵活。空区输出 UP_NORMAL 合理。但 Sobel 权重 `float(i)`/`float(j)` 是简化梯度（非标准 Sobel 核），对大半径平滑过度。 |
| 性能优化 | 8 | 共享内存复用优秀，每像素仅从 shared memory 读取，无全局纹理重复采样；tile 加载协作高效。`barrier()` 使用正确。 |
| 代码规范 | 8 | 结构清晰，常量定义规范（WG/MAX_R/TILE）。 |
| 兼容性 | 8 | 标准实现。 |

#### 修改建议

**算法优化**：
- 当前 Sobel 权重为线性距离（`float(i)`），非标准 Sobel 核。大半径时等效于均值梯度，可引入高斯加权提升质量：
  ```glsl
  float w = exp(-float(i*i + j*j) / (2.0 * float(r) * float(r)));
  gx += h * float(i) * w;
  gy += h * float(j) * w;
  ```

**性能提升**：
- tile 加载已优化，无明显改进空间。可考虑 `shared` 内存 `volatile` 或 padding 避免 bank conflict，但 TILE=24 非对齐，影响有限。

---

### 10. raymarch.glsl — 主光线追踪

**功能描述**：核心 GI 光线追踪，多反弹（max_bounces）+ 反射方向计算 + IGN 蓝噪声 + 边缘渐隐，SDF 引导 sphere tracing。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 8 | 多反弹 + 反射 + IGN + edge_fade 功能丰富。反射方向用法线图计算，合理。但反射后 `total_distance_2d = 0.0` 重置导致反弹后衰减系数 `att` 重新从 0 计算可能过亮；`min_step_uv` 用 `max(x,y)` 而其他 pass 用 `x`，不一致。 |
| 性能优化 | 6 | `max_steps_total = maximum_steps * (max_bounces+1)` 可能极大（如 64*4=256），每步采样 distance_image；早退仅依赖 `bounce_attenuation < 0.001`，未利用总距离；`surface_threshold` 自适应但每条光线重复计算。 |
| 代码规范 | 7 | 注释详尽。但 `min_step_uv` 计算方式与其他 pass 不一致（用 max 而非 x）；`6.28318530718` 魔法数字；`ign` 函数未注释来源公式参数。 |
| 兼容性 | 8 | 标准实现，宽高比修正已处理。 |

#### 修改建议

**算法优化**：
- 反弹后不应完全重置 `total_distance_2d`，否则衰减 `att = 1/(1+0*attenuation)=1`，反弹光过亮。应保留累计距离或使用独立的反弹距离：
  ```glsl
  // 保留总光程用于衰减，仅重置段内距离用于步长判断
  total_distance_2d = 0.0; // 段内距离
  // 另设 total_path_length 累加用于衰减
  ```
  或修正衰减为乘积形式（当前 `bounce_attenuation` 已处理反弹衰减，但 `att` 距离衰减被重置）。

- `min_step_uv` 统一为 `1.0 / float(scene_texture_size.x)` 与其他 pass 一致。

**性能提升**：
- 将 `surface_threshold` 移至主函数预算后传入 `march_ray`，避免每条光线重复计算。
- 内层循环加入总距离早退：
  ```glsl
  if (total_distance_2d > uniform_parameters.maximum_distance && bounce >= 1) break;
  ```

**代码规范**：
- 定义 `TWO_PI` 常量替代 `6.28318530718`；补充 IGN 算法来源注释。

---

### 11. seed.glsl — 种子初始化

**功能描述**：形态学腐蚀生成固体边界种子 + 初始化 JFA 双种子（固体/空区），共享内存 tile 加载。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 8 | 腐蚀逻辑正确（贴边强制腐蚀），双种子哨兵设计规范。共享内存 tile 协作加载优秀。 |
| 性能优化 | 8 | 共享内存复用，barrier 同步正确，早退优化（`!is_eroded` 条件）。tile 加载高效。 |
| 代码规范 | 8 | 清晰，注释说明 tile 协作。 |
| 兼容性 | 8 | 标准实现。 |

#### 修改建议

**算法优化**：
- 腐蚀核遍历可用提前 break 优化（已有 `!is_eroded` 条件），但内层循环顺序固定，可从最近邻开始遍历以更快触发 break。

**性能提升**：
- 已优化充分，无明显改进空间。

---

### 12. sharpen.glsl — 锐化（Unsharp Mask）

**功能描述**：可分离 1D 高斯模糊 + Unsharp Mask（V pass 执行 `original + detail*strength`）。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 7 | Unsharp Mask 实现正确。但 H pass 和 V pass 复用同一 shader 通过 `direction` 切换，`original_image`（binding 2）在 H pass 未使用却仍需绑定（资源浪费）；锐化无亮度阈值，可能放大噪声。 |
| 性能优化 | 7 | 可分离设计正确，`norm_factor` 被注释说明可省略（实际已省略，正确）。但未用共享内存，大 radius 时采样量大；`texture()` 可改 `texelFetch`。 |
| 代码规范 | 8 | 清晰，注释说明 norm_factor 省略原因。 |
| 兼容性 | 8 | 标准实现。 |

#### 修改建议

**算法优化**：
- 加入锐化阈值，避免放大噪声：
  ```glsl
  vec4 detail = original - blurred;
  float lum_detail = dot(detail.rgb, vec3(0.299, 0.587, 0.114));
  float threshold = 0.01;
  float sharpen_weight = abs(lum_detail) > threshold ? uniform_parameters.strength : 0.0;
  imageStore(output_image, coordinates, original + detail * sharpen_weight);
  ```

**性能提升**：
- H pass 时 `original_image` 未使用，GDScript 端可绑定 dummy texture 或 shader 内 `direction==0` 时不声明该 binding（Vulkan 要求绑定一致，可用 push_constant 标记）。实际上更简单：保持绑定但在 H pass 不采样（当前已如此，无实际开销）。

---

### 13. temporal.glsl — 时域累积

**功能描述**：指数移动平均（EMA）时域累积，AABB clamp 消除拖影（ghosting）。

#### 评分表

| 维度 | 得分 | 评分依据 |
|------|:----:|----------|
| 功能完整性 | 7 | AABB clamp 思路正确，消除拖影有效。但无运动矢量重投影（reprojection），相机移动时历史帧位置错位导致模糊；`blend_factor` 固定，未根据运动量/置信度自适应。 |
| 性能优化 | 7 | 3x3 邻域采样 8 次 + current/history 各 1 次，开销适中。`texture()` 可改 `texelFetch`。 |
| 代码规范 | 8 | 清晰，注释说明 AABB clamp 目的。 |
| 兼容性 | 8 | 标准实现。 |

#### 修改建议

**算法优化**：
- AABB clamp 是无运动矢量时的退化方案。若 gi2d 场景相机移动，建议引入速度矢量（基于上一帧相机变换）做重投影：
  ```glsl
  // 简化版：用 gi_uv_offset 变化估算位移
  vec2 velocity = (current_gi_uv_offset - history_gi_uv_offset);
  vec2 history_uv = gi_uv - velocity;
  vec4 history_pixel = texture(history_image, history_uv);
  ```
  若无法获取运动矢量，可基于当前帧与历史帧的亮度差异降低 `blend_factor`（运动大时偏向当前帧）。

- `blend_factor` 自适应：基于邻域方差动态调整，平坦区域高 blend（多累积降噪），高频区域低 blend（减少拖影）。

**性能提升**：
- 邻域采样改 `texelFetch(current_frame_image, coordinates + offset, 0)`。

---

## 四、整体评估

### 4.1 整体优势

1. **架构设计成熟**：采用 SDF 引导的 sphere tracing 作为核心，贯穿 AO、阴影、直接光、间接光全流程，算法选型一致且高效（JFA→距离场→各 pass 复用）。管线分层清晰（种子→JFA→距离场→法线→光线追踪→降噪→时域→合成）。

2. **性能意识强**：多处采用行业最佳实践——平方距离比较省 sqrt（jump_flood、distance_field）、可分离滤波（atrous、blur、sharpen）、共享内存 tile 协作（normal_pass、seed）、Mip 预滤波降采样（blur）、IGN 蓝噪声加速时域收敛（raymarch）、早退策略（seed 的 `!is_eroded`、raymarch 的 `bounce_attenuation` 阈值）。

3. **代码可读性高**：中文注释详尽，数据结构（binding 用途、RGBA 通道编码）说明清晰，push_constant 参数命名规范，函数拆分合理。

4. **兼容性良好**：统一 `#version 450` + Vulkan compute 风格，无平台特定扩展，宽高比修正多处处理，Godot 4 集成规范。

### 4.2 共性问题

| 编号 | 问题 | 影响范围 | 严重度 |
|------|------|----------|--------|
| C1 | **公共代码重复**：`hash12` 在 ao_pass、directional_light_pass、indirect_pass 重复定义；`PI`/`TWO_PI` 多处局部定义；`aspect_vec` 计算重复 | 4 个文件 | 中 |
| C2 | **`texture()` vs `texelFetch()`**：已知整数坐标时仍用 `texture()` 产生不必要插值与 UV 计算 | 7 个文件 | 中 |
| C3 | **阈值/魔法数字硬编码**：`0.01`（indirect_pass）、`0.001`（directional_light_pass）、`0.001`（raymarch edge）、`6.28318530718` 等，未统一为常量或自适应 | 5 个文件 | 中 |
| C4 | **表面检测阈值不一致**：indirect_pass 用固定 `0.01`，raymarch 用自适应 `4-16 像素`，导致两 pass 行为不匹配 | indirect_pass / raymarch | 高 |
| C5 | **`min_step_uv` 计算不一致**：多数用 `1/size.x`，raymarch 用 `1/max(x,y)` | raymarch | 低 |
| C6 | **缺少共享内存优化**：ao_pass、directional_light_pass、indirect_pass 高频访问 distance_image 但未用共享内存 | 3 个文件 | 中 |
| C7 | **时域缺少运动矢量**：temporal 无 reprojection，相机移动时拖影/模糊 | temporal | 中 |
| C8 | **残留调试代码**：gi_display 的注释代码 `//COLOR.rgb = gi_color` | 1 个文件 | 低 |

### 4.3 系统性改进方案

#### 方案一：建立公共头文件 `common.glsl`

提取重复代码，通过 `#include`（Godot 4 支持 GLSL include）统一管理：

```glsl
// common.glsl
const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 自适应表面检测阈值（统一 indirect_pass 与 raymarch）
float surface_threshold(vec2 texture_size, float min_step_uv) {
    return clamp(texture_size.x / 128.0, 4.0, 16.0) * min_step_uv;
}

// 宽高比修正向量
vec2 aspect_vector(vec2 texture_size) {
    return vec2(1.0, texture_size.x / texture_size.y);
}
```

**收益**：消除 C1、C4、C5，降低维护成本，保证行为一致性。

#### 方案二：统一 `texelFetch` 替换 `texture`

在所有已知整数坐标的 compute shader 中，将 `texture(img, uv)` 替换为 `texelFetch(img, ivec2_coords, 0)`，避免硬件插值与 UV 重复计算。

**收益**：消除 C2，预计纹理采样性能提升 5-15%（视硬件而定），且消除亚像素插值带来的精度误差。

#### 方案三：为高频距离场访问引入共享内存

ao_pass、directional_light_pass、indirect_pass 均在 ray march 中高频采样 `distance_image`。可参照 normal_pass 的 tile 协作模式，将 distance_image 的邻域预加载到共享内存。

**注意**：ray march 方向发散，tile 覆盖范围需大于搜索半径，可能导致共享内存占用过大。折中方案：仅对 AO 等固定半径 pass 应用（方向可控），ray march 因射线发散收益有限可暂不优化。

**收益**：消除 C6，AO pass 预计纹理带宽降低 40%+。

#### 方案四：时域 Pass 升级为带运动矢量的重投影

当前 temporal 仅做 AABB clamp（无运动矢量场景的退化方案）。若 gi2d 场景存在相机移动（GILightViewport 有 margin 变化），应引入基于 `gi_uv_offset` 变化的位移估算：

```glsl
// temporal.glsl 改进
layout(push_constant, std430) uniform UniformParameters {
    float blend_factor;
    vec2  gi_uv_offset_delta; // 本帧与上帧 gi_uv_offset 差值
} uniform_parameters;

void main() {
    // ... 
    vec2 history_uv = gi_uv - uniform_parameters.gi_uv_offset_delta;
    vec4 history_pixel = texture(history_image, history_uv);
    // AABB clamp + EMA
}
```

**收益**：消除 C7，显著减少相机移动时的拖影与模糊。

#### 方案五：参数自适应与魔法数字清理

- 将所有硬编码阈值（`0.01`、`0.001`）改为 push_constant 参数或基于分辨率/像素尺寸自适应。
- 统一 `min_step_uv = 1.0 / float(texture_size.x)`。

**收益**：消除 C3、C5，提升跨分辨率一致性。

---

## 五、硬件与环境适应性分析

| 场景 | 表现评估 | 建议 |
|------|----------|------|
| **桌面端独显（NVIDIA/AMD）** | 16x16 workgroup 高效，compute shader 充分利用并行度。raymarch 多反弹场景可能成为瓶颈。 | 可适当提升 num_samples/max_bounces 获得更高质量。 |
| **集成显卡（Intel UHD）** | 共享内存 tile 优化有效，但 raymarch 大量纹理采样可能受限；`rgba16f` 带宽压力大。 | 提供质量档位：低质量用 `rgba8` + 单反弹 + 少采样。 |
| **移动端（Vulkan）** | `#version 450` 在多数移动 GPU 支持，但 compute shader 兼容性参差（部分 Adreno 驱动问题）；`barrier()` 与 shared memory 在移动端开销较高。 | 移动端考虑降级为 fragment shader 实现，或减少 tile 尺寸。 |
| **高分辨率（4K）** | `radius`（UV 空间）导致高分辨率下像素半径过大、性能下降；JFA 步数随 log2(分辨率) 增长。 | radius 改为像素单位；提供分辨率自适应的采样数缩放。 |
| **非正方形宽高比** | raymarch/ao_pass 有 aspect 修正，indirect_pass 缺失（C4）。 | 统一 aspect 修正（方案一）。 |

---

## 六、结论

gi2d 着色器套件整体质量**良好（均分 7.6/10）**，架构设计成熟、性能优化意识强、注释详尽，已具备生产可用基础。核心改进方向集中在：

1. **一致性**（统一公共代码、阈值、采样方式）— 优先级最高，影响行为正确性；
2. **时域质量**（引入运动矢量重投影）— 提升动态场景体验；
3. **移动端适配**（质量档位 + 降级路径）— 扩展兼容性。

建议按「方案一（公共头文件）→ 方案二（texelFetch 统一）→ 方案四（时域升级）」顺序实施，前两项为低成本高收益，第三项需配合 GDScript 端运动矢量传递。
