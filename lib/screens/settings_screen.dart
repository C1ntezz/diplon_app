import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

<<<<<<< HEAD
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

=======
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _savingProfile = false;
  bool _changingPassword = false;

>>>>>>> 6a5430d (Initial Flutter app commit)
  Future<void> _logout(BuildContext context) async {
    final api = context.read<ApiService>();

    context.read<SocketService>().disconnect();
    await api.logout();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Center(
            child: Text('Перезапустите приложение'),
          ),
        ),
      ),
      (_) => false,
    );
  }

<<<<<<< HEAD
  @override
  Widget build(BuildContext context) {
    const String displayName = 'slon';
    const String username = 'slon';
    const String email = 'slon@example.com';
=======
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
              const SizedBox(height: 14),
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

                      if (newPassword.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Новый пароль должен быть не короче 6 символов')),
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
    final displayName = (api.displayName ?? api.username ?? 'Пользователь').trim();
    final username = (api.username ?? '').trim();
>>>>>>> 6a5430d (Initial Flutter app commit)

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
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
              color: Colors.white,
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
                Stack(
                  children: [
<<<<<<< HEAD
                    const CircleAvatar(
                      radius: 46,
                      backgroundColor: Color(0xFFE9EEF5),
                      child: Icon(
                        Icons.person,
                        size: 46,
                        color: Colors.black54,
=======
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: const Color(0xFFE9EEF5),
                      child: Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
>>>>>>> 6a5430d (Initial Flutter app commit)
                      ),
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
                        child: const Icon(
<<<<<<< HEAD
                          Icons.camera_alt,
=======
                          Icons.edit,
>>>>>>> 6a5430d (Initial Flutter app commit)
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
<<<<<<< HEAD
                const Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
=======
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
>>>>>>> 6a5430d (Initial Flutter app commit)
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
<<<<<<< HEAD
                const Text(
                  '@$username',
                  style: TextStyle(
=======
                Text(
                  username.isNotEmpty ? '@$username' : '@',
                  style: const TextStyle(
>>>>>>> 6a5430d (Initial Flutter app commit)
                    fontSize: 15,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
<<<<<<< HEAD
                  onPressed: () {},
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Изменить фото'),
=======
                  onPressed: _savingProfile ? null : _showEditProfileDialog,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Изменить профиль'),
>>>>>>> 6a5430d (Initial Flutter app commit)
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
<<<<<<< HEAD
            children: const [
=======
            children: [
>>>>>>> 6a5430d (Initial Flutter app commit)
              _InfoTile(
                icon: Icons.person_outline,
                title: 'Имя',
                subtitle: displayName,
              ),
<<<<<<< HEAD
              Divider(height: 1),
              _InfoTile(
                icon: Icons.alternate_email,
                title: 'Username',
                subtitle: '@slon',
              ),
              Divider(height: 1),
              _InfoTile(
                icon: Icons.email_outlined,
                title: 'Email',
                subtitle: email,
=======
              const Divider(height: 1),
              _InfoTile(
                icon: Icons.alternate_email,
                title: 'Username',
                subtitle: username.isNotEmpty ? '@$username' : '@',
>>>>>>> 6a5430d (Initial Flutter app commit)
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSectionCard(
            children: [
              _ActionTile(
                icon: Icons.edit_outlined,
<<<<<<< HEAD
                title: 'Изменить имя',
                onTap: () {},
=======
                title: 'Изменить профиль',
                onTap: _savingProfile ? null : _showEditProfileDialog,
>>>>>>> 6a5430d (Initial Flutter app commit)
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.lock_outline,
                title: 'Сменить пароль',
<<<<<<< HEAD
                onTap: () {},
=======
                onTap: _changingPassword ? null : _showChangePasswordDialog,
>>>>>>> 6a5430d (Initial Flutter app commit)
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
        ],
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
<<<<<<< HEAD
  final VoidCallback onTap;
=======
  final VoidCallback? onTap;
>>>>>>> 6a5430d (Initial Flutter app commit)
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
<<<<<<< HEAD
=======
      enabled: onTap != null,
>>>>>>> 6a5430d (Initial Flutter app commit)
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
<<<<<<< HEAD
}
=======
}
>>>>>>> 6a5430d (Initial Flutter app commit)
