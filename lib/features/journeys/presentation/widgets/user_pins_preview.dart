import 'package:flutter/material.dart';
import 'package:tulink_flutter/core/utils/user_pin_utils.dart';
import 'package:tulink_flutter/features/journeys/presentation/widgets/user_map_pin.dart';

/// Preview widget to showcase multiple user pins with different colors
class UserPinsPreview extends StatelessWidget {
  const UserPinsPreview({super.key});

  @override
  Widget build(BuildContext context) {
    // Sample users for demonstration
    final sampleUsers = [
      {'name': 'John Doe', 'isMe': true, 'index': 0},
      {'name': 'Mary Jane Watson', 'isMe': false, 'index': 1},
      {'name': 'Peter Parker', 'isMe': false, 'index': 2},
      {'name': 'Tony Stark', 'isMe': false, 'index': 3},
      {'name': 'Natasha Romanoff', 'isMe': false, 'index': 4},
      {'name': 'Bruce Banner', 'isMe': false, 'index': 5},
      {'name': 'Steve Rogers', 'isMe': false, 'index': 6},
      {'name': 'Prince', 'isMe': false, 'index': 7},
    ];

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('User Pin Preview'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Journey Participants',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            // Grid of user pins
            Wrap(
              spacing: 30,
              runSpacing: 30,
              children: sampleUsers.map((user) {
                return Column(
                  children: [
                    UserMapPin(
                      displayName: user['name'] as String,
                      isMe: user['isMe'] as bool,
                      userIndex: user['index'] as int,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user['name'] as String,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      UserPinUtils.getColorName(user['index'] as int),
                      style: TextStyle(
                        color: UserPinUtils.getUserColor(user['index'] as int),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
            
            const SizedBox(height: 40),
            
            // Legend
            Text(
              'Color Scheme',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            ...List.generate(8, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: UserPinUtils.getUserColor(index),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'User ${index + 1} - ${UserPinUtils.getColorName(index)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}