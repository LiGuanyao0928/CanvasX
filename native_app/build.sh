#!/bin/bash
# 重新编译 CanvasDashboardApp 并装回 .app bundle。第一次跑（.app 还不存在）
# 会自动把整个 bundle 骨架搭起来，之后每次跑只是重新编译+签名。
#
# 签名身份：优先用本地自签名证书（如果钥匙串里有的话）——好处是身份稳定，
# 重新编译不会让 TCC 权限（日历访问等）失效、不用每次都重新弹权限框。
# 没有这个证书（比如刚 clone 下来、还没在"钥匙串访问"里建证书）就自动退回
# ad-hoc 签名，一样能跑，只是每次重新编译后系统权限可能要重新点一次。
# 想用自己的证书：钥匙串访问 → 证书助理 → 创建证书 → 身份类型选"自签名根证书"，
# 证书类型选"代码签名"，然后把下面 SIGNING_IDENTITY 改成你起的名字即可。
#
# 注意：判断证书能不能用，直接实际签一次看成不成功，不要用
# `security find-identity` 预先检查——那个命令按"是否被信任"过滤，
# 自签名证书默认是不受信任的（除非在钥匙串访问里手动设成"始终信任"），
# 会被 find-identity 判定为"无效"，但 codesign 直接用名字签名其实是可以成功的。
#
# 用法：native_app/build.sh
set -euo pipefail
cd "$(dirname "$0")"

SIGNING_IDENTITY="CanvasDashboard Local Dev"
APP="../CanvasDashboard.app"

# 第一次跑，.app 骨架还不存在的话先搭起来
if [ ! -d "$APP" ]; then
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp Info.plist "$APP/Contents/Info.plist"
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

swiftc *.swift -o CanvasDashboardApp -framework Cocoa -framework WebKit

cp CanvasDashboardApp "$APP/Contents/MacOS/CanvasDashboardApp"

if ! codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP" 2>/tmp/canvas_codesign_err.log; then
    echo "⚠️ 找不到证书\"$SIGNING_IDENTITY\"，改用 ad-hoc 签名"
    SIGNING_IDENTITY="-"
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
fi

echo "✅ 编译并签名完成：$APP（签名身份：$SIGNING_IDENTITY）"
