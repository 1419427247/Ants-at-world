# 2D GI 系统未来计划路线图

> 版本: 1.0 | 更新日期: 2026-06-24

本文档为 Godot 4 的 2D GI（全局光照）系统规划未来开发路线。所有任务状态均基于 `experiments/gi/` 目录下的实际代码与 `gi.tscn` 场景配置核实，并修正了早期 `GI_ANALYSIS.md` 中与现状不符的描述。

> **状态标注约定**
> - ✅ **已实现**：代码已存在且功能完整（标注“未接入”表示已实现但未在 `gi.tscn` 中挂载使用）
> - 🔧 **部分实现**：核心代码已存在，但存在未接入合成、缺少子项或仅用于调试预览等情况
> - 📋 **未实现**：代码中尚不存在，需新增

---

## 阶段一：性能基础（优先级：高）

本阶段聚焦于降低 GPU 开销，目标是在不损失视觉质量的前提下将帧时间降低 50%+。最大瓶颈为 Jump Flood 链路（8 个 Pass 全分辨率执行，约 7500 万次纹理采样/帧）。

| 任务名 | 状态 | 预期收益 | 涉及文件 |
|--------|------|----------|----------|
| 距离场脏标记：场景几何静止时跳过 `SeedPass`→`JF×8`→`DF` 链路 | 📋 未实现 | 静态场景耗时 -90%+ | `compute_pass.gd`, `gi_light_viewport.gd`, `gi.tscn` |
| 距离场半分辨率计算（512×512） | 📋 未实现 | JF 采样 -75% | `distance_field_pass.gd`, `jump_flood_pass.gd` |
| AO 降至 1/4 分辨率（256×256） | 📋 未实现 | AO 采样 -93% | `ao_pass.gd` |
| 纹理格式精简（DF 用 RGB16F、AO 用 R8、DirLight 用 RG16F） | 📋 未实现 | 显存带宽 -30% | 各 `*_pass.gd` 的 `_get_output_format` |
| Dispatch 合并：将无依赖的 `PassDirectionalLight` 与 `PassAO` 合并到同一 `compute_list` | 📋 未实现 | 减少 GPU 命令开销 | `compute_pass.gd`, `gi.tscn` |
| 共享内存优化：模糊/时间累积 Pass 用 `shared` memory 预加载邻域 | 📋 未实现 | 全局内存访问 -80%（模糊类 Pass） | `blur.glsl`, `temporal.glsl` |

---

## 阶段二：效果提升（优先级：中）

本阶段聚焦于提升视觉质量。多项核心能力已实现（间接光照 Pass、可分离模糊降噪、法线生成、距离场引导 AO、射线旋转万花筒），重点在于将这些已实现的能力接入最终合成链路。

| 任务名 | 状态 | 预期收益 | 涉及文件 |
|--------|------|----------|----------|
| 多跳间接光照（`IndirectPass`，2-bounce GI） | ✅ 已实现(未接入) | 间接光更真实，色彩溢出；代码已就绪，需在场景中挂载 | `indirect_pass.gd`, `indirect_pass.glsl`, `gi.tscn` |
| 可分离高斯模糊降噪（`BlurH`+`BlurV` 替代 `ATrousPass`） | ✅ 已实现 | 5×5 采样从 25 次降至 10 次，性能提升 2.5× | `blur_pass.gd`, `blur.glsl` |
| 降噪链路接入 `gi_display.gdshader` 合成 | 🔧 部分实现 | 启用完整时间+空间降噪，消除噪声 | `gi.tscn`（改 `pass_gi` 指向 `BlurV`）, `gi_display.gdshader` |
| AO 距离场引导采样（`ao_df_guide_weight`） | ✅ 已实现 | 复杂几何场景遮蔽精度提升 | `ao_pass.gd`, `ao_pass.glsl` |
| 法线图生成（`NormalPass`，Sobel 算子） | ✅ 已实现 | 为双边滤波提供法线引导基础 | `normal_pass.gd`, `normal_pass.glsl` |
| 法线权重接入双边滤波 | 🔧 部分实现 | 减少不同表面间的光线渗透（light leaking） | `blur.glsl`, `normal_pass.gd`, `gi.tscn` |
| 射线旋转万花筒/流光效果（`raymarch_rotation_offset`/`speed`） | ✅ 已实现 | 低采样下等效提升光线覆盖范围 | `raymarch_pass.gd`, `raymarch.glsl` |
| AO 接入 `TemporalPass` 时间累积 | 📋 未实现 | AO 噪声大幅降低 | `gi.tscn` 重新连线 |
| 软阴影（百分比渐近过滤 PCF） | 📋 未实现 | 阴影边缘自然过渡，产生半影 | `directional_light_pass.glsl` |

---

## 阶段三：高级特性（优先级：低）

本阶段聚焦于提升物理正确性与高级渲染特性，适用于对画质有更高要求的场景。

| 任务名 | 状态 | 预期收益 | 涉及文件 |
|--------|------|----------|----------|
| 运动矢量 + 历史帧重投影 | 📋 未实现 | 消除运动场景下的残影与过度模糊 | 新增 `motion_vector_pass.gd/glsl`, `temporal.glsl` |
| 辐射度缓存：空间接近像素复用光线命中结果 | 📋 未实现 | Raymarch 采样需求降低 | 新增 `radiosity_cache_pass.gd/glsl` |
| 多尺度 AO（类 HBAO，多半径混合） | 📋 未实现 | 兼顾近处细节与远处大范围遮蔽 | `ao_pass.glsl` |
| 半球 AO 采样（地面像素仅采样上半球） | 📋 未实现 | 避免地面下方无效采样造成的过度遮蔽 | `ao_pass.glsl` |
| 自适应采样（高频区域多采样，平坦区域少采样） | 📋 未实现 | 同等画质下采样数 -30%~50% | `raymarch.glsl` |
| 物理衰减模型（`1/d²` 替代 `1/(1+d*att)`） | 📋 未实现 | 远处光照符合能量守恒，更物理正确 | `raymarch.glsl` |
| 重要性采样（距离场方向偏向可能命中光源方向） | 📋 未实现 | 同等采样数下光照收敛更快 | `raymarch.glsl` |
| YCoCg 空间 AABB Clamp | 📋 未实现 | 时间累积防拖尾更符合人眼感知 | `temporal.glsl` |
| 置信度权重（动态调整时间混合因子） | 📋 未实现 | 运动区域响应更快，静止区域更平滑 | `temporal.glsl` |

---

## 阶段四：工程化（优先级：低）

本阶段聚焦于架构改进与开发效率，为长期维护与扩展奠定基础。

| 任务名 | 状态 | 预期收益 | 涉及文件 |
|--------|------|----------|----------|
| PassGraph 依赖图：声明式描述 Pass 依赖，自动拓扑排序与并行调度 | 📋 未实现 | 支持并行分支（如 DirLight 与 AO 并行），管线可维护性提升 | 新增 `pass_graph.gd` |
| 调试视图切换器：单视图切换查看距离场/AO/法线/降噪前后对比 | 📋 未实现 | 替代当前 `GridContainer` 罗列预览，开发效率提升 | 新增 `debug_view.gd`, `gi.tscn` |
| 动态分辨率：根据帧率自动调整 Raymarch 分辨率 | 📋 未实现 | 自适应性能，低于 60fps 降至 512，高于 120fps 升至 2048 | `compute_pass.gd` |
| 1+1 JFA（正反两次 Jump Flood） | 📋 未实现 | JF 采样 -50%，精度不降 | `jump_flood_pass.gd`, `jump_flood.glsl` |
| 可变步长平行光（距离场动态调整步长） | 📋 未实现 | 近距离保精度，远距离保速度 | `directional_light_pass.glsl` |
| 二次高度插值（`smoothstep` 替代线性插值） | 📋 未实现 | 阴影过渡更自然 | `directional_light_pass.glsl` |

---

## 实施优先级建议

1. **零成本启用降噪链路**（阶段二）：仅需在 `gi.tscn` 中将 `pass_gi` 由 `PassRM` 改指向 `BlurV`，即可启用完整时间+空间降噪，是最高性价比改进。
2. **距离场脏标记 + 分辨率分层**（阶段一）：预期帧时间降低 50%+，静态场景收益最大。
3. **接入 `IndirectPass`**（阶段二）：代码已就绪，挂载后即可获得 2-bounce 间接光照，显著提升真实感。
4. **运动矢量**（阶段三）：解决运动场景下的时间累积退化问题。
5. **PassGraph**（阶段四）：长期架构改进，为并行调度与扩展打基础。

---

## 与早期文档（`GI_ANALYSIS.md`）的关键修正

| 项 | 早期文档描述 | 实际现状（本路线图基准） |
|----|--------------|--------------------------|
| 多跳间接光照 | 建议新增 | ✅ `IndirectPass` 已实现，仅未接入场景 |
| 降噪方式 | `ATrousPass ×3` | ✅ 已改为 `BlurH`+`BlurV` 可分离高斯模糊 |
| 法线生成 | 未提及 | ✅ `NormalPass` 已实现（Sobel 算子） |
| AO 采样策略 | 纯黄金角度 | ✅ 已实现距离场引导采样（`ao_df_guide_weight`） |
| 万花筒效果 | 未提及 | ✅ `raymarch_rotation_offset`/`speed` 已实现 |
| 距离场脏标记 | 建议新增 | 📋 仍未实现 |
| 运动矢量 | 建议新增 | 📋 仍未实现 |
| PassGraph 依赖图 | 建议新增 | 📋 仍未实现 |
| 动态分辨率 | 建议新增 | 📋 仍未实现 |
