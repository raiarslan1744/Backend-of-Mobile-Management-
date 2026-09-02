class AppSession {
  AppSession._();

  static final AppSession instance = AppSession._();

  String? role;
  String? shopId;
  String? username;
  int? userId;

  void update({
    required String role,
    String? shopId,
    String? username,
    int? userId,
  }) {
    this.role = role;
    this.shopId = shopId;
    this.username = username;
    this.userId = userId;
  }

  void clear() {
    role = null;
    shopId = null;
    username = null;
    userId = null;
  }
}
