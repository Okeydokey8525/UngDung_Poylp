abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const dashboard = '/dashboard';
  static const diagnosis = '/diagnosis';
  static String diagnosisResult(String id) => '/diagnosis/result/$id';
  static const diagnosisImage = '/diagnosis/image';
  static const comparison = '/comparison';
  static String comparisonResult(String comparisonGroupId) =>
      '/comparison/result/$comparisonGroupId';
  static const history = '/history';
  static const account = '/account';
  static const editProfile = '/account/edit';
  static const changePassword = '/account/change-password';
  static const about = '/about';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const disclaimer = '/disclaimer';
}
