import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Emoji offered in Live Chat. A fixed list, so the picker needs no download and never changes.
const List<String> kChatEmoji = [
  '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣',
  '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰',
  '😘', '😗', '😋', '😛', '😜', '🤪', '😎', '🤩',
  '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁',
  '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤',
  '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱',
  '😨', '😰', '😥', '😓', '🤗', '🤔', '🤭', '🤫',
  '😶', '😐', '😑', '😬', '🙄', '😯', '😴', '🤤',
  '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙',
  '👈', '👉', '👆', '👇', '👋', '🙌', '👏', '🙏',
  '💪', '🤝', '👀', '💯', '🔥', '✨', '⭐', '🌟',
  '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '💔',
  '🎉', '🎊', '🎁', '🏆', '🥇', '🎰', '🎲', '🃏',
  '💰', '💵', '💸', '💎', '🪙', '🤑', '🍀', '⚡',
  '✅', '❌', '❓', '❗', '⏳', '⏰', '📷', '🎤',
];

/// Emoji grid shown under the message box. [onPick] inserts one, [onBackspace] removes the last character.
class EmojiPanel extends StatelessWidget {
  const EmojiPanel({super.key, required this.onPick, required this.onBackspace, this.height = 248});
  final ValueChanged<String> onPick;
  final VoidCallback onBackspace;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: Stack(children: [
        GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 56),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 46, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: kChatEmoji.length,
          itemBuilder: (_, i) => InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onPick(kChatEmoji[i]),
            child: Center(child: Text(kChatEmoji[i], style: const TextStyle(fontSize: 25))),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 10,
          child: Material(
            color: AppColors.surface3,
            shape: const StadiumBorder(side: BorderSide(color: AppColors.stroke)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onBackspace,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Icon(Icons.backspace_outlined, size: 20, color: AppColors.muted),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
