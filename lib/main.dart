import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


import 'firebase_options.dart';
import 'chat_screen.dart';
import 'chat_list_screen.dart';
import 'location_service.dart'; // 🔥 IMPORTANTE

// ===================================================
// SSL INSEGURO (SOLO TEST)
// ===================================================
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  HttpOverrides.global = MyHttpOverrides();

  // 🔹 Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔹 CREAR CANAL DE NOTIFICACIÓN (OBLIGATORIO)
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'location_channel', // 🔴 MISMO ID QUE USAS EN LocationService
    'Location Service',
    description: 'Servicio de ubicación en segundo plano',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // 🔹 INICIALIZAR BACKGROUND SERVICE (SOLO CONFIGURA, NO ARRANCA)
  await initializeService();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ===================================================
  // DEEP LINKS
  // ===================================================
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    _sub = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _processLink(uri);
      }
    }, onError: (err) {
      debugPrint("Error link stream: $err");
    });

    try {
      final Uri? initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _processLink(initialUri);
        });
      }
    } catch (e) {
      debugPrint("Error initial link: $e");
    }
  }

  void _processLink(Uri uri) async {
    if (uri.scheme == 'carisacourier' && uri.host == 'chat') {
      final idPedido = uri.queryParameters['id_pedido'];
      final miId = uri.queryParameters['mi_id'];
      final miTipo = uri.queryParameters['mi_tipo'];
      final rolObjetivo =
          uri.queryParameters['rol_objetivo'] ??
          uri.queryParameters['target_role'];

      if (idPedido != null &&
          miId != null &&
          miTipo != null &&
          rolObjetivo != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('mi_id', miId);
        await prefs.setString('mi_tipo', miTipo);

        _abrirChat(
          idPedido: idPedido,
          miId: miId,
          miTipo: miTipo,
          rolObjetivo: rolObjetivo,
        );
      }
    }
  }

  // ===================================================
  // ABRIR CHAT
  // ===================================================
  Future<void> _abrirChat({
    required String idPedido,
    required String miId,
    required String miTipo,
    required String rolObjetivo,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final url = Uri.parse(
        'https://test.dinsidescourier.com/buscar_o_crear_chat_por_pedido.php'
        '?id_pedido=$idPedido'
        '&rol_objetivo=$rolObjetivo'
        '&mi_id=$miId'
        '&mi_tipo=$miTipo',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 60));

      if (navigatorKey.currentState?.canPop() == true) {
        navigatorKey.currentState?.pop();
      }

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        if (jsonResponse['success'] == true) {
          final idConversacion =
              jsonResponse['id_conversacion'].toString();

          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                idConversacion: idConversacion,
                idPedido: idPedido,
                miId: miId,
                miTipo: miTipo,
              ),
            ),
          );
        } else {
          _showError(jsonResponse['message']);
        }
      } else {
        _showError("Error HTTP ${response.statusCode}");
      }
    } catch (e) {
      if (navigatorKey.currentState?.canPop() == true) {
        navigatorKey.currentState?.pop();
      }
      _showError("Error de red: $e");
    }
  }

  void _showError(String mensaje) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dinsides Chats',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      home: const ChatListScreen(),
    );
  }
}
