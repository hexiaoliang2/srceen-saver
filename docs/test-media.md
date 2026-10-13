# 测试视频素材说明（缺陷 4）

> 记录日期：2026-10-13

## 1. 素材来源与许可

两段测试视频均由**本机用 ffmpeg 合成生成**（合成画面 + 正弦音轨），不含任何第三方素材、照片、音乐或商标元素：

| 文件 | 画面来源 | 音轨 | 许可 |
|---|---|---|---|
| `sample_landscape_1080p_10s.mp4` | ffmpeg `testsrc2` 测试图（色条 + 运动元素） | 440Hz 正弦，音量 0.08（默认静音播放，仅用于验证取消静音） | 由本项目自行生成，归项目所有，可随仓库分发 |
| `sample_portrait_1080p_8s.mp4` | ffmpeg `smptebars` 标准彩条 | 660Hz 正弦，音量 0.08 | 同上 |

生成命令（可复现）：

```bash
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30" -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -t 10 -c:v libx264 -preset medium -crf 28 -pix_fmt yuv420p -c:a aac -b:a 96k -af "volume=0.08" \
  -movflags +faststart sample_landscape_1080p_10s.mp4

ffmpeg -y -f lavfi -i "smptebars=size=1080x1920:rate=30" -f lavfi -i "sine=frequency=660:sample_rate=48000" \
  -t 8 -c:v libx264 -preset medium -crf 30 -pix_fmt yuv420p -c:a aac -b:a 96k -af "volume=0.08" \
  -movflags +faststart sample_portrait_1080p_8s.mp4
```

`ffprobe` 复核结果：

| 文件 | 分辨率 | 帧率 | 时长 | 码率 | 大小 |
|---|---|---|---|---|---|
| sample_landscape_1080p_10s.mp4 | 1920×1080 | 30fps | 10.00s | 3018 kbps | 3.7 MB |
| sample_portrait_1080p_8s.mp4 | 1080×1920 | 30fps | 8.00s | 23 kbps | 0.1 MB |

合计约 **3.8 MB**，均 ≤ 1080p、≤ 15s，体积可控。

## 2. 放置目录与版本管理

- 目录：`entry/src/main/resources/rawfile/sample_videos/`
- **纳入版本管理**（与既有 `rawfile/sample_photos/` 相同的策略）：体积小、来源明确、是回归测试的固定输入。
- 运行时由「示例视频」胶囊复制到应用沙箱 `filesDir/sample_videos/`，卡片保存的是沙箱 URI（`file://…`），**不把 rawfile 路径写进配置**。

## 3. 主验证路径（真实使用路径，优先）

1. 进入屏保 → 长按进入编辑态 → 选中视频卡片 → 底栏「卡片设置」；
2. 点「选择视频」→ 系统选择器（`PhotoViewPicker`，视频类型，免权限）→ 从**相册**选择一段视频；
3. 关闭面板 → 退出编辑态观察封面帧；打开「播放视频」观察播放。

> 若相册里没有可用视频，可先用系统相机录制一段，或临时用 `hdc file send` 把 `sample_videos/` 下的文件推入相册目录并触发媒体扫描（本仓库不固化该操作）。

## 4. 手动验证步骤与预期

| 步骤 | 操作 | 预期 |
|---|---|---|
| 1 | 卡片设置 → 「示例视频 · 横屏」 | 状态行显示「已使用示例视频 sample_landscape_1080p_10s.mp4」，日志出现 `video cover generated` |
| 2 | 关闭面板（保持编辑态） | 卡片显示封面帧（播放态关闭时不会自动播放，符合省电设计） |
| 3 | 打开「播放视频」→ 退出编辑态 | 起播；日志 `Video[…] duration: 10`、`Player current status is STARTED`、`start render frame size:[1920x1080]` |
| 4 | 再次进入编辑态 | 播放暂停（编辑态不播放），「播放视频」开关保持 ON |
| 5 | 「循环播放」打开 | 播放到结尾自动重播（不触发 onFinish 复位） |
| 6 | 「静音播放」关闭（需先在设置里调低音量） | 音轨可闻；默认 muted=true |
| 7 | 离开屏保（返回键）→ 重新进入 → 播放态 | **播放偏好保持 ON 并自动续播**（本次修正点；旧版本会被静默复位为 OFF） |
| 8 | 播放中切后台（Home 键） | 立即暂停；日志 `onDidBackground` → `Player current status is PAUSED`；回前台按原开关恢复 |
| 9 | 删除视频文件后重进 | 显示「视频不可用 / 文件已被删除 · 请在配置中重新选择」，编辑态出现「重选」按钮 |
| 10 | 未选择视频 | 显示「未选择视频 / 在配置中选择本地视频」；1×1 极简档降级为一行「无视频」，不空白、不溢出 |

## 5. 本轮实测结果与限制

- 步骤 1、2、3、6（部分）、7、8、10 均已在模拟器上验证通过（截图见 `.verify/shots/d4-*.png`，日志见缺陷报告）。
- **模拟器限制（如实记录）**：模拟器视频解码链路报 `CodecServer … Surface is nullptr`，播放画面在部分时刻渲染为黑帧/不刷新；应用侧状态机、源解析（时长 10s）、帧尺寸（1920×1080）均正确。**真机渲染需复验**。
- 步骤 4/5/9 为代码路径已就绪但本轮未逐条截图的项，按上表可直接复现。
