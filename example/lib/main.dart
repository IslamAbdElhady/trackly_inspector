import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:trackly_inspector/dio.dart';
import 'package:trackly_inspector/http.dart';
import 'package:trackly_inspector/shake.dart';
import 'package:trackly_inspector/trackly_inspector.dart';

final dio = Dio(
  BaseOptions(
    baseUrl: 'https://jsonplaceholder.typicode.com',
    connectTimeout: const Duration(seconds: 10),
    headers: {'Authorization': 'Bearer demo-token-123'},
  ),
)..interceptors.add(TracklyDioInterceptor());

final client = TracklyHttpClient();

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trackly Inspector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      builder:
          (context, child) =>
              TracklyInspector(child: TracklyShakeDetector(child: child!)),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static const _log = TracklyLogger('Demo');

  @override
  void initState() {
    super.initState();
    trackly.info('App started');
    _run(() => dio.get('/posts', queryParameters: {'_limit': 5}));
  }

  Future<void> _run(Future<Object?> Function() request) async {
    try {
      await request();
    } catch (error) {
      _log.warning('Request failed', error: error);
    }
  }

  void _fireAll() {
    trackly.info('Firing one of everything');
    for (final request in <Future<Object?> Function()>[
      () => dio.get('/posts', queryParameters: {'_limit': 10}),
      () => dio.post('/posts', data: {'title': 'Hello', 'userId': 1}),
      () => dio.patch('/posts/1', data: {'title': 'Patched'}),
      () => dio.delete('/posts/1'),
      () => dio.get('/posts/99999'),
      () => dio.get('https://httpbin.org/status/500'),
      () => dio.get(
        'https://httpbin.org/delay/5',
        options: Options(receiveTimeout: const Duration(seconds: 1)),
      ),
      () => dio.post(
        'https://httpbin.org/post',
        data: FormData.fromMap({
          'name': 'avatar',
          'file': MultipartFile.fromString('fake', filename: 'avatar.png'),
        }),
      ),
      () => client.post(
        Uri.parse('https://httpbin.org/post'),
        body: {'email': 'ali@example.com', 'remember': 'true'},
      ),
      () => client.get(Uri.parse('https://httpbin.org/image/png')),
      () => client.get(Uri.parse('https://no-such-host.trackly.invalid/api')),
    ]) {
      _run(request);
    }
    trackly.debug('Cache warmed', extra: {'items': 42});
    trackly.warning('Token expires in 5 minutes');
    try {
      throw const FormatException('Unexpected character at offset 12');
    } catch (e, st) {
      _log.error('Failed to parse settings', error: e, stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trackly Inspector Demo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          const _Hint(),
          const _LiveData(),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _fireAll,
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Fire one of everything'),
          ),
          _Section('Dio', [
            _Action(
              'GET list',
              () => dio.get('/posts', queryParameters: {'_limit': 10}),
            ),
            _Action('GET one', () => dio.get('/posts/1')),
            _Action(
              'POST JSON',
              () => dio.post(
                '/posts',
                data: {
                  'title': 'Hello',
                  'body': 'Sent from Trackly Inspector',
                  'userId': 1,
                  'tags': ['flutter', 'dio'],
                },
              ),
            ),
            _Action(
              'PUT',
              () => dio.put('/posts/1', data: {'id': 1, 'title': 'Updated'}),
            ),
            _Action(
              'PATCH',
              () => dio.patch('/posts/1', data: {'title': 'Patched'}),
            ),
            _Action('DELETE', () => dio.delete('/posts/1')),
            _Action('404', () => dio.get('/posts/99999')),
            _Action('500', () => dio.get('https://httpbin.org/status/500')),
            _Action(
              'Timeout',
              () => dio.get(
                'https://httpbin.org/delay/5',
                options: Options(receiveTimeout: const Duration(seconds: 1)),
              ),
            ),
            _Action(
              'Upload',
              () => dio.post(
                'https://httpbin.org/post',
                data: FormData.fromMap({
                  'name': 'avatar',
                  'file': MultipartFile.fromString(
                    'fake image bytes',
                    filename: 'avatar.png',
                  ),
                }),
              ),
            ),
          ], onPressed: _run),
          _Section('http', [
            _Action(
              'GET user',
              () => client.get(
                Uri.parse('https://jsonplaceholder.typicode.com/users/1'),
              ),
            ),
            _Action(
              'POST form',
              () => client.post(
                Uri.parse('https://httpbin.org/post'),
                body: {'email': 'ali@example.com', 'remember': 'true'},
              ),
            ),
            _Action(
              'Image',
              () => client.get(Uri.parse('https://httpbin.org/image/png')),
            ),
            _Action(
              'Bad host',
              () => client.get(
                Uri.parse('https://no-such-host.trackly.invalid/api'),
              ),
            ),
            _Action(
              'Burst ×5',
              () => Future.wait([
                for (var i = 1; i <= 5; i++)
                  client.get(
                    Uri.parse(
                      'https://jsonplaceholder.typicode.com/comments/$i',
                    ),
                  ),
              ]),
            ),
          ], onPressed: _run),
          _Section('Logs', [
            _Action(
              'debug',
              () async => trackly.debug('Cache warmed', extra: {'items': 42}),
            ),
            _Action('info', () async => _log.info('User opened the demo')),
            _Action('success', () async => trackly.success('Profile saved')),
            _Action(
              'warning',
              () async => trackly.warning('Token expires in 5 minutes'),
            ),
            _Action('error', () async {
              try {
                throw const FormatException(
                  'Unexpected character at offset 12',
                );
              } catch (e, st) {
                _log.error(
                  'Failed to parse settings',
                  error: e,
                  stackTrace: st,
                );
              }
              return null;
            }),
          ], onPressed: _run),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: TracklyInspector.show,
            icon: const Icon(Icons.radar_rounded),
            label: const Text('Open inspector from code'),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Tap the floating bubble to see every request. Long-press it, '
          'then touch any name, price, or picture below to find the '
          'request it came from.',
        ),
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.request);

  final String label;
  final Future<Object?> Function() request;
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.actions, {required this.onPressed});

  final String title;
  final List<_Action> actions;
  final Future<void> Function(Future<Object?> Function()) onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in actions)
                OutlinedButton(
                  onPressed: () => onPressed(action.request),
                  child: Text(action.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Data loaded from a real API, to try inspect mode on.
class _LiveData extends StatefulWidget {
  const _LiveData();

  @override
  State<_LiveData> createState() => _LiveDataState();
}

class _LiveDataState extends State<_LiveData> {
  Map<String, dynamic>? _user;
  List<dynamic> _products = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final responses = await Future.wait([
        dio.get<Map<String, dynamic>>('https://dummyjson.com/users/1'),
        dio.get<Map<String, dynamic>>(
          'https://dummyjson.com/products',
          queryParameters: {
            'limit': 3,
            'select': 'title,price,rating,thumbnail',
          },
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _user = responses[0].data;
        _products = responses[1].data?['products'] as List<dynamic>? ?? [];
      });
    } catch (error) {
      trackly.warning('Could not load the demo data', error: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final company = user['company'] as Map<String, dynamic>;
    final address = user['address'] as Map<String, dynamic>;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundImage: NetworkImage(user['image'] as String),
            ),
            title: Text(
              '${user['firstName']} ${user['lastName']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${company['title']} · ${user['email']}'),
            trailing: Text(address['city'] as String),
          ),
          const Divider(height: 1),
          for (final product in _products.cast<Map<String, dynamic>>())
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  product['thumbnail'] as String,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(product['title'] as String),
              subtitle: Text('Rating ${product['rating']}'),
              trailing: Text(
                'EGP ${(product['price'] as num).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
