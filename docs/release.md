# iMaccy 手工发布流程

本文档定义 iMaccy 的**正式分发**流程。默认约定：

- 本地验证使用 `Release`
- 正式发版使用 `Distribution`
- 正式发版目标：`Developer ID Application` 签名 + notarization + Sparkle appcast 更新

## 0. 前置条件

在开始前，确保本机已经具备：

1. Apple 开发者账号对应的 **Developer ID Application** 证书
2. Xcode 可正常使用该证书进行 macOS 分发签名
3. 已配置 notarization 凭据，推荐使用 notarytool keychain profile：`iMaccy-Notary`
4. 已安装 GitHub CLI，并拥有 `izscc/iMaccy` 仓库发布权限

如果尚未配置 notarization 凭据，可先执行一次：

```bash
xcrun notarytool store-credentials "iMaccy-Notary" \
  --apple-id "<APPLE_ID>" \
  --team-id "MN3X4648SC" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

## 1. 更新版本号

每次发版前，先同步更新两个位置：

1. Xcode 工程中的版本号
   - `MARKETING_VERSION`
   - `CURRENT_PROJECT_VERSION`
2. `appcast.xml`
   - `<title>`
   - `sparkle:shortVersionString`
   - `sparkle:version`
   - `releaseNotesLink`
   - 之后再回填最终 zip 的 `length` 和 `sparkle:edSignature`

## 2. 用 Distribution 归档

正式发版必须从 `Distribution` 配置归档：

```bash
rm -rf build/release
mkdir -p build/release

xcodebuild \
  -project iMaccy.xcodeproj \
  -scheme iMaccy \
  -configuration Distribution \
  -archivePath build/release/iMaccy.xcarchive \
  archive
```

归档后的 app 路径固定为：

```bash
build/release/iMaccy.xcarchive/Products/Applications/iMaccy.app
```

## 3. 校验 Developer ID 签名

先确认归档产物确实是正式分发签名：

```bash
codesign -dv --verbose=4 build/release/iMaccy.xcarchive/Products/Applications/iMaccy.app
spctl -a -vv build/release/iMaccy.xcarchive/Products/Applications/iMaccy.app
```

验收标准：

- `Authority=` 中出现 `Developer ID Application`
- `TeamIdentifier=MN3X4648SC`
- Gatekeeper 检查不过时，先不要继续做 release

## 4. 先打 notarization 用 zip

先对未 staple 的 app 打一个临时 zip 用于提交 notarization：

```bash
ditto -c -k --sequesterRsrc --keepParent \
  build/release/iMaccy.xcarchive/Products/Applications/iMaccy.app \
  build/release/iMaccy-pre-notarize.app.zip
```

## 5. 提交 notarization

```bash
xcrun notarytool submit \
  build/release/iMaccy-pre-notarize.app.zip \
  --keychain-profile "iMaccy-Notary" \
  --wait
```

如果 notarization 失败，先修复签名/entitlements/嵌套框架问题，再重新归档。

## 6. Staple notarization ticket

通过 notarization 后，把票据 stapling 到 app：

```bash
xcrun stapler staple build/release/iMaccy.xcarchive/Products/Applications/iMaccy.app
xcrun stapler validate build/release/iMaccy.xcarchive/Products/Applications/iMaccy.app
```

## 7. 生成最终分发包

**注意**：必须在 staple 完成之后重新打最终 zip，不能复用前面的 notarization 提交包。

```bash
ditto -c -k --sequesterRsrc --keepParent \
  build/release/iMaccy.xcarchive/Products/Applications/iMaccy.app \
  build/release/iMaccy.app.zip
```

可选校验：

```bash
stat -f '%z' build/release/iMaccy.app.zip
shasum -a 256 build/release/iMaccy.app.zip
```

## 8. 生成 Sparkle 签名

先解析本机可用的 `sign_update` 路径，再对最终 zip 签名：

```bash
SIGN_UPDATE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Sparkle/bin/sign_update' -print | head -n 1)"
test -n "$SIGN_UPDATE_BIN"
"$SIGN_UPDATE_BIN" build/release/iMaccy.app.zip
```

输出中会包含：

- `sparkle:edSignature="..."`
- `length="..."`

把这两个值写回 `appcast.xml` 对应版本的 `<enclosure>`。

## 9. 更新 appcast.xml

发版前，确保 `appcast.xml` 中该版本条目已完整填写：

- 版本号
- 发布时间
- release notes 链接
- GitHub Releases 下载链接
- `sparkle:version`
- `sparkle:shortVersionString`
- `sparkle:edSignature`
- `length`

更新完成后提交到 `main`。

## 10. 创建 GitHub Release

```bash
gh release create <VERSION> build/release/iMaccy.app.zip \
  --repo izscc/iMaccy \
  --target main \
  --title "iMaccy <VERSION>"
```

建议 release notes 至少包含：

- 本版本新增功能/修复摘要
- 产物文件名 `iMaccy.app.zip`
- SHA256
- 最低系统版本

## 11. 发布后验证

发布完成后至少验证以下 4 项：

1. `appcast.xml` raw 地址可访问
2. GitHub Release 下载地址可访问
3. 本地 Sparkle 更新源指向当前版本条目
4. 下载下来的 zip 解压后，`spctl -a -vv` 与 `codesign -dv` 结果正常

推荐命令：

```bash
curl -I -L https://raw.githubusercontent.com/izscc/iMaccy/main/appcast.xml
curl -I -L https://github.com/izscc/iMaccy/releases/download/<VERSION>/iMaccy.app.zip
```

## 12. 本流程的边界

- 本文档只定义**手工可执行**发布流程
- 本轮不引入 GitHub Actions / CI 自动发版
- 后续如果要自动化，自动化流程必须复用这里的同一套签名、notarization、Sparkle 更新顺序
