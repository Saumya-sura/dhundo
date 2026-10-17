import 'package:flutter_test/flutter_test.dart';
import 'package:dhundo/theme/app_theme.dart';

void main() {
  test('AppTheme loads dark theme correctly', () {
    final theme = AppTheme.darkTheme;
    expect(theme.scaffoldBackgroundColor, AppTheme.darkBg);
    expect(theme.primaryColor, AppTheme.primary);
  });
}
