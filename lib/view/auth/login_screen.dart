import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodel/profile_viewmodel/login_vm.dart';
import '../../viewmodel/profile_viewmodel/otp_vm.dart';
import '../widgets/phone_field.dart';
import '../widgets/primary_button.dart';
import '../widgets/underline_field.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';
import 'register_screen.dart';

/// UC401 Login Account. Google (A1) up top, then a Phone-OTP / Username &
/// Password tab switch for A2 vs A3.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginVm(),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);

  final _phoneController = TextEditingController();
  String _phoneE164 = '';

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _goToShell() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppRoutes()),
      (route) => false,
    );
  }

  Future<void> _handleGoogle(LoginVm vm) async {
    final profile = await vm.signInWithGoogle();
    if (profile != null && mounted) _goToShell();
  }

  Future<void> _handlePhoneSubmit(LoginVm vm) async {
    final ok = await vm.sendPhoneOtp(_phoneE164);
    if (ok && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(flow: OtpFlow.loginPhone, e164Phone: _phoneE164),
        ),
      );
    }
  }

  Future<void> _handleUsernameSubmit(LoginVm vm) async {
    final profile = await vm.loginWithUsernamePassword(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (profile != null && mounted) _goToShell();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LoginVm>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log In'),
        actions: [
          if (Navigator.canPop(context))
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset('assets/images/branding/logo.png', height: 96),
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'Continue with Google',
                isLoading: vm.isLoading,
                onPressed: () => _handleGoogle(vm),
              ),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: AppColors.inkFaint)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.inkFaint,
                indicatorColor: AppColors.accent,
                tabs: const [Tab(text: 'Phone'), Tab(text: 'Username')],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 260,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PhoneField(
                          localNumberController: _phoneController,
                          errorText: vm.errorMessage,
                          onChanged: (e164) => _phoneE164 = e164,
                        ),
                        const Spacer(),
                        PrimaryButton(
                          label: 'Send OTP',
                          isLoading: vm.isLoading,
                          onPressed: () => _handlePhoneSubmit(vm),
                        ),
                      ],
                    ),
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          UnderlineField(label: 'Username', controller: _usernameController),
                          const SizedBox(height: 16),
                          UnderlineField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: true,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              ),
                              child: const Text('Forgot password?'),
                            ),
                          ),
                          if (vm.errorMessage != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              vm.errorMessage!,
                              style: const TextStyle(color: AppColors.error, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 12),
                          PrimaryButton(
                            label: 'Log In',
                            isLoading: vm.isLoading,
                            onPressed: () => _handleUsernameSubmit(vm),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text('Register'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
