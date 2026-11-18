import 'package:flutter/material.dart';

/// Chhaya's app identity: the coral conversation mark with a crescent motif.
/// The accessible label is the product name, so surrounding brand text can
/// remain visually styled without adding a second spoken label.
class ChhayaBrandMark extends StatelessWidget {
  const ChhayaBrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Chhaya',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/images/chhaya_avatar.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}
