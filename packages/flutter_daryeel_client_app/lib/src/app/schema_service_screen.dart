import 'package:flutter/material.dart';

class SchemaServiceScreen extends StatelessWidget {
  const SchemaServiceScreen({required this.baseUrl, super.key});

  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schema Service')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Base URL:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(baseUrl.isEmpty ? '<not configured>' : baseUrl),
            const SizedBox(height: 16),
            const Text(
              'This route is reached via a schema action of type "navigate".',
            ),
          ],
        ),
      ),
    );
  }
}
