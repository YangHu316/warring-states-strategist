# Project State

> Auto-generated. Do not edit manually.
> Last updated: 2026-06-30 17:35:18

## 概况
- 阶段: V2 | 进度: 100%
- 状态: 可启动，6

## 关键文件
### Scripts (12)
- res://scripts/main.gd (大地图控制器)
- res://scripts/core/state.gd (Autoload, 玩家三维+国家三维+MBTI计分)
- res://scripts/core/data_loader.gd (Autoload, JSON 加载)
- res://scripts/core/arbiter.gd (Autoload, 仲裁器: 掷骰+裁决+漂移+终局判定)
- res://scripts/core/agent_manager.gd (Autoload, 3 君主同步博弈调度)
- res://scripts/core/monarch_ai.gd (class_name MonarchAI, 君主决策)
- res://scripts/core/turn_manager.gd (回合机)
- res://scripts/entities/card.gd (class_name Card, 含 directions 字段)
- res://scripts/ui/mbti_popup.gd
- res://scripts/ui/direction_popup.gd
- res://scripts/ui/dialogue.gd (打字面谈)
- res://scripts/ui/ending.gd (终局评语)

### Scenes (5)
- res://scenes/main.tscn (大地图主场景)
- res://scenes/mbti_popup.tscn
- res://scenes/direction_popup.tscn
- res://scenes/dialogue.tscn
- res://scenes/ending.tscn

### Assets
- 26 个资产文件

## Autoloads
- State
- DataLoader
- Arbiter
- AgentManager

## 已实现功能
- ✅ MBTI 问卷弹窗（5 秒默认 C，12 题）
- ✅ 关键事件横幅生成（按回合×状态分支）
- ✅ 抽行动牌 + 方向选择 + 二值判定
- ✅ 大地图赶路（Tween 移动）
- ✅ 3 君主 Agent 同步博弈（≤2 轮，玩家打牌可打断）
- ✅ 国家状态机（idle/谈判中R1/谈判中R2/召见/决策已定/已处理）
- ✅ 打字面谈（TextEdit 不限时 + 关键词裁决映射综合分）
- ✅ 决策已定挑战（打牌推翻）
- ✅ 事件流面板（Agent + 玩家双向写入）
- ✅ 进入下回合（三对完成后亮起，未处理召见二次确认）
- ✅ 数值自动漂移（偶数回合）
- ✅ 即死叙事（6 种）
- ✅ 终局判定（3 态势 × MBTI 16 型）
- ✅ BGM + 5 SFX 音效

## 已知问题
（无）

## 上次意图
把agent写好，以及你没有理解这个游戏的大循环方式：# 01 · 游戏概述与定位（v7.3 · 3.5 天）
