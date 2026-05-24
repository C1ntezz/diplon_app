import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app_config.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/theme_service.dart';
import '../services/background_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _passwordRulesText =
      'Минимум 9 символов, одна заглавная буква и один спецсимвол';

  bool _savingProfile = false;
  bool _changingPassword = false;

  String _resolveAvatarUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final baseUrl = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    return '$baseUrl$url';
  }

  ImageProvider? _avatarImageProvider(String? avatarUrl) {
    final value = avatarUrl?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('asset://')) {
      return AssetImage(value.substring('asset://'.length));
    }
    return NetworkImage(_resolveAvatarUrl(value));
  }

  Future<List<String>> _loadPresetAvatars() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final avatars = manifest
        .listAssets()
        .where((path) =>
            path.startsWith('assets/profile_icons/') &&
            RegExp(r'\.(png|jpg|jpeg|webp)$', caseSensitive: false).hasMatch(path))
        .toList()
      ..sort();
    return avatars;
  }

  Future<void> _saveAvatar(String? avatarUrl) async {
    final api = context.read<ApiService>();
    setState(() => _savingProfile = true);

    try {
      await api.updateProfile(
        username: api.username ?? '',
        displayName: api.displayName ?? api.username ?? '',
        avatarUrl: avatarUrl ?? '',
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото профиля обновлено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _savingProfile = true);
    try {
      final bytes = await image.readAsBytes();
      final filename = image.name.isNotEmpty ? image.name : 'avatar.jpg';
      final uploadedUrl = await context.read<ApiService>().uploadFile(bytes, filename);
      if (!mounted) return;
      await _saveAvatar(uploadedUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _showPresetAvatarsDialog() async {
    late final List<String> avatars;
    try {
      avatars = await _loadPresetAvatars();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить готовые иконки: $e')),
      );
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Готовые иконки'),
        content: SizedBox(
          width: 360,
          child: avatars.isEmpty
              ? const Text('Добавьте изображения в assets/profile_icons и выполните flutter pub get.')
              : GridView.builder(
                  shrinkWrap: true,
                  itemCount: avatars.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (_, index) {
                    final assetPath = avatars[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(40),
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        await _saveAvatar('asset://$assetPath');
                      },
                      child: CircleAvatar(
                        backgroundImage: AssetImage(assetPath),
                        backgroundColor: Colors.grey.shade200,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAvatarOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Загрузить из галереи'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatarFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: const Text('Выбрать из готовых'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showPresetAvatarsDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Не ставить фото профиля'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _saveAvatar(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final api = context.read<ApiService>();

    // Отключаем сокет
    context.read<SocketService>().disconnect();
    
    // Полностью останавливаем фоновый сервис, чтобы убрать постоянное уведомление из шторки
    try {
      await stopBackgroundService();
    } catch (e) {
      debugPrint("Ошибка остановки фонового сервиса: $e");
    }
    
    // Стираем токен сессии и выходим на бэкенде
    await api.logout();

    if (!context.mounted) return;

    // Закрываем приложение полностью (завершаем активность на Android)
    await SystemNavigator.pop();
  }

  Future<void> _showEditProfileDialog() async {
    final api = context.read<ApiService>();
    final usernameController = TextEditingController(text: api.username ?? '');
    final displayNameController = TextEditingController(text: api.displayName ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Изменить профиль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: displayNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: usernameController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _savingProfile ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: _savingProfile
                  ? null
                  : () async {
                      final username = usernameController.text.trim();
                      final displayName = displayNameController.text.trim();

                      if (username.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Username не может быть пустым')),
                        );
                        return;
                      }

                      if (!dialogContext.mounted) return;
                      setDialogState(() => _savingProfile = true);
                      setState(() => _savingProfile = true);

                      var dialogClosed = false;

                      try {
                        await api.updateProfile(
                          username: username,
                          displayName: displayName.isNotEmpty ? displayName : username,
                        );

                        if (!mounted) return;
                        final socket = context.read<SocketService>();
                        socket.disconnect();
                        socket.connect(token: api.token!);

                        if (!dialogContext.mounted) return;
                        setDialogState(() => _savingProfile = false);
                        setState(() => _savingProfile = false);
                        dialogClosed = true;
                        Navigator.of(dialogContext).pop();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Профиль обновлен')),
                        );
                        return;
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e')),
                        );
                      } finally {
                        if (!dialogClosed && mounted && dialogContext.mounted) {
                          setDialogState(() => _savingProfile = false);
                          setState(() => _savingProfile = false);
                        }
                      }
                    },
              child: _savingProfile
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    // Контроллеры нельзя уничтожать сразу после showDialog в Web/debug:
    // закрывающийся route еще может достраивать TextField в течение кадра.
  }

  String? _passwordRuleError(String password) {
    if (password.length < 9) {
      return 'Пароль должен быть не короче 9 символов';
    }
    if (RegExp(r'\s').hasMatch(password)) {
      return 'Пароль не должен содержать пробелы';
    }
    if (!RegExp(r'[A-ZА-ЯЁ]').hasMatch(password)) {
      return 'Пароль должен содержать хотя бы одну заглавную букву';
    }
    if (!RegExp(r'''[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>/?`~]''').hasMatch(password)) {
      return 'Пароль должен содержать хотя бы один спецсимвол';
    }
    return null;
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final repeatPasswordController = TextEditingController();
    var obscureCurrentPassword = true;
    var obscureNewPassword = true;
    var obscureRepeatPassword = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Сменить пароль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: obscureCurrentPassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Текущий пароль',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: obscureCurrentPassword ? 'Показать пароль' : 'Скрыть пароль',
                    icon: Icon(
                      obscureCurrentPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setDialogState(
                      () => obscureCurrentPassword = !obscureCurrentPassword,
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: newPasswordController,
                obscureText: obscureNewPassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Новый пароль',
                  prefixIcon: const Icon(Icons.password_outlined),
                  suffixIcon: IconButton(
                    tooltip: obscureNewPassword ? 'Показать пароль' : 'Скрыть пароль',
                    icon: Icon(
                      obscureNewPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setDialogState(
                      () => obscureNewPassword = !obscureNewPassword,
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                  child: Text(
                    _passwordRulesText,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: repeatPasswordController,
                obscureText: obscureRepeatPassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Повторите новый пароль',
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: IconButton(
                    tooltip: obscureRepeatPassword ? 'Показать пароль' : 'Скрыть пароль',
                    icon: Icon(
                      obscureRepeatPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setDialogState(
                      () => obscureRepeatPassword = !obscureRepeatPassword,
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _changingPassword ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: _changingPassword
                  ? null
                  : () async {
                      final currentPassword = currentPasswordController.text;
                      final newPassword = newPasswordController.text;
                      final repeatPassword = repeatPasswordController.text;

                      if (currentPassword.isEmpty || newPassword.isEmpty || repeatPassword.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Заполните все поля')),
                        );
                        return;
                      }

                      final passwordError = _passwordRuleError(newPassword);
                      if (passwordError != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(passwordError)),
                        );
                        return;
                      }

                      if (newPassword != repeatPassword) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Новые пароли не совпадают')),
                        );
                        return;
                      }

                      if (!dialogContext.mounted) return;
                      setDialogState(() => _changingPassword = true);
                      setState(() => _changingPassword = true);

                      var dialogClosed = false;

                      try {
                        await context.read<ApiService>().changePassword(
                              currentPassword: currentPassword,
                              newPassword: newPassword,
                            );

                        if (!mounted) return;
                        if (!dialogContext.mounted) return;
                        setDialogState(() => _changingPassword = false);
                        setState(() => _changingPassword = false);
                        dialogClosed = true;
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Пароль изменен')),
                        );
                        return;
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка: $e')),
                        );
                      } finally {
                        if (!dialogClosed && mounted && dialogContext.mounted) {
                          setDialogState(() => _changingPassword = false);
                          setState(() => _changingPassword = false);
                        }
                      }
                    },
              child: _changingPassword
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сменить'),
            ),
          ],
        ),
      ),
    );

    // Контроллеры нельзя уничтожать сразу после showDialog в Web/debug:
    // закрывающийся route еще может достраивать TextField в течение кадра.
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiService>();
    final themeService = context.watch<ThemeService>();
    final displayName = (api.displayName ?? api.username ?? 'Пользователь').trim();
    final username = (api.username ?? '').trim();
    final avatarProvider = _avatarImageProvider(api.avatarUrl);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Настройки',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _savingProfile ? null : _showAvatarOptions,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: const Color(0xFFE9EEF5),
                        backgroundImage: avatarProvider,
                        child: avatarProvider == null
                            ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: _savingProfile
                              ? const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.edit,
                                  size: 14,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  username.isNotEmpty ? '@$username' : '@',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _savingProfile ? null : _showAvatarOptions,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Фото профиля'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _savingProfile ? null : _showEditProfileDialog,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Изменить профиль'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildSectionCard(
            children: [
              _InfoTile(
                icon: Icons.person_outline,
                title: 'Имя',
                subtitle: displayName,
              ),
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.alternate_email,
                title: 'Username',
                subtitle: username.isNotEmpty ? '@$username' : '@',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSectionCard(
            children: [
              _ActionTile(
                icon: Icons.edit_outlined,
                title: 'Изменить профиль',
                onTap: _savingProfile ? null : _showEditProfileDialog,
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.lock_outline,
                title: 'Сменить пароль',
                onTap: _changingPassword ? null : _showChangePasswordDialog,
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                secondary: Icon(
                  themeService.isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  color: Colors.blueGrey,
                ),
                title: const Text(
                  'Темная тема',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                value: themeService.isDarkMode,
                onChanged: themeService.setDarkMode,
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.notifications_none,
                title: 'Уведомления',
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSectionCard(
            children: [
              _ActionTile(
                icon: Icons.logout,
                iconColor: Colors.red,
                title: 'Log out',
                textColor: Colors.red,
                onTap: () => _logout(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Версия приложения
          Center(
            child: Text(
              'Версия 0.16.3',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      leading: Icon(icon, color: Colors.blueGrey),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? textColor;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      leading: Icon(icon, color: iconColor ?? Colors.blueGrey),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
