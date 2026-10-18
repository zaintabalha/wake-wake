import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// إعدادات Firebase الخاصة بمشروعك
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDnaVE88F1QOpJi7CFTujJeOwLHAxdpHzI',
  appId: '1:677970870264:android:8214d0c8fcd3c671fda00d',
  messagingSenderId: '677970870264',
  projectId: 'wake-wake-6fb98',
  storageBucket: 'wake-wake-6fb98.firebasestorage.app',
);

// بريد المدير المعتمد للتعرف التلقائي
const String adminEmail = "admin@wakewake.com";

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
      title: 'معمل قهوة ويك ويك',
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
// بوابة التوزيع: فحص المستخدم وتوجيهه (مدير أو موزع)
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
          return const LoginScreen();
        }

        final user = snapshot.data!;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnap) {
            if (!userSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final data = userSnap.data!.data() as Map<String, dynamic>? ?? {};
            final role = data['role'] ?? 'distributor';

            // إذا كان المستخدم مديراً، يتم فتح لوحة التحكم
            if (role == 'admin' || user.email == adminEmail) {
              return AdminDashboardScreen(user: user);
            }

            // إذا كان موزعاً، يتم فحصه وفق مراحل التوظيف
            return DistributorFunnel(user: user, userData: data);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// شاشة تسجيل الدخول وإنشاء الحساب
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _nameController = TextEditingController();
  final _refCodeController = TextEditingController();
  bool isLogin = true;
  bool isLoading = false;

  String _generateReferralCode() => 'WAKE-${Random().nextInt(9000) + 1000}';

  void _submit() async {
    setState(() => isLoading = true);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passController.text.trim(),
        );
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passController.text.trim(),
        );

        final uid = cred.user!.uid;
        final myCode = _generateReferralCode();
        final refCode = _refCodeController.text.trim();
        final isAdmin = _emailController.text.trim().toLowerCase() == adminEmail.toLowerCase();

        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'uid': uid,
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'role': isAdmin ? 'admin' : 'distributor',
          'referralCode': myCode,
          'referredBy': refCode.isEmpty ? null : refCode,
          'status': isAdmin ? 'accepted' : 'needs_interview',
          'teamCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // زيادة عداد الفريق إذا انضم عبر كود إحالة
        if (refCode.isNotEmpty) {
          final parentQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('referralCode', isEqualTo: refCode)
              .limit(1)
              .get();

          if (parentQuery.docs.isNotEmpty) {
            parentQuery.docs.first.reference.update({'teamCount': FieldValue.increment(1)});
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.coffee, size: 70, color: Color(0xFF4A2C11)),
                const SizedBox(height: 10),
                const Text('معمل قهوة ويك ويك', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                if (!isLogin) ...[
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                ],
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _passController, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
                if (!isLogin) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _refCodeController,
                    decoration: const InputDecoration(labelText: 'كود الدعوة (اختياري)', border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 20),
                isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A2C11),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _submit,
                        child: Text(isLogin ? 'تسجيل الدخول' : 'إنشاء حساب موزع جديد'),
                      ),
                TextButton(
                  onPressed: () => setState(() => isLogin = !isLogin),
                  child: Text(isLogin ? 'ليس لديك حساب؟ سجّل كموزع' : 'لديك حساب بالفعل؟ سجّل دخولك'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// مراحل تدرج الموزع (المقابلة والاعتماد)
// ---------------------------------------------------------------------------
class DistributorFunnel extends StatelessWidget {
  final User user;
  final Map<String, dynamic> userData;
  const DistributorFunnel({super.key, required this.user, required this.userData});

  @override
  Widget build(BuildContext context) {
    final status = userData['status'] ?? 'needs_interview';

    if (status == 'accepted') {
      return DistributorHome(user: user, userData: userData);
    }
    if (status == 'rejected') {
      return const Scaffold(
        body: Center(
          child: Text('نعتذر، لم يتم قبول طلب التوزيع حالياً.', style: TextStyle(color: Colors.red, fontSize: 18)),
        ),
      );
    }
    if (status == 'pending') {
      return Scaffold(
        appBar: AppBar(title: const Text('حالة الطلب'), actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())
        ]),
        body: const Center(
          child: Text('طلبك قيد المراجعة لدى إدارة المعمل، سيتم فتح النظام بعد المقابلة.', style: TextStyle(fontSize: 16)),
        ),
      );
    }

    return InterviewSubmission(user: user);
  }
}

class InterviewSubmission extends StatefulWidget {
  final User user;
  const InterviewSubmission({super.key, required this.user});

  @override
  State<InterviewSubmission> createState() => _InterviewSubmissionState();
}

class _InterviewSubmissionState extends State<InterviewSubmission> {
  final _phone = TextEditingController();
  final _area = TextEditingController();
  String _transport = 'سيارة خاصة';

  void _send() async {
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف / واتساب', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _area, decoration: const InputDecoration(labelText: 'منطقة التوزيع المستهدفة', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _transport,
                items: ['سيارة خاصة', 'فان بضائع', 'دراجة نارية', 'مندوب بدون وسيلة'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) => setState(() => _transport = val!),
                decoration: const InputDecoration(labelText: 'وسيلة النقل', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A2C11), foregroundColor: Colors.white),
                onPressed: _send,
                child: const Text('إرسال طلب المقابلة'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// واجهة الموزع المقبول (الطلبات وسحب القهوة)
// ---------------------------------------------------------------------------
class DistributorHome extends StatelessWidget {
  final User user;
  final Map<String, dynamic> userData;
  const DistributorHome({super.key, required this.user, required this.userData});

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
                  const Text('كود الدعوة الخاص بك', style: TextStyle(color: Colors.white70)),
                  Text(userData['referralCode'] ?? '', style: const TextStyle(fontSize: 24, color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('الموزعون في شبكتك: ${userData['teamCount'] ?? 0}', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6F4E37), foregroundColor: Colors.white),
            onPressed: () => _createOrderDialog(context),
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

  void _createOrderDialog(BuildContext context) {
    final qty = TextEditingController();
    String prod = 'إسبريسو بليند فاخر';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طلب سحب قهوة بالكيلو'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: prod,
              items: ['إسبريسو بليند فاخر', 'قهوة عربية بالهيل', 'قهوة تركية سادة', 'خلطة 3 في 1']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => prod = v!,
              decoration: const InputDecoration(labelText: 'الصنف', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية بالكيلو', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
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
            child: const Text('إرسال الطلب'),
          )
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// لوحة تحكم المدير الكاملة (Web Dashboard)
// ---------------------------------------------------------------------------
class AdminDashboardScreen extends StatefulWidget {
  final User user;
  const AdminDashboardScreen({super.key, required this.user});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة معمل ويك ويك - لوحة المدير'),
        backgroundColor: const Color(0xFF4A2C11),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedTab,
            onDestinationSelected: (i) => setState(() => _selectedTab = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.shopping_cart), label: Text('طلبات التوريد')),
              NavigationRailDestination(icon: Icon(Icons.people), label: Text('المقابلات')),
              NavigationRailDestination(icon: Icon(Icons.coffee), label: Text('أصناف المعمل')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _selectedTab == 0
                ? _buildOrdersTab()
                : _selectedTab == 1
                    ? _buildInterviewsTab()
                    : _buildProductsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final d = doc.data() as Map<String, dynamic>;
            return Card(
              child: ListTile(
                title: Text('${d['product']} - ${d['quantityKg']} كغ'),
                subtitle: Text('الموزع: ${d['distributorName']} | الحالة: ${d['status']}'),
                trailing: ElevatedButton(
                  onPressed: () {
                    doc.reference.update({
                      'status': 'جاهز للتسليم في المعمل',
                      'deliveryDate': 'اليوم 4:00 عصراً',
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

  Widget _buildInterviewsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final d = doc.data() as Map<String, dynamic>;
            return Card(
              child: ListTile(
                title: Text(d['name'] ?? ''),
                subtitle: Text('هاتف: ${d['phone']} | منطقة: ${d['area']} | وسيلة: ${d['transport']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => doc.reference.update({'status': 'accepted'})),
                    IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => doc.reference.update({'status': 'rejected'})),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProductsTab() {
    return const Center(child: Text('أصناف المعمل الحالية مفعلة ومربوطة مباشرة بخط الإنتاج.'));
  }
}
