#!/usr/bin/env bash
# 打包 YCode 并覆盖安装到连着的手机（见 docs/release-android.md）。
#   tool/build_android.sh            打包、签名、安装
#   tool/build_android.sh --no-install 只打包签名
# 版本名和构建号取 pubspec.yaml（如 0.3.0+35）；构建号必须持续递增，
# 不依赖 Git 历史，这样重建仓库后仍能覆盖安装。
set -euo pipefail
cd "$(dirname "$0")/.."

registrant=android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
out=build/app/outputs/flutter-apk

# build-tools 取 SDK 里最新的一版；SDK 在 ANDROID_HOME / ANDROID_SDK_ROOT，
# 没设时找 macOS / Windows 的标准位置。也可以直接用 BUILD_TOOLS 指定。
if [ -z "${BUILD_TOOLS:-}" ]; then
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "${LOCALAPPDATA:+$LOCALAPPDATA/Android/Sdk}" "$HOME/AppData/Local/Android/Sdk"; do
    if [ -n "$sdk" ] && [ -d "$sdk/build-tools" ]; then
      BUILD_TOOLS="$sdk/build-tools/$(ls "$sdk/build-tools" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
      break
    fi
  done
fi
if [ -z "${BUILD_TOOLS:-}" ] ||
  { [ ! -x "$BUILD_TOOLS/zipalign" ] && [ ! -f "$BUILD_TOOLS/zipalign.exe" ]; }; then
  echo "找不到 Android build-tools。请设置 ANDROID_HOME，或用 BUILD_TOOLS 指向 build-tools/<版本> 目录。" >&2
  exit 1
fi
apksigner="$BUILD_TOOLS/apksigner"
[ -f "$apksigner.bat" ] && apksigner="$apksigner.bat"

release_version=$(sed -n 's/^version: *//p' pubspec.yaml | tr -d '\r')
name=${release_version%%+*}
number=${release_version#*+}
if [[ ! "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  [[ ! "$number" =~ ^[1-9][0-9]*$ ]] || [ "$number" -gt 2100000000 ]; then
  echo "pubspec.yaml 必须显式设置版本名和递增构建号，如 version: 0.3.0+35。" >&2
  exit 1
fi
version=$name

# macOS 仅安装 Homebrew JDK 时 java_home 可能找不到，优先使用已有配置。
if [ -z "${JAVA_HOME:-}" ] && [ "$(uname -s)" = Darwin ]; then
  JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || true)
  if [ -z "$JAVA_HOME" ] && command -v brew >/dev/null 2>&1; then
    jdk_prefix=$(brew --prefix openjdk@21 2>/dev/null || true)
    [ ! -d "$jdk_prefix/libexec/openjdk.jdk/Contents/Home" ] || JAVA_HOME="$jdk_prefix/libexec/openjdk.jdk/Contents/Home"
  fi
  [ -z "$JAVA_HOME" ] || export JAVA_HOME
fi

# 正式签名：密钥和口令放在 ~/.android/ycode-release.properties，不入库也不打印。
# 换配置路径用环境变量 YCODE_SIGNING。
signing=${YCODE_SIGNING:-$HOME/.android/ycode-release.properties}
# Git Bash 里写成 /c/... 的路径 apksigner(.bat) 不认，交给它之前转成 C:/...。
to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
if [ ! -f "$signing" ]; then
  echo "找不到签名配置 $signing。请把 ycode-release.jks 和 ycode-release.properties 放到 ~/.android/，或用 YCODE_SIGNING 指向 .properties。" >&2
  exit 1
fi
config() { sed -n "s/^$1=//p" "$signing" | head -1 | tr -d '\r'; }
keystore=$(config storeFile)
store_pass=$(config storePassword)
key_alias=$(config keyAlias)
key_pass=$(config keyPassword)
if [ -z "$keystore" ] || [ -z "$store_pass" ] || [ -z "$key_alias" ] || [ -z "$key_pass" ]; then
  echo "签名配置 $signing 不完整：需要 storeFile、storePassword、keyAlias、keyPassword 四项。" >&2
  exit 1
fi
# storeFile 可以只写文件名：相对 .properties 所在目录，拷到别的电脑不用改。
case "$keystore" in
  /* | [A-Za-z]:*) ;;
  *) keystore="$(dirname "$signing")/$keystore" ;;
esac
keystore=$(to_native "$keystore")
if [ ! -f "$keystore" ]; then
  echo "签名配置里的 storeFile 不存在：$keystore" >&2
  exit 1
fi

# integration_test 只给测试用，release 构建缺它的依赖会失败：打包时先拿掉它的
# 注册，打完无论成败都还原，这个文件不能提交改动（也不能删，删了插件全不注册）。
# 那一段是 `    try {` 到 `    }` 的 try/catch；flutter test 会重写这个文件，
# 所以按边界找，不按行号。
# 文件里已经没有 integration_test，多半是上次打包被强制中断留下的半成品；
# 这时不能把它当原件备份，否则打完会把错误的内容"还原"回去。
if ! grep -q integration_test "$registrant"; then
  echo "$registrant 里没有 integration_test 的注册，可能是上次打包中断留下的改动。请先恢复它（git checkout -- \"$registrant\"）再打包。" >&2
  exit 1
fi
registrant_backup=$(mktemp)
registrant_work=$(mktemp)
cp -p "$registrant" "$registrant_backup"
restore_registrant() {
  cp -p "$registrant_backup" "$registrant"
  rm -f "$registrant_backup" "$registrant_work"
}
trap restore_registrant EXIT
awk '
  /^    try \{$/ { block = $0; buffering = 1; next }
  buffering { block = block ORS $0; if ($0 ~ /^    }$/) { if (block !~ /integration_test/) print block; buffering = 0 }; next }
  { print }
' "$registrant" > "$registrant_work"
cp "$registrant_work" "$registrant"
if grep -q integration_test "$registrant"; then
  echo "没能去掉 integration_test 的注册" >&2
  exit 1
fi

preview_args=()
if [ "${YCODE_TEST_INSTALL:-}" = true ]; then
  preview_args+=(
    -PtestInstall=true
    --dart-define=YCODE_PREVIEW=true
  )
fi
repository=${YCODE_REPOSITORY:-shuishani/ycode}

flutter build apk --release --no-pub \
  --target-platform android-arm64 -P arm64Only=true \
  "${preview_args[@]}" \
  --build-name="$name" --build-number="$number" \
  --dart-define=APP_VERSION="$version" \
  --dart-define=YCODE_REPOSITORY="$repository"

"$BUILD_TOOLS/zipalign" -f -p 4 "$out/app-release.apk" "$out/app-aligned.apk"
export YCODE_STORE_PASSWORD="$store_pass" YCODE_KEY_PASSWORD="$key_pass"
"$apksigner" sign --ks "$keystore" \
  --ks-pass env:YCODE_STORE_PASSWORD --key-pass env:YCODE_KEY_PASSWORD \
  --ks-key-alias "$key_alias" \
  --out "$out/ycode-$name-$number.apk" "$out/app-aligned.apk"
"$apksigner" verify "$out/ycode-$name-$number.apk"
echo "打好了：$out/ycode-$name-$number.apk"

[ "${1:-}" = --no-install ] && exit 0
adb install -r "$out/ycode-$name-$number.apk"
adb shell dumpsys package local.ycode.mobile | grep -E 'versionName|lastUpdateTime'
