import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../chat/live_chat_screen.dart';
import 'faq_data.dart';

/// Questions matching [query] (in the question or the answer), grouped like the full list.
List<FaqCategory> searchFaq(String query, {List<FaqCategory> source = kFaq}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return source;
  final out = <FaqCategory>[];
  for (final cat in source) {
    final hits = cat.items.where((i) => i.question.toLowerCase().contains(q) || i.answer.toLowerCase().contains(q)).toList();
    if (hits.isNotEmpty) out.add(FaqCategory(id: cat.id, title: cat.title, icon: cat.icon, items: hits));
  }
  return out;
}

/// Help & FAQ: the website's FAQ, searchable, with a way straight into Live Chat.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});
  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final _search = TextEditingController();
  final Set<String> _open = <String>{};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = searchFaq(_query);
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & FAQ')),
      body: AppBackground(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            Text('Quick answers to the questions players ask most.', style: AppTheme.body(13.5, color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search the FAQ',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 18),
            if (shown.isEmpty)
              const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No answer found',
                subtitle: 'Try another word, or ask our agents in Live Chat.',
              ),
            for (final cat in shown) ...[
              Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(cat.icon, size: 17, color: AppColors.gold),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(cat.title, style: AppTheme.display(16, color: AppColors.goldLight))),
              ]),
              const SizedBox(height: 10),
              for (final item in cat.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FaqTile(
                    key: ValueKey('faq-${item.id}'),
                    item: item,
                    // While searching, every match is open so the answer is visible at once.
                    open: searching || _open.contains(item.id),
                    onTap: () => setState(() {
                      if (!_open.remove(item.id)) _open.add(item.id);
                    }),
                  ),
                ),
              const SizedBox(height: 14),
            ],
            Panel(
              gradient: AppColors.heroGradient,
              border: AppColors.primary.withValues(alpha: 0.4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Still need help?', style: AppTheme.display(16)),
                const SizedBox(height: 4),
                Text('Our agents answer in Live Chat, any time.', style: AppTheme.body(13, color: AppColors.muted)),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'Open Live Chat',
                  icon: Icons.chat_bubble_outline_rounded,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveChatScreen())),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({super.key, required this.item, required this.open, required this.onTap});
  final FaqItem item;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: open ? AppColors.gold.withValues(alpha: 0.4) : AppColors.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(item.question, style: AppTheme.body(14.5, weight: FontWeight.w800, color: open ? AppColors.gold : AppColors.text, height: 1.3)),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: open ? AppColors.gold : AppColors.muted),
              ),
            ]),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10, right: 6),
                      child: Text(item.answer, style: AppTheme.body(13.5, color: AppColors.muted, height: 1.45)),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ]),
        ),
      ),
    );
  }
}
