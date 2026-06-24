# GI 管线 GLSL Shader 评审报告

> 评审范围：`experiments/gi/` 目录下全部 15 个 `.glsl` 文件
> 评审日期：2026-06-24

## 评分标准

| 维度 | 说明 |
|------|------|
| **算法正确性** | 核心算法逻辑是否正确，是否存在数学/物理错误 |
| **性能** | GPU 占用、分支发散、纹理采样次数、冗余计算 |
| **代码质量** | 可读性、命名、注释、结构清晰度 |
| **健壮性** | 边界处理、除零保护、数值稳定性、宽高比适配 |

每项 1-10 分，总分 = 加权平均（算法 35% + 性能 25% + 代码 20% + 健壮 20%）。

---

## 评分总览

| # | 文件 | 算法 | 性能 | 代码 | 健壮 | 总分 | 等级 |
|---|------|:----:|:----:|:----:|:----:|:----:|:----:|
| 1 | [distance_field.glsl](#1-distance_fieldglsl) | 9 | 9 | 9 | 8 | **8.85** | A |
| 2 | [jump_flood.glsl](#2-jump_floodglsl) | 9 | 8 | 8 | 8 | **8.35** | A |
| 3 | [temporal.glsl](#3-temporalglsl) | 9 | 9 | 9 | 7 | **8.60** | A |
| 4 | [atrous.glsl](#4-atrousglsl) | 9 | 8 | 8 | 8 | **8.35** | A |
| 5 | [blur.glsl](#5-blurglsl) | 8 | 9 | 9 | 9 | **8.75** | A |
| 6 | [sharpen.glsl](#6-sharpenglsl) | 8 | 7 | 8 | 8 | **7.75** | B+ |
| 7 | [scale.glsl](#7-scaleglsl) | 9 | 8 | 9 | 9 | **8.85** | A |
| 8 | [seed.glsl](#8-seedglsl) | 8 | 7 | 8 | 8 | **7.75** | B+ |
| 9 | [normal_pass.glsl](#9-normal_passglsl) | 8 | 7 | 8 | 7 | **7.55** | B+ |
| 10 | [composite_pass.glsl](#10-composite_passglsl) | 7 | 9 | 8 | 8 | **7.95** | B+ |
| 11 | [denoise.glsl](#11-denoiseglsl) | 7 | 6 | 8 | 8 | **7.15** | B |
| 12 | [raymarch.glsl](#12-raymarchglsl) | 8 | 5 | 8 | 7 | **7.05** | B |
| 13 | [indirect_pass.glsl](#13-indirect_passglsl) | 7 | 5 | 7 | 6 | **6.30** | C+ |
| 14 | [ao_pass.glsl](#14-ao_passglsl) | 6 | 6 | 7 | 7 | **6.45** | C+ |
| 15 | [directional_light_pass.glsl](#15-directional_light_passglsl) | 7 | 5 | 8 | 7 | **6.75** | B- |

---

## 详细评审

---

### 1. distance_field.glsl

**功能**：从 Voronoi 结果提取有向距离场（SDF）。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 9 | Voronoi→SDF 转换逻辑正确，固体/空区双向距离计算无误，哨兵值处理得当 |
| 性能 | 9 | 单次纹理采样 + 简单分支，无循环，极轻量 |
| 代码质量 | 9 | 注释清晰，变量命名语义化，输出格式文档完善 |
| 健壮性 | 8 | 除零保护（`nearest_dist > 0.001`），但 `distance()` 在 UV 空间未考虑宽高比 |

**优点**：
- 输出格式（R=距离, GB=方向, A=1）设计合理，下游 pass 直接可用
- 哨兵值 `-1.0` 处理一致

**问题**：
- `distance(pixel_uv, nearest_uv)` 在 UV 空间计算，非正方形视口下距离值有偏差（方向向量已归一化所以方向正确，但距离值本身是椭圆度量）
- `is_solid` 判断用 `distance() < 0.001` 浮点比较，极端分辨率下可能误判

**改进建议**：
- 距离计算可考虑宽高比修正：`length((uv_a - uv_b) * aspect_vec)`
- `is_solid` 可改用 `voronoi.xy == pixel_uv` 的分量级比较

---

### 2. jump_flood.glsl

**功能**：Jump Flooding Algorithm 单步传播，计算最近固体/空区种子。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 9 | JFA 标准实现，3×3 邻域 + 步长递减，固体/空区双通道并行传播 |
| 性能 | 8 | 每 pass 9 次纹理采样（8 邻居+自身），可接受；但 `distance()` 每次调用含 sqrt |
| 代码质量 | 8 | 结构清晰，注释解释了双通道设计 |
| 健壮性 | 8 | 边界检查完善，哨兵值处理正确 |

**优点**：
- 双通道（固体 RG + 空区 BA）在一次 JFA 中同时传播，节省一半 pass 数
- 哨兵值 `-1.0` 判断一致

**问题**：
- `distance()` 在 UV 空间计算，非正方形视口下传播结果有偏差
- `found_solid`/`found_empty` 初始化时已读取 `current`，但后续循环中未检查邻居是否已有有效种子（依赖哨兵值 `>= 0.0` 判断，逻辑正确但可读性稍差）

**改进建议**：
- 距离计算加宽高比修正
- 可用 `dot(diff, diff)` 替代 `distance()` 做比较，省 sqrt（只需相对距离）

---

### 3. temporal.glsl

**功能**：时域累积（TAA），当前帧与历史帧指数移动平均 + AABB Clamp 防拖尾。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 9 | EMA + AABB Clamp 是标准 TAA 做法，clamp 历史值到当前帧 3×3 邻域色域范围 |
| 性能 | 9 | 9 次纹理采样（3×3 邻域），无循环嵌套，非常高效 |
| 代码质量 | 9 | 注释清晰，AABB Clamp 原理有解释 |
| 健壮性 | 7 | 缺少运动矢量（Motion Vector），静态场景效果好但相机移动时会有重影 |

**优点**：
- AABB Clamp 实现简洁有效
- `mix()` 做插值，blend_factor 可调

**问题**：
- **无运动矢量重投影**：历史帧直接按相同坐标读取，相机/物体移动时产生鬼影。当前仅靠 AABB Clamp 限制鬼影，但这是被动方案而非主动方案
- 无历史帧有效性检测（如场景切换时历史帧失效）
- `blend_factor` 为固定值，未做自适应（亮区可用更大权重加速收敛）

**改进建议**：
- 加入运动矢量：根据相机位移偏移历史帧采样坐标
- 加入历史帧有效性检测：比较历史/当前深度，差异过大时丢弃历史
- 自适应 blend_factor：基于颜色方差动态调整

---

### 4. atrous.glsl

**功能**：A-Trous 小波变换双边滤波，用于 GI 降噪。带颜色+深度（SDF）双边权重。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 9 | B3 样条小波权重正确，颜色+深度双边滤波是 SVGF 类标准做法 |
| 性能 | 8 | 5×5 核 = 24 次采样/pass，多 pass 翻倍步长等效大核；可分离优化未实现 |
| 代码质量 | 8 | 权重计算清晰，B3 系数有注释 |
| 健壮性 | 8 | `max(weight_sum, 0.0001)` 防除零，边界 clamp 完善 |

**优点**：
- 深度引导（SDF）有效防止墙体边界被错误平滑
- 步长翻倍设计使 4 pass 即可覆盖 41×41 等效核

**问题**：
- **未做可分离优化**：A-Trous 本质可分离为 H+V 两 pass，当前 5×5 全采样浪费了 2 倍性能
- `color_sigma`/`depth_sigma` 为固定值，未做亮度自适应
- 无法线引导（normal weight），仅颜色+深度

**改进建议**：
- 拆分为水平+垂直两个可分离 pass，性能提升约 2 倍
- 加入法线权重：`weight_normal = pow(max(dot(n0, n1), 0), power)`
- 颜色 sigma 可基于中心像素亮度自适应

---

### 5. blur.glsl

**功能**：可分离高斯模糊，支持水平/垂直方向 + 通道掩码。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 8 | 高斯权重计算正确，可分离设计合理 |
| 性能 | 9 | 一维循环，O(radius) 采样，非常高效 |
| 代码质量 | 9 | 通道掩码位运算设计巧妙，注释清晰 |
| 健壮性 | 9 | 边界 clamp，权重归一化完善 |

**优点**：
- 通道掩码（bit 0-3 对应 RGBA）允许选择性模糊，非常灵活
- 水平/垂直复用同一 shader，减少代码重复

**问题**：
- 高斯归一化常数 `1/sqrt(π*2σ²)` 有误，正确值应为 `1/(σ*sqrt(2π))`。实际不影响结果因为最终做了 `blur_sum / weight_sum` 归一化，但数学上不严谨
- 大 radius 时每次采样都调用 `texture()`，未利用硬件线性过滤做预融合

**改进建议**：
- 修正归一化常数为 `1.0 / (sigma * sqrt(2.0 * PI))`
- 大 radius 时可利用 `textureLod` + 纹理金字塔减少采样次数

---

### 6. sharpen.glsl

**功能**：Unsharp Mask 锐化，高斯模糊后提取细节叠加回原图。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 8 | Unsharp Mask 标准实现，`原图 + (原图 - 模糊) * 强度` |
| 性能 | 7 | 二维嵌套循环 O(radius²)，未做可分离优化 |
| 代码质量 | 8 | 注释清晰，公式有解释 |
| 健壮性 | 8 | 边界无 clamp（依赖 `texture()` 的 repeat/clamp 模式） |

**优点**：
- Unsharp Mask 是经典且有效的锐化方法
- 参数可调（strength, radius, sigma）

**问题**：
- **二维高斯未做可分离**：应先 H 后 V 两 pass，当前 O(r²) 可降为 O(r)
- 与 blur.glsl 功能重叠，可复用 blur pass 生成低频版本

**改进建议**：
- 拆分为可分离两 pass，或直接复用 BlurH+BlurV 的输出做减法
- 加入细节保护：对高频部分做阈值过滤，避免放大噪声

---

### 7. scale.glsl

**功能**：图像缩放，支持双线性 + Catmull-Rom Bicubic 两种模式。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 9 | 双线性和 Catmull-Rom 权重计算正确，像素中心对齐处理得当 |
| 性能 | 8 | 双线性 4 次采样，bicubic 16 次采样，合理 |
| 代码质量 | 9 | 两种模式清晰分离，cubic_weights 函数有注释 |
| 健壮性 | 9 | 边界 clamp 完善，坐标转换无除零风险 |

**优点**：
- Catmull-Rom B-spline 实现正确，适合 GI 上采样
- `input_position = uv * input_size - 0.5` 像素中心对齐处理正确
- 双模式设计灵活

**问题**：
- bicubic 的 4×4 采样未利用 `texture()` 的硬件线性过滤做优化（可用 4 次双线性采样等效 16 次最近邻）
- 无 Lanczos 选项（更锐利的上采样）

**改进建议**：
- bicubic 可优化为 4 次双线性采样（利用硬件插值）
- 可选加入 Lanczos 窗口函数

---

### 8. seed.glsl

**功能**：JFA 初始化，对固体边缘做形态学腐蚀，生成固体/空区种子。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 8 | 形态学腐蚀逻辑正确，边缘固体被腐蚀为空区种子 |
| 性能 | 7 | O(r²) 循环，但 `is_eroded` 提前退出优化有效 |
| 代码质量 | 8 | 腐蚀逻辑注释清晰，哨兵值使用一致 |
| 健壮性 | 8 | 边界像素视为空区强制腐蚀，合理 |

**优点**：
- 腐蚀半径可调，控制光源/障碍物内缩量
- 提前退出（`&& !is_eroded`）减少不必要的邻域检查

**问题**：
- 腐蚀核为方形（3×3, 5×5...），非圆形核，对角线方向腐蚀量偏大
- `erosion_radius` 参数名不够直观，实际是核半径而非腐蚀距离

**改进建议**：
- 用圆形核：`if (i*i + j*j <= r*r)` 替代方形核
- 考虑用距离场做精确腐蚀（已有 SDF 可用）

---

### 9. normal_pass.glsl

**功能**：从高度场（Alpha 通道）用 Sobel 算子计算表面法线。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 8 | Sobel 梯度→法线转换正确，`normalize(-gx, -gy, 1.0)` 方向无误 |
| 性能 | 7 | O(r²) 循环，但实际 r 通常为 1（3×3），可接受 |
| 代码质量 | 8 | 梯度→法线推导有注释，空区法线常量定义清晰 |
| 健壮性 | 7 | 无宽高比修正，`pixel_size` 在 X/Y 方向相同但视口非正方形时梯度失真 |

**优点**：
- Sobel 算子实现简洁
- 法线编码 `n*0.5+0.5` 标准做法

**问题**：
- **无宽高比修正**：`pixel_size.x == pixel_size.y` 仅在正方形视口成立，长方形视口下 Y 方向梯度被拉伸
- Sobel 权重用 `float(i)`/`float(j)` 而非标准 Sobel 核（如 `[1,2,1; 0,0,0; -1,-2,-1]`），实际是简单差分
- 空区法线硬编码为 `(0,0,1)`，未考虑空区表面的高度变化

**改进建议**：
- 梯度计算加宽高比：`gx *= 1.0; gy *= aspect;`
- 使用标准 Sobel 核权重
- 空区也可从邻域高度梯度计算法线（如果空区有高度信息）

---

### 10. composite_pass.glsl

**功能**：Compute shader 合成最终图像（间接光 + 平行光 + AO）。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 7 | 合成公式基本正确，但平行光颜色混合逻辑有瑕疵 |
| 性能 | 9 | 3 次纹理采样，无循环，极轻量 |
| 代码质量 | 8 | 注释清晰，输出格式文档化 |
| 健壮性 | 8 | 无除零风险，边界检查完善 |

**优点**：
- 简洁高效，3 次采样完成合成
- AO 乘法应用方式正确

**问题**：
- **平行光颜色混合逻辑混乱**：
  ```glsl
  vec3 shadow_contrib = shadow_color.rgb * directional * shadow_color.a;
  vec3 light_contrib = dir_color.rgb * directional * dir_color.a;
  vec3 directional_contribution = mix(shadow_contrib, light_contrib, directional_magnitude);
  ```
  `directional` 已经是可见性（0-1），再用它做 `mix` 因子等于双重应用。且 `shadow_color * directional` 在阴影区域（directional=0）贡献为 0，与预期相反
- 缺少色调映射（由 display shader 做了，但 compute 合成结果可能超出 0-1 范围导致精度损失）
- `directional` 通道读取用 `.rrr`，假设 R=可见性，但 directional_light_pass 输出 G=遮挡距离未利用

**改进建议**：
- 修正平行光混合：`directional_color = mix(shadow_color.rgb, dir_color.rgb, directional.r)`
- 考虑在合成阶段就做色调映射，避免 rgba16f 精度浪费
- 利用 G 通道（遮挡距离）做软阴影衰减

---

### 11. denoise.glsl

**功能**：标准双边滤波降噪。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 7 | 双边滤波实现正确，但无深度/法线引导 |
| 性能 | 6 | O(r²) 全采样，大半径时性能差；无可分离优化 |
| 代码质量 | 8 | 代码简洁，注释清晰 |
| 健壮性 | 8 | `max(weight_sum, 0.0001)` 防除零，边界 clamp |

**优点**：
- 实现简洁直接
- 空间+颜色双边权重标准

**问题**：
- **无深度引导**：与 atrous.glsl 不同，此 pass 无 SDF 深度权重，容易模糊几何边缘
- **输出格式 rgba8**：与管线中其他 pass 的 rgba16f 不一致，精度损失
- 与 atrous.glsl 功能高度重叠，且性能更差

**改进建议**：
- 输出格式改为 rgba16f
- 加入深度引导（与 atrous.glsl 一致）
- 考虑直接用 atrous.glsl 替代此 pass

---

### 12. raymarch.glsl

**功能**：2D 光线步进 GI，支持多次反弹、法线反射、SDF 引导步进。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 8 | SDF 引导步进 + 法线反射逻辑正确，多反弹衰减合理 |
| 性能 | 5 | 每像素 N 条光线 × M 步 × (bounce+1) 段，计算量巨大；PCF 无此问题但此 pass 无 |
| 代码质量 | 8 | 函数拆分合理，注释解释了反弹逻辑 |
| 健壮性 | 7 | 边界检查完善，但反弹后 `total_distance_2d = 0.0` 导致衰减计算不连续 |

**优点**：
- SDF 引导步进大幅减少空步
- 法线反射实现正确，`reflect()` 使用得当
- 逐像素随机角度偏移 + 时域累积可收敛
- 宽高比修正已添加

**问题**：
- **反弹后距离重置导致衰减跳变**：`total_distance_2d = 0.0` 使反弹后的衰减从 1.0 重新开始，物理上不正确（应累积总光程）
- `bounce_attenuation *= 0.5` 硬编码衰减，不可调
- 反弹时未检查反射方向是否朝向空区（可能朝向固体内部）
- `step_dist < 0.01` 阈值固定，不同分辨率下表现不一致
- 无最大距离检查在 `step_dist < 0.01` 分支内（仅在外层检查）

**改进建议**：
- 反弹后保留累积距离：`total_distance_2d += bounce_offset` 而非重置为 0
- `bounce_attenuation` 衰减系数改为可配置参数
- 反射后检查方向有效性：若 `dot(reflect_dir, normal) < 0` 则终止
- `step_dist < 0.01` 阈值应与分辨率关联：`step_dist < min_step_uv * 2`

---

### 13. indirect_pass.glsl

**功能**：次级光线追踪，从被照表面收集间接光。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 7 | 间接光收集逻辑基本正确，但物理模型简化过度 |
| 性能 | 5 | 又一轮 N×M 光线步进，与 raymarch 叠加导致性能翻倍 |
| 代码质量 | 7 | 结构清晰，但注释不如 raymarch 详细 |
| 健壮性 | 6 | 无宽高比修正，无反弹后距离保护 |

**优点**：
- 从 PassRM 读取障碍物颜色作为反弹光源，思路合理
- 发光体排除逻辑正确

**问题**：
- **无宽高比修正**：`vec2 direction = vec2(cos(angle), sin(angle))` 未做 aspect 修正（与 raymarch.glsl 不一致）
- **无多次反弹**：只做一次反弹，间接光质量有限
- `bounce_brightness > 0.001` 阈值固定，可能漏掉弱光
- 与 raymarch.glsl 的 march_ray 函数高度重复，应合并

**改进建议**：
- 添加宽高比修正（与 raymarch.glsl 一致）
- 合并到 raymarch.glsl，用 `max_bounces` 参数控制反弹次数
- 阈值改为可配置参数

---

### 14. ao_pass.glsl

**功能**：基于距离场的 2D 环境光遮蔽。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 6 | AO 模型过于简化，非标准 SSAO/GTAO 实现 |
| 性能 | 6 | N 方向 × 3 步 = 3N 次采样，尚可 |
| 代码质量 | 7 | 注释清晰，但部分变量未使用 |
| 健壮性 | 7 | 边界检查完善，宽高比已修正 |

**优点**：
- SDF 引导采样方向，减少无效采样
- 随机旋转偏移 + 时域累积可收敛
- 宽高比修正已添加

**问题**：
- **AO 模型不标准**：当前实现是"检查采样点 SDF 是否小于阈值"，这更像是近邻检测而非真正的环境光遮蔽。标准 AO 应积分半球可见性
- `df_guide_weight` 和 `bias` 参数声明了但未使用
- `center_sdf` 变量读取了但未使用
- 3 步采样太少，AO 质量差（噪点多）
- `occlusion += dist_factor / float(step)` 的 `1/step` 权重无物理依据

**改进建议**：
- 实现标准 2D SSAO：沿方向步进，比较采样点高度与射线高度
- 移除未使用的变量和参数
- 增加采样步数或利用 SDF 做自适应步长
- 考虑用 SDF 距离直接估算 AO：`ao = 1.0 - exp(-sdf * scale)` 的近似

---

### 15. directional_light_pass.glsl

**功能**：平行光阴影投射，SDF 引导步进 + 高度场阴影 + PCF 柔化。

| 维度 | 分数 | 评述 |
|------|:----:|------|
| 算法正确性 | 7 | 高度场阴影逻辑正确，但 PCF 实现有瑕疵 |
| 性能 | 5 | PCF 使计算量乘以 N 倍，每像素 N 次完整光线步进 |
| 代码质量 | 8 | 函数拆分合理，注释清晰 |
| 健壮性 | 7 | 边界检查完善，宽高比已修正 |

**优点**：
- SDF 引导步进高效
- 高度场阴影模型（线性抬升光线高度）直观有效
- 宽高比修正已添加
- PCF 抖动静样设计合理

**问题**：
- **PCF 性能代价过大**：每像素跑 N 次完整光线步进，N=4 时性能降为 1/4
- **PCF 抖动范围太小**：±0.5 像素的抖动对阴影边缘柔化效果有限，应考虑沿光源垂直方向更大范围的抖动
- `luminance_coordinates` 变量计算了但未使用
- `step_dist < 0.01` 阈值固定，与分辨率无关
- PCF 的 hash 函数用 `coordinates + ivec2(j*137, j*73)` 做种子，帧间不变（无时域变化），静态噪点无法被时域累积消除

**改进建议**：
- PCF 改为沿光源垂直方向抖动（而非全方向），用更少样本达到更好效果
- hash 加入帧号（`time`）做时域变化，配合 temporal pass 消除噪点
- `step_dist < 0.01` 阈值改为 `min_step_uv * 2`
- 移除未使用变量
- 考虑用 2D 软阴影（PCSS）替代简单 PCF

---

## 管线级问题

以下问题影响多个 pass，需在管线层面解决：

### 1. 宽高比修正不一致
- **已修正**：raymarch.glsl, ao_pass.glsl, directional_light_pass.glsl
- **未修正**：indirect_pass.glsl, distance_field.glsl, jump_flood.glsl, normal_pass.glsl
- **影响**：JFA/SDF 的距离计算在非正方形视口下有偏差，影响所有下游 pass

### 2. 重复的光线步进代码
- raymarch.glsl 的 `march_ray()` 和 indirect_pass.glsl 的 `march_indirect_ray()` 高度重复
- 应合并为统一函数，通过参数控制行为

### 3. 降噪管线冗余
- denoise.glsl 和 atrous.glsl 功能重叠
- 建议统一使用 atrous.glsl（有深度引导，效果更好）

### 4. 输出格式不一致
- denoise.glsl 输出 `rgba8`，其他 pass 输出 `rgba16f`
- 会导致精度损失和格式转换开销

### 5. 时域累积覆盖不全
- temporal.glsl 仅用于 GI（PassRM → PassTemporal）
- AO 和平行光无时域累积，噪点无法通过帧间平均消除

---

## 优先级排序的改进建议

| 优先级 | 改进项 | 涉及文件 | 预期收益 |
|:------:|--------|----------|----------|
| P0 | 修正 indirect_pass.glsl 宽高比 | indirect_pass.glsl | 修复椭圆变形 |
| P0 | 修正 composite_pass.glsl 平行光混合逻辑 | composite_pass.glsl | 修复阴影颜色错误 |
| P0 | denoise.glsl 输出格式改 rgba16f | denoise.glsl | 修复精度损失 |
| P1 | 合并 raymarch + indirect_pass | raymarch.glsl, indirect_pass.glsl | 减少代码重复 + 性能提升 |
| P1 | atrous.glsl 可分离优化 | atrous.glsl | 性能提升约 2 倍 |
| P1 | temporal.glsl 加入运动矢量 | temporal.glsl | 消除相机移动鬼影 |
| P1 | directional_light PCF 加入帧号 hash | directional_light_pass.glsl | 时域累积消除噪点 |
| P2 | JFA/SDF 距离计算加宽高比 | jump_flood.glsl, distance_field.glsl | 提升非正方形视口精度 |
| P2 | normal_pass.glsl 加宽高比 | normal_pass.glsl | 提升法线质量 |
| P2 | sharpen.glsl 可分离优化 | sharpen.glsl | 性能提升 |
| P2 | ao_pass.glsl 实现标准 SSAO | ao_pass.glsl | 提升 AO 质量 |
| P3 | 移除各 pass 未使用变量 | 多个文件 | 代码清洁 |
| P3 | 统一 step_dist 阈值为分辨率相关 | 多个文件 | 提升一致性 |
