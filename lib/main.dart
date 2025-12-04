import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart'; 
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; 
import 'chat_screen.dart';
import 'chat_list_screen.dart'; 
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';  

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// Observador para detectar cuando volvemos a la lista y recargarla
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **PERMITIR SSL INSEGURO SOLO PARA TEST**
  HttpOverrides.global = MyHttpOverrides();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // 1. Escucha links en segundo plano / app abierta
    _sub = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        print('--- LINK ENTRANDO: $uri ---');
        _processLink(uri);
      }
    }, onError: (err) {
      print('Error link stream: $err');
    });

    // 2. Escucha link inicial (App cerrada)
    try {
      final Uri? initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        print('--- LINK INICIAL: $initialUri ---');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _processLink(initialUri);
        });
      }
    } catch (e) {
      print('Error initial link: $e');
    }
  }

  void _processLink(Uri uri) async {
    if (uri.scheme == 'carisacourier' && uri.host == 'chat') {
      
      final String? idPedido = uri.queryParameters['id_pedido'];
      final String? miId = uri.queryParameters['mi_id'];
      final String? miTipo = uri.queryParameters['mi_tipo']; 
      final String? rolObjetivo = uri.queryParameters['rol_objetivo'] ?? uri.queryParameters['target_role']; 

      if (idPedido != null && miId != null && miTipo != null && rolObjetivo != null) {
        
        // GUARDAR SESIÓN LOCALMENTE
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

  Future<void> _abrirChat({
    required String idPedido,
    required String miId,
    required String miTipo,
    required String rolObjetivo, 
  }) async {
    
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Mostrar carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Construir URL
      final urlString =
        'http://test.dinsidescourier/dinsidescourier/buscar_o_crear_chat_por_pedido.php'
        '?id_pedido=$idPedido'
        '&rol_objetivo=$rolObjetivo'
        '&mi_id=$miId'
        '&mi_tipo=$miTipo';
      print("Consultando API: $urlString");
      
      final url = Uri.parse(urlString);
      final response = await http.get(url).timeout(const Duration(seconds: 60));

      // Cerrar carga
      if (navigatorKey.currentState?.canPop() == true) {
         navigatorKey.currentState?.pop(); 
      }

      if (response.statusCode == 200) {
        try {
            final jsonResponse = jsonDecode(response.body);
            
            if (jsonResponse['success'] == true) {
              final String idConversacion = jsonResponse['id_conversacion'].toString();
              
              // Navegar al Chat
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    idConversacion: idConversacion,
                    idPedido: idPedido,
                    miId: miId,
                    miTipo: miTipo,
                  ),
                ),
              );
            } else {
              _showError("El servidor rechazó la conexión:\n\n${jsonResponse['message']}");
            }
        } catch (e) {
            print("Respuesta del servidor: ${response.body}");
            _showError("Error al leer respuesta del servidor.");
        }
      } else {
        _showError("Error de conexión HTTP: ${response.statusCode}");
      }
    } catch (e) {
      if (navigatorKey.currentState?.canPop() == true) {
        navigatorKey.currentState?.pop();
      }
      _showError("Error de Red/App: $e");
    }
  }

  void _showError(String mensaje) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
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
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 1. CAMBIO DE TÍTULO
      title: 'Dinsides Chats',
      
      // 2. QUITAR ETIQUETA DEBUG
      debugShowCheckedModeBanner: false,
      
      navigatorKey: navigatorKey, 
      
      // 3. TEMA VISUAL AZUL (Forzado para que se vea bien en todas partes)
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white, // Texto e iconos blancos
          elevation: 2,
        ),
      ),
      
      navigatorObservers: [routeObserver],
      home: const ChatListScreen(), 
    );
  }
}