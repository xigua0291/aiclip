# 用 GitHub 云端 Mac 打 AIClip 未签名 IPA

这个文件夹就是 AIClip 的云打包版，里面已经有完整的 AIClip 源码，加上 GitHub 自动打包文件。

原理：GitHub 免费送 macOS 机器跑 workflow，在云上编译出未签名 IPA，你下载后用自己的签名软件签上就能装。

## 第 1 步：新建仓库，上传这个文件夹里的所有文件

1. GitHub 右上角 + → New repository，名字填 `aiclip`，选 Public，点 Create。
2. 点 Add file → Upload files，把这个 `aiclip-github-build` 文件夹里的**所有文件**都拖上去，包括 `.github` 这个隐藏文件夹，点 Commit。
   注意：`.github/workflows/build-ipa.yml` 一定要传上去，不然不会自动打包。
   如果上传页面看不到 `.github`，先把文件夹压缩成 zip 再上传，或者用 GitHub Desktop 传。

## 第 2 步：点一下 Run，等它打好 IPA

1. 打开仓库顶部的 Actions 标签页。
2. 左边选 Build unsigned IPA，右边点 Run workflow → Run workflow。
3. 等几分钟，跑完出现绿色对勾，点进去最下面 Artifacts 里下载 `AIClip-unsigned-ipa`，里面就是 `AIClip-unsigned.ipa`。
4. 拿这个未签名 IPA 去你的签名软件里签名、安装。

## 重要说明

- 打出来的是**未签名 IPA**，直接装会失败，必须先用你的签名软件签过才能装。
- GitHub 免费账号每月有 2000 分钟 macOS 额度，打一次这个小 App 只要几分钟，完全够用。
- 这是现在这个最小版 AIClip 的包，还不是剪映版。以后加了功能，改完 Swift 文件再上传，重新 Run 一次，又会出一个新的 IPA。
- 构建命令：`xcodebuild -project AIClip.xcodeproj -scheme AIClip -configuration Release -destination 'generic/platform=iOS' archive CODE_SIGNING_ALLOWED=NO`
