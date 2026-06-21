import 'package:flutter/material.dart';
import '../../widgets/bottom_navbar.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      bottomNavigationBar: const BottomNavBar(currentIndex: 0),
      body: const Center(child: Text('Home - Segera hadir')),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
      body: const Center(child: Text('Account - Segera hadir')),
    );
  }
}
