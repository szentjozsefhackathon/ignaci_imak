import 'package:flutter/material.dart';

import 'prayer_image.dart';

class PrayerCard extends StatelessWidget {
  const PrayerCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
  });

  final String title;
  final String image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAliasWithSaveLayer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 4,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Positioned.fill(child: PrayerImage(name: image)),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
