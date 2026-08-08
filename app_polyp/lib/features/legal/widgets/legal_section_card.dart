import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';

class LegalSectionCard extends StatelessWidget {
  const LegalSectionCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class LegalBulletList extends StatelessWidget {
  const LegalBulletList({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          Semantics(
            label: 'Mục ${index + 1}: ${items[index]}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(child: Text('•')),
                const SizedBox(width: 10),
                Expanded(child: Text(items[index])),
              ],
            ),
          ),
          if (index != items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}
