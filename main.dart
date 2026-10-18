import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// إعدادات فايربيس المستخرجة من ملفك
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDnaVE88F1QOpJi7CFTujJeOwLHAxdpHzI',
  appId: '1:677970870264:android:8214d0c8fcd3c671fda00d',
  messagingSenderId: '677970870264',
  projectId: 'wake-wake-6fb98',
  storageBucket: 'wake-wake-6fb98.firebasestorage.app',
);

// ضع هنا بريدك الإلكتروني المعتمد كمدير للمعمل
const String adminEmail = "your_admin_email@gmail.com";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const WakeWakeApp());
}

class WakeWakeApp extends StatelessWidget {
  const WakeWakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wake Wake Coffee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6F4E37),
          primary: const Color(0xFF4A2C11),
          secondary: const Color(0xFFD4AF37),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. بوابة التحقق وتحديد الواجهة (مدير أم موزع)
// ---------------------------------------------------------------------------
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData) {
          return const GoogleLoginScreen();
        }

        final user = snapshot.data!;

        // فحص بيانات المستخدم في Firestore
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnap) {
            if (!userSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final data = userSnap.data!.data() as Map<String, dynamic>? ?? {};
            final role = data['role'] ?? 'distributor';

            // توجيه تلقائي: إذا كان مديراً تفتح واجهة المدير، وإلا واجهة الموزع
            if (role == 'admin' || user.email == adminEmail) {
              return AdminDashboardScreen(user: user);
            }

            return DistributorFunnelGate(user: user, userData: data);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. شاشة تسجيل الدخول بواسطة Google وتوليد كود الإحالة
// ---------------------------------------------------------------------------
class GoogleLoginScreen extends StatefulWidget {
  const GoogleLoginScreen({super.key});

  @override
  State<GoogleLoginScreen> createState() => _GoogleLoginScreenState();
}

class _GoogleLoginScreenState extends State<GoogleLoginScreen> {
  final _referralController = TextEditingController();
  bool _isLoading = false;

  String _generateReferralCode(String name) {
    final rand = Random().nextInt(9000) + 1000;
    return 'WAKE-$rand';
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final User? user = userCred.user;

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        // إنشاء الملف أول مرة فقط
        if (!userDoc.exists) {
          final myCode = _generateReferralCode(user.displayName ?? "Distributor");
          final enteredRefCode = _referralController.text.trim();

          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'name': user.displayName ?? '',
            'email': user.email ?? '',
            'photoUrl': user.photoURL ?? '',
            'role': (user.email == adminEmail) ? 'admin' : 'distributor',
            'referralCode': myCode,
            'referredBy': enteredRefCode.isEmpty ? null : enteredRefCode,
            'status': (user.email == adminEmail) ? 'accepted' : 'needs_interview',
            'teamCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // إذا سجل بكود موزع آخر، نرفع عدد أعضاء فريقه تلقائياً
          if (enteredRefCode.isNotEmpty) {
            final parentQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('referralCode', isEqualTo: enteredRefCode)
                .limit(1)
                .get();

            if (parentQuery.docs.isNotEmpty) {
              parentQuery.docs.first.reference.update({
                'teamCount': FieldValue.increment(1),
              });
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.coffee, size: 80, color: Color(0xFF4A2C11)),
              const SizedBox(height: 12),
              const Text('معمل قهوة ويك ويك', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('بوابة الموزعين وإدارة التوريد', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              TextField(
                controller: _referralController,
                decoration: const InputDecoration(
                  labelText: 'كود الدعوة (اختياري)',
                  hintText: 'إذا دعاك موزع أدخل كوده هنا',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.card_giftcard),
                ),
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A2C11),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login),
                      label: const Text('تسجيل الدخول باستخدام Google'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. مسار مراحل الموزع (طلب مقابلة -> انتظار -> قبول)
// ---------------------------------------------------------------------------
class DistributorFunnelGate extends StatelessWidget {
  final User user;
  final Map<String, dynamic> userData;
  const DistributorFunnelGate({super.key, required this.user, required this.userData});

  @override
  Widget build(BuildContext context) {
    final status = userData['status'] ?? 'needs_interview';

    if (status == 'accepted') {
      return DistributorMainView(user: user, userData: userData);
    }

    if (status == 'rejected') {
      return const Scaffold(
        body: Center(
          child: Text('نعتذر، لم يتم قبول طلب التوزيع حالياً في منطقتك.', style: TextStyle(color: Colors.red, fontSize: 18)),
        ),
      );
    }

    if (status == 'pending' || status == 'interviewed') {
      return Scaffold(
        appBar: AppBar(title: const Text('متابعة حالة الطلب'), actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())
        ]),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(status == 'pending' ? Icons.hourglass_empty : Icons.thumb_up, size: 70, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                status == 'pending' ? 'طلبك قيد الدراسة لدى إدارة المعمل' : 'تمت المقابلة، بانتظار تفعيل الحساب',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    // تقديم المقابلة
    return InterviewFormView(user: user);
  }
}

class InterviewFormView extends StatefulWidget {
  final User user;
  const InterviewFormView({super.key, required this.user});

  @override
  State<InterviewFormView> createState() => _InterviewFormViewState();
}

class _InterviewFormViewState extends State<InterviewFormView> {
  final _phone = TextEditingController();
  final _area = TextEditingController();
  String _transport = 'سيارة خاصة';

  void _submit() async {
    if (_phone.text.isEmpty || _area.text.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
      'phone': _phone.text.trim(),
      'area': _area.text.trim(),
      'transport': _transport,
      'status': 'pending',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلب مقابلة توظيف موزع')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف / واتساب', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: _area, decoration: const InputDecoration(labelText: 'منطقة التوزيع المستهدفة', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _transport,
            items: ['سيارة خاصة', 'فان نقل', 'دراجة نارية', 'بدون وسيلة'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (val) => setState(() => _transport = val!),
            decoration: const InputDecoration(labelText: 'وسيلة النقل', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A2C11), foregroundColor: Colors.white),
            onPressed: _submit,
            child: const Text('إرسال طلب المقابلة للمعمل'),
          )
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. واجهة الموزع المقبول (الطلبات وسحب القهوة بالكيلو)
// ---------------------------------------------------------------------------
class DistributorMainView extends StatelessWidget {
  final User user;
  final Map<String, dynamic> userData;
  const DistributorMainView({super.key, required this.user, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الموزع المعتمد'),
        backgroundColor: const Color(0xFF4A2C11),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF4A2C11),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('كود الإحالة الخاص بك', style: TextStyle(color: Colors.white70)),
                  Text(userData['referralCode'] ?? '', style: const TextStyle(fontSize: 24, color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('الموزعون التابعون لك: ${userData['teamCount'] ?? 0}', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6F4E37), foregroundColor: Colors.white),
            onPressed: () => _orderCoffeeSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('طلب سحب كميات من المعمل (بالكيلو)'),
          ),
          const SizedBox(height: 20),
          const Text('طلبياتي:', style: TextStyle(fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('orders').where('distributorId', isEqualTo: user.uid).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      title: Text('${d['product']} (${d['quantityKg']} كغ)'),
                      subtitle: Text('الحالة: ${d['status']} | موعد التسليم: ${d['deliveryDate'] ?? "قيد الجدولة"}'),
                    ),
                  );
                }).toList(),
              );
            },
          )
        ],
      ),
    );
  }

  void _orderCoffeeSheet(BuildContext context) {
    final qty = TextEditingController();
    String prod = 'إسبريسو بليند فاخر';
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: prod,
              items: ['إسبريسو بليند فاخر', 'قهوة عربية بالهيل', 'قهوة تركية سادة', 'خلطة 3 في 1 وكابتشينو']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => prod = v!,
              decoration: const InputDecoration(labelText: 'الصنف', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية بالكيلو', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (qty.text.isNotEmpty) {
                  await FirebaseFirestore.instance.collection('orders').add({
                    'distributorId': user.uid,
                    'distributorName': userData['name'] ?? '',
                    'product': prod,
                    'quantityKg': double.tryParse(qty.text) ?? 0,
                    'status': 'قيد التحضير في المعمل',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('إرسال الطلب للمعمل'),
            )
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. واجهة المدير الخاصة بك (قبول المقابلات وإدارة التوريد)
// ---------------------------------------------------------------------------
class AdminDashboardScreen extends StatelessWidget {
  final User user;
  const AdminDashboardScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة معمل ويك ويك (المدير)'),
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
          actions: [
            IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.assignment_ind), text: 'طلبات المقابلات'),
              Tab(icon: Icon(Icons.local_shipping), text: 'طلبات التوريد'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildInterviewRequests(),
            _buildOrdersManagement(),
          ],
        ),
      ),
    );
  }

  // مراجعة الموزعين الجدد والموافقة عليهم
  Widget _buildInterviewRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا توجد طلبات مقابلات جديدة حالياً.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final d = doc.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: ListTile(
                title: Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('هاتف: ${d['phone']} | منطقة: ${d['area']} | وسيلة: ${d['transport']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => doc.reference.update({'status': 'accepted'}),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => doc.reference.update({'status': 'rejected'}),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // إدارة طلبات القهوة وتحديد موعد التسليم
  Widget _buildOrdersManagement() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا توجد طلبات توريد حالياً.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final d = doc.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: ListTile(
                title: Text('${d['product']} - ${d['quantityKg']} كغ'),
                subtitle: Text('الموزع: ${d['distributorName']} | الحالة: ${d['status']}'),
                trailing: ElevatedButton(
                  onPressed: () {
                    doc.reference.update({
                      'status': 'جاهز للتسليم في المعمل',
                      'deliveryDate': 'اليوم الساعة 4:00 عصراً',
                    });
                  },
                  child: const Text('تأكيد التسليم'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
