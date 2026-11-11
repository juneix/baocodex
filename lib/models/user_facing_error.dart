/// 代码自己已经说成人话的错误：界面原样显示，不再包一层。
///
/// 只用于手机端自己就能判断、而且已经翻译好的失败，比如输入格式不对、
/// 图片太大；来自电脑或协议的错误仍交给 `userMessage` 归类。
class UserFacingError implements Exception {
  const UserFacingError(this.message);

  final String message;

  @override
  String toString() => message;
}
