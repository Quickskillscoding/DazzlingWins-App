import 'package:flutter/material.dart';

// The app's FAQ: the same questions and answers as the website's FAQ page
// (app/(marketing)/faq/FaqAccordion.tsx). Two answers that describe the website's own menus
// (acc-1, acc-2) are worded for the app's screens instead.

class FaqItem {
  const FaqItem({required this.id, required this.question, required this.answer});
  final String id;
  final String question;
  final String answer;
}

class FaqCategory {
  const FaqCategory({required this.id, required this.title, required this.icon, required this.items});
  final String id;
  final String title;
  final IconData icon;
  final List<FaqItem> items;
}

const List<FaqCategory> kFaq = [
  FaqCategory(
    id: 'general',
    title: 'General & Overview',
    icon: Icons.bolt_rounded,
    items: [
      FaqItem(
        id: 'gen-1',
        question: 'What is DazzlingWins?',
        answer: 'One login for the sweepstakes games you already play — Orion Stars, Game Vault, Juwa, Fire Kirin, and more — instead of separate accounts for each one.',
      ),
      FaqItem(
        id: 'gen-2',
        question: 'Do I have to pay to play?',
        answer: 'No. Every game runs on a no-purchase-necessary model. Request free Sweeps Coins and play for real prizes without spending anything. Buying Gold Coins is optional and doesn\'t improve your odds.',
      ),
      FaqItem(
        id: 'gen-3',
        question: 'How do I create an account?',
        answer: 'Open live chat and tell us which game you want. An agent sets it up with you, usually in a few minutes.',
      ),
      FaqItem(
        id: 'gen-4',
        question: 'Why can\'t I sign up myself?',
        answer: 'These games are operated by the platforms themselves, not by us, and they use agent-based setup instead of open registration. Standard across the industry, not specific to DazzlingWins.',
      ),
      FaqItem(
        id: 'gen-5',
        question: 'Which games can I access?',
        answer: 'Orion Stars, Game Vault, Juwa, Juwa 2.0, Game Room, Fire Kirin, Big Winner, Cash Machine, Cash Frenzy, Panda Master, Mr All In One, V Blink, Milky Way, Ultra Panda, Golden Treasure, Vegrs Sweeps, Yolo 777, Mafia, and E Game.',
      ),
    ],
  ),
  FaqCategory(
    id: 'deposits',
    title: 'Deposits & Adding Credits',
    icon: Icons.credit_card_rounded,
    items: [
      FaqItem(
        id: 'dep-1',
        question: 'What\'s the minimum deposit?',
        answer: '\$5.',
      ),
      FaqItem(
        id: 'dep-2',
        question: 'What payment methods do you support?',
        answer: 'CashApp, PayPal, Chime, Venmo, and Crypto. Some come with a deposit bonus, shown at checkout in chat.',
      ),
      FaqItem(
        id: 'dep-3',
        question: 'How long does a deposit take?',
        answer: 'Usually a few minutes after payment is confirmed. If it\'s slower, send support your payment screenshot.',
      ),
      FaqItem(
        id: 'dep-4',
        question: 'Why does payment go through chat instead of a checkout page?',
        answer: 'Deposits are confirmed manually by our team before crediting your account — slower than automated checkout, but a real person verifies every transaction.',
      ),
      FaqItem(
        id: 'dep-5',
        question: 'Is there a maximum deposit?',
        answer: 'For larger amounts, ask support about splitting it across transactions.',
      ),
    ],
  ),
  FaqCategory(
    id: 'withdrawals',
    title: 'Withdrawals & Redemptions',
    icon: Icons.payments_rounded,
    items: [
      FaqItem(
        id: 'wd-1',
        question: 'How do I cash out?',
        answer: 'Message support or live chat and ask to redeem. They confirm your balance and process the payout.',
      ),
      FaqItem(
        id: 'wd-2',
        question: 'What\'s the minimum redemption?',
        answer: 'The minimum redemption amount is \$30.',
      ),
      FaqItem(
        id: 'wd-3',
        question: 'Is there a maximum redemption amount?',
        answer: 'You can withdraw up to \$350 every 24 hours; anything above that can be withdrawn after 24 hours. Redeeming score from a game has no limit. At Level 0 and Level 1 you receive 80% of a redeem up to \$100, or \$100 for anything above that, and the rest goes to your XP. Score added from the Bonus Wallet pays 10%, with the rest going to XP.',
      ),
      FaqItem(
        id: 'wd-4',
        question: 'How long does redemption take?',
        answer: 'Usually a few hours. Larger or first-time redemptions can take longer since we verify the win first.',
      ),
      FaqItem(
        id: 'wd-5',
        question: 'Why hasn\'t my redemption processed yet?',
        answer: 'Usually incomplete verification or high volume. Message support with your username for a status check.',
      ),
    ],
  ),
  FaqCategory(
    id: 'bonuses',
    title: 'Bonuses & Free Play',
    icon: Icons.card_giftcard_rounded,
    items: [
      FaqItem(
        id: 'bon-1',
        question: 'Is there a free play bonus?',
        answer: 'Yes — new players get a bonus on their first spin, no deposit required.',
      ),
      FaqItem(
        id: 'bon-2',
        question: 'Can I redeem winnings from free play?',
        answer: 'Yes, up to 10% of what you win from free play credits.',
      ),
      FaqItem(
        id: 'bon-3',
        question: 'Where do I see my free play balance separately?',
        answer: 'You can check out your bonus wallet.',
      ),
    ],
  ),
  FaqCategory(
    id: 'account',
    title: 'Account & Login Help',
    icon: Icons.person_rounded,
    items: [
      FaqItem(
        id: 'acc-1',
        question: 'How do I reset my password?',
        answer: 'Tap “Forgot password?” on the sign-in screen and enter your email. We send you a link to choose a new password.',
      ),
      FaqItem(
        id: 'acc-2',
        question: 'Where\'s my username?',
        answer: 'On the Profile tab. Your game usernames and passwords are in My Games.',
      ),
      FaqItem(
        id: 'acc-3',
        question: 'The app won\'t open or keeps crashing. What do I do?',
        answer: 'Force-close it, clear its cache, and reopen. If that fails, delete and reinstall from the official link — not a third-party app store.',
      ),
      FaqItem(
        id: 'acc-4',
        question: 'Why isn\'t the app on Google Play or the App Store?',
        answer: 'Sweepstakes-style apps like Orion Stars and Fire Kirin aren\'t distributed through official stores. Always download from the platform\'s own site or a link from our team.',
      ),
      FaqItem(
        id: 'acc-5',
        question: 'I keep getting "incorrect password" but I know it\'s right.',
        answer: 'Usually caps lock or a stray space in the field. Check both before resetting.',
      ),
    ],
  ),
  FaqCategory(
    id: 'trust',
    title: 'Trust, Safety & How This Works',
    icon: Icons.verified_user_rounded,
    items: [
      FaqItem(
        id: 'tru-1',
        question: 'Is this legit?',
        answer: 'Fair question — scams exist under the same label. We don\'t hold funds outside a confirmed transaction, every deposit/redemption is handled by a real agent, and we\'re upfront this is a no-purchase-necessary sweepstakes model, not real-money gambling. If an agent asks for extra "fees" to release money, stop and contact support directly.',
      ),
      FaqItem(
        id: 'tru-2',
        question: 'What\'s the difference between Gold Coins and Sweeps Coins?',
        answer: 'Gold Coins are for fun, no cash value. Sweeps Coins count toward real prizes and are always free to request — never required to buy.',
      ),
      FaqItem(
        id: 'tru-3',
        question: 'Do I really not need to spend money to win real prizes?',
        answer: 'Correct — it\'s a legal requirement for how sweepstakes platforms operate in the US, not marketing language. Free Sweeps Coins are always available on request.',
      ),
      FaqItem(
        id: 'tru-4',
        question: 'Why do platforms use agents instead of normal payment processing?',
        answer: 'It\'s how the sweepstakes-gaming industry is currently structured — Orion Stars, Fire Kirin, Juwa, and the rest all work this way. Not the smoothest experience, and something we\'re working to improve.',
      ),
      FaqItem(
        id: 'tru-5',
        question: 'Is my personal information safe?',
        answer: 'We only collect what\'s needed for identity verification before redemption — nothing beyond that. If anyone claiming to be DazzlingWins asks for anything unusual, verify through official channels first.',
      ),
      FaqItem(
        id: 'tru-6',
        question: 'Do I need to verify my identity?',
        answer: 'Yes, before your first redemption. A one-time quick ID check that protects both sides from fraud.',
      ),
    ],
  ),
  FaqCategory(
    id: 'support',
    title: 'Support',
    icon: Icons.chat_bubble_rounded,
    items: [
      FaqItem(
        id: 'sup-1',
        question: 'How do I reach support?',
        answer: 'Live chat is fastest, usually minutes. Contact form or email work for anything needing documentation.',
      ),
      FaqItem(
        id: 'sup-2',
        question: 'What are your support hours?',
        answer: 'Live chat: 24/7. Email/contact form: response within 24 hours.',
      ),
    ],
  ),
];
