# AI 剪辑决策 Schema（1.0）

「智能剪辑」把自然语言指令转成一份**结构化的编辑决策列表**，再由本地应用器确定性执行。模型或自定义后端必须只返回 JSON，不要附加解释或 Markdown。

当前版本：`schemaVersion` = `"1.0"`。

## 请求上下文

无论使用 OpenAI 兼容 Chat Completions，还是自定义 POST 接口，应用都会附带当前时间线元数据，例如：

```json
{
  "schemaVersion": "1.0",
  "durationSeconds": 12.4,
  "playheadSeconds": 3.2,
  "selectedClipId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "canvasWidth": 1080,
  "canvasHeight": 1920,
  "clips": [
    {
      "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
      "index": 0,
      "timelineStart": 0,
      "timelineEnd": 12.4,
      "sourceStart": 0,
      "sourceEnd": 12.4,
      "speed": 1,
      "filter": "none"
    }
  ],
  "textOverlays": [],
  "fades": []
}
```

`clip.id` 是应用生成的 UUID。模型只能引用上下文里已经存在的 ID，不能编造。

## 响应形状

```json
{
  "schemaVersion": "1.0",
  "operations": [ ]
}
```

`operations` 按**执行顺序**排列。应用会先做校验，再依次执行；无法安全执行的项会被跳过并记入结果，不会让应用崩溃。

## 支持的操作

### `trim`

裁剪一段素材。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `clipId` | string，可选 | 目标片段。省略时，按**项目时间线**只保留 `[startSeconds, endSeconds]`。 |
| `startSeconds` | number，可选 | 有 `clipId` 时，是该片段输出时间线的局部时间（0 表示片段开头）。无 `clipId` 时，是项目时间线。省略表示保持当前起点。 |
| `endSeconds` | number，可选 | 同上，省略表示保持当前终点。 |

### `split`

在项目时间线的指定秒数处把片段一分为二。`timeSeconds` 可省略，省略时使用当前播放头。

### `deleteRange`

删除项目时间线上的闭开区间。必须提供 `startSeconds` 与 `endSeconds`，且 `endSeconds > startSeconds`。

### `deleteClip`

删除指定片段。必须提供已经存在的 `clipId`。

### `setSpeed`

设置播放倍速。`speed` 必须在 `0.25` 到 `4` 之间。`clipId` 可省略，省略时作用于当前选中或播放头所在片段。

### `addFilter`

添加或更换颜色滤镜。`filter` 只能是：

`none`、`vivid`、`mono`、`warm`、`cool`、`vintage`、`cinema`

`clipId` 可省略；省略则应用到全部片段。未知滤镜会被忽略。

### `addTextOverlay`

添加字幕。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `text` | string，必须 | 字幕内容，最长 80 个字符。 |
| `startSeconds` | number，可选 | 项目时间线上的开始时间，默认 0。 |
| `durationSeconds` | number，可选 | 持续时长，需为正数。 |
| `position` | string，可选 | `top`、`center` 或 `bottom`，默认 `bottom`。 |
| `fontSize` | number，可选 | 字号，建议 24–72。 |

### `removeTextOverlays`

清除全部字幕，无其它字段。

### `addFade`

添加淡入或淡出。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `style` | string，必须 | `in` 或 `out`。也接受 `type` 作为别名。 |
| `startSeconds` | number，可选 | 开始时间。省略时，淡入从 0 秒开始，淡出从片尾往前推 `durationSeconds`。 |
| `durationSeconds` | number，可选 | 默认 1 秒。 |

### `reorder`

按给定顺序重排全部片段。`clipIds` 必须是现有片段 ID 的完整排列，不能多、不能少。

## 未知与不安全的操作

- 缺少 `op`、未知的 `op`、无法识别的滤镜名：跳过。
- 非有限数字、负数时间、`endSeconds <= startSeconds`、倍速越界、空字幕、不存在的 `clipId`、不完整的 `reorder`：跳过。
- 应用器不会执行与剪辑无关的操作，也不会根据模型输出去访问网络或文件。

## 示例

用户说：「去掉开头 3 秒，加上淡入，并在底部加字幕」

```json
{
  "schemaVersion": "1.0",
  "operations": [
    { "op": "deleteRange", "startSeconds": 0, "endSeconds": 3 },
    { "op": "addFade", "style": "in", "durationSeconds": 1 },
    {
      "op": "addTextOverlay",
      "text": "字幕",
      "startSeconds": 0,
      "durationSeconds": 5,
      "position": "bottom"
    }
  ]
}
```

用户说：「应用黑白滤镜」

```json
{
  "schemaVersion": "1.0",
  "operations": [
    { "op": "addFilter", "filter": "mono" }
  ]
}
```

用户说：「把当前片段改成两倍速，并在 5 秒处分割」

```json
{
  "schemaVersion": "1.0",
  "operations": [
    { "op": "setSpeed", "speed": 2 },
    { "op": "split", "timeSeconds": 5 }
  ]
}
```

## 系统提示摘要

连接 OpenAI 兼容接口时，应用会发送固定的系统提示，要求模型：

- 只输出一个 JSON 对象；
- 使用 `schemaVersion` `"1.0"` 和上面的 `operations`；
- 不要编造 `clipId`；
- 无法完成时返回空的 `operations` 数组。

完整提示文本在 `AIClip/AI/AISettings.swift` 的 `AISystemPrompt` 中。

## 演示模式

演示模式**不会**调用模型。它只用本地规则解析一小部分中文（及少量英文）指令，例如：

- 去掉开头 3 秒，加上淡入，并在底部加字幕
- 应用黑白滤镜
- 添加 1 秒淡出
- 两倍速
- 在底部加字幕「你好」

解析失败时会明确提示这是演示模式无法理解的指令，而不会伪造一段「AI 回复」。
