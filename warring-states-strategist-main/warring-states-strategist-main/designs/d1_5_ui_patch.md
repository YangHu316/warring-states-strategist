# D1.5 UI 框架补丁（让项目"活起来"）

## 目标
让玩家点进 main.tscn 后立即看到完整游戏框架并可交互，不依赖新美术资源。

## 视口
1152 × 648（沿用 D1 配置）

## 场景结构（基于现有 main.tscn 扩展）

```
Main (Node2D)                                  [现有]
├── Background (Sprite2D)                      [现有，保留]
├── UILayer (CanvasLayer)                      [现有]
│   ├── DebugLabel (Label, 顶部居中)           [现有，移到右上角小字]
│   ├── TopBar (PanelContainer, 顶部)          [新增]
│   │   └── HBoxContainer
│   │       ├── RoundLabel "回合 1/6"
│   │       ├── FavorQin   "秦: 50"
│   │       ├── FavorZhao  "赵: 50"
│   │       └── FavorQi    "齐: 50"
│   ├── DialogPanel (PanelContainer, 中部)     [新增]
│   │   └── VBoxContainer
│   │       ├── MonarchNameLabel "秦王"
│   │       └── DialogLabel  (君主台词，多行)
│   ├── HandPanel (PanelContainer, 底部)       [新增]
│   │   └── HandHBox (HBoxContainer)
│   │       └── [运行时动态生成 CardButton × N]
│   └── ActionPanel (VBoxContainer, 右侧)      [新增]
│       ├── NextTurnButton "下一回合"
│       ├── DumpButton     "查看状态"
│       └── RestartButton  "重开"
└── TurnManagerNode (Node, script)             [现有]
```

## 交互逻辑（main.gd 扩展）

1. `_ready()`:
   - 等 DataLoader.data_loaded → 调用 `_refresh_all()` 渲染初始 UI
   - 当前君主默认显示 "qin"（秦王），台词从 mock_qin.json 第 0 条
2. `_refresh_top_bar()`: 读 State.current_round / State.favor 刷新顶部
3. `_refresh_hand()`: 清空 HandHBox，遍历 State.all_cards 生成 Button（text=卡牌名称），按钮 `pressed` 信号连接到 `_on_card_pressed(card_id)`
4. `_on_card_pressed(card_id)`:
   - 找到 card，应用其效果到 State.favor（mock：游说+10当前/-5其他；其余按 effects 字段简单映射）
   - DialogLabel 显示 "你使用了【卡牌名】"
   - 调用 TurnManagerNode.advance_turn()
5. `_on_turn_changed(round_num)`: 切换当前君主（qin→zhao→qi→qin 循环），更新对话台词
6. `_on_next_turn_pressed()`: 直接 advance_turn
7. `_on_dump_pressed()`: 弹 AcceptDialog 显示 State.dump()
8. `_on_restart_pressed()`: get_tree().reload_current_scene()

## 视觉规范（占位风格，无需新素材）
- TopBar: PanelContainer 半透明深色 (#000000aa)，高 56px，宽 100%
- DialogPanel: 居中，宽 720 高 200，半透明 (#1a1a2eee)，白字
- HandPanel: 底部，高 140，半透明 (#000000bb)，卡牌按钮 100×120
- ActionPanel: 右侧 offset_right=-20, 顶部 offset_top=80，按钮 160×48
- 字体：使用 Theme 默认；Label/Button 全部 16-20px

## 卡牌效果 mock 映射（D1.5 临时，D2 接 effects 字段）
| id          | 效果                          |
|-------------|-------------------------------|
| persuade    | 当前君主 +10                  |
| message     | 当前 +5，其他全 +2           |
| promise     | 当前 +15，其他 -5            |
| alienate    | 其他全 -10                    |
| spy         | 仅显示对方"倾向"，无数值变化 |
| prepare     | 全 +3                         |
| discard     | 无变化（跳过本回合）         |

## 结束条件
- current_round > max_round (6) → DialogLabel 显示 "游戏结束！" + 各国好感度结算
- 任一好感度 ≤0 或 ≥100 → 触发结局提示（D2+ 完善）

## 交付要求
- 文件：仅修改 `scenes/main.tscn` + `scripts/main.gd`
- 编译通过 + 运行无错
- 不新增美术资源，不修改 Autoload，不破坏 D1 既有逻辑
