import 'package:cloud_firestore/cloud_firestore.dart';

/// One-shot helper: writes a handful of realistic help requests near
/// **SKKU Natural Sciences Campus (Suwon, Yeongtong-gu)** so the nearby-
/// request map AND the directions screen have something useful to show
/// during testing.
///
/// Designed for **directions testing** — the four pins are deliberately
/// at different distances from campus so the Mapbox Directions API
/// returns walking routes of different lengths and shapes:
///   • short      ~100 m   (a couple of steps, mostly straight)
///   • medium     ~450 m   (a few turns)
///   • longer     ~900 m   (multi-step route with named streets)
///   • furthest   ~1.4 km  (longest path, multiple turns + a roundabout)
///
/// All four are tagged as **different requester IDs** so the cards show
/// other people's names instead of "You" — that way you can exercise
/// the "I can help" / "Directions" flow as a volunteer.
///
/// How to use:
///   1. Make sure you are signed in (any account is fine).
///   2. Call once from anywhere — easiest is a temporary IconButton in
///      `request_map_screen.dart`'s AppBar:
///        await seedTestRequestsNearSKKU();
///   3. Open Nearby Requests — 4 pins appear within 1-2 seconds.
///   4. Delete the trigger button when you're done.
///
/// Re-running creates duplicates. Clear out by deleting them in the
/// Firebase Console (requests collection).
Future<void> seedTestRequestsNearSKKU() async {
  final db = FirebaseFirestore.instance;
  final now = Timestamp.now();

  // SKKU Natural Sciences Campus center is ≈ (37.2972, 127.0464).
  // Coords below are picked to fall on real streets / blocks around it.
  final samples = <Map<String, dynamic>>[
    // ── Short walk: ~100 m N. Should produce 1-2 simple steps.
    {
      'title': 'Help carrying groceries from CU',
      'description':
          "I just shopped at the CU near the campus gate. Two heavy bags "
          "and I live a 3-minute walk uphill. Could someone help me carry "
          "them?",
      'category': 'groceries',
      'location': 'CU near SKKU Natural Sciences gate',
      'latitude': 37.2982,
      'longitude': 127.0468,
      'phone': '+82 10-1111-2222',
      'requesterUid': 'test_user_kim',
      'requesterName': 'Mrs. Kim',
    },
    // ── Medium walk: ~450 m SE. Should give 3-5 steps with turns.
    {
      'title': 'Need a ride to the pharmacy',
      'description':
          'My usual pharmacy is just down the road but my knee is hurting '
          'today. A short ride or a slow walk together would help a lot.',
      'category': 'transport',
      'location': 'Yeongtong-ro, Iui-dong, Suwon',
      'latitude': 37.2942,
      'longitude': 127.0492,
      'phone': '+82 10-3333-4444',
      'requesterUid': 'test_user_park',
      'requesterName': 'Mr. Park',
    },
    // ── Longer walk: ~900 m NW. Multi-step route with named streets.
    {
      'title': 'Change a high ceiling lightbulb',
      'description':
          'The bulb above the staircase burnt out and the ceiling is too '
          'high for me to reach safely. Should take 10 minutes with a '
          'tall ladder.',
      'category': 'household',
      'location': 'Apartment near Yeongtong-ro & Cheonggi-ro',
      'latitude': 37.3030,
      'longitude': 127.0410,
      'phone': '+82 10-5555-6666',
      'requesterUid': 'test_user_lee',
      'requesterName': 'Mrs. Lee',
    },
    // ── Furthest: ~1.4 km E. Best example for showing turn-by-turn.
    {
      'title': 'Walk and chat in the park',
      'description':
          'I like the lake park but going alone is dull. Would anyone like '
          'to take a half-hour walk with me this afternoon?',
      'category': 'companionship',
      'location': 'Gwanggyo Lake Park, Iui-dong',
      'latitude': 37.2978,
      'longitude': 127.0620,
      'phone': '+82 10-7777-8888',
      'requesterUid': 'test_user_choi',
      'requesterName': 'Mr. Choi',
    },
  ];

  for (final s in samples) {
    // 1. Create / upsert the requester user doc so the volunteer map can
    //    look up the username (`AuthService.getUserDocument`) and show
    //    real names on the cards instead of "Requester".
    await db.collection('users').doc(s['requesterUid'] as String).set({
      'username': s['requesterName'],
      'email': '${s['requesterUid']}@example.test',
      'photoUrl': null,
      'phoneVerifiedUntil': null,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. Write the request itself — same schema as the create-request
    //    screen so it flows through the existing volunteer view.
    await db.collection('requests').add({
      'title': s['title'],
      'category': s['category'],
      'description': s['description'],
      'location': s['location'],
      'latitude': s['latitude'],
      'longitude': s['longitude'],
      'phone': s['phone'],
      'dateTime': now,
      'createdAt': now,
      // RequestStatus.active — must match what your RequestModel writes.
      'status': 'active',
      'userId': s['requesterUid'],
    });
  }
}
