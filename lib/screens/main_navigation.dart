import 'package:flutter/material.dart';
import 'alarm_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  // Start on Library (index 0)
  int _currentIndex = 0; 

  // 1. Reorder the screens: Library, Player, Alarms
  final List<Widget> _screens = [
    const LibraryScreen(),
    const PlayerScreen(),
    const AlarmScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        // 2. Reorder the destinations to match: Library, Player, Alarms
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music), 
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle), 
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.alarm), 
            label: 'Alarms',
          ),
        ],
      ),
    );
  }
}