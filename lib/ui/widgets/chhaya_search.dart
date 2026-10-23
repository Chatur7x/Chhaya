import 'package:flutter/material.dart';
import '../theme/chhaya_theme.dart';

class ChhayaSearch extends StatefulWidget {
  const ChhayaSearch({super.key, required this.controller, required this.hint, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  State<ChhayaSearch> createState() => _ChhayaSearchState();
}

class _ChhayaSearchState extends State<ChhayaSearch> {
  final _focus = FocusNode();
  @override
  void initState() { super.initState(); _focus.addListener(_changed); widget.controller.addListener(_changed); }
  void _changed() { if (mounted) setState(() {}); }
  @override
  void dispose() { _focus.removeListener(_changed); _focus.dispose(); widget.controller.removeListener(_changed); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: ChhayaMotion.duration(context, 220), curve: Curves.easeOutCubic,
    margin: EdgeInsets.symmetric(horizontal: _focus.hasFocus ? 16 : 24),
    child: TextField(controller: widget.controller, focusNode: _focus,
      textInputAction: TextInputAction.search, onChanged: widget.onChanged,
      style: ChhayaType.of(context).bodyLarge,
      decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: widget.controller.text.isEmpty ? null : IconButton(
          tooltip: 'Clear search', icon: const Icon(Icons.close_rounded),
          onPressed: () { widget.controller.clear(); widget.onChanged(''); }))),
  );
}
