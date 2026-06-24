# 场景配置

> 版本: 1.0 | 更新日期: 2026-06-24

本文档说明 `experiments/gi/gi.tscn` 场景的节点结构、各 Pass 配置、合成与调试预览机制，以及常见场景编辑操作指南。所有内容基于实际 `.tscn` 文件与配套 GDScript 整理。

---

## 一、节点树结构

以下是 `gi.tscn` 的完整节点树（缩进表示父子关系，`[...]` 内为关键属性）：

```
GI (Node) [script: GDScript_camera_controller]
├── ColorRect (ColorRect)
│       [material: ShaderMaterial_ikwhx → soil.gdshader]
│       [anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0]
│
├── Camera2D (Camera2D)
│       [position: (525, 521)]
│
├── GILightViewport (SubViewport)
│       [transparent_bg=true, use_hdr_2d=true]
│       [size: (1024, 1024)]
│       [render_target_update_mode=4 (ALWAYS)]
│       [script: gi_light_viewport.gd]
│
├── Composite (ColorRect)
│       [visible=false]
│       [material: ShaderMaterial_composite → gi_display.gdshader]
│       [offset_right=128, offset_bottom=128]
│       [mouse_filter=2 (IGNORE)]
│       [script: GDScript_composite]
│       [pass_gi=NodePath("PassRM"), pass_directional=NodePath("PassDirectionalLight"), pass_ao=NodePath("PassAO")]
│       [metadata/_edit_lock_=true]
│   │
│   ├── ScalePassHalf (Node) [scale_pass.gd]
│   │       [scale_target_width=512, scale_target_height=512]
│   │       [source_viewport=NodePath("../../GILightViewport")]
│   │
│   ├── ScalePassQuarter (Node) [scale_pass.gd]
│   │       [scale_target_width=256, scale_target_height=256]
│   │       [source_viewport=NodePath("../../GILightViewport")]
│   │
│   ├── PassNormal (Node) [normal_pass.gd]
│   │       [normal_blur_radius=2]
│   │       [source_viewport=NodePath("../../GILightViewport")]
│   │
│   ├── PassSeed (Node) [seed_pass.gd]
│   │       [source_viewport=NodePath("../../GILightViewport")]
│   │
│   ├── PassJF1 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=2]
│   ├── PassJF2 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=4]
│   ├── PassJF3 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=8]
│   ├── PassJF4 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=16]
│   ├── PassJF5 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=32]
│   ├── PassJF6 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=64]
│   ├── PassJF7 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=128]
│   ├── PassJF8 (Node) [jump_flood_pass.gd]  [jump_flood_step_divisor=256]
│   │
│   ├── PassDF (Node) [distance_field_pass.gd]
│   │
│   ├── PassRM (Node) [raymarch_pass.gd]
│   │       [raymarch_num_samples=32]
│   │       [source_viewport=NodePath("../../GILightViewport")]
│   │       [extra_input_sources=[NodePath("../PassDF")]]
│   │
│   ├── PassTemporal (Node) [temporal_pass.gd]
│   │
│   ├── BlurH (Node) [blur_pass.gd]
│   │       [blur_direction=0 (水平)]
│   │
│   ├── BlurV (Node) [blur_pass.gd]
│   │       [blur_direction=1 (垂直)]
│   │
│   ├── PassDirectionalLight (Node) [directional_light_pass.gd]
│   │       [light_direction=Vector2(-1, 1)]
│   │       [source_viewport=NodePath("../../GILightViewport")]
│   │       [extra_input_sources=[NodePath("../PassDF")]]
│   │
│   └── PassAO (Node) [ao_pass.gd]
│           [source_viewport=NodePath("../../GILightViewport")]
│           [extra_input_sources=[NodePath("../PassDF")]]
│
├── GridContainer (GridContainer)
│       [anchors_preset=15, anchor_right=1.0, anchor_bottom=1.0]
│       [columns=7]
│       [metadata/_edit_lock_=true, _edit_group_=true]
│   │
│   ├── ScaleHalfTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/ScalePassHalf]
│   ├── ScaleQuarterTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/ScalePassQuarter]
│   ├── NormalTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassNormal]
│   ├── SeedTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassSeed]
│   ├── JF1TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF1]
│   ├── JF2TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF2]
│   ├── JF3TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF3]
│   ├── JF4TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF4]
│   ├── JF5TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF5]
│   ├── JF6TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF6]
│   ├── JF7TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF7]
│   ├── JF8TextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassJF8]
│   ├── DFTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassDF]
│   ├── RMTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassRM]
│   ├── TemporalTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassTemporal]
│   ├── BlurHTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/BlurH]
│   ├── BlurVTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/BlurV]
│   ├── DirectionalLightTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassDirectionalLight]
│   └── AOTextureRect (TextureRect) [texture_from_pass.gd, compute_pass=../../Composite/PassAO]
│       (每个 TextureRect: texture_filter=3, custom_minimum_size=(128,128), layout_mode=2, expand_mode=1)
│
└── GIElement (Node2D)
        [position: (402, 227)]
        [script: gi_element.gd]
        [gi_light_viewport=NodePath("../GILightViewport")]
    │
    ├── Sprite2D (Sprite2D)
    │       [scale: (0.2, 0.2), texture: circle.png]
    │
    ├── Sprite2D2 (Sprite2D)
    │       [position: (299, -108), scale: (293.75, 63.5), texture: 1px.png]
    │
    └── Sprite2D3 (Sprite2D)
            [modulate: Color(0,0,0,1)]
            [position: (-248.9375, 419.625), scale: (129.87502, 388.75), texture: 1px.png]
```

---

## 二、各 Pass 节点关键属性配置

### 2.1 缩放 Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `ScalePassHalf` | `scale_pass.gd` | `scale_target_width=512, scale_target_height=512` | 下采样到 512×512，仅调试预览 |
| `ScalePassQuarter` | `scale_pass.gd` | `scale_target_width=256, scale_target_height=256` | 下采样到 256×256，仅调试预览 |

两者均设置 `source_viewport` 指向 `GILightViewport`，以视口纹理作为主输入。

### 2.2 法线 Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `PassNormal` | `normal_pass.gd` | `normal_blur_radius=2` | Sobel 采样半径，2=5×5 核 |

`source_viewport` 指向 `GILightViewport`。当前输出仅用于调试预览，未接入双边滤波。

### 2.3 种子与 Jump Flood 链路

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `PassSeed` | `seed_pass.gd` | `source_viewport=GILightViewport` | JF 初始化，输出种子图 |
| `PassJF1`~`PassJF8` | `jump_flood_pass.gd` | `jump_flood_step_divisor=2,4,8,16,32,64,128,256` | 8 次传播，步长递减 |

JF 链路通过兄弟节点顺序自动链式连接：`PassJF1` 的主输入自动取前一个兄弟 `PassSeed` 的输出，`PassJF2` 取 `PassJF1` 输出，依此类推（由 `ComputePass` 基类的"向前查找最近启用的兄弟 ComputePass"机制实现）。

### 2.4 距离场 Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `PassDF` | `distance_field_pass.gd` | 无额外配置 | 主输入自动取 `PassJF8` 输出 |

### 2.5 光线步进 Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `PassRM` | `raymarch_pass.gd` | `raymarch_num_samples=32` | 每像素 32 条光线（默认 4，场景覆盖为 32） |

- `source_viewport=GILightViewport`：以视口场景纹理作为主输入（binding 0）。
- `extra_input_sources=[PassDF]`：距离场作为额外输入（binding 2）。

### 2.6 时间累积 Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `PassTemporal` | `temporal_pass.gd` | `temporal_blend_factor=0.1`（默认） | 当前帧权重，主输入自动取 `PassRM` 输出 |

历史纹理作为内部额外输入绑定到 binding 2，由脚本自行管理。

### 2.7 模糊 Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `BlurH` | `blur_pass.gd` | `blur_direction=0`（水平） | 主输入自动取 `PassTemporal` 输出 |
| `BlurV` | `blur_pass.gd` | `blur_direction=1`（垂直） | 主输入自动取 `BlurH` 输出 |

### 2.8 平行光 Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `PassDirectionalLight` | `directional_light_pass.gd` | `light_direction=Vector2(-1, 1)` | 光传播方向 |

- `source_viewport=GILightViewport`：场景纹理作为主输入。
- `extra_input_sources=[PassDF]`：距离场作为额外输入。

### 2.9 AO Pass

| 节点 | 脚本 | 关键属性 | 说明 |
|------|------|----------|------|
| `PassAO` | `ao_pass.gd` | 默认参数 | 主输入为视口场景纹理 |

- `source_viewport=GILightViewport`。
- `extra_input_sources=[PassDF]`：距离场作为额外输入。

---

## 三、Composite 节点的 gdshader uniform 注入逻辑

`Composite` 节点是一个 `ColorRect`，挂载了 `gi_display.gdshader` 的 `ShaderMaterial`（`ShaderMaterial_composite`），并通过内联脚本 `GDScript_composite` 每帧将三个 Pass 的输出纹理 RID 注入到 shader uniform。

### 注入脚本（`GDScript_composite`）

```gdscript
extends ColorRect

@export var pass_gi: ComputePass
@export var pass_directional: ComputePass
@export var pass_ao: ComputePass

func _process(delta: float) -> void:
    var gi_texture := Texture2DRD.new()
    gi_texture.texture_rd_rid = pass_gi.get_output_resource_id()
    material.set_shader_parameter("gi_texture", gi_texture)

    var dir_tex := Texture2DRD.new()
    dir_tex.texture_rd_rid = pass_directional.get_output_resource_id()
    material.set_shader_parameter("directional_texture", dir_tex)

    var ao_tex := Texture2DRD.new()
    ao_tex.texture_rd_rid = pass_ao.get_output_resource_id()
    material.set_shader_parameter("ao_texture", ao_tex)
```

### 注入流程说明

1. **每帧执行**：`_process` 每帧创建三个 `Texture2DRD` 包装对象。
2. **RID 桥接**：通过 `ComputePass.get_output_resource_id()` 获取各 Pass 输出纹理的 RenderingDevice RID，赋值给 `Texture2DRD.texture_rd_rid`，使 Canvas Shader 能采样到 Compute Shader 的输出。
3. **uniform 注入**：用 `material.set_shader_parameter()` 将 `Texture2DRD` 注入到 `gi_display.gdshader` 的三个 uniform：
   - `gi_texture` ← `PassRM` 输出（间接光）
   - `directional_texture` ← `PassDirectionalLight` 输出（平行光阴影）
   - `ao_texture` ← `PassAO` 输出（环境光遮蔽）
4. **节点路径绑定**：场景中通过 `node_paths` 导出属性绑定：
   - `pass_gi = NodePath("PassRM")`
   - `pass_directional = NodePath("PassDirectionalLight")`
   - `pass_ao = NodePath("PassAO")`

> 注：`screen_texture` uniform 使用 `hint_screen_texture`，由 Godot 自动注入当前屏幕纹理，无需脚本处理。

> 注：当前 `pass_gi` 指向 `PassRM`（未降噪的直接光照），如需启用完整降噪链路，可将 `pass_gi` 改指向 `BlurV`。

---

## 四、GridContainer 调试预览配置

`GridContainer` 节点以 7 列网格布局罗列所有 Pass 的输出预览，便于开发时观察管线各阶段中间结果。

### 配置方式

1. **网格布局**：`columns=7`，每个 `TextureRect` 的 `custom_minimum_size=(128,128)`，`expand_mode=1`（KEEP_SIZE），`texture_filter=3`（LINEAR）。
2. **纹理来源脚本**：每个 `TextureRect` 挂载 `texture_from_pass.gd`（`TextureFromPass` 类）：

```gdscript
class_name TextureFromPass extends TextureRect

@export var compute_pass: ComputePass

func _ready() -> void:
    texture = Texture2DRD.new()

func _process(delta: float) -> void:
    texture.texture_rd_rid = compute_pass.get_output_resource_id()
```

3. **绑定机制**：每个 `TextureRect` 通过 `compute_pass` 导出属性指向 `Composite` 下的对应 Pass 节点（如 `compute_pass=NodePath("../../Composite/PassRM")`）。每帧将 Pass 输出 RID 赋值给 `Texture2DRD.texture_rd_rid`，实时显示该 Pass 的输出纹理。

### 预览项列表

共 19 个预览 `TextureRect`，按网格顺序排列：缩放半分辨率、缩放四分之一分辨率、法线、种子、JF1~JF8、距离场、光线步进、时间累积、水平模糊、垂直模糊、平行光、AO。

---

## 五、GILightViewport 配置

`GILightViewport` 是 GI 计算的源视口，所有需要场景纹理的 Pass 均通过 `source_viewport` 指向它。

### 关键属性

| 属性 | 值 | 说明 |
|------|----|------|
| `transparent_bg` | `true` | 透明背景，使空区 alpha=0 |
| `use_hdr_2d` | `true` | 启用 HDR 渲染，输出 RGBA16F 浮点纹理 |
| `size` | `Vector2i(1024, 1024)` | GI 计算分辨率 |
| `render_target_update_mode` | `4`（`UPDATE_ALWAYS`） | 每帧更新渲染目标 |
| `script` | `gi_light_viewport.gd` | 内部 Camera2D 跟随逻辑 |

### 内部 Camera2D 跟随逻辑

`GILightViewport`（`gi_light_viewport.gd`）在初始化时添加一个内部 `Camera2D`，每帧同步主视口相机的变换：

```gdscript
class_name GILightViewport extends SubViewport

var camera: Camera2D = Camera2D.new()

func _init() -> void:
    add_child(camera)

func _process(delta: float) -> void:
    camera.global_transform = get_parent().get_viewport().get_camera_2d().global_transform
```

- **`_init`**：构造时创建内部 `Camera2D` 并添加为子节点，使 SubViewport 有活动相机。
- **`_process`**：每帧将内部相机的 `global_transform` 设为主视口（父节点的视口）相机的 `global_transform`，确保 GI 视口渲染的内容与主场景视角一致。

---

## 六、GIElement 的作用

`GIElement`（`gi_element.gd`）是场景中实际放置发光体/障碍物的容器节点，负责将其子节点转移到 GI 视口渲染，并同步世界变换。

### 脚本实现

```gdscript
class_name GIElement extends Node2D

@export var gi_light_viewport: GILightViewport

var _children: Array[Node2D]

func _ready() -> void:
    _children.assign(get_children())
    for child: Node2D in get_children():
        child.reparent(gi_light_viewport, true)

func _process(delta: float) -> void:
    for child: Node2D in _children:
        child.global_transform = global_transform
```

### 工作机制

1. **`_ready`（reparent 子节点到 GI 视口）**：将 `GIElement` 下所有子节点（`Sprite2D` 等）通过 `reparent(gi_light_viewport, true)` 转移到 `GILightViewport` 内渲染。第二个参数 `true` 表示保留全局变换。同时缓存子节点引用到 `_children` 数组。
2. **`_process`（同步 transform）**：每帧将所有子节点的 `global_transform` 设为 `GIElement` 自身的 `global_transform`。这样在编辑器/主场景中移动 `GIElement` 节点，其子节点在 GI 视口内的位置会同步更新。

### 场景中的 GIElement 内容

`GIElement` 下放置了三个 `Sprite2D` 作为测试几何体：

| 节点 | 纹理 | 关键属性 | 作用 |
|------|------|----------|------|
| `Sprite2D` | `circle.png` | `scale=(0.2, 0.2)` | 小圆形发光体 |
| `Sprite2D2` | `1px.png` | `position=(299,-108), scale=(293.75, 63.5)` | 横向长条障碍物（1px 拉伸） |
| `Sprite2D3` | `1px.png` | `modulate=黑色, position=(-248.9,419.6), scale=(129.875, 388.75)` | 纵向黑色障碍物 |

> 设计意图：`GIElement` 在主场景树中可见可编辑，但其子节点实际渲染到 `GILightViewport`，供 Compute Shader 采样计算 GI。`GIElement` 的 `global_transform` 作为子节点在 GI 视口中的位置来源。

---

## 七、如何添加新 Pass 到场景

以新增一个 `PassIndirect`（多跳间接光照）为例，步骤如下：

### 步骤 1：编写 Shader 与 Pass 脚本

1. 创建 compute shader 文件，如 `experiments/gi/indirect_pass.glsl`，遵循通用约定（`#version 450`、`local_size=(16,16,1)`、binding 0=主输入、binding 1=输出、binding 2+=额外输入）。
2. 创建 Pass 脚本 `indirect_pass.gd`，继承 `ComputePass`，设置 `shader_path` 并实现 `_get_push_data()`：

```gdscript
class_name IndirectPass extends ComputePass

func _ready() -> void:
    shader_path = "res://experiments/gi/indirect_pass.glsl"
    super._ready()
```

### 步骤 2：在场景中添加节点

1. 在 Godot 编辑器中打开 `gi.tscn`。
2. 在 `Composite` 节点下右键 → 添加子节点 → 选择 `Node`，重命名为 `PassIndirect`。
3. 为 `PassIndirect` 挂载 `indirect_pass.gd` 脚本。

### 步骤 3：配置依赖关系

根据 Pass 的数据来源，在检查器中配置：

- **主输入来源**（按优先级，设置其一即可）：
  - 若以视口纹理为输入：设置 `source_viewport` 指向 `../../GILightViewport`。
  - 若以上游 Pass 输出为输入：设置 `primary_input` 指向上游 Pass（如 `PassRM`），或将其放在上游 Pass 之后作为兄弟节点（自动链式连接）。
- **额外输入**：在 `extra_input_sources` 数组中添加依赖的 Pass（如 `PassDF`），会按顺序绑定到 binding 2, 3, ...。

### 步骤 4：调整节点顺序

`ComputePass` 基类支持兄弟节点自动链式连接（向前查找最近启用的兄弟 ComputePass 作为主输入）。若希望新 Pass 自动取上游 Pass 输出，将其放在上游 Pass 之后；若设置了 `primary_input` 或 `source_viewport`，则节点顺序不影响。

### 步骤 5：添加调试预览（可选）

在 `GridContainer` 下添加一个 `TextureRect`：
1. 挂载 `texture_from_pass.gd` 脚本。
2. 设置 `compute_pass` 指向新建的 Pass 节点（如 `../../Composite/PassIndirect`）。
3. 设置 `custom_minimum_size=(128,128)`、`expand_mode=1`、`texture_filter=3`。

### 步骤 6：接入合成（如需）

若新 Pass 需参与最终合成，修改 `Composite` 节点的 `GDScript_composite` 脚本，将对应 `gi_texture` 等 uniform 的 RID 来源改为新 Pass：

```gdscript
gi_texture.texture_rd_rid = pass_indirect.get_output_resource_id()
```

并在检查器中为 `pass_gi`（或新增导出属性）绑定新 Pass 节点路径。

---

## 八、如何修改 GI 分辨率

GI 计算分辨率由 `GILightViewport` 的 `size` 属性决定，默认 `1024×1024`。

### 修改方法

1. **在编辑器中修改**：选中 `GILightViewport` 节点，在检查器中将 `size` 改为目标值（如 `512×512` 或 `2048×2048`）。建议保持正方形（宽高相等），以避免距离场 UV 计算各向异性。
2. **分辨率影响范围**：所有设置 `source_viewport=GILightViewport` 的 Pass 会自动以新分辨率读取视口纹理；下游 Pass（JF 链路、DF、RM、AO、Dir）的输出分辨率会跟随主输入分辨率（由 `ComputePass._get_output_dimensions` 默认继承源尺寸）。

### 注意事项

1. **Jump Flood 步数**：JF 链路的 8 个 Pass（divisor=2~256）覆盖了 1024 分辨率的最大步长。若分辨率大幅变化（如 4096），可能需要增加 JF Pass 数量以保证距离场精度；若分辨率降低（如 256），可减少 JF Pass 数量以节省性能。判断依据：最大 divisor 应 ≥ 分辨率，确保最后一步步长收敛到 1。
2. **缩放 Pass**：`ScalePassHalf`（512）与 `ScalePassQuarter`（256）的 `scale_target_width/height` 是绝对像素值，修改主分辨率后需同步调整这些目标尺寸以保持比例关系（如主分辨率改 2048，则 Half 改 1024、Quarter 改 512）。
3. **性能权衡**：分辨率翻倍，纹理采样量变为 4 倍。1024×1024 下 JF 链路约 7500 万次采样/帧，2048×2048 将达 3 亿次。性能不足时优先考虑半分辨率计算距离场与 GI，再用 `scale.glsl` 的 bicubic 模式上采样。
4. **HDR 格式**：`use_hdr_2d=true` 保证视口输出 RGBA16F 浮点格式，修改分辨率不影响格式。
