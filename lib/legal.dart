import 'package:flutter/material.dart';

/// In-app Terms and Conditions + Privacy Policy.
///
/// Linked from the sign-up checkbox (which previously pointed at nothing).
/// The content below is a working baseline tailored to how AniMart actually
/// operates (ID verification, admin approval, off-platform payments, GCash
/// subscriptions) — have it reviewed by counsel before public launch.
class TermsAndPrivacyPage extends StatelessWidget {
  const TermsAndPrivacyPage({super.key});

  static const Color _green = Color(0xFF3AA876);
  static const Color _dark = Color(0xFF1A2E22);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: _dark,
        title: const Text(
          'Terms & Privacy',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AniMart Terms and Conditions',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _dark),
            ),
            const SizedBox(height: 4),
            const Text(
              'Last updated: July 7, 2026',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 20),
            _section(
              '1. Acceptance of these Terms',
              'By creating an AniMart account or using the app, you agree to '
                  'these Terms and Conditions and the Privacy Policy below. If '
                  'you do not agree, please do not use AniMart.',
            ),
            _section(
              '2. What AniMart is',
              'AniMart is a marketplace that connects livestock sellers and '
                  'buyers in the Philippines. AniMart is a venue only: we do '
                  'not own, inspect, or guarantee any animal or product '
                  'listed, and we are not a party to any sale. The final '
                  'agreement, payment, and handover happen directly between '
                  'the buyer and the seller.',
            ),
            _section(
              '3. Accounts and verification',
              'To keep the marketplace safe, every account must be verified. '
                  'During sign-up you provide your name, email, mobile '
                  'number, address, and a photo of one government-issued or '
                  'school/barangay ID. An administrator reviews your details '
                  'before your account is approved. You must provide true and '
                  'current information and keep your login credentials '
                  'private. Accounts found using false identities may be '
                  'suspended or removed.',
            ),
            _section(
              '4. Listings and marketplace conduct',
              'Sellers are responsible for the accuracy of their listings '
                  '(price, breed, age, weight, condition, and photos) and for '
                  'complying with all applicable laws, including the Animal '
                  'Welfare Act (RA 8485, as amended) and local rules on the '
                  'sale and transport of livestock. Prohibited: listing '
                  'endangered or illegally sourced animals, misrepresenting '
                  'an animal\'s condition, and posting content that is '
                  'fraudulent or abusive. AniMart may remove listings or '
                  'disable accounts that break these rules.',
            ),
            _section(
              '5. Offers, reservations, and deals',
              'When a seller accepts an offer, the listing is reserved for '
                  'that buyer and a deal record is created in the app. '
                  'Payment and delivery arrangements are made directly '
                  'between buyer and seller (for example by cash on meetup). '
                  'Repeatedly cancelling agreed deals lowers your trust '
                  'standing and is visible to other users. Reviews can only '
                  'be left after a completed purchase.',
            ),
            _section(
              '6. Payments to AniMart (subscriptions)',
              'Optional Premium and Super Premium plans are paid via GCash '
                  'to the account shown in the app, and activated manually '
                  'after an administrator confirms the payment. Subscriptions '
                  'do not renew automatically. Marketplace purchases between '
                  'users are never paid through AniMart.',
            ),
            _section(
              '7. Reports and enforcement',
              'You can report listings, sellers, or problem deals in the '
                  'app. We review reports and may warn, restrict, suspend, or '
                  'delete accounts at our discretion to protect the '
                  'community. Deliberate misuse of the reporting system is '
                  'itself a violation.',
            ),
            _section(
              '8. Liability',
              'To the maximum extent permitted by law, AniMart is not liable '
                  'for losses arising from transactions between users, '
                  'including misrepresented animals, failed payments, or '
                  'failed deliveries. Always inspect animals in person and '
                  'use safe meeting practices.',
            ),
            _section(
              '9. Account deletion',
              'You can permanently delete your account at any time from the '
                  'Profile page. Deletion removes your profile, listings, and '
                  'sign-in; deal history involving other users may be '
                  'retained where required for their records or by law. '
                  'Accounts with an active reserved deal must resolve it '
                  'before deleting.',
            ),
            _section(
              '10. Changes',
              'We may update these terms as the service evolves. Significant '
                  'changes will be announced in the app; continued use after '
                  'a change means you accept the updated terms.',
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              'AniMart Privacy Policy',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _dark),
            ),
            const SizedBox(height: 20),
            _section(
              '1. What we collect',
              'Account data: name, email, mobile number, address, and your '
                  'city/municipality (with its map coordinates, used for the '
                  '"near you" features). Verification data: the type and '
                  'photo of the valid ID you upload at sign-up. Marketplace '
                  'data: your listings, photos, offers, deals, reviews, '
                  'reports, favourites, and support messages. Device data: a '
                  'push-notification token so the app can notify you.',
            ),
            _section(
              '2. Why we collect it',
              'To verify that every account belongs to a real person (fraud '
                  'prevention and marketplace safety), to operate the '
                  'marketplace features you use, to show you nearby listings, '
                  'to notify you about offers, deals, and announcements, and '
                  'to respond to your support requests.',
            ),
            _section(
              '3. Who can see your data',
              'Other users see only your display name, profile photo, '
                  'general location (city/municipality), listings, reviews, '
                  'and trust standing — never your ID, email, phone number, '
                  'exact address, or coordinates. Your ID photo is accessible '
                  'only to AniMart administrators for verification. We do not '
                  'sell your personal data.',
            ),
            _section(
              '4. Where it is stored',
              'Account and marketplace data are stored with Supabase; '
                  'listing, profile, and ID photos are stored with '
                  'Cloudinary; push tokens are processed through Firebase '
                  'Cloud Messaging. These providers process data on our '
                  'behalf under their own security safeguards.',
            ),
            _section(
              '5. Retention and deletion',
              'Your data is kept while your account is active. Deleting your '
                  'account removes your profile, listings, and sign-in '
                  'credentials. Some records (e.g. completed deals involving '
                  'other users, or data we must keep by law) may be retained '
                  'after deletion.',
            ),
            _section(
              '6. Your rights (RA 10173)',
              'Under the Philippine Data Privacy Act of 2012 you have the '
                  'right to access, correct, and request deletion of your '
                  'personal data, and to object to certain processing. To '
                  'exercise these rights, contact us through the in-app '
                  'Support Chat (Profile → Customer Service → Live Chat).',
            ),
            _section(
              '7. Children',
              'AniMart is intended for users 18 years old and above. We do '
                  'not knowingly collect data from minors.',
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4FAF7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.support_agent_rounded, color: _green, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Questions about these terms or your data? Message us '
                      'in Support Chat from the Profile page.',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.black54, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w700, color: _dark)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  fontSize: 13, color: Colors.black54, height: 1.55)),
        ],
      ),
    );
  }
}
