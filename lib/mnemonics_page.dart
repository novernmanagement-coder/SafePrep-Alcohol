import 'package:flutter/material.dart';
import 'constants.dart';
import 'home_page.dart';
import 'mixpanel_service.dart';

class MnemonicsPage extends StatefulWidget {
  const MnemonicsPage({super.key});

  @override
  State<MnemonicsPage> createState() => _MnemonicsPageState();
}

class _MnemonicsPageState extends State<MnemonicsPage> {
  // DRAFT alcohol-service mnemonics — written to match the acronym +
  // letter-breakdown format of Manager's mnemonics, but this content is
  // new and NOT sourced from a verified ServSafe Alcohol curriculum.
  // Review against real training material before shipping.
  static const List<_MnemonicEntry> _mnemonics = [
    _MnemonicEntry('F.A.K.E.™', 'ID Verification', Color(0xFFB7950B), [
      ('F', 'Feel the card — real IDs have texture, edges, embedded chips'),
      ('A', 'Angle it — tilt under light to check for holograms'),
      ('K', 'Know your state — familiarize yourself with valid formats'),
      ('E', 'Examine the photo — does it actually match the person?'),
    ]),
    _MnemonicEntry('W.A.T.C.H.™', 'BAC & Physiology', Color(0xFF8E44AD), [
      ('W', 'Weight — lower body weight raises BAC faster'),
      ('A', 'Alcohol content — proof and pour size both matter'),
      ('T', 'Time — BAC keeps rising even after the last drink'),
      ('C', 'Consumption rate — fast drinking spikes BAC quickly'),
      ('H', 'Hunger — an empty stomach absorbs alcohol faster'),
    ]),
    _MnemonicEntry('S.T.O.P.™', 'Intervention & Refusal', Color(0xFFE67E22), [
      ('S', 'See the signs before it becomes a problem'),
      ('T', 'Talk calmly — never confrontational, never public shaming'),
      ('O', 'Offer alternatives — water, food, a cab, a ride'),
      ('P', 'Protect — document the incident and involve a manager'),
    ]),
    _MnemonicEntry('T.I.P.S.Y.™', 'Signs of Intoxication', Color(0xFF2980B9), [
      ('T', 'Talking louder or slurring words'),
      ('I', 'Impaired coordination or balance'),
      ('P', 'Poor judgment or inappropriate behavior'),
      ('S', 'Slowed reaction time'),
      ('Y', 'Yelling, mood swings, sudden emotional shifts'),
    ]),
    _MnemonicEntry('D.R.A.M.™', 'Legal Liability', Color(0xFFC0392B), [
      ('D', 'Document every refusal and incident'),
      ('R', 'Refuse service the moment signs appear — don\'t wait'),
      ('A', 'Avoid over-service — you\'re liable for what happens after'),
      ('M', 'Monitor consumption throughout the shift, not just at close'),
    ]),
    _MnemonicEntry('C.U.P.™', 'Responsible Service', Color(0xFF27AE60), [
      ('C', 'Count drinks served — keep a running mental tally'),
      ('U', 'Understand the early cutoff signs, not just the late ones'),
      ('P', 'Pace service — space drinks, encourage food and water'),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    MixpanelService.instance.track(
      'mnemonics_viewed',
      properties: {'app_name': 'SA'},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.servSafeBlue,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildCardsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Safe',
                style: TextStyle(
                  fontSize: AppFonts.header,
                  fontWeight: FontWeight.w600,
                  color: AppColors.bodyText,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                ),
                child: Image.asset(
                  'Assets/splash.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Prep™',
                style: TextStyle(
                  fontSize: AppFonts.header,
                  fontWeight: FontWeight.w600,
                  color: AppColors.bodyText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '🧠 Mnemonics',
            style: TextStyle(
              fontSize: AppFonts.header,
              fontWeight: FontWeight.bold,
              color: AppColors.strongText,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Memory hooks for responsible alcohol service',
            style: TextStyle(
              fontSize: AppFonts.caption,
              color: AppColors.subtleText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardsList() {
    final items = <Widget>[];
    String currentType = '';
    for (final m in _mnemonics) {
      if (m.type != currentType) {
        currentType = m.type;
        items.add(_buildSectionHeader(currentType));
      }
      items.add(_buildMnemonicCard(m));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => items[i],
    );
  }

  Widget _buildSectionHeader(String type) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          fontSize: AppFonts.caption,
          fontWeight: FontWeight.bold,
          color: Color(0xFF888888),
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildMnemonicCard(_MnemonicEntry m) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border(top: BorderSide(color: m.color, width: 4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: m.color,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFEEEEEE), height: 1),
          const SizedBox(height: 8),
          ...m.letters.map((e) => _buildLetterRow(e.$1, e.$2, m.color)),
        ],
      ),
    );
  }

  Widget _buildLetterRow(String letter, String phrase, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                phrase,
                style: const TextStyle(
                  fontSize: AppFonts.body,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MnemonicEntry {
  final String name;
  final String type;
  final Color color;
  final List<(String, String)> letters;
  const _MnemonicEntry(this.name, this.type, this.color, this.letters);
}
