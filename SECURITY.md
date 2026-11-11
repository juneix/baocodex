# 安全问题报告

**请不要在公开的 Issue 中报告安全问题。** 请通过 GitHub 的私密漏洞报告提交：仓库页面的 **Security → Report a vulnerability**，或直接打开 <https://github.com/shuishani/ycode/security/advisories/new>。

## 范围

YCode 手机端的代码，包括配对与密钥保存、连接加密、本地存储，以及应用内更新的下载和安装校验。

BaoCode 电脑端和 link 协议本身的问题，请报告给官方 [baocode-dev/baocode](https://github.com/baocode-dev/baocode)；中继服务的问题请报告给 [baocode-dev/relay](https://github.com/baocode-dev/relay)。

## 报告内容

请说明问题的影响、复现步骤和受影响的版本。**不要附带真实的配对二维码、配对链接、安全码、令牌、签名文件或聊天内容**，用合成数据复现即可。

只有最新发布的版本会修复安全问题。
