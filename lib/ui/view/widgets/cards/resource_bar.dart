import 'package:flutter/material.dart';

class ResourceBar extends StatelessWidget {
  final String label;
  final String detail;
  final double percentage;
  final Color color;

  const ResourceBar({
    super.key,
    required this.label,
    required this.detail,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            Text(
              detail,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 8,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF374151),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: (percentage / 100).clamp(0.0, 1.0),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
