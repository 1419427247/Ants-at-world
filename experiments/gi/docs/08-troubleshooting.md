# 故障排查与 FAQ

> 版本: 1.0 | 更新日期: 2026-06-24

本文档针对 Godot 4 的 2D GI（全局光照）系统（基于 Compute Shader 实现）整理常见错误与高频问题。内容来源于项目开发历史中遇到的实际问题及解决方案。

---

## 常见错误

### 1. Push constant 大小不匹配

- **症状**: 运行时报错 `This compute pipeline requires (N) bytes of push constant data, supplied: (M)`
- **原因**: `_get_push_data()` 的 `resize()` 大小与 GLSL 中 `push_constant` 结构体不一致。
- **解决**: 检查 `std430` 对齐规则：
  - `int` / `float` = 4 字节
  - `vec2` = 8 字节
  - `vec4` = 16 字节
  - 注意 `CompositePass` 在 offset 8-15 有隐式填充，需在 PackedByteArray 中预留对应字节。

---

### 2. 采样器属性名错误

- **症状**: `RDSamplerState` 找不到 `mipmap_filter` 属性。
- **原因**: Godot 4 中 `RDSamplerState` 使用 `mip_filter` 而非 `mipmap_filter`。
- **解决**: 将所有 `mipmap_filter` 改为 `mip_filter`。

---

### 3. 光线穿透障碍物

- **症状**: 光照出现在墙壁后方，光线异常穿透固体。
- **原因**: 障碍物检测逻辑错误，使用 `surface.a > 0.0` 检测障碍物不正确（半透明或非发光像素也会被误判）。
- **解决**: 使用 `brightness > emissive_threshold` 检测发光体；非发光固体自动阻挡光线，无需额外判断 alpha。

---

### 4. 背景变白/消失

- **症状**: 空区显示白色或背景丢失。
- **原因**: `gi_display.gdshader` 的 alpha 混合逻辑错误，AO 影响了原始场景颜色。
- **解决**:
  - AO 只影响光照层，不应直接作用于原始场景。
  - 使用 `mix(vec3(0.0), scene + lighting, scene_alpha)` 而非直接混合原始颜色。

---

### 5. 只有垂直方向模糊

- **症状**: `BlurH` 不生效，只有 `BlurV` 起作用。
- **原因**: 两个方向都从原图采样，而非串联执行。
- **解决**: `BlurH` → `BlurV` 串联，第二个 Pass 从第一个的输出采样。

---

### 6. 距离场 GB 通道理解错误

- **症状**: 光线步进行为异常，方向错乱。
- **原因**: 误认为距离场纹理的 GB 通道是 UV 坐标。
- **解决**: GB 通道是指向最近异质点的方向向量（归一化），不是 UV 坐标。

---

### 7. image2D vs sampler2D 混用

- **症状**: 着色器编译错误或采样结果不正确。
- **原因**: Compute Shader 中 `image2D`（storage image）和 `sampler2D`（sampled texture）使用方式不同，混用会导致语义和绑定类型不匹配。
- **解决**:
  - 输入用 `sampler2D` + `texture()` 采样。
  - 输出用 `image2D` + `imageStore()` 写入。
  - binding 类型要匹配：`UNIFORM_TYPE_SAMPLER_WITH_TEXTURE` vs `UNIFORM_TYPE_IMAGE`。

---

## FAQ

### Q1: 为什么需要 8 个 JumpFloodPass？

**A**: Jump Flood Algorithm 的步长按 2 的幂递减（256 → 128 → 64 → … → 2）。对于 1024×1024 纹理，最大步长 256 可覆盖全图，8 步保证精度。可减少到 6 步（步长 2, 4, 8, 16, 32, 64）以牺牲少量精度换取性能。

---

### Q2: 为什么 Composite 的 gi_texture 直接取自 PassRM 而非降噪链路？

**A**: 当前设计中 `TemporalPass` 和 `BlurH`/`BlurV` 的输出仅用于调试预览。如需接入降噪链路，将 Composite 脚本中的 `pass_gi` 改为指向 `BlurV` 即可。但需注意过度模糊问题。

---

### Q3: 如何添加新的 ComputePass？

**A**:
1. 创建继承 `ComputePass` 的 `.gd` 脚本；
2. 创建对应的 `.glsl` compute shader；
3. 在 `_init()` 中设置 `shader_path`；
4. 覆盖 `_get_push_data()` 返回参数；
5. 在 `gi.tscn` 的 `Composite` 下添加 Node 并挂载脚本；
6. 配置 `source_viewport` 或 `primary_input`。

---

### Q4: 哪些 Pass 已实现但未在场景中使用？

**A**: 以下 Pass 是预备构建块，可按需接入：
- `IndirectPass`（多跳间接光照）
- `ATrousPass`（小波降噪）
- `CompositePass`（compute 合成）
- `DenoisePass`（双边降噪）
- `SharpenPass`（锐化）

---

### Q5: 为什么使用 sampler2D 而非 image2D 读取输入？

**A**: `sampler2D` 配合 `texture()` 可使用硬件过滤（双线性/最近邻），且语义更清晰。`image2D` 主要用于写入（`imageStore`）。输入纹理只需读取，用 `sampler2D` 更合适。

---

### Q6: 如何调整 GI 分辨率？

**A**: 修改 `GILightViewport` 的 `size` 属性（默认 1024×1024）。所有 Pass 会自动适配。降低分辨率可大幅提升性能但降低精度。

---

### Q7: raymarch_rotation_speed 有什么用？

**A**: 控制射线每帧旋转角度（弧度/秒）。配合少量射线（如 `num_samples=3`），利用视觉暂留效应产生动态万花筒/流光效果。设为 `0` 则静止。
