// lib/View/ProfileScreen.dart

import 'package:flutter/material.dart';
import '../ViewModel/Profile_VM.dart';
import '../Model/Repository/adapter/profile_adapter.dart';
import '../Model/Entity/profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileVM vm;
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _religionCtrl = TextEditingController();
  final _ethnicityCtrl = TextEditingController();
  final _languageCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    vm = ProfileVM(repository: InMemoryProfileAdapter());
    vm.addListener(_onVm);
    vm.load();
  }

  void _onVm() {
    // update controllers when profile loads
    if (vm.profile != null) {
      _nameCtrl.text = vm.name;
      _ageCtrl.text = vm.ageText ?? '';
      _religionCtrl.text = vm.religion ?? '';
      _ethnicityCtrl.text = vm.ethnicity ?? '';
      _languageCtrl.text = vm.language ?? '';
      _countryCtrl.text = vm.country ?? '';
    }
    // trigger rebuild
    setState(() {});
  }

  @override
  void dispose() {
    vm.removeListener(_onVm);
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _religionCtrl.dispose();
    _ethnicityCtrl.dispose();
    _languageCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (vm.error != null) ...[
                      Text(vm.error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (v) => vm.name = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ageCtrl,
                      decoration: const InputDecoration(labelText: 'Age'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => vm.ageText = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _religionCtrl,
                      decoration: const InputDecoration(labelText: 'Religion'),
                      onChanged: (v) => vm.religion = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ethnicityCtrl,
                      decoration: const InputDecoration(labelText: 'Ethnicity'),
                      onChanged: (v) => vm.ethnicity = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _languageCtrl,
                      decoration: const InputDecoration(labelText: 'Language'),
                      onChanged: (v) => vm.language = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _countryCtrl,
                      decoration: const InputDecoration(labelText: 'Country'),
                      onChanged: (v) => vm.country = v,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Gender?>(
                      value: vm.gender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Prefer not to say')),
                        DropdownMenuItem(value: Gender.male, child: Text('Male')),
                        DropdownMenuItem(value: Gender.female, child: Text('Female')),
                        DropdownMenuItem(value: Gender.nonBinary, child: Text('Non-binary')),
                        DropdownMenuItem(value: Gender.other, child: Text('Other')),
                        DropdownMenuItem(value: Gender.undisclosed, child: Text('Undisclosed')),
                      ],
                      onChanged: (g) => setState(() => vm.gender = g),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        final ok = await vm.save();
                        if (ok) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
                        else if (vm.error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.error!)));
                      },
                      child: const Text('Save'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: vm.resetEdits, child: const Text('Reset')),
                  ],
                ),
              ),
            ),
    );
  }
}
