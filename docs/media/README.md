# 界面流程演示

这三个素材分别演示热水、洗衣和首次配置的页面关系。画面来自已脱敏实机截图，字幕由仓库脚本叠加。

- `water-flow-demo.gif/.mp4`
- `laundry-flow-demo.gif/.mp4`
- `setup-flow-demo.gif/.mp4`

它们是界面动画模拟，不是实际出水、扣费、付款或洗衣机启动录像，也不用于证明任何真实交易已经成功。

素材可在 macOS 或 Windows 渲染。原始截图和字幕图位于 `docs/screenshots` 与 `docs/media`；需要 FFmpeg：

```sh
./docs/media/build-demo-media.sh
```

Windows Git Bash 可先准备 `imageio-ffmpeg`，再调用渲染脚本：

```sh
python -m pip install --user imageio-ffmpeg
export FFMPEG="$(cygpath -u "$(python -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')")"
./docs/media/render-demo-media.sh
```
