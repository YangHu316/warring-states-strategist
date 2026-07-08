# RFC-003-A · 世界三维数值变化映射表（落地版）

> **编号**：RFC-003-A（RFC-003 的附件 A，可独立执行）
> **状态**：✅ 已实施（v7.4.0 · 2026-07-07 · 一次性切换）
> **提交**：2026-07-06 策划端
> **前置**：RFC-003-数值系统架构重设计.md
> **目的**：把 RFC-003 §四的映射表细化到"代码可直接落地"的颗粒度，覆盖原版 03-数值系统.md 的所有数值变动点
> **执行原则**：数值系统一旦按此表切换，可直接 copy 用
>
> **实施备注（v7.4.0 与本表的偏差）**：
> 1. §十 三处调参已随实施带上：秦之霸业漂移 +4→+3、天下纷乱漂移 +2→+3、推合纵分支 qin_baye -2 一律 →-3（游说牌 + stance_aware 各条）。
> 2. 合纵却秦阈值放宽：`秦之霸业 ≤ 50` → `≤ 60`。§十 推演即使带上调参，推合纵最优路径终局秦之霸业仍 ≈59 > 50，该结局不可达；放宽到 60 后可达且仍需近乎全程推合纵。
> 3. MONARCH_ACTION_DELTAS / STANCE_AWARE_DELTAS 按 actor 分组建表（prepare/observation 在秦赵齐语义不同，§六 单层表会撞键）。
> 4. 面谈立场未知（如自定义表态）时兜底按"中立"分支结算。
> 5. 漂移仅回合 2/4（第 6 回合不漂移，turn_manager 已加末回合判断）。
> 6. 终局判定新增"压倒性大势"分支（v7.4.3）：单轴 ≥85 且领先另一轴 ≥25 → 直接判连横破盟/合纵却秦，不再因另一轴未跌破阈值而落入未决（修复"秦之霸业 100 仍纵横未决"）。
> 7. 离间牌的高/低盟信分支改为**时机窗**：目标国谈判中打出 → 全额（盟-5 乱+3）；已定策 → 仅添乱（乱+2）。cards.json 键名改为 on_success_in_talks / on_success_settled。

---

## 一、新三维定义（复述 RFC-003 §3.1）

| 值 | 程序字段名 | 语义 | 初值 | 取值范围 | clamp |
|---|---|---|---|---|---|
| **秦之霸业** | `qin_baye` | 秦国东出 / 连横 / 单极霸权的进展 | **50** | 0–100 | 是 |
| **六国之盟** | `liu_guo_meng` | 赵齐合纵 / 多极抗秦 / 联盟巩固 | **40** | 0–100 | 是 |
| **天下纷乱** | `tian_xia_fenluan` | 各方观望 / 局部冲突 / 失序 | **30** | 0–100 | 是 |

**State 字段定义**（替代 `state.gd:18-23` 的 `country_attrs`）：
```gdscript
var world_attrs: Dictionary = {
    "qin_baye": 50,
    "liu_guo_meng": 40,
    "tian_xia_fenluan": 30
}
```

**State API**：
```gdscript
signal world_attrs_changed(attrs: Dictionary)

func apply_world_delta(d: Dictionary) -> void:
    # d 例：{"qin_baye": +5, "liu_guo_meng": -3}
    if d == null or d.is_empty():
        return
    for k in d.keys():
        var key: String = String(k)
        if world_attrs.has(key):
            var v: int = int(world_attrs[key]) + int(d[k])
            world_attrs[key] = clampi(v, 0, 100)
    emit_signal("world_attrs_changed", world_attrs)
```

---

## 二、结局判定（替代 03-数值系统.md §2.1）

### 2.1 阈值表

```
第 6 回合结束 → check_ending()
  ├─ [1] 六国之盟 ≥ 70 且 秦之霸业 ≤ 50
  │      → 【合纵却秦 hezong_success】
  ├─ [2] 秦之霸业 ≥ 70 且 六国之盟 ≤ 40
  │      → 【连横破盟 lianheng_break】
  ├─ [3] 天下纷乱 ≥ 65（且不满足 [1]/[2]）
  │      → 【天下大乱 chaos】（新增结局）
  └─ [4] 其余
         → 【纵横未决 undecided】
```

### 2.2 即死结局移除

**移除** `state.gd:check_death()` 全部 6 种即死叙事（suspected_qin_spy / hezong_martyr / silent_end / tall_tree / no_move / backfire）。

**移除** `endings.json` 的 `death` 节点。

### 2.3 新增"天下大乱"结局文本（endings.json 新增）

```json
"chaos": {
    "title": "天下大乱",
    "text": "六国合纵未成，秦亦未能东出。各方观望，边境摩擦不断，百姓流离。这一年过去了，天下大势未明，乱世才刚刚开始。"
}
```

`stance_review` 三派系新增 `chaos` 字段：
```json
"hezong": {
    "chaos": "乱世来了——你最不愿看到的结局。合纵未成，秦亦未胜，但百姓已苦。你收拾行囊，准备下一局。"
},
"neutral": {
    "chaos": "乱世来了——但你早就料到。你不押注，所以没输；但你也没赢。天下纷乱，你左右逢源，却无人可信。"
},
"qin": {
    "chaos": "乱世来了——秦王未能东出，你也未能借势。统一大业要等下一代。你还有时间，但秦庭的位子不稳了。"
}
```

### 2.4 stance_scores 综合保留

`check_ending()` 返回 `{type, detail, mbti_type}`，其中：
- `type` / `detail` 由世界三维主导（§2.1）
- `mbti_type` 由 `judge_stance()` 返回（保留，用于结局评语个性化）

`judge_stance()` 逻辑不变：
```gdscript
func judge_stance() -> String:
    var hz = int(State.stance_scores.get("hezong", 0))
    var nt = int(State.stance_scores.get("neutral", 0))
    var qn = int(State.stance_scores.get("qin", 0))
    if hz > nt and hz > qn: return "hezong"
    if qn > nt and qn > hz: return "qin"
    return "neutral"
```

---

## 三、自动漂移（替代 03-数值系统.md §1.2）

每 2 回合（回合 2/4 开始时，回合 6 不漂移）：

| 漂移项 | 程序字段 | 量 | 语义 | 替代原漂移 |
|---|---|---|---|---|
| 秦之霸业自然增长 | `qin_baye` | **+4** | 秦崛起脊骨 | 原 `秦国威 +3` + `赵齐国威 +2` 的合并 |
| 六国之盟自然侵蚀 | `liu_guo_meng` | **-3** | 联盟自然衰退 | 原 `赵齐盟信 -2` 的合并 |
| 天下纷乱自然增长 | `tian_xia_fenluan` | **+2** | 局势持续失序 | 新增（原无对应） |

**原漂移移除项**：
- `合纵 -4`（玩家三维移除）
- `名望 -2`（玩家三维移除）
- `心计 -3`（玩家三维移除）

**Arbiter 代码**（替代 arbiter.gd L320-327）：
```gdscript
func apply_auto_drift() -> void:
    State.apply_world_delta({
        "qin_baye": 4,
        "liu_guo_meng": -3,
        "tian_xia_fenluan": 2
    })
```

---

## 四、卡牌行动映射（替代 03-数值系统.md §1.1 + cards.json）

### 4.1 游说（persuade · base_rate 45）

| 方向 | 成功时（世界数值变化） | 失败时 |
|---|---|---|
| 推合纵 | `六国之盟 +5`, `秦之霸业 -2` | `天下纷乱 +2` |
| 推亲秦 | `秦之霸业 +5`, `六国之盟 -3` | `天下纷乱 +2` |
| 中立建言 | `天下纷乱 -3` | `天下纷乱 +2` |

**cards.json 对应**：
```json
{
    "id": "persuade",
    "base_rate": 45,
    "scale_attr": "",       // 留空（按 RFC-003 §5.2 方案 A，固定基础值）
    "scale_coef": 0.0,
    "on_success": {
        "push_hezong": {"liu_guo_meng": 5, "qin_baye": -2},
        "push_qin":    {"qin_baye": 5, "liu_guo_meng": -3},
        "neutral":     {"tian_xia_fenluan": -3}
    },
    "on_fail": {"tian_xia_fenluan": 2}
}
```

### 4.2 传信（message · base_rate 45）

| 方向 | 成功时 | 失败时 |
|---|---|---|
| 利好合纵 | `六国之盟 +3` | `天下纷乱 +2` |
| 利好连横 | `秦之霸业 +3` | `天下纷乱 +2` |
| 中立情报 | `天下纷乱 -2` | `天下纷乱 +2` |

**cards.json**：
```json
{
    "id": "message",
    "base_rate": 45,
    "scale_attr": "",
    "scale_coef": 0.0,
    "on_success": {
        "favor_hezong":   {"liu_guo_meng": 3},
        "favor_lianheng": {"qin_baye": 3},
        "neutral":        {"tian_xia_fenluan": -2}
    },
    "on_fail": {"tian_xia_fenluan": 2}
}
```

### 4.3 许诺（promise · base_rate 50）

| 方向 | 成功时 | 失败时 |
|---|---|---|
| 承诺援助 | `六国之盟 +2`, `天下纷乱 -1` | `天下纷乱 +2` |
| 承诺结盟 | `六国之盟 +4` | `天下纷乱 +2` |
| 承诺中立 | `天下纷乱 -2` | `天下纷乱 +2` |

**cards.json**：
```json
{
    "id": "promise",
    "base_rate": 50,
    "scale_attr": "",
    "scale_coef": 0.0,
    "on_success": {
        "aid":     {"liu_guo_meng": 2, "tian_xia_fenluan": -1},
        "ally":    {"liu_guo_meng": 4},
        "neutral": {"tian_xia_fenluan": -2}
    },
    "on_fail": {"tian_xia_fenluan": 2}
}
```

### 4.4 离间（alienate · base_rate 40 · 不选方向）

| 条件 | 成功时 | 失败时 |
|---|---|---|
| 目标在联盟中（`六国之盟 ≥ 50`） | `六国之盟 -5`, `天下纷乱 +3` | `天下纷乱 +2` |
| 目标不在联盟中（`六国之盟 < 50`） | `天下纷乱 +2` | `天下纷乱 +2` |

**cards.json**：
```json
{
    "id": "alienate",
    "base_rate": 40,
    "scale_attr": "",
    "scale_coef": 0.0,
    "on_success_high_liu_guo_meng": {"liu_guo_meng": -5, "tian_xia_fenluan": 3},
    "on_success_low_liu_guo_meng":  {"tian_xia_fenluan": 2},
    "on_fail": {"tian_xia_fenluan": 2}
}
```

### 4.5 刺探（spy · base_rate 55 · 不选方向）

| 结果 | 效果 |
|---|---|
| 成功 | `天下纷乱 +1`（+ 1 张情报牌） |
| 失败 | `天下纷乱 +2` |

**cards.json**：
```json
{
    "id": "spy",
    "base_rate": 55,
    "scale_attr": "",
    "scale_coef": 0.0,
    "on_success": {"tian_xia_fenluan": 1},
    "on_fail": {"tian_xia_fenluan": 2}
}
```

### 4.6 召见面谈（audience · 无成功率 · 无掷骰）

面谈无成功率，**不影响世界数值的直接结算**——但玩家 stance 会触发 stance_aware_actions（见 §五）。

### 4.7 弃牌

| 行动 | 效果 |
|---|---|
| 主动弃牌 | `天下纷乱 +1`（替代原"心计 -3"） |

---

## 五、召见面谈 stance_aware_actions（替代 03-数值系统.md §3.1 + arbiter.gd settle_proposed_action_with_stance）

每个君主 proposed_action 按玩家 stance 三分支结算世界数值。

### 5.1 通用原则

| 玩家 stance | 数值变化倾向 |
|---|---|
| 推合纵 | `六国之盟 ↑`, `秦之霸业 ↓`, `天下纷乱 ↓ 或不变` |
| 推亲秦 | `秦之霸业 ↑`, `六国之盟 ↓`, `天下纷乱 不变 或 ↑` |
| 中立 | `天下纷乱 ↓`（调停降温）或**半幅执行原动作**（不再原样执行） |

### 5.2 完整映射表（11 个 proposed_action × 3 stance = 33 条）

#### 秦·军事施压（pressure）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家劝缓兵，秦压力削弱 | `秦之霸业 -3`, `六国之盟 +2`, `天下纷乱 -1` |
| 推亲秦 | 玩家帮秦施压 | `秦之霸业 +5`, `天下纷乱 +3` |
| 中立 | 君主半幅执行（压力减半） | `秦之霸业 +2`, `天下纷乱 +2` |

#### 秦·遣使离间（alienate）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家劝阻 + 反制离间 | `六国之盟 +3`, `天下纷乱 -2` |
| 推亲秦 | 玩家主动帮秦离间 | `六国之盟 -8`, `秦之霸业 +3`, `天下纷乱 +2` |
| 中立 | 君主半幅执行（离间减弱） | `六国之盟 -3`, `天下纷乱 +1` |

#### 秦·连横利诱（lure）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家戳穿利诱 | `秦之霸业 -2`, `六国之盟 +2` |
| 推亲秦 | 玩家帮秦利诱 | `秦之霸业 +4`, `六国之盟 -5` |
| 中立 | 君主半幅执行（利诱半成） | `秦之霸业 +2`, `六国之盟 -2` |

#### 秦·备战蓄力（prepare）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家劝缓备战 | `秦之霸业 -2`, `六国之盟 +2` |
| 推亲秦 | 玩家帮秦备战 | `秦之霸业 +5` |
| 中立 | 君主半幅执行 | `秦之霸业 +2` |

#### 赵·求盟联齐（seek_alliance）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家背书 + 强化求盟 | `六国之盟 +6`, `秦之霸业 -2` |
| 推亲秦 | 玩家劝赵放弃求盟 | `秦之霸业 +3`, `六国之盟 -3` |
| 中立 | 君主半幅执行（求盟半成） | `六国之盟 +3` |

#### 赵·备战固境（prepare）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家背书备战抗秦 | `六国之盟 +2`, `秦之霸业 -1` |
| 推亲秦 | 玩家劝赵不备战 | `秦之霸业 +2`, `六国之盟 -2` |
| 中立 | 君主半幅执行 | `六国之盟 +1` |

#### 赵·遣使试探（probe）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 试探偏合纵方向 | `六国之盟 +1` |
| 推亲秦 | 试探偏亲秦方向 | `秦之霸业 +1` |
| 中立 | 不改数值（获取意图） | 无变化 |

#### 赵·骑墙观望（observation）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 劝赵从观望转向合纵 | `六国之盟 +3`, `天下纷乱 -1` |
| 推亲秦 | 赵坐实观望 | `秦之霸业 +2`, `天下纷乱 +2` |
| 中立 | 君主自决（观望加剧失序） | `天下纷乱 +2` |

#### 齐·观望渔利（observation）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 劝齐从观望转向合纵 | `六国之盟 +4`, `天下纷乱 -2` |
| 推亲秦 | 齐坐实观望渔利 | `秦之霸业 +2`, `天下纷乱 +2` |
| 中立 | 君主自决（观望加剧失序） | `天下纷乱 +2` |

#### 齐·待价而沽（wait_price）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家拒绝出价，劝齐靠拢合纵 | `六国之盟 +3`, `秦之霸业 -2` |
| 推亲秦 | 玩家帮齐接受秦的出价 | `秦之霸业 +3`, `六国之盟 -2` |
| 中立 | 君主半幅执行（待价半成） | `秦之霸业 +1` |

#### 齐·趁火打劫（hijack）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 玩家劝止趁火打劫 | `六国之盟 +2`, `天下纷乱 -1` |
| 推亲秦 | 玩家帮齐趁火打劫 | `秦之霸业 +2`, `天下纷乱 +3` |
| 中立 | 君主半幅执行 | `天下纷乱 +2` |

#### 齐·闭门自保（self_protect）

| stance | 效果 | 世界数值变化 |
|---|---|---|
| 推合纵 | 劝齐从闭门转向合纵 | `六国之盟 +3` |
| 推亲秦 | 齐坐实自保 | `秦之霸业 +1` |
| 中立 | 君主自决（自保降温） | `天下纷乱 -1` |

### 5.3 Arbiter 代码骨架

```gdscript
const STANCE_AWARE_DELTAS: Dictionary = {
    "pressure": {
        "推合纵": {"qin_baye": -3, "liu_guo_meng": 2, "tian_xia_fenluan": -1},
        "推亲秦": {"qin_baye": 5, "tian_xia_fenluan": 3},
        "中立":   {"qin_baye": 2, "tian_xia_fenluan": 2}
    },
    "alienate": {
        "推合纵": {"liu_guo_meng": 3, "tian_xia_fenluan": -2},
        "推亲秦": {"liu_guo_meng": -8, "qin_baye": 3, "tian_xia_fenluan": 2},
        "中立":   {"liu_guo_meng": -3, "tian_xia_fenluan": 1}
    },
    # ... 其余 9 个 action 同上
}

func settle_proposed_action_with_stance(monarch: String, proposed_action: String, stance: String, target: String = "") -> Dictionary:
    var action_id: String = String(PROPOSED_ACTION_MAP.get(proposed_action, proposed_action))
    var deltas_by_stance: Dictionary = STANCE_AWARE_DELTAS.get(action_id, {})
    var deltas: Dictionary = deltas_by_stance.get(stance, deltas_by_stance.get("中立", {}))
    if deltas.is_empty():
        return {"deltas": {}, "note": "无变化"}
    State.apply_world_delta(deltas)
    return {"deltas": deltas, "note": _describe_world_delta(monarch, action_id, stance, deltas)}
```

---

## 六、君主 Agent 博弈（替代 03-数值系统.md §2.2 + arbiter.gd settle_action 11 项）

君主 Agent 每回合主动博弈对世界数值的影响（不依赖玩家 stance）：

| 君主 · 动作 | 世界数值变化 | 替代原影响 |
|---|---|---|
| 秦·军事施压 | `秦之霸业 +4`, `天下纷乱 +3` | 原目标国威 -5 秦战心 +3 |
| 秦·遣使离间 | `六国之盟 -5`, `天下纷乱 +2` | 原 AB 间盟信 -8 |
| 秦·连横利诱 | `秦之霸业 +3`, `六国之盟 -3` | 原目标盟信向秦 +5 |
| 秦·备战蓄力 | `秦之霸业 +4` | 原秦国威 +3 秦战心 +5 |
| 赵·求盟联齐 | `六国之盟 +5` | 原双方盟信 +5 |
| 赵·备战固境 | `六国之盟 +2`, `天下纷乱 -1` | 原赵国威 +3 赵战心 +5 |
| 赵·遣使试探 | 不改数值 | 不改数值 |
| 赵·骑墙观望 | `天下纷乱 +2` | 原赵战心 -2 |
| 齐·观望渔利 | `天下纷乱 +3` | 原齐战心 -2 齐盟信 -2 |
| 齐·待价而沽 | `秦之霸业 +2` 或 `六国之盟 +2`（看出价方） | 原与出价方盟信 +5 |
| 齐·趁火打劫 | `天下纷乱 +4` | 原对方国威 -3 己国威 +2 |
| 齐·闭门自保 | `天下纷乱 -1` | 原无变化 |

**Arbiter 代码骨架**：
```gdscript
const MONARCH_ACTION_DELTAS: Dictionary = {
    "pressure":      {"qin_baye": 4, "tian_xia_fenluan": 3},
    "alienate":      {"liu_guo_meng": -5, "tian_xia_fenluan": 2},
    "lure":          {"qin_baye": 3, "liu_guo_meng": -3},
    "prepare":       {"qin_baye": 4},
    "seek_alliance": {"liu_guo_meng": 5},
    # ... 其余同上
}

func settle_monarch_action(actor: String, atype: String, target: String) -> Dictionary:
    var deltas: Dictionary = MONARCH_ACTION_DELTAS.get(atype, {})
    if deltas.is_empty():
        return {"deltas": {}, "note": "无变化"}
    State.apply_world_delta(deltas)
    return {"deltas": deltas, "note": _describe_world_delta(actor, atype, "", deltas)}
```

---

## 七、关键事件影响（新增 · key_events.json）

原版关键事件只改 `_current_event_text` 文本，不改数值。RFC-003-A 新增"关键事件触发时世界数值变化"：

| 事件 ID | 事件文本（节选） | 世界数值变化 |
|---|---|---|
| e_r1_a | 秦王遣内史腾携国书入赵 | `秦之霸业 +2`, `天下纷乱 +1` |
| e_r1_b | 秦国书先一步送到临淄 | `秦之霸业 +2`, `六国之盟 -1` |
| e_r2_a | 秦军拔宜阳，斩首三万 | `秦之霸业 +5`, `天下纷乱 +3` |
| e_r2_b | 张仪亲至临淄，以连横之说游说齐王 | `秦之霸业 +2`, `六国之盟 -2` |
| e_r2_c | 秦急遣使分赴赵齐——谁先动，秦就先打谁 | `六国之盟 -3`, `天下纷乱 +2` |
| e_r3_a | 平原君奔走列国倡合纵之说 | `六国之盟 +3` |
| e_r3_b | 秦相魏冉率兵压赵境 | `秦之霸业 +3`, `天下纷乱 +2` |
| e_r4_a | 六国使节齐聚邯郸——合纵到了签字的关键时刻 | `六国之盟 +4` |
| e_r4_b | 秦军压境，各国噤声 | `秦之霸业 +3`, `六国之盟 -2` |
| e_r4_c | 合纵与连横并立——赵求盟，秦利诱，齐观望 | `天下纷乱 +3` |
| e_r5_a | 六国联军在邯郸集结 | `六国之盟 +3`, `秦之霸业 +2`, `天下纷乱 +2` |
| e_r5_b | 秦军推进，某国先降盟信大涨 | `秦之霸业 +4`, `六国之盟 -3` |
| e_r5_c | 双方在边境对峙——决战前夕 | `天下纷乱 +3` |
| e_r6_a | 函谷关外秦军陈兵——最后一搏 | `秦之霸业 +4`, `天下纷乱 +2` |
| e_r6_b | 齐王临阵倒戈与秦暗通 | `秦之霸业 +5`, `六国之盟 -5`, `天下纷乱 +3` |

**key_events.json 新增 `world_delta` 字段**：
```json
{"id": "e_r2_a", "round_range": [2, 2], "state_tag": "yi_yang_fell",
 "text": "秦军拔宜阳，斩首三万。函谷关外战云密布——赵边境压力陡增，赵齐盟信摇动。",
 "world_delta": {"qin_baye": 5, "tian_xia_fenluan": 3}}
```

**main.gd `_resolve_key_event` 触发时调用**：
```gdscript
func _resolve_key_event() -> void:
    # ... 选 event
    _current_event_tag = String(chosen.get("state_tag", "default"))
    _current_event_text = String(chosen.get("text", ""))
    key_event_banner.text = _current_event_text
    push_event("关键事件：" + _current_event_text, EventType.WORLD)
    # v7.3.10 新增：关键事件触发世界数值变化
    var wd: Dictionary = chosen.get("world_delta", {})
    if wd != null and not wd.is_empty():
        State.apply_world_delta(wd)
```

---

## 八、卡牌成功率新机制（替代 03-数值系统.md §三）

按 RFC-003 §5.2 方案 A（固定基础值 + 情报牌加成）：

```
rate = clamp(base_rate + intel_bonus × 5, 5, 95)
```

| 行动 | base_rate | 满值成功率（情报牌 ×5）|
|---|---|---|
| 游说 | 45 | 70%（5 张情报）|
| 离间 | 40 | 65%（5 张情报）|
| 刺探 | 55 | 80%（5 张情报）|
| 许诺 | 50 | 75%（5 张情报）|
| 传信 | 45 | 70%（5 张情报）|
| 召见面谈 | - | 无成功率（无掷骰）|

**移除**：`cards.json` 的 `scale_attr` / `scale_coef` 字段（留空或删除）。

**移除**：`direction_popup.gd:105` 的 `attr_val = player_attrs.get(scale_attr)` 计算。

**移除**：`arbiter.gd:25-26` 的 `rate = base_rate + player_attrs[attr] × coef`。

---

## 九、UI 显示调整

### 9.1 玩家三维显示移除

**移除** `main.gd:_refresh_top_bar` 的玩家三维显示（原 `hezong/mingwang/xinji`）。

**替代**：显示三项世界数值（让玩家感知天下大势）：
```gdscript
func _refresh_top_bar() -> void:
    top_bar_label.text = "秦之霸业 %d  六国之盟 %d  天下纷乱 %d  |  回合 %d/%d" % [
        int(State.world_attrs.get("qin_baye", 0)),
        int(State.world_attrs.get("liu_guo_meng", 0)),
        int(State.world_attrs.get("tian_xia_fenluan", 0)),
        State.current_round, State.max_round
    ]
```

### 9.2 国家状态显示简化

`_fmt_country_status` 移除"威/盟/战"行，只保留国家状态标签：

```gdscript
func _fmt_country_status(country: String) -> String:
    var st: String = AgentManager.get_country_status(country)
    if String(State.country_states.get(country, "")) == "done":
        st = "已面谈"
    return "%s [%s]" % [_country_name(country), st]
```

### 9.3 briefing 文本格式

`agent_manager.gd:get_audience_briefing` 改为读 world_attrs：

```gdscript
# 原：attrs_lines.append("%s：国威%d 盟信%d 战心%d" % ...)
# 新：
var wa: Dictionary = State.world_attrs
var briefing_lines: Array = [
    "天下大势：秦之霸业 %d / 六国之盟 %d / 天下纷乱 %d" % [
        int(wa.get("qin_baye", 0)), int(wa.get("liu_guo_meng", 0)), int(wa.get("tian_xia_fenluan", 0))
    ]
]
```

---

## 十、6 回合推演验证（设计推算）

按本表数值，6 回合推演各结局可达性：

### 推演路径 1：玩家全程推合纵

| 回合 | 关键事件 | 玩家行动 | 君主行动 | 累计六国之盟 | 累计秦之霸业 | 累计天下纷乱 |
|---|---|---|---|---|---|---|
| R1 | e_r1_a (+2秦,+1乱) | 游说推合纵 (+5盟,-2秦) | 秦·备战 (+4秦) | 45 | 54 | 34 |
| R2 | e_r2_a (+5秦,+3乱) | 漂移 (-3盟,+4秦,+2乱) → 游说推合纵 (+5盟,-2秦) | 秦·离间 (-5盟,+2乱) | 42 | 61 | 41 |
| R3 | e_r3_a (+3盟) | 面谈推合纵 (+6盟,-2秦) | 赵·求盟 (+5盟) | 56 | 59 | 41 |
| R4 | e_r4_a (+4盟) | 漂移 → 面谈推合纵 (+6盟,-2秦) | 秦·施压 (+4秦,+3乱) | 66 | 61 | 46 |
| R5 | e_r5_a (+3盟,+2秦,+2乱) | 游说推合纵 (+5盟,-2秦) | 齐·观望 (+3乱) | 74 | 61 | 51 |
| R6 | e_r6_a (+4秦,+2乱) | 面谈推合纵 (+6盟,-2秦) | 秦·备战 (+4秦) | 80 | 67 | 53 |

**结局判定**：六国之盟 80 ≥ 70 且 秦之霸业 67 > 50 → **不满足合纵却秦**（秦国威超标）
→ 落入"纵横未决"

**问题**：秦之霸业漂移太强，需调小漂移或加大玩家行动效果。

### 推演路径 2：玩家全程推亲秦

| 回合 | 关键事件 | 玩家行动 | 君主行动 | 累计六国之盟 | 累计秦之霸业 |
|---|---|---|---|---|---|
| R1 | e_r1_b (+2秦,-1盟) | 游说推亲秦 (+5秦,-3盟) | 秦·备战 (+4秦) | 36 | 61 |
| R2 | e_r2_b (+2秦,-2盟) | 漂移 → 游说推亲秦 (+5秦,-3盟) | 秦·利诱 (+3秦,-3盟) | 28 | 75 |
| R3 | e_r3_b (+3秦,+2乱) | 面谈推亲秦 (+5秦) | 秦·施压 (+4秦,+3乱) | 28 | 87 |
| R4 | e_r4_b (+3秦,-2盟) | 漂移 → 面谈推亲秦 (+5秦) | 秦·备战 (+4秦) | 23 | 99 |
| R5 | e_r5_b (+4秦,-3盟) | 游说推亲秦 (+5秦,-3盟) | 秦·利诱 (+3秦,-3盟) | 17 | 111 → clamp 100 |
| R6 | e_r6_a (+4秦,+2乱) | 面谈推亲秦 (+5秦) | 秦·备战 (+4秦) | 17 | 100 |

**结局判定**：秦之霸业 100 ≥ 70 且 六国之盟 17 ≤ 40 → **连横破盟** ✅

### 推演路径 3：玩家全程中立

| 回合 | 关键事件 | 玩家行动 | 君主行动 | 累计六国之盟 | 累计秦之霸业 | 累计天下纷乱 |
|---|---|---|---|---|---|---|
| R1 | e_r1_a (+2秦,+1乱) | 游说中立 (-3乱) | 秦·备战 (+4秦) | 40 | 54 | 31 |
| R2 | e_r2_c (-3盟,+2乱) | 漂移 → 游说中立 (-3乱) | 秦·离间 (-5盟,+2乱) | 32 | 58 | 37 |
| R3 | e_r3_b (+3秦,+2乱) | 面谈中立 (+2乱 或 半幅) | 齐·观望 (+3乱) | 32 | 61 | 42 |
| R4 | e_r4_c (+3乱) | 漂移 → 面谈中立 | 齐·待价 (+1秦) | 32 | 62 | 47 |
| R5 | e_r5_c (+3乱) | 游说中立 (-3乱) | 齐·趁火打劫 (+4乱) | 32 | 62 | 51 |
| R6 | e_r6_b (+5秦,-5盟,+3乱) | 面谈中立 | 齐·趁火打劫 (+4乱) | 27 | 67 | 58 |

**结局判定**：天下纷乱 58 < 65 → **不满足天下大乱** → 落入"纵横未决"

**问题**：中立路径天下纷乱增长不够，需调大漂移或君主行动的纷乱贡献。

### 推演结论 + 调参建议

| 路径 | 推演结果 | 问题 | 调参建议 |
|---|---|---|---|
| 推合纵 | 未决（秦国威超标）| 秦之霸业漂移太强 | 玩家行动 `-2 秦` 加大到 `-3`，或漂移 `+4` 减到 `+3` |
| 推亲秦 | 连横破盟 ✅ | 达标 | 无需调整 |
| 中立 | 未决（纷乱不够）| 天下纷乱增长不足 | 君主齐·趁火打劫 `+4乱` 加大到 `+5`，或漂移 `+2` 加到 `+3` |

**建议调参**（程序实施前先按本表，D3 mock 50 局后再校准）：
- 秦之霸业漂移 `+4` → `+3`
- 天下纷乱漂移 `+2` → `+3`
- 推合纵时 `-2 秦` → `-3 秦`

---

## 十一、落地步骤（代码改动清单）

按本表落地，改动顺序：

1. **State** (`state.gd`)：
   - 删 `player_attrs` / `country_attrs` / `apply_player_delta` / `apply_country_delta` / `check_death` / `player_attrs_changed` / `country_attrs_changed` signal
   - 加 `world_attrs` / `apply_world_delta` / `world_attrs_changed` signal
   - `reset()` 重置 `world_attrs`

2. **Arbiter** (`arbiter.gd`)：
   - `roll_card` 移除 player_attrs 加成，改为 `base_rate + intel_bonus × 5`
   - `settle_proposed_action_with_stance` 用 `STANCE_AWARE_DELTAS` 常量表
   - `settle_action`（君主博弈）用 `MONARCH_ACTION_DELTAS` 常量表
   - `check_ending` 用 §2.1 新阈值，删 `check_death` 调用
   - `_gen_intel` 改读 `world_attrs`

3. **main.gd**：
   - `_refresh_top_bar` 显示 world_attrs
   - `_fmt_country_status` 简化（移除威/盟/战）
   - `_check_death_and_react` 删除
   - `_on_player_attrs_changed` 删除
   - `_on_country_attrs_changed` → `_on_world_attrs_changed`
   - `_resolve_key_event` 加 `world_delta` 触发

4. **agent_manager.gd**：
   - LLM ctx `country_attrs` → `world_attrs`
   - `get_audience_briefing` 文本格式改

5. **monarch_ai.gd**：
   - `_score_actions` 移除 `qin.guowei >= 75` 等判断，改用 `world_attrs.qin_baye >= 60`
   - LLM prompt ctx 同步

6. **dialogue.gd**：
   - LLM prompt 里 `country_attrs` → `world_attrs`

7. **direction_popup.gd**：
   - 移除 `player_attrs.get(scale_attr)` 计算 rate

8. **ending.gd**：
   - 移除 `death` 分支
   - 新增 `chaos` 分支

9. **data/cards.json**：
   - 所有 `on_success` / `on_fail` 改为世界数值 delta
   - `scale_attr` / `scale_coef` 留空或删除

10. **data/endings.json**：
    - 删 `death` 节点
    - 新增 `chaos` 节点
    - `stance_review` 三派系加 `chaos` 字段

11. **data/key_events.json**：
    - 每个事件加 `world_delta` 字段

---

## 十二、验收清单

- [ ] `state.gd` 无 `player_attrs` / `country_attrs` / `check_death`
- [ ] `state.gd` 有 `world_attrs` / `apply_world_delta`
- [ ] `arbiter.gd` `check_ending` 用 §2.1 新阈值（含 chaos）
- [ ] `arbiter.gd` `settle_proposed_action_with_stance` 用 `STANCE_AWARE_DELTAS`
- [ ] `arbiter.gd` `settle_action` 用 `MONARCH_ACTION_DELTAS`
- [ ] `cards.json` 所有 delta 指向世界数值
- [ ] `endings.json` 无 `death`，有 `chaos`
- [ ] `key_events.json` 每事件有 `world_delta`
- [ ] UI 不再显示玩家三维 / 国家三维，显示世界三维
- [ ] C01 锁定表更新

---

**本表可直接落地执行。程序成员按 §十一 顺序改动即可。**
