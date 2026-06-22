# 2D GI 管线分析与优化文档

## 一、管线总览

当前 GI 管线由以下 Pass 组成（按执行顺序）：

| # | Pass | 作用 | 输入 | 输出格式 |
|---|------|------|------|----------|
| 1 | ScalePass | 缩放源视口纹理到目标尺寸 | SourceViewport | RGBA16F |
| 2 | SeedPass | 初始化 Jump Flood 种子（固体UV→RG，空区UV→BA） | ScalePass | RGBA16F |
| 3-10 | JumpFloodPass ×8 | 跳洪泛洪计算 Voronoi（最近固体/空区 UV） | 前一级 JF | RGBA16F |
| 11 | DistanceFieldPass | Voronoi → 有向距离场（R=距离, GB=方向） | JF8 | RGBA16F |
| 12 | RaymarchPass | 距离场加速光线步进，收集直接光照 | ScalePass + DF | RGBA16F |
| 13 | DirectionalLightPass | 平行光沿方向投射，带高度场阴影 | ScalePass + DF | RGBA16F |
| 14 | AOPass | 附近采样计算环境光遮蔽 | ScalePass + DF | RGBA16F |
| 15 | TemporalPass | 帧间指数移动平均（EMA + AABB Clamp） | RaymarchPass | RGBA16F |
| 16-18 | ATrousPass ×3 | A-Trous 小波滤波降噪（step=1,2,4） | 前一级 + DF | RGBA16F |
| 19 | ScalePass2 | 最终缩放输出 | ATrous3 | RGBA16F |
| 20 | Display | ACES 色调映射 + sRGB 转换 | ScalePass2 | — |

### 核心数据流

```
SourceViewport
    │
    ▼
ScalePass ──────────────────────────────────┐
    │                                        │
    ▼                                        │
SeedPass → JF×8 → DistanceFieldPass ────────┤
    │                       │                │
    │                       ▼                ▼
    │              RaymarchPass    DirectionalLightPass  AOPass
    │                       │                │            │
    │                       ▼                │            │
    │              TemporalPass              │            │
    │                       │                │            │
    │                       ▼                │            │
    │              ATrousPass ×3             │            │
    │                       │                │            │
    │                       ▼                │            │
    │              ScalePass2                │            │
    │                       │                │            │
    └───────────────────────┴────────────────┴────────────┘
                            │
                            ▼
                         Display (ACES + sRGB)
```

---

## 二、效果优化分析

### 2.1 光线步进（RaymarchPass）

**当前问题：**
- 每像素仅 8 条光线，间接光照采样不足
- 光线遇到非发光固体即终止，无法产生间接反弹
- 衰减模型过于简单（`1/(1+d*att)`），缺乏物理正确性

**优化建议：**
1. **多跳间接光照**：当前仅收集直接发光体。可在 Raymarch 输出上再次步进，收集被照亮的表面作为次级光源，实现 2-bounce 甚至 3-bounce GI
2. **重要性采样**：当前使用均匀黄金角度分布。可根据距离场方向偏向更有可能命中光源的方向
3. **辐射度缓存**：对空间上接近的像素复用光线命中结果，减少光线总数
4. **更好的衰减模型**：使用 `1/d²` 物理衰减替代当前线性衰减

### 2.2 平行光阴影（DirectionalLightPass）

**当前问题：**
- 线性高度插值 `mix(origin, height, t)` 不够精确
- 最大 32 步可能在复杂场景中产生漏光
- 阴影无半影（penumbra）效果

**优化建议：**
1. **百分比渐近过滤（PCF）**：在阴影判定时采样多个邻近像素，产生软阴影
2. **二次高度插值**：使用 `smoothstep` 替代线性插值，阴影过渡更自然
3. **可变步长**：根据距离场动态调整步长，近距离用小步长保精度，远距离用大步长保速度

### 2.3 环境光遮蔽（AOPass）

**当前问题：**
- 仅基于高度差判断遮挡，未考虑水平距离衰减的物理正确性
- 采样点在物体内部时直接计为遮挡，可能过度遮蔽
- 无时间累积，噪声较大

**优化建议：**
1. **半球采样**：当前为全圆采样。对于地面像素，应只采样上半球方向
2. **距离场引导采样**：利用距离场的方向分量（GB 通道），优先在可能有遮挡的方向采样
3. **与 TemporalPass 串联**：AO 结果也应经过时间累积，大幅降低噪声
4. **多尺度 AO**：类似 HBAO，在不同半径下计算 AO 并混合，兼顾近处细节和远处大范围遮蔽

### 2.4 时间累积（TemporalPass）

**当前问题：**
- 仅使用 AABB Clamp 防拖尾，无运动矢量（motion vector）
- 场景运动时会产生残影或过度模糊
- 混合因子固定，无法根据像素置信度自适应

**优化建议：**
1. **运动矢量**：在 SourceViewport 中追踪物体运动，TemporalPass 中按运动矢量重投影历史帧
2. **置信度权重**：根据 AABB Clamp 是否触发、历史与当前差异大小，动态调整混合因子
3. **YCoCg 空间 Clamp**：在 YCoCg 色彩空间做 AABB Clamp，比 RGB 空间更符合人眼感知

### 2.5 降噪（ATrousPass）

**当前问题：**
- 3 个 pass 固定 step=1,2,4，无法根据噪声水平自适应
- 颜色双边权重可能过度模糊彩色光源边缘
- 无法区分直接光照（低噪声）和间接光照（高噪声）

**优化建议：**
1. **G-Buffer 引导**：引入法线/材质 ID 图，在双边权重中加入法线权重，防止不同表面光线渗透
2. **自适应迭代次数**：根据 TemporalPass 的帧计数动态调整 ATrous 迭代次数（首帧多迭代，累积后少迭代）
3. **可分离滤波**：当前 5×5 为 25 次采样。可拆为水平 5 + 垂直 5 = 10 次采样，性能提升 2.5×

---

## 三、性能优化分析

### 3.1 Jump Flood 优化（当前最大瓶颈）

**现状：** 8 个 JumpFloodPass，每个 pass 对全图每像素做 3×3=9 次纹理采样。1024×1024 分辨率下总计：
- 8 passes × 1024² × 9 samples = **~7500 万次纹理采样/帧**

**优化方案：**

| 方案 | 预期收益 | 复杂度 |
|------|----------|--------|
| 减少到 6 passes（step 2,4,8,16,32,64） | -25% 采样 | 低 |
| 1+1 JFA（正反两次 JFA） | -50% 采样，精度不降 | 中 |
| 仅在分辨率变化时重算距离场 | -90%+（静态场景） | 中 |
| 半分辨率距离场 | -75% 采样 | 低 |

**推荐：** 距离场在场景几何不变时无需重算。添加脏标记，仅在源视口内容变化时重新执行 SeedPass→JF→DF 链路。

### 3.2 纹理格式优化

**现状：** 几乎所有中间纹理使用 RGBA16F（64 bits/pixel）

| 纹理 | 当前格式 | 可用格式 | 节省 |
|------|----------|----------|------|
| SeedPass / JumpFlood | RGBA16F (64bit) | RG16F + RG16F 拆分 或 RGBA16F | 已较优 |
| DistanceField | RGBA16F (64bit) | R16G16_SFLOAT (32bit)¹ | -50% |
| AOPass 输出 | RGBA16F (64bit) | R8_UNORM (8bit) | -87% |
| DirectionalLight 输出 | RGBA16F (64bit) | RG16F (32bit)² | -50% |

¹ 距离场 R=距离, GB=方向，实际只需 3 通道，可用 R16G16B16_SFLOAT (48bit)
² 平行光输出 R=可见性, G=遮挡距离，仅需 2 通道

### 3.3 分辨率分层

**现状：** 所有 Pass 在同一分辨率（1024×1024）执行

**优化方案：**
- **距离场**：半分辨率（512×512）计算，足够引导光线步进
- **Raymarch**：半分辨率计算，通过 TemporalPass + ATrous 恢复质量
- **AO**：1/4 分辨率计算，AO 本身为低频信息
- **最终 ScalePass**：bicubic 上采样回全分辨率

预期总纹理采样减少 **~60%**

### 3.4 Dispatch 合并

**现状：** 每个 Pass 独立 dispatch，存在多次 compute_list_begin/end 开销

**优化方案：** 将无依赖的 Pass（如 DirectionalLight 和 AO）合并到同一 compute_list 中，减少 GPU 命令开销。

### 3.5 共享内存优化

**现状：** 所有 Pass 使用 `imageLoad` 全局内存采样

**优化方案：** 在 ATrousPass 和 TemporalPass 中使用 `shared` memory 预加载邻域数据，减少全局内存访问。16×16 线程组共享 18×18 像素数据，每像素仅 1 次全局加载。

---

## 四、架构改进建议

### 4.1 Pass 依赖图

**现状：** ComputePass 通过 `primary_input` 和 `extra_input_sources` 手动指定依赖，通过 `frame_counter` 防止重复消费。兄弟节点按 index 顺序自动链式连接。

**问题：**
- 无法表达并行分支（DirectionalLight 和 AO 互不依赖但都依赖 DF）
- 场景树顺序即执行顺序，不直观

**建议：** 引入显式 PassGraph 资源，声明式描述依赖关系，自动拓扑排序并调度并行 Pass。

### 4.2 动态分辨率

**建议：** 根据帧率自动调整 Raymarch 分辨率。低于 60fps 时降级到 512×512，高于 120fps 时升到 2048×2048。

### 4.3 调试视图

**建议：** 添加调试 Pass 切换器，可单独查看：
- 距离场热力图
- 光线命中次数
- AO 因子
- 时间累积置信度
- 降噪前后对比

---

## 五、未来详细计划

### 阶段一：性能基础（优先级：高）

| 任务 | 预期收益 | 涉及文件 |
|------|----------|----------|
| 距离场脏标记：场景静止时跳过 JF 链路 | -90% 静态场景耗时 | compute_pass.gd, gi.tscn |
| 距离场半分辨率计算 | -75% JF 采样 | distance_field_pass.gd, jump_flood_pass.gd |
| AO 降至 1/4 分辨率 | -93% AO 采样 | ao_pass.gd |
| 纹理格式精简 | -30% 显存带宽 | 各 *_pass.gd 的 `_get_output_format` |

### 阶段二：效果提升（优先级：中）

| 任务 | 效果提升 | 涉及文件 |
|------|----------|----------|
| 多跳间接光照（2-bounce） | 间接光更真实，色彩溢出 | 新增 indirect_pass.gd/glsl |
| AO 接入 TemporalPass | AO 噪声大幅降低 | gi.tscn 重新连线 |
| 软阴影（PCF） | 阴影边缘自然过渡 | directional_light_pass.glsl |
| ATrous 法线权重 | 减少光线渗透 | atrous.glsl, 新增法线 Pass |

### 阶段三：高级特性（优先级：低）

| 任务 | 效果 | 涉及文件 |
|------|------|----------|
| 运动矢量 + 重投影 | 消除运动残影 | 新增 motion_vector_pass, temporal.glsl |
| 辐射度缓存 | 降低 Raymarch 采样需求 | 新增 radiosity_cache_pass |
| 多尺度 AO | 兼顾近处细节与远处遮蔽 | ao_pass.glsl |
| 自适应采样 | 高频区域多采样，平坦区域少采样 | raymarch.glsl |

### 阶段四：工程化（优先级：低）

| 任务 | 效果 | 涉及文件 |
|------|------|----------|
| PassGraph 依赖图 | 声明式管线，支持并行调度 | 新增 pass_graph.gd |
| 调试视图切换器 | 开发效率提升 | 新增 debug_view.gd |
| 动态分辨率 | 自适应性能 | compute_pass.gd |
| 共享内存优化 | 降低带宽瓶颈 | atrous.glsl, temporal.glsl |

---

## 六、关键参数调优指南

### RaymarchPass
| 参数 | 当前值 | 推荐范围 | 说明 |
|------|--------|----------|------|
| raymarch_num_samples | 8 | 4-16 | 与 TemporalPass 配合，低采样+高累积更优 |
| raymarch_attenuation | 3.0 | 1.0-5.0 | 越大光衰减越快，场景越暗 |
| raymarch_max_distance | 0.8 | 0.3-0.9 | 降低可提升性能但减少远处光照 |
| raymarch_max_steps | 32 | 16-64 | 距离场加速下 32 步通常足够 |

### TemporalPass
| 参数 | 当前值 | 推荐范围 | 说明 |
|------|--------|----------|------|
| temporal_blend_factor | 0.2 | 0.05-0.3 | 越低越平滑但延迟越大 |

### ATrousPass
| 参数 | 当前值 | 推荐范围 | 说明 |
|------|--------|----------|------|
| atrous_color_sigma | 0.2 | 0.1-0.5 | 越小越保边但噪声残留越多 |
| atrous_depth_sigma | 0.05 | 0.02-0.1 | 基于距离场，越小越保几何边缘 |

### AOPass
| 参数 | 当前值 | 推荐范围 | 说明 |
|------|--------|----------|------|
| ao_num_samples | 16 | 8-32 | 接入 Temporal 后可降至 8 |
| ao_radius | 0.05 | 0.02-0.1 | 越大遮蔽范围越广但性能越低 |
| ao_bias | 0.01 | 0.005-0.02 | 防止平面自遮挡 |

---

## 七、总结

当前管线已实现完整的 2D GI 基础框架：距离场加速光线步进、时间累积降噪、A-Trous 空间降噪。主要瓶颈在于：

1. **Jump Flood 链路过重**：8 个 Pass 始终全分辨率执行，是最大性能瓶颈
2. **缺乏多跳间接光照**：当前仅直接光照，间接光缺失
3. **时间累积无运动矢量**：运动场景下效果退化
4. **AO 未接入降噪管线**：独立运行，噪声无法消除

优先实施**距离场脏标记**和**分辨率分层**可获得最大性能收益，预期帧时间降低 50%+。其次接入 AO 到 TemporalPass 管线并实现 2-bounce 间接光照，可显著提升视觉质量。
